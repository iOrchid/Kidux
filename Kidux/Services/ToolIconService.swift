import Foundation
import AppKit

/// 解析并缓存软件图标：Catalog URL → 本机 → 远程元数据 → Caskroom 磁盘 → App Store。
/// **绝不**为图标拉起 `brew info` 子进程（曾与 Discover 热门并发叠加导致整机假死风险）。
actor ToolIconService {
    static let shared = ToolIconService()

    /// 未命中缓存时的解析并发上限（远程 API / 读盘），避免热门卡同时打爆网络与主线程压力。
    private static let iconFetchConcurrencyLimit = 4
    /// 详情页 homepage 等非图标路径仍可能用 brew；严格串行。
    private static let brewInfoConcurrencyLimit = 1

    private let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private var homepageCache: [String: String] = [:]
    private var localAppIndex: [String: String]?
    /// 默认关闭：枚举 /Applications + 读图标会触发「访问其他 App 数据」。仅在已安装页主动扫描后开启。
    private var localAppIconLookupEnabled = false
    private let diskCacheDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kidux/IconCache", isDirectory: true)
    }()
    private let shell = ShellExecutor()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()
    private var iconFetchInFlight = 0
    private var iconFetchWaiters: [CheckedContinuation<Void, Never>] = []
    private var brewInfoInFlight = 0
    private var brewInfoWaiters: [CheckedContinuation<Void, Never>] = []

    private var allowsRemoteNetwork: Bool {
        !UserDefaults.standard.bool(forKey: "settings.offlineMode")
    }

    func icon(for tool: DevTool) async -> NSImage {
        if let cached = memoryCache.object(forKey: tool.id as NSString) {
            return cached
        }

        if let disk = loadFromDiskCache(toolID: tool.id) {
            memoryCache.setObject(disk, forKey: tool.id as NSString)
            return disk
        }

        await acquireIconFetchSlot()
        defer { releaseIconFetchSlot() }

        // 排队期间可能已被其它任务写入
        if let cached = memoryCache.object(forKey: tool.id as NSString) {
            return cached
        }
        if let disk = loadFromDiskCache(toolID: tool.id) {
            memoryCache.setObject(disk, forKey: tool.id as NSString)
            return disk
        }

        let started = Date()
        DiagnosticsEventLog.record("icon.start", fields: [
            "toolID": tool.id,
            "source": tool.source.type.rawValue,
            "iconInFlight": "\(iconFetchInFlight)"
        ])

        let resolved: NSImage
        let sourceTag: String
        if let override = IconOverrideRegistry.url(for: tool),
           allowsRemoteNetwork,
           let image = await loadImage(from: override, minPixelSize: 64) {
            resolved = image
            sourceTag = "override"
        } else if let local = await iconFromLocalApplications(tool) {
            resolved = local
            sourceTag = "localApp"
        } else if allowsRemoteNetwork, let url = tool.iconURL, let image = await loadImage(from: url, minPixelSize: 48) {
            resolved = image
            sourceTag = "catalogURL"
        } else if allowsRemoteNetwork, let remote = await iconFromRemoteBrewMetadata(tool) {
            resolved = remote
            sourceTag = "remoteBrew"
        } else if localAppIconLookupEnabled,
                  tool.source.type == .cask,
                  let cask = await iconFromCaskDiskOnly(tool.source.identifier) {
            // 仅在用户已主动扫本机 App 后读 Caskroom/.app 图标，避免首启 TCC 弹窗
            resolved = cask
            sourceTag = "caskroom"
        } else if allowsRemoteNetwork, tool.source.type == .mas, let mas = await iconFromMAS(appID: tool.source.identifier) {
            resolved = mas
            sourceTag = "mas"
        } else {
            resolved = placeholder(for: tool)
            sourceTag = "placeholder"
        }

        memoryCache.setObject(resolved, forKey: tool.id as NSString)
        saveToDiskCache(toolID: tool.id, image: resolved)
        DiagnosticsEventLog.record(
            sourceTag == "placeholder" ? "icon.miss" : "icon.ok",
            durationMs: Date().timeIntervalSince(started) * 1000,
            fields: [
                "toolID": tool.id,
                "via": sourceTag,
                "iconInFlight": "\(iconFetchInFlight)"
            ]
        )
        return resolved
    }

    func setLocalAppIconLookupEnabled(_ enabled: Bool) {
        localAppIconLookupEnabled = enabled
        if !enabled {
            localAppIndex = nil
        }
    }

    func clearDiskCache() {
        memoryCache.removeAllObjects()
        localAppIndex = nil
        try? FileManager.default.removeItem(at: diskCacheDirectory)
    }

    func homepage(for tool: DevTool) async -> String? {
        if let homepage = tool.homepage { return homepage }
        let key = metadataKey(for: tool)
        if let cached = homepageCache[key] { return cached }
        if let fetched = await fetchBrewHomepage(for: tool) {
            homepageCache[key] = fetched
            return fetched
        }
        if tool.source.type == .link {
            return tool.source.identifier
        }
        return nil
    }

    func preload(tools: [DevTool]) async {
        // 只预热首屏附近；具体并发由 iconFetch 槽位限制
        await withTaskGroup(of: Void.self) { group in
            for tool in tools.prefix(12) {
                group.addTask { _ = await self.icon(for: tool) }
            }
        }
    }

    // MARK: - Disk cache

    private func diskCacheFile(for toolID: String) -> URL {
        let safe = toolID.replacingOccurrences(of: "/", with: "_")
        return diskCacheDirectory.appendingPathComponent("\(safe).png")
    }

    private func loadFromDiskCache(toolID: String) -> NSImage? {
        let file = diskCacheFile(for: toolID)
        guard FileManager.default.fileExists(atPath: file.path),
              let image = NSImage(contentsOf: file) else { return nil }
        return image
    }

    private func saveToDiskCache(toolID: String, image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
        try? png.write(to: diskCacheFile(for: toolID))
    }

    // MARK: - Remote icons（优先，避免 brew info）

    private func iconFromRemoteBrewMetadata(_ tool: DevTool) async -> NSImage? {
        guard let homepage = await fetchRemoteBrewHomepage(for: tool) ?? tool.homepage else { return nil }
        homepageCache[metadataKey(for: tool)] = homepage
        if let override = iconURLCandidate(for: tool, homepage: homepage) {
            return await loadImage(from: override)
        }
        guard let domain = domain(from: homepage) else { return nil }
        if domain == "github.com" {
            return nil
        }
        return await loadImage(from: "https://icon.horse/icon/\(domain)")
    }

    private func iconURLCandidate(for tool: DevTool, homepage: String) -> String? {
        if let override = IconOverrideRegistry.url(for: tool) { return override }
        guard let domain = domain(from: homepage), domain != "github.com" else { return nil }
        return "https://icon.horse/icon/\(domain)"
    }

    private func fetchBrewHomepage(for tool: DevTool) async -> String? {
        if let remote = await fetchRemoteBrewHomepage(for: tool) {
            return remote
        }
        return await fetchLocalBrewHomepage(for: tool)
    }

    private func fetchRemoteBrewHomepage(for tool: DevTool) async -> String? {
        let apiURL: URL?
        switch tool.source.type {
        case .formula:
            apiURL = URL(string: "https://formulae.brew.sh/api/formula/\(tool.source.identifier).json")
        case .cask:
            apiURL = URL(string: "https://formulae.brew.sh/api/cask/\(tool.source.identifier).json")
        case .link:
            return tool.source.identifier.hasPrefix("http") ? tool.source.identifier : nil
        default:
            return nil
        }

        guard let apiURL else { return nil }
        guard allowsRemoteNetwork else { return nil }
        do {
            let (data, _) = try await session.data(from: apiURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let homepage = json["homepage"] as? String else { return nil }
            return homepage
        } catch {
            return nil
        }
    }

    private func fetchLocalBrewHomepage(for tool: DevTool) async -> String? {
        let brew = brewExecutable()
        let flag: String
        switch tool.source.type {
        case .formula: flag = "--formula"
        case .cask: flag = "--cask"
        default: return nil
        }

        return await withBrewInfoSlot(toolID: tool.id) {
            await BrewSessionCoordinator.shared.withExclusive {
                guard let result = try? await self.shell.run(
                    "\(brew) info \(flag) \(tool.source.identifier) --json=v2 2>/dev/null"
                ), result.isSuccess,
                    let data = result.stdout.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }

                let key = tool.source.type == .formula ? "formulae" : "casks"
                if let items = json[key] as? [[String: Any]], let first = items.first {
                    return first["homepage"] as? String
                }
                if let items = json as? [[String: Any]], let first = items.first {
                    return first["homepage"] as? String
                }
                return nil
            }
        }
    }

    private func loadImage(from urlString: String, minPixelSize: CGFloat = 32) async -> NSImage? {
        guard allowsRemoteNetwork else { return nil }
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let image = NSImage(data: data) else { return nil }
            let maxDim = max(image.size.width, image.size.height)
            if maxDim < minPixelSize { return nil }
            return image
        } catch {
            return nil
        }
    }

    private func domain(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func metadataKey(for tool: DevTool) -> String {
        "\(tool.source.type.rawValue):\(tool.source.identifier)"
    }

    // MARK: - Local apps

    private func iconFromLocalApplications(_ tool: DevTool) async -> NSImage? {
        guard localAppIconLookupEnabled else { return nil }
        let index = localApplicationsIndex()
        for candidate in appNameCandidates(for: tool) {
            if let path = index[candidate.lowercased()] {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        return nil
    }

    private func localApplicationsIndex() -> [String: String] {
        if let localAppIndex { return localAppIndex }
        var index: [String: String] = [:]
        let paths = [
            "/Applications",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        for base in paths {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appName = entry.replacingOccurrences(of: ".app", with: "")
                let path = (base as NSString).appendingPathComponent(entry)
                index[appName.lowercased()] = path
            }
        }
        localAppIndex = index
        return index
    }

    private func appNameCandidates(for tool: DevTool) -> [String] {
        var names = [tool.name]
        names.append(tool.id.replacingOccurrences(of: "-", with: " "))
        if tool.source.type == .cask {
            names.append(tool.source.identifier.replacingOccurrences(of: "-", with: " "))
        }
        return names
    }

    // MARK: - Homebrew Cask

    /// 不调用 brew：直接扫 Caskroom 目录。
    private func iconFromCaskDiskOnly(_ caskName: String) async -> NSImage? {
        for prefix in caskroomPrefixes() {
            let caskDir = (prefix as NSString).appendingPathComponent(caskName)
            guard let versions = try? FileManager.default.contentsOfDirectory(atPath: caskDir) else { continue }
            for version in versions {
                let versionDir = (caskDir as NSString).appendingPathComponent(version)
                guard let apps = try? FileManager.default.contentsOfDirectory(atPath: versionDir) else { continue }
                if let app = apps.first(where: { $0.hasSuffix(".app") }) {
                    return NSWorkspace.shared.icon(forFile: (versionDir as NSString).appendingPathComponent(app))
                }
            }
        }
        return nil
    }

    private func caskroomPrefixes() -> [String] {
        ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
    }

    private func brewExecutable() -> String {
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin/brew"
        }
        return "brew"
    }

    // MARK: - 并发限流（图标解析 / 非图标 brew info）

    private func acquireIconFetchSlot() async {
        if iconFetchInFlight < Self.iconFetchConcurrencyLimit {
            iconFetchInFlight += 1
            return
        }
        await withCheckedContinuation { continuation in
            iconFetchWaiters.append(continuation)
        }
    }

    private func releaseIconFetchSlot() {
        if !iconFetchWaiters.isEmpty {
            let next = iconFetchWaiters.removeFirst()
            next.resume()
            return
        }
        iconFetchInFlight = max(0, iconFetchInFlight - 1)
    }

    /// 仅供 homepage 等非列表路径；图标解析禁止走此路径。
    private func withBrewInfoSlot<T>(toolID: String, _ work: () async -> T) async -> T {
        await acquireBrewInfoSlot()
        let started = Date()
        DiagnosticsEventLog.record("icon.brew_info.start", fields: [
            "toolID": toolID,
            "brewInFlight": "\(brewInfoInFlight)",
            "purpose": "homepage"
        ])
        defer {
            DiagnosticsEventLog.record(
                "icon.brew_info.done",
                durationMs: Date().timeIntervalSince(started) * 1000,
                fields: [
                    "toolID": toolID,
                    "brewInFlight": "\(brewInfoInFlight)",
                    "purpose": "homepage"
                ]
            )
            releaseBrewInfoSlot()
        }
        return await work()
    }

    private func acquireBrewInfoSlot() async {
        if brewInfoInFlight < Self.brewInfoConcurrencyLimit {
            brewInfoInFlight += 1
            return
        }
        await withCheckedContinuation { continuation in
            brewInfoWaiters.append(continuation)
        }
    }

    private func releaseBrewInfoSlot() {
        if !brewInfoWaiters.isEmpty {
            let next = brewInfoWaiters.removeFirst()
            next.resume()
            return
        }
        brewInfoInFlight = max(0, brewInfoInFlight - 1)
    }

    // MARK: - Mac App Store

    private func iconFromMAS(appID: String) async -> NSImage? {
        guard let id = Int(appID), id > 0 else { return nil }
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)") else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let artwork = first["artworkUrl512"] as? String ?? first["artworkUrl100"] as? String
            else { return nil }
            return await loadImage(from: artwork)
        } catch {
            return nil
        }
    }

    // MARK: - Placeholder

    private func placeholder(for tool: DevTool) -> NSImage {
        let size: CGFloat = 128
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        categoryColor(for: tool.category).setFill()
        NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()

        let initial = String(tool.name.prefix(1)).uppercased()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.42, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: initial, attributes: attrs)
        let strSize = str.size()
        str.draw(at: NSPoint(x: (size - strSize.width) / 2, y: (size - strSize.height) / 2))

        image.unlockFocus()
        return image
    }

    private func categoryColor(for category: String) -> NSColor {
        ToolCategoryTheme.nsColor(for: category)
    }
}

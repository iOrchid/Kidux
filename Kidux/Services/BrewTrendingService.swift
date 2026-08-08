import Foundation

struct BrewTrendingItem: Identifiable, Sendable, Hashable, Codable {
    let name: String
    let sourceType: InstallSourceType
    let installCount: Int
    /// count30 / (count365 / 12)，后台 enrich 后填充
    let velocity: Double?

    var id: String { "\(sourceType.rawValue):\(name)" }

    var asDevTool: DevTool {
        BrewSearchResult(name: name, sourceType: sourceType).asDevTool
    }

    func withVelocity(_ velocity: Double?) -> BrewTrendingItem {
        BrewTrendingItem(
            name: name,
            sourceType: sourceType,
            installCount: installCount,
            velocity: velocity
        )
    }
}

enum BrewTrendingFetchResult: Sendable {
    case success(items: [BrewTrendingItem], source: String)
    case failure(String)
}

/// Homebrew analytics 热门包：磁盘缓存优先（stale-while-revalidate），网络单飞行 + 可取消 + 失败快停。
enum BrewTrendingService {
    static let topLimit = 20
    static let memoryFreshTTL: TimeInterval = 3600
    static let diskMaxAge: TimeInterval = 7 * 24 * 3600
    static let minUsefulBodyBytes = 20_000
    static let requestTimeout: TimeInterval = 8
    static let resourceTimeout: TimeInterval = 10
    static let velocityCacheTTL: TimeInterval = 3600

    private static let store = TrendingStore()
    private static let network = TrendingNetworkGate()

    // MARK: - Public

    static func cachedItems(windowDays: TrendingWindowDays) async -> [BrewTrendingItem]? {
        await store.items(windowDays: windowDays, maxAge: diskMaxAge)
    }

    static func isMemoryFresh(windowDays: TrendingWindowDays) async -> Bool {
        await store.isFresh(windowDays: windowDays, ttl: memoryFreshTTL)
    }

    static func cancelInFlightNetwork() async {
        await network.cancelAll()
        DiagnosticsEventLog.record("trending.network.cancel_all")
    }

    static func fetchTrending(
        windowDays: TrendingWindowDays,
        force: Bool = false
    ) async -> BrewTrendingFetchResult {
        if Task.isCancelled { return .failure("已取消") }

        let offline = await MainActor.run { AppSettings.shared.offlineMode }
        if offline {
            if let cached = await store.items(windowDays: windowDays, maxAge: diskMaxAge) {
                DiagnosticsEventLog.record("trending.cache.hit", fields: [
                    "windowDays": "\(windowDays.rawValue)",
                    "source": "offlineDisk",
                    "itemCount": "\(cached.count)"
                ])
                return .success(items: cached, source: "offlineDisk")
            }
            return .failure("离线模式已开启，且无本地热门缓存")
        }

        if !force,
           await store.isFresh(windowDays: windowDays, ttl: memoryFreshTTL),
           let cached = await store.items(windowDays: windowDays, maxAge: memoryFreshTTL) {
            DiagnosticsEventLog.record("trending.cache.hit", fields: [
                "windowDays": "\(windowDays.rawValue)",
                "source": "memoryFresh",
                "itemCount": "\(cached.count)"
            ])
            return .success(items: cached, source: "memoryFresh")
        }

        let started = Date()
        do {
            let downloaded = try await network.runFetch {
                try await Self.downloadMergedTopN(windowDays: windowDays)
            }
            if Task.isCancelled { return .failure("已取消") }
            await store.store(downloaded.items, windowDays: windowDays)
            DiagnosticsEventLog.record(
                "trending.fetch.http",
                durationMs: Date().timeIntervalSince(started) * 1000,
                fields: [
                    "windowDays": "\(windowDays.rawValue)",
                    "source": "network",
                    "itemCount": "\(downloaded.items.count)",
                    "bytes": "\(downloaded.bytes)",
                    "parseMs": "\(Int(downloaded.parseMs.rounded()))"
                ]
            )
            return .success(items: downloaded.items, source: "network")
        } catch is CancellationError {
            return .failure("已取消")
        } catch let error as TrendingNetworkError {
            DiagnosticsEventLog.record(
                "trending.fetch.fail_fast",
                durationMs: Date().timeIntervalSince(started) * 1000,
                fields: [
                    "windowDays": "\(windowDays.rawValue)",
                    "message": error.message,
                    "bytes": "\(error.bytes)"
                ]
            )
            if let cached = await store.items(windowDays: windowDays, maxAge: diskMaxAge) {
                DiagnosticsEventLog.record("trending.cache.fallback", fields: [
                    "windowDays": "\(windowDays.rawValue)",
                    "itemCount": "\(cached.count)"
                ])
                return .success(items: cached, source: "diskFallback")
            }
            return .failure(error.message)
        } catch {
            DiagnosticsEventLog.record(
                "trending.fetch.fail_fast",
                durationMs: Date().timeIntervalSince(started) * 1000,
                fields: [
                    "windowDays": "\(windowDays.rawValue)",
                    "message": error.localizedDescription,
                    "bytes": "0"
                ]
            )
            if let cached = await store.items(windowDays: windowDays, maxAge: diskMaxAge) {
                return .success(items: cached, source: "diskFallback")
            }
            return .failure(error.localizedDescription)
        }
    }

    static func enrichVelocity(
        items: [BrewTrendingItem],
        windowDays: TrendingWindowDays,
        force: Bool = false
    ) async -> [BrewTrendingItem] {
        guard !items.isEmpty else { return items }
        if Task.isCancelled { return items }
        if await MainActor.run(body: { AppSettings.shared.offlineMode }) {
            return items
        }

        let maps: (month: [String: Int], year: [String: Int])
        if let cached = await store.velocityMaps(force: force) {
            maps = cached
        } else {
            do {
                maps = try await network.runEnrich {
                    async let monthFormulae = fetchCounts(
                        url: analyticsURL(sourceType: .formula, segment: TrendingWindowDays.days30.analyticsSegment),
                        sourceType: .formula,
                        neededNames: Set(items.filter { $0.sourceType == .formula }.map(\.name))
                    )
                    async let monthCasks = fetchCounts(
                        url: analyticsURL(sourceType: .cask, segment: TrendingWindowDays.days30.analyticsSegment),
                        sourceType: .cask,
                        neededNames: Set(items.filter { $0.sourceType == .cask }.map(\.name))
                    )
                    async let yearFormulae = fetchCounts(
                        url: analyticsURL(sourceType: .formula, segment: TrendingWindowDays.days365.analyticsSegment),
                        sourceType: .formula,
                        neededNames: Set(items.filter { $0.sourceType == .formula }.map(\.name))
                    )
                    async let yearCasks = fetchCounts(
                        url: analyticsURL(sourceType: .cask, segment: TrendingWindowDays.days365.analyticsSegment),
                        sourceType: .cask,
                        neededNames: Set(items.filter { $0.sourceType == .cask }.map(\.name))
                    )
                    if Task.isCancelled { throw CancellationError() }
                    let month = await monthFormulae.merging(monthCasks) { _, new in new }
                    let year = await yearFormulae.merging(yearCasks) { _, new in new }
                    return (month: month, year: year)
                }
                await store.storeVelocity(month: maps.month, year: maps.year)
            } catch {
                return items
            }
        }

        return items.map { item in
            let count30 = maps.month[item.id] ?? (windowDays == .days30 ? item.installCount : 0)
            let count365 = maps.year[item.id] ?? 0
            return item.withVelocity(velocityScore(count30: count30, count365: count365))
        }
    }

    // MARK: - Download

    private struct DownloadResult: Sendable {
        var items: [BrewTrendingItem]
        var bytes: Int
        var parseMs: Double
    }

    private static func downloadMergedTopN(windowDays: TrendingWindowDays) async throws -> DownloadResult {
        async let windowFormulae = fetchTopItemsOrEmpty(
            url: analyticsURL(sourceType: .formula, segment: windowDays.analyticsSegment),
            sourceType: .formula,
            limit: topLimit
        )
        async let windowCasks = fetchTopItemsOrEmpty(
            url: analyticsURL(sourceType: .cask, segment: windowDays.analyticsSegment),
            sourceType: .cask,
            limit: topLimit
        )
        let (formulae, casks) = await (windowFormulae, windowCasks)
        if Task.isCancelled { throw CancellationError() }

        let windowItems = formulae.items + casks.items
        let bytes = formulae.bytes + casks.bytes
        let parseMs = formulae.parseMs + casks.parseMs
        guard !windowItems.isEmpty else {
            throw TrendingNetworkError(message: "无法加载热门数据（空结果或接口异常）", bytes: bytes)
        }
        let merged = Array(
            windowItems
                .sorted { $0.installCount > $1.installCount }
                .prefix(topLimit)
        )
        return DownloadResult(items: merged, bytes: bytes, parseMs: parseMs)
    }

    private static func analyticsURL(sourceType: InstallSourceType, segment: String) -> URL {
        switch sourceType {
        case .formula:
            // Install-on-request：用户主动安装（非依赖带入）
            return URL(string: "https://formulae.brew.sh/api/analytics/install-on-request/\(segment).json")!
        case .cask:
            // 官方 API 为 cask-install（无 cask/install-on-request，该路径 404）
            return URL(string: "https://formulae.brew.sh/api/analytics/cask-install/\(segment).json")!
        default:
            return URL(string: "https://formulae.brew.sh/api/analytics/install-on-request/\(segment).json")!
        }
    }

    private static func velocityScore(count30: Int, count365: Int) -> Double? {
        guard count30 > 0, count365 > 0 else { return nil }
        let monthlyAverage = max(Double(count365) / 12.0, 1.0)
        return Double(count30) / monthlyAverage
    }

    private static func fetchTopItems(
        url: URL,
        sourceType: InstallSourceType,
        limit: Int
    ) async throws -> (items: [BrewTrendingItem], bytes: Int, parseMs: Double) {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        let (data, response) = try await network.data(for: request)
        if Task.isCancelled { throw CancellationError() }

        let bytes = data.count
        guard let http = response as? HTTPURLResponse else {
            throw TrendingNetworkError(message: "无效响应", bytes: bytes)
        }
        guard (200...299).contains(http.statusCode) else {
            throw TrendingNetworkError(message: "HTTP \(http.statusCode)", bytes: bytes)
        }
        guard bytes >= minUsefulBodyBytes else {
            throw TrendingNetworkError(message: "响应过小（疑似错误页）", bytes: bytes)
        }

        let parseStarted = Date()
        let items = try await Task.detached(priority: .utility) {
            TopNAnalyticsParser.topItems(from: data, sourceType: sourceType, limit: limit)
        }.value
        let parseMs = Date().timeIntervalSince(parseStarted) * 1000
        if items.isEmpty {
            throw TrendingNetworkError(message: "解析后无条目", bytes: bytes)
        }
        return (items, bytes, parseMs)
    }

    /// 单侧失败不拖垮整次加载（另一侧仍可用）。
    private static func fetchTopItemsOrEmpty(
        url: URL,
        sourceType: InstallSourceType,
        limit: Int
    ) async -> (items: [BrewTrendingItem], bytes: Int, parseMs: Double) {
        do {
            return try await fetchTopItems(url: url, sourceType: sourceType, limit: limit)
        } catch is CancellationError {
            return ([], 0, 0)
        } catch {
            DiagnosticsEventLog.record("trending.fetch.side_fail", fields: [
                "sourceType": sourceType.rawValue,
                "message": (error as? TrendingNetworkError)?.message ?? error.localizedDescription
            ])
            return ([], (error as? TrendingNetworkError)?.bytes ?? 0, 0)
        }
    }

    private static func fetchCounts(
        url: URL,
        sourceType: InstallSourceType,
        neededNames: Set<String>
    ) async -> [String: Int] {
        guard !neededNames.isEmpty else { return [:] }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = requestTimeout
            let (data, response) = try await network.data(for: request)
            if Task.isCancelled { return [:] }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return [:]
            }
            guard data.count >= minUsefulBodyBytes else { return [:] }
            return try await Task.detached(priority: .utility) {
                TopNAnalyticsParser.counts(
                    from: data,
                    sourceType: sourceType,
                    neededNames: neededNames
                )
            }.value
        } catch {
            return [:]
        }
    }
}

// MARK: - Network gate

private struct TrendingNetworkError: Error {
    var message: String
    var bytes: Int
}

private actor TrendingNetworkGate {
    private var session: URLSession
    private var generation = 0
    private var fetchBusy = false

    init() {
        session = Self.makeSession()
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }

    func cancelAll() {
        generation += 1
        session.invalidateAndCancel()
        session = Self.makeSession()
        fetchBusy = false
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let gen = generation
        let (data, response) = try await session.data(for: request)
        guard gen == generation else { throw CancellationError() }
        if Task.isCancelled { throw CancellationError() }
        return (data, response)
    }

    func runFetch<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        if fetchBusy {
            cancelAll()
        }
        fetchBusy = true
        defer { fetchBusy = false }
        let gen = generation
        let value = try await work()
        guard gen == generation else { throw CancellationError() }
        return value
    }

    /// enrich 不抢占主 fetch；忙则直接跳过。
    func runEnrich<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        guard !fetchBusy else { throw TrendingNetworkError(message: "busy", bytes: 0) }
        fetchBusy = true
        defer { fetchBusy = false }
        let gen = generation
        let value = try await work()
        guard gen == generation else { throw CancellationError() }
        return value
    }
}

// MARK: - Memory + disk store

private actor TrendingStore {
    struct Entry: Codable {
        var items: [BrewTrendingItem]
        var cachedAt: Date
    }

    private var entries: [Int: Entry] = [:]
    private var monthCounts: [String: Int]?
    private var yearCounts: [String: Int]?
    private var velocityCachedAt: Date?
    private var diskLoaded = false

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kidux/TrendingCache", isDirectory: true)
    }

    private func fileURL(windowDays: Int) -> URL {
        directory.appendingPathComponent("trending-\(windowDays).json")
    }

    private func ensureDiskLoaded() {
        guard !diskLoaded else { return }
        diskLoaded = true
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for window in TrendingWindowDays.allCases {
            let url = fileURL(windowDays: window.rawValue)
            guard let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data) else { continue }
            if entries[window.rawValue] == nil {
                entries[window.rawValue] = entry
            }
        }
    }

    func items(windowDays: TrendingWindowDays, maxAge: TimeInterval) -> [BrewTrendingItem]? {
        ensureDiskLoaded()
        guard let entry = entries[windowDays.rawValue] else { return nil }
        guard Date().timeIntervalSince(entry.cachedAt) <= maxAge else { return nil }
        guard !entry.items.isEmpty else { return nil }
        return entry.items
    }

    func isFresh(windowDays: TrendingWindowDays, ttl: TimeInterval) -> Bool {
        ensureDiskLoaded()
        guard let entry = entries[windowDays.rawValue] else { return false }
        return Date().timeIntervalSince(entry.cachedAt) < ttl && !entry.items.isEmpty
    }

    func store(_ items: [BrewTrendingItem], windowDays: TrendingWindowDays) {
        ensureDiskLoaded()
        let entry = Entry(items: items, cachedAt: Date())
        entries[windowDays.rawValue] = entry
        let url = fileURL(windowDays: windowDays.rawValue)
        if let data = try? JSONEncoder().encode(entry) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    func velocityMaps(force: Bool) -> (month: [String: Int], year: [String: Int])? {
        guard !force,
              let monthCounts,
              let yearCounts,
              let velocityCachedAt,
              Date().timeIntervalSince(velocityCachedAt) < BrewTrendingService.velocityCacheTTL else {
            return nil
        }
        return (monthCounts, yearCounts)
    }

    func storeVelocity(month: [String: Int], year: [String: Int]) {
        monthCounts = month
        yearCounts = year
        velocityCachedAt = Date()
    }
}

// MARK: - Top-N JSON parser

private enum TopNAnalyticsParser {
    static func topItems(
        from data: Data,
        sourceType: InstallSourceType,
        limit: Int
    ) -> [BrewTrendingItem] {
        guard limit > 0 else { return [] }
        let nameKey = nameKey(for: sourceType)
        var result: [BrewTrendingItem] = []
        result.reserveCapacity(limit)

        forEachItemObject(in: data) { objectData in
            guard result.count < limit else { return false }
            guard let obj = try? JSONSerialization.jsonObject(with: objectData) as? [String: Any],
                  let name = obj[nameKey] as? String, !name.isEmpty else {
                return true
            }
            let count = parseCount(obj["count"])
            guard count > 0 else { return true }
            result.append(
                BrewTrendingItem(name: name, sourceType: sourceType, installCount: count, velocity: nil)
            )
            return result.count < limit
        }
        return result
    }

    static func counts(
        from data: Data,
        sourceType: InstallSourceType,
        neededNames: Set<String>
    ) -> [String: Int] {
        guard !neededNames.isEmpty else { return [:] }
        let nameKey = nameKey(for: sourceType)
        var result: [String: Int] = [:]
        result.reserveCapacity(neededNames.count)
        var remaining = neededNames

        forEachItemObject(in: data) { objectData in
            guard !remaining.isEmpty else { return false }
            guard let obj = try? JSONSerialization.jsonObject(with: objectData) as? [String: Any],
                  let name = obj[nameKey] as? String,
                  remaining.contains(name) else {
                return true
            }
            result["\(sourceType.rawValue):\(name)"] = parseCount(obj["count"])
            remaining.remove(name)
            return !remaining.isEmpty
        }
        return result
    }

    private static func forEachItemObject(in data: Data, body: (Data) -> Bool) {
        guard let itemsKeyRange = data.range(of: Data(#""items""#.utf8)) else { return }
        var i = itemsKeyRange.upperBound
        let bytes = data
        let count = bytes.count

        while i < count {
            let b = bytes[i]
            i += 1
            if b == UInt8(ascii: "[") { break }
            if b == UInt8(ascii: "{") { return }
        }

        while i < count {
            while i < count {
                let b = bytes[i]
                if b == UInt8(ascii: "]") { return }
                if b == UInt8(ascii: "{") { break }
                i += 1
            }
            guard i < count, bytes[i] == UInt8(ascii: "{") else { return }

            let start = i
            var depth = 0
            var inString = false
            var escape = false
            while i < count {
                let b = bytes[i]
                i += 1
                if inString {
                    if escape {
                        escape = false
                    } else if b == UInt8(ascii: "\\") {
                        escape = true
                    } else if b == UInt8(ascii: "\"") {
                        inString = false
                    }
                    continue
                }
                switch b {
                case UInt8(ascii: "\""):
                    inString = true
                case UInt8(ascii: "{"):
                    depth += 1
                case UInt8(ascii: "}"):
                    depth -= 1
                    if depth == 0 {
                        let objectData = bytes.subdata(in: start..<i)
                        if !body(objectData) { return }
                        break
                    }
                default:
                    break
                }
                if depth == 0 { break }
            }
        }
    }

    private static func nameKey(for sourceType: InstallSourceType) -> String {
        switch sourceType {
        case .cask: return "cask"
        default: return "formula"
        }
    }

    private static func parseCount(_ value: Any?) -> Int {
        if let s = value as? String { return Int(s) ?? 0 }
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }
}

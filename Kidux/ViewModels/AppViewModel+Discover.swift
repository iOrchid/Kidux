import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

extension AppViewModel {
    func prepareDiscoverPage() async {
        await ensureRuntimeSnapshot()
        if discoverMode == .homebrew, brewTrendingItems.isEmpty {
            scheduleBrewTrendingLoad(force: false)
        }
        preloadDiscoverIconsIfNeeded()
    }

    func preloadDiscoverIconsIfNeeded() {
        let icons = Array(discoverDisplayTools.prefix(12))
        Task { await ToolIconService.shared.preload(tools: icons) }
    }

    func scanLocalApplications() async {
        isScanningLocalApps = true
        localApplications = await localAppsScanner.scan(matching: bundleManager.catalog)
        isScanningLocalApps = false
        // 信任诊断改为按需（用户点「检测/修复」），避免启动即弹「访问其他 App 数据」。
        // 图标解析也仅在用户主动扫本机 App 后，才允许读 /Applications。
        await ToolIconService.shared.setLocalAppIconLookupEnabled(true)
    }

    /// 单 App 诊断结果写入短缓存，供列表徽章使用（不跑全盘扫描）。
    func rememberTrustReport(_ report: AppTrustReport) {
        switch report.probeStatus {
        case .unknown:
            localAppTrustFixPaths.remove(report.appPath)
        case .ok:
            localAppTrustFixPaths.remove(report.appPath)
        case .needsAttention:
            if report.needsRepair {
                localAppTrustFixPaths.insert(report.appPath)
            } else {
                localAppTrustFixPaths.remove(report.appPath)
            }
        }
    }

    func clearTrustFixBadge(path: String) {
        localAppTrustFixPaths.remove(path)
    }

    func localAppNeedsTrustFix(path: String) -> Bool {
        localAppTrustFixPaths.contains(path)
    }

    func rebuildCatalogCache() {
        let tools = bundleManager.catalog.values
            .filter { $0.id != "homebrew" }
            .sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        cachedAllCatalogTools = tools
        var counts: [ToolCategory: Int] = [.all: tools.count]
        for category in ToolCategory.allCases where category != .all {
            counts[category] = tools.filter { $0.category == category.rawValue }.count
        }
        cachedCategoryCounts = counts

        var sourceCounts: [InstallSourceType: Int] = [:]
        for tool in tools {
            sourceCounts[tool.source.type, default: 0] += 1
        }
        cachedSourceSummary = [
            "Cask \(sourceCounts[.cask, default: 0])",
            "Formula \(sourceCounts[.formula, default: 0])",
            "App Store \(sourceCounts[.mas, default: 0])",
            "脚本 \(sourceCounts[.script, default: 0])",
            "手动 \(sourceCounts[.link, default: 0])"
        ].joined(separator: " · ")

        lastCatalogFilterKey = ""
        cachedFilteredTools = []
        FeaturedPicksStore.invalidateCache()
        reindexSpotlightIfNeeded()
    }

    var allCatalogTools: [DevTool] {
        if cachedAllCatalogTools == nil { rebuildCatalogCache() }
        return cachedAllCatalogTools ?? []
    }

    func catalogCount(for category: ToolCategory) -> Int {
        if cachedCategoryCounts.isEmpty { rebuildCatalogCache() }
        return cachedCategoryCounts[category] ?? 0
    }

    var catalogSourceSummary: String {
        if cachedSourceSummary == nil { rebuildCatalogCache() }
        return cachedSourceSummary ?? ""
    }

    var discoverRoleFilterTitle: String {
        guard let id = discoverRoleFilter,
              let role = bundleManager.roles.first(where: { $0.id == id }) else {
            return "选择岗位"
        }
        return role.name
    }

    var filteredCatalogTools: [DevTool] {
        let query = discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nlKey = discoverNLToolIDs?.sorted().joined(separator: ",") ?? ""
        let filterKey = """
        \(discoverCategory ?? "*")|\(discoverSourceFilter.rawValue)|\(discoverScopeFilter.rawValue)|\
        \(discoverRoleFilter ?? "*")|\(discoverKindFilter?.rawValue ?? "*")|\
        \(discoverSourceTypeFilter?.rawValue ?? "*")|\(nlKey)|\(query)
        """
        if filterKey == lastCatalogFilterKey { return cachedFilteredTools }

        let roleIDs: Set<String> = {
            if discoverScopeFilter != .role { return [] }
            if let roleID = discoverRoleFilter {
                return bundleManager.toolIDs(forRoleID: roleID)
            }
            return bundleManager.allRoleToolIDs
        }()

        cachedFilteredTools = allCatalogTools.filter { tool in
            if let category = discoverCategory, tool.category != category { return false }

            switch discoverScopeFilter {
            case .all:
                break
            case .popular:
                if tool.priority >= 45 { return false }
            case .role:
                if !roleIDs.contains(tool.id) { return false }
            }

            switch discoverSourceFilter {
            case .all:
                break
            case .installable:
                if !tool.isInAppInstallable { return false }
            case .manual:
                if tool.source.type != .link { return false }
            }

            if let kindFilter = discoverKindFilter, tool.resolvedKind != kindFilter { return false }
            if let sourceTypeFilter = discoverSourceTypeFilter, tool.source.type != sourceTypeFilter { return false }
            if let pinned = discoverNLToolIDs, !pinned.isEmpty, !pinned.contains(tool.id) { return false }

            return tool.matchesDiscoverSearch(query)
        }
        lastCatalogFilterKey = filterKey
        return cachedFilteredTools
    }

    var discoverDisplayTools: [DevTool] {
        switch discoverMode {
        case .builtin:
            return filteredCatalogTools
        case .homebrew:
            return brewSearchResults.map(\.asDevTool)
        }
    }

    var showsDiscoverFeaturedSection: Bool {
        guard discoverMode == .builtin else { return false }
        guard discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard discoverNLSummary == nil else { return false }
        guard discoverCategory == nil else { return false }
        guard discoverScopeFilter == .all, discoverSourceFilter == .all else { return false }
        guard discoverRoleFilter == nil else { return false }
        guard discoverKindFilter == nil, discoverSourceTypeFilter == nil else { return false }
        guard discoverNLToolIDs == nil else { return false }
        return true
    }

    var showsDiscoverTrendingSection: Bool {
        guard discoverMode == .homebrew else { return false }
        guard discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch brewTrendingLoadState {
        case .idle:
            return !brewTrendingItems.isEmpty
        case .loading, .failed:
            return true
        case .success:
            return true
        }
    }

    func loadBrewTrending(force: Bool = false) async {
        guard discoverMode == .homebrew else { return }
        if Task.isCancelled {
            DiagnosticsEventLog.record("trending.load.cancel", fields: [
                "windowDays": "\(settings.trendingWindowDays.rawValue)",
                "phase": "preflight"
            ])
            return
        }

        let windowDays = settings.trendingWindowDays
        let started = Date()
        DiagnosticsEventLog.record("trending.load.start", fields: [
            "windowDays": "\(windowDays.rawValue)",
            "force": force ? "true" : "false"
        ])

        // 先涂缓存，秒开；网络只做刷新
        if let cached = await BrewTrendingService.cachedItems(windowDays: windowDays) {
            brewTrendingItems = cached
            brewTrendingLoadState = .success(cached)
            DiagnosticsEventLog.record("trending.cache.hit", fields: [
                "windowDays": "\(windowDays.rawValue)",
                "source": "uiPaint",
                "itemCount": "\(cached.count)"
            ])
            if !force, await BrewTrendingService.isMemoryFresh(windowDays: windowDays) {
                DiagnosticsEventLog.record("trending.fetch.skip", fields: [
                    "windowDays": "\(windowDays.rawValue)",
                    "reason": "memoryFresh"
                ])
                scheduleBrewTrendingVelocityEnrich()
                return
            }
        } else if case .success = brewTrendingLoadState, !brewTrendingItems.isEmpty {
            // 保留上一窗口数据，避免闪空白
        } else {
            brewTrendingLoadState = .loading
        }

        let result = await BrewTrendingService.fetchTrending(
            windowDays: windowDays,
            force: force
        )
        if Task.isCancelled {
            DiagnosticsEventLog.record("trending.load.cancel", fields: [
                "windowDays": "\(windowDays.rawValue)",
                "phase": "afterFetch"
            ])
            return
        }

        let elapsed = Date().timeIntervalSince(started) * 1000
        switch result {
        case .success(let items, let source):
            brewTrendingItems = items
            brewTrendingLoadState = .success(items)
            DiagnosticsEventLog.record("trending.load.ok", durationMs: elapsed, fields: [
                "windowDays": "\(windowDays.rawValue)",
                "itemCount": "\(items.count)",
                "source": source
            ])
            // 仅真实网络刷新后才 enrich，避免失败路径再砸 4 路大 JSON
            if source == "network" || source == "memoryFresh" {
                scheduleBrewTrendingVelocityEnrich()
            }
        case .failure(let message):
            if message == "已取消" {
                DiagnosticsEventLog.record("trending.load.cancel", fields: [
                    "windowDays": "\(windowDays.rawValue)",
                    "phase": "fetchResult"
                ])
                return
            }
            // 有旧数据则保留，不因网络失败清空列表
            if brewTrendingItems.isEmpty {
                brewTrendingLoadState = .failed(message)
            } else {
                brewTrendingLoadState = .success(brewTrendingItems)
            }
            DiagnosticsEventLog.record("trending.load.fail", durationMs: elapsed, fields: [
                "windowDays": "\(windowDays.rawValue)",
                "message": message,
                "keptItems": "\(brewTrendingItems.count)"
            ])
        }
    }

    /// 统一入口：取消旧任务与在途 HTTP，避免切模式 / 连点 30·90·365 叠加。
    func scheduleBrewTrendingLoad(force: Bool = false, debounceNanoseconds: UInt64 = 0) {
        brewTrendingTask?.cancel()
        brewTrendingVelocityTask?.cancel()
        Task(priority: .utility) {
            await BrewTrendingService.cancelInFlightNetwork()
        }
        guard discoverMode == .homebrew else { return }

        DiagnosticsEventLog.record("trending.schedule", fields: [
            "windowDays": "\(settings.trendingWindowDays.rawValue)",
            "force": force ? "true" : "false",
            "debounceMs": "\(debounceNanoseconds / 1_000_000)",
            "existingItems": "\(brewTrendingItems.count)"
        ])

        if !force, case .success = brewTrendingLoadState, !brewTrendingItems.isEmpty {
            // 有成功态时保留 UI，后台刷新
        } else if case .loading = brewTrendingLoadState {
            // keep loading
        } else {
            // 有任意缓存可先不进 loading；真正进 load 时会 paint
            brewTrendingLoadState = .loading
        }

        brewTrendingTask = Task {
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
                if Task.isCancelled { return }
            }
            await loadBrewTrending(force: force)
        }
    }

    func retryBrewTrending() {
        let now = Date()
        if let last = lastBrewTrendingRetryAt, now.timeIntervalSince(last) < 0.5 {
            return
        }
        lastBrewTrendingRetryAt = now
        scheduleBrewTrendingLoad(force: true)
    }

    /// 供 SwiftUI `.refreshable` 等待完成；内部取消旧任务。
    func reloadBrewTrending(force: Bool = true) async {
        brewTrendingTask?.cancel()
        brewTrendingVelocityTask?.cancel()
        await BrewTrendingService.cancelInFlightNetwork()
        if brewTrendingItems.isEmpty {
            brewTrendingLoadState = .loading
        }
        await loadBrewTrending(force: force)
    }

    func enrichBrewTrendingVelocity() async {
        guard discoverMode == .homebrew, !brewTrendingItems.isEmpty else { return }
        if Task.isCancelled {
            DiagnosticsEventLog.record("trending.enrich.cancel", fields: ["phase": "preflight"])
            return
        }
        let snapshot = brewTrendingItems
        let windowDays = settings.trendingWindowDays
        let started = Date()
        DiagnosticsEventLog.record("trending.enrich.start", fields: [
            "windowDays": "\(windowDays.rawValue)",
            "itemCount": "\(snapshot.count)"
        ])
        let enriched = await BrewTrendingService.enrichVelocity(
            items: snapshot,
            windowDays: windowDays
        )
        if Task.isCancelled {
            DiagnosticsEventLog.record("trending.enrich.cancel", fields: [
                "windowDays": "\(windowDays.rawValue)",
                "phase": "afterFetch"
            ])
            return
        }
        // 仅当列表未在 enrich 期间被替换时写回
        guard brewTrendingItems.map(\.id) == snapshot.map(\.id) else {
            DiagnosticsEventLog.record("trending.enrich.cancel", fields: [
                "windowDays": "\(windowDays.rawValue)",
                "phase": "staleList"
            ])
            return
        }
        brewTrendingItems = enriched
        if case .success = brewTrendingLoadState {
            brewTrendingLoadState = .success(enriched)
        }
        DiagnosticsEventLog.record(
            "trending.enrich.ok",
            durationMs: Date().timeIntervalSince(started) * 1000,
            fields: [
                "windowDays": "\(windowDays.rawValue)",
                "itemCount": "\(enriched.count)",
                "withVelocity": "\(enriched.filter { $0.velocity != nil }.count)"
            ]
        )
    }

    func scheduleBrewTrendingVelocityEnrich() {
        brewTrendingVelocityTask?.cancel()
        brewTrendingVelocityTask = Task {
            // 增速是锦上添花：等热门列表稳定后再拉 4 份 analytics，避免与主列表/图标抢 IO
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            await enrichBrewTrendingVelocity()
        }
    }

    func openCommandPalette() {
        showCommandPalette = true
        focusMainWindow()
    }

    var featuredPickSections: [ResolvedFeaturedSection] {
        FeaturedPicksStore.resolvedSections(catalog: allCatalogTools)
    }

    func updateDiscoverSearch(_ text: String) {
        discoverSearchText = text
        if discoverNLSummary != nil {
            clearDiscoverNLFilter()
        }
        scheduleBrewSearch()
    }

    func applyDiscoverNaturalLanguageFilter() async {
        guard discoverMode == .builtin else { return }
        let raw = discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        isApplyingDiscoverNL = true
        defer { isApplyingDiscoverNL = false }

        var plan: DiscoverNLFilterPlan?

        if CatalogNLFilterService.looksLikeNaturalLanguage(raw) {
            plan = try? await AppleIntelligenceSupport.planCatalogFilter(
                input: raw,
                catalog: allCatalogTools,
                roles: bundleManager.roles
            )

            if plan == nil,
               !settings.offlineMode,
               settings.enableCloudAI,
               settings.hasAIAPIKey {
                plan = try? await CatalogNLFilterService.planWithLLM(
                    input: raw,
                    catalog: allCatalogTools,
                    roles: bundleManager.roles,
                    apiKey: settings.aiAPIKey,
                    model: settings.aiModel,
                    baseURL: settings.effectiveBaseURL
                )
            }
        }

        let resolved = plan ?? CatalogNLFilterService.plan(
            input: raw,
            catalog: allCatalogTools,
            roles: bundleManager.roles
        )

        applyDiscoverNLPlan(resolved)
    }

    func clearDiscoverNLFilter() {
        discoverNLSummary = nil
        discoverNLToolIDs = nil
        discoverKindFilter = nil
        discoverSourceTypeFilter = nil
        lastCatalogFilterKey = ""
    }

    func applyDiscoverNLPlan(_ plan: DiscoverNLFilterPlan) {
        if let category = plan.category {
            discoverCategory = category
        }
        if let sourceFilter = plan.sourceFilter {
            discoverSourceFilter = sourceFilter
        }
        if let scopeFilter = plan.scopeFilter {
            discoverScopeFilter = scopeFilter
        }
        if let roleFilter = plan.roleFilter {
            discoverRoleFilter = roleFilter
            discoverScopeFilter = .role
        }

        discoverKindFilter = plan.kindFilter
        discoverSourceTypeFilter = plan.sourceTypeFilter
        discoverNLToolIDs = plan.pinnedToolIDs.isEmpty ? nil : Set(plan.pinnedToolIDs)
        discoverSearchText = plan.keywordQuery
        discoverNLSummary = plan.hasStructuredFilters ? plan.summary : nil
        lastCatalogFilterKey = ""
        scheduleBrewSearch()
    }

    func clearDiscoverFilters() {
        discoverSearchText = ""
        discoverCategory = nil
        discoverScopeFilter = .all
        discoverSourceFilter = .all
        discoverRoleFilter = nil
        clearDiscoverNLFilter()
        lastCatalogFilterKey = ""
        cachedFilteredTools = []
        brewSearchResults = []
        brewSearchHint = nil
        if discoverMode == .homebrew {
            brewSearchHint = "输入至少 2 个字符搜索 Homebrew"
        }
        discoverFiltersRevision += 1
    }

    func askAIAboutDiscover(query: String) {
        navigateTo(.assistant)
        sendAIMessage("帮我找适合我的软件：\(query)")
    }

    func catalogTool(id: String) -> DevTool? {
        bundleManager.catalog[id] ?? allCatalogTools.first { $0.id == id }
    }

    func setDiscoverMode(_ mode: DiscoverCatalogMode) {
        let previous = discoverMode
        discoverMode = mode
        brewSearchHint = nil
        DiagnosticsEventLog.record("ui.discover_mode_changed", fields: [
            "from": previous.rawValue,
            "to": mode.rawValue
        ])
        if mode == .homebrew {
            discoverSelectedTools.removeAll()
            scheduleBrewTrendingLoad(force: false)
        } else {
            brewTrendingTask?.cancel()
            brewTrendingVelocityTask?.cancel()
            Task(priority: .utility) {
                await BrewTrendingService.cancelInFlightNetwork()
            }
            brewTrendingItems = []
            brewTrendingLoadState = .idle
        }
        scheduleBrewSearch()
    }

    func scheduleBrewSearch() {
        brewSearchTask?.cancel()
        guard discoverMode == .homebrew else {
            brewSearchResults = []
            isSearchingBrew = false
            brewSearchHint = nil
            return
        }

        let query = discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            brewSearchResults = []
            isSearchingBrew = false
            brewSearchHint = query.isEmpty ? "输入至少 2 个字符搜索 Homebrew" : "继续输入以搜索"
            return
        }

        brewSearchTask = Task {
            isSearchingBrew = true
            brewSearchHint = nil
            defer { if !Task.isCancelled { isSearchingBrew = false } }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            if !environmentStatus.hasHomebrew {
                await checkEnvironment()
            }
            guard environmentStatus.hasHomebrew else {
                brewSearchResults = []
                brewSearchHint = "需要先安装 Homebrew（可在岗位配置流程中自动安装）"
                return
            }

            let results = await homebrewService.search(query: query)
            guard !Task.isCancelled else { return }
            brewSearchResults = results
            brewSearchHint = results.isEmpty ? "未找到匹配的 formula 或 cask" : nil
        }
    }

    func installStateForCatalog(_ tool: DevTool) -> ToolInstallState {
        guard let snapshot = installedSnapshot else { return .unknown }
        return snapshot.state(for: tool)
    }

    func toggleDiscoverSelection(_ toolID: String) {
        guard let tool = allCatalogTools.first(where: { $0.id == toolID }) else { return }
        if let snapshot = installedSnapshot,
           snapshot.state(for: tool) == .installed,
           tool.isInAppInstallable {
            return
        }
        if discoverSelectedTools.contains(toolID) {
            discoverSelectedTools.remove(toolID)
        } else {
            discoverSelectedTools.insert(toolID)
        }
    }

    var installableDiscoverSelectionCount: Int {
        discoverDisplayTools.filter { discoverSelectedTools.contains($0.id) && $0.isInAppInstallable }.count
    }

    func installableTools(from tools: [DevTool]) -> [DevTool] {
        tools.filter(\.isInAppInstallable)
    }

    func installDiscoverTool(_ tool: DevTool) async {
        if tool.source.type == .link {
            await openExternalLink(for: tool)
            return
        }
        await installDiscoverTools([tool])
    }

    func openExternalLink(for tool: DevTool) async {
        let urlString = await ToolIconService.shared.homepage(for: tool) ?? tool.source.identifier
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func installDiscoverSelection() async {
        let tools = installableTools(from: discoverDisplayTools.filter { discoverSelectedTools.contains($0.id) })
        guard !tools.isEmpty else { return }
        await installDiscoverTools(tools)
        discoverSelectedTools.removeAll()
    }

    func installDiscoverTools(_ tools: [DevTool]) async {
        guard !tools.isEmpty else { return }
        let resolved = tools.map { ResolvedTool(tool: $0, isRequired: false, isSelected: true) }

        // 1. 先填充队列并弹出 Sheet，让用户立刻看到任务列表与停止按钮
        installManager.beginInteractiveSession(tools: resolved, postInstallSteps: [])
        showDiscoverInstallSheet = true
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(120))

        // 2. 扫描已安装（可能较慢，此时 Sheet 已可见且 isInstalling=true）
        if installedSnapshot == nil {
            installManager.logOutput += "🔍 正在扫描已安装软件…\n"
            await scanInstalledStatus()
        }

        // 3. 正式安装（不再清空已展示的队列）
        await installManager.startInstallation(
            tools: resolved,
            postInstallSteps: [],
            mirror: settings.brewMirror,
            enableMAS: settings.enableMAS,
            skipInstalled: settings.skipInstalled,
            snapshot: installedSnapshot
        )
        await scanInstalledStatus(force: true)
        recordInstallCompletionSummary(source: .discover)
        notifyInstallFinishedIfNeeded()
    }

}

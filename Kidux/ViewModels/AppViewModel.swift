import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case assistant
    case roles
    case discover
    case installed
    case environment
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return String(localized: "tab.home")
        case .assistant: return String(localized: "tab.assistant")
        case .roles: return String(localized: "tab.roles")
        case .discover: return String(localized: "tab.discover")
        case .installed: return String(localized: "tab.installed")
        case .environment: return String(localized: "tab.environment")
        case .settings: return String(localized: "tab.settings")
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .assistant: return "sparkles"
        case .roles: return "person.crop.rectangle.stack"
        case .discover: return "square.grid.2x2"
        case .installed: return "checkmark.circle"
        case .environment: return "terminal"
        case .settings: return "gearshape"
        }
    }

    /// 经典模式侧栏 Tab（设置走系统 Settings 窗口，不占侧栏）
    static let classicTabs: [AppTab] = [
        .home, .assistant, .roles, .discover, .installed, .environment
    ]
}

enum AppScreen: Hashable {
    case welcome
    case roleSelection
    case bundleDetail
    case installation
    case complete
}

@MainActor
@Observable
final class AppViewModel {
    var selectedTab: AppTab = .home
    var currentScreen: AppScreen = .welcome
    var environmentStatus: EnvironmentStatus = .unsupported
    var isCheckingEnvironment = false
    var isScanningInstalled = false

    var discoverSearchText = ""
    var discoverCategory: String?
    /// 发现页筛选重置时递增，供视图同步本地状态
    var discoverFiltersRevision = 0
    var discoverSourceFilter: DiscoverSourceFilter = .all
    var discoverScopeFilter: DiscoverScopeFilter = .all
    var discoverRoleFilter: String?
    var discoverMode: DiscoverCatalogMode = .builtin
    var discoverSelectedTools: Set<String> = []
    var discoverNLSummary: String?
    var discoverNLToolIDs: Set<String>?
    var discoverKindFilter: ToolKind?
    var discoverSourceTypeFilter: InstallSourceType?
    var isApplyingDiscoverNL = false
    var isDiscoverSpeechListening = false
    var discoverSpeechStatus: String?
    var showDiscoverInstallSheet = false
    var brewSearchResults: [BrewSearchResult] = []
    var isSearchingBrew = false
    var brewSearchHint: String?
    var brewTrendingItems: [BrewTrendingItem] = []
    var brewTrendingLoadState: LoadState<[BrewTrendingItem]> = .idle
    var lastBrewTrendingRetryAt: Date?
    var showCommandPalette = false

    var selectedRoles: Set<String> = []
    var resolvedTools: [ResolvedTool] = []
    var postInstallSteps: [PostInstallStep] = []
    var installedSnapshot: InstalledStatusSnapshot?
    var localApplications: [LocalApplication] = []
    var isScanningLocalApps = false
    /// 本机应用路径集合：仅用户按需诊断后、且 needsRepair 时显示徽章（不启动全盘扫描）
    var localAppTrustFixPaths: Set<String> = []

    var aiMessages: [AIChatMessage] = []
    var aiSuggestedFollowUps: [String] = []
    var aiIsThinking = false
    var aiIsStreaming = false
    var aiStreamRevision = 0
    var aiConnectionTestResult: String?
    var aiModelCatalogStatus: String?
    var extendedCatalogStatusMessage: String?
    var aiConnectionTestInProgress = false
    var aiGenerationTask: Task<Void, Never>?

    var outdatedResult: OutdatedScanResult?
    var isCheckingUpdates = false
    var updateCheckMessage: String?
    var isUpgradingItem: String?
    var updateBannerDismissed = false
    var showMaintenanceSheet = false
    var uninstallSelection: Set<String> = []
    var maintenanceStatusMessage: String?
    var brewServices: [BrewServiceItem] = []
    var isLoadingBrewServices = false
    var brewServiceActionID: String?
    var formulaDependencyRoot: DependencyTreeNode?
    var isLoadingFormulaDependencies = false
    var formulaDependencyError: String?
    var formulaDependencyCache: [String: DependencyTreeNode] = [:]
    var brewLeavesNames: Set<String> = []
    var isLoadingBrewLeaves = false
    var pinnedFormulae: Set<String> = []
    var isLoadingPinned = false
    var brewDiskUsage: BrewDiskUsage?
    var isLoadingBrewDisk = false
    var isRunningBrewCleanup = false
    var brewVulnerabilityScan: BrewVulnerabilityScan?
    var isLoadingBrewVulns = false
    var isInstallingBrewVulnsPlugin = false
    var mackupInstalled = false

    var runtimeProfiles: [RuntimeProfile] = []
    var localServiceHealth: [LocalServiceHealth] = []
    var versionManagerProfiles: [VersionManagerProfile] = []
    var isScanningRuntimeEnvironment = false
    var runtimeEnvironmentScannedAt: Date?
    var environmentDriftReport: EnvironmentDriftReport?
    var isComparingEnvironmentDrift = false
    var environmentDriftStatusMessage: String?
    var environmentDriftExplanation: EnvironmentDriftExplanation?
    var isExplainingEnvironmentDrift = false
    var isInstallingDriftMissing = false
    var runtimeScanInFlight = false
    var lastRuntimeScanDate: Date?
    let runtimeScanCooldown: TimeInterval = 30
    var lastDriftCompareDate: Date?
    let driftCompareCooldown: TimeInterval = 60
    var lastEnvironmentCheckDate: Date?
    let environmentCheckCooldown: TimeInterval = 120

    var appUpdateInfo: AppReleaseInfo?
    var isCheckingAppUpdate = false
    var appUpdateBannerDismissed = false
    var appUpdateStatusMessage: String?
    var installCompletionSummary: String?
    var shouldPresentOnboarding = false
    var shouldShowInstalledUpdatesScope = false
    var showMigrationWizard = false
    var showDryRunSheet = false
    var dryRunPlan: InstallDryRunPlan?
    var preflightReport: InstallPreflightReport?
    var isAnalyzingPreflight = false
    var showPreflightConfirm = false
    var pendingInstallAfterPreflight = false
    var lastRollbackBatch: InstallRollbackBatch?
    var isAISpeechListening = false
    var aiSpeechStatus: String?
    var pendingSpotlightToolID: String?
    /// S18-19
    var lastImportedEnvironmentSnapshot: EnvironmentSnapshot?
    var migrationRecommendations: [MigrationRecommendation] = []
    var selectedMigrationRecommendationIDs: Set<String> = []
    var isRefreshingMigrationRecommendations = false
    /// S18-12
    var brewfileSyncDiff: BrewfileSyncDiff?
    var brewfileSyncStatusMessage: String?

    /// 当前会话交互模式（经典 / 沉浸），与设置中的「默认布局」独立
    var activeInteractionMode: AppInteractionMode

    var outdatedCount: Int { outdatedResult?.count ?? 0 }

    /// S22-20 — 共享服务（Discover / Installed / Environment / InstallSession 共用）
    let services = AppServices()
    var settings: AppSettings { services.settings }
    var bundleManager: BundleManager { services.bundleManager }
    var installManager: InstallManager { services.installManager }
    var maintenanceManager: MaintenanceManager { services.maintenanceManager }
    var installedScanner: InstalledStatusScanner { services.installedScanner }
    var localAppsScanner: LocalApplicationsScanner { services.localAppsScanner }
    var homebrewService: HomebrewService { services.homebrewService }

    var brewSearchTask: Task<Void, Never>?
    var brewTrendingTask: Task<Void, Never>?
    var brewTrendingVelocityTask: Task<Void, Never>?

    var cachedAllCatalogTools: [DevTool]?
    var cachedCategoryCounts: [ToolCategory: Int] = [:]
    var cachedSourceSummary: String?
    var cachedFilteredTools: [DevTool] = []
    var lastCatalogFilterKey = ""

    var lastScanDate: Date?
    var scanInFlight = false
    let scanCooldown: TimeInterval = 45
    var lastBrewServicesDate: Date?
    let brewServicesCooldown: TimeInterval = 60
    var lastPinnedFormulaeDate: Date?
    let pinnedFormulaeCooldown: TimeInterval = 120
    var lastMackupStatusDate: Date?
    let mackupStatusCooldown: TimeInterval = 120

    var isBrewOperationBusy: Bool { services.isBrewBusy }

    init() {
        activeInteractionMode = AppSettings.shared.interactionMode
        lastRollbackBatch = InstallRollbackStore.load()
        // S22-10 — catalog 后台加载，避免阻塞首帧
        Task { await self.bootstrapCatalogAsync() }
        // 更新检查 / 通知授权 / Brewfile 对比一律延后，避免与首帧叠加触发系统权限弹窗。
        Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await checkKiduxAppUpdate()
        }
        Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            await InstallNotificationService.requestAuthorizationIfNeeded()
        }
        Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await checkBrewfileSyncIfEnabled()
        }
    }

    func bootstrapCatalogAsync() async {
        await bundleManager.reloadAsync()
        rebuildCatalogCache()
        // 冷启动只加载目录；不扫 brew/mas/本机 App（会触发「访问其他 App 数据」）。
        // Spotlight 延后到用户打开发现/已安装，或设置里手动开关。
        await checkEnvironment()
    }

    /// 页内按需：环境探测 +（可选）已安装快照。冷启动勿调用含扫描的路径。
    func ensureRuntimeSnapshot(force: Bool = false, includeInstalledScan: Bool = true) async {
        await checkEnvironment(force: force)
        if includeInstalledScan {
            await scanInstalledStatus(force: force, checkUpdates: true)
        }
    }

    func openInstalledUpdates() {
        navigateTo(.installed)
        shouldShowInstalledUpdatesScope = true
        focusMainWindow()
    }

    func focusMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let mains = NSApplication.shared.windows.filter {
            $0.styleMask.contains(.titled) && $0.canBecomeMain && $0.level == .normal
        }
        if let target = mains.first(where: \.isVisible) ?? mains.first {
            target.makeKeyAndOrderFront(nil)
        } else {
            // 冷启动仅有菜单栏时，打开主窗口场景
            NSApp.windows.first { $0.styleMask.contains(.titled) }?.makeKeyAndOrderFront(nil)
        }
    }

    /// 退出前清理：停语音/AI、取消 brew/维护，避免 terminate 与后台任务竞态。
    func prepareForTermination() async {
        cancelAIGeneration()
        DiscoverSpeechInputService.shared.stopListening()
        maintenanceManager.requestCancel()
        await installManager.requestCancel()
    }

    /// 打开系统「设置」窗口（S22-05 单一入口）
    /// 状态栏 / 后台点击时必须先激活 App，并用 AppKit `showSettingsWindow:`；
    /// 仅靠 SwiftUI `openSettings` 在非前台或主窗未开时经常无响应。
    func openSystemSettings() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let settingsSelector = Selector(("showSettingsWindow:"))
            let prefsSelector = Selector(("showPreferencesWindow:"))
            if NSApp.sendAction(settingsSelector, to: nil, from: nil) {
                return
            }
            if NSApp.sendAction(prefsSelector, to: nil, from: nil) {
                return
            }
            NotificationCenter.default.post(name: Self.openSettingsNotification, object: nil)
        }
    }

    static let openSettingsNotification = Notification.Name("co.langem.kidux.openSettings")

    func notifyInstallFinishedIfNeeded() {
        guard let summary = installManager.summary else { return }
        Task {
            await InstallNotificationService.notifyInstallFinished(
                summary: summary,
                cancelled: installManager.isCancelled
            )
        }
    }

    /// 打开指定模块；沉浸模式下非对话目标会切回经典侧栏（避免嵌入重型页面卡顿）
    func navigateTo(_ tab: AppTab) {
        if tab == .settings {
            openSystemSettings()
            return
        }
        if activeInteractionMode == .ai, tab != .assistant, tab != .home {
            activeInteractionMode = .classic
        }
        selectedTab = tab == .home ? .home : tab
        if tab == .roles, currentScreen == .welcome {
            currentScreen = .roleSelection
        }
    }

    func reset() {
        selectedRoles = []
        resolvedTools = []
        postInstallSteps = []
        installedSnapshot = nil
        discoverSelectedTools = []
        currentScreen = .welcome
        selectedTab = .home
    }
}

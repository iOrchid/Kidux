import Foundation
import Observation

enum TrendingWindowDays: Int, CaseIterable, Identifiable, Codable, Sendable {
    case days30 = 30
    case days90 = 90
    case days365 = 365

    var id: Int { rawValue }

    /// 列表/副标题用语，例如「近 30 天」
    var displayName: String {
        switch self {
        case .days30: return "近 30 天"
        case .days90: return "近 90 天"
        case .days365: return "近 1 年"
        }
    }

    /// 分段控件短标签
    var shortTitle: String { displayName }

    var analyticsSegment: String { "\(rawValue)d" }
}

enum BrewMirror: String, CaseIterable, Identifiable, Codable, Sendable {
    case official
    case tsinghua
    case ustc
    case bfsu
    case tencent
    case aliyun

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .official: return "官方源（brew.sh）"
        case .tsinghua: return "清华大学镜像"
        case .ustc: return "中科大镜像"
        case .bfsu: return "北京外国语大学镜像"
        case .tencent: return "腾讯镜像"
        case .aliyun: return "阿里巴巴镜像"
        }
    }

    var environmentVariables: [String: String] {
        switch self {
        case .official:
            return [:]
        case .tsinghua:
            return [
                "HOMEBREW_API_DOMAIN": "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api",
                "HOMEBREW_BOTTLE_DOMAIN": "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles",
                "HOMEBREW_BREW_GIT_REMOTE": "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git",
                "HOMEBREW_CORE_GIT_REMOTE": "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git",
                "HOMEBREW_INSTALL_FROM_API": "1"
            ]
        case .ustc:
            return [
                "HOMEBREW_API_DOMAIN": "https://mirrors.ustc.edu.cn/homebrew-bottles/api",
                "HOMEBREW_BOTTLE_DOMAIN": "https://mirrors.ustc.edu.cn/homebrew-bottles",
                "HOMEBREW_BREW_GIT_REMOTE": "https://mirrors.ustc.edu.cn/brew.git",
                "HOMEBREW_CORE_GIT_REMOTE": "https://mirrors.ustc.edu.cn/homebrew-core.git",
                "HOMEBREW_INSTALL_FROM_API": "1"
            ]
        case .bfsu:
            return [
                "HOMEBREW_BOTTLE_DOMAIN": "https://mirrors.bfsu.edu.cn/homebrew-bottles",
                "HOMEBREW_BREW_GIT_REMOTE": "https://mirrors.bfsu.edu.cn/git/homebrew/brew.git",
                "HOMEBREW_CORE_GIT_REMOTE": "https://mirrors.bfsu.edu.cn/git/homebrew/homebrew-core.git",
                "HOMEBREW_INSTALL_FROM_API": "1"
            ]
        case .tencent:
            return [
                "HOMEBREW_BOTTLE_DOMAIN": "https://mirrors.cloud.tencent.com/homebrew-bottles",
                "HOMEBREW_BREW_GIT_REMOTE": "https://mirrors.cloud.tencent.com/homebrew/brew.git",
                "HOMEBREW_CORE_GIT_REMOTE": "https://mirrors.cloud.tencent.com/homebrew/homebrew-core.git",
                "HOMEBREW_INSTALL_FROM_API": "1"
            ]
        case .aliyun:
            return [
                "HOMEBREW_BOTTLE_DOMAIN": "https://mirrors.aliyun.com/homebrew/homebrew-bottles",
                "HOMEBREW_BREW_GIT_REMOTE": "https://mirrors.aliyun.com/homebrew/brew.git",
                "HOMEBREW_CORE_GIT_REMOTE": "https://mirrors.aliyun.com/homebrew/homebrew-core.git",
                "HOMEBREW_INSTALL_FROM_API": "1"
            ]
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let brewMirror = "settings.brewMirror"
        static let enableMAS = "settings.enableMAS"
        static let enableThirdPartySources = "settings.enableThirdPartySources"
        static let thirdPartyDisclaimerAccepted = "settings.thirdPartyDisclaimerAccepted"
        static let skipInstalled = "settings.skipInstalled"
        static let allowMultipleRoles = "settings.allowMultipleRoles"
        static let interactionMode = "settings.interactionMode"
        static let aiStreamEnabled = "settings.aiStreamEnabled"
        static let aiTemperature = "settings.aiTemperature"
        static let aiMaxTokens = "settings.aiMaxTokens"
        static let aiProvider = "settings.aiProvider"
        static let aiAPIKey = "settings.aiAPIKey"
        static let aiModel = "settings.aiModel"
        static let aiCustomBaseURL = "settings.aiCustomBaseURL"
        static let enableCloudAI = "settings.enableCloudAI"
        // 旧版键（迁移用）
        static let siliconFlowAPIKey = "settings.siliconFlowAPIKey"
        static let siliconFlowModel = "settings.siliconFlowModel"
        static let enableSiliconFlowAI = "settings.enableSiliconFlowAI"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let teamBundleName = "settings.teamBundleName"
        static let teamBundleAuthor = "settings.teamBundleAuthor"
        static let driftBaselineJSON = "settings.driftBaselineJSON"
        static let driftBaselineLabel = "settings.driftBaselineLabel"
        static let showMenuBarHealthIndicator = "settings.showMenuBarHealthIndicator"
        static let trendingWindowDays = "settings.trendingWindowDays"
        static let offlineMode = "settings.offlineMode"
        static let taggedFormulaIDs = "settings.taggedFormulaIDs"
        /// 是否已配置 API Key（仅 UserDefaults 标记，启动时不读 Keychain）
        static let aiAPIKeyPresent = "settings.aiAPIKeyPresent"
        static let indexCatalogInSpotlight = "settings.indexCatalogInSpotlight"
        static let scheduledBrewUpdateEnabled = "settings.scheduledBrewUpdateEnabled"
        static let lastScheduledBrewUpdateAt = "settings.lastScheduledBrewUpdateAt"
        static let weeklyHealthDigestEnabled = "settings.weeklyHealthDigestEnabled"
        static let lastWeeklyHealthDigestAt = "settings.lastWeeklyHealthDigestAt"
        static let brewfileWatchPath = "settings.brewfileWatchPath"
        static let brewfileAutoSyncCheckEnabled = "settings.brewfileAutoSyncCheckEnabled"
        static let preferredShell = "settings.preferredShell"
        static let usageFrequencyTrackingEnabled = "settings.usageFrequencyTrackingEnabled"
    }

    /// 首次启动引导是否已完成（S11-03）
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }

    var brewMirror: BrewMirror {
        didSet { UserDefaults.standard.set(brewMirror.rawValue, forKey: Keys.brewMirror) }
    }

    var enableMAS: Bool {
        didSet { UserDefaults.standard.set(enableMAS, forKey: Keys.enableMAS) }
    }

    var enableThirdPartySources: Bool {
        didSet { UserDefaults.standard.set(enableThirdPartySources, forKey: Keys.enableThirdPartySources) }
    }

    var thirdPartyDisclaimerAccepted: Bool {
        didSet { UserDefaults.standard.set(thirdPartyDisclaimerAccepted, forKey: Keys.thirdPartyDisclaimerAccepted) }
    }

    func acceptThirdPartyDisclaimer() {
        thirdPartyDisclaimerAccepted = true
    }

    var skipInstalled: Bool {
        didSet { UserDefaults.standard.set(skipInstalled, forKey: Keys.skipInstalled) }
    }

    var allowMultipleRoles: Bool {
        didSet { UserDefaults.standard.set(allowMultipleRoles, forKey: Keys.allowMultipleRoles) }
    }

    var aiProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(aiProvider.rawValue, forKey: Keys.aiProvider)
            if oldValue != aiProvider {
                applyProviderDefaults(preserveKey: true)
            }
        }
    }

    /// API Key（存 Keychain，v1.0 不再写入 UserDefaults）
    var aiAPIKey: String {
        get {
            ensureAPIKeyHydrated()
            return _aiAPIKeyStorage
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            _aiAPIKeyStorage = trimmed
            _aiAPIKeyHydrated = true
            UserDefaults.standard.set(!trimmed.isEmpty, forKey: Keys.aiAPIKeyPresent)
            UserDefaults.standard.removeObject(forKey: Keys.aiAPIKey)
            UserDefaults.standard.removeObject(forKey: Keys.siliconFlowAPIKey)
            try? KeychainStore.saveAIAPIKey(trimmed)
        }
    }

    private var _aiAPIKeyStorage = ""
    private var _aiAPIKeyHydrated = false

    var aiModel: String {
        didSet { UserDefaults.standard.set(aiModel, forKey: Keys.aiModel) }
    }

    var aiCustomBaseURL: String {
        didSet { UserDefaults.standard.set(aiCustomBaseURL, forKey: Keys.aiCustomBaseURL) }
    }

    var enableCloudAI: Bool {
        didSet { UserDefaults.standard.set(enableCloudAI, forKey: Keys.enableCloudAI) }
    }

    var aiStreamEnabled: Bool {
        didSet { UserDefaults.standard.set(aiStreamEnabled, forKey: Keys.aiStreamEnabled) }
    }

    var aiTemperature: Double {
        didSet { UserDefaults.standard.set(aiTemperature, forKey: Keys.aiTemperature) }
    }

    var aiMaxTokens: Int {
        didSet { UserDefaults.standard.set(aiMaxTokens, forKey: Keys.aiMaxTokens) }
    }

    var interactionMode: AppInteractionMode {
        didSet { UserDefaults.standard.set(interactionMode.rawValue, forKey: Keys.interactionMode) }
    }

    /// 团队 Bundle 导出时的团队名（S12-03）
    var teamBundleName: String {
        didSet { UserDefaults.standard.set(teamBundleName, forKey: Keys.teamBundleName) }
    }

    /// 团队 Bundle 导出时的作者/备注名
    var teamBundleAuthor: String {
        didSet { UserDefaults.standard.set(teamBundleAuthor, forKey: Keys.teamBundleAuthor) }
    }

    var driftBaselineLabel: String {
        get { UserDefaults.standard.string(forKey: Keys.driftBaselineLabel) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.driftBaselineLabel) }
    }

    func loadDriftBaseline() -> MachineEnvironmentState? {
        guard let data = UserDefaults.standard.data(forKey: Keys.driftBaselineJSON) else { return nil }
        return try? JSONDecoder().decode(MachineEnvironmentState.self, from: data)
    }

    func saveDriftBaseline(_ state: MachineEnvironmentState, label: String) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Keys.driftBaselineJSON)
        }
        driftBaselineLabel = label
    }

    func clearDriftBaseline() {
        UserDefaults.standard.removeObject(forKey: Keys.driftBaselineJSON)
        driftBaselineLabel = ""
    }

    /// 菜单栏环境红绿灯（S16-06）
    var showMenuBarHealthIndicator: Bool {
        didSet { UserDefaults.standard.set(showMenuBarHealthIndicator, forKey: Keys.showMenuBarHealthIndicator) }
    }

    /// Homebrew 热门排行统计窗口（S17-01）
    var trendingWindowDays: TrendingWindowDays {
        didSet { UserDefaults.standard.set(trendingWindowDays.rawValue, forKey: Keys.trendingWindowDays) }
    }

    /// 离线模式：阻断 analytics / 远程图标 / 应用更新检查（S17-05）
    var offlineMode: Bool {
        didSet { UserDefaults.standard.set(offlineMode, forKey: Keys.offlineMode) }
    }

    /// 将 Catalog 索引到系统 Spotlight（S20-01）
    var indexCatalogInSpotlight: Bool {
        didSet {
            UserDefaults.standard.set(indexCatalogInSpotlight, forKey: Keys.indexCatalogInSpotlight)
        }
    }

    /// S18-17 — 定时 brew update + outdated 扫描（LaunchAgent，默认关）
    var scheduledBrewUpdateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(scheduledBrewUpdateEnabled, forKey: Keys.scheduledBrewUpdateEnabled)
        }
    }

    var lastScheduledBrewUpdateAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: Keys.lastScheduledBrewUpdateAt)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.lastScheduledBrewUpdateAt)
        }
    }

    /// S19-03 — 环境健康周报本地通知（默认关）
    var weeklyHealthDigestEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weeklyHealthDigestEnabled, forKey: Keys.weeklyHealthDigestEnabled)
        }
    }

    var lastWeeklyHealthDigestAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: Keys.lastWeeklyHealthDigestAt)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.lastWeeklyHealthDigestAt)
        }
    }

    /// S18-12 — 监视的 Brewfile 路径（支持 ~）
    var brewfileWatchPath: String {
        didSet { UserDefaults.standard.set(brewfileWatchPath, forKey: Keys.brewfileWatchPath) }
    }

    /// S18-12 — 启动时自动对比 Brewfile 与 Kidux 勾选
    var brewfileAutoSyncCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(brewfileAutoSyncCheckEnabled, forKey: Keys.brewfileAutoSyncCheckEnabled)
        }
    }

    /// S17-12 — 终端 Shell 偏好（影响 postInstall）
    var preferredShell: PreferredShell {
        didSet { UserDefaults.standard.set(preferredShell.rawValue, forKey: Keys.preferredShell) }
    }

    /// S19-04 — 本机匿名使用频率追踪（默认关，不上报）
    var usageFrequencyTrackingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(usageFrequencyTrackingEnabled, forKey: Keys.usageFrequencyTrackingEnabled)
        }
    }

    /// 用户标记为「主动安装」的 formula（S17-03 Cork 式标签）
    private(set) var taggedFormulaIDs: Set<String> = []

    func isFormulaTagged(_ name: String) -> Bool {
        taggedFormulaIDs.contains(normalizeFormulaID(name))
    }

    func setFormulaTagged(_ name: String, tagged: Bool) {
        let key = normalizeFormulaID(name)
        if tagged {
            taggedFormulaIDs.insert(key)
        } else {
            taggedFormulaIDs.remove(key)
        }
        persistTaggedFormulaIDs()
    }

    func toggleFormulaTagged(_ name: String) {
        setFormulaTagged(name, tagged: !isFormulaTagged(name))
    }

    private func normalizeFormulaID(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func persistTaggedFormulaIDs() {
        UserDefaults.standard.set(Array(taggedFormulaIDs).sorted(), forKey: Keys.taggedFormulaIDs)
    }

    private func loadTaggedFormulaIDs() {
        let stored = UserDefaults.standard.stringArray(forKey: Keys.taggedFormulaIDs) ?? []
        taggedFormulaIDs = Set(stored.map { $0.lowercased() })
    }

    /// UI / 状态展示用，不触发 Keychain 读取。
    var hasAIAPIKey: Bool {
        UserDefaults.standard.bool(forKey: Keys.aiAPIKeyPresent)
    }

    /// 仅在 AI 相关功能首次使用时读取 Keychain，避免启动时弹出钥匙串密码。
    func ensureAPIKeyHydrated() {
        guard !_aiAPIKeyHydrated else { return }
        _aiAPIKeyHydrated = true

        let keychainKey = KeychainStore.loadAIAPIKey()
        if !keychainKey.isEmpty {
            _aiAPIKeyStorage = keychainKey
            UserDefaults.standard.set(true, forKey: Keys.aiAPIKeyPresent)
            return
        }

        let legacyUD = UserDefaults.standard.string(forKey: Keys.aiAPIKey)
            ?? UserDefaults.standard.string(forKey: Keys.siliconFlowAPIKey)
            ?? ""
        guard !legacyUD.isEmpty else { return }

        _aiAPIKeyStorage = legacyUD
        UserDefaults.standard.set(true, forKey: Keys.aiAPIKeyPresent)
        try? KeychainStore.saveAIAPIKey(legacyUD)
        UserDefaults.standard.removeObject(forKey: Keys.aiAPIKey)
        UserDefaults.standard.removeObject(forKey: Keys.siliconFlowAPIKey)
    }

    var effectiveBaseURL: String {
        let url = aiProvider == .custom ? aiCustomBaseURL : aiProvider.defaultBaseURL
        return url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func applyProviderDefaults(preserveKey: Bool = false) {
        if !preserveKey { /* key 保留 */ }
        aiModel = aiProvider.defaultModel
        if aiProvider != .custom {
            aiCustomBaseURL = aiProvider.defaultBaseURL
        }
    }

    private init() {
        let hadPriorDefaults = UserDefaults.standard.object(forKey: Keys.brewMirror) != nil
            || UserDefaults.standard.object(forKey: Keys.interactionMode) != nil

        let mirrorRaw = UserDefaults.standard.string(forKey: Keys.brewMirror) ?? BrewMirror.official.rawValue
        brewMirror = BrewMirror(rawValue: mirrorRaw) ?? .official
        enableMAS = UserDefaults.standard.object(forKey: Keys.enableMAS) as? Bool ?? true
        enableThirdPartySources = UserDefaults.standard.bool(forKey: Keys.enableThirdPartySources)
        thirdPartyDisclaimerAccepted = UserDefaults.standard.bool(forKey: Keys.thirdPartyDisclaimerAccepted)
        skipInstalled = UserDefaults.standard.object(forKey: Keys.skipInstalled) as? Bool ?? true
        allowMultipleRoles = UserDefaults.standard.bool(forKey: Keys.allowMultipleRoles)
        aiStreamEnabled = UserDefaults.standard.object(forKey: Keys.aiStreamEnabled) as? Bool ?? true
        aiTemperature = UserDefaults.standard.object(forKey: Keys.aiTemperature) as? Double ?? 0.7
        aiMaxTokens = UserDefaults.standard.object(forKey: Keys.aiMaxTokens) as? Int ?? 1024
        let modeRaw = UserDefaults.standard.string(forKey: Keys.interactionMode) ?? AppInteractionMode.ai.rawValue
        interactionMode = AppInteractionMode(rawValue: modeRaw) ?? .ai
        teamBundleName = UserDefaults.standard.string(forKey: Keys.teamBundleName) ?? ""
        teamBundleAuthor = UserDefaults.standard.string(forKey: Keys.teamBundleAuthor) ?? ""
        showMenuBarHealthIndicator = UserDefaults.standard.object(forKey: Keys.showMenuBarHealthIndicator) as? Bool ?? true
        let trendingRaw = UserDefaults.standard.object(forKey: Keys.trendingWindowDays) as? Int ?? TrendingWindowDays.days30.rawValue
        trendingWindowDays = TrendingWindowDays(rawValue: trendingRaw) ?? .days30
        offlineMode = UserDefaults.standard.bool(forKey: Keys.offlineMode)
        indexCatalogInSpotlight = UserDefaults.standard.object(forKey: Keys.indexCatalogInSpotlight) as? Bool ?? false
        scheduledBrewUpdateEnabled = UserDefaults.standard.bool(forKey: Keys.scheduledBrewUpdateEnabled)
        weeklyHealthDigestEnabled = UserDefaults.standard.bool(forKey: Keys.weeklyHealthDigestEnabled)
        brewfileWatchPath = UserDefaults.standard.string(forKey: Keys.brewfileWatchPath)
            ?? BrewfileSyncService.defaultSuggestedPath()
        brewfileAutoSyncCheckEnabled = UserDefaults.standard.bool(forKey: Keys.brewfileAutoSyncCheckEnabled)
        let shellRaw = UserDefaults.standard.string(forKey: Keys.preferredShell) ?? PreferredShell.system.rawValue
        preferredShell = PreferredShell(rawValue: shellRaw) ?? .system
        usageFrequencyTrackingEnabled = UserDefaults.standard.bool(forKey: Keys.usageFrequencyTrackingEnabled)

        // 迁移旧版硅基流动字段
        let legacyKey = UserDefaults.standard.string(forKey: Keys.siliconFlowAPIKey) ?? ""
        let legacyModel = UserDefaults.standard.string(forKey: Keys.siliconFlowModel)
        let legacyEnable = UserDefaults.standard.object(forKey: Keys.enableSiliconFlowAI) as? Bool

        let providerRaw = UserDefaults.standard.string(forKey: Keys.aiProvider) ?? AIProvider.siliconFlow.rawValue
        let resolvedProvider = AIProvider(rawValue: providerRaw) ?? .siliconFlow
        aiProvider = resolvedProvider

        // 启动阶段不访问 Keychain；首次使用 AI 或打开 AI 设置时再 hydrate
        _aiAPIKeyStorage = ""
        _aiAPIKeyHydrated = false
        aiModel = UserDefaults.standard.string(forKey: Keys.aiModel)
            ?? legacyModel
            ?? resolvedProvider.defaultModel
        aiCustomBaseURL = UserDefaults.standard.string(forKey: Keys.aiCustomBaseURL)
            ?? resolvedProvider.defaultBaseURL
        enableCloudAI = UserDefaults.standard.object(forKey: Keys.enableCloudAI) as? Bool
            ?? legacyEnable
            ?? true

        if UserDefaults.standard.object(forKey: Keys.hasCompletedOnboarding) == nil {
            // 须在写入默认偏好之前判断；否则全新安装也会被误判为老用户
            hasCompletedOnboarding = hadPriorDefaults
        } else {
            hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
        }

        loadTaggedFormulaIDs()
    }
}

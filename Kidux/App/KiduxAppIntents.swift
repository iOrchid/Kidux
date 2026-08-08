import AppIntents
import Foundation

// MARK: - S18-03 App Intents

struct ScanInstalledAppsIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "扫描已安装软件" }
    nonisolated static var description: IntentDescription {
        IntentDescription("扫描本机 Homebrew 与 App Store 已装项。")
    }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try AppIntentBridge.shared.requireViewModel()
        await viewModel.scanInstalledStatus(force: true)
        await viewModel.scanLocalApplications()
        viewModel.navigateTo(.installed)

        let snapshot = viewModel.installedSnapshot
        let count = (snapshot?.formulae.count ?? 0)
            + (snapshot?.casks.count ?? 0)
            + (snapshot?.masApps.count ?? 0)
        let outdated = viewModel.outdatedCount

        return .result(dialog: "扫描完成：已装 \(count) 项，\(outdated) 项可更新。")
    }
}

struct SelectKiduxRoleIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "选择开发岗位" }
    nonisolated static var description: IntentDescription {
        IntentDescription("在 Kidux 中选择岗位并打开工具清单。")
    }
    nonisolated static var openAppWhenRun: Bool { true }

    @Parameter(title: "岗位名称或 ID")
    var roleQuery: String

    static var parameterSummary: some ParameterSummary {
        Summary("选择 \(\.$roleQuery) 岗位")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try AppIntentBridge.shared.requireViewModel()
        let query = roleQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return .result(dialog: "请提供岗位名称，例如「前端」或 frontend_developer。")
        }

        let roles = viewModel.bundleManager.roles
        let matched = roles.first { role in
            role.id.lowercased() == query
                || role.name.lowercased() == query
                || role.name.lowercased().contains(query)
                || role.id.replacingOccurrences(of: "_", with: " ").contains(query)
        }

        guard let role = matched else {
            return .result(dialog: "未找到岗位「\(roleQuery)」。请在 Kidux 岗位页查看完整列表。")
        }

        if viewModel.settings.allowMultipleRoles {
            viewModel.selectedRoles.insert(role.id)
        } else {
            viewModel.selectedRoles = [role.id]
        }
        viewModel.refreshResolvedTools()
        viewModel.navigateTo(.roles)
        viewModel.currentScreen = .bundleDetail

        return .result(dialog: "已选择岗位「\(role.name)」，工具清单已打开。")
    }
}

struct ExportKiduxSnapshotIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "导出环境快照" }
    nonisolated static var description: IntentDescription {
        IntentDescription("导出 Kidux 环境快照 JSON 到文稿目录。")
    }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try AppIntentBridge.shared.requireViewModel()
        guard let path = await viewModel.exportEnvironmentSnapshotToDocuments() else {
            return .result(dialog: "快照导出失败，请在 Kidux 环境页重试。")
        }
        viewModel.navigateTo(.environment)
        return .result(dialog: "快照已导出：\(path)")
    }
}

// MARK: - S20-02 App Intents 扩展

struct InstallKiduxRoleIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "安装岗位工具" }
    nonisolated static var description: IntentDescription {
        IntentDescription("选择岗位并安装对应工具清单。")
    }
    nonisolated static var openAppWhenRun: Bool { true }

    @Parameter(title: "岗位名称或 ID")
    var roleQuery: String

    @Parameter(title: "仅预览不安装", default: false)
    var previewOnly: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("安装 \(\.$roleQuery) 岗位")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try AppIntentBridge.shared.requireViewModel()
        let outcome = await viewModel.performRoleInstallIntent(
            query: roleQuery,
            previewOnly: previewOnly
        )
        return .result(dialog: IntentDialog(stringLiteral: outcome))
    }
}

struct UpgradeOutdatedIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "升级可更新软件" }
    nonisolated static var description: IntentDescription {
        IntentDescription("扫描并升级 Homebrew / App Store 可更新项。")
    }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try AppIntentBridge.shared.requireViewModel()
        let message = await viewModel.performUpgradeOutdatedIntent()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct CheckEnvironmentDriftIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "检查环境漂移" }
    nonisolated static var description: IntentDescription {
        IntentDescription("对比环境基准并报告漂移摘要。")
    }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try AppIntentBridge.shared.requireViewModel()
        let message = await viewModel.performEnvironmentDriftCheckIntent()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// S20-06 — Shortcuts：在发现页搜索软件
struct SearchKiduxCatalogIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "在 Kidux 中搜索" }
    nonisolated static var description: IntentDescription {
        IntentDescription("打开发现页并搜索指定软件名或关键词。")
    }
    nonisolated static var openAppWhenRun: Bool { true }

    @Parameter(title: "关键词")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("在 Kidux 中搜索 \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try AppIntentBridge.shared.requireViewModel()
        viewModel.openDiscoverSearch(query: query)
        return .result(dialog: "已搜索「\(query)」")
    }
}

/// S20-09 — 开发者专注链：选岗 + 模拟安装预览
struct DryRunKiduxRoleIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "模拟安装岗位" }
    nonisolated static var description: IntentDescription {
        IntentDescription("选择岗位并打开模拟安装预览，不会真正安装。")
    }
    nonisolated static var openAppWhenRun: Bool { true }

    @Parameter(title: "岗位名称或 ID")
    var roleQuery: String

    static var parameterSummary: some ParameterSummary {
        Summary("模拟安装 \(\.$roleQuery) 岗位")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let viewModel = try AppIntentBridge.shared.requireViewModel()
        let message = await viewModel.performRoleInstallIntent(query: roleQuery, previewOnly: true)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct KiduxAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanInstalledAppsIntent(),
            phrases: [
                "Scan installed apps in \(.applicationName)",
                "用 \(.applicationName) 扫描已装软件"
            ],
            shortTitle: "扫描已装",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: SelectKiduxRoleIntent(),
            phrases: [
                "Select role in \(.applicationName)",
                "在 \(.applicationName) 选择岗位"
            ],
            shortTitle: "选择岗位",
            systemImageName: "person.crop.rectangle.stack"
        )
        AppShortcut(
            intent: ExportKiduxSnapshotIntent(),
            phrases: [
                "Export environment snapshot in \(.applicationName)",
                "用 \(.applicationName) 导出环境快照"
            ],
            shortTitle: "导出快照",
            systemImageName: "square.and.arrow.up"
        )
        AppShortcut(
            intent: InstallKiduxRoleIntent(),
            phrases: [
                "Install role in \(.applicationName)",
                "用 \(.applicationName) 安装岗位工具",
                "在 \(.applicationName) 安装前端岗位"
            ],
            shortTitle: "安装岗位",
            systemImageName: "arrow.down.circle"
        )
        AppShortcut(
            intent: UpgradeOutdatedIntent(),
            phrases: [
                "Upgrade outdated apps in \(.applicationName)",
                "用 \(.applicationName) 升级可更新软件"
            ],
            shortTitle: "升级软件",
            systemImageName: "arrow.up.circle"
        )
        AppShortcut(
            intent: CheckEnvironmentDriftIntent(),
            phrases: [
                "Check environment drift in \(.applicationName)",
                "用 \(.applicationName) 检查环境漂移"
            ],
            shortTitle: "检查漂移",
            systemImageName: "exclamationmark.triangle"
        )
        AppShortcut(
            intent: SearchKiduxCatalogIntent(),
            phrases: [
                "Search catalog in \(.applicationName)",
                "在 \(.applicationName) 中搜索软件"
            ],
            shortTitle: "搜索软件",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: DryRunKiduxRoleIntent(),
            phrases: [
                "Dry run role in \(.applicationName)",
                "用 \(.applicationName) 模拟安装岗位"
            ],
            shortTitle: "模拟安装",
            systemImageName: "eye"
        )
    }
}

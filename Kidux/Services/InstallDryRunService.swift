import Foundation

struct InstallDryRunItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let command: String
    let sourceLabel: String
    let willSkip: Bool
    let isManual: Bool
    let warnings: [String]
}

struct InstallDryRunPlan: Sendable {
    let items: [InstallDryRunItem]
    let postInstallSteps: [PostInstallStep]
    let skippedCount: Int
    let manualCount: Int
    let executableCount: Int
    let preflight: InstallPreflightReport?

    var summaryLine: String {
        var parts: [String] = ["将执行 \(executableCount) 步"]
        if skippedCount > 0 { parts.append("跳过 \(skippedCount)") }
        if manualCount > 0 { parts.append("手动 \(manualCount)") }
        return parts.joined(separator: " · ")
    }

    init(
        items: [InstallDryRunItem],
        postInstallSteps: [PostInstallStep],
        skippedCount: Int,
        manualCount: Int,
        executableCount: Int,
        preflight: InstallPreflightReport? = nil
    ) {
        self.items = items
        self.postInstallSteps = postInstallSteps
        self.skippedCount = skippedCount
        self.manualCount = manualCount
        self.executableCount = executableCount
        self.preflight = preflight
    }
}

/// S18-16 — 模拟安装链预览（不执行 brew/mas）
enum InstallDryRunService {
    static func buildPlan(
        tools: [ResolvedTool],
        postInstallSteps: [PostInstallStep],
        enableMAS: Bool,
        skipInstalled: Bool,
        snapshot: InstalledStatusSnapshot?
    ) -> InstallDryRunPlan {
        let selected = tools.filter(\.isSelected).sorted { $0.tool.priority < $1.tool.priority }
        var items: [InstallDryRunItem] = []

        for resolved in selected {
            let tool = resolved.tool
            let state = snapshot?.state(for: tool) ?? .unknown
            let willSkip = skipInstalled && state == .installed
            let command = installCommand(for: tool, enableMAS: enableMAS)
            let isManual = tool.source.type == .link || command.isEmpty
            var warnings: [String] = []
            if tool.source.type == .mas, !enableMAS {
                warnings.append("App Store 安装已在设置中关闭")
            }
            if tool.source.type == .script {
                warnings.append("将执行内置脚本：\(tool.source.identifier)")
            }
            if tool.source.type == .link {
                warnings.append("需手动下载安装")
            }

            items.append(
                InstallDryRunItem(
                    id: tool.id,
                    name: tool.name,
                    command: command.isEmpty ? "（无自动命令）" : command,
                    sourceLabel: sourceLabel(for: tool.source.type),
                    willSkip: willSkip,
                    isManual: isManual,
                    warnings: warnings
                )
            )
        }

        let skipped = items.filter(\.willSkip).count
        let manual = items.filter(\.isManual).count
        let executable = items.filter { !$0.willSkip && !$0.isManual }.count

        return InstallDryRunPlan(
            items: items,
            postInstallSteps: postInstallSteps,
            skippedCount: skipped,
            manualCount: manual,
            executableCount: executable
        )
    }

    private static func installCommand(for tool: DevTool, enableMAS: Bool) -> String {
        switch tool.source.type {
        case .formula:
            return "brew install \(tool.source.identifier)"
        case .cask:
            return "brew install --cask \(tool.source.identifier)"
        case .mas:
            guard enableMAS else { return "" }
            return "mas install \(tool.source.identifier)"
        case .script:
            return "bash Resources/scripts/\(tool.source.identifier)"
        case .link:
            return tool.resolvedHomepage ?? tool.source.identifier
        }
    }

    private static func sourceLabel(for type: InstallSourceType) -> String {
        switch type {
        case .formula: return "formula"
        case .cask: return "cask"
        case .mas: return "App Store"
        case .script: return "script"
        case .link: return "外链"
        }
    }
}

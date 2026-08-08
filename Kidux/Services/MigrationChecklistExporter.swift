import Foundation

/// S16-07 换机 checklist Markdown 导出
enum MigrationChecklistExporter {
    struct Input: Sendable {
        let roleNames: [String]
        let selectedTools: [ResolvedTool]
        let postInstallSteps: [PostInstallStep]
        let driftReport: EnvironmentDriftReport?
        let driftBaselineLabel: String?
        let installedSnapshot: InstalledStatusSnapshot?
        let mackupInstalled: Bool
    }

    static func generate(_ input: Input) -> String {
        let exportedAt = isoTimestamp()
        var lines: [String] = [
            "# \(BrandInfo.displayNameCN) 换机清单",
            "",
            "> 导出时间：\(exportedAt) · \(AppInfo.displayVersion) · \(BrandInfo.generatedBy)",
            ""
        ]

        if input.roleNames.isEmpty {
            lines.append("**岗位**：未选择")
        } else {
            lines.append("**岗位**：\(input.roleNames.joined(separator: "、"))")
        }
        lines.append("")

        lines += installableSection(input)
        lines += manualSection(input)
        lines += driftSection(input)
        lines += postInstallSection(input)
        lines += nextStepsSection()

        return lines.joined(separator: "\n")
    }

    private static func installableSection(_ input: Input) -> [String] {
        let selected = input.selectedTools.filter(\.isSelected)
        let installable = selected.filter { $0.tool.source.type != .link }
        guard !installable.isEmpty else { return [] }

        var lines: [String] = [
            "## 1. 一键安装（brew / mas / 脚本）",
            ""
        ]

        for resolved in installable.sorted(by: { $0.tool.name.localizedCaseInsensitiveCompare($1.tool.name) == .orderedAscending }) {
            let tool = resolved.tool
            let state = input.installedSnapshot?.state(for: tool) ?? .unknown
            let checked = state == .installed
            let marker = checked ? "x" : " "
            let source = sourceLabel(for: tool)
            let required = resolved.isRequired ? " · 必选" : ""
            lines.append("- [\(marker)] **\(tool.name)** — \(source)\(required)")
        }
        lines.append("")
        return lines
    }

    private static func manualSection(_ input: Input) -> [String] {
        let manual = input.selectedTools.filter { $0.isSelected && $0.tool.source.type == .link }
        guard !manual.isEmpty else { return [] }

        var lines: [String] = [
            "## 2. 需手动安装",
            "",
            "以下工具需从官网下载，Kidux 无法一键安装：",
            ""
        ]

        for resolved in manual.sorted(by: { $0.tool.name.localizedCaseInsensitiveCompare($1.tool.name) == .orderedAscending }) {
            let tool = resolved.tool
            lines.append("- [ ] **\(tool.name)** — 官网 / 手动下载")
            if !tool.description.isEmpty {
                lines.append("  - \(tool.description)")
            }
        }
        lines.append("")
        return lines
    }

    private static func driftSection(_ input: Input) -> [String] {
        guard let report = input.driftReport else {
            if let label = input.driftBaselineLabel, !label.isEmpty {
                return [
                    "## 3. 环境漂移",
                    "",
                    "基准：\(label)（导出时未执行对比，可在环境页重新对比后再次导出）",
                    ""
                ]
            }
            return [
                "## 3. 环境漂移",
                "",
                "尚未设置漂移基准。建议在环境页「设为基准」或导出 v3 快照后再对比。",
                ""
            ]
        }

        var lines: [String] = [
            "## 3. 环境漂移",
            ""
        ]
        if let label = input.driftBaselineLabel, !label.isEmpty {
            lines.append("基准：\(label)")
        }
        lines.append("对比时间：\(report.comparedAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("")

        if !report.hasDrift {
            lines.append("✅ 与基准一致，未检测到漂移。")
            lines.append("")
            return lines
        }

        lines.append("**\(report.summaryLine)**")
        lines.append("")
        for item in report.items {
            let kind = driftKindLabel(item.kind)
            lines.append("- **\(kind)** · `\(item.title)` — \(item.detail)")
        }
        lines.append("")
        return lines
    }

    private static func postInstallSection(_ input: Input) -> [String] {
        var lines: [String] = [
            "## 4. 安装后配置",
            ""
        ]

        if input.postInstallSteps.isEmpty {
            lines.append("- 当前岗位无额外安装后脚本。")
        } else {
            for step in input.postInstallSteps {
                lines.append("- [ ] **\(step.name)**")
            }
        }

        lines.append("")
        lines.append("### Mackup 设置备份（可选）")
        if input.mackupInstalled {
            lines.append("- [x] 已安装 mackup — 换机前运行 `mackup backup`，新机 `mackup restore`")
        } else {
            lines.append("- [ ] 安装 [Mackup](https://github.com/lra/mackup) 备份 VS Code、iTerm 等偏好")
        }
        lines.append("")
        lines.append("> \(MackupGuideService.guideText.split(separator: "\n").first.map(String.init) ?? "")")
        lines.append("")
        return lines
    }

    private static func nextStepsSection() -> [String] {
        [
            "## 5. 建议下一步",
            "",
            "1. 在旧 Mac 导出 **v3 环境快照**（设置 → 环境快照）",
            "2. 在新 Mac 导入快照并「设为漂移基准」",
            "3. 运行 **bootstrap.sh** 或 Kidux 内「开始安装」",
            "4. 完成手动项与 Mackup 恢复",
            ""
        ]
    }

    private static func sourceLabel(for tool: DevTool) -> String {
        switch tool.source.type {
        case .formula: return "brew formula · \(tool.source.identifier)"
        case .cask: return "brew cask · \(tool.source.identifier)"
        case .mas: return "App Store · \(tool.source.identifier)"
        case .script: return "脚本"
        case .link: return "手动"
        }
    }

    private static func driftKindLabel(_ kind: EnvironmentDriftItem.Kind) -> String {
        switch kind {
        case .missing: return "缺失"
        case .extra: return "多出"
        case .changed: return "变更"
        }
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

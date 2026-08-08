import Foundation

enum CommandPaletteCommandKind: Sendable {
    case navigate(AppTab)
    case scanUpdates
    case exportChecklist
    case openMigrationWizard
    case openDiscoverSearch
}

struct CommandPaletteCommand: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let keywords: [String]
    let kind: CommandPaletteCommandKind
}

enum CommandPaletteRegistry {
    static let all: [CommandPaletteCommand] = [
        CommandPaletteCommand(
            id: "nav.home",
            title: "前往首页",
            subtitle: "欢迎页与快捷入口",
            systemImage: "house",
            keywords: ["首页", "欢迎", "home"],
            kind: .navigate(.home)
        ),
        CommandPaletteCommand(
            id: "nav.assistant",
            title: "打开 AI 问答",
            subtitle: "智能安装助手",
            systemImage: "sparkles",
            keywords: ["AI", "问答", "助手"],
            kind: .navigate(.assistant)
        ),
        CommandPaletteCommand(
            id: "nav.roles",
            title: "前往岗位配置",
            subtitle: "选择开发岗位与工具包",
            systemImage: "person.crop.rectangle.stack",
            keywords: ["岗位", "角色", "bundle"],
            kind: .navigate(.roles)
        ),
        CommandPaletteCommand(
            id: "nav.discover",
            title: "浏览软件库",
            subtitle: "发现页 · 内置目录与 Homebrew",
            systemImage: "square.grid.2x2",
            keywords: ["发现", "软件库", "catalog", "brew"],
            kind: .navigate(.discover)
        ),
        CommandPaletteCommand(
            id: "nav.installed",
            title: "查看已安装",
            subtitle: "维护、更新与依赖树",
            systemImage: "checkmark.circle",
            keywords: ["已装", "维护", "更新"],
            kind: .navigate(.installed)
        ),
        CommandPaletteCommand(
            id: "nav.environment",
            title: "打开环境页",
            subtitle: "运行时、漂移与版本管理器",
            systemImage: "terminal",
            keywords: ["环境", "漂移", "mise", "nvm", "path"],
            kind: .navigate(.environment)
        ),
        CommandPaletteCommand(
            id: "nav.settings",
            title: "打开设置",
            subtitle: "镜像、AI 与偏好",
            systemImage: "gearshape",
            keywords: ["设置", "偏好", "镜像"],
            kind: .navigate(.settings)
        ),
        CommandPaletteCommand(
            id: "action.scanUpdates",
            title: "检查软件更新",
            subtitle: "扫描 Homebrew / mas 可更新项",
            systemImage: "arrow.triangle.2.circlepath",
            keywords: ["更新", "outdated", "升级"],
            kind: .scanUpdates
        ),
        CommandPaletteCommand(
            id: "action.exportChecklist",
            title: "导出换机清单",
            subtitle: "Markdown 待办与漂移摘要",
            systemImage: "doc.text",
            keywords: ["导出", "换机", "checklist", "清单"],
            kind: .exportChecklist
        ),
        CommandPaletteCommand(
            id: "action.migrationWizard",
            title: "打开换机向导",
            subtitle: "新机导入或旧机导出引导",
            systemImage: "arrow.left.arrow.right",
            keywords: ["换机", "向导", "迁移", "wizard"],
            kind: .openMigrationWizard
        ),
        CommandPaletteCommand(
            id: "action.discoverSearch",
            title: "搜索软件库",
            subtitle: "跳转到发现页并聚焦搜索",
            systemImage: "magnifyingglass",
            keywords: ["搜索", "查找", "search"],
            kind: .openDiscoverSearch
        ),
    ]

    static func filtered(query: String) -> [CommandPaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }

        let tokens = trimmed
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return all.filter { command in
            let haystack = ([command.title, command.subtitle ?? ""] + command.keywords)
                .joined(separator: " ")
                .lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}

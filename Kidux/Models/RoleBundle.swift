import Foundation

struct PostInstallStep: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let script: String
    let skipIf: String?

    init(id: String? = nil, name: String, script: String, skipIf: String? = nil) {
        self.id = id ?? script
        self.name = name
        self.script = script
        self.skipIf = skipIf
    }
}

struct RoleBundle: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let version: String
    let includes: [String]?
    let tools: [ToolReference]
    let postInstall: [PostInstallStep]?
    /// S19-05 — 岗位新人必读（Markdown 纯文本）
    let readme: String?

    var toolCount: Int { tools.count }

    var hasReadme: Bool {
        guard let readme else { return false }
        return !readme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: String,
        name: String,
        description: String,
        icon: String,
        version: String,
        includes: [String]?,
        tools: [ToolReference],
        postInstall: [PostInstallStep]? = nil,
        readme: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.version = version
        self.includes = includes
        self.tools = tools
        self.postInstall = postInstall
        self.readme = readme
    }
}

struct ToolCatalog: Codable, Sendable {
    let version: String
    let tools: [DevTool]
}

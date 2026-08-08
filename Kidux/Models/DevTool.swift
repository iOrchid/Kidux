import Foundation

enum InstallSourceType: String, Codable, Sendable {
    case formula
    case cask
    case mas
    case script
    /// 官网 / GitHub 等外链，应用内引导用户手动下载安装
    case link
}

enum ToolKind: String, Codable, Sendable {
    case cli
    case gui
}

struct InstallSource: Codable, Sendable, Hashable {
    let type: InstallSourceType
    let identifier: String
    let args: [String]?

    init(type: InstallSourceType, identifier: String, args: [String]? = nil) {
        self.type = type
        self.identifier = identifier
        self.args = args
    }

    /// script 类型时 args[0] 可作为 skip_if 条件表达式
    var skipIf: String? { args?.first }
}

struct DevTool: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let description: String
    let category: String
    let kind: ToolKind?
    let source: InstallSource
    let required: Bool
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, kind, source, required, priority
        case homepage, iconURL, longDescription, screenshots, tags, sourceLevel, installable
    }

    let homepage: String?
    let iconURL: String?
    let longDescription: String?
    let screenshots: [String]?
    let tags: [String]?
    let sourceLevel: String?
    let installable: Bool?

    /// 是否可在应用内一键安装（link 类型默认需手动安装）
    var isInAppInstallable: Bool {
        if let installable { return installable }
        return source.type != .link
    }

    var displayDescription: String {
        longDescription ?? description
    }

    var resolvedHomepage: String? {
        homepage
    }

    var resolvedKind: ToolKind {
        if let kind { return kind }
        switch source.type {
        case .formula, .script, .link:
            return .cli
        case .cask, .mas:
            return .gui
        }
    }

    init(
        id: String,
        name: String,
        description: String,
        category: String,
        kind: ToolKind? = nil,
        source: InstallSource,
        required: Bool = false,
        priority: Int = 50,
        homepage: String? = nil,
        iconURL: String? = nil,
        longDescription: String? = nil,
        screenshots: [String]? = nil,
        tags: [String]? = nil,
        sourceLevel: String? = nil,
        installable: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.kind = kind
        self.source = source
        self.required = required
        self.priority = priority
        self.homepage = homepage
        self.iconURL = iconURL
        self.longDescription = longDescription
        self.screenshots = screenshots
        self.tags = tags
        self.sourceLevel = sourceLevel
        self.installable = installable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        category = try container.decode(String.self, forKey: .category)
        kind = try container.decodeIfPresent(ToolKind.self, forKey: .kind)
        source = try container.decode(InstallSource.self, forKey: .source)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 50
        homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
        longDescription = try container.decodeIfPresent(String.self, forKey: .longDescription)
        screenshots = try container.decodeIfPresent([String].self, forKey: .screenshots)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        sourceLevel = try container.decodeIfPresent(String.self, forKey: .sourceLevel)
        installable = try container.decodeIfPresent(Bool.self, forKey: .installable)
    }
}

struct ToolReference: Codable, Sendable {
    let ref: String
    let required: Bool?
}

struct ResolvedTool: Identifiable, Sendable, Hashable {
    let tool: DevTool
    let isRequired: Bool
    var isSelected: Bool

    var id: String { tool.id }

    init(tool: DevTool, isRequired: Bool, isSelected: Bool = true) {
        self.tool = tool
        self.isRequired = isRequired
        self.isSelected = isSelected
    }
}

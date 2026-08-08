import Foundation

enum ToolCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case infra
    case terminal
    case editor
    case language
    case devops
    case database
    case browser
    case collab
    case design
    case product
    case utility
    case media
    case security

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .infra: return "基础设施"
        case .terminal: return "终端工具"
        case .editor: return "编辑器"
        case .language: return "语言运行时"
        case .devops: return "DevOps"
        case .database: return "数据库"
        case .browser: return "浏览器"
        case .collab: return "协作沟通"
        case .design: return "设计工具"
        case .product: return "产品工具"
        case .utility: return "效率工具"
        case .media: return "媒体娱乐"
        case .security: return "安全隐私"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .infra: return "gearshape.2"
        case .terminal: return "terminal"
        case .editor: return "chevron.left.forwardslash.chevron.right"
        case .language: return "curlybraces"
        case .devops: return "shippingbox"
        case .database: return "cylinder"
        case .browser: return "globe"
        case .collab: return "bubble.left.and.bubble.right"
        case .design: return "paintbrush"
        case .product: return "lightbulb"
        case .utility: return "sparkles"
        case .media: return "play.circle"
        case .security: return "lock.shield"
        }
    }

    static func label(for category: String) -> String {
        ToolCategory(rawValue: category)?.displayName ?? category
    }
}

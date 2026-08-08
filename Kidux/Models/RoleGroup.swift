import Foundation

enum RoleGroup: String, CaseIterable, Identifiable, Sendable {
    case starter
    case product
    case design
    case engineering
    case mobile
    case data
    case quality
    case infra

    var id: String { rawValue }

    var title: String {
        switch self {
        case .starter: return "入门学习"
        case .product: return "产品运营"
        case .design: return "设计创意"
        case .engineering: return "研发工程"
        case .mobile: return "移动开发"
        case .data: return "数据智能"
        case .quality: return "质量安全"
        case .infra: return "运维部署"
        }
    }

    var icon: String {
        switch self {
        case .starter: return "graduationcap"
        case .product: return "chart.bar.doc.horizontal"
        case .design: return "paintbrush.pointed"
        case .engineering: return "chevron.left.forwardslash.chevron.right"
        case .mobile: return "iphone.gen3"
        case .data: return "chart.dots.scatter"
        case .quality: return "checkmark.shield"
        case .infra: return "server.rack"
        }
    }

    static func group(for roleID: String) -> RoleGroup {
        switch roleID {
        case "student_starter":
            return .starter
        case "product_manager", "operations_specialist":
            return .product
        case "designer":
            return .design
        case "frontend_developer", "backend_developer", "fullstack_developer",
             "java_developer", "python_developer", "golang_developer", "ai_developer":
            return .engineering
        case "ios_developer", "android_developer", "mobile_developer":
            return .mobile
        case "data_analyst", "data_engineer", "algorithm_engineer":
            return .data
        case "qa_engineer", "security_engineer":
            return .quality
        case "devops_engineer", "sre_engineer":
            return .infra
        default:
            return .engineering
        }
    }
}

extension RoleBundle {
    var group: RoleGroup { RoleGroup.group(for: id) }
}

import Foundation

/// S16-02 换机向导：旧机导出 vs 新机导入
enum MigrationMacRole: String, CaseIterable, Identifiable, Sendable {
    case source
    case target

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "旧 Mac（导出）"
        case .target: return "新 Mac（导入）"
        }
    }

    var subtitle: String {
        switch self {
        case .source: return "导出 v3 快照与换机清单，拷贝到新电脑"
        case .target: return "导入同事或旧机的 Bundle，一键恢复岗位与工具"
        }
    }

    var icon: String {
        switch self {
        case .source: return "arrow.up.doc"
        case .target: return "arrow.down.doc"
        }
    }
}

enum MigrationWizardStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case exportSnapshot
    case importSnapshot
    case reviewBundle
    case finish

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "选择场景"
        case .exportSnapshot: return "导出快照"
        case .importSnapshot: return "导入快照"
        case .reviewBundle: return "确认清单"
        case .finish: return "完成"
        }
    }

    static func steps(for role: MigrationMacRole) -> [MigrationWizardStep] {
        switch role {
        case .source:
            return [.welcome, .exportSnapshot, .finish]
        case .target:
            return [.welcome, .importSnapshot, .reviewBundle, .finish]
        }
    }
}

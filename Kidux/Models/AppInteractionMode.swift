import Foundation

/// 应用交互模式：经典侧栏 vs 全屏沉浸对话
enum AppInteractionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "经典模式"
        case .ai: return "沉浸对话模式"
        }
    }

    var enterLabel: String {
        switch self {
        case .classic: return "经典模式"
        case .ai: return "沉浸对话"
        }
    }

    var enterIcon: String {
        switch self {
        case .classic: return "square.grid.2x2"
        case .ai: return "bubble.left.and.bubble.right"
        }
    }
}

import SwiftUI

/// S16-06 菜单栏环境健康聚合状态
enum MenuBarHealthStatus: Sendable, Equatable {
    case gray
    case green
    case yellow
    case red

    var color: Color {
        switch self {
        case .gray: return .secondary
        case .green: return .green
        case .yellow: return .orange
        case .red: return .red
        }
    }

    var summaryLine: String {
        switch self {
        case .gray: return "环境未扫描"
        case .green: return "环境正常"
        case .yellow: return "有待关注项"
        case .red: return "环境异常"
        }
    }
}

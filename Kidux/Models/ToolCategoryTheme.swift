import SwiftUI
import AppKit

enum ToolCategoryTheme {
    static func swiftUIColor(for category: String) -> Color {
        switch category {
        case "infra": return Color(white: 0.42)
        case "terminal": return Color(white: 0.22)
        case "editor": return .blue
        case "language": return .purple
        case "devops": return .teal
        case "database": return .orange
        case "browser": return .cyan
        case "collab": return .mint
        case "design": return .pink
        case "product": return .yellow
        case "utility": return .indigo
        case "media": return .red
        case "security": return .green
        default: return .gray
        }
    }

    static func nsColor(for category: String) -> NSColor {
        switch category {
        case "infra": return NSColor(red: 0.35, green: 0.38, blue: 0.45, alpha: 1)
        case "terminal": return NSColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1)
        case "editor": return NSColor(red: 0.12, green: 0.45, blue: 0.85, alpha: 1)
        case "language": return NSColor(red: 0.55, green: 0.32, blue: 0.85, alpha: 1)
        case "devops": return NSColor(red: 0.18, green: 0.55, blue: 0.45, alpha: 1)
        case "database": return NSColor(red: 0.85, green: 0.45, blue: 0.18, alpha: 1)
        case "browser": return NSColor(red: 0.22, green: 0.55, blue: 0.95, alpha: 1)
        case "collab": return NSColor(red: 0.25, green: 0.65, blue: 0.55, alpha: 1)
        case "design": return NSColor(red: 0.92, green: 0.35, blue: 0.55, alpha: 1)
        case "product": return NSColor(red: 0.95, green: 0.62, blue: 0.15, alpha: 1)
        case "utility": return NSColor(red: 0.45, green: 0.50, blue: 0.95, alpha: 1)
        case "media": return NSColor(red: 0.88, green: 0.28, blue: 0.32, alpha: 1)
        case "security": return NSColor(red: 0.30, green: 0.55, blue: 0.30, alpha: 1)
        default: return NSColor(red: 0.40, green: 0.42, blue: 0.48, alpha: 1)
        }
    }

    static func symbol(for category: String, kind: ToolKind = .gui) -> String {
        ToolCategory(rawValue: category)?.icon ?? (kind == .cli ? "terminal" : "app")
    }
}

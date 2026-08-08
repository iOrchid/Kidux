import SwiftUI

struct ToolRowView: View {
    let tool: ResolvedTool
    let installState: ToolInstallState
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { tool.isSelected },
                set: { _ in onToggle() }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(tool.isRequired)
            .accessibilityLabel(tool.isSelected ? String(format: String(localized: "ui.ToolRowView.fmt.1d6b83fedf"), locale: .current, "\(tool.tool.name)") : String(format: String(localized: "ui.ToolRowView.fmt.179420053a"), locale: .current, "\(tool.tool.name)"))

            ToolIconView(tool: tool.tool, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.tool.name)
                        .font(.body)
                    if tool.isRequired {
                        ToolStatusTag(title: String(localized: "ui.ToolRowView.417973c15f"), color: .orange)
                    }
                    if installState == .installed {
                        ToolStatusTag(title: String(localized: "ui.ToolRowView.9d5bf2a10a"), color: .green)
                    }
                    ToolStatusTag(title: tool.tool.resolvedKind == .cli ? "CLI" : "GUI", color: .blue)
                }
                Text(tool.tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SourceBadge(source: tool.tool.source)
                .accessibilityLabel(String(format: String(localized: "ui.ToolRowView.fmt.c81e03ab93"), locale: .current, "\(tool.tool.source.type.rawValue)"))
        }
        .padding(.vertical, 4)
        .opacity(tool.isSelected ? 1 : 0.55)
    }
}

struct SourceBadge: View {
    let source: InstallSource

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2.weight(.semibold))
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .fixedSize()
    }

    private var label: String {
        switch source.type {
        case .formula: return "Formula"
        case .cask: return "Cask"
        case .mas: return "App Store"
        case .script: return String(localized: "ui.ToolRowView.ba311d8a6a")
        case .link: return String(localized: "ui.ToolRowView.9353dc3dc6")
        }
    }

    private var iconName: String {
        switch source.type {
        case .formula: return "terminal"
        case .cask: return "macwindow.on.rectangle"
        case .mas: return "bag"
        case .script: return "doc.text"
        case .link: return "link"
        }
    }

    private var foreground: Color {
        switch source.type {
        case .formula: return .orange
        case .cask: return .yellow
        case .mas: return .blue
        case .script: return .purple
        case .link: return .teal
        }
    }

    private var background: Color {
        foreground.opacity(0.14)
    }
}

#Preview {
    ToolRowView(
        tool: ResolvedTool(
            tool: DevTool(
                id: "iterm2",
                name: "iTerm2",
                description: String(localized: "ui.ToolRowView.0a30f1356b"),
                category: "terminal",
                source: InstallSource(type: .cask, identifier: "iterm2")
            ),
            isRequired: false
        ),
        installState: .installed,
        onToggle: {}
    )
    .padding()
    .frame(width: 500)
}

import SwiftUI

/// AI 对话与摘要的富文本排版（Markdown + 列表/段落间距）
struct AIFormattedText: View {
    let text: String
    var role: AIChatRole = .assistant
    var font: Font = .body

    var body: some View {
        Group {
            if role == .assistant, let rendered = Self.renderAssistantMarkdown(text) {
                Text(rendered)
            } else {
                Text(displayText)
            }
        }
        .font(font)
        .lineSpacing(role == .assistant ? 5 : 3)
        .multilineTextAlignment(role == .user ? .trailing : .leading)
        .textSelection(.enabled)
    }

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? " " : trimmed
    }

    static func renderAssistantMarkdown(_ source: String) -> AttributedString? {
        let normalized = normalizeAssistantMarkdown(source)
        guard !normalized.isEmpty else { return nil }

        guard var rendered = try? AttributedString(
            markdown: normalized,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) else { return nil }

        rendered.font = .body
        return rendered
    }

    static func normalizeAssistantMarkdown(_ source: String) -> String {
        var lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        lines = lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("• ") || trimmed.hasPrefix("· ") || trimmed.hasPrefix("● ") {
                return "- " + String(trimmed.dropFirst(2))
            }
            return line
        }

        var text = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return text
    }
}

// MARK: - 聊天气泡宽度策略

enum AIChatLayout {
    /// 单行/短句：气泡紧贴文字
    static func isCompactUserMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.contains("\n") && trimmed.count <= 42
    }

    /// 短回复（含操作按钮）：卡片随内容收缩
    static func isCompactAssistantMessage(
        text: String,
        hasRecommendations: Bool
    ) -> Bool {
        if hasRecommendations { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("\n- ") || trimmed.contains("\n* ") { return false }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > 4 { return false }
        return trimmed.count <= 140
    }
}

private struct AIChatWidthPolicy: ViewModifier {
    let compact: Bool
    let maxWidth: CGFloat
    var alignment: Alignment = .leading

    func body(content: Content) -> some View {
        if compact {
            content.fixedSize(horizontal: true, vertical: false)
        } else {
            content
                .frame(maxWidth: maxWidth, alignment: alignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 用户气泡

struct AIUserMessageBubble: View {
    let text: String
    var maxWidth: CGFloat = 300

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCompact: Bool {
        AIChatLayout.isCompactUserMessage(text)
    }

    var body: some View {
        Text(trimmed)
            .font(.body)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.14), lineWidth: 1)
            )
            .modifier(
                AIChatWidthPolicy(
                    compact: isCompact,
                    maxWidth: maxWidth,
                    alignment: .trailing
                )
            )
    }
}

// MARK: - 助手回复卡片

struct AIAssistantMessageCard<Content: View>: View {
    var maxWidth: CGFloat = 520
    var compact: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            .modifier(
                AIChatWidthPolicy(
                    compact: compact,
                    maxWidth: maxWidth,
                    alignment: .leading
                )
            )
    }
}

// MARK: - 紧凑操作按钮（绝不拉满行宽）

struct AICompactActionButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

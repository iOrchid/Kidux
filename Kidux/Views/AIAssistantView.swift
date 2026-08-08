import SwiftUI

struct AIAssistantView: View {
    @Environment(AppViewModel.self) private var viewModel
    var immersive: Bool = false

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    private let assistantBubbleMaxWidth: CGFloat = 520
    private let userBubbleMaxWidth: CGFloat = 300

    var body: some View {
        Group {
            if immersive {
                immersiveBody
            } else {
                AppPageScaffold(style: .ai, maxContentWidth: AppTheme.aiContentMaxWidth) {
                    immersiveBody
                }
            }
        }
        .onAppear {
            if viewModel.aiMessages.isEmpty {
                viewModel.aiMessages = [AIAssistantService.welcome]
            }
        }
    }

    private var immersiveBody: some View {
        VStack(spacing: 0) {
            if !immersive {
                classicHeader
                Divider().opacity(0.5)
            }
            chatArea
            inputSection
        }
    }

    private var classicHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            aiAvatar(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(BrandInfo.assistantName)
                    .font(.title2.bold())
                Text(viewModel.aiStatusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "ui.AIAssistantView.288f0c404c")) {
                viewModel.resetAIConversation()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 18)
    }

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    if immersive, viewModel.aiMessages.count <= 1 {
                        immersiveWelcome
                    }

                    ForEach(viewModel.aiMessages) { message in
                        if !message.isStreaming {
                            chatBubble(message)
                                .id(message.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 10)),
                                        removal: .opacity
                                    )
                                )
                        }
                    }

                    if viewModel.aiIsThinking {
                        thinkingRow
                            .id("ai-thinking")
                    }
                }
                .padding(.horizontal, immersive ? 24 : AppTheme.pageHorizontalPadding)
                .padding(.vertical, immersive ? 28 : 20)
                .frame(maxWidth: AppTheme.aiContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: viewModel.aiMessages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.aiIsThinking) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.aiStreamRevision) { _, _ in scrollToBottom(proxy) }
        }
        .onAppear {
            inputFocused = true
        }
    }

    private var immersiveWelcome: some View {
        VStack(spacing: 16) {
            BrandAppIcon(size: 64)
            Text(String(localized: "ui.AIAssistantView.61295bc6"))
                .font(.title.bold())
            Text(String(localized: "assistant.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !viewModel.settings.hasAIAPIKey {
                Text(String(localized: "ui.AIAssistantView.019133d9"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.22)) {
            if viewModel.aiIsThinking {
                proxy.scrollTo("ai-thinking", anchor: .bottom)
            } else if let last = viewModel.aiMessages.last(where: { !$0.isStreaming }) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var thinkingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            aiAvatar(size: 28)

            if viewModel.aiIsStreaming, let streaming = viewModel.aiMessages.last(where: { $0.isStreaming }) {
                AIAssistantMessageCard(
                    maxWidth: assistantBubbleMaxWidth,
                    compact: AIChatLayout.isCompactAssistantMessage(
                        text: streaming.text,
                        hasRecommendations: false
                    )
                ) {
                    HStack(alignment: .bottom, spacing: 6) {
                        AIFormattedText(text: streaming.text, role: .assistant)
                        streamingCursor
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "ui.AIAssistantView.4cd7a41809"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streamingCursor: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .opacity(viewModel.aiIsStreaming ? 1 : 0)
            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: viewModel.aiIsStreaming)
            .padding(.bottom, 3)
    }

    @ViewBuilder
    private func chatBubble(_ message: AIChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack(alignment: .top, spacing: 10) {
                Spacer(minLength: 0)
                userMessageBubble(message)
                userAvatar(size: 28)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                aiAvatar(size: 28)
                assistantMessageBubble(message)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .system:
            HStack(alignment: .top, spacing: 10) {
                aiAvatar(size: 28)
                systemMessageBubble(message)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func userMessageBubble(_ message: AIChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            AIUserMessageBubble(text: message.text, maxWidth: userBubbleMaxWidth)

            Text(message.timestamp, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func assistantMessageBubble(_ message: AIChatMessage) -> some View {
        let compact = AIChatLayout.isCompactAssistantMessage(
            text: message.text,
            hasRecommendations: !message.recommendedToolIDs.isEmpty
        )

        return VStack(alignment: .leading, spacing: 6) {
            AIAssistantMessageCard(
                maxWidth: assistantBubbleMaxWidth,
                compact: compact
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    AIFormattedText(text: message.text, role: .assistant)

                    if let label = message.actionLabel, let tab = message.actionTab {
                        assistantActionButton(label: label, tab: tab)
                    }

                    if !message.recommendedToolIDs.isEmpty {
                        assistantSectionDivider
                        AIRecommendationCards(toolIDs: message.recommendedToolIDs, embedded: true)
                    }
                }
            }

            Text(message.timestamp, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .fixedSize(horizontal: compact, vertical: false)
    }

    private func systemMessageBubble(_ message: AIChatMessage) -> some View {
        AIFormattedText(text: message.text, role: .assistant)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
            )
            .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func assistantActionButton(label: String, tab: AppTab) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            assistantSectionDivider
            HStack(spacing: 0) {
                AICompactActionButton(label: label) {
                    viewModel.navigateTo(tab)
                    if tab == .roles { viewModel.currentScreen = .roleSelection }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var assistantSectionDivider: some View {
        Divider().opacity(0.28)
    }

    private func aiAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentGradient)
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(.white.opacity(0.28), lineWidth: max(1, size * 0.04))
                .frame(width: size - 2, height: size - 2)
            BrandAppIcon(size: size * 0.62, showShadow: false)
        }
        .shadow(color: Color.accentColor.opacity(0.22), radius: size * 0.1, y: size * 0.03)
    }

    private func userAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: size, height: size)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var inputSection: some View {
        VStack(spacing: 12) {
            if !viewModel.aiSuggestedFollowUps.isEmpty, !viewModel.aiIsThinking {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "ui.AIAssistantView.012df30a22"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.aiSuggestedFollowUps, id: \.self) { prompt in
                                Button(prompt) { send(prompt) }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.primary.opacity(0.05), in: Capsule())
                                    .overlay(Capsule().stroke(AppTheme.cardStroke, lineWidth: 1))
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }

            AIInputBar(
                text: $inputText,
                placeholder: immersive
                    ? String(localized: "ui.AIAssistantView.2e08bc4ec3")
                    : String(localized: "ui.AIAssistantView.97c5f05e7f"),
                isGenerating: viewModel.aiIsThinking,
                onSubmit: submit,
                onStop: { viewModel.cancelAIGeneration() },
                focus: $inputFocused
            )

            HStack(spacing: 8) {
                Button {
                    viewModel.toggleAISpeechInput()
                } label: {
                    Label(
                        viewModel.isAISpeechListening ? String(localized: "ui.AIAssistantView.095e938e") : String(localized: "ui.AIAssistantView.48df356fae"),
                        systemImage: viewModel.isAISpeechListening ? "mic.fill" : "mic"
                    )
                }
                .buttonStyle(.bordered)
                .tint(viewModel.isAISpeechListening ? .red : nil)
                .disabled(viewModel.aiIsThinking)

                if let status = viewModel.aiSpeechStatus, viewModel.isAISpeechListening {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, immersive ? 24 : AppTheme.pageHorizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, immersive ? 20 : 16)
        .frame(maxWidth: AppTheme.aiContentMaxWidth)
        .frame(maxWidth: .infinity)
        .background {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, Color(nsColor: .windowBackgroundColor).opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                Color(nsColor: .windowBackgroundColor).opacity(0.92)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func submit() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !viewModel.aiIsThinking else { return }
        inputText = ""
        send(text)
    }

    private func send(_ text: String) {
        viewModel.sendAIMessage(text)
    }
}

private struct AIRecommendationCards: View {
    @Environment(AppViewModel.self) private var viewModel
    let toolIDs: [String]
    var embedded: Bool = false

    private var tools: [DevTool] {
        toolIDs.compactMap { viewModel.catalogTool(id: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !embedded {
                Text(String(localized: "ui.AIAssistantView.c566946b95"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Label(String(localized: "ui.AIAssistantView.c566946b95"), systemImage: "square.grid.2x2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(tools) { tool in
                HStack(spacing: 10) {
                    ToolIconView(tool: tool, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tool.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(tool.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { viewModel.discoverSelectedTools.contains(tool.id) },
                        set: { _ in viewModel.toggleDiscoverSelection(tool.id) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    Button(String(localized: "ui.AIAssistantView.e655a410")) {
                        Task { await viewModel.installDiscoverTool(tool) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!tool.isInAppInstallable)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if viewModel.discoverSelectedTools.count > 0 {
                HStack(spacing: 0) {
                    AICompactActionButton(label: String(format: String(localized: "ui.AIAssistantView.fmt.2598bc784c"), locale: .current, "\(viewModel.discoverSelectedTools.count)")) {
                        Task { await viewModel.installDiscoverSelection() }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

#Preview {
    AIAssistantView(immersive: true)
        .environment(AppViewModel())
        .frame(width: 800, height: 650)
}

import SwiftUI

/// 全屏 AI 沉浸布局（对话优先；其他模块通过 navigateTo 切回经典侧栏）
struct AIWorkspaceView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showAISettings = false

    var body: some View {
        AppPageScaffold(style: .ai) {
            VStack(spacing: 0) {
                aiTopBar
                Divider().opacity(0.45)
                AIAssistantView(immersive: true)
            }
        }
        .sheet(isPresented: $showAISettings) {
            AISettingsSheet()
        }
    }

    private var aiTopBar: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 10) {
                BrandAppIcon(size: 28, showShadow: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(BrandInfo.assistantName)
                        .font(.headline)
                    Text(viewModel.aiStatusSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 8) {
                if viewModel.outdatedCount > 0 {
                    Button {
                        viewModel.openInstalledUpdates()
                    } label: {
                        Label(String(format: String(localized: "ui.AIWorkspaceView.fmt.445556f7a8"), locale: .current, "\(viewModel.outdatedCount)"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    viewModel.resetAIConversation()
                } label: {
                    Label(String(localized: "ui.AIWorkspaceView.1ac07a4bb2"), systemImage: "plus.message")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.aiIsThinking)

                Button {
                    showAISettings = true
                } label: {
                    Label(String(localized: "ui.AIWorkspaceView.c6f186f75a"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                InteractionModeToggleButton(compact: true)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

#Preview {
    AIWorkspaceView()
        .environment(AppViewModel())
        .frame(width: 900, height: 700)
}

import SwiftUI
import AppKit

/// 可显示/隐藏的 API Key 输入框
struct SecureKeyField: View {
    @Binding var text: String
    var placeholder: String = "API Key"

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                } else {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                }
            }
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isRevealed ? String(localized: "ui.AIConfigurationForm.34db6c87dd") : String(localized: "ui.AIConfigurationForm.6f7f7b5467"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.cardStroke)
        )
    }
}

/// AI 配置表单（设置页 / AI 设置 Sheet 共用）
struct AIConfigurationForm: View {
    @Environment(AppViewModel.self) private var viewModel
    var compact: Bool = false

    var body: some View {
        let settings = viewModel.settings
        let provider = settings.aiProvider

        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            Label {
                Text(AppleIntelligenceSupport.catalogFilterStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: AppleIntelligenceSupport.isCatalogFilterAvailable ? "apple.intelligence" : "cpu")
                    .foregroundStyle(AppleIntelligenceSupport.isCatalogFilterAvailable ? Color.accentColor : .secondary)
            }

            Toggle(String(localized: "ui.AIConfigurationForm.8ca9385564"), isOn: Bindable(viewModel.settings).enableCloudAI)
            Text(String(localized: "ui.AIConfigurationForm.99803116b8"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(String(localized: "ui.AIConfigurationForm.79f09f89ec"), selection: Bindable(viewModel.settings).aiProvider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.subheadline.weight(.medium))
                SecureKeyField(
                    text: Bindable(viewModel.settings).aiAPIKey,
                    placeholder: provider.keyPlaceholder
                )
                if !settings.hasAIAPIKey {
                    Text("在 \(provider.displayName) 官网注册后创建 Key，粘贴到上方。岗位装软件不需要 Key。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: provider.consoleURL) {
                        Button("打开 \(provider.displayName) 控制台") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }

            if provider == .custom {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Base URL")
                        .font(.subheadline.weight(.medium))
                    TextField("https://api.example.com/v1", text: Bindable(viewModel.settings).aiCustomBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            if provider.modelPresets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "ui.AIConfigurationForm.afec32b8fc"))
                        .font(.subheadline.weight(.medium))
                    TextField("model-name", text: Bindable(viewModel.settings).aiModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            } else {
                Picker(String(localized: "ui.AIConfigurationForm.8000f187"), selection: Bindable(viewModel.settings).aiModel) {
                    ForEach(provider.resolvedModelPresets(customModel: settings.aiModel), id: \.id) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }

                if provider == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "ui.AIConfigurationForm.1eebd3f34b"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("model-name", text: Bindable(viewModel.settings).aiModel)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        let msg = await AIModelCatalogService.refreshFromRemote(force: true)
                        viewModel.aiModelCatalogStatus = msg
                    }
                } label: {
                    Label(String(localized: "ui.AIConfigurationForm.d04df05229"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(String(localized: "ui.AIConfigurationForm.dfb6cd01ff"))

                Text(viewModel.aiModelCatalogStatus ?? AIModelCatalogService.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Toggle(String(localized: "ui.AIConfigurationForm.e5debae97f"), isOn: Bindable(viewModel.settings).aiStreamEnabled)

            LabeledContent(String(localized: "ui.AIConfigurationForm.c9bf0b889a")) {
                HStack(spacing: 8) {
                    Slider(value: Bindable(viewModel.settings).aiTemperature, in: 0...1, step: 0.1)
                    Text(String(format: "%.1f", settings.aiTemperature))
                        .monospacedDigit()
                        .frame(width: 28)
                }
            }

            Stepper(
                String(format: String(localized: "ui.AIConfigurationForm.fmt.93aebe001c"), locale: .current, "\(settings.aiMaxTokens)"),
                value: Bindable(viewModel.settings).aiMaxTokens,
                in: 256...4096,
                step: 256
            )

            HStack(spacing: 12) {
                if settings.hasAIAPIKey {
                    Label(String(localized: "ui.AIConfigurationForm.e4a1feb49b"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Text(String(localized: "ui.AIConfigurationForm.671326f9a0"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "ui.AIConfigurationForm.69e74756")) {
                    viewModel.testAIConnection()
                }
                .disabled(!settings.hasAIAPIKey || viewModel.aiConnectionTestInProgress)
                Button(String(localized: "ui.AIConfigurationForm.250a1a297a")) {
                    if let url = URL(string: provider.consoleURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            if let result = viewModel.aiConnectionTestResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix(String(localized: "ui.AIConfigurationForm.b33199d32d")) ? .green : .orange)
            }

            Text(String(localized: "ui.AIConfigurationForm.5d9ab5a3"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AIConfigurationForm()
        .environment(AppViewModel())
        .padding()
        .frame(width: 520)
}

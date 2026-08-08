import SwiftUI

/// AI 模式内快速设置（无需切回工具台）
struct AISettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(String(localized: "ui.AISettingsSheet.2d18da59bb"), systemImage: "sparkles")
                    .font(.title2.bold())
                Spacer()
                Button(String(localized: "ui.AISettingsSheet.769d88e425")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                AIConfigurationForm(compact: true)
            }
        }
        .padding(24)
        .frame(width: 520, height: 560)
    }
}

#Preview {
    AISettingsSheet()
        .environment(AppViewModel())
}

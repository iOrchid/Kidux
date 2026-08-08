import SwiftUI

/// v1.0 — 启动后 brew 可更新提醒（固定高度，避免顶栏布局跳动）
struct UpdateReminderBanner: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        if viewModel.outdatedCount > 0, !viewModel.updateBannerDismissed {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(.orange)
                Text(String(format: String(localized: "ui.UpdateReminderBanner.fmt.1abf48f613"), locale: .current, "\(viewModel.outdatedCount)"))
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(String(localized: "ui.UpdateReminderBanner.607e7a4f37")) {
                    viewModel.openInstalledUpdates()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button {
                    viewModel.updateBannerDismissed = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .frame(height: 52, alignment: .center)
        }
    }
}

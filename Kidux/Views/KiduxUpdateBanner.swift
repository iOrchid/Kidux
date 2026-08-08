import SwiftUI

/// Kidux 自身新版本提醒
struct KiduxUpdateBanner: View {
    @Environment(AppViewModel.self) private var viewModel

    static let slotHeight: CGFloat = 52

    private var isVisible: Bool {
        viewModel.appUpdateInfo != nil && !viewModel.appUpdateBannerDismissed
    }

    var body: some View {
        Group {
            if let release = viewModel.appUpdateInfo, !viewModel.appUpdateBannerDismissed {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.app.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: String(localized: "ui.KiduxUpdateBanner.fmt.5a24e44709"), locale: .current, "\(BrandInfo.displayNameCN)", "\(release.version)"))
                            .font(.subheadline.weight(.medium))
                        Text(String(format: String(localized: "ui.KiduxUpdateBanner.fmt.b93b77fecd"), locale: .current, "\(AppInfo.marketingVersion)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "ui.KiduxUpdateBanner.f26ef91424")) {
                        viewModel.openKiduxDownloadPage()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button {
                        viewModel.appUpdateBannerDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, AppTheme.pageHorizontalPadding)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(format: String(localized: "ui.KiduxUpdateBanner.fmt.aab8e80b97"), locale: .current, "\(BrandInfo.displayNameCN)", "\(release.version)"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
    }
}

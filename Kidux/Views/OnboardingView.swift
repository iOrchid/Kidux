import SwiftUI

private struct OnboardingPage: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let subtitle: String
    let bullets: [String]
}

/// 首次启动三页引导（S11-03）
struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var pageIndex = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            icon: "person.3.fill",
            title: String(localized: "ui.OnboardingView.167bf28f82"),
            subtitle: String(localized: "ui.OnboardingView.5cee2e7098"),
            bullets: [
                String(localized: "ui.OnboardingView.28e32e8546"),
                String(localized: "ui.OnboardingView.d80e5f5259"),
                String(localized: "ui.OnboardingView.9cff4b630f")
            ]
        ),
        OnboardingPage(
            id: 1,
            icon: "square.grid.2x2.fill",
            title: String(localized: "ui.OnboardingView.7f9e586f8c"),
            subtitle: String(localized: "ui.OnboardingView.23b04fc8a3"),
            bullets: [
                String(localized: "ui.OnboardingView.ed3857bd77"),
                String(localized: "ui.OnboardingView.cfac991ce1"),
                String(localized: "ui.OnboardingView.530f960875")
            ]
        ),
        OnboardingPage(
            id: 2,
            icon: "sparkles",
            title: String(localized: "ui.OnboardingView.d777de2e63"),
            subtitle: String(localized: "ui.OnboardingView.a8df0635f0"),
            bullets: [
                String(localized: "ui.OnboardingView.3ac934f6d0"),
                String(localized: "ui.OnboardingView.068f11714b"),
                String(localized: "ui.OnboardingView.7228d90e5e")
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            pageContent(pages[pageIndex])
                .id(pageIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.easeInOut(duration: 0.25), value: pageIndex)

            pageIndicator
            Divider()
            bottomBar
        }
        .frame(minWidth: 540, minHeight: 480)
        .background(AppTheme.pageBackground(style: .classic))
    }

    private var topBar: some View {
        HStack {
            BrandAppIcon(size: 28)
            Text(BrandInfo.fullTitle)
                .font(.headline)
            Spacer()
            Button(String(localized: "ui.OnboardingView.92636e8c")) {
                onComplete()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func pageContent(_ page: OnboardingPage) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 52))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(AppTheme.accentGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(page.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.body)
                        Text(bullet)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardStroke)
            )

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages) { page in
                Capsule()
                    .fill(page.id == pageIndex ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: page.id == pageIndex ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: pageIndex)
            }
        }
        .padding(.vertical, 16)
    }

    private var bottomBar: some View {
        HStack {
            if pageIndex > 0 {
                Button(String(localized: "ui.OnboardingView.eeb6908870")) {
                    withAnimation { pageIndex -= 1 }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if pageIndex < pages.count - 1 {
                Button(String(localized: "ui.OnboardingView.38ce27d8")) {
                    withAnimation { pageIndex += 1 }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(String(localized: "ui.OnboardingView.85d22db7")) {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .frame(width: 640, height: 580)
}

import SwiftUI

struct DiscoverTrendingSection: View {
    @Environment(AppViewModel.self) private var viewModel

    let onShowDetail: (DevTool) -> Void
    let onInstall: (DevTool) -> Void

    private let trendingColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12)
    ]

    private var windowDays: TrendingWindowDays {
        viewModel.settings.trendingWindowDays
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppTheme.DiscoverSectionHeader(
                title: String(localized: "ui.DiscoverTrendingSection.82133ae7bb"),
                subtitle: String(format: String(localized: "ui.DiscoverTrendingSection.fmt.9498b817b8"), locale: .current, "\(windowDays.displayName)")
            )

            trendingContent
        }
    }

    @ViewBuilder
    private var trendingContent: some View {
        switch viewModel.brewTrendingLoadState {
        case .idle:
            if viewModel.brewTrendingItems.isEmpty {
                loadingRow
            } else {
                trendingCards
            }
        case .loading:
            if viewModel.brewTrendingItems.isEmpty {
                loadingRow
            } else {
                trendingCards
            }
        case .success:
            trendingCards
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(String(localized: "ui.DiscoverTrendingSection.132c5cdc")) {
                    viewModel.retryBrewTrending()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 8)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(String(localized: "discover.loading_trending"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var trendingCards: some View {
        LazyVGrid(columns: trendingColumns, alignment: .leading, spacing: 12) {
            ForEach(viewModel.brewTrendingItems) { item in
                trendingCard(item)
            }
        }
    }

    private func trendingCard(_ item: BrewTrendingItem) -> some View {
        let tool = item.asDevTool
        let installState = viewModel.installStateForCatalog(tool)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ToolIconView(tool: tool, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(item.sourceType == .formula ? "Formula" : "Cask")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if item.installCount > 0 {
                Text(String(format: String(localized: "ui.DiscoverTrendingSection.fmt.f335c677aa"), locale: .current, "\(windowDays.displayName)", "\(formattedCount(item.installCount))"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let velocity = item.velocity, velocity > 0 {
                Text(String(format: String(localized: "ui.trending.velocity"), locale: .current, "\(String(format: "%.1f", velocity))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(String(localized: "ui.DiscoverTrendingSection.f26225bd")) { onShowDetail(tool) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                AppTheme.AppStoreGetButton(
                    title: tool.installActionTitle(installState: installState),
                    isDisabled: installState == .installed && tool.isInAppInstallable
                ) {
                    onInstall(tool)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(AppTheme.cardStroke, lineWidth: 1)
        }
    }

    private func formattedCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

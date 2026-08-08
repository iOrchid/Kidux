import SwiftUI

/// App Store「精选」横滑分区：大标题 + 横向卡片行，无重复页级标题。
struct DiscoverFeaturedSection: View {
    @Environment(AppViewModel.self) private var viewModel

    let onShowDetail: (DevTool) -> Void
    let onInstall: (DevTool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(viewModel.featuredPickSections) { section in
                sectionBlock(section)
            }
        }
    }

    private func sectionBlock(_ section: ResolvedFeaturedSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.title3.weight(.bold))
                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(section.tools) { tool in
                        featuredCard(tool)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: DiscoverFeaturedLayout.rowHeight)
            .clipped()
        }
    }

    private func featuredCard(_ tool: DevTool) -> some View {
        let installState = viewModel.installStateForCatalog(tool)
        let isSelected = viewModel.discoverSelectedTools.contains(tool.id)
        let isInstalled = installState == .installed && tool.isInAppInstallable

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ToolIconView(tool: tool, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(tool.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                SourceBadge(source: tool.source)
                if isInstalled {
                    ToolStatusTag(title: String(localized: "ui.DiscoverFeaturedSection.c4a9649c89"), color: .green)
                }
                if isSelected {
                    ToolStatusTag(title: String(localized: "ui.DiscoverFeaturedSection.7bf54e288c"), color: .accentColor)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(String(localized: "ui.DiscoverFeaturedSection.f26225bd")) { onShowDetail(tool) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                AppTheme.AppStoreGetButton(
                    title: tool.installActionTitle(installState: installState),
                    isDisabled: isInstalled
                ) {
                    onInstall(tool)
                }
            }
        }
        .padding(14)
        .frame(width: 248, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : AppTheme.cardStroke, lineWidth: isSelected ? 2 : 1)
        }
        .contextMenu {
            Button(isSelected ? String(localized: "ui.DiscoverFeaturedSection.cc7008c275") : String(localized: "ui.DiscoverFeaturedSection.950c12eeb3")) {
                viewModel.toggleDiscoverSelection(tool.id)
            }
            Button(String(localized: "ui.DiscoverFeaturedSection.5b48dbb8dc")) { onShowDetail(tool) }
        }
    }
}

private enum DiscoverFeaturedLayout {
    static let rowHeight: CGFloat = 168
}

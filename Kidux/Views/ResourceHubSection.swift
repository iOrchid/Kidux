import SwiftUI
import AppKit

struct ResourceHubSection: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showDisclaimer = false
    @State private var references: [CommunityAppReference] = ExternalResourceHub.loadReferences()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if viewModel.settings.enableThirdPartySources {
                enabledContent
            } else {
                disabledCard
            }
        }
        .padding(.vertical, 12)
        .alert(String(localized: "ui.ResourceHubSection.0bac84503d"), isPresented: $showDisclaimer) {
            Button(String(localized: "ui.ResourceHubSection.625fb26b4b"), role: .cancel) {}
            Button(String(localized: "ui.ResourceHubSection.e6b0f358c5")) {
                viewModel.settings.acceptThirdPartyDisclaimer()
                viewModel.settings.enableThirdPartySources = true
            }
        } message: {
            Text(ExternalResourceHub.legalDisclaimer)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(String(localized: "ui.ResourceHubSection.ddba77724f"), systemImage: "link.circle")
                    .font(.title3.weight(.bold))
                Text(viewModel.settings.enableThirdPartySources
                     ? String(localized: "ui.ResourceHubSection.0a1e998e41")
                     : String(localized: "ui.ResourceHubSection.eb92bfd569"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !viewModel.settings.enableThirdPartySources {
                Button(String(localized: "ui.ResourceHubSection.cc42dd3170")) { showDisclaimer = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var disabledCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "ui.ResourceHubSection.6d4f345abe"))
                    .font(.subheadline.bold())
                Text(String(format: String(localized: "ui.ResourceHubSection.fmt.188eba314d"), locale: .current, "\(BrandInfo.displayNameCN)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var enabledContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            siteGrid
            referenceSection
        }
    }

    private var siteGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(ExternalResourceHub.sites) { site in
                Button {
                    if let url = URL(string: site.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(site.name)
                                .font(.subheadline.bold())
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(site.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        if let firstTag = site.tags.first {
                            Text(firstTag)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    firstTag == "开源" ? Color.green.opacity(0.12) : Color.orange.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(firstTag == "开源" ? .green : .orange)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.cardStroke)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "ui.ResourceHubSection.c5f906e127"))
                .font(.subheadline.bold())
            Text(String(format: String(localized: "ui.ResourceHubSection.fmt.ed9a037341"), locale: .current, "\(BrandInfo.displayNameCN)"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(references.prefix(8)) { ref in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ref.name)
                            .font(.body)
                        Text(ref.communityNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let catalogID = ref.officialCatalogID,
                       let tool = viewModel.allCatalogTools.first(where: { $0.id == catalogID }) {
                        Button(String(localized: "ui.ResourceHubSection.83ded71428")) {
                            Task { await viewModel.installDiscoverTool(tool) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if let homepage = ref.homepage, let url = URL(string: homepage) {
                        Button(String(localized: "ui.ResourceHubSection.847652d1d8")) { NSWorkspace.shared.open(url) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    ResourceHubSection()
        .environment(AppViewModel())
        .frame(width: 700)
}

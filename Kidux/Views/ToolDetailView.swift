import SwiftUI
import AppKit

struct ToolDetailView: View {
    let tool: DevTool
    let installState: ToolInstallState
    var relatedTools: [DevTool] = []
    var onInstall: () -> Void
    var onSelectRelated: ((DevTool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var homepage: String?
    @State private var previewScreenshotURL: String?
    @State private var enrichedScreenshots: [String] = []
    @State private var enrichedDescription: String?

    private var displayScreenshots: [String] {
        if !enrichedScreenshots.isEmpty { return enrichedScreenshots }
        return tool.screenshots ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    if !displayScreenshots.isEmpty {
                        screenshotsSection(displayScreenshots)
                    }
                    metaSection
                    descriptionSection
                    externalLinksSection
                    if !relatedTools.isEmpty {
                        relatedSection
                    }
                }
                .padding(AppTheme.pageHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: sheetHeight)
        .sheet(isPresented: Binding(
            get: { previewScreenshotURL != nil },
            set: { if !$0 { previewScreenshotURL = nil } }
        )) {
            if let urlString = previewScreenshotURL {
                ScreenshotPreviewSheet(urlString: urlString)
            }
        }
        .userActivity("co.langem.kidux.view-tool") { activity in
            // S20-11 — Handoff / Spotlight 继续浏览 Catalog
            activity.title = String(format: String(localized: "ui.ToolDetailView.fmt.07e5d70e75"), locale: .current, "\(tool.name)")
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.userInfo = ["toolID": tool.id]
            activity.requiredUserInfoKeys = ["toolID"]
            activity.webpageURL = URL(string: "kidux://search?q=\(tool.id)")
        }
        .task {
            UsageFrequencyStore.shared.recordOpen(toolID: tool.id)
            if let resolved = tool.resolvedHomepage {
                homepage = resolved
            } else {
                homepage = await ToolIconService.shared.homepage(for: tool)
            }
            let enrichment = await ToolScreenshotEnrichmentService.shared.enrich(tool: tool)
            enrichedScreenshots = enrichment.screenshots
            if let hp = enrichment.homepage, homepage == nil {
                homepage = hp
            }
            if let desc = enrichment.longDescription, !(tool.longDescription?.isEmpty == false) {
                enrichedDescription = desc
            }
        }
    }

    private var sheetHeight: CGFloat {
        let base: CGFloat = displayScreenshots.isEmpty ? 560 : 660
        return relatedTools.isEmpty ? base : base + 80
    }

    private var header: some View {
        HStack {
            Text(String(localized: "ui.ToolDetailView.042a3148fd"))
                .font(.headline)
            Spacer()
            Button(String(localized: "ui.ToolDetailView.b15d91274e")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            ToolIconView(tool: tool, size: 88)
                .accessibilityLabel(String(format: String(localized: "ui.ToolDetailView.fmt.966cce5548"), locale: .current, "\(tool.name)"))

            VStack(alignment: .leading, spacing: 8) {
                Text(tool.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text(ToolCategory.label(for: tool.category))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    SourceBadge(source: tool.source)
                    Text(tool.resolvedKind == .cli ? String(localized: "ui.ToolDetailView.dbb0d3bb03") : String(localized: "ui.ToolDetailView.1c32ae7a64"))
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    if installState == .installed {
                        Text(String(localized: "ui.ToolDetailView.9d5bf2a10a"))
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.14), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    if let quality = CatalogQualityStore.shared.quality(for: tool.id) {
                        CatalogQualityBadgeView(quality: quality)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func screenshotsSection(_ urls: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "ui.ToolDetailView.369abff3bc"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(localized: "ui.ToolDetailView.b434ad252e"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(urls, id: \.self) { urlString in
                        Button {
                            previewScreenshotURL = urlString
                        } label: {
                            ScreenshotThumb(urlString: urlString)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "ui.ToolDetailView.3bc9990b51"))
                        .accessibilityLabel(String(format: String(localized: "ui.ToolDetailView.fmt.80f7b49ebd"), locale: .current, "\(tool.name)"))
                        .accessibilityHint(String(localized: "ui.ToolDetailView.2a162c496e"))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "ui.ToolDetailView.85b1a749dc"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text(String(localized: "ui.ToolDetailView.79941a4c82")).foregroundStyle(.secondary)
                    Text(tool.installMethodLabel)
                }
                GridRow {
                    Text(String(localized: "ui.ToolDetailView.f3c00c7e55")).foregroundStyle(.secondary)
                    Text(tool.source.identifier)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if let sourceLevel = tool.sourceLevel {
                    GridRow {
                        Text(String(localized: "ui.ToolDetailView.a8a969ce9e")).foregroundStyle(.secondary)
                        Text(sourceLevel)
                    }
                }
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "ui.ToolDetailView.61a3ec6656"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            let bodyText = enrichedDescription?.isEmpty == false
                ? (enrichedDescription ?? tool.displayDescription)
                : tool.displayDescription

            if let attributed = try? AttributedString(
                markdown: bodyText,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let tags = tool.tags, !tags.isEmpty {
                FlowTagsView(tags: tags)
            }
        }
    }

    @ViewBuilder
    private var externalLinksSection: some View {
        let homepageURL = homepage.flatMap { URL(string: $0) }
        let githubURL = tool.githubRepositoryURL

        if homepageURL != nil || githubURL != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "ui.ToolDetailView.d82680d89f"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    if let githubURL {
                        Link(destination: githubURL) {
                            Label(String(localized: "ui.ToolDetailView.aadf5a3564"), systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .buttonStyle(.bordered)
                    }
                    if let homepageURL {
                        Link(destination: homepageURL) {
                            Label(String(localized: "ui.ToolDetailView.667b5b8b60"), systemImage: "globe")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "ui.ToolDetailView.3d20c254ad"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(relatedTools.prefix(8)) { related in
                        Button {
                            onSelectRelated?(related)
                        } label: {
                            HStack(spacing: 8) {
                                ToolIconView(tool: related, size: 28)
                                Text(related.name)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.background, in: Capsule())
                            .overlay(Capsule().stroke(AppTheme.cardStroke))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let homepage, let url = URL(string: homepage) {
                Button(String(localized: "ui.ToolDetailView.f5f413b230")) {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .accessibilityHint(String(format: String(localized: "ui.ToolDetailView.fmt.a4053b2d72"), locale: .current, "\(tool.name)"))
            }
            if let githubURL = tool.githubRepositoryURL {
                Button("GitHub") {
                    NSWorkspace.shared.open(githubURL)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(String(localized: "ui.ToolDetailView.8f9e4b3e74"))
            }
            Spacer()
            Button(action: onInstall) {
                Text(tool.installActionDetailTitle(installState: installState))
            }
            .buttonStyle(.borderedProminent)
            .disabled(installState == .installed && tool.isInAppInstallable)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("\(tool.installActionDetailTitle(installState: installState)) \(tool.name)")
        }
        .padding(20)
    }
}

private struct ScreenshotPreviewSheet: View {
    let urlString: String
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "ui.ToolDetailView.b56fd1606b"))
                    .font(.headline)
                Spacer()
                Button(String(localized: "ui.ToolDetailView.b15d91274e")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                } else if failed {
                    ContentUnavailableView(String(localized: "ui.ToolDetailView.6583b1bec9"), systemImage: "photo")
                } else {
                    ProgressView(String(localized: "ui.ToolDetailView.fb4ca1cf1b"))
                }
            }
            .frame(minWidth: 720, minHeight: 480)
        }
        .task(id: urlString) {
            guard let url = URL(string: urlString) else {
                failed = true
                return
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let loaded = NSImage(data: data) else {
                    failed = true
                    return
                }
                image = loaded
            } catch {
                failed = true
            }
        }
    }
}

private struct ScreenshotThumb: View {
    let urlString: String
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if failed {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        ProgressView().controlSize(.small)
                    }
            }
        }
        .frame(width: 220, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption2)
                .padding(6)
                .background(.ultraThinMaterial, in: Circle())
                .padding(8)
        }
        .task(id: urlString) {
            guard let url = URL(string: urlString) else {
                failed = true
                return
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let loaded = NSImage(data: data) else {
                    failed = true
                    return
                }
                image = loaded
            } catch {
                failed = true
            }
        }
    }
}

private struct FlowTagsView: View {
    let tags: [String]

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.top, 4)
    }
}

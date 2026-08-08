import SwiftUI

struct DiscoverView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var selectedCategory: ToolCategory = .all
    @State private var detailTool: DevTool?
    /// 窗口化渲染：绝不在单次布局中实例化全部 760 张卡（那会卡死主线程）。
    @State private var visibleCount = DiscoverLayout.initialPageSize

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 16)
    ]

    var body: some View {
        discoverPage
            .task { await viewModel.prepareDiscoverPage() }
            .modifier(DiscoverViewLifecycleModifier(
                viewModel: viewModel,
                selectedCategory: $selectedCategory,
                detailTool: $detailTool,
                resetVisibleWindow: { visibleCount = DiscoverLayout.initialPageSize }
            ))
            .modifier(DiscoverViewSheetsModifier(
                viewModel: viewModel,
                detailTool: $detailTool,
                relatedTools: relatedTools(for:)
            ))
    }

    private var discoverPage: some View {
        ClassicPageScaffold(
            title: String(localized: "page.discover.title"),
            subtitle: discoverSubtitle,
            headerTrailing: { discoverHeaderTrailing },
            chrome: {
                DiscoverHeader(selectedCategory: $selectedCategory)
            },
            accessory: {
                if let error = viewModel.bundleManager.loadError {
                    catalogLoadErrorBanner(error)
                }
            },
            content: { discoverCatalogScroll }
        )
    }

    @ViewBuilder
    private var discoverHeaderTrailing: some View {
        HStack(spacing: 8) {
            if viewModel.isScanningInstalled || viewModel.isSearchingBrew {
                ProgressView().controlSize(.small)
            }

            if viewModel.installManager.isInstalling || viewModel.installManager.isFinished,
               !viewModel.showDiscoverInstallSheet
            {
                Button {
                    viewModel.showDiscoverInstallSheet = true
                } label: {
                    Label(String(localized: "ui.DiscoverView.c7bff79d"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .fixedSize()
            }

            Button(String(format: String(localized: "ui.DiscoverView.fmt.a753703b55"), locale: .current, "\(viewModel.installableDiscoverSelectionCount)")) {
                Task { await viewModel.installDiscoverSelection() }
            }
            .buttonStyle(.borderedProminent)
            .opacity(viewModel.installableDiscoverSelectionCount == 0 ? 0.35 : 1)
            .disabled(viewModel.installableDiscoverSelectionCount == 0)
            .fixedSize()
        }
    }

    private var discoverSubtitle: String {
        switch viewModel.discoverMode {
        case .builtin:
            let total = viewModel.discoverDisplayTools.count
            if selectedCategory != .all {
                return String(format: String(localized: "ui.DiscoverView.fmt.2246926cb5"), locale: .current, "\(selectedCategory.displayName)", "\(total)")
            }
            return String(format: String(localized: "ui.DiscoverView.fmt.15d5db03fb"), locale: .current, "\(viewModel.allCatalogTools.count)")
        case .homebrew:
            return String(localized: "ui.DiscoverView.ffd6fd85d3")
        }
    }

    private var visibleTools: [DevTool] {
        Array(viewModel.discoverDisplayTools.prefix(visibleCount))
    }

    private var hasMoreTools: Bool {
        visibleCount < viewModel.discoverDisplayTools.count
    }

    /// App Store 风格主内容：单栏 ScrollView + LazyVGrid，背景与脚手架一致。
    private var discoverCatalogScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                catalogHeaderBlocks

                if !viewModel.discoverDisplayTools.isEmpty {
                    catalogGridSection
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .isolatesScrollSafeAreaFromWindowChrome()
        .refreshable {
            if viewModel.discoverMode == .homebrew {
                await viewModel.reloadBrewTrending(force: true)
            }
        }
    }

    @ViewBuilder
    private var catalogHeaderBlocks: some View {
        if viewModel.showsDiscoverTrendingSection {
            DiscoverTrendingSection(
                onShowDetail: { detailTool = $0 },
                onInstall: { tool in
                    Task { await viewModel.installDiscoverTool(tool) }
                }
            )
            if let hint = viewModel.brewSearchHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let hint = viewModel.brewSearchHint, viewModel.discoverMode == .homebrew,
                  viewModel.discoverDisplayTools.isEmpty {
            EmptyStateView(
                title: String(localized: "ui.DiscoverView.54c450ed85"),
                systemImage: "magnifyingglass",
                description: hint
            )
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        } else if viewModel.discoverDisplayTools.isEmpty {
            EmptyStateView(
                title: String(localized: "ui.DiscoverView.731ba8bcdd"),
                systemImage: "tray",
                description: emptyDescription,
                actions: emptyStateActions
            )
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        } else if viewModel.showsDiscoverFeaturedSection {
            DiscoverFeaturedSection(
                onShowDetail: { detailTool = $0 },
                onInstall: { tool in
                    Task { await viewModel.installDiscoverTool(tool) }
                }
            )
        }

        // 社区资源：紧跟精选/热门之后，避免藏在「加载完全部 760 款」之后。
        if viewModel.discoverMode == .builtin,
           viewModel.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ResourceHubSection()
        }
    }

    private var catalogGridSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !viewModel.showsDiscoverFeaturedSection || viewModel.discoverMode == .homebrew {
                AppTheme.DiscoverSectionHeader(
                    title: gridSectionTitle,
                    subtitle: nil,
                    trailing: "\(viewModel.discoverDisplayTools.count)"
                )
            } else {
                AppTheme.DiscoverSectionHeader(
                    title: String(localized: "ui.DiscoverView.edc4bab539"),
                    subtitle: nil,
                    trailing: "\(viewModel.discoverDisplayTools.count)"
                )
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(visibleTools) { tool in
                    DiscoverToolCard(
                        tool: tool,
                        installState: viewModel.installStateForCatalog(tool),
                        isSelected: viewModel.discoverSelectedTools.contains(tool.id),
                        onToggleSelect: { viewModel.toggleDiscoverSelection(tool.id) },
                        onShowDetail: { detailTool = tool },
                        onInstall: {
                            Task { await viewModel.installDiscoverTool(tool) }
                        }
                    )
                    .id(tool.id)
                }
            }

            if hasMoreTools {
                loadMoreFooter
            }
        }
    }

    private var loadMoreFooter: some View {
        VStack(spacing: 10) {
            Text(String(format: String(localized: "ui.DiscoverView.fmt.6df8c5e03e"), locale: .current, "\(visibleTools.count)", "\(viewModel.discoverDisplayTools.count)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(String(localized: "ui.DiscoverView.77281549")) {
                expandVisibleWindow()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func expandVisibleWindow() {
        let total = viewModel.discoverDisplayTools.count
        guard visibleCount < total else { return }
        visibleCount = min(visibleCount + DiscoverLayout.pageSize, total)
        viewModel.preloadDiscoverIconsIfNeeded()
    }

    private func relatedTools(for tool: DevTool) -> [DevTool] {
        Array(
            viewModel.discoverDisplayTools
                .filter { $0.category == tool.category && $0.id != tool.id }
                .prefix(8)
        )
    }

    private func catalogLoadErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(String(format: String(localized: "ui.DiscoverView.fmt.bc2ccddb53"), locale: .current, "\(message)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }

    private var gridSectionTitle: String {
        viewModel.discoverMode == .homebrew ? String(localized: "ui.DiscoverView.098f9e940d") : String(localized: "ui.DiscoverView.4890e35142")
    }

    private var emptyDescription: String {
        switch viewModel.discoverMode {
        case .builtin:
            if !viewModel.discoverSearchText.isEmpty {
                return String(format: String(localized: "ui.DiscoverView.fmt.99ec1a413c"), locale: .current, "\(viewModel.discoverSearchText)")
            }
            return String(localized: "ui.DiscoverView.910f55e3aa")
        case .homebrew:
            return String(localized: "ui.DiscoverView.adf2667fbf")
        }
    }

    private var emptyStateActions: [EmptyStateAction] {
        switch viewModel.discoverMode {
        case .builtin:
            var actions: [EmptyStateAction] = [
                EmptyStateAction(title: String(localized: "ui.DiscoverView.a95500ef")) {
                    viewModel.clearDiscoverFilters()
                },
                EmptyStateAction(title: String(localized: "ui.DiscoverView.045c971cd9")) {
                    viewModel.clearDiscoverFilters()
                    viewModel.discoverScopeFilter = .popular
                }
            ]
            let query = viewModel.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                actions.insert(EmptyStateAction(title: String(localized: "ui.DiscoverView.6c8523b8a2")) {
                    Task { await viewModel.applyDiscoverNaturalLanguageFilter() }
                }, at: 0)
                actions.append(EmptyStateAction(title: String(localized: "ui.DiscoverView.e54ad63d77")) {
                    viewModel.askAIAboutDiscover(query: query)
                })
            } else {
                actions.append(EmptyStateAction(title: String(localized: "ui.DiscoverView.e54ad63d77")) {
                    viewModel.askAIAboutDiscover(query: String(localized: "ui.DiscoverView.8fefb578f3"))
                })
            }
            return actions
        case .homebrew:
            return []
        }
    }
}

private enum DiscoverLayout {
    static let initialPageSize = 48
    static let pageSize = 48
}

struct DiscoverToolCard: View {
    let tool: DevTool
    let installState: ToolInstallState
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onShowDetail: () -> Void
    let onInstall: () -> Void

    private var isInstalled: Bool {
        installState == .installed && tool.isInAppInstallable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onShowDetail) {
                    ToolIconView(tool: tool, size: AppTheme.discoverIconSize)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Button(action: onShowDetail) {
                        Text(tool.name)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                SourceBadge(source: tool.source)
                if isInstalled {
                    ToolStatusTag(title: String(localized: "ui.DiscoverView.9d5bf2a10a"), color: .green)
                }
                if isSelected {
                    ToolStatusTag(title: String(localized: "ui.DiscoverView.7bf54e288c"), color: .accentColor)
                }
                Spacer(minLength: 0)

                Button(String(localized: "ui.DiscoverView.f26225bd")) { onShowDetail() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                AppTheme.AppStoreGetButton(
                    title: tool.installActionTitle(installState: installState),
                    isDisabled: isInstalled
                ) {
                    onInstall()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : AppTheme.cardStroke,
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .onTapGesture(count: 2, perform: onShowDetail)
        .contextMenu {
            Button(isSelected ? String(localized: "ui.DiscoverView.cc7008c275") : String(localized: "ui.DiscoverView.950c12eeb3")) {
                onToggleSelect()
            }
            Button(String(localized: "ui.DiscoverView.5b48dbb8dc")) { onShowDetail() }
            if !isInstalled {
                Button(String(localized: "ui.DiscoverView.e655a410")) { onInstall() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.name)，\(tool.description)")
        .accessibilityHint(isSelected ? String(localized: "ui.DiscoverView.9846c3e695") : String(localized: "ui.DiscoverView.08a3e646dd"))
        .modifier(DiscoverSelectedTrait(isSelected: isSelected))
    }
}

private struct DiscoverSelectedTrait: ViewModifier {
    let isSelected: Bool
    func body(content: Content) -> some View {
        if isSelected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content
        }
    }
}

struct DiscoverInstallSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // S22-27 — 与 MaintenanceProgressSheet 统一尺寸
        InstallationProgressView(style: .sheet) {
            dismiss()
        }
        .environment(viewModel)
        .frame(width: BrewProgressLayout.sheetWidth, height: BrewProgressLayout.sheetHeight)
    }
}

private struct DiscoverViewLifecycleModifier: ViewModifier {
    @Bindable var viewModel: AppViewModel
    @Binding var selectedCategory: ToolCategory
    @Binding var detailTool: DevTool?
    var resetVisibleWindow: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.pendingSpotlightToolID) { _, toolID in
                guard let toolID,
                      let tool = viewModel.catalogTool(id: toolID) else { return }
                detailTool = tool
                _ = viewModel.consumePendingSpotlightToolID()
            }
            .onChange(of: viewModel.discoverMode) { _, _ in
                resetVisibleWindow()
            }
            .onChange(of: viewModel.discoverFiltersRevision) { _, _ in
                selectedCategory = .all
                resetVisibleWindow()
            }
            .onChange(of: viewModel.discoverSearchText) { _, _ in
                resetVisibleWindow()
            }
            .onChange(of: viewModel.discoverScopeFilter) { _, _ in
                resetVisibleWindow()
            }
            .onChange(of: viewModel.discoverSourceFilter) { _, _ in
                resetVisibleWindow()
            }
            .onChange(of: viewModel.discoverCategory) { _, newValue in
                resetVisibleWindow()
                if let raw = newValue, let category = ToolCategory(rawValue: raw) {
                    selectedCategory = category
                } else {
                    selectedCategory = .all
                }
            }
            .onChange(of: selectedCategory) { _, newValue in
                viewModel.discoverCategory = newValue == .all ? nil : newValue.rawValue
            }
            .onAppear {
                viewModel.preloadDiscoverIconsIfNeeded()
            }
    }
}

private struct DiscoverViewSheetsModifier: ViewModifier {
    @Bindable var viewModel: AppViewModel
    @Binding var detailTool: DevTool?
    let relatedTools: (DevTool) -> [DevTool]

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { viewModel.showDiscoverInstallSheet },
                set: { viewModel.showDiscoverInstallSheet = $0 }
            )) {
                DiscoverInstallSheet()
                    .environment(viewModel)
            }
            .sheet(item: $detailTool) { tool in
                ToolDetailView(
                    tool: tool,
                    installState: viewModel.installStateForCatalog(tool),
                    relatedTools: relatedTools(tool),
                    onInstall: {
                        Task {
                            await viewModel.installDiscoverTool(tool)
                            detailTool = nil
                        }
                    },
                    onSelectRelated: { related in
                        detailTool = related
                    }
                )
            }
    }
}

#Preview {
    DiscoverView()
        .environment(AppViewModel())
        .frame(width: 900, height: 600)
}

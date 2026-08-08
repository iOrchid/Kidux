import SwiftUI

/// 经典模式：侧栏 + 内容区（遵循 macOS HIG：`NavigationSplitView` + `List(selection:)` + `Label`）
struct ClassicShellView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    /// S22-22 — 仅保活「当前 + 上一」重型 Tab，避免三页常驻占内存。
    @State private var retainedHeavyTabs: [AppTab] = []

    private static let heavyTabs: Set<AppTab> = [
        .discover, .installed, .environment
    ]
    private static let maxRetainedHeavyTabs = 2

    private var tabSelection: Binding<AppTab?> {
        Binding(
            get: { viewModel.selectedTab },
            set: { newValue in
                if let newValue {
                    viewModel.navigateTo(newValue)
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: AppTheme.sidebarWidth,
                    max: 260
                )
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                // S22-21 — 固定高度 Banner slot，避免布局跳动
                ZStack {
                    KiduxUpdateBanner()
                }
                .frame(
                    height: (viewModel.appUpdateInfo != nil && !viewModel.appUpdateBannerDismissed)
                        ? KiduxUpdateBanner.slotHeight
                        : 0
                )
                .clipped()
                DetailContentHost {
                    detailContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(AppTheme.heroBackground)
            .animation(nil, value: viewModel.selectedTab)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            columnVisibility = isSidebarVisible ? .detailOnly : .all
                        }
                    } label: {
                        Image(systemName: "sidebar.leading")
                    }
                    .help(isSidebarVisible ? String(localized: "ui.ClassicShellView.222d7f43") : String(localized: "ui.ClassicShellView.a69d1320"))
                    .accessibilityLabel(isSidebarVisible ? String(localized: "ui.ClassicShellView.222d7f43") : String(localized: "ui.ClassicShellView.a69d1320"))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 系统标题栏由窗口标题 + 侧栏品牌承担；不再叠一层玻璃「启椟」字样
        .toolbarBackground(.visible, for: .windowToolbar)
        .onAppear {
            retainHeavyTabIfNeeded(viewModel.selectedTab)
        }
        .onChange(of: viewModel.selectedTab) { _, tab in
            retainHeavyTabIfNeeded(tab)
        }
    }

    private var isSidebarVisible: Bool {
        columnVisibility == .all || columnVisibility == .doubleColumn
    }

    private var sidebar: some View {
        List(selection: tabSelection) {
            Section {
                HStack(spacing: 12) {
                    BrandAppIcon(size: 32, showShadow: false)
                    Text(BrandInfo.displayNameCN)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(BrandInfo.displayNameCN)
            }

            Section(String(localized: "ui.ClassicShellView.056f2d7df6")) {
                ForEach(AppTab.classicTabs) { tab in
                    Label {
                        HStack {
                            Text(tab.title)
                            Spacer(minLength: 0)
                            if tab == .installed, viewModel.outdatedCount > 0 {
                                Text("\(viewModel.outdatedCount)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                    } icon: {
                        Image(systemName: tab.icon)
                    }
                    .tag(tab)
                    .accessibilityLabel(tab.title)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel(String(localized: "ui.ClassicShellView.2b2c9b8425"))
    }

    @ViewBuilder
    private var detailContent: some View {
        let selected = viewModel.selectedTab
        ZStack {
            if retainedHeavyTabs.contains(.discover) {
                heavyTabHost(.discover, selected: selected) { DiscoverView() }
            }
            if retainedHeavyTabs.contains(.installed) {
                heavyTabHost(.installed, selected: selected) { InstalledAppsView() }
            }
            if retainedHeavyTabs.contains(.environment) {
                heavyTabHost(.environment, selected: selected) { EnvironmentPanelView() }
            }

            if !Self.heavyTabs.contains(selected) {
                lightTabContent(selected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func heavyTabHost<Content: View>(
        _ tab: AppTab,
        selected: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selected == tab ? 1 : 0)
            .allowsHitTesting(selected == tab)
            .accessibilityHidden(selected != tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func lightTabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            WelcomeView()
        case .assistant:
            AIAssistantView(immersive: false)
        case .roles:
            RolesFlowView()
        default:
            EmptyView()
        }
    }

    private func retainHeavyTabIfNeeded(_ tab: AppTab) {
        guard Self.heavyTabs.contains(tab) else { return }
        if let existing = retainedHeavyTabs.firstIndex(of: tab) {
            retainedHeavyTabs.remove(at: existing)
        }
        retainedHeavyTabs.append(tab)
        if retainedHeavyTabs.count > Self.maxRetainedHeavyTabs {
            retainedHeavyTabs.removeFirst(retainedHeavyTabs.count - Self.maxRetainedHeavyTabs)
        }
    }
}
#Preview {
    ClassicShellView()
        .environment(AppViewModel())
        .frame(width: 1100, height: 750)
}

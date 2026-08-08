import SwiftUI
import AppKit

struct InstalledAppsView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var scope: InstalledScope = .local
    @State private var filterKind: ToolKindFilter = .all
    @State private var catalogSearchText = ""
    @State private var trustFixTarget: TrustFixTarget?
    @State private var showUninstallConfirm = false
    @State private var uninstallConfirmMessage = ""
    @State private var showCleanupConfirm = false
    @State private var maintenanceSection: MaintenanceSection = .services
    @State private var dependencyFormulaSheet: FormulaDependencyTarget?
    @State private var reverseDependencyFormulaSheet: FormulaDependencyTarget?
    @State private var formulaSearchText = ""
    @State private var showOnlyIntentionalFormulae = false

    enum InstalledScope: String, CaseIterable, Identifiable {
        case local
        case catalog
        case updates
        case uninstall
        case maintenance

        var id: String { rawValue }

        var title: String {
            switch self {
            case .local: return String(localized: "installed.scope.local")
            case .catalog: return String(localized: "installed.scope.catalog")
            case .updates: return String(localized: "installed.scope.updates")
            case .uninstall: return String(localized: "installed.scope.uninstall")
            case .maintenance: return String(localized: "installed.scope.maintenance")
            }
        }
    }

    enum MaintenanceSection: String, CaseIterable, Identifiable {
        case services
        case storage
        case security
        case dependencies
        case history

        var id: String { rawValue }

        var title: String {
            switch self {
            case .services: return String(localized: "installed.maintenance.services")
            case .storage: return String(localized: "installed.maintenance.storage")
            case .security: return String(localized: "installed.maintenance.security")
            case .dependencies: return String(localized: "installed.maintenance.dependencies")
            case .history: return String(localized: "installed.maintenance.history")
            }
        }
    }

    enum ToolKindFilter: String, CaseIterable, Identifiable {
        case all, cli, gui

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "ui.InstalledAppsView.a8b0c204")
            case .cli: return "CLI"
            case .gui: return "GUI"
            }
        }
    }

    var body: some View {
        pageLayout
            .task { await loadInstalledPageData() }
            .onAppear { applyInstalledScopeRequest() }
            .onChange(of: viewModel.shouldShowInstalledUpdatesScope) { _, _ in
                applyInstalledScopeRequest()
            }
            .onChange(of: scope) { _, newScope in
                switch newScope {
                case .updates:
                    Task { await viewModel.ensureUpdatesChecked() }
                case .maintenance:
                    Task { await loadMaintenanceSectionIfNeeded(maintenanceSection) }
                default:
                    break
                }
            }
            .onChange(of: maintenanceSection) { _, section in
                guard scope == .maintenance else { return }
                Task { await loadMaintenanceSectionIfNeeded(section) }
            }
            .modifier(InstalledAppsDialogsModifier(
                viewModel: viewModel,
                trustFixTarget: $trustFixTarget,
                dependencyFormulaSheet: $dependencyFormulaSheet,
                reverseDependencyFormulaSheet: $reverseDependencyFormulaSheet,
                showUninstallConfirm: $showUninstallConfirm,
                uninstallConfirmMessage: uninstallConfirmMessage,
                showCleanupConfirm: $showCleanupConfirm
            ))
    }

    private var pageLayout: some View {
        ClassicPageScaffold(
            title: String(localized: "page.installed.title"),
            subtitle: installedSubtitle,
            headerTrailing: { installedHeaderTrailing },
            chrome: { scopePickerBar },
            accessory: {
                updateBannerSlot
                scopeSecondaryBar
            },
            content: { installedMainContent }
        )
    }

    @ViewBuilder
    private var installedHeaderTrailing: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if scope == .updates, viewModel.outdatedCount > 0 {
                    Button {
                        Task { await viewModel.upgradeAllOutdated() }
                    } label: {
                        Label(String(format: String(localized: "ui.InstalledAppsView.fmt.50a66e0e45"), locale: .current, "\(viewModel.outdatedCount)"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.maintenanceManager.isRunning)
                }
                if scope == .uninstall, !viewModel.uninstallSelection.isEmpty {
                    Button(role: .destructive) {
                        Task {
                            uninstallConfirmMessage = await viewModel.buildUninstallConfirmationMessage()
                            showUninstallConfirm = true
                        }
                    } label: {
                        Label(String(format: String(localized: "ui.InstalledAppsView.fmt.087b567a59"), locale: .current, "\(viewModel.uninstallSelection.count)"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.maintenanceManager.isRunning)
                }
                if scope == .maintenance, maintenanceSection == .storage {
                    Button {
                        showCleanupConfirm = true
                    } label: {
                        Label(String(localized: "ui.InstalledAppsView.7ba2fcc342"), systemImage: "trash.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRunningBrewCleanup || viewModel.isLoadingBrewDisk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            PageHeaderRescanButton(
                isLoading: viewModel.isScanningInstalled || viewModel.isScanningLocalApps
            ) {
                Task {
                    await viewModel.scanInstalledStatus(force: true)
                    await viewModel.checkForUpdates()
                    if scope == .maintenance {
                        await viewModel.loadBrewServices(force: true)
                        await viewModel.loadBrewDiskUsage(force: true)
                        await viewModel.loadBrewVulnerabilities(force: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var installedMainContent: some View {
        scopeBody
            .animation(nil, value: scope)
            .animation(nil, value: maintenanceSection)
    }

    private func loadInstalledPageData() async {
        await viewModel.ensureRuntimeSnapshot()
        if viewModel.localApplications.isEmpty {
            await viewModel.scanLocalApplications()
        }
        await viewModel.loadBrewServices()
        await viewModel.loadPinnedFormulae()
    }

    private func applyInstalledScopeRequest() {
        guard viewModel.shouldShowInstalledUpdatesScope else { return }
        scope = .updates
        viewModel.shouldShowInstalledUpdatesScope = false
    }

    private var showsScopeSecondaryBar: Bool {
        scope == .maintenance || scope == .catalog
    }

    private func loadMaintenanceSectionIfNeeded(_ section: MaintenanceSection) async {
        switch section {
        case .services:
            await viewModel.loadBrewServices()
        case .storage:
            await viewModel.loadBrewDiskUsage()
        case .security:
            await viewModel.loadBrewVulnerabilities()
        case .dependencies:
            await viewModel.loadBrewLeaves()
        case .history:
            break
        }
    }

    private var showsUpdateReminder: Bool {
        viewModel.outdatedCount > 0 && !viewModel.updateBannerDismissed
    }

    private var scopePickerBar: some View {
        Picker(String(localized: "ui.InstalledAppsView.df011658"), selection: $scope) {
            ForEach(InstalledScope.allCases) { s in
                Text(s.title).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .frame(height: InstalledAppsLayout.scopePickerHeight)
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .animation(nil, value: scope)
    }

    @ViewBuilder
    private var scopeSecondaryBar: some View {
        if scope == .maintenance {
            HStack(spacing: 12) {
                Picker(String(localized: "ui.InstalledAppsView.107baa8e"), selection: $maintenanceSection) {
                    ForEach(MaintenanceSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 480)

                Spacer(minLength: 0)
            }
            .frame(height: InstalledAppsLayout.secondaryToolbarHeight)
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
        } else if scope == .catalog {
            HStack(spacing: 12) {
                Text(String(localized: "ui.InstalledAppsView.226b0912"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker(String(localized: "ui.InstalledAppsView.226b0912"), selection: $filterKind) {
                    ForEach(ToolKindFilter.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField(String(localized: "ui.InstalledAppsView.30c41605ab"), text: $catalogSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(maxWidth: 260)

                Spacer(minLength: 0)
            }
            .frame(height: InstalledAppsLayout.catalogFilterBarHeight)
            .clipped()
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
        }
    }

    @ViewBuilder
    private var updateBannerSlot: some View {
        ZStack {
            if showsUpdateReminder {
                UpdateReminderBanner()
            }
        }
        .frame(height: showsUpdateReminder ? InstalledAppsLayout.updateBannerHeight : 0)
        .clipped()
        .animation(nil, value: showsUpdateReminder)
    }

    private var installedSubtitle: String {
        let matched = viewModel.localApplications.filter(\.isInCatalog).count
        let scanned = viewModel.installedSnapshot != nil
            ? String(localized: "installed.scanned")
            : String(localized: "installed.scanning_short")
        let updates = viewModel.outdatedCount
        let updateHint = updates > 0 ? " · \(updates)" : ""
        let base = "\(String(localized: "installed.scope.local")) \(viewModel.localApplications.count) · \(String(localized: "installed.scope.catalog")) \(matched) · \(scanned)\(updateHint)"
        if scope == .local {
            return base + " · " + String(localized: "installed.permission_note")
        }
        return base
    }

    private var scopeBody: some View {
        // 只挂载当前 scope 的 List，保留单 shell 以满足 NavigationSplitView safe area。
        Group {
            switch scope {
            case .local:
                localAppsList
            case .catalog:
                catalogMatchedList
            case .updates:
                updatesList
            case .uninstall:
                uninstallList
            case .maintenance:
                maintenanceContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(nil, value: scope)
    }

    private func installedLoadingOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.94))
    }

    private func installedEmptyOverlay(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.94))
    }

    /// 保持 List 始终在视图树中，避免 NavigationSplitView 顶栏 safe area 被重算
    private func installedListShell<ListContent: View, Overlay: View>(
        @ViewBuilder list: () -> ListContent,
        @ViewBuilder overlay: () -> Overlay
    ) -> some View {
        ZStack(alignment: .top) {
            list().modifier(InstalledListStyle())
            overlay()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var localAppsList: some View {
        installedListShell {
            List(viewModel.localApplications) { app in
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.body)
                        Text(app.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if app.isInCatalog {
                        Text(String(localized: "installed.in_catalog"))
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                            .foregroundStyle(.green)
                    } else {
                        Text(String(localized: "installed.local_only"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.localAppNeedsTrustFix(path: app.path) {
                        Text(String(localized: "installed.needs_repair"))
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }

                    Button(String(localized: "installed.check_trust")) {
                        trustFixTarget = TrustFixTarget(path: app.path)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(String(localized: "installed.check_trust.help"))

                    Button(String(localized: "common.open")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
        } overlay: {
            if viewModel.isScanningLocalApps && viewModel.localApplications.isEmpty {
                installedLoadingOverlay(String(localized: "installed.scanning"))
            } else if viewModel.localApplications.isEmpty {
                installedEmptyOverlay {
                    EmptyStateView(
                        title: String(localized: "installed.empty.title"),
                        systemImage: "app",
                        description: String(localized: "installed.empty.description")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var updatesList: some View {
        installedListShell {
            List(viewModel.outdatedResult?.allEntries ?? []) { entry in
                HStack(spacing: 12) {
                    entryIcon(for: entry)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName).font(.body)
                        Text(entry.sourceLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(String(localized: "ui.InstalledAppsView.32ac152b")) {
                        Task { await viewModel.upgradeOutdatedEntry(entry) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.isUpgradingItem == entry.id || viewModel.maintenanceManager.isRunning)
                }
                .padding(.vertical, 4)
            }
        } overlay: {
            if viewModel.isCheckingUpdates, viewModel.outdatedResult == nil {
                installedLoadingOverlay(String(localized: "ui.InstalledAppsView.edbf4fc5ba"))
            } else if let message = viewModel.updateCheckMessage {
                installedEmptyOverlay {
                    EmptyStateView(
                        title: String(localized: "ui.InstalledAppsView.ea4d94a0b3"),
                        systemImage: "exclamationmark.triangle",
                        description: message,
                        actions: [
                            EmptyStateAction(title: String(localized: "ui.InstalledAppsView.132c5cdc")) {
                                Task { await viewModel.checkForUpdates(force: true) }
                            }
                        ]
                    )
                }
            } else if let result = viewModel.outdatedResult, result.allEntries.isEmpty {
                installedEmptyOverlay {
                    EmptyStateView(
                        title: String(localized: "ui.InstalledAppsView.4e4d8a24bc"),
                        systemImage: "checkmark.seal",
                        description: String(localized: "ui.InstalledAppsView.c92caffff1"),
                        actions: [
                            EmptyStateAction(title: String(localized: "ui.InstalledAppsView.a1ad52042d")) {
                                Task { await viewModel.checkForUpdates(force: true) }
                            }
                        ]
                    )
                }
            } else if viewModel.outdatedResult == nil {
                installedEmptyOverlay {
                    EmptyStateView(
                        title: String(localized: "ui.InstalledAppsView.9168e7dcfe"),
                        systemImage: "arrow.triangle.2.circlepath",
                        description: String(localized: "ui.InstalledAppsView.b19b172bed"),
                        actions: [
                            EmptyStateAction(title: String(localized: "ui.InstalledAppsView.4ff133709c")) {
                                Task { await viewModel.checkForUpdates(force: true) }
                            }
                        ]
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var uninstallList: some View {
        let tools = viewModel.uninstallableCatalogTools
        installedListShell {
            List(tools) { tool in
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { viewModel.uninstallSelection.contains(tool.id) },
                        set: { _ in viewModel.toggleUninstallSelection(tool.id) }
                    )) {
                        EmptyView()
                    }
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    ToolIconView(tool: tool, size: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name).font(.body)
                        Text(tool.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(sourceLabel(for: tool.source))
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } overlay: {
            if viewModel.isScanningInstalled && viewModel.installedSnapshot == nil {
                installedLoadingOverlay(String(localized: "ui.InstalledAppsView.00563bda6d"))
            } else if tools.isEmpty {
                installedEmptyOverlay {
                    EmptyStateView(
                        title: String(localized: "ui.InstalledAppsView.1b6105c1fc"),
                        systemImage: "trash.slash",
                        description: String(localized: "ui.InstalledAppsView.7a899b92ac")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func entryIcon(for entry: OutdatedEntry) -> some View {
        switch entry {
        case .brew(let item):
            if let tool = item.catalogTool {
                ToolIconView(tool: tool, size: 32)
            } else {
                Image(systemName: item.sourceType == .cask ? "macwindow" : "terminal")
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
        case .mas(let item):
            if let tool = item.catalogTool {
                ToolIconView(tool: tool, size: 32)
            } else {
                Image(systemName: "bag")
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var maintenanceContent: some View {
        // 维护子面板同样只挂当前 section，避免 5 个 List 同时存活。
        Group {
            switch maintenanceSection {
            case .services:
                brewServicesList
            case .storage:
                brewStoragePanel
            case .security:
                brewSecurityPanel
            case .dependencies:
                formulaDependenciesPanel
            case .history:
                installHistoryPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(nil, value: maintenanceSection)
    }

    @ViewBuilder
    private var formulaDependenciesPanel: some View {
        let formulae: [String] = {
            guard viewModel.installedSnapshot != nil else { return [] }
            return viewModel.filteredInstalledFormulae(
                search: formulaSearchText,
                onlyIntentional: showOnlyIntentionalFormulae
            )
        }()

        VStack(spacing: 0) {
            if viewModel.installedSnapshot != nil, !viewModel.installedFormulaeNames.isEmpty {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField(String(localized: "ui.InstalledAppsView.1f68e782f3"), text: $formulaSearchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                    Toggle(String(localized: "ui.InstalledAppsView.f20bbdc477"), isOn: $showOnlyIntentionalFormulae)
                        .toggleStyle(.button)
                        .controlSize(.small)
                }
                .padding(.horizontal, AppTheme.pageHorizontalPadding)
                .padding(.vertical, 10)

                if showOnlyIntentionalFormulae {
                    Text(String(localized: "ui.InstalledAppsView.19c2a034fc"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.pageHorizontalPadding)
                        .padding(.bottom, 6)
                }
            }

            installedListShell {
                List(formulae, id: \.self) { name in
                    formulaDependencyRow(name)
                }
            } overlay: {
                if viewModel.isScanningInstalled && viewModel.installedSnapshot == nil {
                    installedLoadingOverlay(String(localized: "ui.InstalledAppsView.5a5b999c7e"))
                } else if viewModel.installedFormulaeNames.isEmpty {
                    installedEmptyOverlay {
                        EmptyStateView(
                            title: String(localized: "ui.InstalledAppsView.5f62fe3e3f"),
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: String(localized: "ui.InstalledAppsView.3f2851f8c8")
                        )
                    }
                } else if formulae.isEmpty {
                    installedEmptyOverlay {
                        EmptyStateView(
                            title: showOnlyIntentionalFormulae ? String(localized: "ui.InstalledAppsView.d5b00f40e5") : String(localized: "ui.InstalledAppsView.c072d15840"),
                            systemImage: showOnlyIntentionalFormulae ? "star" : "magnifyingglass",
                            description: showOnlyIntentionalFormulae
                                ? String(localized: "ui.InstalledAppsView.80ed509c5f")
                                : String(localized: "ui.InstalledAppsView.eacbc222")
                        )
                    }
                }
            }
        }
    }

    private func formulaDependencyRow(_ name: String) -> some View {
        let tagged = viewModel.settings.isFormulaTagged(name)
        let isLeaf = viewModel.brewLeavesNames.contains(name.lowercased())
        let isPinned = viewModel.pinnedFormulae.contains(name.lowercased())

        return HStack(spacing: 12) {
            if isPinned {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: tagged ? "star.fill" : (isLeaf ? "leaf" : "terminal"))
                    .foregroundStyle(tagged ? Color.orange : .secondary)
            }
            Text(name)
                .font(.body.monospaced())
            Spacer()
            HStack(spacing: 6) {
                Button(String(localized: "ui.InstalledAppsView.6860b943")) {
                    dependencyFormulaSheet = FormulaDependencyTarget(name: name)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(String(localized: "ui.InstalledAppsView.3488d300")) {
                    reverseDependencyFormulaSheet = FormulaDependencyTarget(name: name)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if isPinned {
                Button(String(localized: "ui.InstalledAppsView.0395d25e8e")) {
                    Task { await viewModel.togglePin(formula: name) }
                }
            } else {
                Button(String(localized: "ui.InstalledAppsView.8f8c0bc596")) {
                    Task { await viewModel.togglePin(formula: name) }
                }
            }
            Divider()
            Button(String(localized: "ui.InstalledAppsView.ddd8be069d")) {
                reverseDependencyFormulaSheet = FormulaDependencyTarget(name: name)
            }
            Divider()
            if tagged {
                Button(String(localized: "ui.InstalledAppsView.3708410373")) {
                    viewModel.toggleFormulaTag(name)
                }
            } else {
                Button(String(localized: "ui.InstalledAppsView.fc775d7d6e")) {
                    viewModel.toggleFormulaTag(name)
                }
            }
        }
    }

    @ViewBuilder
    private var brewServicesList: some View {
        installedListShell {
            List(viewModel.brewServices) { service in
                HStack(spacing: 12) {
                    Image(systemName: service.isRunning ? "circle.fill" : "circle")
                        .foregroundStyle(service.isRunning ? .green : .secondary)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name).font(.body.monospaced())
                        Text(service.statusLabel)
                            .font(.caption2)
                            .foregroundStyle(service.status == "error" ? .red : .secondary)
                        if let user = service.user {
                            Text(user)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        if service.isRunning {
                            serviceButton(String(localized: "ui.InstalledAppsView.095e938e"), service: service, action: .stop)
                            serviceButton(String(localized: "ui.InstalledAppsView.01b4e06f"), service: service, action: .restart)
                        } else {
                            serviceButton(String(localized: "ui.InstalledAppsView.8e54ddfe"), service: service, action: .start, prominent: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } overlay: {
            if viewModel.isLoadingBrewServices {
                installedLoadingOverlay(String(localized: "ui.InstalledAppsView.60a01c7d9f"))
            } else if viewModel.brewServices.isEmpty {
                installedEmptyOverlay {
                    EmptyStateView(
                        title: String(localized: "ui.InstalledAppsView.d032fb1afe"),
                        systemImage: "gearshape.2",
                        description: String(localized: "ui.InstalledAppsView.79fe019ddf"),
                        actions: [
                            EmptyStateAction(title: String(localized: "ui.InstalledAppsView.694fc5ef")) {
                                Task { await viewModel.loadBrewServices(force: true) }
                            }
                        ]
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var brewStoragePanel: some View {
        installedListShell {
            List {
                if let usage = viewModel.brewDiskUsage {
                    Section {
                        storageCard(
                            title: String(localized: "ui.InstalledAppsView.9273f33758"),
                            value: usage.cellarDisplay,
                            path: usage.cellarPath,
                            icon: "shippingbox"
                        )
                        storageCard(
                            title: String(localized: "ui.InstalledAppsView.65a0b69a15"),
                            value: usage.cacheDisplay,
                            path: usage.cachePath,
                            icon: "arrow.down.circle"
                        )
                        if let reclaimable = usage.reclaimableBytes, reclaimable > 0 {
                            HStack {
                                Label(String(format: String(localized: "ui.InstalledAppsView.fmt.201e24469b"), locale: .current, "\(usage.reclaimableDisplay)"), systemImage: "sparkles")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                        }

                        if !usage.cleanupPreviewLines.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(localized: "ui.InstalledAppsView.fba1957311"))
                                    .font(.headline)
                                Text(usage.cleanupPreviewLines.joined(separator: "\n"))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                        } else {
                            Text(String(localized: "ui.InstalledAppsView.93f23c6b34"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 12)
                                .padding(.leading, AppTheme.pageHorizontalPadding)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: AppTheme.pageHorizontalPadding, bottom: 6, trailing: AppTheme.pageHorizontalPadding))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        } overlay: {
            if viewModel.isLoadingBrewDisk, viewModel.brewDiskUsage == nil {
                installedLoadingOverlay(String(localized: "ui.InstalledAppsView.9205dbf763"))
            } else if viewModel.brewDiskUsage == nil {
                installedEmptyOverlay {
                    EmptyStateView(
                        title: String(localized: "ui.InstalledAppsView.7b8dd92374"),
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: String(localized: "ui.InstalledAppsView.92ee65bdc2"),
                        actions: [
                            EmptyStateAction(title: String(localized: "ui.InstalledAppsView.132c5cdc")) {
                                Task { await viewModel.loadBrewDiskUsage(force: true) }
                            }
                        ]
                    )
                }
            }
        }
    }

    private func storageCard(title: String, value: String, path: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(value).font(.title3.bold())
                if !path.isEmpty {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var brewSecurityPanel: some View {
        VStack(spacing: 0) {
            if let scan = viewModel.brewVulnerabilityScan,
               scan.state == .foundIssues || scan.state == .clean {
                securityScanHeader(scan: scan, allClear: scan.state == .clean)
            }

            installedListShell {
                List(viewModel.brewVulnerabilityScan?.packages ?? []) { pkg in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(pkg.name).font(.body.monospaced().bold())
                            if let version = pkg.version {
                                Text(version)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: String(localized: "ui.InstalledAppsView.fmt.06fcdbe7eb"), locale: .current, "\(pkg.vulnerabilities.count)"))
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.12), in: Capsule())
                                .foregroundStyle(.red)
                        }
                        ForEach(pkg.vulnerabilities) { finding in
                            HStack(alignment: .top, spacing: 8) {
                                Text(finding.severity)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(severityBackground(for: finding.severity), in: Capsule())
                                    .foregroundStyle(severityForeground(for: finding.severity))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(finding.id).font(.caption.monospaced())
                                    Text(finding.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } overlay: {
                if viewModel.isLoadingBrewVulns, viewModel.brewVulnerabilityScan == nil {
                    installedLoadingOverlay(String(localized: "ui.InstalledAppsView.db2cf5cd7b"))
                } else if let scan = viewModel.brewVulnerabilityScan {
                    switch scan.state {
                    case .homebrewMissing:
                        installedEmptyOverlay {
                            EmptyStateView(
                                title: String(localized: "ui.InstalledAppsView.1732cc7f8d"),
                                systemImage: "exclamationmark.triangle",
                                description: String(localized: "ui.InstalledAppsView.e2bb92100a")
                            )
                        }
                    case .pluginMissing:
                        installedEmptyOverlay {
                            EmptyStateView(
                                title: String(localized: "ui.InstalledAppsView.d9561df7db"),
                                systemImage: "lock.shield",
                                description: String(localized: "ui.InstalledAppsView.c40e83fce1"),
                                actions: [
                                    EmptyStateAction(title: viewModel.isInstallingBrewVulnsPlugin ? String(localized: "ui.InstalledAppsView.c8f8c93798") : String(localized: "ui.InstalledAppsView.b5a870e05a")) {
                                        Task { await viewModel.installBrewVulnsPlugin() }
                                    },
                                    EmptyStateAction(title: String(localized: "ui.InstalledAppsView.06a3c111c0")) {
                                        if let url = URL(string: "https://github.com/Homebrew/homebrew-brew-vulns") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                ]
                            )
                        }
                    case .scanFailed(let message):
                        installedEmptyOverlay {
                            EmptyStateView(
                                title: String(localized: "ui.InstalledAppsView.5ec14542d7"),
                                systemImage: "wifi.exclamationmark",
                                description: message,
                                actions: [
                                    EmptyStateAction(title: String(localized: "ui.InstalledAppsView.132c5cdc")) {
                                        Task { await viewModel.loadBrewVulnerabilities(force: true) }
                                    }
                                ]
                            )
                        }
                    case .clean:
                        installedEmptyOverlay {
                            EmptyStateView(
                                title: String(localized: "ui.InstalledAppsView.925e4ce21b"),
                                systemImage: "checkmark.shield",
                                description: String(localized: "ui.InstalledAppsView.6dfa209af7"),
                                actions: [
                                    EmptyStateAction(title: String(localized: "ui.InstalledAppsView.75e1781b")) {
                                        Task { await viewModel.loadBrewVulnerabilities(force: true) }
                                    }
                                ]
                            )
                        }
                    case .foundIssues:
                        EmptyView()
                    }
                } else {
                    installedEmptyOverlay {
                        EmptyStateView(
                            title: String(localized: "ui.InstalledAppsView.4fa30feaaa"),
                            systemImage: "shield.lefthalf.filled",
                            description: String(localized: "ui.InstalledAppsView.e8f5c0df72"),
                            actions: [
                                EmptyStateAction(title: String(localized: "ui.InstalledAppsView.65dcdff8fc")) {
                                    Task { await viewModel.loadBrewVulnerabilities(force: true) }
                                }
                            ]
                        )
                    }
                }
            }
        }
    }

    private func securityScanHeader(scan: BrewVulnerabilityScan, allClear: Bool) -> some View {
        HStack {
            Label(
                scan.summaryLine ?? (allClear ? String(localized: "ui.InstalledAppsView.1df790ce75") : String(format: String(localized: "ui.InstalledAppsView.fmt.6a9967632b"), locale: .current, "\(scan.totalFindings)")),
                systemImage: allClear ? "checkmark.shield" : "exclamationmark.shield"
            )
            .font(.subheadline)
            .foregroundStyle(allClear ? .green : .orange)
            Spacer()
            Button(String(localized: "ui.InstalledAppsView.75e1781b")) {
                Task { await viewModel.loadBrewVulnerabilities(force: true) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoadingBrewVulns)
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 10)
    }

    private func severityBackground(for severity: String) -> Color {
        switch severity.uppercased() {
        case "CRITICAL", "HIGH": return Color.red.opacity(0.15)
        case "MEDIUM": return Color.orange.opacity(0.15)
        default: return Color.secondary.opacity(0.12)
        }
    }

    private func severityForeground(for severity: String) -> Color {
        switch severity.uppercased() {
        case "CRITICAL", "HIGH": return .red
        case "MEDIUM": return .orange
        default: return .secondary
        }
    }

    @ViewBuilder
    private func serviceButton(
        _ title: String,
        service: BrewServiceItem,
        action: BrewServiceAction,
        prominent: Bool = false
    ) -> some View {
        let actionID = "\(service.name)-\(action.rawValue)"
        if prominent {
            Button(title) {
                Task { await viewModel.runBrewService(name: service.name, action: action) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.brewServiceActionID == actionID)
        } else {
            Button(title) {
                Task { await viewModel.runBrewService(name: service.name, action: action) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.brewServiceActionID == actionID)
        }
    }

    @ViewBuilder
    private var catalogMatchedList: some View {
        let items = viewModel.installedSnapshot.map { filteredCatalogItems(from: $0) } ?? []
        installedListShell {
            List {
                Color.clear
                    .frame(height: InstalledAppsLayout.catalogFilterBarHeight)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityHidden(true)

                ForEach(items) { item in
                    HStack(spacing: 12) {
                        ToolIconView(tool: item.tool, size: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.tool.name).font(.body)
                            Text(item.tool.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(item.sourceLabel)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                            .foregroundStyle(.secondary)

                        if item.canOpen {
                            Button(String(localized: "ui.InstalledAppsView.d7098f50")) {
                                viewModel.openInstalledTool(item.tool)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Text(String(localized: "ui.InstalledAppsView.dbb0d3bb03"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } overlay: {
            if viewModel.isScanningInstalled && viewModel.installedSnapshot == nil {
                installedLoadingOverlay(String(localized: "ui.InstalledAppsView.360748fff0"))
            } else if items.isEmpty {
                installedEmptyOverlay {
                    EmptyStateView(
                        title: String(localized: "ui.InstalledAppsView.55e0debf18"),
                        systemImage: "tray",
                        description: catalogSearchText.isEmpty
                            ? String(format: String(localized: "ui.InstalledAppsView.fmt.2f6e0b1046"), locale: .current, "\(viewModel.localApplications.count)")
                            : String(format: String(localized: "ui.InstalledAppsView.fmt.1926347de6"), locale: .current, "\(catalogSearchText)")
                    )
                }
            }
        }
    }

    private func filteredCatalogItems(from snapshot: InstalledStatusSnapshot) -> [InstalledCatalogItem] {
        let query = catalogSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return viewModel.allCatalogTools.compactMap { tool -> InstalledCatalogItem? in
            guard snapshot.state(for: tool) == .installed else { return nil }
            switch filterKind {
            case .all: break
            case .cli where tool.resolvedKind != .cli: return nil
            case .gui where tool.resolvedKind != .gui: return nil
            default: break
            }
            guard query.isEmpty || tool.matchesDiscoverSearch(query) else { return nil }
            return InstalledCatalogItem(
                tool: tool,
                sourceLabel: sourceLabel(for: tool.source),
                canOpen: tool.source.type == .cask || tool.source.type == .mas || tool.source.type == .link
            )
        }
        .sorted { $0.tool.name.localizedCaseInsensitiveCompare($1.tool.name) == .orderedAscending }
    }

    private func sourceLabel(for source: InstallSource) -> String {
        switch source.type {
        case .formula: return "brew"
        case .cask: return "cask"
        case .mas: return "mas"
        case .script: return "script"
        case .link: return "link"
        }
    }

    @ViewBuilder
    private var installHistoryPanel: some View {
        installedListShell {
            List {
                let stats = InstallHistoryStore.shared.stats
                if !stats.isEmpty {
                    Section {
                        HStack(spacing: 24) {
                            installStatCell(title: String(localized: "ui.InstalledAppsView.92a3dc3a4a"), value: "\(stats.sessionCount)")
                            installStatCell(title: String(localized: "ui.InstalledAppsView.1e582b1b5d"), value: "\(stats.totalTools)")
                            installStatCell(title: String(localized: "ui.InstalledAppsView.c73a9abab0"), value: stats.estimatedTimeLabel)
                        }
                        .padding(.vertical, 8)
                        Text(String(localized: "ui.InstalledAppsView.b03e2c238a"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    let topQuality = CatalogQualityStore.shared.topVerified(limit: 6)
                    if !topQuality.isEmpty {
                        Section(String(localized: "ui.InstalledAppsView.2f87b2ffce")) {
                            ForEach(topQuality) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(viewModel.catalogTool(id: item.toolID)?.name ?? item.toolID)
                                            .font(.subheadline.weight(.medium))
                                        Text(item.summaryLine)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    CatalogQualityBadgeView(quality: item, compact: true)
                                }
                            }
                            Text(String(localized: "ui.InstalledAppsView.a59ed1bedf"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if viewModel.settings.usageFrequencyTrackingEnabled {
                        let topUsage = UsageFrequencyStore.shared.topTools(limit: 8)
                        if !topUsage.isEmpty {
                            Section(String(localized: "ui.InstalledAppsView.29ae7ebdcf")) {
                                ForEach(topUsage) { item in
                                    HStack {
                                        Text(viewModel.catalogTool(id: item.toolID)?.name ?? item.toolID)
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Text(String(format: String(localized: "ui.InstalledAppsView.fmt.b8aaacaa26"), locale: .current, "\(item.openCount)", "\(item.installCount)"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Button(String(localized: "ui.InstalledAppsView.a1a92ef110")) {
                                    UsageFrequencyStore.shared.clearAll()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                    }

                    Section {
                        InstallHistoryChartSection(entries: InstallHistoryStore.shared.entries)
                    }
                }

                Section {
                    ForEach(
                        InstallHistoryAnalytics.filtered(
                            entries: InstallHistoryStore.shared.entries,
                            range: .all,
                            source: .all
                        )
                    ) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.source == .discover ? String(localized: "ui.InstalledAppsView.336b6e9cb7") : String(localized: "ui.InstalledAppsView.8402fcdd8d"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(entry.roleLabel)
                            .font(.body)
                        Text(entry.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    }
                }
            }
        } overlay: {
            if InstallHistoryStore.shared.entries.isEmpty {
                installedEmptyOverlay {
                    EmptyStateView(
                        title: String(localized: "ui.InstalledAppsView.cf49e9d7d3"),
                        systemImage: "calendar",
                        description: String(localized: "ui.InstalledAppsView.7d2478c280")
                    )
                }
            }
        }
    }

    private func installStatCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InstalledAppsDialogsModifier: ViewModifier {
    @Bindable var viewModel: AppViewModel
    @Binding var trustFixTarget: TrustFixTarget?
    @Binding var dependencyFormulaSheet: FormulaDependencyTarget?
    @Binding var reverseDependencyFormulaSheet: FormulaDependencyTarget?
    @Binding var showUninstallConfirm: Bool
    let uninstallConfirmMessage: String
    @Binding var showCleanupConfirm: Bool

    func body(content: Content) -> some View {
        content
            .sheet(item: $trustFixTarget) { target in
                AppTrustFixSheet(appPath: target.path) { report in
                    viewModel.rememberTrustReport(report)
                }
            }
            .sheet(item: $dependencyFormulaSheet) { target in
                FormulaDependencySheet(formula: target.name)
                    .environment(viewModel)
            }
            .sheet(item: $reverseDependencyFormulaSheet) { target in
                FormulaReverseDependencySheet(formula: target.name)
                    .environment(viewModel)
            }
            .alert(String(localized: "installed.confirm_uninstall"), isPresented: $showUninstallConfirm) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "installed.uninstall"), role: .destructive) {
                    Task { await viewModel.uninstallSelectedTools() }
                }
            } message: {
                Text(uninstallConfirmMessage)
            }
            .alert(String(localized: "ui.InstalledAppsView.02d9819dda"), isPresented: maintenanceAlertBinding) {
                Button(String(localized: "ui.InstalledAppsView.ac2c8f13c6")) { viewModel.maintenanceStatusMessage = nil }
            } message: {
                Text(viewModel.maintenanceStatusMessage ?? "")
            }
            .alert(String(localized: "ui.InstalledAppsView.dbe4ba7587"), isPresented: $showCleanupConfirm) {
                Button(String(localized: "ui.InstalledAppsView.625fb26b"), role: .cancel) {}
                Button(String(localized: "ui.InstalledAppsView.e47bb1cd"), role: .destructive) {
                    Task { await viewModel.runBrewCleanup() }
                }
            } message: {
                Text(String(localized: "ui.InstalledAppsView.781eab2087"))
            }
    }

    private var maintenanceAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.maintenanceStatusMessage != nil },
            set: { if !$0 { viewModel.maintenanceStatusMessage = nil } }
        )
    }
}

private struct InstalledListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
    }
}

private enum InstalledAppsLayout {
    static let scopePickerHeight: CGFloat = 44
    /// 目录匹配「类型」筛选行高度（与 scopeSecondaryBar catalog 分支一致）
    static let catalogFilterBarHeight: CGFloat = 44
    static let secondaryToolbarHeight: CGFloat = 44
    static let updateBannerHeight: CGFloat = 52
}

private struct TrustFixTarget: Identifiable {
    let path: String
    var id: String { path }
}

private struct FormulaDependencyTarget: Identifiable {
    let name: String
    var id: String { name }
}

private struct InstalledCatalogItem: Identifiable {
    let tool: DevTool
    let sourceLabel: String
    let canOpen: Bool

    var id: String { tool.id }
}

#Preview {
    InstalledAppsView()
        .environment(AppViewModel())
        .frame(width: 800, height: 600)
}

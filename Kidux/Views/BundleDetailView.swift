import SwiftUI
import TipKit

struct BundleDetailView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var searchText = ""

    @State private var showRoleReadme = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolList
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
            if !viewModel.postInstallSteps.isEmpty {
                postInstallSection
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showRoleReadme) {
            RoleKnowledgeSheet(roles: selectedRolesWithReadme)
        }
        .task {
            await viewModel.scanInstalledStatus()
            await viewModel.checkEnvironment()
        }
    }

    private var selectedRolesWithReadme: [RoleBundle] {
        viewModel.bundleManager.roles.filter {
            viewModel.selectedRoles.contains($0.id) && $0.hasReadme
        }
    }

    private var installSizeEstimate: InstallSizeEstimate {
        InstallSizeEstimate.estimate(
            tools: viewModel.resolvedTools,
            snapshot: viewModel.installedSnapshot
        )
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "roles.tools_list"))
                        .font(.title2.bold())
                    Text(String(localized: "roles.tools_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if viewModel.isScanningInstalled {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("CLI \(viewModel.cliToolCount) · GUI \(viewModel.guiToolCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(format: String(localized: "ui.BundleDetailView.fmt.f071a87bdc"), locale: .current, "\(viewModel.selectedToolCount)", "\(viewModel.resolvedTools.count)"))
                    .font(.headline)
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField(String(localized: "ui.BundleDetailView.4d19da580c"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !viewModel.environmentStatus.hasSufficientDiskSpace {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text(String(format: String(localized: "ui.bundle.disk_low"), locale: .current, "\(Int(EnvironmentStatus.minimumDiskGB))", "\(viewModel.environmentStatus.diskSpaceLabel)"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if installSizeEstimate.hasItems {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .foregroundStyle(.blue)
                    Text(installSizeEstimate.summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(AppTheme.contentPadding)
    }

    private var filteredTools: [ResolvedTool] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.resolvedTools }
        return viewModel.resolvedTools.filter {
            $0.tool.matchesDiscoverSearch(query)
        }
    }

    private var toolList: some View {
        Group {
            if filteredTools.isEmpty {
                EmptyStateView(
                    title: String(localized: "ui.BundleDetailView.c410d4c54c"),
                    systemImage: "magnifyingglass",
                    description: String(localized: "ui.BundleDetailView.eacbc222")
                )
            } else {
                List {
                    ForEach(sortedCategories, id: \.self) { category in
                        Section(categoryLabel(category)) {
                            ForEach(groupedFilteredTools[category] ?? []) { tool in
                                ToolRowView(
                                    tool: tool,
                                    installState: viewModel.installState(for: tool.id),
                                    onToggle: { viewModel.toggleToolSelection(tool.id) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var groupedFilteredTools: [String: [ResolvedTool]] {
        Dictionary(grouping: filteredTools) { $0.tool.category }
    }

    private var sortedCategories: [String] {
        let order = ToolCategory.allCases.map(\.rawValue).filter { $0 != ToolCategory.all.rawValue }
        let keys = Set(groupedFilteredTools.keys)
        return order.filter { keys.contains($0) } + keys.subtracting(order).sorted()
    }

    private var postInstallSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: String(localized: "ui.BundleDetailView.fmt.76cbd41ad6"), locale: .current, "\(viewModel.postInstallSteps.count)"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(viewModel.postInstallSteps) { step in
                    Label(step.name, systemImage: "gearshape")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.1), in: Capsule())
                }
            }
        }
        .padding(.horizontal, AppTheme.contentPadding)
        .padding(.vertical, 10)
    }

    private func categoryLabel(_ category: String) -> String {
        ToolCategory.label(for: category)
    }

    private var footer: some View {
        HStack {
            Button(String(localized: "ui.BundleDetailView.5f411223ca")) {
                viewModel.currentScreen = .roleSelection
            }
            .keyboardShortcut(.cancelAction)

            if !selectedRolesWithReadme.isEmpty {
                Button {
                    showRoleReadme = true
                } label: {
                    Label(String(localized: "ui.BundleDetailView.96bee624e6"), systemImage: "book.pages")
                }
                .help(String(localized: "ui.BundleDetailView.f7771dd97d"))
            }

            Spacer()

            Button(String(localized: "ui.BundleDetailView.9e3011ca75")) {
                viewModel.exportBootstrapScript()
            }
            .help(String(localized: "ui.BundleDetailView.6f88dad78e"))

            Button(String(localized: "ui.BundleDetailView.647ded95bc")) {
                viewModel.exportMigrationChecklist()
            }
            .help(String(localized: "ui.BundleDetailView.bbf699d5b5"))

            Button(String(localized: "ui.BundleDetailView.4629b49b0a")) {
                Task { await viewModel.presentDryRunSheet() }
            }
            .help(String(localized: "ui.BundleDetailView.81285f4115"))
            .modifier(DryRunInstallTipModifier())

            if viewModel.lastRollbackBatch != nil {
                Button(String(localized: "ui.BundleDetailView.7124a56f60")) {
                    Task { await viewModel.rollbackLastInstallBatch() }
                }
                .help(String(localized: "ui.BundleDetailView.7ce4458b5f"))
            }

            Button(String(localized: "ui.BundleDetailView.bb5ea0f3")) {
                Task { await viewModel.startInstallationWithPreflight() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.selectedToolCount == 0 || !viewModel.environmentStatus.hasSufficientDiskSpace || viewModel.isAnalyzingPreflight)
            .keyboardShortcut(.defaultAction)
        }
        .padding(AppTheme.contentPadding)
    }
}

/// S19-05 — 岗位知识库 Sheet
private struct DryRunInstallTipModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.popoverTip(DryRunInstallTip())
        } else {
            content
        }
    }
}

struct RoleKnowledgeSheet: View {
    let roles: [RoleBundle]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(String(localized: "ui.BundleDetailView.a4724a46ed"), systemImage: "book.pages")
                    .font(.title3.bold())
                Spacer()
                Button(String(localized: "ui.BundleDetailView.769d88e425")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(roles) { role in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(role.name, systemImage: role.icon)
                                .font(.headline)
                            Text(role.readme ?? "")
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

#Preview {
    BundleDetailView()
        .environment({
            let vm = AppViewModel()
            vm.selectedRoles = ["fullstack_developer"]
            vm.refreshResolvedTools()
            return vm
        }())
        .frame(width: 900, height: 600)
}

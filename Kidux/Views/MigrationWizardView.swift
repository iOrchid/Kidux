import SwiftUI

/// S16-02 换机引导 Wizard（独立于营销 Onboarding）
struct MigrationWizardView: View {
    @Environment(AppViewModel.self) private var viewModel
    var onComplete: () -> Void

    @State private var selectedRole: MigrationMacRole?
    @State private var stepIndex = 0
    @State private var didExportSnapshot = false
    @State private var didImportSnapshot = false

    private var activeSteps: [MigrationWizardStep] {
        guard let role = selectedRole else { return [.welcome] }
        return MigrationWizardStep.steps(for: role)
    }

    private var currentStep: MigrationWizardStep {
        activeSteps[min(stepIndex, activeSteps.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            stepContent
                .id("\(selectedRole?.rawValue ?? "none")-\(stepIndex)")
                .animation(.easeInOut(duration: 0.22), value: stepIndex)
            stepIndicator
            Divider()
            bottomBar
        }
        .frame(minWidth: 580, minHeight: 540)
        .background(AppTheme.pageBackground(style: .classic))
    }

    private var topBar: some View {
        HStack {
            Label(String(localized: "ui.MigrationWizardView.5b4046ac6a"), systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Spacer()
            Button(String(localized: "ui.MigrationWizardView.b15d91274e")) { onComplete() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .exportSnapshot:
                    exportStep
                case .importSnapshot:
                    importStep
                case .reviewBundle:
                    reviewStep
                case .finish:
                    finishStep
                }
            }
            .padding(28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(String(localized: "ui.MigrationWizardView.cb77c1fba0"))
                .font(.title2.bold())
            Text(String(localized: "ui.MigrationWizardView.22a88e5263"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(MigrationMacRole.allCases) { role in
                Button {
                    selectedRole = role
                    withAnimation { stepIndex = 1 }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: role.icon)
                            .font(.title2)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(role.title)
                                .font(.headline)
                            Text(role.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.cardStroke)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var exportStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "ui.MigrationWizardView.51e370d481"))
                .font(.title2.bold())
            Text(String(localized: "ui.MigrationWizardView.de0d59a18c"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            bullet(String(localized: "ui.MigrationWizardView.ccd7d77475"))
            bullet(String(localized: "ui.MigrationWizardView.aff460acd9"))

            Button(String(localized: "ui.MigrationWizardView.75c5994b71")) {
                viewModel.exportEnvironmentSnapshot()
                didExportSnapshot = true
            }
            .buttonStyle(.borderedProminent)

            if didExportSnapshot {
                Label(String(localized: "ui.MigrationWizardView.10da8b482a"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Divider()

            Text(String(localized: "ui.MigrationWizardView.c5631f76d9"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(String(localized: "ui.MigrationWizardView.ca814a1839")) {
                viewModel.exportMigrationChecklist()
            }
            .buttonStyle(.bordered)
        }
    }

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "ui.MigrationWizardView.c4420cb17f"))
                .font(.title2.bold())
            Text(String(localized: "ui.MigrationWizardView.11abdba941"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(String(localized: "ui.MigrationWizardView.c535b32106")) {
                viewModel.importEnvironmentSnapshotPanel()
                didImportSnapshot = true
            }
            .buttonStyle(.borderedProminent)

            if didImportSnapshot {
                Label(String(localized: "ui.MigrationWizardView.ece4fbf28e"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let msg = viewModel.extendedCatalogStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "ui.MigrationWizardView.23448022a3"))
                .font(.title2.bold())

            if viewModel.selectedRoles.isEmpty && viewModel.migrationRecommendations.isEmpty {
                Text(String(localized: "ui.MigrationWizardView.5e8b31dcbc"))
                    .foregroundStyle(.orange)
            } else {
                if !viewModel.selectedRoles.isEmpty {
                    let roleNames = viewModel.bundleManager.roles
                        .filter { viewModel.selectedRoles.contains($0.id) }
                        .map(\.name)
                    Text(String(format: String(localized: "ui.migration.roles_prefix"), locale: .current, "\(roleNames.joined(separator: "、"))"))
                        .font(.subheadline)
                    Text(String(format: String(localized: "ui.MigrationWizardView.fmt.c73e50333e"), locale: .current, "\(viewModel.selectedToolCount)", "\(viewModel.resolvedTools.count)"))
                        .font(.headline)
                        .foregroundStyle(.blue)
                }

                if !viewModel.environmentStatus.hasSufficientDiskSpace {
                    Label(String(localized: "ui.MigrationWizardView.a6a543c95d"), systemImage: "externaldrive.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label(viewModel.environmentStatus.diskSpaceLabel, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                migrationRecommendationSection

                Button(String(localized: "ui.MigrationWizardView.79090a7014")) {
                    viewModel.proceedToBundleDetail()
                    onComplete()
                }
                .buttonStyle(.bordered)
            }
        }
        .task(id: viewModel.lastImportedEnvironmentSnapshot?.exportedAt) {
            if viewModel.migrationRecommendations.isEmpty,
               viewModel.lastImportedEnvironmentSnapshot != nil || viewModel.environmentDriftReport != nil
            {
                await viewModel.refreshMigrationRecommendations()
            }
        }
    }

    @ViewBuilder
    private var migrationRecommendationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "ui.MigrationWizardView.0c1aa1f463"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if viewModel.isRefreshingMigrationRecommendations {
                    ProgressView().controlSize(.small)
                } else {
                    Button(String(localized: "ui.MigrationWizardView.694fc5efa9")) {
                        Task { await viewModel.refreshMigrationRecommendations() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            if viewModel.migrationRecommendations.isEmpty {
                Text(String(localized: "ui.MigrationWizardView.4a8ef241ea"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: String(localized: "ui.MigrationWizardView.fmt.4244fe3cb4"), locale: .current, "\(viewModel.migrationRecommendations.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(String(localized: "ui.MigrationWizardView.66eeacd93a")) { viewModel.selectAllMigrationRecommendations(true) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(String(localized: "ui.MigrationWizardView.1011955431")) { viewModel.selectAllMigrationRecommendations(false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(String(localized: "ui.MigrationWizardView.0ad6a3c764")) {
                        viewModel.applySelectedMigrationRecommendations()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.selectedMigrationRecommendationIDs.isEmpty)
                }

                ForEach(viewModel.migrationRecommendations.prefix(12)) { item in
                    Toggle(isOn: Binding(
                        get: { viewModel.selectedMigrationRecommendationIDs.contains(item.id) },
                        set: { on in
                            if on {
                                viewModel.selectedMigrationRecommendationIDs.insert(item.id)
                            } else {
                                viewModel.selectedMigrationRecommendationIDs.remove(item.id)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.toolName)
                                .font(.subheadline.weight(.medium))
                            Text(item.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                if viewModel.migrationRecommendations.count > 12 {
                    Text(String(format: String(localized: "ui.MigrationWizardView.fmt.e41033bf6a"), locale: .current, "\(viewModel.migrationRecommendations.count - 12)"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(selectedRole == .source ? String(localized: "ui.MigrationWizardView.8afbc8dda6") : String(localized: "ui.MigrationWizardView.db48393e47"))
                .font(.title2.bold())

            if selectedRole == .source {
                Text(String(localized: "ui.MigrationWizardView.83c967f1e2"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "ui.MigrationWizardView.90787d80a6"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button(String(localized: "ui.MigrationWizardView.bb5ea0f3cf")) {
                        Task {
                            await viewModel.startInstallation()
                            onComplete()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedToolCount == 0)

                    Button(String(localized: "ui.MigrationWizardView.9e3011ca75")) {
                        viewModel.exportBootstrapScript()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button(String(localized: "ui.MigrationWizardView.ca814a1839")) {
                viewModel.exportMigrationChecklist()
            }
            .buttonStyle(.bordered)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.accentColor)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Array(activeSteps.enumerated()), id: \.offset) { index, step in
                Capsule()
                    .fill(index == stepIndex ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: index == stepIndex ? 24 : 8, height: 8)
            }
        }
        .padding(.vertical, 14)
    }

    private var bottomBar: some View {
        HStack {
            if stepIndex > 0 {
                Button(String(localized: "ui.MigrationWizardView.eeb6908870")) {
                    withAnimation {
                        if stepIndex == 1 {
                            selectedRole = nil
                        }
                        stepIndex = max(0, stepIndex - 1)
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep == .finish {
                Button(String(localized: "ui.MigrationWizardView.769d88e425")) { onComplete() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if stepIndex > 0 {
                Button(String(localized: "ui.MigrationWizardView.38ce27d846")) {
                    withAnimation { stepIndex = min(stepIndex + 1, activeSteps.count - 1) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(nextDisabled)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var nextDisabled: Bool {
        switch currentStep {
        case .importSnapshot:
            return viewModel.selectedRoles.isEmpty && !didImportSnapshot
        case .reviewBundle:
            return viewModel.selectedRoles.isEmpty && viewModel.migrationRecommendations.isEmpty
        default:
            return false
        }
    }
}

#Preview {
    MigrationWizardView(onComplete: {})
        .environment(AppViewModel())
        .frame(width: 640, height: 580)
}

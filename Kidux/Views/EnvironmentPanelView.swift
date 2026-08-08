import SwiftUI

struct EnvironmentPanelView: View {
    @Environment(AppViewModel.self) private var viewModel

    private let runtimeColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)
    ]

    var body: some View {
        ClassicPageScaffold(
            title: String(localized: "page.environment.title"),
            subtitle: environmentSubtitle,
            headerTrailing: {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    PageHeaderRescanButton(
                        isLoading: viewModel.isScanningRuntimeEnvironment
                    ) {
                        Task { await viewModel.scanRuntimeEnvironment(force: true) }
                    }
                }
            },
            content: { environmentBody }
        )
        .task(id: "environment-scan") {
            await viewModel.scanRuntimeEnvironment()
        }
    }

    @ViewBuilder
    private var environmentBody: some View {
        // 稳定内容壳 + overlay，避免扫描中整页替换导致「一直转圈」感。
        ClassicPageScrollContent {
            VStack(alignment: .leading, spacing: 28) {
                runtimeSection
                versionManagerSection
                serviceSection
                driftSection
            }
        }
        .overlay {
            if viewModel.isScanningRuntimeEnvironment, viewModel.runtimeProfiles.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(String(localized: "page.environment.scanning"))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var environmentSubtitle: String {
        let installed = viewModel.runtimeProfiles.filter(\.isInstalled).count
        let healthy = viewModel.localServiceHealth.filter(\.isHealthy).count
        if let scannedAt = viewModel.runtimeEnvironmentScannedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            let when = formatter.localizedString(for: scannedAt, relativeTo: Date())
            return String(format: String(localized: "ui.EnvironmentPanelView.fmt.9893e2f8b2"), locale: .current, "\(installed)", "\(healthy)", "\(when)")
        }
        return String(localized: "page.environment.subtitle")
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(String(localized: "environment.runtime"), systemImage: "terminal")

            LazyVGrid(columns: runtimeColumns, alignment: .leading, spacing: 16) {
                ForEach(viewModel.runtimeProfiles) { profile in
                    runtimeCard(profile)
                }
            }
        }
    }

    private var versionManagerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(String(localized: "environment.version_managers"), systemImage: "square.stack.3d.up")

            Text(String(localized: "ui.EnvironmentPanelView.13b5f0fa29"))
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: runtimeColumns, alignment: .leading, spacing: 16) {
                ForEach(viewModel.versionManagerProfiles) { profile in
                    versionManagerCard(profile)
                }
            }
        }
    }

    private func versionManagerCard(_ profile: VersionManagerProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: profile.kind.icon)
                    .font(.title3)
                    .foregroundStyle(profile.isInstalled ? Color.accentColor : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.kind.title)
                        .font(.headline)
                    Text(profile.statusLabel)
                        .font(.caption)
                        .foregroundStyle(profile.isInstalled ? .green : .secondary)
                }

                Spacer(minLength: 0)
            }

            Text(profile.displaySummary)
                .font(.subheadline.monospaced())
                .lineLimit(3)
                .foregroundStyle(profile.isInstalled ? .primary : .secondary)

            if !profile.detailLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(profile.detailLines.prefix(5).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if profile.detailLines.count > 5 {
                        Text(String(format: String(localized: "ui.EnvironmentPanelView.fmt.91bec02707"), locale: .current, "\(profile.detailLines.count - 5)"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let path = profile.executablePath {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(String(localized: "environment.services"), systemImage: "point.3.connected.trianglepath.dotted")

            VStack(spacing: 10) {
                ForEach(viewModel.localServiceHealth) { service in
                    serviceRow(service)
                }
            }

            if !viewModel.brewServices.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                sectionTitle(String(localized: "environment.brew_services"), systemImage: "gearshape.2")
                    .font(.subheadline)

                VStack(spacing: 8) {
                    ForEach(viewModel.brewServices) { service in
                        brewServiceRow(service)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func runtimeCard(_ profile: RuntimeProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: profile.kind.icon)
                    .font(.title3)
                    .foregroundStyle(profile.isInstalled ? Color.accentColor : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.kind.title)
                        .font(.headline)
                    Text(profile.statusLabel)
                        .font(.caption)
                        .foregroundStyle(profile.isInstalled ? .green : .secondary)
                }

                Spacer(minLength: 0)
            }

            Text(profile.displayVersion)
                .font(.subheadline.monospaced())
                .lineLimit(2)
                .foregroundStyle(profile.isInstalled ? .primary : .secondary)

            if let path = profile.executablePath {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func serviceRow(_ service: LocalServiceHealth) -> some View {
        HStack(spacing: 12) {
            Image(systemName: service.kind.icon)
                .frame(width: 24)
                .foregroundStyle(service.isHealthy ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.kind.title)
                    .font(.body.weight(.medium))
                Text(service.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(service.state.label)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(statusColor(service.state).opacity(0.14), in: Capsule())
                .foregroundStyle(statusColor(service.state))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func brewServiceRow(_ service: BrewServiceItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: service.isRunning ? "circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(service.isRunning ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.body.monospaced())
                Text(service.statusLabel)
                    .font(.caption)
                    .foregroundStyle(service.status == "error" ? .red : .secondary)
            }

            Spacer(minLength: 8)

            Text(service.isRunning ? String(localized: "ui.EnvironmentPanelView.d679aea3") : String(localized: "ui.EnvironmentPanelView.829778546a"))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(service.isRunning ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(service.isRunning ? .green : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statusColor(_ state: LocalServiceHealthState) -> Color {
        switch state {
        case .running: return .green
        case .installed: return .orange
        case .notInstalled: return .secondary
        case .unreachable: return .red
        }
    }

    private var driftSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle(String(localized: "environment.drift"), systemImage: "arrow.triangle.branch")
                Spacer(minLength: 8)
                if viewModel.hasEnvironmentDriftBaseline {
                    Button(String(localized: "ui.EnvironmentPanelView.8ddfef4c90")) {
                        Task { await viewModel.compareEnvironmentDrift(force: true) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isComparingEnvironmentDrift)
                }
                Button(String(localized: "ui.EnvironmentPanelView.647ded95bc")) {
                    viewModel.exportMigrationChecklist()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(String(localized: "ui.EnvironmentPanelView.1cd09a56")) {
                    Task { await viewModel.captureEnvironmentDriftBaseline() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isComparingEnvironmentDrift)
            }

            if viewModel.hasEnvironmentDriftBaseline {
                Text(String(format: String(localized: "ui.EnvironmentPanelView.fmt.57c44b4b74"), locale: .current, "\(viewModel.environmentDriftBaselineLabel)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let staleCaption = viewModel.environmentDriftBaselineStaleCaption {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(staleCaption)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text(String(localized: "ui.EnvironmentPanelView.84fcb7a89b"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isComparingEnvironmentDrift, viewModel.environmentDriftReport == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "ui.EnvironmentPanelView.d9e6bdd2b1"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let report = viewModel.environmentDriftReport {
                driftSummaryCard(report)
                if report.hasDrift {
                    HStack(spacing: 10) {
                        Button {
                            Task { await viewModel.explainEnvironmentDriftWithAI() }
                        } label: {
                            if viewModel.isExplainingEnvironmentDrift {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(String(localized: "ui.EnvironmentPanelView.8664df6540"), systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(viewModel.isExplainingEnvironmentDrift)

                        if viewModel.environmentDriftExplanation != nil {
                            Button(String(localized: "ui.EnvironmentPanelView.97544797cc")) {
                                viewModel.environmentDriftExplanation = nil
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }

                        let fixPlan = EnvironmentDriftService.suggestFixes(from: report)
                        if fixPlan.hasInstallableMissing {
                            Button {
                                Task { await viewModel.installDriftMissingPackages() }
                            } label: {
                                if viewModel.isInstallingDriftMissing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(String(localized: "ui.EnvironmentPanelView.22b4345617"), systemImage: "arrow.down.circle")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(viewModel.isInstallingDriftMissing)
                            .help(fixPlan.summary)
                        }
                    }

                    if let explanation = viewModel.environmentDriftExplanation {
                        driftExplanationCard(explanation)
                    }

                    VStack(spacing: 8) {
                        ForEach(report.items.prefix(20)) { item in
                            driftRow(item)
                        }
                        if report.items.count > 20 {
                            Text(String(format: String(localized: "ui.EnvironmentPanelView.fmt.3bb6c0baec"), locale: .current, "\(report.items.count - 20)"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if let msg = viewModel.environmentDriftStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func driftSummaryCard(_ report: EnvironmentDriftReport) -> some View {
        HStack(spacing: 10) {
            Image(systemName: report.hasDrift ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .foregroundStyle(report.hasDrift ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.summaryLine)
                    .font(.subheadline.weight(.medium))
                Text(String(format: String(localized: "ui.EnvironmentPanelView.fmt.13d2b1a9fc"), locale: .current, "\(report.comparedAt.formatted(date: .abbreviated, time: .shortened))"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            (report.hasDrift ? Color.orange : Color.green).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func driftExplanationCard(_ explanation: EnvironmentDriftExplanation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(Color.accentColor)
                Text(explanation.sourceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(explanation.summary)
                .font(.subheadline.weight(.medium))
            Text(explanation.narrative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !explanation.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "ui.EnvironmentPanelView.19444e70d7"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(explanation.suggestedActions.enumerated()), id: \.offset) { index, action in
                        Text("\(index + 1). \(action)")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func driftRow(_ item: EnvironmentDriftItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(driftKindLabel(item.kind))
                .font(.caption2.bold())
                .frame(width: 36, alignment: .leading)
                .foregroundStyle(driftKindColor(item.kind))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.monospaced())
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func driftKindLabel(_ kind: EnvironmentDriftItem.Kind) -> String {
        switch kind {
        case .missing: return String(localized: "ui.EnvironmentPanelView.d56b7e3c42")
        case .extra: return String(localized: "ui.EnvironmentPanelView.95f838a536")
        case .changed: return String(localized: "ui.EnvironmentPanelView.1dd554cdfc")
        }
    }

    private func driftKindColor(_ kind: EnvironmentDriftItem.Kind) -> Color {
        switch kind {
        case .missing: return .orange
        case .extra: return .blue
        case .changed: return .purple
        }
    }
}

#Preview {
    EnvironmentPanelView()
        .environment(AppViewModel())
        .frame(width: 900, height: 700)
}

import SwiftUI

struct InstallDryRunView: View {
    let plan: InstallDryRunPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    summaryCard
                    if let preflight = plan.preflight {
                        preflightSection(preflight)
                    }
                    ForEach(plan.items) { item in
                        itemRow(item)
                    }
                    if !plan.postInstallSteps.isEmpty {
                        postInstallSection
                    }
                }
                .padding(AppTheme.contentPadding)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "ui.InstallDryRunView.a9fab53390"))
                    .font(.title2.bold())
                Text(String(localized: "ui.InstallDryRunView.1ba7b5f6a8"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "ui.InstallDryRunView.b15d91274e")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(AppTheme.contentPadding)
    }

    private var summaryCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(plan.summaryLine)
                .font(.subheadline.bold())
            Spacer()
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func preflightSection(_ report: InstallPreflightReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: report.blocksInstall ? "xmark.octagon.fill" : "checkmark.shield")
                    .foregroundStyle(preflightColor(report.highestSeverity))
                Text(report.summaryLine)
                    .font(.subheadline.bold())
                Spacer()
            }

            if report.findings.isEmpty {
                Text(String(localized: "ui.InstallDryRunView.60f067ee0a"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.findings.prefix(12)) { finding in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: severityIcon(finding.severity))
                                .foregroundStyle(preflightColor(finding.severity))
                            Text(finding.title)
                                .font(.caption.bold())
                            if let name = finding.toolName {
                                Text(name)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                        Text(finding.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let suggestion = finding.suggestion {
                            Text(suggestion)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        if let toolID = finding.toolID,
                           let deps = report.dependencyHints[toolID], !deps.isEmpty {
                            Text(String(format: String(localized: "ui.dryrun.deps"), locale: .current, "\(deps.prefix(8).joined(separator: ", ") + (deps.count > 8 ? String(localized: "ui.common.ellipsis") : ""))"))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(preflightColor(finding.severity).opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func itemRow(_ item: InstallDryRunItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.body.bold())
                Text(item.sourceLabel)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                if item.willSkip {
                    Text(String(localized: "ui.InstallDryRunView.dc6a277a49"))
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
                if item.isManual {
                    Text(String(localized: "ui.InstallDryRunView.2a3e7f5c38"))
                        .font(.caption2.bold())
                        .foregroundStyle(.teal)
                }
                Spacer()
            }
            Text(item.command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ForEach(item.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let deps = plan.preflight?.dependencyHints[item.id], !deps.isEmpty {
                Text(String(format: String(localized: "ui.dryrun.will_install_deps"), locale: .current, "\(deps.prefix(6).joined(separator: ", ") + (deps.count > 6 ? String(localized: "ui.common.ellipsis") : ""))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.cardStroke)
        )
    }

    private var postInstallSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "ui.InstallDryRunView.a773dd27f6"))
                .font(.subheadline.bold())
            ForEach(plan.postInstallSteps, id: \.name) { step in
                HStack {
                    Image(systemName: "gearshape.2")
                        .foregroundStyle(.secondary)
                    Text(step.name)
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(String(localized: "ui.InstallDryRunView.b15d91274e")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(AppTheme.contentPadding)
    }

    private func preflightColor(_ severity: InstallPreflightSeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func severityIcon(_ severity: InstallPreflightSeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

#Preview {
    InstallDryRunView(
        plan: InstallDryRunPlan(
            items: [
                InstallDryRunItem(
                    id: "git",
                    name: "Git",
                    command: "brew install git",
                    sourceLabel: "formula",
                    willSkip: true,
                    isManual: false,
                    warnings: []
                )
            ],
            postInstallSteps: [],
            skippedCount: 1,
            manualCount: 0,
            executableCount: 0,
            preflight: InstallPreflightReport(findings: [], dependencyHints: [:], analyzedCount: 1)
        )
    )
}

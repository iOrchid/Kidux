import SwiftUI
import AppKit

struct AppTrustFixSheet: View {
    let appPath: String
    var onReportUpdated: ((AppTrustReport) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var report: AppTrustReport?
    @State private var isLoading = true
    @State private var isFixing = false
    @State private var fixMessage: String?
    @State private var fixError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(String(localized: "trust.sheet.title"), systemImage: "shield.checkered")
                    .font(.title2.bold())
                Spacer()
                Button(String(localized: "common.close")) { dismiss() }
                    .buttonStyle(.borderless)
            }

            if isLoading {
                ProgressView(String(localized: "trust.sheet.diagnosing"))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let report {
                diagnosisContent(report)
            }

            if let fixMessage {
                Text(fixMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let fixError {
                Text(fixError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 480)
        .task { await loadReport(force: true) }
    }

    @ViewBuilder
    private func diagnosisContent(_ report: AppTrustReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.appName)
                .font(.headline)
            Text(report.appPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            switch report.probeStatus {
            case .unknown:
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "trust.summary.unknown"))
                            .font(.subheadline.bold())
                        Text(String(localized: "trust.sheet.unknown.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                Button {
                    Task { await loadReport(force: true) }
                } label: {
                    Label(String(localized: "trust.sheet.retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

            case .needsAttention where !report.issues.isEmpty:
                ForEach(report.issues, id: \.rawValue) { issue in
                    issueCard(issue)
                }

                HStack(spacing: 10) {
                    if report.issues.contains(.quarantine) {
                        Button {
                            Task { await fixQuarantine() }
                        } label: {
                            Label(String(localized: "trust.sheet.clear_quarantine"), systemImage: "bandage")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFixing)
                    }

                    if report.needsSystemSettings {
                        Button {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?General") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label(String(localized: "trust.sheet.open_privacy"), systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                    }
                }

            case .ok, .needsAttention:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "trust.sheet.healthy"))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            Text(String(localized: "trust.sheet.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(localized: "trust.sheet.permission_note"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func issueCard(_ issue: AppTrustIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.subheadline.bold())
                Text(issue.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func loadReport(force: Bool) async {
        isLoading = true
        fixError = nil
        let result = await AppTrustService.shared.diagnose(appPath: appPath, force: force)
        report = result
        onReportUpdated?(result)
        isLoading = false
    }

    private func fixQuarantine() async {
        isFixing = true
        fixError = nil
        fixMessage = nil
        do {
            try await AppTrustService.shared.removeQuarantine(appPath: appPath)
            fixMessage = String(localized: "trust.sheet.cleared")
            await loadReport(force: true)
        } catch {
            fixError = error.localizedDescription
        }
        isFixing = false
    }
}

#Preview {
    AppTrustFixSheet(appPath: "/Applications/Safari.app")
}

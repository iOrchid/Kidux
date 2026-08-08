import SwiftUI

struct MaintenanceProgressSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MaintenanceProgressView(onDismiss: { dismiss() })
            .environment(viewModel)
            .frame(width: BrewProgressLayout.sheetWidth, height: BrewProgressLayout.sheetHeight)
    }
}

private struct MaintenanceProgressView: View {
    @Environment(AppViewModel.self) private var viewModel
    var onDismiss: () -> Void

    @State private var showLog = true

    private var manager: MaintenanceManager { viewModel.maintenanceManager }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                taskPanel
                    .frame(minWidth: 300, idealWidth: 320)
                if showLog {
                    Divider()
                    logPanel
                }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(manager.sessionTitle)
                    .font(.title2.bold())
                Text(String(format: String(localized: "ui.MaintenanceProgressView.fmt.0071b26f64"), locale: .current, "\(manager.completedCount)", "\(manager.tasks.count)", "\(manager.failedCount)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView(value: manager.overallProgress)
                .progressViewStyle(.circular)
                .frame(width: 44, height: 44)
        }
        .padding(20)
    }

    private var taskPanel: some View {
        List(manager.tasks) { task in
            HStack(spacing: 10) {
                statusIcon(for: task.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(.body)
                    Text(task.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let error = task.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
    }

    private var logPanel: some View {
        ScrollView {
            Text(manager.logOutput.isEmpty ? String(localized: "ui.MaintenanceProgressView.0debfc10e2") : manager.logOutput)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
    }

    private var footer: some View {
        HStack {
            Toggle(String(localized: "ui.MaintenanceProgressView.13dd8251d5"), isOn: $showLog)
                .toggleStyle(.checkbox)
            Spacer()
            if manager.isRunning {
                Button(String(localized: "ui.MaintenanceProgressView.625fb26b4b"), role: .destructive) {
                    viewModel.cancelMaintenanceSession()
                }
            }
            Button(manager.isRunning ? String(localized: "ui.MaintenanceProgressView.0dbfcb5a85") : String(localized: "ui.MaintenanceProgressView.b15d91274e")) {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(manager.isRunning)
        }
        .padding(16)
    }

    @ViewBuilder
    private func statusIcon(for status: InstallStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .skipped, .cancelled:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }
}

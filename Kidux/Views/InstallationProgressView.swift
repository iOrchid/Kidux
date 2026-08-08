import SwiftUI
import AppKit

enum InstallationProgressStyle {
    case embedded
    case sheet
}

/// 包装层：从 AppViewModel 取出 InstallManager 并交给 @Bindable 子视图，确保安装进度实时刷新。
struct InstallationProgressView: View {
    @Environment(AppViewModel.self) private var viewModel
    var style: InstallationProgressStyle = .embedded
    var onDismiss: (() -> Void)?

    var body: some View {
        InstallationProgressContent(
            installManager: viewModel.installManager,
            viewModel: viewModel,
            style: style,
            onDismiss: onDismiss
        )
    }
}

private struct InstallationProgressContent: View {
    @Bindable var installManager: InstallManager
    let viewModel: AppViewModel
    var style: InstallationProgressStyle
    var onDismiss: (() -> Void)?

    @State private var showLog = true
    @State private var logCopied = false

    private var progressAccessibilityValue: String {
        if installManager.isFinished, let summary = installManager.summary {
            return String(format: String(localized: "ui.InstallationProgressView.fmt.46cc8bac2e"), locale: .current, "\(summary.succeeded)", "\(summary.failed)", "\(summary.skipped)")
        }
        if let current = installManager.tasks.first(where: { $0.id == installManager.currentTaskID }) {
            return String(format: String(localized: "ui.InstallationProgressView.fmt.d3b79e124a"), locale: .current, "\(current.displayName)", "\(installManager.completedCount)", "\(installManager.tasks.count)")
        }
        return String(format: String(localized: "ui.InstallationProgressView.fmt.fa188204b6"), locale: .current, "\(installManager.tasks.count)")
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            HStack(spacing: 0) {
                taskPanel
                    .frame(minWidth: style == .sheet ? 300 : 340, idealWidth: style == .sheet ? 320 : 380)
                if showLog {
                    Divider()
                    logPanel
                }
            }
            Divider()
            footerActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "ui.InstallationProgressView.d8cfe085"))
        .accessibilityValue(progressAccessibilityValue)
        .onChange(of: installManager.currentTaskID) { _, _ in
            AccessibilityNotification.Announcement(progressAccessibilityValue).post()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headerTitle)
                        .font(style == .sheet ? .title2.bold() : .title.bold())
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                progressRing
            }

            if installManager.awaitingAdminPassword {
                passwordBanner
            }

            if installManager.isCancelled {
                statusBanner(
                    icon: "stop.circle.fill",
                    color: .orange,
                    text: String(localized: "ui.InstallationProgressView.c11ebdc34e")
                )
            } else if installManager.isFinished, let summary = installManager.summary, summary.failed > 0 {
                statusBanner(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    text: String(format: String(localized: "ui.InstallationProgressView.fmt.b63cf4dd36"), locale: .current, "\(summary.failed)")
                )
            }
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, style == .sheet ? 16 : 20)
    }

    private var headerTitle: String {
        if installManager.isCancelled { return String(localized: "ui.InstallationProgressView.c5b4d023c8") }
        if installManager.isFinished { return String(localized: "ui.InstallationProgressView.8bd39e4e") }
        if installManager.isInstalling { return String(localized: "ui.InstallationProgressView.e9471939d7") }
        return String(localized: "ui.InstallationProgressView.1702a1d3d2")
    }

    private var headerSubtitle: String {
        if let current = installManager.currentTask, installManager.isInstalling {
            return String(format: String(localized: "ui.InstallationProgressView.fmt.d50c5d865f"), locale: .current, "\(current.displayName)")
        }
        return String(format: String(localized: "ui.progress.summary_counts"), locale: .current, "\(installManager.tasks.count)", "\(installManager.completedCount)", "\(installManager.failedCount)")
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: installManager.overallProgress)
                .stroke(
                    installManager.isCancelled ? Color.orange : Color.accentColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: installManager.overallProgress)
            Text("\(Int(installManager.overallProgress * 100))%")
                .font(.caption.bold().monospacedDigit())
        }
        .frame(width: 56, height: 56)
    }

    private var passwordBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.blue)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "ui.InstallationProgressView.8630bc2a09"))
                    .font(.subheadline.bold())
                Text(String(localized: "ui.InstallationProgressView.20f36221"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusBanner(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Tasks

    private var taskPanel: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(installManager.tasks) { task in
                    taskRow(task)
                    if task.id != installManager.tasks.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func taskRow(_ task: InstallTask) -> some View {
        HStack(spacing: 10) {
            statusIcon(for: task.status)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.displayName)
                    .font(.body)
                    .lineLimit(1)
                if let error = task.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text(statusLabel(task.status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if task.status == .failed || task.status == .cancelled {
                Button(String(localized: "ui.InstallationProgressView.132c5cdc")) {
                    Task { await viewModel.retryInstallTask(task.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 10)
        .background(task.id == installManager.currentTaskID ? Color.accentColor.opacity(0.06) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.displayName)，\(accessibilityStatus(task.status))")
    }

    // MARK: - Log

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(String(localized: "ui.InstallationProgressView.a94180c214"), systemImage: "terminal")
                    .font(.headline)
                Spacer()
                if !installManager.logOutput.isEmpty {
                    Button {
                        copyInstallLog()
                    } label: {
                        Label(logCopied ? String(localized: "ui.InstallationProgressView.52e6abbe5c") : String(localized: "ui.InstallationProgressView.3615f73472"), systemImage: logCopied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                Button(showLog ? String(localized: "ui.InstallationProgressView.def9e98b60") : String(localized: "ui.InstallationProgressView.e2edde5adb")) {
                    withAnimation(.easeInOut(duration: 0.2)) { showLog.toggle() }
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(installManager.logOutput.isEmpty ? String(localized: "ui.InstallationProgressView.0debfc10e2") : installManager.logOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("logBottom")
                }
                .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(Color(red: 0.75, green: 0.95, blue: 0.75))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .onChange(of: installManager.logOutput) { _, _ in
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack(spacing: 10) {
            if installManager.isInstalling {
                Button(String(localized: "ui.InstallationProgressView.095e938e")) {
                    Task { await viewModel.cancelInstallation() }
                }
                .buttonStyle(.bordered)
                .tint(.red)

                if installManager.pendingCount > 0 {
                    Button(String(localized: "ui.InstallationProgressView.695e624257")) {
                        viewModel.skipRemainingInstallTasks()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button(showLog ? String(localized: "ui.InstallationProgressView.1c160ae9b1") : String(localized: "ui.InstallationProgressView.13dd8251d5")) {
                withAnimation { showLog.toggle() }
            }
            .buttonStyle(.borderless)

            Spacer()

            if style == .sheet {
                if installManager.isInstalling {
                    Button(String(localized: "ui.InstallationProgressView.1a6db952ed")) { onDismiss?() }
                        .buttonStyle(.bordered)
                } else if installManager.isFinished || installManager.isCancelled {
                    Button(String(localized: "ui.InstallationProgressView.b15d9127")) { onDismiss?() }
                        .buttonStyle(.bordered)
                }
            }

            if installManager.isFinished || installManager.isCancelled {
                if installManager.canResumeInstallation {
                    Button {
                        Task {
                            if style == .sheet {
                                await viewModel.resumeDiscoverInstallation()
                            } else {
                                await viewModel.resumeInstallation()
                            }
                        }
                    } label: {
                        Label(String(format: String(localized: "ui.InstallationProgressView.fmt.c9792453d5"), locale: .current, "\(installManager.resumableTaskCount)"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if installManager.failedCount > 0 {
                    Button {
                        viewModel.analyzeInstallFailuresWithAI()
                    } label: {
                        Label(String(localized: "ui.InstallationProgressView.cbcbca50d2"), systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                }

                Button(installManager.isCancelled ? String(localized: "ui.InstallationProgressView.b15d9127") : String(localized: "ui.InstallationProgressView.769d88e425")) {
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .opacity(style == .embedded ? 0 : 1)
                .disabled(style == .embedded)
            }
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func statusIcon(for status: InstallStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .skipped:
            Image(systemName: "forward.circle.fill").foregroundStyle(.orange)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
        }
    }

    private func statusLabel(_ status: InstallStatus) -> String {
        switch status {
        case .pending: return String(localized: "ui.InstallationProgressView.65dd9ef1")
        case .running: return String(localized: "ui.InstallationProgressView.231fd676")
        case .success: return String(localized: "ui.InstallationProgressView.fad5222ca0")
        case .failed: return String(localized: "ui.InstallationProgressView.acd5cb84")
        case .skipped: return String(localized: "ui.InstallationProgressView.4a085478")
        case .cancelled: return String(localized: "ui.InstallationProgressView.2111ccbb")
        }
    }

    private func accessibilityStatus(_ status: InstallStatus) -> String {
        statusLabel(status)
    }

    private func copyInstallLog() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(installManager.logOutput, forType: .string)
        logCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            logCopied = false
        }
    }
}

#Preview {
    InstallationProgressView(style: .sheet)
        .environment(AppViewModel())
        .frame(width: 720, height: 560)
}

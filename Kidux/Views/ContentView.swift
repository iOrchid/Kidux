import SwiftUI
import AppKit
import TipKit

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings
    @State private var showOnboarding = false

    private var preflightAlertMessage: String {
        guard let report = viewModel.preflightReport else {
            return String(localized: "ui.ContentView.7072736334")
        }
        let titles = report.findings.prefix(4).map(\.title).joined(separator: "；")
        if report.blocksInstall {
            return "\(report.summaryLine)。\(titles.isEmpty ? "请先解决严重问题。" : titles)"
        }
        return "\(report.summaryLine)。\(titles.isEmpty ? "确认后仍可继续安装。" : titles)"
    }

    private var mainInterface: some View {
        Group {
            if viewModel.activeInteractionMode == .classic {
                ClassicShellView()
            } else {
                AIWorkspaceView()
            }
        }
    }

    var body: some View {
        Group {
            if viewModel.settings.hasCompletedOnboarding {
                mainInterface
            } else {
                AppTheme.pageBackground(style: .classic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowChromeFixer(title: BrandInfo.windowTitle))
        .onAppear {
            AppIntentBridge.shared.viewModel = viewModel
            if !viewModel.settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: viewModel.shouldPresentOnboarding) { _, shouldShow in
            if shouldShow {
                showOnboarding = true
                viewModel.shouldPresentOnboarding = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppViewModel.openSettingsNotification)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showMigrationWizard },
            set: { viewModel.showMigrationWizard = $0 }
        )) {
            MigrationWizardView {
                viewModel.showMigrationWizard = false
            }
            .environment(viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showCommandPalette },
            set: { viewModel.showCommandPalette = $0 }
        )) {
            CommandPaletteView()
                .environment(viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showMaintenanceSheet },
            set: { viewModel.showMaintenanceSheet = $0 }
        )) {
            MaintenanceProgressSheet()
                .environment(viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showDryRunSheet },
            set: { viewModel.showDryRunSheet = $0 }
        )) {
            if let plan = viewModel.dryRunPlan {
                InstallDryRunView(plan: plan)
            }
        }
        .alert(
            String(localized: "ui.ContentView.adf758f494"),
            isPresented: Binding(
                get: { viewModel.showPreflightConfirm },
                set: { viewModel.showPreflightConfirm = $0 }
            )
        ) {
            if viewModel.preflightReport?.blocksInstall == true {
                Button(String(localized: "ui.ContentView.0e6ab59258")) {
                    viewModel.cancelInstallAfterPreflight()
                    Task { await viewModel.presentDryRunSheet() }
                }
                Button(String(localized: "ui.ContentView.625fb26b"), role: .cancel) {
                    viewModel.cancelInstallAfterPreflight()
                }
            } else {
                Button(String(localized: "ui.ContentView.708a73e122")) {
                    Task { await viewModel.confirmInstallAfterPreflight() }
                }
                Button(String(localized: "ui.ContentView.5b48dbb8dc")) {
                    viewModel.cancelInstallAfterPreflight()
                    Task { await viewModel.presentDryRunSheet() }
                }
                Button(String(localized: "ui.ContentView.625fb26b"), role: .cancel) {
                    viewModel.cancelInstallAfterPreflight()
                }
            }
        } message: {
            Text(preflightAlertMessage)
        }
        .background {
            Button(String(localized: "ui.ContentView.93e40c8484")) {
                viewModel.openCommandPalette()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .hidden()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                viewModel.settings.completeOnboarding()
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
    }
}

struct WelcomeView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        ClassicPageScaffold(
            title: BrandInfo.displayNameCN,
            subtitle: BrandInfo.tagline
        ) {
            ClassicPageScrollContent(maxContentWidth: 720, verticalPadding: 24) {
                VStack(spacing: 28) {
                    BrandAppIcon(size: 96)

                    HStack(spacing: 20) {
                        StatBadge(value: "\(viewModel.bundleManager.roles.count)", label: String(localized: "ui.ContentView.8402fcdd8d"))
                        StatBadge(value: "\(viewModel.allCatalogTools.count)", label: String(localized: "ui.ContentView.f0dfc65b71"))
                        StatBadge(
                            value: viewModel.outdatedCount > 0 ? "\(viewModel.outdatedCount)" : "—",
                            label: String(localized: "ui.ContentView.b48cca48")
                        )
                    }

                    Group {
                        if viewModel.isCheckingEnvironment {
                            ProgressView(String(localized: "ui.ContentView.7ac8b6e61e"))
                        } else {
                            EnvironmentBadge(status: viewModel.environmentStatus)
                        }
                    }
                    .frame(height: 56)

                    immersiveModeCard

                    // 不用 TipKit TipView：会污染 NavigationSplitView 安全区
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "ui.ContentView.1e7925184e"))
                                .font(.subheadline.weight(.semibold))
                            Text(String(localized: "ui.ContentView.ce74fd3e85"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 16) {
                        Button(String(localized: "ui.ContentView.5b4046ac6a")) {
                            viewModel.openMigrationWizard()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(String(localized: "ui.ContentView.db6b2fe6f0")) {
                            viewModel.selectedTab = .discover
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(String(localized: "ui.ContentView.7af603bb91")) {
                            Task {
                                await viewModel.checkEnvironment()
                                viewModel.currentScreen = .roleSelection
                                viewModel.selectedTab = .roles
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .isolatesScrollSafeAreaFromWindowChrome()
        .task {
            // 首页只做轻量环境探测，不扫 brew list / mas / Applications
            await viewModel.ensureRuntimeSnapshot(includeInstalledScan: false)
        }
    }

    private var immersiveModeCard: some View {
        Button {
            viewModel.toggleInteractionMode(to: .ai)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: AppInteractionMode.ai.enterIcon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "ui.ContentView.7059685e"))
                        .font(.headline)
                    Text(String(localized: "ui.ContentView.dfbb4ac265"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 440)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.cardStroke)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "ui.ContentView.7059685e"))
        .accessibilityHint(String(localized: "ui.ContentView.dcde309d"))
    }
}

struct StatBadge: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 72)
        .padding(.vertical, 12)
        .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

struct EnvironmentBadge: View {
    let status: EnvironmentStatus

    var body: some View {
        HStack(spacing: 12) {
            StatusPill(label: "macOS", ok: status.isMacOSSupported, detail: status.macOSVersion)
            StatusPill(label: "CLT", ok: status.hasCommandLineTools, detail: status.hasCommandLineTools ? String(localized: "ui.ContentView.9d5bf2a10a") : String(localized: "ui.ContentView.f45c4e6567"))
            StatusPill(label: "Homebrew", ok: status.hasHomebrew, detail: status.hasHomebrew ? String(localized: "ui.ContentView.9d5bf2a10a") : String(localized: "ui.ContentView.6285d6cd14"))
            StatusPill(label: String(localized: "ui.ContentView.0eaa6af97d"), ok: true, detail: status.architecture)
            if status.availableDiskGB != nil {
                StatusPill(
                    label: String(localized: "ui.ContentView.4f5537dddf"),
                    ok: status.hasSufficientDiskSpace,
                    detail: status.diskSpaceLabel
                )
            }
        }
    }
}

struct StatusPill: View {
    let label: String
    let ok: Bool
    let detail: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? .green : .orange)
                    .font(.caption)
                Text(detail).font(.caption2).lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.cardStroke))
    }
}

struct PostInstallSetupPanel: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var gitName = ""
    @State private var gitEmail = ""
    @State private var selectedPresets: Set<String> = ["finder_dev"]
    @State private var gitAvailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(String(localized: "ui.ContentView.de2d834d78"), systemImage: "wrench.and.screwdriver")
                .font(.headline)

            if gitAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "ui.ContentView.9944281e73")).font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        TextField("user.name", text: $gitName)
                            .textFieldStyle(.roundedBorder)
                        TextField("user.email", text: $gitEmail)
                            .textFieldStyle(.roundedBorder)
                        Button(String(localized: "ui.ContentView.be5fbbe3")) {
                            Task { await viewModel.saveGitIdentity(name: gitName, email: gitEmail) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "ui.ContentView.3cc936f72b")).font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach(MacOSDefaultsService.developerPresets.prefix(2)) { preset in
                        Toggle(preset.title, isOn: Binding(
                            get: { selectedPresets.contains(preset.id) },
                            set: { on in
                                if on { selectedPresets.insert(preset.id) }
                                else { selectedPresets.remove(preset.id) }
                            }
                        ))
                        .font(.caption)
                    }
                }
                Button(String(localized: "ui.ContentView.f423893a45")) {
                    Task { await viewModel.applyMacOSDefaults(presetIDs: selectedPresets) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedPresets.isEmpty)
            }

            Button(String(localized: "ui.ContentView.158c5e5ba6")) {
                viewModel.copyBundleShareJSONToPasteboard()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.cardStroke))
        .task {
            gitAvailable = await GitSetupService.isGitAvailable()
            if gitAvailable {
                let identity = await GitSetupService.readIdentity()
                gitName = identity.name
                gitEmail = identity.email
            }
        }
    }
}

struct CompletionView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(String(localized: "ui.ContentView.a399814ff2")).font(.largeTitle.bold())

            if let summary = viewModel.installManager.summary {
                HStack(spacing: 24) {
                    SummaryCard(title: String(localized: "ui.ContentView.330363df"), count: summary.succeeded, color: .green)
                    SummaryCard(title: String(localized: "ui.ContentView.92636e8c"), count: summary.skipped, color: .orange)
                    SummaryCard(title: String(localized: "ui.ContentView.acd5cb84"), count: summary.failed, color: .red)
                    SummaryCard(title: String(localized: "ui.ContentView.599b5a32"), count: summary.total, color: .blue)
                }
            }

            if let summary = viewModel.installManager.summary, summary.failed > 0 || viewModel.installManager.canResumeInstallation {
                Text(
                    viewModel.installManager.canResumeInstallation
                        ? String(format: String(localized: "ui.ContentView.fmt.ec8e1b77a9"), locale: .current, "\(viewModel.installManager.resumableTaskCount)")
                        : String(format: String(localized: "ui.ContentView.fmt.51c9b7a414"), locale: .current, "\(summary.failed)")
                )
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if let aiSummary = viewModel.installCompletionSummary {
                VStack(alignment: .leading, spacing: 10) {
                    Label(String(localized: "ui.ContentView.3f4cc7a4f3"), systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    AIFormattedText(text: aiSummary, role: .assistant)
                }
                .padding(18)
                .frame(maxWidth: 560, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.cardStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            }

            PostInstallSetupPanel()
                .frame(maxWidth: 560)

            Spacer()

            HStack(spacing: 16) {
                if viewModel.installManager.canResumeInstallation {
                    Button(String(localized: "ui.ContentView.ec13dfe5ca")) {
                        Task { await viewModel.resumeInstallation() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if (viewModel.installManager.summary?.failed ?? 0) > 0 {
                    Button(String(localized: "ui.ContentView.c475defe3a")) {
                        viewModel.selectedTab = .roles
                        viewModel.currentScreen = .installation
                    }
                    .buttonStyle(.bordered)
                }
                Button(String(localized: "ui.ContentView.52effdd3ca")) { viewModel.selectedTab = .installed }
                    .buttonStyle(.bordered)
                Button(String(localized: "ui.ContentView.91960a38c7")) { viewModel.reset() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SummaryCard: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)").font(.title.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 80)
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
        .frame(width: 1100, height: 750)
}

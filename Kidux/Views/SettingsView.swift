import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TipKit

struct SettingsPageView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var installHistory = InstallHistoryStore.shared
    @State private var showThirdPartyDisclaimer = false
    @State private var bundleShareURL = ""
    @State private var teamCodeInput = ""
    @State private var selectedMacOSPresets: Set<String> = []
    @State private var gitName = ""
    @State private var gitEmail = ""
    @State private var gitAvailable = true

    var body: some View {
        TabView {
            settingsTabScroll {
                appearanceSection
            }
            .tabItem { Label(String(localized: "settings.tab.general"), systemImage: "gearshape") }

            settingsTabScroll {
                aiSection
            }
            .tabItem { Label("AI", systemImage: "sparkles") }

            settingsTabScroll {
                installRow
                installHistorySection
            }
            .tabItem { Label(String(localized: "common.install"), systemImage: "arrow.down.circle") }

            settingsTabScroll {
                environmentSetupSection
                trustPrivacyNoteSection
            }
            .tabItem { Label(String(localized: "tab.environment"), systemImage: "terminal") }

            settingsTabScroll {
                snapshotSection
            }
            .tabItem { Label(String(localized: "settings.tab.team"), systemImage: "person.3") }

            settingsTabScroll {
                footerRow
            }
            .tabItem { Label(String(localized: "settings.tab.advanced"), systemImage: "wrench.and.screwdriver") }
        }
        .frame(minWidth: 640, minHeight: 480)
        // 与发现/首页一致：窗口底色，避免 Tab 内容区额外卡片底
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await viewModel.checkEnvironment()
            gitAvailable = await GitSetupService.isGitAvailable()
            if gitAvailable {
                let identity = await GitSetupService.readIdentity()
                gitName = identity.name
                gitEmail = identity.email
            }
            await viewModel.refreshMackupStatus()
        }
        .alert(String(localized: "settings.alert.community_title"), isPresented: $showThirdPartyDisclaimer) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "settings.alert.community_ack")) {
                viewModel.settings.acceptThirdPartyDisclaimer()
                viewModel.settings.enableThirdPartySources = true
            }
        } message: {
            Text(ExternalResourceHub.legalDisclaimer)
        }
    }

    @ViewBuilder
    private func settingsTabScroll<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ClassicPageScrollContent(maxContentWidth: 880, verticalPadding: 0) {
            LazyVStack(alignment: .leading, spacing: 28) {
                content()
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    private var appearanceSection: some View {
            settingsCard(title: String(localized: "settings.card.appearance"), icon: "rectangle.2.swap") {
                Picker(String(localized: "settings.picker.default_layout"), selection: Bindable(viewModel.settings).interactionMode) {
                    ForEach(AppInteractionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(String(localized: "settings.hint.default_layout"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(String(localized: "settings.button.show_onboarding")) {
                    viewModel.settings.resetOnboarding()
                    viewModel.shouldPresentOnboarding = true
                }
                .buttonStyle(.bordered)
            }
    }

    private var aiSection: some View {
        settingsCard(title: String(localized: "settings.card.ai"), icon: "sparkles") {
            AIConfigurationForm(compact: true)
        }
    }

    private var installRow: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsCardRow {
                settingsCard(title: String(localized: "settings.card.install_source"), icon: "arrow.down.circle") {
                    Picker(String(localized: "settings.picker.brew_mirror"), selection: Bindable(viewModel.settings).brewMirror) {
                        ForEach(BrewMirror.allCases) { mirror in
                            Text(mirror.displayName).tag(mirror)
                        }
                    }
                    Toggle(String(localized: "settings.toggle.enable_mas"), isOn: Bindable(viewModel.settings).enableMAS)
                    Toggle(String(localized: "settings.toggle.community_refs"), isOn: Bindable(viewModel.settings).enableThirdPartySources)
                        .onChange(of: viewModel.settings.enableThirdPartySources) { _, enabled in
                            if enabled, !viewModel.settings.thirdPartyDisclaimerAccepted {
                                viewModel.settings.enableThirdPartySources = false
                                showThirdPartyDisclaimer = true
                            }
                        }
                    Text(String(localized: "settings.hint.community_refs"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingsCard(title: String(localized: "settings.card.install_behavior"), icon: "slider.horizontal.3") {
                    Toggle(String(localized: "settings.toggle.skip_installed"), isOn: Bindable(viewModel.settings).skipInstalled)
                    Toggle(String(localized: "settings.toggle.multi_roles"), isOn: Bindable(viewModel.settings).allowMultipleRoles)
                    Toggle(String(localized: "settings.toggle.menubar_health"), isOn: Bindable(viewModel.settings).showMenuBarHealthIndicator)
                    Toggle(String(localized: "settings.toggle.offline"), isOn: Bindable(viewModel.settings).offlineMode)
                    Toggle(String(localized: "settings.toggle.usage_freq"), isOn: Bindable(viewModel.settings).usageFrequencyTrackingEnabled)
                    Toggle(String(localized: "settings.toggle.spotlight"), isOn: Bindable(viewModel.settings).indexCatalogInSpotlight)
                        .onChange(of: viewModel.settings.indexCatalogInSpotlight) { _, _ in
                            viewModel.reindexSpotlightIfNeeded()
                        }
                    Toggle(String(localized: "settings.toggle.scheduled_update"), isOn: Binding(
                        get: { viewModel.settings.scheduledBrewUpdateEnabled },
                        set: { viewModel.applyScheduledBrewUpdatePreference(enabled: $0) }
                    ))
                    Toggle(String(localized: "settings.toggle.weekly_health"), isOn: Binding(
                        get: { viewModel.settings.weeklyHealthDigestEnabled },
                        set: { viewModel.applyWeeklyHealthDigestPreference(enabled: $0) }
                    ))
                    Text(String(localized: "settings.hint.offline"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "settings.hint.scheduled"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "settings.hint.multi_roles"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            extendedCatalogSection
        }
    }

    private var installHistorySection: some View {
        settingsCard(title: String(localized: "settings.card.install_history"), icon: "clock.arrow.circlepath") {
            Text(String(localized: "settings.hint.install_history"))
                .font(.caption)
                .foregroundStyle(.secondary)

            let stats = installHistory.stats
            if !stats.isEmpty {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(stats.sessionCount)").font(.title2.bold())
                        Text(String(localized: "settings.stat.install_count")).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(stats.totalTools)").font(.title2.bold())
                        Text(String(localized: "settings.stat.total_tools")).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stats.estimatedTimeLabel).font(.title2.bold())
                        Text(String(localized: "settings.stat.time_saved")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(String(localized: "settings.hint.time_saved"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if installHistory.entries.isEmpty {
                Text(String(localized: "settings.empty.history"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(installHistory.entries.prefix(15)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.formattedDate)
                                    .font(.subheadline.weight(.medium))
                                Spacer(minLength: 8)
                                Text(entry.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(entry.roleLabel) · \(entry.toolCount) " + String(localized: "settings.unit.tools_suffix"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if entry.id != installHistory.entries.prefix(15).last?.id {
                            Divider()
                        }
                    }
                }

                Button(String(localized: "settings.button.clear_history"), role: .destructive) {
                    installHistory.clearAll()
                }
                .buttonStyle(.bordered)
            }

            if let batch = viewModel.lastRollbackBatch {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "settings.card.rollback"))
                        .font(.subheadline.bold())
                    Text(batch.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "settings.button.rollback_brew")) {
                        Task { await viewModel.rollbackLastInstallBatch() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var extendedCatalogSection: some View {
        settingsCard(title: String(localized: "settings.card.extended_catalog"), icon: "doc.badge.plus") {
            Text(String(localized: "settings.hint.extended_catalog"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                LabeledContent(String(localized: "settings.label.imported")) {
                    Text("\(ExtendedCatalogStore.importedCount)" + String(localized: "settings.unit.count_suffix"))
                }
                Spacer()
                Button(String(localized: "settings.button.choose_json")) { importExtendedCatalog() }
                    .buttonStyle(.bordered)
                if ExtendedCatalogStore.importedCount > 0 {
                    Button(String(localized: "common.clear")) {
                        Task { await viewModel.clearExtendedCatalog() }
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button(String(localized: "settings.button.clear_icon_cache")) {
                Task { await viewModel.clearIconDiskCache() }
            }
            .buttonStyle(.borderless)
            .font(.caption)

            if let msg = viewModel.extendedCatalogStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func importExtendedCatalog() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "settings.panel.import_catalog")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.importExtendedCatalog(from: url) }
    }

    private var footerRow: some View {
        settingsCardRow {
            settingsCard(title: String(localized: "settings.card.system_env"), icon: "desktopcomputer") {
                LabeledContent("Homebrew") {
                    Text(viewModel.environmentStatus.hasHomebrew ? String(localized: "common.installed") : String(localized: "common.not_installed"))
                        .foregroundStyle(viewModel.environmentStatus.hasHomebrew ? .green : .orange)
                }
                if let path = viewModel.environmentStatus.homebrewPath {
                    LabeledContent(String(localized: "common.path"), value: path)
                }
                LabeledContent(String(localized: "settings.label.arch"), value: viewModel.environmentStatus.architecture)
                LabeledContent(String(localized: "settings.label.system"), value: viewModel.environmentStatus.macOSVersion)
                Button(String(localized: "settings.button.recheck")) {
                    Task { await viewModel.checkEnvironment(force: true) }
                }
                .buttonStyle(.bordered)
            }

            settingsCard(title: String(localized: "settings.section.about"), icon: "info.circle") {
                LabeledContent(String(localized: "settings.label.product"), value: BrandInfo.fullTitle)
                LabeledContent(String(localized: "settings.label.version"), value: "\(AppInfo.marketingVersion) (\(AppInfo.buildNumber))")
                LabeledContent(String(localized: "settings.label.roles"), value: "\(viewModel.bundleManager.roles.count)")
                LabeledContent(String(localized: "settings.label.catalog"), value: "\(viewModel.allCatalogTools.count)" + String(localized: "settings.unit.count_suffix"))
                LabeledContent("Swift", value: "6.3")
                LabeledContent(String(localized: "settings.label.min_os"), value: "macOS 15.0")

                HStack {
                    Button {
                        viewModel.checkKiduxAppUpdateWithSparkleUI()
                    } label: {
                        Text(String(localized: "settings.button.check_update"))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!SparkleUpdateController.shared.canCheckForUpdates)

                    Button {
                        Task { await viewModel.checkKiduxAppUpdate(sparkleBackground: true) }
                    } label: {
                        if viewModel.isCheckingAppUpdate {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(String(localized: "settings.button.fallback_check"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isCheckingAppUpdate)

                    if viewModel.appUpdateInfo != nil {
                        Button(String(localized: "settings.button.download_update")) {
                            viewModel.openKiduxDownloadPage()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text(String(localized: "settings.hint.updates"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let msg = viewModel.appUpdateStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "settings.card.diagnostics"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "settings.hint.diagnostics"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "settings.button.export_diagnostics")) {
                        viewModel.exportDiagnosticsPackage()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(String(localized: "settings.a11y.export_diagnostics"))
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "settings.card.audit"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "settings.hint.audit"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let audit = EnterpriseAuditStore.shared.recent
                    if audit.isEmpty {
                        Text(String(localized: "settings.empty.audit"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(audit.prefix(5)) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(event.action)
                                    .font(.caption.monospaced())
                                Text(event.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(event.action)，\(event.detail)")
                        }
                    }
                    HStack(spacing: 12) {
                        Button(String(localized: "settings.button.export_csv")) {
                            viewModel.exportEnterpriseAuditCSV()
                        }
                        .buttonStyle(.bordered)
                        Button(String(localized: "settings.button.clear_audit")) {
                            EnterpriseAuditStore.shared.clearAll()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "settings.card.automation"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "settings.hint.automation"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "settings.button.copy_applescript")) {
                        let sample = """
                        tell application "启椟"
                          dry run role "frontend"
                        end tell
                        """
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sample, forType: .string)
                        viewModel.extendedCatalogStatusMessage = String(localized: "settings.status.applescript_copied")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var trustPrivacyNoteSection: some View {
        settingsCard(title: String(localized: "settings.section.privacy"), icon: "hand.raised") {
            Text(String(localized: "settings.trust_note"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var environmentSetupSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsCard(title: String(localized: "settings.card.macos_defaults"), icon: "macwindow.on.rectangle") {
                Text(String(localized: "settings.hint.macos_defaults"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(MacOSDefaultsService.developerPresets) { preset in
                    Toggle(isOn: Binding(
                        get: { selectedMacOSPresets.contains(preset.id) },
                        set: { on in
                            if on { selectedMacOSPresets.insert(preset.id) }
                            else { selectedMacOSPresets.remove(preset.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title).font(.subheadline)
                            Text(preset.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Button(String(localized: "settings.button.apply_presets")) {
                    Task { await viewModel.applyMacOSDefaults(presetIDs: selectedMacOSPresets) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedMacOSPresets.isEmpty)
            }

            settingsCard(title: String(localized: "settings.card.shell"), icon: "terminal") {
                Text(String(localized: "settings.hint.shell"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    String(localized: "settings.picker.shell"),
                    selection: Binding(
                        get: { viewModel.settings.preferredShell },
                        set: { viewModel.setPreferredShell($0) }
                    )
                ) {
                    ForEach(PreferredShell.allCases) { shell in
                        Text(shell.displayName).tag(shell)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(viewModel.settings.preferredShell.summary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if ShellPreferenceService.effectiveShell(from: viewModel.settings.preferredShell) == .fish {
                    Text(String(localized: "settings.hint.shell_fish"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            settingsCardRow {
                settingsCard(title: String(localized: "settings.card.git"), icon: "chevron.left.forwardslash.chevron.right") {
                    Text(String(localized: "settings.hint.git"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if gitAvailable {
                        TextField("user.name", text: $gitName)
                            .textFieldStyle(.roundedBorder)
                        TextField("user.email", text: $gitEmail)
                            .textFieldStyle(.roundedBorder)
                        Button(String(localized: "settings.button.save_git")) {
                            Task { await viewModel.saveGitIdentity(name: gitName, email: gitEmail) }
                        }
                        .buttonStyle(.bordered)
                        Text(GitSetupService.dotfilesGuide)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "settings.hint.git_missing"))
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard(title: String(localized: "settings.card.brewfile"), icon: "doc.text") {
                    Text(String(localized: "settings.hint.brewfile"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(String(localized: "settings.field.brewfile_path"), text: Bindable(viewModel.settings).brewfileWatchPath)
                        .textFieldStyle(.roundedBorder)

                    Toggle(
                        String(localized: "settings.toggle.brewfile_auto"),
                        isOn: Binding(
                            get: { viewModel.settings.brewfileAutoSyncCheckEnabled },
                            set: { viewModel.setBrewfileAutoSyncCheckEnabled($0) }
                        )
                    )

                    HStack(spacing: 8) {
                        Button(String(localized: "settings.button.choose_path")) {
                            viewModel.chooseBrewfileWatchPathPanel()
                        }
                        .buttonStyle(.bordered)
                        Button(String(localized: "settings.button.compare_now")) {
                            Task { await viewModel.checkBrewfileSync(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button(String(localized: "settings.button.sync_to_kidux")) {
                            viewModel.applyBrewfileOnlyItemsToDiscover()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.brewfileSyncDiff?.onlyInBrewfile.isEmpty != false)
                        Button(String(localized: "settings.button.export_brewfile")) {
                            viewModel.exportBrewfilePanel()
                        }
                        .buttonStyle(.bordered)
                        Button(String(localized: "settings.button.import_brewfile")) {
                            viewModel.importBrewfilePanel()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let msg = viewModel.brewfileSyncStatusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let diff = viewModel.brewfileSyncDiff, diff.hasDifferences {
                        if !diff.onlyInBrewfile.isEmpty {
                            let names = diff.onlyInBrewfile.prefix(6).map(\.name).joined(separator: ", ")
                            let more = diff.onlyInBrewfile.count > 6 ? "…" : ""
                            Text(String(localized: "settings.diff.only_brewfile") + " " + names + more)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !diff.onlyInKidux.isEmpty {
                            let names = diff.onlyInKidux.prefix(6).map(\.name).joined(separator: ", ")
                            let more = diff.onlyInKidux.count > 6 ? "…" : ""
                            Text(String(localized: "settings.diff.only_kidux") + " " + names + more)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            settingsCard(title: String(localized: "settings.card.mackup"), icon: "externaldrive.badge.icloud") {
                Text(MackupGuideService.guideText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    if viewModel.mackupInstalled {
                        Label(String(localized: "settings.status.mackup_installed"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        Button(String(localized: "settings.button.install_mackup")) {
                            Task { await viewModel.installMackup() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.maintenanceManager.isRunning)
                    }

                    Button(String(localized: "settings.button.open_docs")) {
                        NSWorkspace.shared.open(MackupGuideService.homepage)
                    }
                    .buttonStyle(.bordered)

                    Button(String(localized: "settings.button.refresh_status")) {
                        Task { await viewModel.refreshMackupStatus() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var snapshotSection: some View {
        settingsCard(title: String(localized: "settings.card.team_bundle"), icon: "person.3") {
            Text(String(localized: "settings.hint.team_bundle"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if #available(macOS 14.0, *) {
                TipView(MigrationWizardTip(), arrowEdge: .bottom)
                    .tipBackground(Color(nsColor: .controlBackgroundColor))
            }

            TextField(String(localized: "settings.field.team_name"), text: Bindable(viewModel.settings).teamBundleName)
                .textFieldStyle(.roundedBorder)
            TextField(String(localized: "settings.field.team_author"), text: Bindable(viewModel.settings).teamBundleAuthor)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button(String(localized: "settings.button.migration_wizard")) {
                    viewModel.openMigrationWizard()
                }
                .buttonStyle(.bordered)
                Button(String(localized: "settings.button.export_bundle")) {
                    viewModel.exportEnvironmentSnapshot()
                }
                .buttonStyle(.borderedProminent)
                Button(String(localized: "settings.button.import_bundle")) {
                    viewModel.importEnvironmentSnapshotPanel()
                }
                .buttonStyle(.bordered)
                Button(String(localized: "settings.button.copy_share_json")) {
                    viewModel.copyBundleShareJSONToPasteboard()
                }
                .buttonStyle(.bordered)
                Button(String(localized: "settings.button.copy_kidux_link")) {
                    Task { await viewModel.copyLocalSnapshotShareLink() }
                }
                .buttonStyle(.bordered)
                Button(String(localized: "settings.button.export_mdm")) {
                    viewModel.exportMDMProfile()
                }
                .buttonStyle(.bordered)
                .help(String(localized: "settings.help.export_mdm"))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.team_code_heading") + "\(TeamBundlePayload.currentVersion)")
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "settings.team_code_body_prefix") + "\(TeamBundlePayload.currentVersion)" + String(localized: "settings.team_code_body_suffix"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(String(localized: "settings.button.gen_team_code")) {
                        viewModel.createAndCopyTeamBundleCode()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(String(localized: "settings.button.export_team_json")) {
                        viewModel.exportTeamBundlePanel()
                    }
                    .buttonStyle(.bordered)
                    Button(String(localized: "settings.button.import_from_file")) {
                        viewModel.importTeamBundlePanel()
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 8) {
                    TextField(String(localized: "settings.field.team_code"), text: $teamCodeInput)
                        .textFieldStyle(.roundedBorder)
                    Button(String(localized: "common.import")) {
                        Task { await viewModel.importTeamBundleFromPasteboardOrText(teamCodeInput) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(teamCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.hint.share_import"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField(String(localized: "settings.field.share_url"), text: $bundleShareURL)
                        .textFieldStyle(.roundedBorder)
                    Button(String(localized: "common.import")) {
                        Task { await importShareLink(bundleShareURL) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(bundleShareURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(String(localized: "settings.button.wrap_link")) {
                        viewModel.copyWrappedSnapshotImportLink(from: bundleShareURL)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!bundleShareURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http"))
                }
                Text(String(localized: "settings.hint.wrap_link"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let msg = viewModel.extendedCatalogStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func importShareLink(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            viewModel.extendedCatalogStatusMessage = String(localized: "settings.status.invalid_link")
            return
        }
        if url.scheme?.lowercased() == SnapshotShareService.scheme {
            await viewModel.handleIncomingKiduxURL(url)
        } else {
            await viewModel.importBundleFromShareURL(trimmed)
        }
    }

    /// 宽屏并排、窄屏自动纵向堆叠，避免双卡被压扁错位。
    @ViewBuilder
    private func settingsCardRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                content()
            }
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
                .labelStyle(.titleAndIcon)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(20)
        .background(
            Color.clear,
            in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct SettingsView: View {
    var body: some View {
        SettingsPageView()
            .frame(minWidth: 720, minHeight: 520)
    }
}

#Preview {
    SettingsPageView()
        .environment(AppViewModel())
        .frame(width: 900, height: 700)
}

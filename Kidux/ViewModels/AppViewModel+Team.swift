import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

extension AppViewModel {
    func exportEnvironmentSnapshot() {
        Task {
            let snapshot = await EnvironmentSnapshotService.makeFullSnapshot(from: self)
            if let machine = snapshot.machineState {
                let label = snapshot.teamName?.isEmpty == false
                    ? "Bundle · \(snapshot.teamName!)"
                    : "导出 \(AppInfo.displayVersion)"
                settings.saveDriftBaseline(machine, label: label)
            }
            let panel = NSSavePanel()
            panel.title = "导出团队 Bundle / 环境快照"
            let teamSuffix = settings.teamBundleName.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = teamSuffix.isEmpty ? "kidux-snapshot" : "kidux-team-\(teamSuffix)"
            panel.nameFieldStringValue = "\(baseName)-\(AppInfo.marketingVersion).json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let data = try EnvironmentSnapshotService.encode(snapshot)
                try data.write(to: url)
                extendedCatalogStatusMessage = "团队 Bundle 已导出（v4 含 brew/git/运行时/MAS/defaults/shell）"
                await compareEnvironmentDriftIfBaselineExists()
            } catch {
                extendedCatalogStatusMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    /// S18-03 — Shortcuts 导出快照到 ~/Documents/Kidux/snapshots/
    @discardableResult
    func exportEnvironmentSnapshotToDocuments() async -> String? {
        let snapshot = await EnvironmentSnapshotService.makeFullSnapshot(from: self)
        if let machine = snapshot.machineState {
            let label = snapshot.teamName?.isEmpty == false
                ? "Shortcut · \(snapshot.teamName!)"
                : "Shortcut \(AppInfo.displayVersion)"
            settings.saveDriftBaseline(machine, label: label)
        }

        do {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let directory = documents.appendingPathComponent("Kidux/snapshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            let fileName = "kidux-snapshot-\(formatter.string(from: Date())).json"
            let url = directory.appendingPathComponent(fileName)

            let data = try EnvironmentSnapshotService.encode(snapshot)
            try data.write(to: url)
            extendedCatalogStatusMessage = "快照已导出到文稿/Kidux/snapshots（v4）"
            await compareEnvironmentDriftIfBaselineExists()
            return url.path
        } catch {
            extendedCatalogStatusMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    func importEnvironmentSnapshot(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try EnvironmentSnapshotService.decode(from: data)
            guard confirmStaleSnapshotImport(snapshot) else {
                extendedCatalogStatusMessage = "已取消导入"
                return
            }
            await applyImportedEnvironmentSnapshot(snapshot)
            EnterpriseAuditStore.shared.record(
                action: "snapshot.import",
                detail: url.lastPathComponent,
                toolCount: snapshot.selectedToolIDs.count,
                source: "snapshot"
            )
            extendedCatalogStatusMessage = "已导入 Bundle（\(snapshot.selectedRoleIDs.count) 岗位 · \(snapshot.selectedToolIDs.count) 工具）"
        } catch {
            extendedCatalogStatusMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func importEnvironmentSnapshotPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入环境快照"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importEnvironmentSnapshot(from: url) }
    }

    func applyImportedEnvironmentSnapshot(_ snapshot: EnvironmentSnapshot) async {
        lastImportedEnvironmentSnapshot = snapshot
        EnvironmentSnapshotService.apply(snapshot, to: self)
        if let machine = snapshot.machineState {
            settings.saveDriftBaseline(
                machine,
                label: snapshot.teamName?.isEmpty == false ? "导入 · \(snapshot.teamName!)" : "导入快照"
            )
            await compareEnvironmentDrift(force: true)
        }
        await refreshMigrationRecommendations()
    }

    /// S18-19 — 根据导入快照 + 漂移报告生成缺失推荐
    func refreshMigrationRecommendations() async {
        isRefreshingMigrationRecommendations = true
        defer { isRefreshingMigrationRecommendations = false }

        if installedSnapshot == nil {
            await scanInstalledStatus(force: true)
        }

        let items = MigrationRecommendationService.recommend(
            snapshot: lastImportedEnvironmentSnapshot,
            driftReport: environmentDriftReport,
            catalog: allCatalogTools,
            installed: installedSnapshot
        )
        migrationRecommendations = items
        selectedMigrationRecommendationIDs = Set(items.map(\.id))
        if !items.isEmpty {
            extendedCatalogStatusMessage = "智能换机推荐 \(items.count) 款可补齐软件"
        }
    }

    func toggleMigrationRecommendation(_ id: String) {
        if selectedMigrationRecommendationIDs.contains(id) {
            selectedMigrationRecommendationIDs.remove(id)
        } else {
            selectedMigrationRecommendationIDs.insert(id)
        }
    }

    func selectAllMigrationRecommendations(_ select: Bool) {
        if select {
            selectedMigrationRecommendationIDs = Set(migrationRecommendations.map(\.id))
        } else {
            selectedMigrationRecommendationIDs.removeAll()
        }
    }

    /// 将选中的推荐加入岗位清单 / 发现页勾选
    func applySelectedMigrationRecommendations() {
        let want = selectedMigrationRecommendationIDs
        guard !want.isEmpty else {
            extendedCatalogStatusMessage = "请先勾选要补齐的推荐软件"
            return
        }

        var applied = 0
        for index in resolvedTools.indices {
            let id = resolvedTools[index].id
            if want.contains(id) {
                resolvedTools[index].isSelected = true
                applied += 1
            }
        }
        for id in want {
            if resolvedTools.contains(where: { $0.id == id }) { continue }
            discoverSelectedTools.insert(id)
            applied += 1
        }

        extendedCatalogStatusMessage = "已将 \(applied) 款推荐软件加入清单"
        navigateTo(.roles)
        currentScreen = .bundleDetail
    }

    @discardableResult
    func confirmStaleSnapshotImport(_ snapshot: EnvironmentSnapshot) -> Bool {
        guard SnapshotFreshness.isStale(exportedAt: snapshot.exportedAt) else { return true }

        let alert = NSAlert()
        alert.messageText = "快照可能已过时"
        alert.informativeText = SnapshotFreshness.staleImportAlertMessage(exportedAt: snapshot.exportedAt)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "仍要导入")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func copyBundleShareJSONToPasteboard() {
        do {
            let json = try BundleShareService.makeShareJSON(from: self)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
            extendedCatalogStatusMessage = "Bundle JSON 已复制到剪贴板，可发给同事或粘贴到共享文件"
        } catch {
            extendedCatalogStatusMessage = "复制失败：\(error.localizedDescription)"
        }
    }

    // MARK: - S18-10 团队配置码

    func createAndCopyTeamBundleCode() {
        do {
            let share = try TeamBundleSyncService.createShare(from: self)
            let json = try TeamBundleSyncService.jsonString(share.payload)
            let clipboard = """
            \(share.code)
            \(share.link)

            \(json)
            """
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipboard, forType: .string)
            if !settings.teamBundleName.isEmpty {
                // keep name
            }
            extendedCatalogStatusMessage = "已生成 \(share.code) 并复制到剪贴板（含 JSON，可发给同事）"
        } catch {
            extendedCatalogStatusMessage = "生成团队码失败：\(error.localizedDescription)"
        }
    }

    func exportTeamBundlePanel() {
        do {
            let share = try TeamBundleSyncService.createShare(from: self)
            let json = try TeamBundleSyncService.jsonString(share.payload)
            let panel = NSSavePanel()
            panel.title = "导出团队配置"
            panel.nameFieldStringValue = "\(share.code).json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try json.write(to: url, atomically: true, encoding: .utf8)
            extendedCatalogStatusMessage = "已导出 \(share.code) → \(url.lastPathComponent)"
        } catch {
            extendedCatalogStatusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func importTeamBundle(code raw: String) async {
        do {
            let result = try TeamBundleSyncService.load(code: raw)
            applyTeamBundle(result.payload)
            extendedCatalogStatusMessage = "已导入 \(result.payload.teamCode)（\(result.payload.roles.count) 岗位 · \(result.payload.selectedTools.count) 工具 · \(result.statusLine)）"
        } catch {
            extendedCatalogStatusMessage = error.localizedDescription
        }
    }

    func importTeamBundleFromPasteboardOrText(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if TeamBundleSyncService.isValidCode(TeamBundleSyncService.normalizeCode(trimmed)) {
            await importTeamBundle(code: trimmed)
            return
        }
        if let data = trimmed.data(using: .utf8),
           let result = try? TeamBundleSyncService.importResult(from: data)
        {
            applyTeamBundle(result.payload)
            extendedCatalogStatusMessage = "已从 JSON 导入 \(result.payload.teamCode)（\(result.statusLine)）"
            return
        }
        if let jsonStart = trimmed.firstIndex(of: "{"),
           let data = String(trimmed[jsonStart...]).data(using: .utf8),
           let result = try? TeamBundleSyncService.importResult(from: data)
        {
            applyTeamBundle(result.payload)
            extendedCatalogStatusMessage = "已从粘贴内容导入 \(result.payload.teamCode)（\(result.statusLine)）"
            return
        }
        extendedCatalogStatusMessage = "无法识别：请输入 TEAM-XXXXXXXX，或粘贴团队配置 JSON"
    }

    func importTeamBundlePanel() {
        let panel = NSOpenPanel()
        panel.title = "导入团队配置 JSON"
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try Data(contentsOf: url)
                let result = try TeamBundleSyncService.importResult(from: data)
                applyTeamBundle(result.payload)
                extendedCatalogStatusMessage = "已从文件导入 \(result.payload.teamCode)（\(result.statusLine)）"
            } catch {
                extendedCatalogStatusMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    func applyTeamBundle(_ payload: TeamBundlePayload) {
        EnterpriseAuditStore.shared.record(
            action: "bundle.import",
            detail: payload.teamName.isEmpty ? "团队 Bundle" : payload.teamName,
            toolCount: payload.selectedTools.count + payload.discoverToolIDs.count,
            source: "team"
        )
        if !payload.teamName.isEmpty {
            settings.teamBundleName = payload.teamName
        }
        if !payload.author.isEmpty {
            settings.teamBundleAuthor = payload.author
        }
        if let mirrorRaw = payload.preferredBrewMirror,
           let mirror = BrewMirror(rawValue: mirrorRaw)
        {
            settings.brewMirror = mirror
        }
        if let skip = payload.skipInstalled {
            settings.skipInstalled = skip
        }
        if !payload.roles.isEmpty {
            selectedRoles = Set(payload.roles)
            refreshResolvedTools()
            if !payload.selectedTools.isEmpty {
                let want = Set(payload.selectedTools)
                for index in resolvedTools.indices {
                    resolvedTools[index].isSelected = want.contains(resolvedTools[index].id)
                        || resolvedTools[index].isRequired
                }
            }
            navigateTo(.roles)
            currentScreen = .bundleDetail
        }
        if !payload.discoverToolIDs.isEmpty {
            for id in payload.discoverToolIDs {
                discoverSelectedTools.insert(id)
            }
            if payload.roles.isEmpty {
                navigateTo(.discover)
            }
        }
    }

    func exportDiagnosticsPackage() {
        Task { await DiagnosticExportService.exportPanel(from: self) }
    }

    func exportMDMProfile() {
        MDMProfileExporter.exportPanel(from: self)
    }

    func importBundleFromShareURL(_ urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            extendedCatalogStatusMessage = "链接无效，请填写 https:// 开头的 raw JSON 地址"
            return
        }
        await importSnapshotFromRemoteURL(url)
    }

    func copyLocalSnapshotShareLink() async {
        do {
            let link = try await SnapshotShareService.createLocalShareLink(from: self)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
            extendedCatalogStatusMessage = SnapshotShareService.humanReadableHint(for: link)
        } catch {
            extendedCatalogStatusMessage = "生成分享链接失败：\(error.localizedDescription)"
        }
    }

    func copyWrappedSnapshotImportLink(from remoteURLString: String) {
        let trimmed = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let link = SnapshotShareService.makeImportLink(forRemoteURL: url)
        else {
            extendedCatalogStatusMessage = "请先填写有效的 https raw JSON 地址"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        extendedCatalogStatusMessage = SnapshotShareService.humanReadableHint(for: link)
    }

    func handleIncomingKiduxURL(_ url: URL) async {
        // S20-06 — 搜索深链
        if url.scheme?.lowercased() == "kidux",
           url.host?.lowercased() == "search"
        {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "q" || $0.name == "query" })?
                .value
            openDiscoverSearch(query: query ?? "")
            return
        }

        // S18-10 — 团队码
        if let code = TeamBundleSyncService.parseIncomingURL(url) {
            await importTeamBundle(code: code)
            return
        }

        // S18-17 / S19-03 — 定时维护
        if let action = MaintenanceSchedulerService.parseMaintenanceURL(url) {
            switch action {
            case .scheduledUpdate:
                await runScheduledBrewUpdate(force: true)
            case .weeklyDigest:
                await runWeeklyHealthDigest(force: true)
            }
            return
        }

        // S20-05 — Share Extension 收件箱
        if url.scheme?.lowercased() == "kidux",
           url.host?.lowercased() == "share"
        {
            await processShareExtensionInbox()
            return
        }

        guard let incoming = SnapshotShareService.parseIncomingURL(url) else {
            extendedCatalogStatusMessage = "无法识别的 Kidux 链接"
            return
        }

        do {
            let snapshot: EnvironmentSnapshot
            switch incoming {
            case .localToken(let token):
                snapshot = try SnapshotShareService.loadLocalSnapshot(token: token)
            case .remoteImport(let remote):
                snapshot = try await BundleShareService.fetchSnapshot(from: remote)
            }

            guard confirmStaleSnapshotImport(snapshot) else {
                extendedCatalogStatusMessage = "已取消导入"
                return
            }
            await applyImportedEnvironmentSnapshot(snapshot)
            navigateTo(.roles)
            currentScreen = .bundleDetail
            extendedCatalogStatusMessage = "已从 Kidux 分享链接导入 Bundle（\(snapshot.selectedRoleIDs.count) 岗位 · \(snapshot.selectedToolIDs.count) 工具）"
        } catch {
            extendedCatalogStatusMessage = "Kidux 链接导入失败：\(error.localizedDescription)"
        }
    }

    /// S20-05 — 处理系统分享菜单写入的待导入文件
    func processShareExtensionInbox() async {
        guard let pending = ShareImportInbox.consume() else {
            extendedCatalogStatusMessage = "没有待导入的分享内容"
            return
        }

        switch pending.kind {
        case .brewfile:
            let result = BrewfileImporter.importFromFile(content: pending.utf8Text, catalog: allCatalogTools)
            guard !result.matchedTools.isEmpty else {
                extendedCatalogStatusMessage = "分享的 Brewfile 未匹配到 Catalog（\(result.unmatched.count) 行未识别）"
                return
            }
            for tool in result.matchedTools {
                discoverSelectedTools.insert(tool.id)
            }
            navigateTo(.discover)
            var msg = "已从分享导入 Brewfile：\(result.matchedTools.count) 款"
            if !result.unmatched.isEmpty {
                msg += "（\(result.unmatched.count) 行未识别）"
            }
            extendedCatalogStatusMessage = msg

        case .snapshot, .teamBundle:
            do {
                let data = Data(pending.utf8Text.utf8)
                if let snapshot = try? EnvironmentSnapshotService.decode(from: data) {
                    guard confirmStaleSnapshotImport(snapshot) else {
                        extendedCatalogStatusMessage = "已取消导入"
                        return
                    }
                    await applyImportedEnvironmentSnapshot(snapshot)
                    navigateTo(.roles)
                    currentScreen = .bundleDetail
                    extendedCatalogStatusMessage = "已从分享导入快照（\(snapshot.selectedRoleIDs.count) 岗位 · \(snapshot.selectedToolIDs.count) 工具）"
                    return
                }

                if let role = try? JSONDecoder().decode(RoleBundle.self, from: data),
                   bundleManager.roles.contains(where: { $0.id == role.id })
                {
                    selectedRoles = [role.id]
                    refreshResolvedTools()
                    navigateTo(.roles)
                    currentScreen = .bundleDetail
                    extendedCatalogStatusMessage = "已从分享导入岗位「\(role.name)」"
                    return
                }

                extendedCatalogStatusMessage = "无法识别分享的 JSON（\(pending.fileName)）"
            }
        }
    }

    func importSnapshotFromRemoteURL(_ url: URL) async {
        do {
            let snapshot = try await BundleShareService.fetchSnapshot(from: url)
            guard confirmStaleSnapshotImport(snapshot) else {
                extendedCatalogStatusMessage = "已取消导入"
                return
            }
            await applyImportedEnvironmentSnapshot(snapshot)
            extendedCatalogStatusMessage = "已从链接导入 Bundle（\(snapshot.selectedRoleIDs.count) 岗位 · \(snapshot.selectedToolIDs.count) 工具）"
        } catch {
            extendedCatalogStatusMessage = "链接导入失败：\(error.localizedDescription)"
        }
    }

    func toggleDiscoverSpeechInput() {
        if isDiscoverSpeechListening {
            stopDiscoverSpeechInput()
        } else {
            Task { await startDiscoverSpeechInput() }
        }
    }

    func stopDiscoverSpeechInput() {
        DiscoverSpeechInputService.shared.stopListening()
        isDiscoverSpeechListening = false
    }

    func startDiscoverSpeechInput() async {
        guard discoverMode == .builtin else { return }

        guard await DiscoverSpeechInputService.shared.requestAuthorization() else {
            discoverSpeechStatus = "请在系统设置中允许麦克风与语音识别"
            return
        }

        discoverSpeechStatus = nil
        isDiscoverSpeechListening = true

        do {
            try DiscoverSpeechInputService.shared.startListening(
                onPartial: { [weak self] text in
                    Task { @MainActor in
                        self?.updateDiscoverSearch(text)
                    }
                },
                onFinal: { [weak self] text in
                    Task { @MainActor in
                        guard let self else { return }
                        self.updateDiscoverSearch(text)
                        self.stopDiscoverSpeechInput()
                        if CatalogNLFilterService.looksLikeNaturalLanguage(text) {
                            await self.applyDiscoverNaturalLanguageFilter()
                        }
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.discoverSpeechStatus = message
                        self?.stopDiscoverSpeechInput()
                    }
                }
            )
        } catch {
            discoverSpeechStatus = error.localizedDescription
            stopDiscoverSpeechInput()
        }
    }

    func applyMacOSDefaults(presetIDs: Set<String>) async {
        do {
            let message = try await MacOSDefaultsService.apply(presetIDs: presetIDs)
            extendedCatalogStatusMessage = message
        } catch {
            extendedCatalogStatusMessage = error.localizedDescription
        }
    }

    func saveGitIdentity(name: String, email: String) async {
        do {
            try await GitSetupService.applyIdentity(name: name, email: email)
            extendedCatalogStatusMessage = "Git 身份已保存"
        } catch {
            extendedCatalogStatusMessage = error.localizedDescription
        }
    }

    func importBrewfile(from url: URL) async {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let result = BrewfileImporter.importFromFile(content: content, catalog: allCatalogTools)
            guard !result.matchedTools.isEmpty else {
                extendedCatalogStatusMessage = "Brewfile 中未匹配到 Catalog 条目（\(result.unmatched.count) 行未识别）"
                return
            }
            for tool in result.matchedTools {
                discoverSelectedTools.insert(tool.id)
            }
            navigateTo(.discover)
            var msg = "已从 Brewfile 导入 \(result.matchedTools.count) 款到发现页清单"
            if !result.unmatched.isEmpty {
                msg += "（\(result.unmatched.count) 行未在 Catalog 中找到）"
            }
            extendedCatalogStatusMessage = msg
        } catch {
            extendedCatalogStatusMessage = "Brewfile 导入失败：\(error.localizedDescription)"
        }
    }

    func importBrewfilePanel() {
        let panel = NSOpenPanel()
        panel.title = "导入 Brewfile"
        panel.allowedContentTypes = [.plainText, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importBrewfile(from: url) }
    }

    // MARK: - S18-12 Brewfile 自动同步

    var currentBrewfileSyncSelectionIDs: Set<String> {
        var ids = Set(resolvedTools.filter(\.isSelected).map(\.id))
        ids.formUnion(discoverSelectedTools)
        return ids
    }

    func chooseBrewfileWatchPathPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择要监视的 Brewfile"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let expanded = BrewfileSyncService.expandPath(settings.brewfileWatchPath)
        if FileManager.default.fileExists(atPath: expanded) {
            panel.directoryURL = URL(fileURLWithPath: expanded).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.brewfileWatchPath = url.path
        Task { await checkBrewfileSync(force: true) }
    }

    func checkBrewfileSyncIfEnabled() async {
        guard settings.brewfileAutoSyncCheckEnabled else { return }
        await checkBrewfileSync(force: false)
    }

    func checkBrewfileSync(force: Bool) async {
        let path = settings.brewfileWatchPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            if force {
                brewfileSyncStatusMessage = "请先选择 Brewfile 路径"
            }
            return
        }
        do {
            let diff = try BrewfileSyncService.compare(
                brewfilePath: path,
                catalog: allCatalogTools,
                kiduxSelectedIDs: currentBrewfileSyncSelectionIDs
            )
            brewfileSyncDiff = diff
            if diff.hasDifferences {
                brewfileSyncStatusMessage = "检测到差异：\(diff.summaryLine)。可将 Brewfile 多出的项同步到 Kidux。"
            } else {
                brewfileSyncStatusMessage = force ? diff.summaryLine : nil
            }
        } catch {
            brewfileSyncDiff = nil
            if force {
                brewfileSyncStatusMessage = error.localizedDescription
            }
        }
    }

    func applyBrewfileOnlyItemsToDiscover() {
        guard let diff = brewfileSyncDiff, !diff.onlyInBrewfile.isEmpty else {
            brewfileSyncStatusMessage = "没有可从 Brewfile 同步的项"
            return
        }
        for tool in diff.onlyInBrewfile {
            discoverSelectedTools.insert(tool.id)
        }
        navigateTo(.discover)
        brewfileSyncStatusMessage = "已从 Brewfile 同步 \(diff.onlyInBrewfile.count) 款到发现页清单"
        Task { await checkBrewfileSync(force: true) }
    }

    func exportBrewfilePanel() {
        let selected = allCatalogTools.filter { currentBrewfileSyncSelectionIDs.contains($0.id) }
        guard !selected.isEmpty else {
            brewfileSyncStatusMessage = "请先在岗位清单或发现页勾选软件"
            return
        }
        let content = BrewfileSyncService.generateContent(from: selected)
        let panel = NSSavePanel()
        panel.title = "导出 Brewfile"
        panel.nameFieldStringValue = "Brewfile"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            settings.brewfileWatchPath = url.path
            brewfileSyncStatusMessage = "已导出 Brewfile → \(url.lastPathComponent)"
            Task { await checkBrewfileSync(force: true) }
        } catch {
            brewfileSyncStatusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func setBrewfileAutoSyncCheckEnabled(_ enabled: Bool) {
        settings.brewfileAutoSyncCheckEnabled = enabled
        if enabled {
            Task { await checkBrewfileSync(force: true) }
        }
    }

    // MARK: - S18-16 Dry-run · S18-15 Rollback · S20-01 Spotlight · S20-02 Intents

    func reindexSpotlightIfNeeded() {
        guard settings.indexCatalogInSpotlight else {
            CatalogSpotlightIndexer.deleteAllIndexed()
            return
        }
        CatalogSpotlightIndexer.indexCatalog(allCatalogTools)
    }

    func navigateToCatalogTool(id toolID: String) {
        guard catalogTool(id: toolID) != nil else { return }
        navigateTo(.discover)
        discoverSearchText = ""
        discoverCategory = nil
        discoverMode = .builtin
        pendingSpotlightToolID = toolID
    }

    /// S20-06 — 系统服务冷启动待搜索词
    func openDiscoverSearch(query: String) {
        focusMainWindow()
        navigateTo(.discover)
        discoverMode = .builtin
        discoverCategory = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateDiscoverSearch(trimmed)
        extendedCatalogStatusMessage = "已搜索「\(trimmed)」"
    }

    func consumePendingDiscoverSearch() {
        let key = KiduxPendingSearch.defaultsKey
        guard let query = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty
        else { return }
        UserDefaults.standard.removeObject(forKey: key)
        openDiscoverSearch(query: query)
    }

    func consumePendingSpotlightToolID() -> String? {
        defer { pendingSpotlightToolID = nil }
        return pendingSpotlightToolID
    }

    @discardableResult
    func matchRole(query: String) -> RoleBundle? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return bundleManager.roles.first { role in
            role.id.lowercased() == normalized
                || role.name.lowercased() == normalized
                || role.name.lowercased().contains(normalized)
                || role.id.replacingOccurrences(of: "_", with: " ").contains(normalized)
        }
    }

    func selectRole(_ role: RoleBundle) {
        if settings.allowMultipleRoles {
            selectedRoles.insert(role.id)
        } else {
            selectedRoles = [role.id]
        }
        refreshResolvedTools()
    }

    func prepareDryRunPlan() async -> InstallDryRunPlan {
        if installedSnapshot == nil {
            await scanInstalledStatus()
        }
        let preflight = await InstallPreflightService.analyze(
            tools: resolvedTools,
            enableMAS: settings.enableMAS,
            skipInstalled: settings.skipInstalled,
            snapshot: installedSnapshot,
            environment: environmentStatus,
            mirror: settings.brewMirror
        )
        preflightReport = preflight
        var plan = InstallDryRunService.buildPlan(
            tools: resolvedTools,
            postInstallSteps: postInstallSteps,
            enableMAS: settings.enableMAS,
            skipInstalled: settings.skipInstalled,
            snapshot: installedSnapshot
        )
        plan = InstallDryRunPlan(
            items: plan.items,
            postInstallSteps: plan.postInstallSteps,
            skippedCount: plan.skippedCount,
            manualCount: plan.manualCount,
            executableCount: plan.executableCount,
            preflight: preflight
        )
        return plan
    }

    func presentDryRunSheet() async {
        isAnalyzingPreflight = true
        defer { isAnalyzingPreflight = false }
        dryRunPlan = await prepareDryRunPlan()
        showDryRunSheet = true
    }

    /// 开始安装前跑依赖分析；有严重问题时弹确认。
    func startInstallationWithPreflight() async {
        isAnalyzingPreflight = true
        let report = await InstallPreflightService.analyze(
            tools: resolvedTools,
            enableMAS: settings.enableMAS,
            skipInstalled: settings.skipInstalled,
            snapshot: installedSnapshot,
            environment: environmentStatus,
            mirror: settings.brewMirror
        )
        isAnalyzingPreflight = false
        preflightReport = report

        if report.blocksInstall || report.warningCount > 0 {
            pendingInstallAfterPreflight = true
            showPreflightConfirm = true
            return
        }
        await startInstallation()
    }

    func confirmInstallAfterPreflight() async {
        showPreflightConfirm = false
        pendingInstallAfterPreflight = false
        await startInstallation()
    }

    func cancelInstallAfterPreflight() {
        showPreflightConfirm = false
        pendingInstallAfterPreflight = false
    }

    func performRoleInstallIntent(query: String, previewOnly: Bool) async -> String {
        guard let role = matchRole(query: query) else {
            return "未找到岗位「\(query)」。请在 Kidux 岗位页查看完整列表。"
        }

        selectRole(role)
        navigateTo(.roles)
        currentScreen = .bundleDetail

        if previewOnly {
            dryRunPlan = await prepareDryRunPlan()
            showDryRunSheet = true
            return "已选择「\(role.name)」，模拟安装预览已打开。"
        }

        guard selectedToolCount > 0 else {
            return "岗位「\(role.name)」没有可安装的工具。"
        }

        await startInstallation()
        let failed = installManager.summary?.failed ?? 0
        if failed > 0 {
            return "岗位「\(role.name)」安装完成，但有 \(failed) 项失败。请在安装页查看日志。"
        }
        return "已开始安装岗位「\(role.name)」的工具清单。"
    }

    func performUpgradeOutdatedIntent() async -> String {
        await scanInstalledStatus(force: true)
        await checkForUpdates(force: true)
        guard let result = outdatedResult, !result.allEntries.isEmpty else {
            navigateTo(.installed)
            return "太棒了！当前没有可更新的 brew / App Store 软件。"
        }
        let count = result.allEntries.count
        await upgradeAllOutdated()
        navigateTo(.installed)
        return "已启动 \(count) 项软件更新，请在维护进度中查看。"
    }

    func performEnvironmentDriftCheckIntent() async -> String {
        navigateTo(.environment)
        if !hasEnvironmentDriftBaseline {
            return "尚未设置环境基准。请在环境页导出快照或设基准后再检查漂移。"
        }
        await compareEnvironmentDrift(force: true)
        guard let report = environmentDriftReport else {
            return "环境对比失败，请稍后重试。"
        }
        if !report.hasDrift {
            return "环境与基准一致，未检测到漂移。"
        }
        return "环境漂移：\(report.summaryLine)。详情已打开环境页。"
    }

    func rollbackLastInstallBatch() async {
        guard let batch = lastRollbackBatch else {
            extendedCatalogStatusMessage = "没有可回滚的安装批次"
            return
        }

        let tools = batch.toolIDs.compactMap { catalogTool(id: $0) }
            .filter { tool in
                switch tool.source.type {
                case .formula, .cask: return true
                case .mas, .script, .link: return false
                }
            }

        guard !tools.isEmpty else {
            extendedCatalogStatusMessage = "上一批次没有可自动卸载的 brew 项"
            InstallRollbackStore.clear()
            lastRollbackBatch = nil
            return
        }

        maintenanceManager.beginUninstallSession(tools: tools)
        showMaintenanceSheet = true
        await maintenanceManager.runUninstalls(tools: tools, mirror: settings.brewMirror)
        InstallRollbackStore.clear()
        lastRollbackBatch = nil
        await scanInstalledStatus(force: true)
        extendedCatalogStatusMessage = "已回滚卸载 \(tools.count) 款软件"
    }

    func toggleAISpeechInput() {
        if isAISpeechListening {
            stopAISpeechInput()
        } else {
            Task { await startAISpeechInput() }
        }
    }

    func stopAISpeechInput() {
        DiscoverSpeechInputService.shared.stopListening()
        isAISpeechListening = false
    }

    func startAISpeechInput() async {
        stopDiscoverSpeechInput()

        guard await DiscoverSpeechInputService.shared.requestAuthorization() else {
            aiSpeechStatus = "请在系统设置中允许麦克风与语音识别"
            return
        }

        aiSpeechStatus = nil
        isAISpeechListening = true

        do {
            try DiscoverSpeechInputService.shared.startListening(
                onPartial: { [weak self] text in
                    Task { @MainActor in
                        self?.aiSpeechStatus = text
                    }
                },
                onFinal: { [weak self] text in
                    Task { @MainActor in
                        guard let self else { return }
                        self.stopAISpeechInput()
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        self.sendAIMessage(trimmed)
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.aiSpeechStatus = message
                        self?.stopAISpeechInput()
                    }
                }
            )
        } catch {
            aiSpeechStatus = error.localizedDescription
            stopAISpeechInput()
        }
    }

    func recordRollbackCandidates(source: InstallHistorySource) {
        let succeededIDs = installManager.tasks.compactMap { task -> String? in
            guard task.status == .success else { return nil }
            guard case .tool(let resolved) = task.kind else { return nil }
            switch resolved.tool.source.type {
            case .formula, .cask:
                return resolved.tool.id
            case .mas, .script, .link:
                return nil
            }
        }

        guard !succeededIDs.isEmpty else { return }

        let roleNames: [String]
        if source == .discover {
            roleNames = ["发现页"]
        } else {
            roleNames = bundleManager.roles
                .filter { selectedRoles.contains($0.id) }
                .map(\.name)
        }

        InstallRollbackStore.record(
            toolIDs: succeededIDs,
            source: source,
            roleNames: roleNames
        )
        lastRollbackBatch = InstallRollbackStore.load()
    }

    func recordInstallCompletionSummary(source: InstallHistorySource = .bundle) {
        guard let summary = installManager.summary else { return }
        installCompletionSummary = AIAssistantService.installCompletionSummary(
            summary: summary,
            roleName: selectedRoleName
        )

        let roleNames: [String]
        if source == .discover {
            roleNames = ["发现页"]
        } else {
            roleNames = bundleManager.roles
                .filter { selectedRoles.contains($0.id) }
                .map(\.name)
        }
        InstallHistoryStore.shared.record(
            roleNames: roleNames,
            summary: summary,
            cancelled: installManager.isCancelled,
            source: source
        )
        EnterpriseAuditStore.shared.record(
            action: installManager.isCancelled ? "install.cancelled" : "install.complete",
            detail: "\(summary.succeeded) 成功 · \(summary.failed) 失败 · 来源 \(source == .discover ? "发现页" : roleNames.joined(separator: "/"))",
            toolCount: summary.succeeded + summary.failed,
            source: source == .discover ? "discover" : "bundle"
        )
        recordCatalogQualityFromInstallTasks()
        if summary.succeeded > 0 {
            recordRollbackCandidates(source: source)
        }
    }

    func recordCatalogQualityFromInstallTasks() {
        let outcomes: [(toolID: String, success: Bool)] = installManager.tasks.compactMap { task in
            guard case .tool(let resolved) = task.kind else { return nil }
            switch task.status {
            case .success:
                return (resolved.tool.id, true)
            case .failed:
                return (resolved.tool.id, false)
            case .pending, .running, .skipped, .cancelled:
                return nil
            }
        }
        CatalogQualityStore.shared.record(outcomes: outcomes)
        let successIDs = outcomes.filter(\.success).map(\.toolID)
        UsageFrequencyStore.shared.recordInstalls(toolIDs: successIDs)
    }

}

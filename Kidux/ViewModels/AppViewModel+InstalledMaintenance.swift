import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

extension AppViewModel {
    func upgradeOutdatedItem(_ item: OutdatedBrewItem) async {
        await upgradeOutdatedEntry(.brew(item))
    }

    func upgradeOutdatedEntry(_ entry: OutdatedEntry) async {
        isUpgradingItem = entry.id
        defer { isUpgradingItem = nil }
        maintenanceManager.beginUpgradeSession(entries: [entry])
        showMaintenanceSheet = true
        await maintenanceManager.runUpgrades(entries: [entry], mirror: settings.brewMirror)
        await scanInstalledStatus(force: true)
        await checkForUpdates()
    }

    func upgradeAllOutdated() async {
        guard let result = outdatedResult, !result.allEntries.isEmpty else { return }
        let entries = result.allEntries
        maintenanceManager.beginUpgradeSession(entries: entries)
        showMaintenanceSheet = true
        await maintenanceManager.runUpgrades(entries: entries, mirror: settings.brewMirror)
        await scanInstalledStatus(force: true)
        await checkForUpdates(force: true)
    }

    var uninstallableCatalogTools: [DevTool] {
        guard let snapshot = installedSnapshot else { return [] }
        return allCatalogTools.filter { tool in
            guard snapshot.state(for: tool) == .installed else { return false }
            switch tool.source.type {
            case .formula, .cask:
                return true
            case .mas, .script, .link:
                return false
            }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func toggleUninstallSelection(_ toolID: String) {
        if uninstallSelection.contains(toolID) {
            uninstallSelection.remove(toolID)
        } else {
            uninstallSelection.insert(toolID)
        }
    }

    func uninstallSelectedTools() async {
        let tools = uninstallableCatalogTools.filter { uninstallSelection.contains($0.id) }
        guard !tools.isEmpty else { return }
        maintenanceManager.beginUninstallSession(tools: tools)
        showMaintenanceSheet = true
        await maintenanceManager.runUninstalls(tools: tools, mirror: settings.brewMirror)
        EnterpriseAuditStore.shared.record(
            action: "uninstall.complete",
            detail: tools.map(\.name).joined(separator: ", "),
            toolCount: tools.count,
            source: "maintenance"
        )
        uninstallSelection.removeAll()
        await scanInstalledStatus(force: true)
    }

    func exportEnterpriseAuditCSV() {
        EnterpriseAuditStore.shared.exportCSVPanel()
        extendedCatalogStatusMessage = "已导出企业审计 CSV"
    }

    func buildUninstallConfirmationMessage() async -> String {
        let tools = uninstallableCatalogTools.filter { uninstallSelection.contains($0.id) }
        guard !tools.isEmpty else {
            return "将卸载所选软件。"
        }

        var parts = ["将卸载 \(tools.count) 款 brew 软件，此操作不可撤销。"]
        for tool in tools where tool.source.type == .formula {
            let dependents = await BrewDependencyService.fetchDependents(
                formula: tool.source.identifier,
                mirror: settings.brewMirror
            )
            guard !dependents.isEmpty else { continue }
            let preview = dependents.prefix(5).joined(separator: ", ")
            let suffix = dependents.count > 5 ? " 等 \(dependents.count) 项" : ""
            parts.append("⚠️ \(tool.name) 仍被其他 formula 依赖：\(preview)\(suffix)")
        }
        return parts.joined(separator: "\n\n")
    }

    func loadBrewServices(force: Bool = false) async {
        if isLoadingBrewServices, !force { return }
        if !force,
           let lastBrewServicesDate,
           Date().timeIntervalSince(lastBrewServicesDate) < brewServicesCooldown,
           !brewServices.isEmpty {
            return
        }
        isLoadingBrewServices = true
        defer { isLoadingBrewServices = false }
        brewServices = await BrewMaintenanceService.listServices(mirror: settings.brewMirror)
        lastBrewServicesDate = Date()
    }

    func loadFormulaDependencies(for formula: String) async {
        let key = formula.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cached = formulaDependencyCache[key] {
            formulaDependencyRoot = cached
            formulaDependencyError = nil
            return
        }

        isLoadingFormulaDependencies = true
        formulaDependencyError = nil
        formulaDependencyRoot = nil
        defer { isLoadingFormulaDependencies = false }

        let result = await BrewDependencyService.fetchTree(
            formula: formula,
            mirror: settings.brewMirror
        )
        switch result {
        case .success(let root):
            formulaDependencyRoot = root
            formulaDependencyCache[key] = root
        case .failure(let error):
            formulaDependencyError = error.localizedDescription
        }
    }

    func fetchReverseDependencies(formula: String) async -> [String] {
        await BrewDependencyService.fetchDependents(
            formula: formula,
            mirror: settings.brewMirror
        )
    }

    var installedFormulaeNames: [String] {
        guard let snapshot = installedSnapshot else { return [] }
        return snapshot.formulae.sorted()
    }

    func filteredInstalledFormulae(search: String, onlyIntentional: Bool) -> [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return installedFormulaeNames.filter { name in
            if onlyIntentional, !isIntentionalFormula(name) { return false }
            return query.isEmpty || name.localizedCaseInsensitiveContains(query)
        }
    }

    func isIntentionalFormula(_ name: String) -> Bool {
        settings.isFormulaTagged(name) || brewLeavesNames.contains(name.lowercased())
    }

    func toggleFormulaTag(_ name: String) {
        settings.toggleFormulaTagged(name)
    }

    func loadBrewLeaves(force: Bool = false) async {
        if isLoadingBrewLeaves, !force { return }
        isLoadingBrewLeaves = true
        defer { isLoadingBrewLeaves = false }
        brewLeavesNames = await BrewMaintenanceService.fetchLeaves(mirror: settings.brewMirror)
    }

    func loadPinnedFormulae(force: Bool = false) async {
        if isLoadingPinned, !force { return }
        if !force,
           let lastPinnedFormulaeDate,
           Date().timeIntervalSince(lastPinnedFormulaeDate) < pinnedFormulaeCooldown {
            return
        }
        isLoadingPinned = true
        defer { isLoadingPinned = false }
        let pinned = await homebrewService.listPinned()
        pinnedFormulae = Set(pinned.map { $0.lowercased() })
        lastPinnedFormulaeDate = Date()
    }

    func togglePin(formula: String) async {
        let key = formula.lowercased()
        if pinnedFormulae.contains(key) {
            do {
                try await homebrewService.unpinFormula(formula)
                pinnedFormulae.remove(key)
            } catch {
                maintenanceStatusMessage = "解锁失败：\(error.localizedDescription)"
            }
        } else {
            do {
                try await homebrewService.pinFormula(formula)
                pinnedFormulae.insert(key)
            } catch {
                maintenanceStatusMessage = "锁定失败：\(error.localizedDescription)"
            }
        }
    }

    func runBrewService(name: String, action: BrewServiceAction) async {
        brewServiceActionID = "\(name)-\(action.rawValue)"
        defer { brewServiceActionID = nil }
        do {
            _ = try await BrewMaintenanceService.runService(
                name: name,
                action: action,
                mirror: settings.brewMirror
            )
            await loadBrewServices(force: true)
        } catch {
            maintenanceStatusMessage = "服务操作失败：\(error.localizedDescription)"
        }
    }

    func loadBrewDiskUsage(force: Bool = false) async {
        if isLoadingBrewDisk, !force { return }
        isLoadingBrewDisk = true
        defer { isLoadingBrewDisk = false }
        brewDiskUsage = await BrewMaintenanceService.loadDiskUsage(mirror: settings.brewMirror)
    }

    func runBrewCleanup() async {
        isRunningBrewCleanup = true
        defer { isRunningBrewCleanup = false }
        do {
            _ = try await BrewMaintenanceService.runCleanup(mirror: settings.brewMirror)
            await loadBrewDiskUsage(force: true)
            maintenanceStatusMessage = "Homebrew 缓存清理完成"
        } catch {
            maintenanceStatusMessage = "清理失败：\(error.localizedDescription)"
        }
    }

    func loadBrewVulnerabilities(force: Bool = false) async {
        if isLoadingBrewVulns, !force { return }
        isLoadingBrewVulns = true
        defer { isLoadingBrewVulns = false }
        brewVulnerabilityScan = await BrewMaintenanceService.scanVulnerabilities(mirror: settings.brewMirror)
    }

    func installBrewVulnsPlugin() async {
        isInstallingBrewVulnsPlugin = true
        defer { isInstallingBrewVulnsPlugin = false }
        do {
            _ = try await BrewMaintenanceService.installVulnsPlugin(mirror: settings.brewMirror)
            maintenanceStatusMessage = "brew-vulns 已安装，正在扫描…"
            await loadBrewVulnerabilities(force: true)
        } catch {
            maintenanceStatusMessage = "安装 brew-vulns 失败：\(error.localizedDescription)"
        }
    }

    func refreshMackupStatus(force: Bool = false) async {
        if !force,
           let lastMackupStatusDate,
           Date().timeIntervalSince(lastMackupStatusDate) < mackupStatusCooldown {
            return
        }
        mackupInstalled = await MackupGuideService.isInstalled()
        lastMackupStatusDate = Date()
    }

    func cancelMaintenanceSession() {
        maintenanceManager.requestCancel()
    }

    func installMackup() async {
        let tool = DevTool(
            id: "mackup",
            name: "Mackup",
            description: "应用设置备份",
            category: "utilities",
            source: InstallSource(type: .formula, identifier: MackupGuideService.installFormula),
            priority: 35
        )
        maintenanceManager.beginInstallSession(tools: [tool], title: "安装 Mackup")
        showMaintenanceSheet = true
        await maintenanceManager.runInstalls(tools: [tool], mirror: settings.brewMirror)
        await refreshMackupStatus()
        if maintenanceManager.completedCount > 0 {
            mackupInstalled = true
        }
    }

    /// 发现页后台准备：复用 runtime 快照 + 图标预载。trending 仅由 `setDiscoverMode` / 显式 refresh 触发。
}

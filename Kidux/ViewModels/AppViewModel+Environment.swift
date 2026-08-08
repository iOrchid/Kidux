import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

extension AppViewModel {
    func checkEnvironment(force: Bool = false) async {
        if !force,
           let lastEnvironmentCheckDate,
           Date().timeIntervalSince(lastEnvironmentCheckDate) < environmentCheckCooldown {
            return
        }
        isCheckingEnvironment = true
        defer { isCheckingEnvironment = false }
        environmentStatus = await EnvironmentChecker().check()
        lastEnvironmentCheckDate = Date()
    }

    func scanRuntimeEnvironment(force: Bool = false) async {
        if runtimeScanInFlight { return }
        if !force,
           let lastRuntimeScanDate,
           Date().timeIntervalSince(lastRuntimeScanDate) < runtimeScanCooldown,
           !runtimeProfiles.isEmpty {
            return
        }

        runtimeScanInFlight = true
        isScanningRuntimeEnvironment = true

        let snapshot = await RuntimeEnvironmentService.scan()
        runtimeProfiles = snapshot.runtimes
        localServiceHealth = snapshot.services
        brewServices = snapshot.brewServices
        versionManagerProfiles = snapshot.versionManagers
        runtimeEnvironmentScannedAt = snapshot.scannedAt
        lastRuntimeScanDate = Date()
        // 主扫描一结束立刻清 loading；漂移对比放后面，避免环境页一直转圈。
        isScanningRuntimeEnvironment = false
        runtimeScanInFlight = false

        await compareEnvironmentDriftIfBaselineExists(runtime: snapshot)
    }

    func captureEnvironmentDriftBaseline() async {
        isComparingEnvironmentDrift = true
        defer { isComparingEnvironmentDrift = false }
        let state = await EnvironmentDriftService.captureCurrent(mirror: settings.brewMirror)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let label = "本机 \(formatter.string(from: state.capturedAt))"
        settings.saveDriftBaseline(state, label: label)
        environmentDriftStatusMessage = "已保存漂移基准（\(state.brewFormulae.count) formula · \(state.brewCasks.count) cask）"
        await compareEnvironmentDriftIfBaselineExists()
    }

    func compareEnvironmentDrift(force: Bool = false, runtime: RuntimeEnvironmentSnapshot? = nil) async {
        guard let baseline = settings.loadDriftBaseline() else {
            environmentDriftReport = nil
            if force {
                environmentDriftStatusMessage = "尚未设置漂移基准，可点「设为基准」或导出/导入 v3 快照"
            }
            return
        }
        if isComparingEnvironmentDrift, !force { return }
        isComparingEnvironmentDrift = true
        defer { isComparingEnvironmentDrift = false }
        let current = await EnvironmentDriftService.captureCurrent(
            mirror: settings.brewMirror,
            runtime: runtime
        )
        environmentDriftReport = EnvironmentDriftService.compare(baseline: baseline, current: current)
        environmentDriftExplanation = nil
    }

    func explainEnvironmentDriftWithAI() async {
        guard let report = environmentDriftReport, report.hasDrift else { return }

        isExplainingEnvironmentDrift = true
        defer { isExplainingEnvironmentDrift = false }

        let label = environmentDriftBaselineLabel.isEmpty ? "未命名基准" : environmentDriftBaselineLabel
        var explanation: EnvironmentDriftExplanation?

        explanation = try? await AppleIntelligenceSupport.explainEnvironmentDrift(
            report: report,
            baselineLabel: label
        )

        if explanation == nil,
           !settings.offlineMode,
           settings.enableCloudAI,
           settings.hasAIAPIKey {
            explanation = try? await EnvironmentDriftExplanationService.explainWithLLM(
                report: report,
                baselineLabel: label,
                apiKey: settings.aiAPIKey,
                model: settings.aiModel,
                baseURL: settings.effectiveBaseURL
            )
        }

        environmentDriftExplanation = explanation
            ?? EnvironmentDriftExplanationService.explainRules(report: report, baselineLabel: label)
    }

    func installDriftMissingPackages() async {
        guard let report = environmentDriftReport else { return }
        let plan = EnvironmentDriftService.suggestFixes(from: report)
        guard plan.hasInstallableMissing else {
            environmentDriftStatusMessage = "当前漂移项没有可通过 Homebrew 一键补齐的包"
            return
        }

        isInstallingDriftMissing = true
        defer { isInstallingDriftMissing = false }

        let catalog = Array(bundleManager.catalog.values)
        var tools: [DevTool] = []

        for name in plan.missingFormulae {
            if let tool = catalog.first(where: {
                $0.source.type == .formula && ($0.source.identifier == name || $0.id == name)
            }) {
                tools.append(tool)
            } else {
                tools.append(DevTool(
                    id: name,
                    name: name,
                    description: "漂移补齐",
                    category: "infra",
                    source: InstallSource(type: .formula, identifier: name)
                ))
            }
        }

        for name in plan.missingCasks {
            if let tool = catalog.first(where: {
                $0.source.type == .cask && ($0.source.identifier == name || $0.id == name)
            }) {
                tools.append(tool)
            } else {
                tools.append(DevTool(
                    id: name,
                    name: name,
                    description: "漂移补齐",
                    category: "infra",
                    kind: .gui,
                    source: InstallSource(type: .cask, identifier: name)
                ))
            }
        }

        await maintenanceManager.runInstalls(tools: tools, mirror: settings.brewMirror)
        await scanInstalledStatus(force: true)
        await compareEnvironmentDrift(force: true)
        environmentDriftStatusMessage = "已尝试补齐 \(tools.count) 个缺失包（\(plan.summary)）"
    }

    func compareEnvironmentDriftIfBaselineExists(
        force: Bool = false,
        runtime: RuntimeEnvironmentSnapshot? = nil
    ) async {
        guard settings.loadDriftBaseline() != nil else { return }
        if !force,
           let lastDriftCompareDate,
           Date().timeIntervalSince(lastDriftCompareDate) < driftCompareCooldown,
           environmentDriftReport != nil {
            return
        }
        await compareEnvironmentDrift(force: force, runtime: runtime)
        lastDriftCompareDate = Date()
    }

    var hasEnvironmentDriftBaseline: Bool {
        settings.loadDriftBaseline() != nil
    }

    var environmentDriftBaselineLabel: String {
        settings.driftBaselineLabel
    }

    var isEnvironmentDriftBaselineStale: Bool {
        guard let baseline = settings.loadDriftBaseline() else { return false }
        return SnapshotFreshness.isStale(exportedAt: baseline.capturedAt)
    }

    var environmentDriftBaselineStaleCaption: String? {
        guard let baseline = settings.loadDriftBaseline(),
              SnapshotFreshness.isStale(exportedAt: baseline.capturedAt) else {
            return nil
        }
        return SnapshotFreshness.staleBaselineCaption(capturedAt: baseline.capturedAt)
    }

    func openMigrationWizard() {
        showMigrationWizard = true
        focusMainWindow()
    }

    var menuBarHealthStatus: MenuBarHealthStatus {
        guard settings.showMenuBarHealthIndicator else { return .green }

        if let report = environmentDriftReport, report.hasDrift {
            return .red
        }
        if localServiceHealth.contains(where: { $0.state == .unreachable }) {
            return .red
        }
        if outdatedCount > 0 {
            return .yellow
        }
        if localServiceHealth.contains(where: { $0.state == .installed }) {
            return .yellow
        }
        if !hasEnvironmentDriftBaseline, runtimeProfiles.isEmpty, localServiceHealth.isEmpty {
            return .gray
        }
        return .green
    }

    var menuBarHealthDetailLine: String? {
        if let report = environmentDriftReport, report.hasDrift {
            return "环境漂移：\(report.summaryLine)"
        }
        if let unhealthy = localServiceHealth.first(where: { $0.state == .unreachable || $0.state == .installed }) {
            return "\(unhealthy.kind.title) \(unhealthy.state.label)"
        }
        if outdatedCount > 0 {
            return "\(outdatedCount) 款可更新"
        }
        if menuBarHealthStatus == .green {
            return "环境与基准一致"
        }
        return nil
    }

    func refreshMenuBarEnvironment() async {
        await scanRuntimeEnvironment()
        await compareEnvironmentDriftIfBaselineExists()
        publishWidgetSnapshot()
    }

    /// S20-03 — 写入 App Group 快照并刷新桌面小组件
    func publishWidgetSnapshot() {
        let installing = installManager.isInstalling
        let total = max(installManager.tasks.count, 1)
        let finished = installManager.tasks.filter {
            switch $0.status {
            case .success, .failed, .skipped, .cancelled: return true
            case .pending, .running: return false
            }
        }.count
        let progress = installing ? Double(finished) / Double(total) : 0
        let health: String
        switch menuBarHealthStatus {
        case .green: health = "green"
        case .yellow: health = "yellow"
        case .red: health = "red"
        case .gray: health = "gray"
        }

        KiduxWidgetSnapshotStore.save(
            KiduxWidgetSnapshot(
                outdatedCount: outdatedCount,
                healthRaw: health,
                healthDetail: menuBarHealthDetailLine,
                isInstalling: installing,
                installTitle: installManager.currentTask.map { $0.displayName },
                installProgress: progress,
                updatedAt: Date()
            )
        )
    }

}

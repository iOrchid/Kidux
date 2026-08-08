import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

extension AppViewModel {
    func scanInstalledStatus(force: Bool = false, checkUpdates: Bool = true) async {
        if scanInFlight { return }
        if !force,
           let lastScanDate,
           Date().timeIntervalSince(lastScanDate) < scanCooldown,
           installedSnapshot != nil {
            // 本机 /Applications 扫描不在启动路径触发（会弹「访问其他 App 数据」），仅已安装页按需调用。
            if checkUpdates, outdatedResult == nil, !isCheckingUpdates {
                await checkForUpdates()
            }
            return
        }

        scanInFlight = true
        isScanningInstalled = true
        defer {
            scanInFlight = false
            lastScanDate = Date()
        }
        let scanner = installedScanner
        let enableMAS = settings.enableMAS
        installedSnapshot = await BrewSessionCoordinator.shared.installedSnapshot(force: force) {
            await scanner.scan(enableMAS: enableMAS)
        }
        isScanningInstalled = false
        if checkUpdates {
            await checkForUpdates()
        }
    }

    func ensureUpdatesChecked() async {
        if outdatedResult != nil { return }
        while isCheckingUpdates {
            try? await Task.sleep(for: .milliseconds(150))
        }
        if outdatedResult == nil {
            await checkForUpdates()
        }
    }

    func checkForUpdates(force: Bool = false) async {
        if isCheckingUpdates {
            if force {
                while isCheckingUpdates {
                    try? await Task.sleep(for: .milliseconds(150))
                }
            } else {
                return
            }
        }
        isCheckingUpdates = true
        updateCheckMessage = nil
        defer { isCheckingUpdates = false }

        let started = Date()
        let catalog = bundleManager.catalog
        let mirror = settings.brewMirror
        let enableMAS = settings.enableMAS
        let scan = await BrewSessionCoordinator.shared.outdatedScan(force: force) {
            await UpdateCheckService.scanOutdated(
                catalog: catalog,
                mirror: mirror,
                enableMAS: enableMAS
            )
        }
        outdatedResult = scan.result

        if scan.timedOut {
            updateCheckMessage = "检查超时或网络较慢，请确认 Homebrew / mas 可用后重试"
        } else if scan.result.allEntries.isEmpty, Date().timeIntervalSince(started) >= 40 {
            updateCheckMessage = "检查超时或网络较慢，请确认 Homebrew / mas 可用后重试"
        }
        publishWidgetSnapshot()
    }

    /// App 启动时：按需跑定时更新节流检查 + 健康周报
    func runBackgroundMaintenanceTasksIfNeeded() async {
        if settings.scheduledBrewUpdateEnabled {
            await runScheduledBrewUpdate(force: false)
        }
        if settings.weeklyHealthDigestEnabled {
            await runWeeklyHealthDigest(force: false)
        }
    }

    /// S18-17 — brew update + outdated；force 时忽略 20h 节流（LaunchAgent 触发）
    func runScheduledBrewUpdate(force: Bool) async {
        guard settings.scheduledBrewUpdateEnabled || force else { return }
        if settings.offlineMode {
            extendedCatalogStatusMessage = "离线模式已开启，已跳过定时 brew 更新"
            return
        }

        if !force, let last = settings.lastScheduledBrewUpdateAt,
           Date().timeIntervalSince(last) < 20 * 3600
        {
            return
        }

        let brew = HomebrewService()
        _ = await brew.updateIndex(mirror: settings.brewMirror)
        await checkForUpdates(force: true)
        settings.lastScheduledBrewUpdateAt = Date()

        let count = outdatedCount
        if count > 0 {
            await InstallNotificationService.notifyOutdatedAvailable(count: count)
            extendedCatalogStatusMessage = "定时扫描完成：\(count) 款可更新"
        } else {
            extendedCatalogStatusMessage = "定时扫描完成：软件已是最新"
        }
        publishWidgetSnapshot()
    }

    func applyScheduledBrewUpdatePreference(enabled: Bool) {
        settings.scheduledBrewUpdateEnabled = enabled
        do {
            if enabled {
                try MaintenanceSchedulerService.installScheduledUpdateAgent()
                Task { await InstallNotificationService.requestAuthorizationIfNeeded() }
                extendedCatalogStatusMessage = "已开启定时更新（每天 10:00 后台检查）"
            } else {
                MaintenanceSchedulerService.uninstallScheduledUpdateAgent()
                extendedCatalogStatusMessage = "已关闭定时更新"
            }
        } catch {
            extendedCatalogStatusMessage = "LaunchAgent 配置失败：\(error.localizedDescription)"
            settings.scheduledBrewUpdateEnabled = false
        }
    }

    /// S19-03 — 每周环境健康摘要通知
    func runWeeklyHealthDigest(force: Bool) async {
        guard settings.weeklyHealthDigestEnabled || force else { return }

        if !force, let last = settings.lastWeeklyHealthDigestAt,
           Date().timeIntervalSince(last) < 7 * 24 * 3600
        {
            return
        }

        if outdatedResult == nil {
            await checkForUpdates(force: false)
        }
        if settings.loadDriftBaseline() != nil {
            await compareEnvironmentDrift()
        }
        if brewServices.isEmpty {
            await loadBrewServices()
        }

        var parts: [String] = []
        let outdated = outdatedCount
        parts.append(outdated > 0 ? "\(outdated) 款可更新" : "软件已是最新")

        if let report = environmentDriftReport {
            let missing = report.items.filter { $0.kind == .missing }.count
            if missing > 0 {
                parts.append("漂移缺失 \(missing) 项")
            } else if report.hasDrift {
                parts.append(report.summaryLine)
            } else {
                parts.append("环境与基准一致")
            }
        }

        if let errored = brewServices.first(where: { $0.status == "error" }) {
            parts.append("服务异常：\(errored.name)")
        } else if let stopped = brewServices.first(where: { $0.status == "stopped" }) {
            parts.append("服务已停：\(stopped.name)")
        } else if !brewServices.isEmpty {
            parts.append("后台服务正常")
        }

        if let baseline = settings.loadDriftBaseline(),
           SnapshotFreshness.isStale(exportedAt: baseline.capturedAt)
        {
            parts.append("基准快照已过期")
        }

        let body = parts.joined(separator: " · ")
        await InstallNotificationService.notifyWeeklyHealthDigest(body: body)
        settings.lastWeeklyHealthDigestAt = Date()
        extendedCatalogStatusMessage = "已发送本周健康周报"
    }

    func applyWeeklyHealthDigestPreference(enabled: Bool) {
        settings.weeklyHealthDigestEnabled = enabled
        if enabled {
            Task {
                await InstallNotificationService.requestAuthorizationIfNeeded()
                await runWeeklyHealthDigest(force: true)
            }
            extendedCatalogStatusMessage = "已开启健康周报（约每周一次）"
        } else {
            extendedCatalogStatusMessage = "已关闭健康周报"
        }
    }

    func checkKiduxAppUpdate(sparkleBackground: Bool = false) async {
        guard !isCheckingAppUpdate else { return }
        isCheckingAppUpdate = true
        defer { isCheckingAppUpdate = false }

        if settings.offlineMode {
            appUpdateInfo = nil
            appUpdateStatusMessage = "离线模式已开启，已跳过应用更新检查"
            return
        }

        if sparkleBackground, SparkleUpdateController.shared.canCheckForUpdates {
            SparkleUpdateController.shared.checkForUpdatesInBackground()
        }

        appUpdateInfo = await KiduxAppUpdateService.checkForUpdate()
        if appUpdateInfo == nil {
            if SparkleUpdateController.shared.isConfigured {
                appUpdateStatusMessage = "暂无新版本 · Sparkle 已在后台检查更新源"
            } else {
                appUpdateStatusMessage = "当前已是最新版本 v\(AppInfo.marketingVersion)"
            }
        } else {
            appUpdateStatusMessage = nil
        }
    }

    func checkKiduxAppUpdateWithSparkleUI() {
        SparkleUpdateController.shared.checkForUpdates()
    }

    func openKiduxDownloadPage() {
        if let url = appUpdateInfo?.downloadURL {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(RepositoryConfig.releasesURL)
        }
    }

}

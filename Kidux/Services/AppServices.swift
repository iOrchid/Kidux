import Foundation

/// S22-20 — 共享服务容器，供 AppViewModel 各域 extension 复用同一套依赖。
@MainActor
final class AppServices {
    let settings = AppSettings.shared
    let bundleManager = BundleManager()
    let installManager = InstallManager()
    let maintenanceManager = MaintenanceManager()
    let installedScanner = InstalledStatusScanner()
    let localAppsScanner = LocalApplicationsScanner()
    let homebrewService = HomebrewService()

    var isBrewBusy: Bool {
        installManager.isInstalling || maintenanceManager.isRunning
    }

    var brewBusyTitle: String? {
        if installManager.isInstalling {
            return installManager.currentTask?.displayName ?? "正在安装…"
        }
        if maintenanceManager.isRunning {
            return maintenanceManager.sessionTitle
        }
        return nil
    }
}

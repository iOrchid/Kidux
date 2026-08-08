import Foundation
import Sparkle

/// Sparkle 自动更新。更新源见 `RepositoryConfig.appcastFeedURL`。
@MainActor
final class SparkleUpdateController: NSObject {
    static let shared = SparkleUpdateController()

    private let controller: SPUStandardUpdaterController
    private let updaterDelegate: SparkleUpdaterDelegateHost
    private var didStartUpdater = false

    private override init() {
        let host = SparkleUpdaterDelegateHost()
        updaterDelegate = host
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: host,
            userDriverDelegate: nil
        )
        super.init()
    }

    func startUpdaterIfNeeded() {
        guard !didStartUpdater else { return }
        guard isConfigured else { return }
        do {
            try controller.updater.start()
            didStartUpdater = true
        } catch {
            #if DEBUG
            print("Sparkle startUpdater failed: \(error)")
            #endif
        }
    }

    var isConfigured: Bool {
        true
    }

    var canCheckForUpdates: Bool {
        didStartUpdater && controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        guard canCheckForUpdates else { return }
        controller.updater.checkForUpdatesInBackground()
    }
}

/// 退出安装路径的轻量 delegate；并提供统一配置的 appcast URL。
private final class SparkleUpdaterDelegateHost: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        RepositoryConfig.appcastFeedURL.absoluteString
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        false
    }
}

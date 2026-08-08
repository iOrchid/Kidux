import AppKit
import Foundation

enum KiduxPendingSearch {
    static let defaultsKey = "kidux.pendingDiscoverSearch"
}

@MainActor
final class AppIntentBridge {
    static let shared = AppIntentBridge()

    weak var viewModel: AppViewModel?

    private init() {}

    func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func requireViewModel() throws -> AppViewModel {
        guard let viewModel else {
            throw AppIntentBridgeError.appNotReady
        }
        activateApp()
        return viewModel
    }
}

enum AppIntentBridgeError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            return "请先打开 Kidux 应用"
        }
    }
}

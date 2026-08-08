import Foundation
import AppKit

/// 统一退出闸门：先停 chrome / 语音 / shell，再 terminate，避免关窗与 WindowServer 死锁。
@MainActor
enum KiduxTerminationGuard {
    private static var didBegin = false

    /// 幂等；可在 `applicationShouldTerminate` / 菜单「退出」中调用。
    static func beginShutdown() async {
        guard !didBegin else { return }
        didBegin = true

        WindowChromeEnforcer.isEnabled = false

        DiscoverSpeechInputService.shared.stopListening()
        await AppIntentBridge.shared.viewModel?.prepareForTermination()
        await ShellProcessRegistry.shared.cancelAll(graceSeconds: 1.5)
    }

    static func requestQuit() {
        NSApplication.shared.terminate(nil)
    }
}

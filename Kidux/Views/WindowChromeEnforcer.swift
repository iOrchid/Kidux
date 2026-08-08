import AppKit
import SwiftUI

/// 仅纠正**主窗口标题**；不再改 `styleMask` / titlebar 透明等 chrome。
///
/// 历史问题：在 `didBecomeKey` / `willBecomeActive` / layout 循环里改 `styleMask`
///（尤其 `.fullSizeContentView`）会与 WindowServer 竞态，曾出现整桌假死。
/// 标题栏样式交给 SwiftUI：`windowStyle(.titleBar)` + `toolbarBackground(.visible)`。
enum WindowChromeEnforcer {
    /// 进程退出准备开始后置 false，阻止一切窗口写入。
    nonisolated(unsafe) static var isEnabled = true

    /// 仅设置窗口标题；禁止触碰 styleMask。
    static func applyTitle(_ title: String, to window: NSWindow?) {
        guard isEnabled else { return }
        guard let window else { return }
        guard shouldManage(window) else { return }
        guard !title.isEmpty, window.title != title else { return }
        window.title = title
    }

    /// - Warning: 已废弃 styleMask 修正。保留空实现供旧调用点安全退化。
    static func apply(to window: NSWindow?) {
        // 故意 no-op：不再改 chrome，避免 WindowServer 假死。
        _ = window
    }

    private static func shouldManage(_ window: NSWindow) -> Bool {
        guard window.styleMask.contains(.titled) else { return false }
        guard window.level == .normal else { return false }
        guard window.canBecomeMain else { return false }
        guard window.isVisible || window.isKeyWindow || window.isMainWindow else { return false }
        let autosave = window.frameAutosaveName
        if autosave.localizedCaseInsensitiveContains("settings")
            || autosave.localizedCaseInsensitiveContains("preferences") {
            return false
        }
        let title = window.title
        if title == "设置"
            || title == String(localized: "ui.WindowChromeEnforcer.e366ccf155")
            || title.localizedCaseInsensitiveContains("Settings") {
            return false
        }
        return true
    }
}

struct WindowChromeFixer: NSViewRepresentable {
    var title: String

    func makeNSView(context: Context) -> NSView {
        let view = ChromeHostView()
        view.title = title
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard WindowChromeEnforcer.isEnabled else { return }
        guard let view = nsView as? ChromeHostView else { return }
        view.title = title
        view.applyTitleIfNeeded()
    }
}

private final class ChromeHostView: NSView {
    var title: String = ""
    private var lastAppliedTitle: String?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lastAppliedTitle = nil
        applyTitleIfNeeded()
    }

    func applyTitleIfNeeded() {
        guard WindowChromeEnforcer.isEnabled else { return }
        guard let window else { return }
        guard !title.isEmpty else { return }
        guard lastAppliedTitle != title || window.title != title else { return }
        lastAppliedTitle = title
        WindowChromeEnforcer.applyTitle(title, to: window)
    }
}

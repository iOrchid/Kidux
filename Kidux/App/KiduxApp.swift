import SwiftUI
import AppKit
import CoreSpotlight

private final class KiduxAppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: AppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshApplicationIcon()
        applyChineseAppMenuTitle()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        // 不再在启动 / key / active 时批量改窗口 chrome（曾与桌面假死相关）。
        // 主窗标题由 ContentView 的 WindowChromeFixer 一次性写入。
        Task { @MainActor in
            SparkleUpdateController.shared.startUpdaterIfNeeded()
        }
    }

    /// 菜单栏最左侧应用菜单名：CFBundleName 常被 PRODUCT_NAME=Kidux 覆盖，运行时再钉成「启椟」。
    private func applyChineseAppMenuTitle() {
        let title = BrandInfo.displayNameCN
        if let appMenu = NSApp.mainMenu?.items.first {
            appMenu.title = title
        }
        // About 面板标题
        NSApplication.shared.helpMenu?.title = "帮助"
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        refreshApplicationIcon()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WindowChromeEnforcer.isEnabled = false
        Task { @MainActor in
            await KiduxTerminationGuard.beginShutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowChromeEnforcer.isEnabled = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        viewModel?.focusMainWindow()
        return true
    }

    @objc func searchInKidux(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let text = (pboard.string(forType: .string) ?? pboard.string(forType: .html) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            error?.pointee = "未选中可搜索的文字" as NSString
            return
        }

        UserDefaults.standard.set(text, forKey: KiduxPendingSearch.defaultsKey)
        var components = URLComponents(string: "kidux://search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshApplicationIcon() {
        let branded = BrandAppIcon.renderedImage(size: 512)
        NSApp.applicationIconImage = MacIconStyle.applySquircleMask(to: branded, size: 512)
    }
}

@main
struct KiduxApp: App {
    @NSApplicationDelegateAdaptor(KiduxAppDelegate.self) private var appDelegate
    @State private var appViewModel = AppViewModel()

    init() {
        KiduxTips.configureIfAvailable()
        AIModelCatalogService.bootstrap()
        DiagnosticsEventLog.recordLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appViewModel)
                .frame(minWidth: 1000, minHeight: 650)
                .onAppear {
                    AppIntentBridge.shared.viewModel = appViewModel
                    appDelegate.viewModel = appViewModel
                    appViewModel.consumePendingDiscoverSearch()
                }
                .onOpenURL { url in
                    Task { await appViewModel.handleIncomingKiduxURL(url) }
                }
                .task {
                    // 延后非关键后台任务，避免首启叠权限弹窗
                    try? await Task.sleep(for: .seconds(10))
                    await appViewModel.runBackgroundMaintenanceTasksIfNeeded()
                    appViewModel.consumePendingDiscoverSearch()
                    _ = await AIModelCatalogService.refreshFromRemote(force: false)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let toolID = CatalogSpotlightIndexer.toolID(from: activity) {
                        appViewModel.navigateToCatalogTool(id: toolID)
                    }
                }
                .onContinueUserActivity("co.langem.kidux.view-tool") { activity in
                    if let toolID = activity.userInfo?["toolID"] as? String {
                        appViewModel.navigateToCatalogTool(id: toolID)
                    }
                }
        }
        .defaultSize(width: 1100, height: 750)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(String(localized: "app.quit")) {
                    KiduxTerminationGuard.requestQuit()
                }
                .keyboardShortcut("q")
            }
            CommandGroup(replacing: .saveItem) {
                Button(String(localized: "nav.close_window")) {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w")
            }
            CommandMenu(String(localized: "nav.menu")) {
                Button(String(localized: "tab.home")) { appViewModel.navigateTo(.home) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button(String(localized: "tab.assistant")) { appViewModel.navigateTo(.assistant) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button(String(localized: "tab.roles")) { appViewModel.navigateTo(.roles) }
                    .keyboardShortcut("3", modifiers: [.command])
                Button(String(localized: "tab.discover")) { appViewModel.navigateTo(.discover) }
                    .keyboardShortcut("4", modifiers: [.command])
                Button(String(localized: "tab.installed")) { appViewModel.navigateTo(.installed) }
                    .keyboardShortcut("5", modifiers: [.command])
                Button(String(localized: "tab.environment")) { appViewModel.navigateTo(.environment) }
                    .keyboardShortcut("6", modifiers: [.command])
                Divider()
                Button(String(localized: "nav.show_sidebar")) {
                    appViewModel.focusMainWindow()
                }
            }
            CommandMenu(String(localized: "discover.menu")) {
                Button(String(localized: "nav.command_palette")) {
                    appViewModel.openCommandPalette()
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button(String(localized: "nav.check_updates")) {
                    Task { await appViewModel.checkForUpdates(force: true) }
                }
                Button(String(localized: "nav.open_settings")) {
                    appViewModel.openSystemSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(appViewModel)
                .frame(minWidth: 640, minHeight: 520)
        }

        KiduxMenuBarScene(viewModel: appViewModel)
    }
}

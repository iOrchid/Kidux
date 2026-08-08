import Foundation
import UserNotifications

enum InstallNotificationService {
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func notifyInstallFinished(summary: InstallSummary, cancelled: Bool) async {
        await requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = cancelled ? "启椟 · 安装已停止" : "启椟 · 安装完成"
        content.body = "成功 \(summary.succeeded) · 失败 \(summary.failed) · 跳过 \(summary.skipped)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "kidux.install.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    /// S18-17 — 定时扫描发现可更新软件
    static func notifyOutdatedAvailable(count: Int) async {
        guard count > 0 else { return }
        await requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "启椟 · 发现可更新软件"
        content.body = "有 \(count) 款软件可更新，打开启椟即可一键升级。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "kidux.outdated.\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    /// S19-03 — 环境健康周报
    static func notifyWeeklyHealthDigest(body: String) async {
        await requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "启椟 · 本周环境健康"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "kidux.weekly-health.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

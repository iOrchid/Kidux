import Foundation

/// S18-17 / S19-03 — 定时维护与健康周报共用的调度基础设施
enum MaintenanceSchedulerService {
    static let agentLabel = "co.langem.kidux.scheduled-update"
    static let scheduledUpdateURL = URL(string: "kidux://maintenance/scheduled-update")!
    static let weeklyDigestURL = URL(string: "kidux://maintenance/weekly-digest")!

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static func isLaunchAgentInstalled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    /// 安装/更新用户 LaunchAgent：每天本地时间 10:00 唤起 Kidux 做 brew update + outdated 扫描
    static func installScheduledUpdateAgent(hour: Int = 10, minute: Int = 0) throws {
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [
                "/usr/bin/open",
                "-g",
                scheduledUpdateURL.absoluteString
            ],
            "StartCalendarInterval": [
                "Hour": hour,
                "Minute": minute
            ],
            "RunAtLoad": false
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        let dir = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: launchAgentURL, options: .atomic)
        reloadLaunchAgent()
    }

    static func uninstallScheduledUpdateAgent() {
        let uid = getuid()
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(agentLabel)"])
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    private static func reloadLaunchAgent() {
        let uid = getuid()
        let path = launchAgentURL.path
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(agentLabel)"])
        if runLaunchctl(["bootstrap", "gui/\(uid)", path]) != 0 {
            _ = runLaunchctl(["load", "-w", path])
        }
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    static func parseMaintenanceURL(_ url: URL) -> MaintenanceAction? {
        guard url.scheme?.lowercased() == "kidux",
              url.host?.lowercased() == "maintenance"
        else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        // kidux://maintenance/scheduled-update → host=maintenance, path=/scheduled-update
        // Also accept host as action: kidux://scheduled-update (not used)
        switch path {
        case "scheduled-update", "":
            return .scheduledUpdate
        case "weekly-digest":
            return .weeklyDigest
        default:
            return nil
        }
    }

    enum MaintenanceAction: Sendable {
        case scheduledUpdate
        case weeklyDigest
    }
}

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// S20-03 — 主 App 与 Widget Extension 共享的快照数据
struct KiduxWidgetSnapshot: Codable, Sendable, Equatable {
    var outdatedCount: Int
    var healthRaw: String
    var healthDetail: String?
    var isInstalling: Bool
    var installTitle: String?
    var installProgress: Double
    var updatedAt: Date

    static let empty = KiduxWidgetSnapshot(
        outdatedCount: 0,
        healthRaw: "gray",
        healthDetail: nil,
        isInstalling: false,
        installTitle: nil,
        installProgress: 0,
        updatedAt: .distantPast
    )

    var healthLabel: String {
        switch healthRaw {
        case "green": return "环境正常"
        case "yellow": return "需关注"
        case "red": return "有风险"
        default: return "未扫描"
        }
    }
}

enum KiduxWidgetSnapshotStore {
    static let appGroupID = "group.co.langem.kidux"
    private static let defaultsKey = "kidux.widget.snapshot"
    private static let fileName = "widget-snapshot.json"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastReloadAt: Date = .distantPast
    private static let reloadCooldown: TimeInterval = 30

    /// 主 App 默认只写 Application Support，避免访问 App Group 触发 Sequoia
    /// 「想访问其他 App 的数据」（Debug 签名与扩展身份不一致时尤其明显）。
    nonisolated(unsafe) static var writesToAppGroup = false

    static func save(_ snapshot: KiduxWidgetSnapshot) {
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }

            if let url = applicationSupportFileURL() {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: url, options: .atomic)
            }

            if writesToAppGroup {
                if let defaults = UserDefaults(suiteName: appGroupID) {
                    defaults.set(data, forKey: defaultsKey)
                }
                if let url = appGroupFileURL() {
                    try? data.write(to: url, options: .atomic)
                }
            }

            let shouldReload: Bool = {
                lock.lock()
                defer { lock.unlock() }
                let now = Date()
                guard now.timeIntervalSince(lastReloadAt) >= reloadCooldown else { return false }
                lastReloadAt = now
                return true
            }()

            guard shouldReload, writesToAppGroup else { return }
            #if canImport(WidgetKit)
            await MainActor.run {
                WidgetCenter.shared.reloadAllTimelines()
            }
            #endif
        }
    }

    static func load() -> KiduxWidgetSnapshot {
        if let url = applicationSupportFileURL(),
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(KiduxWidgetSnapshot.self, from: data) {
            return snapshot
        }
        // Widget 扩展侧可读 App Group；主 App 冷路径不主动碰，以免弹 TCC。
        if writesToAppGroup,
           let defaults = UserDefaults(suiteName: appGroupID),
           let data = defaults.data(forKey: defaultsKey),
           let snapshot = try? JSONDecoder().decode(KiduxWidgetSnapshot.self, from: data) {
            return snapshot
        }
        if writesToAppGroup,
           let url = appGroupFileURL(),
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(KiduxWidgetSnapshot.self, from: data) {
            return snapshot
        }
        return .empty
    }

    private static func applicationSupportFileURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return support
            .appendingPathComponent("Kidux", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func appGroupFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }
}

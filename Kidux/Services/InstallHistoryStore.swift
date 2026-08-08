import Foundation
import Observation

private struct InstallHistoryFile: Codable {
    var entries: [InstallHistoryEntry]
}

/// 本地安装历史（S17-08）— `~/Library/Application Support/Kidux/install-history.json`
@MainActor
@Observable
final class InstallHistoryStore {
    static let shared = InstallHistoryStore()

    private(set) var entries: [InstallHistoryEntry] = []

    private var saveTask: Task<Void, Never>?
    private static let maxEntries = 100
    private static let saveDebounceNanoseconds: UInt64 = 5_000_000_000

    private var historyFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kidux/install-history.json")
    }

    private init() {
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path),
              let data = try? Data(contentsOf: historyFileURL),
              let file = try? JSONDecoder().decode(InstallHistoryFile.self, from: data)
        else {
            entries = []
            return
        }
        entries = file.entries.sorted { $0.date > $1.date }
    }

    func record(
        roleNames: [String],
        summary: InstallSummary,
        cancelled: Bool,
        source: InstallHistorySource
    ) {
        guard summary.total > 0 else { return }
        if cancelled, summary.succeeded == 0 { return }

        var parts: [String] = ["成功 \(summary.succeeded)"]
        if summary.failed > 0 { parts.append("失败 \(summary.failed)") }
        if summary.skipped > 0 { parts.append("跳过 \(summary.skipped)") }
        if cancelled { parts.append("已停止") }

        let entry = InstallHistoryEntry(
            roleNames: roleNames,
            toolCount: summary.total,
            summary: parts.joined(separator: " · "),
            source: source
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        scheduleSave()
    }

    func clearAll() {
        entries = []
        saveTask?.cancel()
        saveTask = nil
        try? FileManager.default.removeItem(at: historyFileURL)
    }

    /// S19-01 — 基于安装历史的累计统计（节省时间按每工具约 3 分钟手工装机估算）
    var stats: InstallStatsSummary {
        InstallStatsSummary(entries: entries)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: Self.saveDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            persistNow()
        }
    }

    private func persistNow() {
        let directory = historyFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = InstallHistoryFile(entries: entries)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: historyFileURL, options: .atomic)
    }
}

struct InstallStatsSummary: Sendable, Equatable {
    let sessionCount: Int
    let totalTools: Int
    let estimatedMinutesSaved: Int

    init(entries: [InstallHistoryEntry]) {
        sessionCount = entries.count
        totalTools = entries.reduce(0) { $0 + $1.toolCount }
        // 保守估算：每款工具手工检索 + 下载 + 配置约 3 分钟
        estimatedMinutesSaved = totalTools * 3
    }

    var estimatedTimeLabel: String {
        if estimatedMinutesSaved >= 60 {
            let hours = estimatedMinutesSaved / 60
            let mins = estimatedMinutesSaved % 60
            return mins == 0 ? "约 \(hours) 小时" : "约 \(hours) 小时 \(mins) 分钟"
        }
        return "约 \(estimatedMinutesSaved) 分钟"
    }

    var isEmpty: Bool { sessionCount == 0 }
}

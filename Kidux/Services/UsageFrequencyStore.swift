import Foundation
import Observation

/// S19-04 — 本机匿名使用频率（默认关；仅统计 toolID 与次数，不上报）
struct UsageFrequencyEntry: Codable, Sendable, Identifiable, Equatable {
    var id: String { toolID }
    var toolID: String
    var openCount: Int
    var installCount: Int
    var lastSeenAt: Date

    var score: Int { openCount * 2 + installCount * 5 }
}

private struct UsageFrequencyFile: Codable {
    var entries: [String: UsageFrequencyEntry]
}

@MainActor
@Observable
final class UsageFrequencyStore {
    static let shared = UsageFrequencyStore()

    private(set) var entries: [String: UsageFrequencyEntry] = [:]
    private var saveTask: Task<Void, Never>?

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kidux/usage-frequency.json")
    }

    private init() { load() }

    func recordOpen(toolID: String) {
        guard AppSettings.shared.usageFrequencyTrackingEnabled else { return }
        bump(toolID: toolID, open: 1, install: 0)
    }

    func recordInstall(toolID: String) {
        guard AppSettings.shared.usageFrequencyTrackingEnabled else { return }
        bump(toolID: toolID, open: 0, install: 1)
    }

    func recordInstalls(toolIDs: [String]) {
        guard AppSettings.shared.usageFrequencyTrackingEnabled else { return }
        for id in toolIDs { bump(toolID: id, open: 0, install: 1) }
    }

    func topTools(limit: Int = 10) -> [UsageFrequencyEntry] {
        entries.values.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }

    func clearAll() {
        entries = [:]
        saveTask?.cancel()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func bump(toolID: String, open: Int, install: Int) {
        var entry = entries[toolID] ?? UsageFrequencyEntry(
            toolID: toolID,
            openCount: 0,
            installCount: 0,
            lastSeenAt: Date()
        )
        entry.openCount += open
        entry.installCount += install
        entry.lastSeenAt = Date()
        entries[toolID] = entry
        scheduleSave()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(UsageFrequencyFile.self, from: data)
        else {
            entries = [:]
            return
        }
        entries = file.entries
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func persist() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = UsageFrequencyFile(entries: entries)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

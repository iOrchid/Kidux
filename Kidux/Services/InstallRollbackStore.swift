import Foundation

private struct InstallRollbackFile: Codable {
    var batch: InstallRollbackBatch?
}

struct InstallRollbackBatch: Codable, Sendable {
    let date: Date
    let toolIDs: [String]
    let source: InstallHistorySource
    let roleNames: [String]

    var label: String {
        let when = date.formatted(date: .abbreviated, time: .shortened)
        let roles = roleNames.isEmpty ? "安装批次" : roleNames.joined(separator: " · ")
        return "\(roles) · \(when) · \(toolIDs.count) 项"
    }
}

/// S18-15 — 记录最近一次成功安装的 brew 项，支持一键回滚卸载
@MainActor
enum InstallRollbackStore {
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kidux/install-rollback.json")
    }

    static func load() -> InstallRollbackBatch? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(InstallRollbackFile.self, from: data)
        else { return nil }
        return file.batch
    }

    static func record(
        toolIDs: [String],
        source: InstallHistorySource,
        roleNames: [String]
    ) {
        guard !toolIDs.isEmpty else { return }
        let batch = InstallRollbackBatch(
            date: Date(),
            toolIDs: toolIDs,
            source: source,
            roleNames: roleNames
        )
        persist(batch)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func persist(_ batch: InstallRollbackBatch) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = InstallRollbackFile(batch: batch)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

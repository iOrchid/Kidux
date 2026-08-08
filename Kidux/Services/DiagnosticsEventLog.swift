import Foundation
import OSLog

/// 诊断事件落盘：OSLog + Application Support jsonl，便于强制重启后对照时间线。
actor DiagnosticsEventLogStore {
    static let shared = DiagnosticsEventLogStore()

    private let logger = Logger(subsystem: "co.langem.kidux", category: "diagnostics")
    private let maxLines = 800
    private let iso = ISO8601DateFormatter()
    private var appendCountSinceTrim = 0

    var diagnosticsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kidux/diagnostics", isDirectory: true)
    }

    var eventsFileURL: URL {
        diagnosticsDirectory.appendingPathComponent("events.jsonl")
    }

    func recordLaunch() {
        record(
            "app.launch",
            fields: [
                "version": AppInfo.marketingVersion,
                "build": AppInfo.buildNumber,
                "pid": "\(ProcessInfo.processInfo.processIdentifier)"
            ]
        )
    }

    func record(
        _ event: String,
        durationMs: Double? = nil,
        fields: [String: String] = [:]
    ) {
        var payload: [String: Any] = [
            "ts": iso.string(from: Date()),
            "event": event
        ]
        if let durationMs {
            payload["durationMs"] = (durationMs * 10).rounded() / 10
        }
        if !fields.isEmpty {
            payload["fields"] = fields
        }

        let line: String
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            line = text
        } else {
            line = #"{"ts":"\#(iso.string(from: Date()))","event":"\#(event)"}"#
        }

        let fieldSummary = fields
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        if let durationMs {
            logger.info("\(event, privacy: .public) \(durationMs, format: .fixed(precision: 1))ms \(fieldSummary, privacy: .public)")
        } else {
            logger.info("\(event, privacy: .public) \(fieldSummary, privacy: .public)")
        }

        appendLine(line)
    }

    func snapshotEventsFile() -> URL? {
        trimIfNeeded(force: true)
        let url = eventsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func appendLine(_ line: String) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
            let url = eventsFileURL
            if !fm.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = (line + "\n").data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            appendCountSinceTrim += 1
            if appendCountSinceTrim >= 40 {
                trimIfNeeded(force: false)
            }
        } catch {
            logger.error("diagnostics append failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func trimIfNeeded(force: Bool) {
        guard force || appendCountSinceTrim >= 40 else { return }
        appendCountSinceTrim = 0
        let url = eventsFileURL
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        guard lines.count > maxLines else { return }
        let kept = Array(lines.suffix(maxLines)).joined(separator: "\n") + "\n"
        try? kept.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// 同步调用门面：fire-and-forget 写盘，导出时 await 快照。
enum DiagnosticsEventLog {
    static var eventsFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Kidux/diagnostics", isDirectory: true)
            .appendingPathComponent("events.jsonl")
    }

    static func recordLaunch() {
        Task(priority: .utility) {
            await DiagnosticsEventLogStore.shared.recordLaunch()
        }
    }

    static func record(
        _ event: String,
        durationMs: Double? = nil,
        fields: [String: String] = [:]
    ) {
        Task(priority: .utility) {
            await DiagnosticsEventLogStore.shared.record(event, durationMs: durationMs, fields: fields)
        }
    }

    static func snapshotEventsFile() async -> URL? {
        await DiagnosticsEventLogStore.shared.snapshotEventsFile()
    }
}

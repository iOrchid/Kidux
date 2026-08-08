import Foundation
import AppKit
import Observation

/// S21-02 / M15-F03 — 本机企业审计（安装/卸载/导入；不上报）
struct EnterpriseAuditEvent: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var timestamp: Date
    var action: String
    var detail: String
    var toolCount: Int
    var source: String

    static func make(
        action: String,
        detail: String,
        toolCount: Int = 0,
        source: String = "app"
    ) -> EnterpriseAuditEvent {
        EnterpriseAuditEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            action: action,
            detail: detail,
            toolCount: toolCount,
            source: source
        )
    }
}

@MainActor
@Observable
final class EnterpriseAuditStore {
    static let shared = EnterpriseAuditStore()

    private(set) var recent: [EnterpriseAuditEvent] = []
    private let maxInMemory = 200

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kidux/enterprise-audit.jsonl")
    }

    private init() { reloadRecent() }

    func record(_ event: EnterpriseAuditEvent) {
        appendLine(event)
        recent.insert(event, at: 0)
        if recent.count > maxInMemory {
            recent = Array(recent.prefix(maxInMemory))
        }
    }

    func record(
        action: String,
        detail: String,
        toolCount: Int = 0,
        source: String = "app"
    ) {
        record(.make(action: action, detail: detail, toolCount: toolCount, source: source))
    }

    func reloadRecent() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else {
            recent = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var events: [EnterpriseAuditEvent] = []
        for line in text.split(separator: "\n").reversed() {
            guard let lineData = String(line).data(using: .utf8),
                  let event = try? decoder.decode(EnterpriseAuditEvent.self, from: lineData)
            else { continue }
            events.append(event)
            if events.count >= maxInMemory { break }
        }
        recent = events
    }

    func exportCSVPanel() {
        reloadRecent()
        let formatter = ISO8601DateFormatter()
        var csv = "timestamp,action,detail,toolCount,source\n"
        for event in recent.reversed() {
            let detail = event.detail
                .replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            csv += "\(formatter.string(from: event.timestamp)),\(event.action),\"\(detail)\",\(event.toolCount),\(event.source)\n"
        }
        let panel = NSSavePanel()
        panel.title = "导出企业审计 CSV"
        panel.nameFieldStringValue = "Kidux-audit.csv"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = csv.data(using: .utf8)
        else { return }
        try? data.write(to: url, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clearAll() {
        recent = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func appendLine(_ event: EnterpriseAuditEvent) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(event) else { return }
        data.append(contentsOf: "\n".utf8)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL)
        {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

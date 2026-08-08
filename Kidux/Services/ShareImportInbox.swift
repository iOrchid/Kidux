import Foundation

/// S20-05 — Share Extension 与主 App 之间的待导入文件收件箱（App Group）
enum ShareImportInbox {
    static let appGroupID = "group.co.langem.kidux"
    static let pendingFileName = "pending-share-import.json"
    static let openURL = URL(string: "kidux://share/pending")!

    enum Kind: String, Codable, Sendable {
        case brewfile
        case snapshot
        case teamBundle
    }

    struct PendingImport: Codable, Sendable {
        let kind: Kind
        let fileName: String
        let createdAt: Date
        let utf8Text: String
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var pendingURL: URL? {
        containerURL?.appendingPathComponent(pendingFileName)
    }

    static func detectKind(fileName: String, content: String) -> Kind {
        let lower = fileName.lowercased()
        if lower.contains("brewfile") || lower.hasSuffix("brewfile") {
            return .brewfile
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if trimmed.contains("\"formatVersion\"")
                || trimmed.contains("\"selectedRoleIDs\"")
                || trimmed.contains("\"selectedToolIDs\"")
                || lower.contains("snapshot")
                || lower.contains(".kidux-snapshot")
            {
                return .snapshot
            }
            if trimmed.contains("\"tools\"")
                && (trimmed.contains("\"id\"") || trimmed.contains("\"ref\""))
            {
                return .teamBundle
            }
            return .snapshot
        }

        if content.contains("brew \"") || content.contains("cask \"") || content.contains("tap \"") {
            return .brewfile
        }
        return .brewfile
    }

    @discardableResult
    static func writePending(fileName: String, content: String) throws -> PendingImport {
        let kind = detectKind(fileName: fileName, content: content)
        let pending = PendingImport(
            kind: kind,
            fileName: fileName,
            createdAt: Date(),
            utf8Text: content
        )
        guard let url = pendingURL else {
            throw InboxError.appGroupUnavailable
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(pending)
        try data.write(to: url, options: .atomic)
        return pending
    }

    static func peek() -> PendingImport? {
        guard let url = pendingURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let pending = try? JSONDecoder().decode(PendingImport.self, from: data)
        else { return nil }
        return pending
    }

    static func consume() -> PendingImport? {
        guard let pending = peek(), let url = pendingURL else { return nil }
        try? FileManager.default.removeItem(at: url)
        return pending
    }

    enum InboxError: LocalizedError {
        case appGroupUnavailable

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                return "无法访问 App Group 收件箱"
            }
        }
    }
}

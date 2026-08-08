import Foundation

enum InstallHistorySource: String, Codable, Sendable {
    case bundle
    case discover
}

struct InstallHistoryEntry: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let date: Date
    let roleNames: [String]
    let toolCount: Int
    let summary: String
    let source: InstallHistorySource

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        roleNames: [String],
        toolCount: Int,
        summary: String,
        source: InstallHistorySource
    ) {
        self.id = id
        self.date = date
        self.roleNames = roleNames
        self.toolCount = toolCount
        self.summary = summary
        self.source = source
    }

    var roleLabel: String {
        if roleNames.isEmpty {
            return source == .discover ? "发现页" : "未指定岗位"
        }
        return roleNames.joined(separator: " · ")
    }

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

import Foundation

struct EnvironmentSnapshot: Codable {
    var formatVersion: Int
    let kiduxVersion: String
    let exportedAt: Date
    let selectedRoleIDs: [String]
    let selectedToolIDs: [String]
    let brewMirror: String
    let enableMAS: Bool
    let skipInstalled: Bool
    let allowMultipleRoles: Bool
    let note: String?
    var teamName: String?
    var author: String?
    var discoverSelectedToolIDs: [String]?
    var machineState: MachineEnvironmentState?

    static let fileExtension = "kidux-snapshot.json"
}

struct MachineEnvironmentState: Codable {
    let brewFormulae: [String]
    let brewCasks: [String]
    let gitName: String?
    let gitEmail: String?
    let runtimeVersions: [String: String]
    let capturedAt: Date
    let masAppIDs: [String]?
    let macOSDefaults: [MacOSDefaultSnapshotEntry]?
    let shellSnapshot: ShellEnvironmentSnapshot?
}

struct MacOSDefaultSnapshotEntry: Codable {
    let domain: String
    let key: String
    let value: String
    let label: String
}

struct ShellEnvironmentSnapshot: Codable {
    let loginShell: String?
    let pathPreview: [String]
    let profileFilesPresent: [String]
}

enum SnapshotCodec {
    static func encode(_ snapshot: EnvironmentSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(from data: Data) throws -> EnvironmentSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EnvironmentSnapshot.self, from: data)
    }

    static func load(from url: URL) throws -> EnvironmentSnapshot {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }

    static func summary(for snapshot: EnvironmentSnapshot) -> String {
        var lines: [String] = []
        lines.append("格式版本: v\(snapshot.formatVersion)")
        lines.append("Kidux: \(snapshot.kiduxVersion)")
        lines.append("导出时间: \(ISO8601DateFormatter().string(from: snapshot.exportedAt))")
        lines.append("岗位: \(snapshot.selectedRoleIDs.joined(separator: ", ").nilIfEmpty ?? "—")")
        lines.append("工具: \(snapshot.selectedToolIDs.count) 项")
        lines.append("镜像: \(snapshot.brewMirror) · MAS: \(snapshot.enableMAS ? "开" : "关")")
        if let note = snapshot.note?.nilIfEmpty {
            lines.append("备注: \(note)")
        }
        if let machine = snapshot.machineState {
            lines.append("本机 brew formula: \(machine.brewFormulae.count)")
            lines.append("本机 brew cask: \(machine.brewCasks.count)")
            if let mas = machine.masAppIDs {
                lines.append("MAS App: \(mas.count)")
            }
            if let gitName = machine.gitName, let gitEmail = machine.gitEmail {
                lines.append("Git: \(gitName) <\(gitEmail)>")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

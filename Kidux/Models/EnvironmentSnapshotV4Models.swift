import Foundation

struct MacOSDefaultSnapshotEntry: Codable, Sendable, Equatable, Hashable {
    let domain: String
    let key: String
    let value: String
    let label: String

    var compositeKey: String { "\(domain)::\(key)" }
}

struct ShellEnvironmentSnapshot: Codable, Sendable, Equatable {
    let loginShell: String?
    let pathPreview: [String]
    let profileFilesPresent: [String]
}

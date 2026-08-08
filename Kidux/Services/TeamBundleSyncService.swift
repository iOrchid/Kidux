import Foundation

/// S18-10 / S18-11 — 团队配置码（本机短码 + JSON；v2 平滑升级）
struct TeamBundlePayload: Codable, Sendable, Equatable {
    var format: String
    var teamCode: String
    var teamId: String
    var teamName: String
    var author: String
    var roles: [String]
    var selectedTools: [String]
    var discoverToolIDs: [String]
    var version: Int
    var createdAt: Date
    /// v2+
    var notes: String?
    var preferredBrewMirror: String?
    var skipInstalled: Bool?

    static let currentFormat = "kidux.team-bundle"
    static let currentVersion = 2
    static let minSupportedVersion = 1

    enum CodingKeys: String, CodingKey {
        case format, teamCode, teamId, teamName, author, roles, selectedTools
        case discoverToolIDs, version, createdAt, notes, preferredBrewMirror, skipInstalled
    }

    init(
        format: String = currentFormat,
        teamCode: String,
        teamId: String,
        teamName: String,
        author: String,
        roles: [String],
        selectedTools: [String],
        discoverToolIDs: [String],
        version: Int = currentVersion,
        createdAt: Date = Date(),
        notes: String? = nil,
        preferredBrewMirror: String? = nil,
        skipInstalled: Bool? = nil
    ) {
        self.format = format
        self.teamCode = teamCode
        self.teamId = teamId
        self.teamName = teamName
        self.author = author
        self.roles = roles
        self.selectedTools = selectedTools
        self.discoverToolIDs = discoverToolIDs
        self.version = version
        self.createdAt = createdAt
        self.notes = notes
        self.preferredBrewMirror = preferredBrewMirror
        self.skipInstalled = skipInstalled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? TeamBundlePayload.currentFormat
        teamCode = try c.decode(String.self, forKey: .teamCode)
        teamId = try c.decodeIfPresent(String.self, forKey: .teamId) ?? "team_unknown"
        teamName = try c.decodeIfPresent(String.self, forKey: .teamName) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        roles = try c.decodeIfPresent([String].self, forKey: .roles) ?? []
        selectedTools = try c.decodeIfPresent([String].self, forKey: .selectedTools) ?? []
        discoverToolIDs = try c.decodeIfPresent([String].self, forKey: .discoverToolIDs) ?? []
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        preferredBrewMirror = try c.decodeIfPresent(String.self, forKey: .preferredBrewMirror)
        skipInstalled = try c.decodeIfPresent(Bool.self, forKey: .skipInstalled)
    }
}

struct TeamBundleImportResult: Sendable {
    let payload: TeamBundlePayload
    let upgradedFrom: Int?
    let newerThanApp: Bool
    var statusLine: String {
        var parts = ["v\(payload.version)"]
        if let from = upgradedFrom {
            parts.append("已从 v\(from) 升级")
        }
        if newerThanApp {
            parts.append("配置版本新于本机，已尽力兼容")
        }
        return parts.joined(separator: " · ")
    }
}

enum TeamBundleSyncService {
    static let scheme = "kidux"

    enum SyncError: LocalizedError {
        case invalidCode
        case notFound
        case encodingFailed
        case decodingFailed
        case emptySelection
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .invalidCode: return "团队码格式无效（应为 TEAM-XXXXXXXX）"
            case .notFound: return "本机找不到该团队码，请让 Leader 导出 JSON 或通过 AirDrop 发送配置文件"
            case .encodingFailed: return "团队配置编码失败"
            case .decodingFailed: return "无法解析团队配置 JSON"
            case .emptySelection: return "请先选择岗位或工具后再生成团队码"
            case .unsupportedVersion(let v): return "团队配置版本 v\(v) 过旧，最低支持 v\(TeamBundlePayload.minSupportedVersion)"
            }
        }
    }

    private static var sharedDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kidux/team-shares", isDirectory: true)
    }

    @MainActor
    static func createShare(from viewModel: AppViewModel) throws -> (code: String, link: String, payload: TeamBundlePayload) {
        let roles = Array(viewModel.selectedRoles).sorted()
        let tools = viewModel.resolvedTools.filter(\.isSelected).map(\.id).sorted()
        let discover = Array(viewModel.discoverSelectedTools).sorted()
        guard !roles.isEmpty || !tools.isEmpty || !discover.isEmpty else {
            throw SyncError.emptySelection
        }

        let code = makeTeamCode()
        let payload = TeamBundlePayload(
            teamCode: code,
            teamId: "team_\(code.lowercased().replacingOccurrences(of: "team-", with: ""))",
            teamName: viewModel.settings.teamBundleName,
            author: viewModel.settings.teamBundleAuthor,
            roles: roles,
            selectedTools: tools,
            discoverToolIDs: discover,
            version: TeamBundlePayload.currentVersion,
            notes: nil,
            preferredBrewMirror: viewModel.settings.brewMirror.rawValue,
            skipInstalled: viewModel.settings.skipInstalled
        )

        try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        let data = try encode(payload)
        try data.write(to: fileURL(for: code), options: .atomic)
        pruneOldShares(keeping: 40)

        let link = "\(scheme)://team/\(code)"
        return (code, link, payload)
    }

    static func load(code raw: String) throws -> TeamBundleImportResult {
        let code = normalizeCode(raw)
        guard isValidCode(code) else { throw SyncError.invalidCode }
        let url = fileURL(for: code)
        guard FileManager.default.fileExists(atPath: url.path) else { throw SyncError.notFound }
        let data = try Data(contentsOf: url)
        return try importResult(from: data)
    }

    static func importResult(from data: Data) throws -> TeamBundleImportResult {
        let raw = try decode(from: data)
        return migrate(raw)
    }

    /// S18-11 — 将旧版 payload 平滑升级到当前版本
    static func migrate(_ payload: TeamBundlePayload) -> TeamBundleImportResult {
        var p = payload
        let original = p.version
        var upgradedFrom: Int?

        if p.version < TeamBundlePayload.minSupportedVersion {
            // still try to apply but mark
            upgradedFrom = p.version
        }

        if p.version < TeamBundlePayload.currentVersion {
            upgradedFrom = p.version
            if p.version < 2 {
                // v1 → v2：补齐可选字段默认值
                if p.preferredBrewMirror == nil { p.preferredBrewMirror = BrewMirror.official.rawValue }
                if p.skipInstalled == nil { p.skipInstalled = true }
            }
            p.version = TeamBundlePayload.currentVersion
            p.format = TeamBundlePayload.currentFormat
        }

        let newer = original > TeamBundlePayload.currentVersion
        if newer {
            // 未知新字段已在 decode 时忽略；降级为 current 标记便于 UI
            p.version = TeamBundlePayload.currentVersion
        }

        return TeamBundleImportResult(
            payload: p,
            upgradedFrom: upgradedFrom,
            newerThanApp: newer
        )
    }

    static func decode(from data: Data) throws -> TeamBundlePayload {
        if let direct = try? JSONDecoder.iso8601.decode(TeamBundlePayload.self, from: data),
           direct.format == TeamBundlePayload.currentFormat
            || direct.format.isEmpty
            || direct.teamCode.uppercased().hasPrefix("TEAM-")
        {
            return direct
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let nested = obj["teamBundle"],
           let nestedData = try? JSONSerialization.data(withJSONObject: nested),
           let payload = try? JSONDecoder.iso8601.decode(TeamBundlePayload.self, from: nestedData)
        {
            return payload
        }
        throw SyncError.decodingFailed
    }

    static func encode(_ payload: TeamBundlePayload) throws -> Data {
        let encoder = JSONEncoder.iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func jsonString(_ payload: TeamBundlePayload) throws -> String {
        let data = try encode(payload)
        guard let text = String(data: data, encoding: .utf8) else { throw SyncError.encodingFailed }
        return text
    }

    static func parseIncomingURL(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        if url.host?.lowercased() == "team" {
            let code = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let normalized = normalizeCode(code.isEmpty ? (url.host ?? "") : code)
            return isValidCode(normalized) ? normalized : nil
        }
        if let host = url.host, isValidCode(normalizeCode(host)) {
            return normalizeCode(host)
        }
        return nil
    }

    static func normalizeCode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("TEAM-") { return trimmed }
        if trimmed.hasPrefix("TEAM") && trimmed.count > 4 {
            let rest = trimmed.dropFirst(4).filter { $0.isLetter || $0.isNumber }
            return "TEAM-\(rest)"
        }
        let alnum = trimmed.filter { $0.isLetter || $0.isNumber }
        if alnum.count >= 6 { return "TEAM-\(alnum)" }
        return trimmed
    }

    static func isValidCode(_ code: String) -> Bool {
        let pattern = #"^TEAM-[A-Z0-9]{6,12}$"#
        return code.range(of: pattern, options: .regularExpression) != nil
    }

    private static func makeTeamCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var suffix = ""
        for _ in 0..<8 {
            suffix.append(alphabet.randomElement()!)
        }
        return "TEAM-\(suffix)"
    }

    private static func fileURL(for code: String) -> URL {
        sharedDirectory.appendingPathComponent("\(normalizeCode(code)).json")
    }

    private static func pruneOldShares(keeping: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: sharedDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = files.sorted {
            let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d0 > d1
        }
        for url in sorted.dropFirst(keeping) {
            try? fm.removeItem(at: url)
        }
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

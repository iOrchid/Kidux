import Foundation

/// S17-06 — OpenBoot 式快照分享链接（本地 token + 远程 URL 包装，v2.0 云端前置）
enum SnapshotShareService {
    static let scheme = "kidux"

    enum IncomingShare: Sendable {
        case localToken(String)
        case remoteImport(URL)
    }

    enum ShareError: LocalizedError {
        case invalidToken
        case snapshotMissing
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .invalidToken: return "分享码无效"
            case .snapshotMissing: return "分享快照不存在或已过期"
            case .invalidURL: return "Kidux 链接格式无效"
            }
        }
    }

    private static var sharedDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kidux/shared-snapshots", isDirectory: true)
    }

    @MainActor
    static func createLocalShareLink(from viewModel: AppViewModel) async throws -> String {
        let snapshot = await EnvironmentSnapshotService.makeFullSnapshot(from: viewModel)
        let token = makeToken()
        try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)

        let fileURL = sharedDirectory.appendingPathComponent("\(token).json")
        let data = try EnvironmentSnapshotService.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)

        pruneOldShares(keeping: 24)
        return "\(scheme)://snapshot/\(token)"
    }

    static func makeImportLink(forRemoteURL url: URL) -> String? {
        guard url.scheme?.hasPrefix("http") == true else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url?.absoluteString
    }

    static func parseIncomingURL(_ url: URL) -> IncomingShare? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        if url.host?.lowercased() == "import" {
            guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let raw = items.first(where: { $0.name == "url" })?.value,
                  let remote = URL(string: raw),
                  remote.scheme?.hasPrefix("http") == true
            else { return nil }
            return .remoteImport(remote)
        }

        let token = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if isValidToken(token) {
            return .localToken(token)
        }

        if let host = url.host, isValidToken(host) {
            return .localToken(host)
        }

        return nil
    }

    static func loadLocalSnapshot(token: String) throws -> EnvironmentSnapshot {
        guard isValidToken(token) else { throw ShareError.invalidToken }
        let fileURL = sharedDirectory.appendingPathComponent("\(token).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ShareError.snapshotMissing
        }
        let data = try Data(contentsOf: fileURL)
        return try EnvironmentSnapshotService.decode(from: data)
    }

    static func humanReadableHint(for link: String) -> String {
        if link.contains("://snapshot/") {
            return "已复制 Kidux 本地分享链接。同事在本机打开 Kidux 后粘贴到浏览器或运行 `open '\(link)'` 即可导入。"
        }
        return "已复制 Kidux 导入链接。接收方需安装 Kidux，打开链接即可从远程 JSON 导入 Bundle。"
    }

    private static func makeToken() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10)).lowercased()
    }

    private static func isValidToken(_ token: String) -> Bool {
        guard (6...32).contains(token.count) else { return false }
        return token.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func pruneOldShares(keeping limit: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sharedDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let sorted = files
            .filter { $0.pathExtension == "json" }
            .sorted {
                let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d0 > d1
            }

        for file in sorted.dropFirst(limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

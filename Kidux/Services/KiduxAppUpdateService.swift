import Foundation

struct AppReleaseInfo: Sendable, Equatable {
    let version: String
    let downloadURL: URL?
    let releaseNotes: String
    let publishedAt: String?
}

/// 检查 GitHub Release 是否有新版本 Kidux（Sparkle 之外的轻量备用方案）
enum KiduxAppUpdateService {
    static let releaseAPI = RepositoryConfig.latestReleaseAPIURL

    static func checkForUpdate(currentVersion: String = AppInfo.marketingVersion) async -> AppReleaseInfo? {
        if await MainActor.run(body: { AppSettings.shared.offlineMode }) {
            return nil
        }

        do {
            var request = URLRequest(url: releaseAPI)
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let tag = (json["tag_name"] as? String ?? json["name"] as? String ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard !tag.isEmpty, isNewerVersion(tag, than: currentVersion) else { return nil }

            let notes = json["body"] as? String ?? ""
            let published = json["created_at"] as? String
            let download = parseDownloadURL(from: json)

            return AppReleaseInfo(
                version: tag,
                downloadURL: download,
                releaseNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                publishedAt: published
            )
        } catch {
            return nil
        }
    }

    private static func parseDownloadURL(from json: [String: Any]) -> URL? {
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let urlString = asset["browser_download_url"] as? String,
                   urlString.lowercased().hasSuffix(".dmg"),
                   let url = URL(string: urlString) {
                    return url
                }
            }
            if let first = assets.first,
               let urlString = first["browser_download_url"] as? String,
               let url = URL(string: urlString) {
                return url
            }
        }
        if let html = json["html_url"] as? String, let url = URL(string: html) {
            return url
        }
        return RepositoryConfig.releasesURL
    }

    static func isNewerVersion(_ remote: String, than local: String) -> Bool {
        compareVersions(remote, local) == .orderedDescending
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = lhs.split(separator: ".").compactMap { Int($0) }
        let b = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(a.count, b.count, 3)
        for i in 0..<count {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av > bv ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }
}

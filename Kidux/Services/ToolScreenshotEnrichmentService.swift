import Foundation

/// S18-20 — 运行时从 Homebrew API 补全截图 / 长描述（离线模式跳过）
struct ToolScreenshotEnrichment: Sendable, Equatable {
    let screenshots: [String]
    let longDescription: String?
    let homepage: String?
}

actor ToolScreenshotEnrichmentService {
    static let shared = ToolScreenshotEnrichmentService()

    private var cache: [String: ToolScreenshotEnrichment] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    private var allowsRemote: Bool {
        !UserDefaults.standard.bool(forKey: "settings.offlineMode")
    }

    func enrich(tool: DevTool) async -> ToolScreenshotEnrichment {
        let key = "\(tool.source.type.rawValue):\(tool.source.identifier)"
        if let cached = cache[key] { return cached }

        // Catalog 已有截图时仍允许补全 homepage / desc
        var shots = tool.screenshots ?? []
        var longDesc = tool.longDescription
        var homepage = tool.homepage

        if allowsRemote, let remote = await fetchBrewMetadata(for: tool) {
            if shots.isEmpty { shots = remote.screenshots }
            if longDesc == nil || longDesc?.isEmpty == true { longDesc = remote.longDescription }
            if homepage == nil || homepage?.isEmpty == true { homepage = remote.homepage }
        }

        // GitHub README / social preview 启发式（无截图时）
        if shots.isEmpty, allowsRemote, let hp = homepage ?? tool.homepage {
            shots = githubOpenGraphCandidates(from: hp)
        }

        let result = ToolScreenshotEnrichment(
            screenshots: Array(shots.prefix(6)),
            longDescription: longDesc,
            homepage: homepage
        )
        cache[key] = result
        return result
    }

    private func fetchBrewMetadata(for tool: DevTool) async -> ToolScreenshotEnrichment? {
        let apiURL: URL?
        switch tool.source.type {
        case .formula:
            apiURL = URL(string: "https://formulae.brew.sh/api/formula/\(tool.source.identifier).json")
        case .cask:
            apiURL = URL(string: "https://formulae.brew.sh/api/cask/\(tool.source.identifier).json")
        default:
            return nil
        }
        guard let apiURL else { return nil }

        do {
            let (data, response) = try await session.data(from: apiURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }

            let homepage = json["homepage"] as? String
            let desc = (json["desc"] as? String) ?? (json["caveats"] as? String)
            var shots: [String] = []

            // cask 偶发带 screenshot URL；formula 通常没有 — 用 homepage OG
            if let urls = json["screenshots"] as? [String] {
                shots.append(contentsOf: urls)
            } else if let url = json["screenshot"] as? String {
                shots.append(url)
            }

            if shots.isEmpty, let homepage {
                shots = githubOpenGraphCandidates(from: homepage)
            }

            return ToolScreenshotEnrichment(
                screenshots: shots,
                longDescription: desc,
                homepage: homepage
            )
        } catch {
            return nil
        }
    }

    private func githubOpenGraphCandidates(from homepage: String) -> [String] {
        // https://github.com/owner/repo → opengraph image
        guard let url = URL(string: homepage),
              url.host?.contains("github.com") == true
        else { return [] }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return [] }
        let owner = parts[0]
        let repo = parts[1].replacingOccurrences(of: ".git", with: "")
        return [
            "https://opengraph.githubassets.com/1/\(owner)/\(repo)"
        ]
    }
}

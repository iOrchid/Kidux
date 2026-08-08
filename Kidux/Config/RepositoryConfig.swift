import Foundation

/// 本仓库对外地址的单一配置入口。
/// Fork 或自建远程时，优先修改此处的 `owner` / `name` / `defaultBranch`；
/// Apple Team ID 见同目录 `Signing.xcconfig`。
enum RepositoryConfig {
    /// GitHub 用户或组织名
    static let owner = "iOrchid"
    /// 仓库名
    static let name = "Kidux"
    /// 用于 raw 资源的默认分支
    static let defaultBranch = "main"

    // MARK: - 派生 URL

    static var homeURL: URL {
        URL(string: "https://github.com/\(owner)/\(name)")!
    }

    static var pagesURL: URL {
        URL(string: "https://\(owner.lowercased()).github.io/\(name)/")!
    }

    static var releasesURL: URL {
        URL(string: "https://github.com/\(owner)/\(name)/releases")!
    }

    static var latestReleaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases/latest")!
    }

    static var issuesURL: URL {
        URL(string: "https://github.com/\(owner)/\(name)/issues")!
    }

    static var discussionsURL: URL {
        URL(string: "https://github.com/\(owner)/\(name)/discussions")!
    }

    /// Sparkle appcast（对应仓库内 `bin/appcast.xml`）
    static var appcastFeedURL: URL {
        rawURL(path: "bin/appcast.xml")
    }

    /// AI 模型目录（对应仓库内 `data/ai-model-catalog.json`）
    static var aiModelCatalogURL: URL {
        rawURL(path: "data/ai-model-catalog.json")
    }

    /// Release 资源下载地址（写入 / 校验 `bin/appcast.xml` 时使用）
    static func releaseAssetURL(tag: String, fileName: String) -> URL {
        let normalized = tag.hasPrefix("v") ? tag : "v\(tag)"
        return URL(string: "https://github.com/\(owner)/\(name)/releases/download/\(normalized)/\(fileName)")!
    }

    static func rawURL(path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://raw.githubusercontent.com/\(owner)/\(name)/\(defaultBranch)/\(trimmed)")!
    }
}

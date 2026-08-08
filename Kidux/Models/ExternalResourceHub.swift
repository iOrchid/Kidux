import Foundation

/// 社区资源站：仅提供跳转与官方替代对照，不在应用内分发破解包。
struct ExternalResourceSite: Identifiable, Sendable {
    let id: String
    let name: String
    let url: String
    let description: String
    let tags: [String]
}

struct CommunityAppReference: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let communityNote: String
    let officialCatalogID: String?
    let officialName: String?
    let homepage: String?

    var hasOfficialAlternative: Bool { officialCatalogID != nil }
}

enum ExternalResourceHub {
    static let legalDisclaimer = """
    以下链接指向第三方社区网站，\(BrandInfo.displayNameCN)不会下载、托管或安装任何破解软件包。
    请自行承担版权与安全风险；我们优先推荐 Homebrew / App Store 等官方渠道。
    """

    static let sites: [ExternalResourceSite] = [
        ExternalResourceSite(
            id: "indiegoodies-oss",
            name: "Indie Goodies · 开源 Mac",
            url: "https://indiegoodies.com/awesome-open-source-mac-apps",
            description: "111+ 开源 macOS 应用精选，可按标签浏览",
            tags: ["开源", "清单"]
        ),
        ExternalResourceSite(
            id: "awesome-mac",
            name: "awesome-mac",
            url: "https://github.com/jaywcjlove/awesome-mac",
            description: "GitHub 上最全的 Mac 软件清单（开源）",
            tags: ["开源", "清单"]
        ),
        ExternalResourceSite(
            id: "oss-mac-apps",
            name: "open-source-mac-os-apps",
            url: "https://github.com/serhii-londar/open-source-mac-os-apps",
            description: "开源 macOS 应用合集，\(BrandInfo.displayNameCN) 目录的重要参考",
            tags: ["开源", "清单"]
        ),
        ExternalResourceSite(
            id: "xclient",
            name: "Xclient",
            url: "https://xclient.info/s/",
            description: "精品 Mac 应用分享社区，可作为软件发现参考",
            tags: ["社区", "参考"]
        ),
        ExternalResourceSite(
            id: "insmac",
            name: "InsMac",
            url: "https://insmac.org/",
            description: "macOS 软件与游戏下载社区，仅作发现参考",
            tags: ["社区", "参考"]
        ),
        ExternalResourceSite(
            id: "appstorrent",
            name: "AppStorrent",
            url: "https://www.appstorrent.ru/",
            description: "第三方 Mac 软件资讯站，请自行承担版权风险",
            tags: ["社区", "参考"]
        ),
        ExternalResourceSite(
            id: "macappbox",
            name: "Mac软件盒子",
            url: "https://www.macappbox.com/",
            description: "Mac 软件下载社区，仅跳转外链，不提供一键安装",
            tags: ["社区", "参考"]
        ),
        ExternalResourceSite(
            id: "haxmac",
            name: "HaxMac",
            url: "https://haxmac.cc/",
            description: "Mac 软件资讯与分享站",
            tags: ["社区", "参考"]
        ),
        ExternalResourceSite(
            id: "macwk",
            name: "MacWK",
            url: "https://www.macwk.com/",
            description: "Mac 软件下载与教程社区",
            tags: ["社区", "参考"]
        )
    ]

    static func loadReferences() -> [CommunityAppReference] {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "community-references", withExtension: "json"),
            Bundle.main.url(forResource: "community-references", withExtension: "json", subdirectory: "bundles"),
            Bundle.main.url(forResource: "community-references", withExtension: "json", subdirectory: "Resources/bundles")
        ]
        guard let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: url)
        else { return fallbackReferences }

        struct Payload: Codable { let references: [CommunityAppReference] }
        return (try? JSONDecoder().decode(Payload.self, from: data).references) ?? fallbackReferences
    }

    private static let fallbackReferences: [CommunityAppReference] = [
        CommunityAppReference(
            id: "bettertouchtool",
            name: "BetterTouchTool",
            communityNote: "xclient 热门效率工具",
            officialCatalogID: "bettertouchtool",
            officialName: "BetterTouchTool",
            homepage: "https://folivora.ai/"
        ),
        CommunityAppReference(
            id: "typora",
            name: "Typora",
            communityNote: "Markdown 编辑器",
            officialCatalogID: "typora",
            officialName: "Typora",
            homepage: "https://typora.io/"
        ),
        CommunityAppReference(
            id: "cleanshot-x",
            name: "CleanShot X",
            communityNote: "截图标注工具",
            officialCatalogID: "cleanshot",
            officialName: "CleanShot X",
            homepage: "https://cleanshot.com/"
        ),
        CommunityAppReference(
            id: "parallels",
            name: "Parallels Desktop",
            communityNote: "虚拟机",
            officialCatalogID: "parallels",
            officialName: "Parallels Desktop",
            homepage: "https://www.parallels.com/"
        )
    ]
}

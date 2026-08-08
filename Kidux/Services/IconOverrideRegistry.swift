import Foundation

/// 内置常用软件图标 URL 覆盖（避免 GitHub 域名误匹配章鱼猫等）
enum IconOverrideRegistry {
    private static let overrides: [String: String] = load()

    static func url(for tool: DevTool) -> String? {
        if let hit = overrides[tool.id] { return hit }
        if let hit = overrides[tool.source.identifier] { return hit }
        return nil
    }

    private static func load() -> [String: String] {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "icon-overrides", withExtension: "json"),
            Bundle.main.url(forResource: "icon-overrides", withExtension: "json", subdirectory: "Resources"),
            devResourceURL()
        ]
        for url in candidates.compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            return map
        }
        return [:]
    }

    private static func devResourceURL() -> URL? {
        let devRoot = Bundle.main.bundlePath
            .replacingOccurrences(of: "/Build/Products/Debug/Kidux.app", with: "")
        let path = devRoot + "/Kidux/Resources/icon-overrides.json"
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
}

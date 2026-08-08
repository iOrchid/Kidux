import Foundation

extension DevTool {
    /// 卡片主按钮短文案（对齐 App Store「获取」，避免长命令被截断）
    func installActionTitle(installState: ToolInstallState) -> String {
        if installState == .installed { return "已安装" }
        switch source.type {
        case .link: return "下载"
        case .mas: return "获取"
        case .script: return "安装"
        case .formula, .cask: return "获取"
        }
    }

    /// 详情页等可用的完整动作说明
    func installActionDetailTitle(installState: ToolInstallState) -> String {
        if installState == .installed { return "已安装" }
        switch source.type {
        case .link: return "打开下载页"
        case .mas: return "从 App Store 获取"
        case .script: return "运行安装脚本"
        case .formula: return "brew install"
        case .cask: return "brew install --cask"
        }
    }

    var installMethodLabel: String {
        switch source.type {
        case .formula: return "Homebrew Formula（命令行）"
        case .cask: return "Homebrew Cask（图形应用）"
        case .mas: return "Mac App Store（mas-cli）"
        case .script: return "内置安装脚本"
        case .link: return "官网手动下载安装"
        }
    }

    func matchesDiscoverSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = [
            name,
            description,
            longDescription ?? "",
            id,
            tags?.joined(separator: " ") ?? ""
        ].joined(separator: " ").lowercased()
        return haystack.contains(query)
    }

    /// 从 homepage 解析 GitHub 仓库链接（用于详情页）
    var githubRepositoryURL: URL? {
        guard let homepage else { return nil }
        let trimmed = homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("github.com") else { return nil }
        guard var components = URLComponents(string: trimmed) else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        components.path = "/\(parts[0])/\(parts[1])"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

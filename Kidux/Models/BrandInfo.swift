import Foundation

/// 产品品牌：用户可见名「启椟」；工程/脚本标识仍可用 Kidux
enum BrandInfo {
    static let displayNameCN = "启椟"
    static let displayNameEN = "Kidux"
    static var tagline: String { String(localized: "brand.tagline") }
    static let assistantName = "启椟助手"
    /// 脚本 / Brewfile / 日志等生成物署名（保持 ASCII）
    static let generatedBy = "Kidux"

    /// 用户可见全称（Mac 菜单栏 / 关于 / 首页）
    static var fullTitle: String { displayNameCN }

    /// 窗口标题栏
    static var windowTitle: String { displayNameCN }

    static var menuBarTitle: String { displayNameCN }
}

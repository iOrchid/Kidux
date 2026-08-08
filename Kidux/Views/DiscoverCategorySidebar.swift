import SwiftUI

/// 分类芯片数据源（横向筛选用）。侧栏布局已弃用，保留分区定义供 chips / 测试复用。
enum DiscoverCategorySections {
    static let groups: [(String, [ToolCategory])] = [
        (String(localized: "ui.DiscoverCategorySidebar.9c5c5cdbc5"), [.all]),
        (String(localized: "ui.DiscoverCategorySidebar.3ff3c3e26a"), [.infra, .terminal, .editor, .language, .devops, .database]),
        (String(localized: "ui.DiscoverCategorySidebar.db53804b7d"), [.browser, .collab, .product]),
        (String(localized: "ui.DiscoverCategorySidebar.c9efa01290"), [.design, .media]),
        (String(localized: "ui.DiscoverCategorySidebar.8a8b895fcc"), [.utility, .security])
    ]

    static var allCategories: [ToolCategory] {
        ToolCategory.allCases
    }
}

import Foundation

struct BrewSearchResult: Identifiable, Sendable, Hashable {
    let name: String
    let sourceType: InstallSourceType

    var id: String { "\(sourceType.rawValue):\(name)" }

    var asDevTool: DevTool {
        DevTool(
            id: "brew-live:\(id)",
            name: name,
            description: sourceType == .formula ? "Homebrew Formula" : "Homebrew Cask",
            category: "brew-live",
            kind: sourceType == .formula ? .cli : .gui,
            source: InstallSource(type: sourceType, identifier: name),
            priority: 100
        )
    }
}

enum DiscoverCatalogMode: String, CaseIterable, Identifiable, Sendable {
    case builtin
    case homebrew

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtin: return String(localized: "discover.mode.builtin")
        case .homebrew: return String(localized: "discover.mode.homebrew")
        }
    }
}

enum DiscoverSourceFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case installable
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部来源"
        case .installable: return "可一键安装"
        case .manual: return "手动安装"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: return "全部"
        case .installable: return "可安装"
        case .manual: return "手动"
        }
    }
}

enum DiscoverScopeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case popular
    case role

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .popular: return "精选热门"
        case .role: return "岗位推荐"
        }
    }
}

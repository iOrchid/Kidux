import Foundation

enum ToolInstallState: Sendable, Equatable {
    case unknown
    case installed
    case notInstalled
    case skippedBySetting
}

struct InstalledStatusSnapshot: Sendable {
    var formulae: Set<String> = []
    var casks: Set<String> = []
    var masApps: Set<String> = []
    var scannedAt: Date?

    func state(for tool: DevTool) -> ToolInstallState {
        switch tool.source.type {
        case .formula:
            return formulae.contains(tool.source.identifier) ? .installed : .notInstalled
        case .cask:
            return casks.contains(tool.source.identifier) ? .installed : .notInstalled
        case .mas:
            return masApps.contains(tool.source.identifier) ? .installed : .notInstalled
        case .script:
            return .unknown
        case .link:
            return .unknown
        }
    }
}

actor InstalledStatusScanner {
    private let homebrew = HomebrewService()
    private let mas = MASService()

    func scan(enableMAS: Bool) async -> InstalledStatusSnapshot {
        var snapshot = InstalledStatusSnapshot()
        snapshot.scannedAt = Date()

        if await homebrew.isInstalled() {
            snapshot.formulae = (try? await homebrew.listFormulae()) ?? []
            snapshot.casks = (try? await homebrew.listCasks()) ?? []
        }

        if enableMAS, await mas.isAvailable() {
            snapshot.masApps = (try? await mas.listInstalledAppIDs()) ?? []
        }

        return snapshot
    }
}

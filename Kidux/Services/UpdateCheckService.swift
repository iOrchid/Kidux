import Foundation

struct OutdatedBrewItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let sourceType: InstallSourceType
    var catalogTool: DevTool?

    var displayName: String { catalogTool?.name ?? name }
}

struct OutdatedMASItem: Identifiable, Sendable, Hashable {
    let id: String
    let appID: String
    let name: String
    var catalogTool: DevTool?

    var displayName: String { catalogTool?.name ?? name }
}

enum OutdatedEntry: Identifiable, Sendable, Hashable {
    case brew(OutdatedBrewItem)
    case mas(OutdatedMASItem)

    var id: String {
        switch self {
        case .brew(let item): return item.id
        case .mas(let item): return item.id
        }
    }

    var displayName: String {
        switch self {
        case .brew(let item): return item.displayName
        case .mas(let item): return item.displayName
        }
    }

    var sourceLabel: String {
        switch self {
        case .brew(let item):
            return item.sourceType == .cask ? "brew cask" : "brew formula"
        case .mas:
            return "App Store (mas)"
        }
    }
}

struct OutdatedScanResult: Sendable {
    let formulae: [OutdatedBrewItem]
    let casks: [OutdatedBrewItem]
    let masApps: [OutdatedMASItem]
    let scannedAt: Date

    var allBrew: [OutdatedBrewItem] { formulae + casks }
    var allEntries: [OutdatedEntry] {
        allBrew.map { .brew($0) } + masApps.map { .mas($0) }
    }

    var count: Int { allEntries.count }
}

struct OutdatedScanResponse: Sendable {
    let result: OutdatedScanResult
    let timedOut: Bool
}

enum UpdateCheckService {
    private static let brew = HomebrewService()
    private static let mas = MASService()
    private static let timeoutSeconds: TimeInterval = 45
    private static let scanShell = ShellExecutor()

    static func scanOutdated(
        catalog: [String: DevTool],
        mirror: BrewMirror,
        enableMAS: Bool
    ) async -> OutdatedScanResponse {
        let brewService = HomebrewService(shell: scanShell)
        let masService = MASService(shell: scanShell)

        async let brewOutdated = withTimeout(seconds: timeoutSeconds, shell: scanShell) {
            await brewService.listOutdated(mirror: mirror)
        }

        let brewTimedOut = await brewOutdated == nil
        let outdated = await brewOutdated ?? HomebrewService.OutdatedPackages(formulae: [], casks: [])
        var masItems: [OutdatedMASItem] = []
        var masTimedOut = false
        if enableMAS, await masService.isAvailable() {
            let masOutdated = await withTimeout(seconds: timeoutSeconds, shell: scanShell) {
                await masService.listOutdated()
            }
            if masOutdated == nil {
                masTimedOut = true
            } else {
                masItems = masOutdated!.map { mapMASItem($0, catalog: catalog) }
            }
        }

        let formulae = outdated.formulae.map { mapBrewItem($0, type: .formula, catalog: catalog) }
        let casks = outdated.casks.map { mapBrewItem($0, type: .cask, catalog: catalog) }
        return OutdatedScanResponse(
            result: OutdatedScanResult(
                formulae: formulae,
                casks: casks,
                masApps: masItems,
                scannedAt: Date()
            ),
            timedOut: brewTimedOut || masTimedOut
        )
    }

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        shell: ShellExecutor,
        operation: @Sendable @escaping () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            defer { group.cancelAll() }
            while let next = await group.next() {
                if let value = next {
                    return value
                }
                // S22-14 — 超时显式杀 brew/mas 子进程
                await shell.cancelActive()
                return nil
            }
            return nil
        }
    }

    static func upgrade(
        entry: OutdatedEntry,
        mirror: BrewMirror,
        shell: ShellExecutor,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let brew = HomebrewService(shell: shell)
        let mas = MASService(shell: shell)
        switch entry {
        case .brew(let item):
            return try await brew.upgrade(
                name: item.name,
                type: item.sourceType,
                mirror: mirror,
                onOutput: onOutput
            )
        case .mas(let item):
            return try await mas.upgrade(appID: item.appID, onOutput: onOutput)
        }
    }

    static func upgrade(
        item: OutdatedBrewItem,
        mirror: BrewMirror,
        shell: ShellExecutor,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await upgrade(entry: .brew(item), mirror: mirror, shell: shell, onOutput: onOutput)
    }

    static func uninstall(
        tool: DevTool,
        mirror: BrewMirror,
        shell: ShellExecutor? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let brew = HomebrewService(shell: shell ?? ShellExecutor())
        return try await brew.uninstall(
            name: tool.source.identifier,
            type: tool.source.type,
            mirror: mirror,
            onOutput: onOutput
        )
    }

    private static func mapBrewItem(
        _ name: String,
        type: InstallSourceType,
        catalog: [String: DevTool]
    ) -> OutdatedBrewItem {
        let tool = catalog.values.first { $0.source.type == type && $0.source.identifier == name }
        return OutdatedBrewItem(id: "\(type.rawValue)-\(name)", name: name, sourceType: type, catalogTool: tool)
    }

    private static func mapMASItem(_ app: MASService.OutdatedApp, catalog: [String: DevTool]) -> OutdatedMASItem {
        let tool = catalog.values.first { $0.source.type == .mas && $0.source.identifier == app.appID }
        return OutdatedMASItem(
            id: "mas-\(app.appID)",
            appID: app.appID,
            name: app.name,
            catalogTool: tool
        )
    }
}

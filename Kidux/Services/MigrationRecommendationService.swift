import Foundation

/// S18-19 — 根据旧机快照 / 漂移差异，推荐新机应补齐的 Catalog 软件
enum MigrationRecommendationKind: String, Sendable, Codable {
    case driftMissing
    case snapshotSelected
    case discoverSelected

    var displayReason: String {
        switch self {
        case .driftMissing: return "旧机已装，本机缺失"
        case .snapshotSelected: return "快照清单已勾选"
        case .discoverSelected: return "旧机发现页勾选"
        }
    }

    var priority: Int {
        switch self {
        case .driftMissing: return 1
        case .snapshotSelected: return 2
        case .discoverSelected: return 3
        }
    }
}

struct MigrationRecommendation: Identifiable, Sendable, Equatable, Hashable {
    var id: String { toolID }
    let toolID: String
    let toolName: String
    let kind: MigrationRecommendationKind
    let detail: String?

    var reason: String {
        if let detail, !detail.isEmpty {
            return "\(kind.displayReason) · \(detail)"
        }
        return kind.displayReason
    }
}

enum MigrationRecommendationService {
    static func recommend(
        snapshot: EnvironmentSnapshot?,
        driftReport: EnvironmentDriftReport?,
        catalog: [DevTool],
        installed: InstalledStatusSnapshot?
    ) -> [MigrationRecommendation] {
        var byID: [String: MigrationRecommendation] = [:]
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })

        if let report = driftReport {
            let plan = EnvironmentDriftService.suggestFixes(from: report)
            let matched = BrewfileImporter.matchTools(
                formulae: plan.missingFormulae,
                casks: plan.missingCasks,
                catalog: catalog
            )
            for tool in matched.matchedTools {
                guard !isInstalled(tool, in: installed) else { continue }
                upsert(
                    MigrationRecommendation(
                        toolID: tool.id,
                        toolName: tool.name,
                        kind: .driftMissing,
                        detail: tool.source.identifier
                    ),
                    into: &byID
                )
            }
        }

        if let snapshot {
            for toolID in snapshot.selectedToolIDs {
                guard let tool = catalogByID[toolID] else { continue }
                guard !isInstalled(tool, in: installed) else { continue }
                upsert(
                    MigrationRecommendation(
                        toolID: tool.id,
                        toolName: tool.name,
                        kind: .snapshotSelected,
                        detail: nil
                    ),
                    into: &byID
                )
            }

            for toolID in snapshot.discoverSelectedToolIDs ?? [] {
                guard let tool = catalogByID[toolID] else { continue }
                guard !isInstalled(tool, in: installed) else { continue }
                upsert(
                    MigrationRecommendation(
                        toolID: tool.id,
                        toolName: tool.name,
                        kind: .discoverSelected,
                        detail: nil
                    ),
                    into: &byID
                )
            }
        }

        return byID.values.sorted {
            if $0.kind.priority != $1.kind.priority {
                return $0.kind.priority < $1.kind.priority
            }
            return $0.toolName.localizedCaseInsensitiveCompare($1.toolName) == .orderedAscending
        }
    }

    private static func isInstalled(_ tool: DevTool, in snapshot: InstalledStatusSnapshot?) -> Bool {
        guard let snapshot else { return false }
        return snapshot.state(for: tool) == .installed
    }

    private static func upsert(_ item: MigrationRecommendation, into map: inout [String: MigrationRecommendation]) {
        if let existing = map[item.toolID], existing.kind.priority <= item.kind.priority {
            return
        }
        map[item.toolID] = item
    }
}

import Foundation

/// 环境快照 / 团队 Bundle：换机、团队复刻（参考 OpenBoot snapshot 思路）
struct EnvironmentSnapshot: Codable, Sendable {
    /// 1 = 初版；2 = 含团队字段与发现页勾选；3 = 含本机 brew/git/运行时；4 = + MAS/defaults/shell
    var formatVersion: Int = 4
    let kiduxVersion: String
    let exportedAt: Date
    let selectedRoleIDs: [String]
    let selectedToolIDs: [String]
    let brewMirror: String
    let enableMAS: Bool
    let skipInstalled: Bool
    let allowMultipleRoles: Bool
    let note: String?
    var teamName: String?
    var author: String?
    var discoverSelectedToolIDs: [String]?
    var machineState: MachineEnvironmentState?

    static let fileExtension = "kidux-snapshot.json"

    init(
        formatVersion: Int = 4,
        kiduxVersion: String,
        exportedAt: Date,
        selectedRoleIDs: [String],
        selectedToolIDs: [String],
        brewMirror: String,
        enableMAS: Bool,
        skipInstalled: Bool,
        allowMultipleRoles: Bool,
        note: String?,
        teamName: String? = nil,
        author: String? = nil,
        discoverSelectedToolIDs: [String]? = nil,
        machineState: MachineEnvironmentState? = nil
    ) {
        self.formatVersion = formatVersion
        self.kiduxVersion = kiduxVersion
        self.exportedAt = exportedAt
        self.selectedRoleIDs = selectedRoleIDs
        self.selectedToolIDs = selectedToolIDs
        self.brewMirror = brewMirror
        self.enableMAS = enableMAS
        self.skipInstalled = skipInstalled
        self.allowMultipleRoles = allowMultipleRoles
        self.note = note
        self.teamName = teamName
        self.author = author
        self.discoverSelectedToolIDs = discoverSelectedToolIDs
        self.machineState = machineState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        kiduxVersion = try container.decode(String.self, forKey: .kiduxVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        selectedRoleIDs = try container.decode([String].self, forKey: .selectedRoleIDs)
        selectedToolIDs = try container.decode([String].self, forKey: .selectedToolIDs)
        brewMirror = try container.decode(String.self, forKey: .brewMirror)
        enableMAS = try container.decode(Bool.self, forKey: .enableMAS)
        skipInstalled = try container.decode(Bool.self, forKey: .skipInstalled)
        allowMultipleRoles = try container.decode(Bool.self, forKey: .allowMultipleRoles)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        discoverSelectedToolIDs = try container.decodeIfPresent([String].self, forKey: .discoverSelectedToolIDs)
        machineState = try container.decodeIfPresent(MachineEnvironmentState.self, forKey: .machineState)
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, kiduxVersion, exportedAt, selectedRoleIDs, selectedToolIDs
        case brewMirror, enableMAS, skipInstalled, allowMultipleRoles, note
        case teamName, author, discoverSelectedToolIDs, machineState
    }
}

enum EnvironmentSnapshotService {
    @MainActor
    static func makeSnapshot(
        from viewModel: AppViewModel,
        note: String? = nil,
        teamName: String? = nil,
        author: String? = nil,
        machineState: MachineEnvironmentState? = nil
    ) -> EnvironmentSnapshot {
        EnvironmentSnapshot(
            formatVersion: 4,
            kiduxVersion: AppInfo.marketingVersion,
            exportedAt: Date(),
            selectedRoleIDs: Array(viewModel.selectedRoles).sorted(),
            selectedToolIDs: viewModel.resolvedTools.filter(\.isSelected).map(\.id).sorted(),
            brewMirror: viewModel.settings.brewMirror.rawValue,
            enableMAS: viewModel.settings.enableMAS,
            skipInstalled: viewModel.settings.skipInstalled,
            allowMultipleRoles: viewModel.settings.allowMultipleRoles,
            note: note,
            teamName: teamName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            author: author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            discoverSelectedToolIDs: Array(viewModel.discoverSelectedTools).sorted(),
            machineState: machineState
        )
    }

    @MainActor
    static func makeFullSnapshot(from viewModel: AppViewModel) async -> EnvironmentSnapshot {
        let machine = await EnvironmentDriftService.captureCurrent(mirror: viewModel.settings.brewMirror)
        return makeSnapshot(
            from: viewModel,
            teamName: viewModel.settings.teamBundleName,
            author: viewModel.settings.teamBundleAuthor,
            machineState: machine
        )
    }

    static func encode(_ snapshot: EnvironmentSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(from data: Data) throws -> EnvironmentSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EnvironmentSnapshot.self, from: data)
    }

    @MainActor
    static func apply(_ snapshot: EnvironmentSnapshot, to viewModel: AppViewModel) {
        if let mirror = BrewMirror(rawValue: snapshot.brewMirror) {
            viewModel.settings.brewMirror = mirror
        }
        viewModel.settings.enableMAS = snapshot.enableMAS
        viewModel.settings.skipInstalled = snapshot.skipInstalled
        viewModel.settings.allowMultipleRoles = snapshot.allowMultipleRoles
        viewModel.selectedRoles = Set(snapshot.selectedRoleIDs)
        viewModel.refreshResolvedTools()

        let selectedSet = Set(snapshot.selectedToolIDs)
        viewModel.resolvedTools = viewModel.resolvedTools.map { item in
            var copy = item
            copy.isSelected = item.isRequired || selectedSet.contains(item.id)
            return copy
        }
        if let discoverIDs = snapshot.discoverSelectedToolIDs {
            viewModel.discoverSelectedTools = Set(discoverIDs)
        }
        viewModel.selectedTab = .roles
        viewModel.currentScreen = .bundleDetail
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

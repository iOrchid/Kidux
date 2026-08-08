import Foundation

struct MachineEnvironmentState: Codable, Sendable, Equatable {
    let brewFormulae: [String]
    let brewCasks: [String]
    let gitName: String?
    let gitEmail: String?
    /// RuntimeKind.rawValue → version 行
    let runtimeVersions: [String: String]
    let capturedAt: Date
    /// v4+ — MAS 已装 App ID
    let masAppIDs: [String]?
    /// v4+ — 跟踪的 macOS defaults 键值
    let macOSDefaults: [MacOSDefaultSnapshotEntry]?
    /// v4+ — shell / profile 摘要
    let shellSnapshot: ShellEnvironmentSnapshot?

    static let empty = MachineEnvironmentState(
        brewFormulae: [],
        brewCasks: [],
        gitName: nil,
        gitEmail: nil,
        runtimeVersions: [:],
        capturedAt: .distantPast,
        masAppIDs: nil,
        macOSDefaults: nil,
        shellSnapshot: nil
    )

    init(
        brewFormulae: [String],
        brewCasks: [String],
        gitName: String?,
        gitEmail: String?,
        runtimeVersions: [String: String],
        capturedAt: Date,
        masAppIDs: [String]? = nil,
        macOSDefaults: [MacOSDefaultSnapshotEntry]? = nil,
        shellSnapshot: ShellEnvironmentSnapshot? = nil
    ) {
        self.brewFormulae = brewFormulae
        self.brewCasks = brewCasks
        self.gitName = gitName
        self.gitEmail = gitEmail
        self.runtimeVersions = runtimeVersions
        self.capturedAt = capturedAt
        self.masAppIDs = masAppIDs
        self.macOSDefaults = macOSDefaults
        self.shellSnapshot = shellSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brewFormulae = try container.decode([String].self, forKey: .brewFormulae)
        brewCasks = try container.decode([String].self, forKey: .brewCasks)
        gitName = try container.decodeIfPresent(String.self, forKey: .gitName)
        gitEmail = try container.decodeIfPresent(String.self, forKey: .gitEmail)
        runtimeVersions = try container.decodeIfPresent([String: String].self, forKey: .runtimeVersions) ?? [:]
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        masAppIDs = try container.decodeIfPresent([String].self, forKey: .masAppIDs)
        macOSDefaults = try container.decodeIfPresent([MacOSDefaultSnapshotEntry].self, forKey: .macOSDefaults)
        shellSnapshot = try container.decodeIfPresent(ShellEnvironmentSnapshot.self, forKey: .shellSnapshot)
    }

    private enum CodingKeys: String, CodingKey {
        case brewFormulae, brewCasks, gitName, gitEmail, runtimeVersions, capturedAt
        case masAppIDs, macOSDefaults, shellSnapshot
    }
}

struct EnvironmentDriftItem: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let detail: String
    let kind: Kind

    enum Kind: String, Sendable {
        case missing
        case extra
        case changed
    }
}

struct EnvironmentDriftReport: Sendable {
    let items: [EnvironmentDriftItem]
    let baselineCapturedAt: Date
    let comparedAt: Date

    var hasDrift: Bool { !items.isEmpty }

    var summaryLine: String {
        guard hasDrift else { return "与基准一致，未检测到漂移" }
        let missing = items.filter { $0.kind == .missing }.count
        let extra = items.filter { $0.kind == .extra }.count
        let changed = items.filter { $0.kind == .changed }.count
        var parts: [String] = []
        if missing > 0 { parts.append("缺失 \(missing)") }
        if extra > 0 { parts.append("多出 \(extra)") }
        if changed > 0 { parts.append("变更 \(changed)") }
        return parts.joined(separator: " · ")
    }
}

enum EnvironmentDriftService {
    static func captureCurrent(
        mirror: BrewMirror,
        includeV4Extras: Bool = true,
        runtime: RuntimeEnvironmentSnapshot? = nil
    ) async -> MachineEnvironmentState {
        let homebrew = HomebrewService()
        let env = ShellEnvironment.developerEnvironment(extra: mirror.environmentVariables)

        async let formulaeTask = captureBrewList(homebrew: homebrew, cask: false, env: env)
        async let casksTask = captureBrewList(homebrew: homebrew, cask: true, env: env)
        async let gitTask = GitSetupService.readIdentity()
        let runtimeSnapshot: RuntimeEnvironmentSnapshot
        if let runtime {
            runtimeSnapshot = runtime
        } else {
            runtimeSnapshot = await RuntimeEnvironmentService.scan()
        }

        let formulae = await formulaeTask
        let casks = await casksTask
        let git = await gitTask
        let runtime = runtimeSnapshot

        var versions: [String: String] = [:]
        for profile in runtime.runtimes where profile.isInstalled {
            versions[profile.kind.rawValue] = profile.versionLine ?? profile.executablePath ?? "installed"
        }

        var masAppIDs: [String]?
        var macOSDefaults: [MacOSDefaultSnapshotEntry]?
        var shellSnapshot: ShellEnvironmentSnapshot?
        if includeV4Extras {
            async let masTask = EnvironmentSnapshotV4Capture.captureMASAppIDs()
            async let defaultsTask = EnvironmentSnapshotV4Capture.captureMacOSDefaults()
            async let shellTask = EnvironmentSnapshotV4Capture.captureShellEnvironment()
            masAppIDs = await masTask
            macOSDefaults = await defaultsTask
            shellSnapshot = await shellTask
        }

        return MachineEnvironmentState(
            brewFormulae: formulae.sorted(),
            brewCasks: casks.sorted(),
            gitName: git.name.nilIfEmpty,
            gitEmail: git.email.nilIfEmpty,
            runtimeVersions: versions,
            capturedAt: Date(),
            masAppIDs: masAppIDs,
            macOSDefaults: macOSDefaults,
            shellSnapshot: shellSnapshot
        )
    }

    static func compare(baseline: MachineEnvironmentState, current: MachineEnvironmentState) -> EnvironmentDriftReport {
        var items: [EnvironmentDriftItem] = []

        let baseFormulae = Set(baseline.brewFormulae)
        let curFormulae = Set(current.brewFormulae)
        for name in baseFormulae.subtracting(curFormulae).sorted() {
            items.append(EnvironmentDriftItem(
                id: "formula-missing-\(name)",
                title: name,
                detail: "基准中有此 formula，本机未安装",
                kind: .missing
            ))
        }
        for name in curFormulae.subtracting(baseFormulae).sorted() {
            items.append(EnvironmentDriftItem(
                id: "formula-extra-\(name)",
                title: name,
                detail: "本机已装，基准中未记录",
                kind: .extra
            ))
        }

        let baseCasks = Set(baseline.brewCasks)
        let curCasks = Set(current.brewCasks)
        for name in baseCasks.subtracting(curCasks).sorted() {
            items.append(EnvironmentDriftItem(
                id: "cask-missing-\(name)",
                title: name,
                detail: "基准中有此 cask，本机未安装",
                kind: .missing
            ))
        }
        for name in curCasks.subtracting(baseCasks).sorted() {
            items.append(EnvironmentDriftItem(
                id: "cask-extra-\(name)",
                title: name,
                detail: "本机已装，基准中未记录",
                kind: .extra
            ))
        }

        if baseline.gitName != current.gitName || baseline.gitEmail != current.gitEmail {
            items.append(EnvironmentDriftItem(
                id: "git-identity",
                title: "Git 身份",
                detail: "基准 \(baseline.gitName ?? "—") / \(baseline.gitEmail ?? "—") → 当前 \(current.gitName ?? "—") / \(current.gitEmail ?? "—")",
                kind: .changed
            ))
        }

        let runtimeKeys = Set(baseline.runtimeVersions.keys).union(current.runtimeVersions.keys)
        for key in runtimeKeys.sorted() {
            let base = baseline.runtimeVersions[key]
            let cur = current.runtimeVersions[key]
            guard base != cur else { continue }
            let title = RuntimeKind(rawValue: key)?.title ?? key
            if base == nil {
                items.append(EnvironmentDriftItem(
                    id: "runtime-extra-\(key)",
                    title: title,
                    detail: "基准未记录 · 当前 \(cur ?? "—")",
                    kind: .extra
                ))
            } else if cur == nil {
                items.append(EnvironmentDriftItem(
                    id: "runtime-missing-\(key)",
                    title: title,
                    detail: "基准 \(base ?? "—") · 本机未检测到",
                    kind: .missing
                ))
            } else {
                items.append(EnvironmentDriftItem(
                    id: "runtime-changed-\(key)",
                    title: title,
                    detail: "\(base ?? "—") → \(cur ?? "—")",
                    kind: .changed
                ))
            }
        }

        compareMAS(baseline: baseline, current: current, into: &items)
        compareDefaults(baseline: baseline, current: current, into: &items)
        compareShell(baseline: baseline, current: current, into: &items)

        return EnvironmentDriftReport(
            items: items,
            baselineCapturedAt: baseline.capturedAt,
            comparedAt: Date()
        )
    }

    struct DriftFixPlan: Sendable {
        let missingFormulae: [String]
        let missingCasks: [String]
        let missingMASAppIDs: [String]

        var hasInstallableMissing: Bool {
            !missingFormulae.isEmpty || !missingCasks.isEmpty
        }

        var summary: String {
            var parts: [String] = []
            if !missingFormulae.isEmpty { parts.append("\(missingFormulae.count) formula") }
            if !missingCasks.isEmpty { parts.append("\(missingCasks.count) cask") }
            if !missingMASAppIDs.isEmpty { parts.append("\(missingMASAppIDs.count) MAS") }
            guard !parts.isEmpty else { return "无缺失 brew 包" }
            return "可补齐 " + parts.joined(separator: " · ")
        }
    }

    static func suggestFixes(from report: EnvironmentDriftReport) -> DriftFixPlan {
        DriftFixPlan(
            missingFormulae: report.items
                .filter { $0.kind == .missing && $0.id.hasPrefix("formula-missing-") }
                .map(\.title),
            missingCasks: report.items
                .filter { $0.kind == .missing && $0.id.hasPrefix("cask-missing-") }
                .map(\.title),
            missingMASAppIDs: report.items
                .filter { $0.kind == .missing && $0.id.hasPrefix("mas-missing-") }
                .map(\.title)
        )
    }

    private static func compareMAS(
        baseline: MachineEnvironmentState,
        current: MachineEnvironmentState,
        into items: inout [EnvironmentDriftItem]
    ) {
        guard let baseIDs = baseline.masAppIDs, let curIDs = current.masAppIDs else { return }
        let base = Set(baseIDs)
        let cur = Set(curIDs)
        for id in base.subtracting(cur).sorted() {
            items.append(EnvironmentDriftItem(
                id: "mas-missing-\(id)",
                title: id,
                detail: "基准中有此 MAS App，本机未安装",
                kind: .missing
            ))
        }
        for id in cur.subtracting(base).sorted() {
            items.append(EnvironmentDriftItem(
                id: "mas-extra-\(id)",
                title: id,
                detail: "本机已装，基准中未记录",
                kind: .extra
            ))
        }
    }

    private static func compareDefaults(
        baseline: MachineEnvironmentState,
        current: MachineEnvironmentState,
        into items: inout [EnvironmentDriftItem]
    ) {
        guard let baseEntries = baseline.macOSDefaults, let curEntries = current.macOSDefaults else { return }
        let baseMap = Dictionary(uniqueKeysWithValues: baseEntries.map { ($0.compositeKey, $0) })
        let curMap = Dictionary(uniqueKeysWithValues: curEntries.map { ($0.compositeKey, $0) })

        for key in Set(baseMap.keys).union(curMap.keys).sorted() {
            let base = baseMap[key]
            let cur = curMap[key]
            guard base?.value != cur?.value else { continue }
            let label = base?.label ?? cur?.label ?? key
            if base == nil {
                items.append(EnvironmentDriftItem(
                    id: "defaults-extra-\(key)",
                    title: label,
                    detail: "当前 \(cur?.value ?? "—")",
                    kind: .extra
                ))
            } else if cur == nil {
                items.append(EnvironmentDriftItem(
                    id: "defaults-missing-\(key)",
                    title: label,
                    detail: "基准 \(base?.value ?? "—") · 当前未设置",
                    kind: .missing
                ))
            } else {
                items.append(EnvironmentDriftItem(
                    id: "defaults-changed-\(key)",
                    title: label,
                    detail: "\(base?.value ?? "—") → \(cur?.value ?? "—")",
                    kind: .changed
                ))
            }
        }
    }

    private static func compareShell(
        baseline: MachineEnvironmentState,
        current: MachineEnvironmentState,
        into items: inout [EnvironmentDriftItem]
    ) {
        guard let baseShell = baseline.shellSnapshot, let curShell = current.shellSnapshot else { return }

        if baseShell.loginShell != curShell.loginShell {
            items.append(EnvironmentDriftItem(
                id: "shell-login",
                title: "登录 Shell",
                detail: "\(baseShell.loginShell ?? "—") → \(curShell.loginShell ?? "—")",
                kind: .changed
            ))
        }

        let baseProfiles = Set(baseShell.profileFilesPresent)
        let curProfiles = Set(curShell.profileFilesPresent)
        for file in baseProfiles.subtracting(curProfiles).sorted() {
            items.append(EnvironmentDriftItem(
                id: "shell-missing-\(file)",
                title: file,
                detail: "基准存在此 profile 文件，当前缺失",
                kind: .missing
            ))
        }
        for file in curProfiles.subtracting(baseProfiles).sorted() {
            items.append(EnvironmentDriftItem(
                id: "shell-extra-\(file)",
                title: file,
                detail: "当前存在，基准未记录",
                kind: .extra
            ))
        }
    }

    private static func captureBrewList(
        homebrew: HomebrewService,
        cask: Bool,
        env: [String: String]
    ) async -> [String] {
        guard await homebrew.isInstalled() else { return [] }
        let shell = ShellExecutor()
        let flag = cask ? "--cask" : "--formula"
        let result = try? await shell.run("brew list \(flag) 2>/dev/null", environment: env)
        guard let text = result?.stdout else { return [] }
        return text
            .split(whereSeparator: \.isWhitespace)
            .map { String($0) }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

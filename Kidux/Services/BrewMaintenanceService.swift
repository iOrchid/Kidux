import Foundation

struct BrewServiceItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let status: String
    let user: String?
    let plistPath: String?

    var isRunning: Bool { status == "started" }
    var statusLabel: String {
        switch status {
        case "started": return "运行中"
        case "stopped": return "已停止"
        case "error": return "异常"
        case "none": return "未注册"
        default: return status
        }
    }
}

struct BrewDiskUsage: Sendable {
    let cellarPath: String
    let cachePath: String
    let cellarBytes: Int64?
    let cacheBytes: Int64?
    let cleanupPreviewLines: [String]
    let reclaimableBytes: Int64?

    var cellarDisplay: String { Self.formatBytes(cellarBytes) }
    var cacheDisplay: String { Self.formatBytes(cacheBytes) }
    var reclaimableDisplay: String { Self.formatBytes(reclaimableBytes) }

    static func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

enum BrewServiceAction: String, Sendable {
    case start
    case stop
    case restart
}

enum BrewVulnerabilityScanState: Sendable, Equatable {
    case homebrewMissing
    case pluginMissing
    case scanFailed(String)
    case clean
    case foundIssues
}

struct BrewVulnerabilityFinding: Identifiable, Sendable, Hashable {
    let id: String
    let severity: String
    let summary: String

    var severityColor: String {
        switch severity.uppercased() {
        case "CRITICAL", "HIGH": return "red"
        case "MEDIUM": return "orange"
        default: return "secondary"
        }
    }
}

struct BrewVulnerablePackage: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let version: String?
    let vulnerabilities: [BrewVulnerabilityFinding]
}

struct BrewVulnerabilityScan: Sendable {
    let state: BrewVulnerabilityScanState
    let packages: [BrewVulnerablePackage]
    let summaryLine: String?
    let scannedAt: Date

    var totalFindings: Int {
        packages.reduce(0) { $0 + $1.vulnerabilities.count }
    }
}

enum BrewMaintenanceService {
    private static let brew = HomebrewService()

    static func listServices(mirror: BrewMirror) async -> [BrewServiceItem] {
        guard await brew.isInstalled() else { return [] }
        let env = mirror.environmentVariables
        let result = await brewShell("brew services list --json 2>/dev/null", env: env)
        guard let data = result.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return parseServicesText(result)
        }

        return array.compactMap { row in
            guard let name = row["name"] as? String else { return nil }
            let status = (row["status"] as? String) ?? "unknown"
            return BrewServiceItem(
                id: name,
                name: name,
                status: status,
                user: row["user"] as? String,
                plistPath: row["file"] as? String
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// S17-03 用户显式安装的 formula（`brew leaves`）
    static func fetchLeaves(mirror: BrewMirror) async -> Set<String> {
        guard await brew.isInstalled() else { return [] }
        let env = ShellEnvironment.developerEnvironment(extra: mirror.environmentVariables)
        let result = await brewShell("brew leaves 2>/dev/null", env: env)
        guard !result.isEmpty else { return [] }
        return Set(
            result
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    static func runService(
        name: String,
        action: BrewServiceAction,
        mirror: BrewMirror
    ) async throws -> String {
        guard await brew.isInstalled() else { throw HomebrewError.notInstalled }
        let env = mirror.environmentVariables
        let result = try await brewShellChecked(
            "brew services \(action.rawValue) \(shellQuote(name))",
            env: env
        )
        return result
    }

    static func loadDiskUsage(mirror: BrewMirror) async -> BrewDiskUsage {
        guard await brew.isInstalled() else {
            return BrewDiskUsage(
                cellarPath: "",
                cachePath: "",
                cellarBytes: nil,
                cacheBytes: nil,
                cleanupPreviewLines: [],
                reclaimableBytes: nil
            )
        }

        let env = mirror.environmentVariables
        async let cellarPath = brewPath(flag: "--cellar", env: env)
        async let cachePath = brewPath(flag: "--cache", env: env)
        async let preview = cleanupPreview(env: env)

        let cellar = await cellarPath
        let cache = await cachePath
        let previewResult = await preview

        async let cellarSize = directorySize(path: cellar)
        async let cacheSize = directorySize(path: cache)

        return BrewDiskUsage(
            cellarPath: cellar,
            cachePath: cache,
            cellarBytes: await cellarSize,
            cacheBytes: await cacheSize,
            cleanupPreviewLines: previewResult.lines,
            reclaimableBytes: previewResult.reclaimableBytes
        )
    }

    static func runCleanup(mirror: BrewMirror) async throws -> String {
        guard await brew.isInstalled() else { throw HomebrewError.notInstalled }
        return try await brewShellChecked("brew cleanup -s", env: mirror.environmentVariables)
    }

    // MARK: - brew vulns（需 brew install homebrew/brew-vulns/brew-vulns）

    static func isVulnsPluginAvailable(mirror: BrewMirror) async -> Bool {
        guard await brew.isInstalled() else { return false }
        let output = await brewShell("brew vulns --help 2>&1", env: mirror.environmentVariables)
        return !output.localizedCaseInsensitiveContains("unknown command")
    }

    static func installVulnsPlugin(mirror: BrewMirror) async throws -> String {
        guard await brew.isInstalled() else { throw HomebrewError.notInstalled }
        return try await brewShellChecked(
            "brew install homebrew/brew-vulns/brew-vulns",
            env: mirror.environmentVariables
        )
    }

    static func scanVulnerabilities(mirror: BrewMirror) async -> BrewVulnerabilityScan {
        guard await brew.isInstalled() else {
            return BrewVulnerabilityScan(
                state: .homebrewMissing,
                packages: [],
                summaryLine: nil,
                scannedAt: Date()
            )
        }

        guard await isVulnsPluginAvailable(mirror: mirror) else {
            return BrewVulnerabilityScan(
                state: .pluginMissing,
                packages: [],
                summaryLine: nil,
                scannedAt: Date()
            )
        }

        let env = mirror.environmentVariables
        let jsonOutput = await brewShell("brew vulns --json --severity low 2>&1", env: env)
        if let scan = parseVulnerabilityJSON(jsonOutput) {
            return scan
        }

        let textOutput = await brewShell("brew vulns --severity low 2>&1", env: env)
        if textOutput.localizedCaseInsensitiveContains("unknown command") {
            return BrewVulnerabilityScan(state: .pluginMissing, packages: [], summaryLine: nil, scannedAt: Date())
        }
        if textOutput.localizedCaseInsensitiveContains("error:") &&
            textOutput.localizedCaseInsensitiveContains("network") {
            return BrewVulnerabilityScan(
                state: .scanFailed(textOutput),
                packages: [],
                summaryLine: nil,
                scannedAt: Date()
            )
        }

        return parseVulnerabilityText(textOutput)
    }

    private static func parseVulnerabilityJSON(_ output: String) -> BrewVulnerabilityScan? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return nil }

        var packages: [BrewVulnerablePackage] = []

        func appendPackage(name: String, version: String?, vulns: [[String: Any]]) {
            let findings = vulns.compactMap { row -> BrewVulnerabilityFinding? in
                let id = (row["id"] as? String) ?? (row["cve"] as? String) ?? (row["summary"] as? String) ?? "vuln"
                let severity = (row["severity"] as? String) ?? "unknown"
                let summary = (row["summary"] as? String) ?? (row["details"] as? String) ?? id
                return BrewVulnerabilityFinding(id: id, severity: severity.uppercased(), summary: summary)
            }
            guard !findings.isEmpty else { return }
            packages.append(BrewVulnerablePackage(id: name, name: name, version: version, vulnerabilities: findings))
        }

        if let array = json as? [[String: Any]] {
            for row in array {
                guard let name = row["name"] as? String ?? row["formula"] as? String else { continue }
                let version = row["version"] as? String
                let vulns = row["vulnerabilities"] as? [[String: Any]] ?? []
                appendPackage(name: name, version: version, vulns: vulns)
            }
        } else if let object = json as? [String: Any] {
            let rows = (object["packages"] as? [[String: Any]]) ?? (object["results"] as? [[String: Any]]) ?? []
            for row in rows {
                guard let name = row["name"] as? String ?? row["formula"] as? String else { continue }
                let version = row["version"] as? String
                let vulns = row["vulnerabilities"] as? [[String: Any]] ?? []
                appendPackage(name: name, version: version, vulns: vulns)
            }
        } else {
            return nil
        }

        let summary = extractSummaryLine(from: output)
        return BrewVulnerabilityScan(
            state: packages.isEmpty ? .clean : .foundIssues,
            packages: packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            summaryLine: summary,
            scannedAt: Date()
        )
    }

    private static func parseVulnerabilityText(_ output: String) -> BrewVulnerabilityScan {
        var packages: [BrewVulnerablePackage] = []
        var currentName: String?
        var currentVersion: String?
        var currentFindings: [BrewVulnerabilityFinding] = []

        func flushPackage() {
            guard let name = currentName, !currentFindings.isEmpty else {
                currentName = nil
                currentVersion = nil
                currentFindings = []
                return
            }
            packages.append(
                BrewVulnerablePackage(
                    id: name,
                    name: name,
                    version: currentVersion,
                    vulnerabilities: currentFindings
                )
            )
            currentName = nil
            currentVersion = nil
            currentFindings = []
        }

        let packagePattern = #"^(\S+)\s+\(([^)]+)\)"#
        let bracketPattern = #"^\s+\[(CRITICAL|HIGH|MEDIUM|LOW)\]\s+(\S+)\s*-\s*(.+)$"#
        let parenPattern = #"^\s+(\S+)\s+\((CRITICAL|HIGH|MEDIUM|LOW)\)\s*-\s*(.+)$"#
        let packageRegex = try? NSRegularExpression(pattern: packagePattern, options: .caseInsensitive)
        let bracketRegex = try? NSRegularExpression(pattern: bracketPattern, options: .caseInsensitive)
        let parenRegex = try? NSRegularExpression(pattern: parenPattern, options: .caseInsensitive)

        for line in output.split(separator: "\n").map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let packageRegex,
               let match = packageRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               match.numberOfRanges >= 3,
               let nameRange = Range(match.range(at: 1), in: trimmed),
               let versionRange = Range(match.range(at: 2), in: trimmed) {
                flushPackage()
                currentName = String(trimmed[nameRange])
                currentVersion = String(trimmed[versionRange])
                continue
            }

            if let bracketRegex,
               let match = bracketRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               match.numberOfRanges >= 4,
               let sevRange = Range(match.range(at: 1), in: line),
               let idRange = Range(match.range(at: 2), in: line),
               let summaryRange = Range(match.range(at: 3), in: line) {
                currentFindings.append(
                    BrewVulnerabilityFinding(
                        id: String(line[idRange]),
                        severity: String(line[sevRange]).uppercased(),
                        summary: String(line[summaryRange]).trimmingCharacters(in: .whitespaces)
                    )
                )
                continue
            }

            if let parenRegex,
               let match = parenRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               match.numberOfRanges >= 4,
               let idRange = Range(match.range(at: 1), in: line),
               let sevRange = Range(match.range(at: 2), in: line),
               let summaryRange = Range(match.range(at: 3), in: line) {
                currentFindings.append(
                    BrewVulnerabilityFinding(
                        id: String(line[idRange]),
                        severity: String(line[sevRange]).uppercased(),
                        summary: String(line[summaryRange]).trimmingCharacters(in: .whitespaces)
                    )
                )
            }
        }
        flushPackage()

        let summary = extractSummaryLine(from: output)
        let state: BrewVulnerabilityScanState
        if packages.isEmpty {
            state = output.localizedCaseInsensitiveContains("no vulnerabilities") ||
                output.localizedCaseInsensitiveContains("0 vulnerabilities") ? .clean : .clean
        } else {
            state = .foundIssues
        }

        return BrewVulnerabilityScan(
            state: state,
            packages: packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            summaryLine: summary,
            scannedAt: Date()
        )
    }

    private static func extractSummaryLine(from output: String) -> String? {
        for line in output.split(separator: "\n").map(String.init).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.localizedCaseInsensitiveContains("vulnerabilit") ||
                    trimmed.contains("漏洞") else { continue }
            return trimmed
        }
        return nil
    }

    private struct CleanupPreview {
        let lines: [String]
        let reclaimableBytes: Int64?
    }

    private static func cleanupPreview(env: [String: String]) async -> CleanupPreview {
        let output = (try? await brewShellChecked("brew cleanup -n -s 2>&1", env: env)) ?? ""
        let lines = output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        let reclaimable = parseReclaimable(from: output)
        return CleanupPreview(lines: lines, reclaimableBytes: reclaimable)
    }

    private static func parseReclaimable(from output: String) -> Int64? {
        for line in output.split(separator: "\n") {
            let text = String(line)
            guard text.localizedCaseInsensitiveContains("would be freed") ||
                    text.contains("可回收") ||
                    text.contains("Reclaimable") else { continue }
            if let bytes = extractByteCount(from: text) { return bytes }
        }
        return nil
    }

    private static func extractByteCount(from text: String) -> Int64? {
        let pattern = #"(\d+(?:\.\d+)?)\s*([KMGTP]?B)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange])
        else { return nil }

        let unit = text[unitRange].uppercased()
        let multiplier: Double
        switch unit {
        case "KB": multiplier = 1024
        case "MB": multiplier = 1024 * 1024
        case "GB": multiplier = 1024 * 1024 * 1024
        case "TB": multiplier = 1024 * 1024 * 1024 * 1024
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }

    private static func parseServicesText(_ output: String) -> [BrewServiceItem] {
        output
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> BrewServiceItem? in
                let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard parts.count >= 2 else { return nil }
                let name = parts[0]
                let status = parts[1].lowercased()
                return BrewServiceItem(id: name, name: name, status: status, user: parts.count > 2 ? parts[2] : nil, plistPath: nil)
            }
    }

    private static func brewPath(flag: String, env: [String: String]) async -> String {
        let result = await brewShell("brew \(flag) 2>/dev/null", env: env)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func directorySize(path: String) async -> Int64? {
        guard !path.isEmpty else { return nil }
        let quoted = shellQuote(path)
        let result = await brewShell("du -sk \(quoted) 2>/dev/null | awk '{print $1}'")
        guard let value = Int64(result.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return value * 1024
    }

    private static func brewShell(_ command: String, env: [String: String] = [:]) async -> String {
        let shell = ShellExecutor()
        let brewPath = await brew.brewPath
        let full = command.replacingOccurrences(of: "brew ", with: "\(brewPath) ")
        let result = try? await shell.run(full, environment: env)
        return result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func brewShellChecked(_ command: String, env: [String: String]) async throws -> String {
        let shell = ShellExecutor()
        let brewPath = await brew.brewPath
        let full = command.replacingOccurrences(of: "brew ", with: "\(brewPath) ")
        let result = try await shell.run(full, environment: env)
        guard result.isSuccess else {
            throw HomebrewError.commandFailed(result.combinedOutput)
        }
        return result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

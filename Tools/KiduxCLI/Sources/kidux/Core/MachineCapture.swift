import Foundation

enum ShellRunner {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        var isSuccess: Bool { exitCode == 0 }
        var combinedOutput: String {
            [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    @discardableResult
    static func run(_ command: String, environment: [String: String] = [:]) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]

        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return Result(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

enum MachineCapture {
    private static let trackedDefaults: [(domain: String, key: String, label: String)] = [
        ("com.apple.finder", "AppleShowAllFiles", "Finder 显示隐藏文件"),
        ("NSGlobalDomain", "AppleShowAllExtensions", "显示所有扩展名"),
        ("com.apple.finder", "_FXShowPosixPathInTitle", "Finder 标题路径栏"),
        ("com.apple.dock", "autohide", "Dock 自动隐藏"),
        ("com.apple.dock", "mru-spaces", "Dock 按最近使用排列 Space"),
        ("NSGlobalDomain", "NSAutomaticWindowAnimationsEnabled", "窗口动画"),
        ("NSGlobalDomain", "KeyRepeat", "按键重复速率"),
        ("NSGlobalDomain", "InitialKeyRepeat", "按键重复延迟"),
        ("com.apple.screencapture", "location", "截图保存路径"),
        ("com.apple.screencapture", "type", "截图格式")
    ]

    private static let runtimeProbes: [(kind: String, command: String, versionCommand: String)] = [
        ("node", "node", "node --version 2>/dev/null"),
        ("python", "python3", "python3 --version 2>/dev/null"),
        ("java", "java", "java -version 2>&1 | head -n 1"),
        ("go", "go", "go version 2>/dev/null")
    ]

    static func capture(includeV4Extras: Bool = true) throws -> MachineEnvironmentState {
        let formulae = try captureBrewList(cask: false)
        let casks = try captureBrewList(cask: true)
        let gitName = try runOptional("git config --global user.name")
        let gitEmail = try runOptional("git config --global user.email")
        let runtimes = try captureRuntimes()

        var masAppIDs: [String]?
        var macOSDefaults: [MacOSDefaultSnapshotEntry]?
        var shellSnapshot: ShellEnvironmentSnapshot?

        if includeV4Extras {
            masAppIDs = try captureMASAppIDs()
            macOSDefaults = try captureDefaults()
            shellSnapshot = try captureShell()
        }

        return MachineEnvironmentState(
            brewFormulae: formulae.sorted(),
            brewCasks: casks.sorted(),
            gitName: gitName,
            gitEmail: gitEmail,
            runtimeVersions: runtimes,
            capturedAt: Date(),
            masAppIDs: masAppIDs,
            macOSDefaults: macOSDefaults,
            shellSnapshot: shellSnapshot
        )
    }

    private static func captureBrewList(cask: Bool) throws -> [String] {
        let brewCheck = try ShellRunner.run("command -v brew >/dev/null 2>&1")
        guard brewCheck.isSuccess else { return [] }

        let flag = cask ? "--cask" : "--formula"
        let result = try ShellRunner.run("eval \"$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)\" && brew list \(flag) 2>/dev/null")
        guard result.isSuccess else { return [] }
        return result.stdout
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func captureRuntimes() throws -> [String: String] {
        var versions: [String: String] = [:]
        for probe in runtimeProbes {
            let pathResult = try ShellRunner.run("command -v \(probe.command) 2>/dev/null")
            guard pathResult.isSuccess, !pathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let versionResult = try ShellRunner.run(probe.versionCommand)
            let line = versionResult.combinedOutput
                .split(whereSeparator: \.isNewline)
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            versions[probe.kind] = line?.nilIfEmpty ?? pathResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return versions
    }

    private static func captureMASAppIDs() throws -> [String] {
        let masCheck = try ShellRunner.run("command -v mas >/dev/null 2>&1")
        guard masCheck.isSuccess else { return [] }
        let result = try ShellRunner.run("mas list 2>/dev/null")
        guard result.isSuccess else { return [] }
        let ids = result.stdout.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
            return String(first)
        }
        return ids.sorted()
    }

    private static func captureDefaults() throws -> [MacOSDefaultSnapshotEntry] {
        var entries: [MacOSDefaultSnapshotEntry] = []
        for item in trackedDefaults {
            let result = try ShellRunner.run("defaults read \(item.domain) \(item.key) 2>/dev/null")
            guard result.isSuccess else { continue }
            let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            entries.append(
                MacOSDefaultSnapshotEntry(
                    domain: item.domain,
                    key: item.key,
                    value: value,
                    label: item.label
                )
            )
        }
        return entries
    }

    private static func captureShell() throws -> ShellEnvironmentSnapshot {
        let loginShell = try runOptional("printenv SHELL")
        let pathRaw = try ShellRunner.run("printenv PATH").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathPreview = pathRaw
            .split(separator: ":", omittingEmptySubsequences: false)
            .prefix(20)
            .map(String.init)

        let home = FileManager.default.homeDirectoryForCurrentUser
        let profileCandidates = [".zprofile", ".zshrc", ".bash_profile", ".bashrc", ".profile", ".config/fish/config.fish"]
        let present = profileCandidates.filter { relative in
            FileManager.default.fileExists(atPath: home.appendingPathComponent(relative).path)
        }

        return ShellEnvironmentSnapshot(
            loginShell: loginShell,
            pathPreview: pathPreview,
            profileFilesPresent: present.sorted()
        )
    }

    private static func runOptional(_ command: String) throws -> String? {
        let result = try ShellRunner.run(command)
        guard result.isSuccess else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

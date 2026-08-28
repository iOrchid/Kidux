import Foundation

enum HomebrewError: LocalizedError {
    case notInstalled
    case installFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Homebrew 未安装"
        case .installFailed(let msg):
            return "Homebrew 安装失败: \(msg)"
        case .commandFailed(let msg):
            return msg
        }
    }
}

actor HomebrewService {
    private let shell: ShellExecutor

    init(shell: ShellExecutor = ShellExecutor()) {
        self.shell = shell
    }

    var brewPath: String {
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin/brew"
        }
        return "brew"
    }

    func isInstalled() async -> Bool {
        let result = try? await shell.run("command -v brew")
        return result?.isSuccess == true
    }

    /// 是否已安装 Xcode Command Line Tools（Homebrew / git 前置）
    func hasCommandLineTools() async -> Bool {
        let result = try? await shell.run("xcode-select -p 2>/dev/null")
        return result?.isSuccess == true
    }

    /// 弹出系统「安装命令行工具」对话框（用户需在系统窗口完成）
    @discardableResult
    func promptInstallCommandLineTools() async -> Bool {
        let result = try? await shell.run("xcode-select --install 2>&1")
        // 已安装时会非 0；已弹出安装器时也可能非 0，只要命令能执行即可
        return result != nil
    }

    func installHomebrew(
        mirror: BrewMirror,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        if await !hasCommandLineTools() {
            onOutput?("❌ 尚未安装 Xcode 命令行工具（含 git）\n")
            onOutput?("💡 正在打开系统安装窗口，请完成后回到启椟重试…\n")
            _ = await promptInstallCommandLineTools()
            throw HomebrewError.installFailed(
                "需要先安装「命令行工具（CLT）」。请在系统弹窗中完成安装，再重新开始。"
            )
        }

        let env = mirror.environmentVariables
        onOutput?("▶ 正在安装 Homebrew（首次可能需几分钟，请保持网络畅通）…\n")
        let script = """
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        """
        let result = try await shell.run(script, environment: env, onOutput: onOutput)
        guard result.isSuccess else {
            let combined = result.combinedOutput
            let hint: String
            if combined.lowercased().contains("xcode") || combined.lowercased().contains("command line") {
                hint = "\n提示：请先安装命令行工具（CLT），再重试 Homebrew。"
            } else if combined.lowercased().contains("curl") || combined.lowercased().contains("network") {
                hint = "\n提示：网络异常时，可在设置中切换 Homebrew 国内镜像后重试。"
            } else {
                hint = ""
            }
            throw HomebrewError.installFailed(combined + hint)
        }
        if mirror != .official {
            try await applyMirrorRemotes(mirror: mirror, onOutput: onOutput)
        }
    }

    func applyMirrorRemotes(
        mirror: BrewMirror,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let env = mirror.environmentVariables
        guard !env.isEmpty else { return }

        let prefix = brewPath.hasPrefix("/")
            ? URL(fileURLWithPath: brewPath).deletingLastPathComponent().deletingLastPathComponent().path
            : "$(brew --prefix)"
        var commands: [String] = []

        if let brewRemote = env["HOMEBREW_BREW_GIT_REMOTE"] {
            commands.append("git -C \"\(prefix)\" remote set-url origin \"\(brewRemote)\" 2>/dev/null || true")
        }
        if let coreRemote = env["HOMEBREW_CORE_GIT_REMOTE"] {
            commands.append("git -C \"\(prefix)/Library/Taps/homebrew/homebrew-core\" remote set-url origin \"\(coreRemote)\" 2>/dev/null || true")
        }

        for command in commands {
            _ = try await shell.run(command, environment: env, onOutput: onOutput)
        }
    }

    func listFormulae() async throws -> Set<String> {
        let result = try await shell.run("\(brewPath) list --formula 2>/dev/null")
        guard result.isSuccess else { return [] }
        return Set(result.stdout.split(separator: "\n").map(String.init))
    }

    func listCasks() async throws -> Set<String> {
        let result = try await shell.run("\(brewPath) list --cask 2>/dev/null")
        guard result.isSuccess else { return [] }
        return Set(result.stdout.split(separator: "\n").map(String.init))
    }

    func isToolInstalled(_ tool: DevTool, snapshot: InstalledStatusSnapshot?) async -> Bool {
        if let snapshot {
            return snapshot.state(for: tool) == .installed
        }
        switch tool.source.type {
        case .formula:
            let formulae = (try? await listFormulae()) ?? []
            return formulae.contains(tool.source.identifier)
        case .cask:
            let casks = (try? await listCasks()) ?? []
            return casks.contains(tool.source.identifier)
        case .mas, .script, .link:
            return false
        }
    }

    func installTool(
        _ tool: DevTool,
        mirror: BrewMirror,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let env = ShellEnvironment.developerEnvironment(extra: mirror.environmentVariables)
        let command: String
        switch tool.source.type {
        case .formula:
            command = "\(brewPath) install \(tool.source.identifier)"
        case .cask:
            command = "\(brewPath) install --cask \(tool.source.identifier)"
        case .mas:
            command = "mas install \(tool.source.identifier)"
        case .script:
            command = tool.source.identifier
        case .link:
            throw HomebrewError.commandFailed("外链软件请在浏览器中手动安装")
        }

        let result = try await shell.run(command, environment: env, onOutput: onOutput)
        if result.isSuccess {
            return result.combinedOutput
        }

        if AdminShellHelper.needsElevation(result.combinedOutput) {
            onOutput?("⚠️ 需要管理员权限，正在弹出系统授权…\n")
            let admin = try await AdminShellHelper.runWithPrivileges(command: command, environment: env)
            guard admin.isSuccess else {
                throw HomebrewError.commandFailed(admin.combinedOutput)
            }
            return admin.combinedOutput
        }

        throw HomebrewError.commandFailed(result.combinedOutput)
    }

    func ensureMASInstalled(
        mirror: BrewMirror,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let masTool = DevTool(
            id: "mas",
            name: "mas-cli",
            description: "",
            category: "infra",
            source: InstallSource(type: .formula, identifier: "mas"),
            priority: 3
        )
        if await isToolInstalled(masTool, snapshot: nil) { return }
        _ = try await installTool(masTool, mirror: mirror, onOutput: onOutput)
    }

    func generateBrewfile(tools: [ResolvedTool]) -> String {
        var lines = ["# Generated by \(BrandInfo.generatedBy)", "tap \"homebrew/cask\""]
        let sorted = tools
            .filter(\.isSelected)
            .sorted { $0.tool.priority < $1.tool.priority }

        for resolved in sorted {
            switch resolved.tool.source.type {
            case .formula:
                lines.append("brew \"\(resolved.tool.source.identifier)\"")
            case .cask:
                lines.append("cask \"\(resolved.tool.source.identifier)\"")
            case .mas, .script, .link:
                break
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func runBundle(
        brewfileContent: String,
        mirror: BrewMirror,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let brewfileURL = tempDir.appendingPathComponent("\(BrandInfo.generatedBy)-Brewfile")
        try brewfileContent.write(to: brewfileURL, atomically: true, encoding: .utf8)

        let result = try await shell.run(
            "\(brewPath) bundle --file=\"\(brewfileURL.path)\"",
            environment: mirror.environmentVariables,
            onOutput: onOutput
        )
        guard result.isSuccess else {
            throw HomebrewError.commandFailed(result.combinedOutput)
        }
        return result.combinedOutput
    }

    func search(query: String, includeFormulae: Bool = true, includeCasks: Bool = true) async -> [BrewSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard await isInstalled() else { return [] }

        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
        var results: [BrewSearchResult] = []

        if includeFormulae {
            let formulaResult = try? await shell.run("\(brewPath) search --formula \"\(escaped)\" 2>/dev/null")
            if let output = formulaResult?.stdout, formulaResult?.isSuccess == true {
                results.append(contentsOf: parseSearchOutput(output, type: .formula))
            }
        }

        if includeCasks {
            let caskResult = try? await shell.run("\(brewPath) search --cask \"\(escaped)\" 2>/dev/null")
            if let output = caskResult?.stdout, caskResult?.isSuccess == true {
                results.append(contentsOf: parseSearchOutput(output, type: .cask))
            }
        }

        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }

    private func parseSearchOutput(_ output: String, type: InstallSourceType) -> [BrewSearchResult] {
        output
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
            .map { BrewSearchResult(name: $0, sourceType: type) }
    }

    struct OutdatedPackages: Sendable {
        let formulae: [String]
        let casks: [String]
    }

    func listOutdated(mirror: BrewMirror = .official) async -> OutdatedPackages {
        guard await isInstalled() else {
            return OutdatedPackages(formulae: [], casks: [])
        }

        let env = mirror.environmentVariables
        let result = try? await shell.run("\(brewPath) outdated --json=v2 2>/dev/null", environment: env)
        guard let json = result?.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        else {
            return OutdatedPackages(formulae: [], casks: [])
        }

        let formulae = (object["formulae"] as? [String]) ?? []
        let casks = (object["casks"] as? [String]) ?? []
        return OutdatedPackages(formulae: formulae, casks: casks)
    }

    /// S18-17 — 刷新 Homebrew 配方索引（不升级已装包）
    @discardableResult
    func updateIndex(mirror: BrewMirror = .official) async -> Bool {
        guard await isInstalled() else { return false }
        let env = mirror.environmentVariables
        let result = try? await shell.run("\(brewPath) update", environment: env)
        return result?.isSuccess == true
    }

    func upgrade(
        name: String,
        type: InstallSourceType,
        mirror: BrewMirror,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let env = ShellEnvironment.developerEnvironment(extra: mirror.environmentVariables)
        let command: String
        switch type {
        case .formula:
            command = "\(brewPath) upgrade \(name)"
        case .cask:
            command = "\(brewPath) upgrade --cask \(name)"
        default:
            throw HomebrewError.commandFailed("仅支持 brew formula / cask 更新")
        }

        let result = try await shell.run(command, environment: env, onOutput: onOutput)
        if result.isSuccess {
            return result.combinedOutput
        }

        if AdminShellHelper.needsElevation(result.combinedOutput) {
            onOutput?("⚠️ 需要管理员权限，正在弹出系统授权…\n")
            let admin = try await AdminShellHelper.runWithPrivileges(command: command, environment: env)
            guard admin.isSuccess else {
                throw HomebrewError.commandFailed(admin.combinedOutput)
            }
            return admin.combinedOutput
        }

        throw HomebrewError.commandFailed(result.combinedOutput)
    }

    func uninstall(
        name: String,
        type: InstallSourceType,
        mirror: BrewMirror,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let env = mirror.environmentVariables
        let command: String
        switch type {
        case .formula:
            command = "\(brewPath) uninstall \(name)"
        case .cask:
            command = "\(brewPath) uninstall --cask \(name)"
        default:
            throw HomebrewError.commandFailed("仅支持卸载 brew formula / cask")
        }

        let result = try await shell.run(command, environment: env, onOutput: onOutput)
        guard result.isSuccess else {
            throw HomebrewError.commandFailed(result.combinedOutput)
        }
        return result.combinedOutput
    }

    // MARK: - Version Pinning

    /// 锁定 formula 版本，防止意外升级
    func pinFormula(_ formula: String) async throws {
        let result = try await shell.run("\(brewPath) pin \(formula)")
        guard result.isSuccess else {
            throw HomebrewError.commandFailed(result.combinedOutput)
        }
    }

    /// 解锁 formula 版本，允许升级
    func unpinFormula(_ formula: String) async throws {
        let result = try await shell.run("\(brewPath) unpin \(formula)")
        guard result.isSuccess else {
            throw HomebrewError.commandFailed(result.combinedOutput)
        }
    }

    /// 列出所有已锁定的 formula
    func listPinned() async -> Set<String> {
        let result = try? await shell.run("\(brewPath) list --pinned 2>/dev/null")
        guard result?.isSuccess == true, let output = result?.stdout else {
            return []
        }
        return Set(output.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    /// 检查指定 formula 是否已锁定
    func isPinned(_ formula: String) async -> Bool {
        let pinned = await listPinned()
        return pinned.contains(formula)
    }
}

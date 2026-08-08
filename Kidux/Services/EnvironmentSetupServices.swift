import Foundation

// MARK: - S12-05 macOS defaults

struct MacOSDefaultPreset: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let shellScript: String
}

enum MacOSDefaultsService {
    static let developerPresets: [MacOSDefaultPreset] = [
        MacOSDefaultPreset(
            id: "finder_dev",
            title: "Finder 开发者视图",
            summary: "显示隐藏文件、扩展名、标题路径栏",
            shellScript: """
            defaults write com.apple.finder AppleShowAllFiles -bool true
            defaults write NSGlobalDomain AppleShowAllExtensions -bool true
            defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
            killall Finder 2>/dev/null || true
            """
        ),
        MacOSDefaultPreset(
            id: "dock_dev",
            title: "Dock 与窗口",
            summary: "关闭 Dock 自动隐藏、禁用重新排列 Space",
            shellScript: """
            defaults write com.apple.dock autohide -bool false
            defaults write com.apple.dock mru-spaces -bool false
            defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
            killall Dock 2>/dev/null || true
            """
        ),
        MacOSDefaultPreset(
            id: "keyboard_dev",
            title: "键盘重复速率",
            summary: "加快按键重复（适合编码）",
            shellScript: """
            defaults write NSGlobalDomain KeyRepeat -int 2
            defaults write NSGlobalDomain InitialKeyRepeat -int 25
            """
        ),
        MacOSDefaultPreset(
            id: "screenshot_dev",
            title: "截图默认路径",
            summary: "截图保存到桌面",
            shellScript: """
            defaults write com.apple.screencapture location -string "${HOME}/Desktop"
            defaults write com.apple.screencapture type -string "png"
            killall SystemUIServer 2>/dev/null || true
            """
        )
    ]

    /// S15-01 — 快照 v4 采集的 defaults 键（与开发者预设一致）
    private static let snapshotTrackedKeys: [(domain: String, key: String, label: String)] = [
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

    static func captureSnapshotEntries() async -> [MacOSDefaultSnapshotEntry] {
        let shell = ShellExecutor()
        var entries: [MacOSDefaultSnapshotEntry] = []

        for item in snapshotTrackedKeys {
            let command = "defaults read \(item.domain) \(item.key) 2>/dev/null"
            guard let result = try? await shell.run(command), result.isSuccess else { continue }
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

    static func apply(presetIDs: Set<String>) async throws -> String {
        let scripts = developerPresets
            .filter { presetIDs.contains($0.id) }
            .map(\.shellScript)
        guard !scripts.isEmpty else { return "未选择任何预设" }

        let shell = ShellExecutor()
        let combined = scripts.joined(separator: "\n")
        let result = try await shell.run(combined)
        guard result.isSuccess else {
            throw MacOSDefaultsError.applyFailed(result.combinedOutput)
        }
        return "已应用 \(presetIDs.count) 项 macOS 偏好"
    }
}

enum MacOSDefaultsError: LocalizedError {
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .applyFailed(let output): return "defaults 执行失败：\(output)"
        }
    }
}

// MARK: - S12-06 Git 身份

struct GitIdentity: Sendable, Equatable {
    var name: String
    var email: String

    var isConfigured: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum GitSetupService {
    static let dotfilesGuide = """
    建议后续步骤（可选）：
    1. 使用 `gh auth login` 登录 GitHub
    2. 用 chezmoi / Mackup 备份 dotfiles
    3. 将 SSH Key 加入 GitHub / Git 托管平台
    """

    static func readIdentity() async -> GitIdentity {
        let shell = ShellExecutor()
        let name = (try? await shell.run("git config --global user.name"))?.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = (try? await shell.run("git config --global user.email"))?.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GitIdentity(name: name, email: email)
    }

    static func applyIdentity(name: String, email: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else {
            throw GitSetupError.invalidInput
        }

        let shell = ShellExecutor()
        let nameResult = try await shell.run("git config --global user.name \"\(escapeShell(trimmedName))\"")
        guard nameResult.isSuccess else { throw GitSetupError.commandFailed(nameResult.combinedOutput) }

        let emailResult = try await shell.run("git config --global user.email \"\(escapeShell(trimmedEmail))\"")
        guard emailResult.isSuccess else { throw GitSetupError.commandFailed(emailResult.combinedOutput) }
    }

    static func isGitAvailable() async -> Bool {
        let shell = ShellExecutor()
        let result = try? await shell.run("command -v git")
        return result?.isSuccess == true
    }

    private static func escapeShell(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum GitSetupError: LocalizedError {
    case invalidInput
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "请填写 Git 用户名与邮箱"
        case .commandFailed(let msg): return msg
        }
    }
}

// MARK: - S12-07 Brewfile 导入

struct BrewfileImportResult: Sendable {
    let formulae: [String]
    let casks: [String]
    let matchedTools: [DevTool]
    let unmatched: [String]
}

enum BrewfileImporter {
    static func parse(_ content: String) -> (formulae: [String], casks: [String]) {
        var formulae: [String] = []
        var casks: [String] = []

        let brewPattern = #"brew\s+\"([^\"]+)\""#
        let caskPattern = #"cask\s+\"([^\"]+)\""#

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            if let id = firstMatch(in: trimmed, pattern: brewPattern) {
                formulae.append(id)
            } else if let id = firstMatch(in: trimmed, pattern: caskPattern) {
                casks.append(id)
            }
        }
        return (formulae, casks)
    }

    static func matchTools(
        formulae: [String],
        casks: [String],
        catalog: [DevTool]
    ) -> BrewfileImportResult {
        var matched: [DevTool] = []
        var unmatched: [String] = []

        for name in formulae {
            if let tool = catalog.first(where: { $0.source.type == .formula && $0.source.identifier == name }) {
                matched.append(tool)
            } else {
                unmatched.append("brew \"\(name)\"")
            }
        }
        for name in casks {
            if let tool = catalog.first(where: { $0.source.type == .cask && $0.source.identifier == name }) {
                matched.append(tool)
            } else {
                unmatched.append("cask \"\(name)\"")
            }
        }

        var seen = Set<String>()
        matched = matched.filter { seen.insert($0.id).inserted }
        return BrewfileImportResult(
            formulae: formulae,
            casks: casks,
            matchedTools: matched,
            unmatched: unmatched
        )
    }

    static func importFromFile(content: String, catalog: [DevTool]) -> BrewfileImportResult {
        let parsed = parse(content)
        return matchTools(formulae: parsed.formulae, casks: parsed.casks, catalog: catalog)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[capture])
    }
}

// MARK: - S12-04 Bundle 分享

enum BundleShareService {
    @MainActor
    static func makeShareJSON(from viewModel: AppViewModel) throws -> String {
        let snapshot = EnvironmentSnapshotService.makeSnapshot(
            from: viewModel,
            teamName: viewModel.settings.teamBundleName,
            author: viewModel.settings.teamBundleAuthor
        )
        let data = try EnvironmentSnapshotService.encode(snapshot)
        guard let json = String(data: data, encoding: .utf8) else {
            throw BundleShareError.encodingFailed
        }
        return json
    }

    static func fetchSnapshot(from url: URL) async throws -> EnvironmentSnapshot {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BundleShareError.downloadFailed
        }
        return try EnvironmentSnapshotService.decode(from: data)
    }
}

enum BundleShareError: LocalizedError {
    case encodingFailed
    case downloadFailed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Bundle JSON 编码失败"
        case .downloadFailed: return "无法下载分享链接（请确认是 raw JSON 地址）"
        case .invalidURL: return "链接格式无效"
        }
    }
}

// MARK: - S14-07 Mackup 设置备份引导

enum MackupGuideService {
    static let homepage = URL(string: "https://github.com/lra/mackup")!
    static let installFormula = "mackup"

    static let guideText = """
    Mackup 可将 VS Code、iTerm、Raycast 等 App 的偏好设置备份到 iCloud 或 Dropbox，换机后一条命令恢复。

    常用命令：
    • mackup list     查看可备份的应用
    • mackup backup   备份到 ~/Mackup
    • mackup restore  从备份恢复（换机后）

    Kidux 不内置备份引擎，仅引导安装与使用 Mackup。
    """

    static func isInstalled() async -> Bool {
        let shell = ShellExecutor()
        let result = try? await shell.run("command -v mackup")
        guard let result, result.isSuccess else { return false }
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func install(mirror: BrewMirror) async throws -> String {
        let brew = HomebrewService()
        guard await brew.isInstalled() else { throw HomebrewError.notInstalled }
        let tool = DevTool(
            id: "mackup",
            name: "Mackup",
            description: "应用设置备份",
            category: "utilities",
            source: InstallSource(type: .formula, identifier: installFormula),
            priority: 35
        )
        return try await brew.installTool(tool, mirror: mirror)
    }
}

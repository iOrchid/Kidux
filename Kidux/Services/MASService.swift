import Foundation

enum MASError: LocalizedError {
    case notAvailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "mas-cli 未安装，请先在设置中启用 App Store 集成并安装 mas"
        case .commandFailed(let msg):
            return msg
        }
    }
}

actor MASService {
    private let shell: ShellExecutor

    init(shell: ShellExecutor = ShellExecutor()) {
        self.shell = shell
    }

    func isAvailable() async -> Bool {
        let result = try? await shell.run("command -v mas")
        return result?.isSuccess == true
    }

    func listInstalledAppIDs() async throws -> Set<String> {
        guard await isAvailable() else { return [] }
        let result = try await shell.run("mas list")
        guard result.isSuccess else { return [] }

        // 格式: "497799835  Xcode  (16.0)"
        var ids = Set<String>()
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if let id = parts.first {
                ids.insert(String(id))
            }
        }
        return ids
    }

    func isAppInstalled(appID: String) async -> Bool {
        let installed = (try? await listInstalledAppIDs()) ?? []
        return installed.contains(appID)
    }

    func install(
        appID: String,
        environment: [String: String] = [:],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard await isAvailable() else {
            throw MASError.notAvailable
        }
        let result = try await shell.run(
            "mas install \(appID)",
            environment: environment,
            onOutput: onOutput
        )
        return try await finishMASCommand(
            command: "mas install \(appID)",
            environment: environment,
            result: result,
            onOutput: onOutput
        )
    }

    struct OutdatedApp: Sendable, Hashable {
        let appID: String
        let name: String
    }

    func listOutdated() async -> [OutdatedApp] {
        guard await isAvailable() else { return [] }
        let result = try? await shell.run("mas outdated")
        guard result?.isSuccess == true else { return [] }

        var items: [OutdatedApp] = []
        for line in result?.stdout.split(separator: "\n") ?? [] {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard let appID = parts.first else { continue }
            let remainder = parts.dropFirst().joined(separator: " ")
            let name: String
            if let parenIndex = remainder.firstIndex(of: "(") {
                name = String(remainder[..<parenIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                name = remainder
            }
            items.append(OutdatedApp(appID: String(appID), name: name.isEmpty ? String(appID) : name))
        }
        return items
    }

    func upgrade(
        appID: String? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard await isAvailable() else {
            throw MASError.notAvailable
        }
        let command: String
        if let appID {
            command = "mas upgrade \(appID)"
        } else {
            command = "mas upgrade"
        }
        let result = try await shell.run(command, onOutput: onOutput)
        return try await finishMASCommand(
            command: command,
            environment: [:],
            result: result,
            onOutput: onOutput
        )
    }

    private func finishMASCommand(
        command: String,
        environment: [String: String],
        result: ShellResult,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> String {
        if result.isSuccess {
            return result.combinedOutput
        }
        if AdminShellHelper.needsElevation(result.combinedOutput) {
            onOutput?("⚠️ 需要管理员权限，正在弹出系统授权…\n")
            let admin = try await AdminShellHelper.runWithPrivileges(command: command, environment: environment)
            guard admin.isSuccess else {
                throw MASError.commandFailed(admin.combinedOutput)
            }
            return admin.combinedOutput
        }
        throw MASError.commandFailed(result.combinedOutput)
    }
}

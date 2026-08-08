import Foundation

enum ScriptRunnerError: LocalizedError {
    case scriptNotFound(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound(let name):
            return "找不到脚本: \(name)"
        case .commandFailed(let msg):
            return msg
        }
    }
}

struct ScriptRunner {
    private let shell: ShellExecutor

    init(shell: ShellExecutor = ShellExecutor()) {
        self.shell = shell
    }

    func shouldSkip(condition: String?) async -> Bool {
        guard let condition, !condition.isEmpty else { return false }
        let result = try? await shell.run(condition)
        return result?.isSuccess == true
    }

    func runBundledScript(
        named scriptName: String,
        environment: [String: String] = [:],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let scriptPath = resolveScriptPath(named: scriptName) else {
            throw ScriptRunnerError.scriptNotFound(scriptName)
        }

        let result = try await shell.run(
            "/bin/bash \"\(scriptPath)\"",
            environment: environment,
            onOutput: onOutput
        )
        guard result.isSuccess else {
            throw ScriptRunnerError.commandFailed(result.combinedOutput)
        }
        return result.combinedOutput
    }

    private func resolveScriptPath(named name: String) -> String? {
        if let url = Bundle.main.url(
            forResource: name.replacingOccurrences(of: ".sh", with: ""),
            withExtension: "sh",
            subdirectory: "scripts"
        ) {
            return url.path
        }

        // 开发期回退路径
        let devCandidate = Bundle.main.bundlePath
            .replacingOccurrences(of: "/Build/Products/Debug/Kidux.app", with: "")
            + "/Kidux/Resources/scripts/\(name)"
        if FileManager.default.fileExists(atPath: devCandidate) {
            return devCandidate
        }
        return nil
    }
}

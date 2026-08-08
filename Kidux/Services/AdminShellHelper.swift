import Foundation

/// GUI 环境下 brew 升级等需 sudo 时，通过系统授权弹窗执行
enum AdminShellHelper {
    static func needsElevation(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("sudo: a terminal is required")
            || text.contains("sudo: a password is required")
            || text.contains("need to be root")
            || (text.contains("permission denied") && text.contains("/usr/local"))
    }

    static func runWithPrivileges(
        command: String,
        environment: [String: String] = [:]
    ) async throws -> ShellResult {
        let envPrefix = environment
            .sorted { $0.key < $1.key }
            .map { key, value in
                "export \(key)=\(shellSingleQuote(value))"
            }
            .joined(separator: " ")
        let fullCommand = envPrefix.isEmpty ? command : "\(envPrefix) && \(command)"

        let escaped = appleScriptEscape(fullCommand)
        let scriptSource = "do shell script \"\(escaped)\" with administrator privileges"

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", scriptSource]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let result = ShellResult(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

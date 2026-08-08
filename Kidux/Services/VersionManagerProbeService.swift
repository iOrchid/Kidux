import Foundation

/// S16-03 mise / nvm 只读探测（不替用户切换版本）
enum VersionManagerProbeService {
    private static let probeTimeout: TimeInterval = 5

    static func probeAll() async -> [VersionManagerProfile] {
        async let mise = probeMise()
        async let nvm = probeNvm()
        return await [mise, nvm]
    }

    static func probeMise() async -> VersionManagerProfile {
        let env = ShellEnvironment.developerEnvironment()
        let shell = ShellExecutor()
        let path = await resolveExecutable(named: "mise", env: env, shell: shell)

        guard let path else {
            return VersionManagerProfile(
                kind: .mise,
                isInstalled: false,
                summaryLine: "未检测到 mise",
                detailLines: [],
                executablePath: nil
            )
        }

        let versionResult = try? await shell.run(
            "mise --version 2>/dev/null",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        let version = mergedOutput(versionResult).firstNonEmptyLine ?? "mise"

        let listResult = try? await shell.run(
            "mise list 2>/dev/null | head -n 15",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        let lines = mergedOutput(listResult)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let summary: String
        if lines.isEmpty {
            summary = version
        } else {
            summary = "\(lines.count) 个工具 · \(version)"
        }

        return VersionManagerProfile(
            kind: .mise,
            isInstalled: true,
            summaryLine: summary,
            detailLines: lines,
            executablePath: path
        )
    }

    static func probeNvm() async -> VersionManagerProfile {
        let nvmScriptPath = NSHomeDirectory() + "/.nvm/nvm.sh"
        let hasNvmInstall = FileManager.default.fileExists(atPath: nvmScriptPath)
        let env = ShellEnvironment.developerEnvironment()
        let shell = ShellExecutor()

        let script = """
        export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
        if [ -s "$NVM_DIR/nvm.sh" ]; then
          . "$NVM_DIR/nvm.sh"
          nvm current 2>/dev/null
        fi
        """

        let result = try? await shell.run(script, environment: env, timeoutSeconds: probeTimeout)
        let current = mergedOutput(result).firstNonEmptyLine ?? ""

        guard hasNvmInstall || !current.isEmpty else {
            return VersionManagerProfile(
                kind: .nvm,
                isInstalled: false,
                summaryLine: "未检测到 nvm",
                detailLines: [],
                executablePath: nil
            )
        }

        let summary: String
        if current.isEmpty || current == "none" {
            summary = "已安装 · 未激活 Node"
        } else if current == "system" {
            summary = "当前 system Node"
        } else {
            summary = "当前 \(current)"
        }

        return VersionManagerProfile(
            kind: .nvm,
            isInstalled: true,
            summaryLine: summary,
            detailLines: current.isEmpty ? [] : [current],
            executablePath: hasNvmInstall ? nvmScriptPath : nil
        )
    }

    private static func resolveExecutable(
        named command: String,
        env: [String: String],
        shell: ShellExecutor
    ) async -> String? {
        let result = try? await shell.run(
            "command -v \(command) 2>/dev/null",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        let path = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result?.isSuccess == true, let path, !path.isEmpty {
            return path
        }
        return ShellEnvironment.resolveExecutable(named: command)
    }

    private static func mergedOutput(_ result: ShellResult?) -> String {
        guard let result else { return "" }
        return [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private extension String {
    var firstNonEmptyLine: String? {
        split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

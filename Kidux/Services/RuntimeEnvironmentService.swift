import Foundation

enum RuntimeEnvironmentService {
    /// 单条探测命令默认超时，避免 docker/mysql 挂起导致环境页一直转圈。
    private static let probeTimeout: TimeInterval = 5
    private static let dockerTimeout: TimeInterval = 6
    private static let brewServicesTimeout: TimeInterval = 10

    static func scan() async -> RuntimeEnvironmentSnapshot {
        async let runtimes = probeRuntimes()
        async let services = probeLocalServices()
        async let brewServices = probeBrewServices()
        async let versionManagers = VersionManagerProbeService.probeAll()
        return RuntimeEnvironmentSnapshot(
            runtimes: await runtimes,
            services: await services,
            brewServices: await brewServices,
            versionManagers: await versionManagers,
            scannedAt: Date()
        )
    }

    private static func probeRuntimes() async -> [RuntimeProfile] {
        await withTaskGroup(of: RuntimeProfile.self) { group in
            for kind in RuntimeKind.allCases {
                group.addTask { await probeRuntime(kind) }
            }
            var results: [RuntimeProfile] = []
            for await profile in group {
                results.append(profile)
            }
            return RuntimeKind.allCases.compactMap { kind in
                results.first { $0.kind == kind }
            }
        }
    }

    private static func probeRuntime(_ kind: RuntimeKind) async -> RuntimeProfile {
        let shell = ShellExecutor()
        let env = ShellEnvironment.developerEnvironment()
        let command = kind.probeCommand
        let pathResult = try? await shell.run(
            "command -v \(command) 2>/dev/null",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        var path = pathResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if pathResult?.isSuccess != true || path?.isEmpty != false {
            path = ShellEnvironment.resolveExecutable(named: command)
        }
        guard let path, !path.isEmpty else {
            return RuntimeProfile(kind: kind, executablePath: nil, versionLine: nil)
        }

        let versionResult = try? await shell.run(
            kind.versionCommand,
            environment: env,
            timeoutSeconds: probeTimeout
        )
        let versionLine = mergedOutput(versionResult).firstNonEmptyLine
        return RuntimeProfile(kind: kind, executablePath: path, versionLine: versionLine)
    }

    private static func probeLocalServices() async -> [LocalServiceHealth] {
        await withTaskGroup(of: LocalServiceHealth.self) { group in
            for kind in LocalServiceKind.allCases {
                group.addTask { await probeService(kind) }
            }
            var results: [LocalServiceHealth] = []
            for await item in group {
                results.append(item)
            }
            return LocalServiceKind.allCases.compactMap { kind in
                results.first { $0.kind == kind }
            }
        }
    }

    private static func probeService(_ kind: LocalServiceKind) async -> LocalServiceHealth {
        switch kind {
        case .docker:
            return await probeDocker()
        case .mysql:
            return await probeMySQL()
        case .redis:
            return await probeRedis()
        }
    }

    private static func probeDocker() async -> LocalServiceHealth {
        let shell = ShellExecutor()
        let env = ShellEnvironment.developerEnvironment()
        let pathResult = try? await shell.run(
            "command -v docker 2>/dev/null",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        var path = pathResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if pathResult?.isSuccess != true || path?.isEmpty != false {
            path = ShellEnvironment.resolveExecutable(named: "docker")
        }
        let hasBinary = path?.isEmpty == false

        guard hasBinary, let path else {
            return LocalServiceHealth(kind: .docker, state: .notInstalled, detail: "未找到 docker 命令")
        }

        // Docker Desktop 未就绪时 `docker info` 极易挂死；必须限时。
        let infoResult = try? await shell.run(
            "docker info --format '{{.ServerVersion}}' 2>/dev/null",
            environment: env,
            timeoutSeconds: dockerTimeout
        )
        let version = infoResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if infoResult?.isSuccess == true, !version.isEmpty {
            return LocalServiceHealth(kind: .docker, state: .running, detail: "Server \(version)")
        }

        return LocalServiceHealth(kind: .docker, state: .unreachable, detail: "已安装但 daemon 未运行或探测超时")
    }

    private static func probeMySQL() async -> LocalServiceHealth {
        let shell = ShellExecutor()
        let env = ShellEnvironment.developerEnvironment()
        let pathResult = try? await shell.run(
            "command -v mysql 2>/dev/null",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        var path = pathResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if pathResult?.isSuccess != true || path?.isEmpty != false {
            path = ShellEnvironment.resolveExecutable(named: "mysql")
        }
        let hasClient = path?.isEmpty == false

        guard hasClient else {
            return LocalServiceHealth(kind: .mysql, state: .notInstalled, detail: "未找到 mysql 客户端")
        }

        let versionResult = try? await shell.run(
            "mysql --version 2>/dev/null",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        let version = mergedOutput(versionResult).firstNonEmptyLine ?? "MySQL 客户端"

        let pingResult = try? await shell.run(
            "mysqladmin ping -h127.0.0.1 --silent 2>/dev/null",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        if pingResult?.isSuccess == true {
            return LocalServiceHealth(kind: .mysql, state: .running, detail: version)
        }

        return LocalServiceHealth(kind: .mysql, state: .installed, detail: "\(version) · 本机未响应 ping")
    }

    private static func probeRedis() async -> LocalServiceHealth {
        let shell = ShellExecutor()
        let env = ShellEnvironment.developerEnvironment()
        let pathResult = try? await shell.run(
            "command -v redis-cli 2>/dev/null",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        var path = pathResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if pathResult?.isSuccess != true || path?.isEmpty != false {
            path = ShellEnvironment.resolveExecutable(named: "redis-cli")
        }
        let hasClient = path?.isEmpty == false

        guard hasClient else {
            return LocalServiceHealth(kind: .redis, state: .notInstalled, detail: "未找到 redis-cli")
        }

        let pingResult = try? await shell.run(
            "redis-cli ping 2>/dev/null",
            environment: env,
            timeoutSeconds: probeTimeout
        )
        let response = pingResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if pingResult?.isSuccess == true, response.caseInsensitiveCompare("PONG") == .orderedSame {
            let infoResult = try? await shell.run(
                "redis-cli INFO server 2>/dev/null | grep '^redis_version:' | head -n 1",
                environment: env,
                timeoutSeconds: probeTimeout
            )
            let detail = infoResult?.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "redis_version:", with: "Redis ")
            return LocalServiceHealth(
                kind: .redis,
                state: .running,
                detail: detail?.isEmpty == false ? detail! : "PONG"
            )
        }

        return LocalServiceHealth(kind: .redis, state: .installed, detail: "redis-cli 可用 · 服务未响应")
    }

    private static func mergedOutput(_ result: ShellResult?) -> String {
        guard let result else { return "" }
        return [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func probeBrewServices() async -> [BrewServiceItem] {
        await withTaskGroup(of: [BrewServiceItem]?.self) { group in
            group.addTask {
                await BrewMaintenanceService.listServices(mirror: .official)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(brewServicesTimeout))
                return nil
            }
            defer { group.cancelAll() }
            while let next = await group.next() {
                if let value = next {
                    return value
                }
                return []
            }
            return []
        }
    }
}

private extension String {
    var firstNonEmptyLine: String? {
        split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

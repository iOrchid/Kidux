import ArgumentParser
import Foundation

struct Bootstrap: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "从岗位 Bundle 生成 bootstrap 安装脚本",
        subcommands: [Export.self, Run.self]
    )
}

extension Bootstrap {
    struct Export: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "export",
            abstract: "生成 bootstrap.sh（等价于 bin/export-bundle.sh）"
        )

        @Argument(help: "岗位 Bundle ID，例如 fullstack_developer")
        var role: String

        @Option(name: .shortAndLong, help: "输出脚本路径")
        var output: String?

        @Flag(name: .long, help: "禁用 MAS 安装命令")
        var noMAS: Bool = false

        @Flag(name: .long, help: "不跳过已安装项")
        var noSkipInstalled: Bool = false

        @Option(name: .long, help: "仓库根目录")
        var repoRoot: String?

        mutating func run() async throws {
            let root = try repoRoot.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? RepoPaths.resolveRoot()
            let tools = try CatalogLoader.resolveTools(roleID: role, root: root)

            let outURL: URL
            if let output {
                outURL = URL(fileURLWithPath: output)
            } else {
                outURL = root
                    .appendingPathComponent("exports/bootstrap-\(role).sh")
            }

            let content = BootstrapGenerator.generate(
                tools: tools,
                root: root,
                bundleLabel: role,
                enableMAS: !noMAS,
                skipInstalled: !noSkipInstalled
            )

            try FileManager.default.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: outURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outURL.path)
            try BootstrapGenerator.copyBundledScripts(to: outURL.deletingLastPathComponent(), root: root)

            print(outURL.path)
        }
    }

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "生成并执行 bootstrap 脚本"
        )

        @Argument(help: "岗位 Bundle ID")
        var role: String

        @Option(name: .long, help: "仓库根目录")
        var repoRoot: String?

        mutating func run() async throws {
            var exportCommand = Export()
            exportCommand.role = role
            exportCommand.repoRoot = repoRoot
            try await exportCommand.run()

            let root = try repoRoot.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? RepoPaths.resolveRoot()
            let script = root.appendingPathComponent("exports/bootstrap-\(role).sh")
            fputs("执行 \(script.path) …\n", stderr)
            let result = try ShellRunner.run("bash \"\(script.path)\"")
            if !result.isSuccess {
                throw KiduxCLIError.commandFailed(result.combinedOutput)
            }
            print(result.stdout)
        }
    }
}

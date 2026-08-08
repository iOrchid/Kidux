import ArgumentParser
import Foundation

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "从快照或岗位清单安装 brew/mas 工具",
        discussion: """
        默认 dry-run 仅打印将执行的 brew 命令；加 --run 才会真正安装。
        """
    )

    @Option(name: .long, help: "从 .kidux-snapshot.json 读取 selectedToolIDs")
    var snapshot: String?

    @Option(name: .long, help: "从岗位 Bundle 安装")
    var role: String?

    @Flag(name: .long, help: "实际执行安装（默认仅预览）")
    var run: Bool = false

    @Flag(name: .long, help: "禁用 MAS")
    var noMAS: Bool = false

    @Option(name: .long, help: "仓库根目录")
    var repoRoot: String?

    mutating func run() async throws {
        let root = try repoRoot.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? RepoPaths.resolveRoot()

        let toolIDs: [String]
        if let snapshot {
            let loaded = try SnapshotCodec.load(from: URL(fileURLWithPath: snapshot))
            toolIDs = loaded.selectedToolIDs
            guard !toolIDs.isEmpty else {
                throw KiduxCLIError.invalidSnapshot("快照中无 selectedToolIDs")
            }
        } else if let role {
            toolIDs = try CatalogLoader.resolveToolIDs(roleIDs: [role], root: root)
        } else {
            throw ValidationError("请指定 --snapshot 或 --role")
        }

        let catalog = try CatalogLoader.loadCatalog(from: root)
        let tools = toolIDs.compactMap { catalog[$0] }.sorted { ($0.priority ?? 999) < ($1.priority ?? 999) }

        var commands: [String] = []
        commands.append("eval \"$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)\"")

        if !noMAS, tools.contains(where: { $0.source.type == "mas" }) {
            commands.append("command -v mas >/dev/null 2>&1 || brew install mas")
        }

        for tool in tools {
            guard let cmd = installCommand(for: tool, enableMAS: !noMAS) else { continue }
            commands.append(cmd)
        }

        if run {
            fputs("开始安装 \(tools.count) 项…\n", stderr)
            for command in commands {
                fputs("[kidux] \(command)\n", stderr)
                let result = try ShellRunner.run(command)
                if !result.isSuccess {
                    throw KiduxCLIError.commandFailed("\(command)\n\(result.combinedOutput)")
                }
            }
            print("安装完成")
        } else {
            print("# dry-run — 加 --run 执行")
            for command in commands {
                print(command)
            }
        }
    }

    private func installCommand(for tool: CatalogTool, enableMAS: Bool) -> String? {
        switch tool.source.type {
        case "formula":
            return "brew install \(tool.source.identifier)"
        case "cask":
            return "brew install --cask \(tool.source.identifier)"
        case "mas":
            guard enableMAS else { return nil }
            return "mas install \(tool.source.identifier)"
        case "script":
            return "# script: \(tool.source.identifier) — 请用 bootstrap export 复制 scripts/"
        case "link":
            return "# link: \(tool.source.identifier)"
        default:
            return nil
        }
    }
}

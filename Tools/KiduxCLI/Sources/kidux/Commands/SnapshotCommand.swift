import ArgumentParser
import Foundation

struct Snapshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "环境快照导出 / 查看 / 校验",
        subcommands: [Export.self, Show.self, Validate.self]
    )
}

extension Snapshot {
    struct Export: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "export",
            abstract: "导出 .kidux-snapshot.json（含本机 brew/git/运行时状态）"
        )

        @Option(name: .shortAndLong, help: "输出路径（默认 ./kidux-snapshot-<timestamp>.json）")
        var output: String?

        @Option(name: .long, help: "岗位 ID，逗号分隔，例如 fullstack_developer")
        var roles: String?

        @Option(name: .long, help: "备注")
        var note: String?

        @Flag(name: .long, help: "跳读本机状态采集（更快）")
        var noMachine: Bool = false

        @Option(name: .long, help: "仓库根目录（默认自动探测或 KIDUX_REPO_ROOT）")
        var repoRoot: String?

        mutating func run() async throws {
            let root = try repoRoot.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? RepoPaths.resolveRoot()
            let roleIDs = roles?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []

            let toolIDs: [String]
            if roleIDs.isEmpty {
                toolIDs = []
            } else {
                toolIDs = try CatalogLoader.resolveToolIDs(roleIDs: roleIDs, root: root)
            }

            let machineState: MachineEnvironmentState?
            if noMachine {
                machineState = nil
            } else {
                fputs("正在采集本机环境…\n", stderr)
                machineState = try MachineCapture.capture()
            }

            let snapshot = EnvironmentSnapshot(
                formatVersion: KiduxMetadata.snapshotFormatVersion,
                kiduxVersion: KiduxMetadata.cliVersion,
                exportedAt: Date(),
                selectedRoleIDs: roleIDs.sorted(),
                selectedToolIDs: toolIDs.sorted(),
                brewMirror: "official",
                enableMAS: true,
                skipInstalled: true,
                allowMultipleRoles: roleIDs.count > 1,
                note: note,
                teamName: nil,
                author: NSUserName(),
                discoverSelectedToolIDs: nil,
                machineState: machineState
            )

            let data = try SnapshotCodec.encode(snapshot)
            let outURL: URL
            if let output {
                outURL = URL(fileURLWithPath: output)
            } else {
                let stamp = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("kidux-snapshot-\(stamp).json")
            }

            try FileManager.default.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outURL)
            print(outURL.path)
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "可读摘要"
        )

        @Argument(help: "快照 JSON 路径")
        var file: String

        mutating func run() async throws {
            let snapshot = try SnapshotCodec.load(from: URL(fileURLWithPath: file))
            print(SnapshotCodec.summary(for: snapshot))
        }
    }

    struct Validate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "校验 JSON 格式与 formatVersion"
        )

        @Argument(help: "快照 JSON 路径")
        var file: String

        mutating func run() async throws {
            let snapshot = try SnapshotCodec.load(from: URL(fileURLWithPath: file))
            guard snapshot.formatVersion >= 1, snapshot.formatVersion <= KiduxMetadata.snapshotFormatVersion else {
                throw KiduxCLIError.invalidSnapshot("不支持的 formatVersion \(snapshot.formatVersion)")
            }
            print("OK · formatVersion \(snapshot.formatVersion) · \(snapshot.selectedToolIDs.count) tools")
        }
    }
}

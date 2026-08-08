import ArgumentParser
import Foundation

@main
struct KiduxCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kidux",
        abstract: "启椟 Kidux 命令行：环境快照与 bootstrap 安装脚本",
        version: KiduxMetadata.cliVersion,
        subcommands: [
            Snapshot.self,
            Bootstrap.self,
            Install.self
        ],
        defaultSubcommand: Snapshot.self
    )
}

enum KiduxMetadata {
    /// 与 Kidux MARKETING_VERSION 同步
    static let cliVersion = "2.0.0"
    static let snapshotFormatVersion = 4
}

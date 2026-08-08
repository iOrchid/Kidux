import Foundation

struct InstallSizeEstimate: Sendable, Equatable {
    let itemCount: Int
    let skippedInstalledCount: Int
    let estimatedDownloadBytes: Int64
    let estimatedInstalledBytes: Int64

    static let empty = InstallSizeEstimate(
        itemCount: 0,
        skippedInstalledCount: 0,
        estimatedDownloadBytes: 0,
        estimatedInstalledBytes: 0
    )

    var hasItems: Bool { itemCount > 0 }

    var downloadLabel: String {
        Self.formatBytes(estimatedDownloadBytes)
    }

    var installedLabel: String {
        Self.formatBytes(estimatedInstalledBytes)
    }

    /// 粗估安装耗时（分钟）
    var estimatedMinutes: Int {
        max(1, Int(ceil(Double(itemCount) / 4.0)))
    }

    var summaryLine: String {
        guard hasItems else { return "未选择可安装项" }
        var parts: [String] = [
            "预计下载约 \(downloadLabel)",
            "安装后占用约 \(installedLabel)",
            "耗时约 \(estimatedMinutes) 分钟"
        ]
        if skippedInstalledCount > 0 {
            parts.append("已跳过 \(skippedInstalledCount) 项已安装")
        }
        return parts.joined(separator: " · ")
    }

    static func estimate(
        tools: [ResolvedTool],
        snapshot: InstalledStatusSnapshot?
    ) -> InstallSizeEstimate {
        var itemCount = 0
        var skipped = 0
        var download: Int64 = 0
        var installed: Int64 = 0

        for resolved in tools where resolved.isSelected {
            let tool = resolved.tool
            guard tool.isInAppInstallable else { continue }

            if let snapshot, snapshot.state(for: tool) == .installed {
                skipped += 1
                continue
            }

            itemCount += 1
            let bytes = heuristicBytes(for: tool)
            download += bytes.download
            installed += bytes.installed
        }

        return InstallSizeEstimate(
            itemCount: itemCount,
            skippedInstalledCount: skipped,
            estimatedDownloadBytes: download,
            estimatedInstalledBytes: installed
        )
    }

    private static func heuristicBytes(for tool: DevTool) -> (download: Int64, installed: Int64) {
        switch tool.source.type {
        case .formula:
            return (45 * 1_048_576, 55 * 1_048_576)
        case .cask:
            return (180 * 1_048_576, 220 * 1_048_576)
        case .mas:
            return (120 * 1_048_576, 150 * 1_048_576)
        case .script:
            return (8 * 1_048_576, 12 * 1_048_576)
        case .link:
            return (0, 0)
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        if mb >= 1.0 {
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.0f KB", Double(bytes) / 1024.0)
    }
}

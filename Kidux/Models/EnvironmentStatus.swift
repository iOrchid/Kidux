import Foundation

struct EnvironmentStatus: Sendable {
    var macOSVersion: String
    var isMacOSSupported: Bool
    var hasCommandLineTools: Bool
    var hasHomebrew: Bool
    var homebrewPath: String?
    var architecture: String
    /// 系统盘可用空间（GB），检测失败时为 nil
    var availableDiskGB: Double?

    static let minimumDiskGB: Double = 10

    static let unsupported = EnvironmentStatus(
        macOSVersion: "Unknown",
        isMacOSSupported: false,
        hasCommandLineTools: false,
        hasHomebrew: false,
        homebrewPath: nil,
        architecture: "unknown",
        availableDiskGB: nil
    )

    var hasSufficientDiskSpace: Bool {
        guard let availableDiskGB else { return true }
        return availableDiskGB >= Self.minimumDiskGB
    }

    var diskSpaceLabel: String {
        guard let availableDiskGB else { return "未知" }
        return String(format: "%.0f GB 可用", availableDiskGB)
    }

    /// 可安全安装第三方软件：系统版本 + CLT + Homebrew + 磁盘
    var isReadyForInstall: Bool {
        isMacOSSupported && hasCommandLineTools && hasHomebrew && hasSufficientDiskSpace
    }

    /// 环境未就绪时给用户看的短说明（安装前拦截用）
    var installBlockerSummary: String? {
        var parts: [String] = []
        if !isMacOSSupported { parts.append("系统版本过低") }
        if !hasCommandLineTools { parts.append("未装命令行工具（CLT / git）") }
        if !hasHomebrew { parts.append("未装 Homebrew") }
        if !hasSufficientDiskSpace { parts.append("磁盘空间不足（\(diskSpaceLabel)）") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "；")
    }
}

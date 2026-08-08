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

    var isReadyForInstall: Bool {
        isMacOSSupported && hasHomebrew && hasSufficientDiskSpace
    }
}

import Foundation

struct EnvironmentChecker {
    private let shell = ShellExecutor()

    func check() async -> EnvironmentStatus {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let arch = await currentArchitecture()
        let supported = isMacOSSupported()
        let hasCLT = await hasCommandLineTools()
        let brewPath = await detectHomebrewPath()
        let diskGB = availableDiskSpaceGB()

        return EnvironmentStatus(
            macOSVersion: version,
            isMacOSSupported: supported,
            hasCommandLineTools: hasCLT,
            hasHomebrew: brewPath != nil,
            homebrewPath: brewPath,
            architecture: arch,
            availableDiskGB: diskGB
        )
    }

    private func availableDiskSpaceGB() -> Double? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home),
              let freeBytes = attrs[.systemFreeSize] as? Int64 else {
            return nil
        }
        return Double(freeBytes) / 1_073_741_824.0
    }

    private func isMacOSSupported() -> Bool {
        if #available(macOS 14.0, *) {
            return true
        }
        return false
    }

    private func currentArchitecture() async -> String {
        let result = try? await shell.run("uname -m")
        return result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    private func hasCommandLineTools() async -> Bool {
        let result = try? await shell.run("xcode-select -p 2>/dev/null")
        return result?.isSuccess == true
    }

    private func detectHomebrewPath() async -> String? {
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let result = try? await shell.run("command -v brew")
        guard result?.isSuccess == true else { return nil }
        return result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

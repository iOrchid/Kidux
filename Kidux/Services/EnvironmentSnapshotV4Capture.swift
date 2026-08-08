import Foundation

/// S15-01 — 快照 v4 扩展采集（MAS · macOS defaults · shell）
enum EnvironmentSnapshotV4Capture {
    static func captureMASAppIDs() async -> [String] {
        let mas = MASService()
        guard await mas.isAvailable() else { return [] }
        let ids = (try? await mas.listInstalledAppIDs()) ?? []
        return ids.sorted()
    }

    static func captureMacOSDefaults() async -> [MacOSDefaultSnapshotEntry] {
        await MacOSDefaultsService.captureSnapshotEntries()
    }

    static func captureShellEnvironment() async -> ShellEnvironmentSnapshot {
        let shell = ShellExecutor()
        let loginShell = (try? await shell.run("printenv SHELL"))?
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        let pathRaw = (try? await shell.run("printenv PATH"))?
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pathPreview = pathRaw
            .split(separator: ":", omittingEmptySubsequences: false)
            .prefix(20)
            .map(String.init)

        let home = FileManager.default.homeDirectoryForCurrentUser
        let profileCandidates = [".zprofile", ".zshrc", ".bash_profile", ".bashrc", ".profile", ".config/fish/config.fish"]
        let present = profileCandidates.filter { relativePath in
            FileManager.default.fileExists(atPath: home.appendingPathComponent(relativePath).path)
        }

        return ShellEnvironmentSnapshot(
            loginShell: loginShell,
            pathPreview: pathPreview,
            profileFilesPresent: present.sorted()
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

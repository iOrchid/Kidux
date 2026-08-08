import Foundation
import AppKit
import UniformTypeIdentifiers

/// S20-12 — 一键导出匿名化诊断包（供排查；不含 API Key）
enum DiagnosticExportService {
    enum ExportError: LocalizedError {
        case writeFailed
        case zipFailed

        var errorDescription: String? {
            switch self {
            case .writeFailed: return "无法写入诊断文件"
            case .zipFailed: return "压缩诊断包失败"
            }
        }
    }

    @MainActor
    static func exportPanel(from viewModel: AppViewModel) async {
        do {
            let zipURL = try await buildZip(from: viewModel)
            let panel = NSSavePanel()
            panel.title = "导出诊断包"
            panel.nameFieldStringValue = "Kidux-diagnostics-\(AppInfo.marketingVersion).zip"
            panel.allowedContentTypes = [.zip]
            guard panel.runModal() == .OK, let dest = panel.url else {
                try? FileManager.default.removeItem(at: zipURL.deletingLastPathComponent())
                return
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: zipURL, to: dest)
            try? FileManager.default.removeItem(at: zipURL.deletingLastPathComponent())
            viewModel.extendedCatalogStatusMessage = "诊断包已导出：\(dest.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            viewModel.extendedCatalogStatusMessage = "诊断包导出失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    static func buildZip(from viewModel: AppViewModel) async throws -> URL {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("kidux-diag-\(UUID().uuidString)", isDirectory: true)
        let contentDir = tempRoot.appendingPathComponent("Kidux-diagnostics", isDirectory: true)
        try fm.createDirectory(at: contentDir, withIntermediateDirectories: true)

        try writeManifest(to: contentDir.appendingPathComponent("manifest.json"))
        try writeSettingsRedacted(from: viewModel, to: contentDir.appendingPathComponent("settings-redacted.json"))
        try writeInstallHistory(to: contentDir.appendingPathComponent("install-history.json"))
        try await writeEnvironmentProbe(to: contentDir.appendingPathComponent("environment.txt"), viewModel: viewModel)
        try writeRuntimeNotes(from: viewModel, to: contentDir.appendingPathComponent("runtime-notes.txt"))
        try writeDiscoverRuntime(from: viewModel, to: contentDir.appendingPathComponent("discover-runtime.txt"))
        try await copyDiagnosticsEvents(to: contentDir.appendingPathComponent("events.jsonl"))

        let zipURL = tempRoot.appendingPathComponent("Kidux-diagnostics.zip")
        try await zip(directory: contentDir, to: zipURL)
        return zipURL
    }

    private static func writeManifest(to url: URL) throws {
        let info: [String: Any] = [
            "app": BrandInfo.displayNameEN,
            "version": AppInfo.marketingVersion,
            "build": AppInfo.buildNumber,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "arch": {
                #if arch(arm64)
                return "arm64"
                #else
                return "x86_64"
                #endif
            }(),
            "note": "Anonymized diagnostics. API keys and emails are redacted."
        ]
        let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    private static func writeSettingsRedacted(from viewModel: AppViewModel, to url: URL) throws {
        let s = viewModel.settings
        let dict: [String: Any] = [
            "brewMirror": s.brewMirror.rawValue,
            "enableMAS": s.enableMAS,
            "skipInstalled": s.skipInstalled,
            "allowMultipleRoles": s.allowMultipleRoles,
            "offlineMode": s.offlineMode,
            "interactionMode": s.interactionMode.rawValue,
            "enableCloudAI": s.enableCloudAI,
            "aiProvider": s.aiProvider.rawValue,
            "hasAIAPIKey": s.hasAIAPIKey,
            "aiAPIKey": s.hasAIAPIKey ? "[REDACTED]" : "",
            "scheduledBrewUpdateEnabled": s.scheduledBrewUpdateEnabled,
            "weeklyHealthDigestEnabled": s.weeklyHealthDigestEnabled,
            "indexCatalogInSpotlight": s.indexCatalogInSpotlight,
            "teamBundleName": s.teamBundleName,
            "teamBundleAuthor": redactPerson(s.teamBundleAuthor)
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    private static func writeInstallHistory(to url: URL) throws {
        let entries = InstallHistoryStore.shared.entries.prefix(30).map { entry -> [String: Any] in
            [
                "date": ISO8601DateFormatter().string(from: entry.date),
                "roles": entry.roleNames,
                "toolCount": entry.toolCount,
                "summary": entry.summary,
                "source": entry.source.rawValue
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: Array(entries), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    private static func writeEnvironmentProbe(to url: URL, viewModel: AppViewModel) async throws {
        let shell = ShellExecutor()
        var lines: [String] = []
        lines.append("=== Kidux environment probe ===")
        lines.append("Date: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        if let brew = try? await shell.run("command -v brew && brew --version | head -n 3") {
            lines.append("-- brew --")
            lines.append(brew.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }
        if let doctor = try? await shell.run("brew doctor 2>&1 | head -n 40") {
            lines.append("-- brew doctor (truncated) --")
            lines.append(redactSecrets(doctor.combinedOutput))
            lines.append("")
        }

        lines.append("-- app state --")
        lines.append("outdatedCount: \(viewModel.outdatedCount)")
        lines.append("selectedRoles: \(Array(viewModel.selectedRoles).sorted().joined(separator: ","))")
        lines.append("hasDriftBaseline: \(viewModel.settings.loadDriftBaseline() != nil)")
        if let report = viewModel.environmentDriftReport {
            lines.append("drift: \(report.summaryLine)")
        }
        lines.append("brewServices: \(viewModel.brewServices.count)")

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func writeRuntimeNotes(from viewModel: AppViewModel, to url: URL) throws {
        let lines: [String] = [
            "statusMessage: \(viewModel.extendedCatalogStatusMessage ?? "(none)")",
            "updateCheckMessage: \(viewModel.updateCheckMessage ?? "(none)")",
            "isCheckingUpdates: \(viewModel.isCheckingUpdates)",
            "teamBundleFormat: \(TeamBundlePayload.currentFormat) v\(TeamBundlePayload.currentVersion)"
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func writeDiscoverRuntime(from viewModel: AppViewModel, to url: URL) throws {
        let loadState: String
        switch viewModel.brewTrendingLoadState {
        case .idle: loadState = "idle"
        case .loading: loadState = "loading"
        case .success(let items): loadState = "success(\(items.count))"
        case .failed(let message): loadState = "failed(\(message))"
        }
        let lines: [String] = [
            "discoverMode: \(viewModel.discoverMode.rawValue)",
            "trendingWindowDays: \(viewModel.settings.trendingWindowDays.rawValue)",
            "brewTrendingLoadState: \(loadState)",
            "brewTrendingItems: \(viewModel.brewTrendingItems.count)",
            "brewSearchResults: \(viewModel.brewSearchResults.count)",
            "isSearchingBrew: \(viewModel.isSearchingBrew)",
            "discoverSearchTextLength: \(viewModel.discoverSearchText.count)",
            "eventsLog: \(DiagnosticsEventLog.eventsFileURL.path)"
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func copyDiagnosticsEvents(to url: URL) async throws {
        if let source = await DiagnosticsEventLog.snapshotEventsFile() {
            try FileManager.default.copyItem(at: source, to: url)
        } else {
            try "".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func zip(directory: URL, to zipURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", directory.path, zipURL.path]
                    try process.run()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: zipURL.path) else {
                        throw ExportError.zipFailed
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func redactPerson(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("@") { return "[REDACTED_EMAIL]" }
        return trimmed
    }

    private static func redactSecrets(_ text: String) -> String {
        var result = text
        // crude email redaction
        if let regex = try? NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[REDACTED_EMAIL]")
        }
        return result
    }
}

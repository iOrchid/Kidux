import AppKit
import Foundation

/// S20-08 — AppleScript / OSA 命令（tell application "启椟" …）
///
/// 示例：
/// ```applescript
/// tell application "启椟" to install role "frontend"
/// tell application "启椟" to select role "backend_developer"
/// tell application "启椟" to dry run role "fullstack"
/// tell application "启椟" to search catalog "docker"
/// ```

@objc(KiduxInstallRoleCommand)
final class KiduxInstallRoleCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let query = resolvedQuery() else {
            scriptErrorNumber = NSRequiredArgumentsMissingScriptError
            scriptErrorString = "请提供岗位名称或 ID"
            return nil
        }
        runAsync { await $0.performRoleInstallIntent(query: query, previewOnly: false) }
        return "Installing role: \(query)"
    }
}

@objc(KiduxSelectRoleCommand)
final class KiduxSelectRoleCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let query = resolvedQuery() else {
            scriptErrorNumber = NSRequiredArgumentsMissingScriptError
            scriptErrorString = "请提供岗位名称或 ID"
            return nil
        }
        runAsync { viewModel in
            guard let role = viewModel.matchRole(query: query) else {
                return "未找到岗位「\(query)」"
            }
            viewModel.selectRole(role)
            viewModel.navigateTo(.roles)
            viewModel.currentScreen = .bundleDetail
            return "已选择岗位「\(role.name)」"
        }
        return "Selecting role: \(query)"
    }
}

@objc(KiduxDryRunRoleCommand)
final class KiduxDryRunRoleCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let query = resolvedQuery() else {
            scriptErrorNumber = NSRequiredArgumentsMissingScriptError
            scriptErrorString = "请提供岗位名称或 ID"
            return nil
        }
        runAsync { await $0.performRoleInstallIntent(query: query, previewOnly: true) }
        return "Dry-run role: \(query)"
    }
}

@objc(KiduxSearchCatalogCommand)
final class KiduxSearchCatalogCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let query = resolvedQuery() else {
            scriptErrorNumber = NSRequiredArgumentsMissingScriptError
            scriptErrorString = "请提供搜索关键词"
            return nil
        }
        runAsync { viewModel in
            viewModel.openDiscoverSearch(query: query)
            return "已搜索「\(query)」"
        }
        return "Searching: \(query)"
    }
}

private extension NSScriptCommand {
    func resolvedQuery() -> String? {
        if let text = directParameter as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let args = evaluatedArguments as? [String: Any] {
            for key in ["role", "query", "q", "Keyword", "Role"] {
                if let text = args[key] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    func runAsync(_ work: @escaping @MainActor (AppViewModel) async -> String) {
        Task { @MainActor in
            do {
                let viewModel = try AppIntentBridge.shared.requireViewModel()
                let message = await work(viewModel)
                viewModel.extendedCatalogStatusMessage = message
            } catch {
                NSLog("Kidux scripting error: \(error.localizedDescription)")
            }
        }
    }
}

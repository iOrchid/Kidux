import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

extension AppViewModel {
    func toggleRole(_ roleID: String) {
        if settings.allowMultipleRoles {
            if selectedRoles.contains(roleID) {
                selectedRoles.remove(roleID)
            } else {
                selectedRoles.insert(roleID)
            }
        } else {
            // 默认互斥单选
            if selectedRoles.contains(roleID) {
                selectedRoles.remove(roleID)
            } else {
                selectedRoles = [roleID]
            }
        }
        refreshResolvedTools()
    }

    var selectedRoleName: String? {
        guard let id = selectedRoles.first else { return nil }
        return bundleManager.roles.first { $0.id == id }?.name
    }

    func refreshResolvedTools() {
        let selected = bundleManager.roles.filter { selectedRoles.contains($0.id) }
        resolvedTools = bundleManager.resolveTools(for: selected)
        let rawSteps = bundleManager.resolvePostInstallSteps(for: selected)
        postInstallSteps = ShellPreferenceService.adaptPostInstall(
            rawSteps,
            preferred: settings.preferredShell
        )

        // Fish 偏好时自动勾选 / 注入 fish formula
        if ShellPreferenceService.effectiveShell(from: settings.preferredShell) == .fish {
            if let index = resolvedTools.firstIndex(where: { $0.id == "fish" }) {
                resolvedTools[index].isSelected = true
            } else if let fish = catalogTool(id: "fish") {
                resolvedTools.append(
                    ResolvedTool(tool: fish, isRequired: false, isSelected: true)
                )
            }
        }
    }

    func setPreferredShell(_ shell: PreferredShell) {
        settings.preferredShell = shell
        refreshResolvedTools()
        if ShellPreferenceService.effectiveShell(from: shell) == .fish {
            discoverSelectedTools.insert("fish")
        }
        extendedCatalogStatusMessage = "终端 Shell 偏好已设为：\(shell.displayName)"
    }

    func installState(for toolID: String) -> ToolInstallState {
        guard let tool = resolvedTools.first(where: { $0.id == toolID })?.tool,
              let snapshot = installedSnapshot else {
            return .unknown
        }
        return snapshot.state(for: tool)
    }

    func toggleToolSelection(_ toolID: String) {
        guard let index = resolvedTools.firstIndex(where: { $0.id == toolID }) else { return }
        guard !resolvedTools[index].isRequired else { return }
        resolvedTools[index].isSelected.toggle()
    }

    var selectedToolCount: Int {
        resolvedTools.filter(\.isSelected).count
    }

    var cliToolCount: Int {
        resolvedTools.filter { $0.isSelected && $0.tool.resolvedKind == .cli }.count
    }

    var guiToolCount: Int {
        resolvedTools.filter { $0.isSelected && $0.tool.resolvedKind == .gui }.count
    }

    func bootstrapScriptContent() -> String {
        BootstrapScriptGenerator().generate(
            tools: resolvedTools,
            postInstallSteps: postInstallSteps,
            mirror: settings.brewMirror,
            enableMAS: settings.enableMAS,
            skipInstalled: settings.skipInstalled
        )
    }

    func exportBootstrapScript() {
        let content = bootstrapScriptContent()
        let panel = NSSavePanel()
        panel.title = "导出安装脚本"
        panel.nameFieldStringValue = "bootstrap.sh"
        panel.allowedContentTypes = [UTType.shellScript]
        panel.canCreateDirectories = true
        panel.message = "生成无 GUI 一键安装脚本；请将 \(BrandInfo.displayNameEN)/Resources/scripts/ 目录放在同级的 scripts/ 文件夹"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        } catch {
            NSLog("导出失败: \(error.localizedDescription)")
        }
    }

    func exportMigrationChecklist() {
        Task {
            await scanInstalledStatus(force: true)
            await compareEnvironmentDrift(force: true)

            let roleNames = bundleManager.roles
                .filter { selectedRoles.contains($0.id) }
                .map(\.name)
            let content = MigrationChecklistExporter.generate(
                MigrationChecklistExporter.Input(
                    roleNames: roleNames,
                    selectedTools: resolvedTools,
                    postInstallSteps: postInstallSteps,
                    driftReport: environmentDriftReport,
                    driftBaselineLabel: hasEnvironmentDriftBaseline ? environmentDriftBaselineLabel : nil,
                    installedSnapshot: installedSnapshot,
                    mackupInstalled: mackupInstalled
                )
            )

            let panel = NSSavePanel()
            panel.title = "导出换机清单"
            let roleSuffix = roleNames.first?.replacingOccurrences(of: " ", with: "-") ?? "checklist"
            panel.nameFieldStringValue = "kidux-checklist-\(roleSuffix).md"
            panel.allowedContentTypes = [.plainText]
            panel.canCreateDirectories = true
            panel.message = "Markdown 换机待办：岗位工具、漂移 diff、手动项与 Mackup 引导"

            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                extendedCatalogStatusMessage = "换机清单已导出"
            } catch {
                extendedCatalogStatusMessage = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    func proceedToBundleDetail() {
        refreshResolvedTools()
        selectedTab = .roles
        currentScreen = .bundleDetail
        Task { await scanInstalledStatus() }
    }

    func startInstallation() async {
        selectedTab = .roles
        currentScreen = .installation
        if installedSnapshot == nil {
            await scanInstalledStatus()
        }
        publishWidgetSnapshot()
        await installManager.startInstallation(
            tools: resolvedTools,
            postInstallSteps: postInstallSteps,
            mirror: settings.brewMirror,
            enableMAS: settings.enableMAS,
            skipInstalled: settings.skipInstalled,
            snapshot: installedSnapshot
        )
        await scanInstalledStatus(force: true)
        recordInstallCompletionSummary()
        notifyInstallFinishedIfNeeded()
        publishWidgetSnapshot()
        currentScreen = (installManager.summary?.failed ?? 0) > 0 ? .installation : .complete
    }

    func retryInstallTask(_ taskID: String) async {
        await installManager.retryTask(
            taskID,
            mirror: settings.brewMirror,
            enableMAS: settings.enableMAS
        )
        await scanInstalledStatus(force: true)
    }

    func cancelInstallation() async {
        await installManager.requestCancel()
    }

    func resumeInstallation() async {
        if installedSnapshot == nil {
            await scanInstalledStatus()
        }
        selectedTab = .roles
        currentScreen = .installation
        await installManager.resumeInstallation(
            mirror: settings.brewMirror,
            enableMAS: settings.enableMAS,
            skipInstalled: settings.skipInstalled,
            snapshot: installedSnapshot
        )
        await scanInstalledStatus(force: true)
        recordInstallCompletionSummary()
        currentScreen = installManager.canResumeInstallation ? .installation : .complete
        notifyInstallFinishedIfNeeded()
    }

    func resumeDiscoverInstallation() async {
        if installedSnapshot == nil {
            await scanInstalledStatus()
        }
        showDiscoverInstallSheet = true
        await Task.yield()
        await installManager.resumeInstallation(
            mirror: settings.brewMirror,
            enableMAS: settings.enableMAS,
            skipInstalled: settings.skipInstalled,
            snapshot: installedSnapshot
        )
        await scanInstalledStatus(force: true)
        recordInstallCompletionSummary(source: .discover)
        notifyInstallFinishedIfNeeded()
    }

    func skipRemainingInstallTasks() {
        installManager.skipRemainingTasks()
    }

    func toggleInteractionMode(to mode: AppInteractionMode? = nil) {
        let next = mode ?? (activeInteractionMode == .classic ? AppInteractionMode.ai : .classic)
        guard next != activeInteractionMode else { return }

        if next == .ai, aiMessages.isEmpty {
            aiMessages = [AIAssistantService.welcomeMessage(hasAPIKey: settings.hasAIAPIKey)]
        }
        activeInteractionMode = next
    }

}

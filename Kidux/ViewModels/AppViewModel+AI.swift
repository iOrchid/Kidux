import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

extension AppViewModel {
    func sendAIMessage(_ text: String) {
        aiGenerationTask?.cancel()
        aiGenerationTask = Task { await sendAIMessageAsync(text) }
    }

    func cancelAIGeneration() {
        aiGenerationTask?.cancel()
        aiGenerationTask = nil
        aiIsThinking = false
        aiIsStreaming = false
        if let idx = aiMessages.lastIndex(where: { $0.isStreaming }) {
            aiMessages[idx].isStreaming = false
            if aiMessages[idx].text.isEmpty {
                aiMessages.remove(at: idx)
            }
        }
    }

    func resetAIConversation() {
        cancelAIGeneration()
        aiMessages = [AIAssistantService.welcomeMessage(hasAPIKey: settings.hasAIAPIKey)]
        aiSuggestedFollowUps = []
    }

    /// 根据 NL 输入预选岗位 / 软件（规则层编排）
    @discardableResult
    func applyNLInstallPlan(from input: String) -> NLInstallPlan? {
        guard let plan = AIInstallOrchestrator.plan(
            input: input,
            roles: bundleManager.roles,
            catalog: Array(bundleManager.catalog.values)
        ) else { return nil }
        applyNLInstallPlan(plan)
        return plan
    }

    func applyNLInstallPlan(_ plan: NLInstallPlan) {
        if let role = plan.matchedRole {
            if settings.allowMultipleRoles {
                selectedRoles.insert(role.id)
            } else {
                selectedRoles = [role.id]
            }
            refreshResolvedTools()
            currentScreen = .bundleDetail
        }

        if !plan.matchedTools.isEmpty {
            for tool in plan.matchedTools {
                discoverSelectedTools.insert(tool.id)
            }
        }
    }

    /// FM → 云端 → 规则
    func resolveNLInstallPlan(from input: String) async -> NLInstallPlan? {
        var plan: NLInstallPlan?

        if AIInstallOrchestrator.looksLikeInstallIntent(input) {
            plan = try? await AppleIntelligenceSupport.planInstallIntent(
                input: input,
                roles: bundleManager.roles,
                catalog: Array(bundleManager.catalog.values)
            )

            if plan == nil,
               !settings.offlineMode,
               settings.enableCloudAI,
               settings.hasAIAPIKey {
                plan = try? await AIInstallOrchestrator.planWithLLM(
                    input: input,
                    roles: bundleManager.roles,
                    catalog: Array(bundleManager.catalog.values),
                    apiKey: settings.aiAPIKey,
                    model: settings.aiModel,
                    baseURL: settings.effectiveBaseURL
                )
            }
        }

        if plan == nil {
            plan = AIInstallOrchestrator.plan(
                input: input,
                roles: bundleManager.roles,
                catalog: Array(bundleManager.catalog.values)
            )
        }

        if let plan {
            applyNLInstallPlan(plan)
        }
        return plan
    }

    func triggerNLInstallIfNeeded(_ plan: NLInstallPlan) async {
        guard plan.autoInstall else { return }

        if plan.matchedRole != nil {
            navigateTo(.roles)
            currentScreen = .bundleDetail
            installManager.beginInteractiveSession(
                tools: resolvedTools.filter(\.isSelected),
                postInstallSteps: postInstallSteps
            )
            await startInstallation()
            return
        }

        let installable = plan.matchedTools.filter(\.isInAppInstallable)
        guard !installable.isEmpty else { return }
        navigateTo(.discover)
        await installDiscoverTools(installable)
    }

    func reloadCatalogData() {
        bundleManager.load()
        cachedAllCatalogTools = nil
        cachedCategoryCounts = [:]
        cachedSourceSummary = nil
        lastCatalogFilterKey = ""
        cachedFilteredTools = []
    }

    func importExtendedCatalog(from url: URL) async {
        do {
            let count = try ExtendedCatalogStore.importFrom(url)
            reloadCatalogData()
            extendedCatalogStatusMessage = "已导入 \(count) 款扩展软件到本地目录"
        } catch {
            extendedCatalogStatusMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func clearExtendedCatalog() async {
        do {
            try ExtendedCatalogStore.clear()
            reloadCatalogData()
            extendedCatalogStatusMessage = "已清除扩展目录"
        } catch {
            extendedCatalogStatusMessage = "清除失败：\(error.localizedDescription)"
        }
    }

    func clearIconDiskCache() async {
        await ToolIconService.shared.clearDiskCache()
        extendedCatalogStatusMessage = "图标磁盘缓存已清除"
    }

    func analyzeInstallFailuresWithAI() {
        let logs = installManager.tasks
            .filter { $0.status == .failed }
            .map { task -> String in
                var block = "【\(task.displayName)】"
                if let err = task.errorMessage { block += "\n\(err)" }
                if !task.log.isEmpty { block += "\n\(task.log)" }
                return block
            }
            .joined(separator: "\n\n---\n\n")
        guard !logs.isEmpty else { return }

        navigateTo(.assistant)
        aiMessages.append(AIChatMessage(role: .system, text: "正在分析安装失败日志…"))

        Task { @MainActor in
            var reply: AIAssistantReply?

            reply = try? await AppleIntelligenceSupport.diagnoseInstallFailures(logs: logs)

            if reply == nil,
               !settings.offlineMode,
               settings.enableCloudAI,
               settings.hasAIAPIKey {
                reply = try? await InstallDiagnosisService.diagnoseWithLLM(
                    logs: logs,
                    apiKey: settings.aiAPIKey,
                    model: settings.aiModel,
                    baseURL: settings.effectiveBaseURL
                )
            }

            let resolved = reply ?? InstallDiagnosisService.diagnoseRules(logs)
            if let idx = aiMessages.lastIndex(where: { $0.role == .system && $0.text.hasPrefix("正在分析") }) {
                aiMessages.remove(at: idx)
            }
            aiMessages.append(AIChatMessage(
                role: .assistant,
                text: resolved.text,
                actionLabel: resolved.actionLabel,
                actionTab: resolved.actionTab
            ))
            aiSuggestedFollowUps = resolved.suggestedFollowUps
        }
    }

    func testAIConnection() {
        guard settings.hasAIAPIKey else {
            aiConnectionTestResult = "请先填写 API Key"
            return
        }
        aiConnectionTestInProgress = true
        aiConnectionTestResult = nil
        Task {
            defer { aiConnectionTestInProgress = false }
            do {
                let client = SiliconFlowClient()
                let reply = try await client.testConnection(
                    apiKey: settings.aiAPIKey,
                    model: settings.aiModel,
                    baseURL: settings.effectiveBaseURL
                )
                aiConnectionTestResult = "连接成功：\(reply.prefix(40))"
            } catch {
                aiConnectionTestResult = "连接失败：\(error.localizedDescription)"
            }
        }
    }

    var aiStatusSummary: String {
        if settings.enableCloudAI, settings.hasAIAPIKey {
            let stream = settings.aiStreamEnabled ? "流式" : "完整"
            return "\(settings.aiProvider.displayName) · \(displayModelName(settings.aiModel)) · \(stream)"
        }
        return "本地规则引擎"
    }

    func displayModelName(_ id: String) -> String {
        settings.aiProvider.resolvedModelPresets(customModel: id).first(where: { $0.id == id })?.name
            ?? id.split(separator: "/").last.map(String.init)
            ?? id
    }

    func sendAIMessageAsync(_ text: String) async {
        aiMessages.append(AIChatMessage(role: .user, text: text))
        aiIsThinking = true
        aiSuggestedFollowUps = []
        defer {
            aiIsThinking = false
            aiIsStreaming = false
        }

        if settings.enableCloudAI, settings.hasAIAPIKey {
            do {
                try Task.checkCancellation()
                let params = AIChatParameters(
                    model: settings.aiModel,
                    temperature: settings.aiTemperature,
                    maxTokens: settings.aiMaxTokens,
                    stream: false,
                    baseURL: settings.effectiveBaseURL
                )
                let agentResult = try await AIFunctionExecutor.run(
                    userInput: text,
                    viewModel: self,
                    apiKey: settings.aiAPIKey,
                    parameters: params
                )
                aiMessages.append(AIChatMessage(
                    role: .assistant,
                    text: agentResult.text,
                    actionLabel: agentResult.actionLabel,
                    actionTab: agentResult.actionTab,
                    recommendedToolIDs: agentResult.recommendedToolIDs
                ))
                aiSuggestedFollowUps = agentResult.suggestedFollowUps
                return
            } catch is CancellationError {
                return
            } catch {
                if let idx = aiMessages.lastIndex(where: { $0.isStreaming }) {
                    aiMessages.remove(at: idx)
                }
                aiMessages.append(AIChatMessage(
                    role: .system,
                    text: "Agent 模式暂时不可用（\(error.localizedDescription)），已切换本地助手。"
                ))
            }
        }

        let nlPlan = await resolveNLInstallPlan(from: text)

        if settings.enableCloudAI, settings.hasAIAPIKey {
            do {
                try Task.checkCancellation()
                let client = SiliconFlowClient()
                var apiMessages: [(role: String, content: String)] = [
                    ("system", AIAssistantService.systemPrompt(for: self))
                ]
                for message in aiMessages.suffix(10) where message.role != .system && !message.isStreaming {
                    let role = message.role == .user ? "user" : "assistant"
                    apiMessages.append((role, message.text))
                }

                let params = AIChatParameters(
                    model: settings.aiModel,
                    temperature: settings.aiTemperature,
                    maxTokens: settings.aiMaxTokens,
                    stream: settings.aiStreamEnabled,
                    baseURL: settings.effectiveBaseURL
                )

                let assistantID: UUID?
                if settings.aiStreamEnabled {
                    let id = UUID()
                    aiMessages.append(AIChatMessage(id: id, role: .assistant, text: "", isStreaming: true))
                    assistantID = id
                    aiIsStreaming = true
                } else {
                    assistantID = nil
                }

                let response: String
                if settings.aiStreamEnabled, let assistantID {
                    response = try await client.chatStream(
                        apiKey: settings.aiAPIKey,
                        messages: apiMessages,
                        parameters: params
                    ) { [weak self] delta in
                        Task { @MainActor in
                            guard let self,
                                  let idx = self.aiMessages.firstIndex(where: { $0.id == assistantID })
                            else { return }
                            self.aiMessages[idx].text += delta
                            self.aiStreamRevision += 1
                        }
                    }
                } else {
                    response = try await client.chat(
                        apiKey: settings.aiAPIKey,
                        messages: apiMessages,
                        parameters: params
                    )
                }

                try Task.checkCancellation()

                let enriched = AIAssistantService.enrichLLMResponse(response, userInput: text, nlPlan: nlPlan)
                if let assistantID, let idx = aiMessages.firstIndex(where: { $0.id == assistantID }) {
                    aiMessages[idx].text = enriched.text
                    aiMessages[idx].isStreaming = false
                    aiMessages[idx].actionLabel = enriched.actionLabel
                    aiMessages[idx].actionTab = enriched.actionTab
                } else {
                    aiMessages.append(AIChatMessage(
                        role: .assistant,
                        text: enriched.text,
                        actionLabel: enriched.actionLabel,
                        actionTab: enriched.actionTab
                    ))
                }
                aiSuggestedFollowUps = enriched.suggestedFollowUps
                if let nlPlan { await triggerNLInstallIfNeeded(nlPlan) }
                return
            } catch is CancellationError {
                return
            } catch {
                if let idx = aiMessages.lastIndex(where: { $0.isStreaming }) {
                    aiMessages.remove(at: idx)
                }
                aiMessages.append(AIChatMessage(
                    role: .system,
                    text: "云端 AI 暂时不可用（\(error.localizedDescription)），已使用本地助手回答。"
                ))
            }
        }

        let reply = AIAssistantService.reply(to: text, nlPlan: nlPlan)
        aiMessages.append(AIChatMessage(
            role: .assistant,
            text: reply.text,
            actionLabel: reply.actionLabel,
            actionTab: reply.actionTab
        ))
        aiSuggestedFollowUps = reply.suggestedFollowUps
        if let nlPlan { await triggerNLInstallIfNeeded(nlPlan) }

        // 无 Key 时：本地规则答完后补一句配置引导（避免用户以为 AI「坏了」）
        if !settings.hasAIAPIKey || !settings.enableCloudAI {
            let alreadyTipped = aiMessages.contains {
                $0.opensAISettings && $0.text.contains("刚才用的是")
            }
            if !alreadyTipped {
                aiMessages.append(AIAssistantService.missingAPIKeyTip())
            }
        }
    }

    func openInstalledTool(_ tool: DevTool) {
        switch tool.source.type {
        case .cask, .mas:
            if let app = viewModelLocalAppMatch(for: tool) {
                NSWorkspace.shared.open(app)
                return
            }
            NSWorkspace.shared.launchApplication(tool.name)
        case .link:
            Task { await openExternalLink(for: tool) }
        case .formula, .script:
            break
        }
    }

    func viewModelLocalAppMatch(for tool: DevTool) -> URL? {
        let names = [tool.name, tool.id.replacingOccurrences(of: "-", with: " ")]
        for app in localApplications {
            if names.contains(where: { $0.caseInsensitiveCompare(app.name) == .orderedSame }) {
                return URL(fileURLWithPath: app.path)
            }
        }
        return nil
    }

}

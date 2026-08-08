import Foundation

struct NLInstallPlan: Sendable {
    let matchedRole: RoleBundle?
    let matchedTools: [DevTool]
    let summary: String
    /// 用户明确要求「直接安装 / 一键安装」时为 true
    let autoInstall: Bool
}

/// 自然语言 → 岗位 / 软件匹配（规则层，v1.0）
enum AIInstallOrchestrator {
    struct NLInstallPayload: Sendable {
        var roleID: String?
        var toolIDs: [String]?
        var autoInstall: Bool?
    }

    static func plan(
        from payload: NLInstallPayload,
        roles: [RoleBundle],
        catalog: [DevTool],
        summaryPrefix: String,
        fallbackInput: String? = nil
    ) -> NLInstallPlan? {
        let matchedRole = payload.roleID.flatMap { id in roles.first { $0.id == id } }
        let catalogMap = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let matchedTools = (payload.toolIDs ?? []).compactMap { catalogMap[$0] }.prefix(8).map { $0 }

        guard matchedRole != nil || !matchedTools.isEmpty else { return nil }

        var parts: [String] = [summaryPrefix]
        if let role = matchedRole {
            parts.append("岗位「\(role.name)」")
        }
        if !matchedTools.isEmpty {
            let names = matchedTools.prefix(5).map(\.name).joined(separator: "、")
            let suffix = matchedTools.count > 5 ? " 等 \(matchedTools.count) 款" : ""
            parts.append("软件 \(names)\(suffix)")
        }

        let autoInstall = payload.autoInstall
            ?? fallbackInput.map { wantsAutoInstall(text: $0.lowercased()) }
            ?? false

        return NLInstallPlan(
            matchedRole: matchedRole,
            matchedTools: Array(matchedTools),
            summary: parts.joined(separator: " · "),
            autoInstall: autoInstall
        )
    }

    static func plan(input: String, roles: [RoleBundle], catalog: [DevTool]) -> NLInstallPlan? {
        let normalized = input.lowercased()
        let matchedRole = matchRole(in: normalized, roles: roles)
        let matchedTools = matchTools(in: normalized, catalog: catalog, excludingRole: matchedRole)

        guard matchedRole != nil || !matchedTools.isEmpty else { return nil }

        var parts: [String] = []
        if let role = matchedRole {
            parts.append("岗位「\(role.name)」")
        }
        if !matchedTools.isEmpty {
            let names = matchedTools.prefix(5).map(\.name).joined(separator: "、")
            let suffix = matchedTools.count > 5 ? " 等 \(matchedTools.count) 款" : ""
            parts.append("软件 \(names)\(suffix)")
        }

        return NLInstallPlan(
            matchedRole: matchedRole,
            matchedTools: matchedTools,
            summary: parts.joined(separator: " · "),
            autoInstall: wantsAutoInstall(text: normalized)
        )
    }

    static func looksLikeInstallIntent(_ input: String) -> Bool {
        let text = input.lowercased()
        return ["装", "安装", "配置", "环境", "setup", "install", "bundle", "岗位"].contains { text.contains($0) }
    }

    private static func wantsAutoInstall(text: String) -> Bool {
        ["直接安装", "一键安装", "马上装", "立即安装", "直接装", "帮我装", "开始安装"].contains { text.contains($0) }
    }

    // MARK: - LLM 增强（v1.0）

    private struct LLMIntentPayload: Decodable {
        let role_id: String?
        let tool_ids: [String]?
        let auto_install: Bool?
    }

    /// 云端 AI 解析装机意图 → 结构化岗位 / 工具 ID
    static func planWithLLM(
        input: String,
        roles: [RoleBundle],
        catalog: [DevTool],
        apiKey: String,
        model: String,
        baseURL: String
    ) async throws -> NLInstallPlan? {
        let roleLines = roles.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
        let sampleTools = catalog.prefix(40).map { "- \($0.id): \($0.name)" }.joined(separator: "\n")

        let system = """
        你是 Mac 装机助手 JSON 解析器。根据用户自然语言，只输出一行 JSON，不要 markdown、不要解释。
        格式：{"role_id":"岗位id或null","tool_ids":["catalog-id"],"auto_install":true或false}
        role_id 必须从下列岗位 id 中选择或 null；tool_ids 必须从 catalog id 中选择（最多 8 个）。
        auto_install 在用户要求直接/一键安装时为 true。
        """

        let user = """
        可选岗位：
        \(roleLines)

        Catalog 示例（共 \(catalog.count) 款，仅列部分 id）：
        \(sampleTools)

        用户需求：\(input)
        """

        let client = SiliconFlowClient()
        let raw = try await client.chat(
            apiKey: apiKey,
            messages: [("system", system), ("user", user)],
            parameters: AIChatParameters(model: model, temperature: 0.2, maxTokens: 256, stream: false, baseURL: baseURL)
        )

        guard let payload = parseLLMJSON(from: raw) else { return nil }

        return plan(
            from: NLInstallPayload(
                roleID: payload.role_id,
                toolIDs: payload.tool_ids,
                autoInstall: payload.auto_install
            ),
            roles: roles,
            catalog: catalog,
            summaryPrefix: "AI 解析",
            fallbackInput: input
        )
    }

    private static func parseLLMJSON(from text: String) -> LLMIntentPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder().decode(LLMIntentPayload.self, from: data) {
            return payload
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else { return nil }
        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMIntentPayload.self, from: data)
    }

    private static func matchRole(in text: String, roles: [RoleBundle]) -> RoleBundle? {
        var best: (RoleBundle, Int)?
        for role in roles {
            var score = 0
            if text.contains(role.name.lowercased()) { score += 10 }
            if text.contains(role.id.replacingOccurrences(of: "_", with: " ")) { score += 8 }
            for keyword in roleKeywords(role) where text.contains(keyword) {
                score += 5
            }
            if score > 0, score > (best?.1 ?? 0) {
                best = (role, score)
            }
        }
        return best?.0
    }

    private static func roleKeywords(_ role: RoleBundle) -> [String] {
        switch role.id {
        case "fullstack_developer": return ["全栈", "fullstack", "full stack", "全端"]
        case "frontend_developer": return ["前端", "frontend", "react", "vue"]
        case "backend_developer": return ["后端", "backend"]
        case "python_developer": return ["python", "django", "flask"]
        case "golang_developer": return ["go语言", "golang", " go "]
        case "java_developer": return ["java", "spring"]
        case "ios_developer": return ["ios", "swift", "xcode"]
        case "android_developer": return ["android", "kotlin"]
        case "devops_engineer", "sre_engineer": return ["devops", "运维", "sre"]
        case "data_analyst": return ["数据分析", "分析师"]
        case "data_engineer": return ["数据工程", "data engineer"]
        case "product_manager": return ["产品经理", "product"]
        case "designer": return ["设计师", "design", "ui", "ux"]
        case "qa_engineer": return ["测试", "qa", "quality"]
        case "student_starter": return ["学生", "入门", "新手"]
        case "ai_developer": return ["ai开发", "ai 开发", "ai工程师", "claude code", "codex", "cursor", "ollama", "大模型", "llm"]
        default:
            return role.name
                .replacingOccurrences(of: "工程师", with: "")
                .replacingOccurrences(of: "开发", with: "")
                .split(separator: " ")
                .map { String($0).lowercased() }
                .filter { $0.count >= 2 }
        }
    }

    private static func matchTools(
        in text: String,
        catalog: [DevTool],
        excludingRole: RoleBundle?
    ) -> [DevTool] {
        let installIntent = ["装", "安装", "下载", "要", "需要", "给我", "帮我"].contains { text.contains($0) }
        guard installIntent else { return [] }

        var hits: [DevTool] = []
        let sorted = catalog.sorted { $0.name.count > $1.name.count }

        for tool in sorted where tool.id != "homebrew" {
            let names = [
                tool.name.lowercased(),
                tool.id.replacingOccurrences(of: "-", with: " ").lowercased(),
                tool.id.lowercased()
            ]
            if names.contains(where: { name in
                name.count >= 3 && text.contains(name)
            }) {
                if !hits.contains(where: { $0.id == tool.id }) {
                    hits.append(tool)
                }
            }
        }

        return Array(hits.prefix(8))
    }
}

// MARK: - S12-01 AI Function Calling Agent

struct AIAgentResult: Sendable {
    let text: String
    let recommendedToolIDs: [String]
    let actionLabel: String?
    let actionTab: AppTab?
    let suggestedFollowUps: [String]
}

@MainActor
enum AIFunctionExecutor {
    private struct SearchArgs: Decodable { let query: String }
    private struct RoleArgs: Decodable { let role_id: String }
    private struct InstallArgs: Decodable {
        let tool_ids: [String]
        let auto_install: Bool?
    }

    private struct ToolHit: Encodable {
        let id: String
        let name: String
        let description: String
    }

    static func run(
        userInput: String,
        viewModel: AppViewModel,
        apiKey: String,
        parameters: AIChatParameters
    ) async throws -> AIAgentResult {
        let client = SiliconFlowClient()
        var transcript: [LLMConversationMessage] = [
            .system(AIAssistantService.agentSystemPrompt(for: viewModel)),
            .user(userInput)
        ]
        var recommendedToolIDs: [String] = []
        var actionLabel: String?
        var actionTab: AppTab?

        for _ in 0..<5 {
            try Task.checkCancellation()
            let completion = try await client.chatCompletion(
                apiKey: apiKey,
                messages: transcript,
                parameters: parameters
            )

            if completion.toolCalls.isEmpty {
                let text = completion.content ?? "已完成操作。"
                let enriched = AIAssistantService.enrichLLMResponse(text, userInput: userInput)
                return AIAgentResult(
                    text: enriched.text,
                    recommendedToolIDs: recommendedToolIDs,
                    actionLabel: actionLabel ?? enriched.actionLabel,
                    actionTab: actionTab ?? enriched.actionTab,
                    suggestedFollowUps: enriched.suggestedFollowUps
                )
            }

            transcript.append(.assistantToolCalls(completion.toolCalls))

            for call in completion.toolCalls {
                let (resultJSON, sideEffect) = await execute(
                    call: call,
                    viewModel: viewModel,
                    recommendedToolIDs: &recommendedToolIDs
                )
                if let sideEffect {
                    actionLabel = sideEffect.label
                    actionTab = sideEffect.tab
                }
                transcript.append(.toolResult(callID: call.id, content: resultJSON))
            }
        }

        throw LLMClientError.invalidResponse
    }

    private struct SideEffect {
        let label: String
        let tab: AppTab
    }

    private static func execute(
        call: LLMToolCall,
        viewModel: AppViewModel,
        recommendedToolIDs: inout [String]
    ) async -> (String, SideEffect?) {
        switch call.name {
        case "search_catalog":
            guard let args = decodeArgs(SearchArgs.self, from: call.arguments) else {
                return (#"{"error":"invalid arguments"}"#, nil)
            }
            let query = args.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let hits = viewModel.allCatalogTools
                .filter { $0.matchesDiscoverSearch(query) }
                .prefix(8)
                .map { ToolHit(id: $0.id, name: $0.name, description: $0.description) }
            let ids = hits.map(\.id)
            recommendedToolIDs.append(contentsOf: ids)
            recommendedToolIDs = Array(Set(recommendedToolIDs))
            let json = (try? String(data: JSONEncoder().encode(["tools": hits]), encoding: .utf8))
                ?? #"{"tools":[]}"#
            return (json, SideEffect(label: "去发现页查看", tab: .discover))

        case "scan_installed":
            await viewModel.scanInstalledStatus(force: true)
            let snapshot = viewModel.installedSnapshot
            let installed = (snapshot?.formulae.count ?? 0) + (snapshot?.casks.count ?? 0) + (snapshot?.masApps.count ?? 0)
            let outdated = viewModel.outdatedCount
            let json = #"{"installed_count":\#(installed),"outdated_count":\#(outdated)}"#
            return (json, SideEffect(label: "查看已安装", tab: .installed))

        case "select_role":
            guard let args = decodeArgs(RoleArgs.self, from: call.arguments),
                  viewModel.bundleManager.roles.contains(where: { $0.id == args.role_id }) else {
                return (#"{"error":"unknown role_id"}"#, nil)
            }
            if viewModel.settings.allowMultipleRoles {
                viewModel.selectedRoles.insert(args.role_id)
            } else {
                viewModel.selectedRoles = [args.role_id]
            }
            viewModel.refreshResolvedTools()
            viewModel.navigateTo(.roles)
            viewModel.currentScreen = .bundleDetail
            let name = viewModel.bundleManager.roles.first(where: { $0.id == args.role_id })?.name ?? args.role_id
            return (#"{"role_id":"\#(args.role_id)","name":"\#(name)"}"#, SideEffect(label: "查看工具清单", tab: .roles))

        case "install_tools":
            guard let args = decodeArgs(InstallArgs.self, from: call.arguments) else {
                return (#"{"error":"invalid arguments"}"#, nil)
            }
            let catalog = viewModel.allCatalogTools
            let tools = args.tool_ids.compactMap { id in catalog.first(where: { $0.id == id }) }
            guard !tools.isEmpty else {
                return (#"{"error":"no valid tool_ids"}"#, nil)
            }
            for tool in tools {
                viewModel.discoverSelectedTools.insert(tool.id)
            }
            recommendedToolIDs.append(contentsOf: tools.map(\.id))
            recommendedToolIDs = Array(Set(recommendedToolIDs))

            if args.auto_install == true {
                viewModel.navigateTo(.discover)
                await viewModel.installDiscoverTools(tools)
                return (#"{"added":\#(tools.count),"installed":true}"#, SideEffect(label: "查看安装进度", tab: .discover))
            }
            return (#"{"added":\#(tools.count),"installed":false}"#, SideEffect(label: "去安装清单", tab: .discover))

        default:
            return (#"{"error":"unknown function"}"#, nil)
        }
    }

    private static func decodeArgs<T: Decodable>(_ type: T.Type, from arguments: String) -> T? {
        guard let data = arguments.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

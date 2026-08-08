import Foundation

struct DiscoverNLFilterPlan: Sendable, Equatable {
    var category: String?
    var sourceFilter: DiscoverSourceFilter?
    var scopeFilter: DiscoverScopeFilter?
    var roleFilter: String?
    var kindFilter: ToolKind?
    var sourceTypeFilter: InstallSourceType?
    var keywordQuery: String
    var pinnedToolIDs: [String]
    var summary: String

    var hasStructuredFilters: Bool {
        category != nil
            || sourceFilter != nil
            || scopeFilter != nil
            || roleFilter != nil
            || kindFilter != nil
            || sourceTypeFilter != nil
            || !pinnedToolIDs.isEmpty
    }
}

/// S14-03 — 自然语言 → 发现页筛选（规则层 + 可选 LLM）
enum CatalogNLFilterService {
    private struct CategoryRule {
        let category: ToolCategory
        let keywords: [String]
    }

    private static let categoryRules: [CategoryRule] = [
        CategoryRule(category: .database, keywords: ["数据库", "database", "mysql", "postgres", "postgresql", "redis", "mongodb", "sql"]),
        CategoryRule(category: .editor, keywords: ["编辑器", "editor", "ide", "vscode", "代码编辑", "写代码"]),
        CategoryRule(category: .browser, keywords: ["浏览器", "browser", "chrome", "firefox", "safari"]),
        CategoryRule(category: .terminal, keywords: ["终端", "terminal", "shell", "iterm", "warp"]),
        CategoryRule(category: .devops, keywords: ["devops", "docker", "kubernetes", "k8s", "容器", "ci/cd", "流水线"]),
        CategoryRule(category: .language, keywords: ["语言", "runtime", "运行时", "python", "node", "java", "golang", "rust"]),
        CategoryRule(category: .design, keywords: ["设计", "design", "figma", "sketch", "ui", "ux", "原型"]),
        CategoryRule(category: .collab, keywords: ["协作", "沟通", "slack", "teams", "飞书", "zoom", "会议"]),
        CategoryRule(category: .product, keywords: ["产品", "product", "notion", "jira", "项目管理"]),
        CategoryRule(category: .utility, keywords: ["效率", "utility", "工具", "clipboard", "launcher", "alfred", "raycast"]),
        CategoryRule(category: .security, keywords: ["安全", "security", "vpn", "密码", "1password"]),
        CategoryRule(category: .media, keywords: ["媒体", "media", "视频", "音频", "播放器"]),
        CategoryRule(category: .infra, keywords: ["基础设施", "infra", "homebrew", "包管理"])
    ]

    static func looksLikeNaturalLanguage(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 4 else { return false }
        if text.contains(where: { $0.isWhitespace }) { return true }
        let cues = [
            "适合", "想要", "需要", "推荐", "有没有", "哪些", "什么", "帮我", "找", "筛", "工具",
            "前端", "后端", "数据库", "编辑器", "浏览器", "命令行", "图形", "精选", "岗位"
        ]
        let lower = text.lowercased()
        return cues.contains { lower.contains($0) }
    }

    static func plan(
        input: String,
        catalog: [DevTool],
        roles: [RoleBundle]
    ) -> DiscoverNLFilterPlan {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else {
            return DiscoverNLFilterPlan(keywordQuery: "", pinnedToolIDs: [], summary: "")
        }

        var category: String?
        var sourceFilter: DiscoverSourceFilter?
        var scopeFilter: DiscoverScopeFilter?
        var roleFilter: String?
        var kindFilter: ToolKind?
        var sourceTypeFilter: InstallSourceType?
        var summaryParts: [String] = []
        var consumed = Set<String>()

        for rule in categoryRules {
            if let hit = firstMatch(in: text, keywords: rule.keywords) {
                category = rule.category.rawValue
                summaryParts.append(rule.category.displayName)
                consumed.insert(hit)
                break
            }
        }

        if matchesAny(in: text, keywords: ["精选", "热门", "推荐", "popular"]) {
            scopeFilter = .popular
            summaryParts.append("精选热门")
            consumed.formUnion(["精选", "热门", "推荐", "popular"])
        }

        if matchesAny(in: text, keywords: ["岗位", "bundle", "角色包"]) {
            scopeFilter = .role
            summaryParts.append("岗位推荐")
            consumed.formUnion(["岗位", "bundle", "角色包"])
        }

        if let role = matchRole(in: text, roles: roles) {
            roleFilter = role.id
            scopeFilter = .role
            if !summaryParts.contains("岗位推荐") {
                summaryParts.append("岗位「\(role.name)」")
            }
        }

        if matchesAny(in: text, keywords: ["可安装", "可一键", "一键安装", "brew"]) {
            sourceFilter = .installable
            summaryParts.append("可一键安装")
            consumed.formUnion(["可安装", "可一键", "一键安装", "brew"])
        }

        if matchesAny(in: text, keywords: ["手动", "外链", "官网", "手动安装"]) {
            sourceFilter = .manual
            summaryParts.append("手动安装")
            consumed.formUnion(["手动", "外链", "官网", "手动安装"])
        }

        if matchesAny(in: text, keywords: ["命令行", "cli", "formula", "终端工具"]) {
            kindFilter = .cli
            sourceTypeFilter = .formula
            summaryParts.append("CLI / Formula")
            consumed.formUnion(["命令行", "cli", "formula", "终端工具"])
        }

        if matchesAny(in: text, keywords: ["图形", "gui", "应用", "app", "cask", "桌面"]) {
            kindFilter = .gui
            sourceTypeFilter = .cask
            summaryParts.append("GUI / Cask")
            consumed.formUnion(["图形", "gui", "应用", "app", "cask", "桌面"])
        }

        if matchesAny(in: text, keywords: ["app store", "mas", "应用商店"]) {
            sourceTypeFilter = .mas
            summaryParts.append("App Store")
            consumed.formUnion(["app store", "mas", "应用商店"])
        }

        let pinnedTools = matchTools(in: text, catalog: catalog)
        if !pinnedTools.isEmpty {
            let names = pinnedTools.prefix(3).map(\.name).joined(separator: "、")
            summaryParts.append("匹配 \(names)")
        }

        var keywords = extractKeywords(from: text, consumedPhrases: consumed)
        if keywords.isEmpty, pinnedTools.isEmpty, !summaryParts.isEmpty {
            keywords = text
        }

        let summary = summaryParts.isEmpty
            ? (pinnedTools.isEmpty ? "" : "已匹配 \(pinnedTools.count) 款软件")
            : "智能筛选：" + summaryParts.joined(separator: " · ")

        return DiscoverNLFilterPlan(
            category: category,
            sourceFilter: sourceFilter,
            scopeFilter: scopeFilter,
            roleFilter: roleFilter,
            kindFilter: kindFilter,
            sourceTypeFilter: sourceTypeFilter,
            keywordQuery: keywords,
            pinnedToolIDs: pinnedTools.map(\.id),
            summary: summary
        )
    }

    // MARK: - Shared payload → plan

    struct NLFilterPayload: Sendable {
        var category: String?
        var sourceFilter: String?
        var scopeFilter: String?
        var roleID: String?
        var kind: String?
        var sourceType: String?
        var keywords: String?
        var toolIDs: [String]?
    }

    static func plan(from payload: NLFilterPayload, catalog: [DevTool], summaryPrefix: String) -> DiscoverNLFilterPlan {
        let catalogMap = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let pinned = (payload.toolIDs ?? []).compactMap { catalogMap[$0] }.map(\.id)

        var parts: [String] = [summaryPrefix]
        if let cat = payload.category?.nilIfEmpty, ToolCategory(rawValue: cat) != nil {
            parts.append(ToolCategory(rawValue: cat)!.displayName)
        }
        if let keywords = payload.keywords?.nilIfEmpty {
            parts.append("「\(keywords)」")
        }
        if !pinned.isEmpty {
            parts.append("\(pinned.count) 款匹配")
        }

        return DiscoverNLFilterPlan(
            category: payload.category?.nilIfEmpty,
            sourceFilter: payload.sourceFilter?.nilIfEmpty.flatMap { DiscoverSourceFilter(rawValue: $0) },
            scopeFilter: payload.scopeFilter?.nilIfEmpty.flatMap { DiscoverScopeFilter(rawValue: $0) },
            roleFilter: payload.roleID?.nilIfEmpty,
            kindFilter: payload.kind?.nilIfEmpty.flatMap { ToolKind(rawValue: $0) },
            sourceTypeFilter: payload.sourceType?.nilIfEmpty.flatMap { InstallSourceType(rawValue: $0) },
            keywordQuery: payload.keywords?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            pinnedToolIDs: pinned,
            summary: parts.joined(separator: " · ")
        )
    }

    // MARK: - LLM

    private struct LLMFilterPayload: Decodable {
        let category: String?
        let source_filter: String?
        let scope_filter: String?
        let role_id: String?
        let kind: String?
        let source_type: String?
        let keywords: String?
        let tool_ids: [String]?
    }

    static func planWithLLM(
        input: String,
        catalog: [DevTool],
        roles: [RoleBundle],
        apiKey: String,
        model: String,
        baseURL: String
    ) async throws -> DiscoverNLFilterPlan? {
        let categories = ToolCategory.allCases.filter { $0 != .all }.map { $0.rawValue }.joined(separator: ", ")
        let roleLines = roles.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
        let sampleTools = catalog.prefix(30).map { "- \($0.id): \($0.name)" }.joined(separator: "\n")

        let system = """
        你是 Mac 软件目录筛选 JSON 解析器。根据用户自然语言，只输出一行 JSON，不要 markdown。
        格式：{"category":"分类rawValue或null","source_filter":"all|installable|manual或null","scope_filter":"all|popular|role或null","role_id":"岗位id或null","kind":"cli|gui或null","source_type":"formula|cask|mas|script|link或null","keywords":"剩余关键词","tool_ids":["catalog-id"]}
        category 可选: \(categories)
        tool_ids 最多 8 个，必须从 catalog id 选择。
        """

        let user = """
        岗位：
        \(roleLines)

        Catalog 示例：
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
            from: NLFilterPayload(
                category: payload.category,
                sourceFilter: payload.source_filter,
                scopeFilter: payload.scope_filter,
                roleID: payload.role_id,
                kind: payload.kind,
                sourceType: payload.source_type,
                keywords: payload.keywords,
                toolIDs: payload.tool_ids
            ),
            catalog: catalog,
            summaryPrefix: "AI 筛选"
        )
    }

    private static func parseLLMJSON(from text: String) -> LLMFilterPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder().decode(LLMFilterPayload.self, from: data) {
            return payload
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else { return nil }
        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMFilterPayload.self, from: data)
    }

    // MARK: - Helpers

    private static func matchRole(in text: String, roles: [RoleBundle]) -> RoleBundle? {
        var best: (RoleBundle, Int)?
        for role in roles {
            var score = 0
            if text.contains(role.name.lowercased()) { score += 10 }
            if text.contains(role.id.replacingOccurrences(of: "_", with: " ")) { score += 8 }
            let keywords = roleKeywords(role)
            for keyword in keywords where text.contains(keyword) {
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
        case "fullstack_developer": return ["全栈", "fullstack", "full stack"]
        case "frontend_developer": return ["前端", "frontend", "react", "vue"]
        case "backend_developer": return ["后端", "backend"]
        case "python_developer": return ["python", "django"]
        case "golang_developer": return ["golang", " go "]
        case "java_developer": return ["java", "spring"]
        case "ios_developer": return ["ios", "swift"]
        case "android_developer": return ["android", "kotlin"]
        case "devops_engineer", "sre_engineer": return ["devops", "运维", "sre"]
        case "data_analyst": return ["数据分析", "分析师"]
        case "data_engineer": return ["数据工程"]
        case "product_manager": return ["产品经理", "product"]
        case "designer": return ["设计师", "design"]
        case "qa_engineer": return ["测试", "qa"]
        case "student_starter": return ["学生", "入门", "新手"]
        case "ai_developer": return ["ai开发", "ai 开发", "claude code", "codex", "cursor", "ollama", "大模型", "llm"]
        default:
            return role.name
                .split(separator: " ")
                .map { String($0).lowercased() }
                .filter { $0.count >= 2 }
        }
    }

    private static func matchTools(in text: String, catalog: [DevTool]) -> [DevTool] {
        var hits: [DevTool] = []
        let sorted = catalog.sorted { $0.name.count > $1.name.count }

        for tool in sorted where tool.id != "homebrew" {
            let candidates = [
                tool.name.lowercased(),
                tool.id.replacingOccurrences(of: "-", with: " ").lowercased(),
                tool.id.lowercased()
            ]
            if candidates.contains(where: { name in
                name.count >= 3 && text.contains(name)
            }) {
                if !hits.contains(where: { $0.id == tool.id }) {
                    hits.append(tool)
                }
            }
        }

        return Array(hits.prefix(8))
    }

    private static func firstMatch(in text: String, keywords: [String]) -> String? {
        keywords.first { text.contains($0.lowercased()) }
    }

    private static func matchesAny(in text: String, keywords: [String]) -> Bool {
        firstMatch(in: text, keywords: keywords) != nil
    }

    private static func extractKeywords(from text: String, consumedPhrases: Set<String>) -> String {
        var remaining = text
        let sortedPhrases = consumedPhrases.sorted { $0.count > $1.count }
        for phrase in sortedPhrases where phrase.count >= 2 {
            remaining = remaining.replacingOccurrences(of: phrase, with: " ")
        }

        let stopWords: Set<String> = [
            "的", "了", "吗", "呢", "啊", "吧", "我", "你", "有", "没", "一些", "几个",
            "适合", "想要", "需要", "推荐", "有没有", "哪些", "什么", "帮我", "找", "筛",
            "软件", "工具", "应用", "一下", "请"
        ]

        let tokens = remaining
            .split(whereSeparator: { $0.isWhitespace || "，。！？、；：".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 2 && !stopWords.contains($0) }

        return tokens.joined(separator: " ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

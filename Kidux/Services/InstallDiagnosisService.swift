import Foundation

struct InstallDiagnosisPayload: Sendable {
    var summary: String?
    var causes: [String]?
    var suggestSwitchMirror: Bool?
    var suggestRetry: Bool?
    var suggestCheckInstalled: Bool?
    var suggestGatekeeperFix: Bool?
}

/// S18-02 — 安装失败日志诊断（规则 + 可选 LLM/FM）
enum InstallDiagnosisService {
    private static let logTailLimit = 6000

    static func trimmedLog(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > logTailLimit else { return trimmed }
        return String(trimmed.suffix(logTailLimit))
    }

    static func reply(from payload: InstallDiagnosisPayload, summaryPrefix: String, logText: String) -> AIAssistantReply {
        let causes = (payload.causes ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let resolvedCauses = causes.isEmpty ? inferRuleCauses(from: logText) : causes

        let summary = payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "检测到 \(resolvedCauses.count) 类可能原因"

        let body = resolvedCauses.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let text = "**\(summaryPrefix)**：\(summary)\n\n\(body)\n\n可在安装进度页 **重试失败项**，或按下方建议操作。"

        let lower = logText.lowercased()
        let networkHints = ["network", "timeout", "could not resolve", "connection", "ssl", "timed out"]
        let switchMirror = payload.suggestSwitchMirror ?? networkHints.contains { lower.contains($0) }
        let gatekeeper = payload.suggestGatekeeperFix ?? {
            let t = logText.lowercased()
            return t.contains("quarantine") || t.contains("damaged") || t.contains("xattr")
        }()
        let checkInstalled = payload.suggestCheckInstalled ?? logText.lowercased().contains("already installed")
        let retry = payload.suggestRetry ?? true

        let (actionLabel, actionTab) = primaryAction(
            switchMirror: switchMirror,
            gatekeeper: gatekeeper,
            checkInstalled: checkInstalled,
            retry: retry
        )

        var followUps: [String] = []
        if switchMirror { followUps.append("切换 brew 镜像") }
        if retry { followUps.append("如何重试失败项") }
        if gatekeeper { followUps.append("应用打不开怎么办") }
        if checkInstalled { followUps.append("查看已安装") }
        if followUps.isEmpty {
            followUps = ["切换 brew 镜像", "如何重试失败项"]
        }

        return AIAssistantReply(
            text: text,
            actionLabel: actionLabel,
            actionTab: actionTab,
            suggestedFollowUps: Array(followUps.prefix(4))
        )
    }

    static func diagnoseRules(_ text: String) -> AIAssistantReply {
        reply(
            from: InstallDiagnosisPayload(
                summary: nil,
                causes: inferRuleCauses(from: text),
                suggestSwitchMirror: nil,
                suggestRetry: true,
                suggestCheckInstalled: nil,
                suggestGatekeeperFix: nil
            ),
            summaryPrefix: "规则诊断",
            logText: text
        )
    }

    static func diagnoseWithLLM(
        logs: String,
        apiKey: String,
        model: String,
        baseURL: String
    ) async throws -> AIAssistantReply? {
        let logText = trimmedLog(logs)

        let system = """
        你是 Mac Homebrew 安装失败诊断 JSON 解析器。根据日志只输出一行 JSON，不要 markdown。
        格式：{"summary":"一句话","causes":["原因1"],"suggest_switch_mirror":true/false,"suggest_retry":true/false,"suggest_check_installed":true/false,"suggest_gatekeeper_fix":true/false}
        causes 2-5 条，中文，每条不超过 80 字。
        """

        let user = """
        安装失败日志：
        \(logText)
        """

        let client = SiliconFlowClient()
        let raw = try await client.chat(
            apiKey: apiKey,
            messages: [("system", system), ("user", user)],
            parameters: AIChatParameters(model: model, temperature: 0.2, maxTokens: 512, stream: false, baseURL: baseURL)
        )

        guard let payload = parseLLMJSON(from: raw) else { return nil }

        return reply(
            from: InstallDiagnosisPayload(
                summary: payload.summary,
                causes: payload.causes,
                suggestSwitchMirror: payload.suggest_switch_mirror,
                suggestRetry: payload.suggest_retry,
                suggestCheckInstalled: payload.suggest_check_installed,
                suggestGatekeeperFix: payload.suggest_gatekeeper_fix
            ),
            summaryPrefix: "AI 诊断",
            logText: logText
        )
    }

    private struct LLMDiagnosisPayload: Decodable {
        let summary: String?
        let causes: [String]?
        let suggest_switch_mirror: Bool?
        let suggest_retry: Bool?
        let suggest_check_installed: Bool?
        let suggest_gatekeeper_fix: Bool?
    }

    private static func parseLLMJSON(from text: String) -> LLMDiagnosisPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder().decode(LLMDiagnosisPayload.self, from: data) {
            return payload
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else { return nil }
        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMDiagnosisPayload.self, from: data)
    }

    private static func inferRuleCauses(from text: String) -> [String] {
        let t = text.lowercased()
        var causes: [String] = []

        if t.contains("password") || t.contains("sudo") || t.contains("permission denied") {
            causes.append("**权限不足**：安装需要管理员密码，请在系统弹窗中输入 Mac 登录密码。")
        }
        if t.contains("network") || t.contains("timeout") || t.contains("could not resolve") {
            causes.append("**网络问题**：可在 **设置 → 安装源** 切换国内 Homebrew 镜像后重试。")
        }
        if t.contains("already installed") || t.contains("already exists") {
            causes.append("**已安装**：可在已安装页确认，或关闭「自动跳过已安装」后重装。")
        }
        if t.contains("cask") && (t.contains("quarantine") || t.contains("damaged")) {
            causes.append("**Gatekeeper**：到 **已安装 → 本机应用** 点「修复」清除隔离属性。")
        }
        if t.contains("mas") || t.contains("app store") {
            causes.append("**App Store**：确认已登录 Apple ID，且 `mas` 已安装（设置中启用 MAS 集成）。")
        }
        if causes.isEmpty {
            causes.append("请检查 brew 日志中的 **Error** 行；常见原因：网络、权限、包名错误或已安装冲突。")
        }
        return causes
    }

    private static func primaryAction(
        switchMirror: Bool,
        gatekeeper: Bool,
        checkInstalled: Bool,
        retry: Bool
    ) -> (String?, AppTab?) {
        if switchMirror {
            return ("打开安装源设置", .settings)
        }
        if gatekeeper {
            return ("去已安装修复", .installed)
        }
        if checkInstalled {
            return ("查看已安装", .installed)
        }
        if retry {
            return ("查看安装进度", .discover)
        }
        return ("查看已安装", .installed)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

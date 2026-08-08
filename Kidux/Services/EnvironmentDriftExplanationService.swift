import Foundation

struct EnvironmentDriftExplanation: Sendable, Equatable {
    let summary: String
    let narrative: String
    let suggestedActions: [String]
    let sourceLabel: String
}

/// S18-05 — 环境漂移人话解释（规则 + 可选 LLM/FM）
enum EnvironmentDriftExplanationService {
    private static let itemLimit = 28

    static func promptText(report: EnvironmentDriftReport, baselineLabel: String) -> String {
        var lines = [
            "基准名称: \(baselineLabel)",
            "基准时间: \(report.baselineCapturedAt.formatted(date: .abbreviated, time: .shortened))",
            "对比时间: \(report.comparedAt.formatted(date: .abbreviated, time: .shortened))",
            "统计: \(report.summaryLine)",
            "明细:"
        ]
        for item in report.items.prefix(itemLimit) {
            lines.append("[\(kindLabel(item.kind))] \(item.title) — \(item.detail)")
        }
        if report.items.count > itemLimit {
            lines.append("… 还有 \(report.items.count - itemLimit) 项未列出")
        }
        return lines.joined(separator: "\n")
    }

    static func explainRules(report: EnvironmentDriftReport, baselineLabel: String) -> EnvironmentDriftExplanation {
        let missing = report.items.filter { $0.kind == .missing }
        let extra = report.items.filter { $0.kind == .extra }
        let changed = report.items.filter { $0.kind == .changed }

        let missingFormulae = missing.filter { $0.id.hasPrefix("formula-missing") }.map(\.title)
        let missingCasks = missing.filter { $0.id.hasPrefix("cask-missing") }.map(\.title)
        let extraFormulae = extra.filter { $0.id.hasPrefix("formula-extra") }.map(\.title)
        let hasGitDrift = report.items.contains { $0.id == "git-identity" }
        let runtimeDrifts = report.items.filter { $0.id.hasPrefix("runtime-") }

        var narrativeParts: [String] = []
        if !missingFormulae.isEmpty || !missingCasks.isEmpty {
            let samples = (missingFormulae + missingCasks).prefix(4).joined(separator: "、")
            let suffix = samples.isEmpty ? "。" : "，例如 \(samples)。"
            narrativeParts.append("相对基准「\(baselineLabel)」，本机少了 \(missingFormulae.count) 个 formula 与 \(missingCasks.count) 个 cask\(suffix)")
        }
        if !extraFormulae.isEmpty {
            narrativeParts.append("本机还多装了 \(extraFormulae.count) 个 formula/cask，可能是基准之后新装的工具。")
        }
        if hasGitDrift {
            narrativeParts.append("Git 用户名或邮箱与基准不一致，可能影响提交记录归属。")
        }
        if !runtimeDrifts.isEmpty {
            narrativeParts.append("Node/Python 等运行时版本与基准不同，换机或升级工具链后较常见。")
        }
        if narrativeParts.isEmpty {
            narrativeParts.append("未检测到需要特别说明的漂移。")
        }

        var actions: [String] = []
        if !missingFormulae.isEmpty || !missingCasks.isEmpty {
            actions.append("在发现页或已装页补装缺失包，或用换机 Wizard 一键恢复")
        }
        if !extraFormulae.isEmpty {
            actions.append("若多出的包是预期变更，可在环境页重新「设为基准」")
        }
        if hasGitDrift {
            actions.append("到设置或环境页核对 Git 身份是否与团队一致")
        }
        if !runtimeDrifts.isEmpty {
            actions.append("检查 mise/nvm 版本，或在岗位清单中重装对应运行时")
        }
        if actions.isEmpty {
            actions.append("重新导出 v3 快照并设为漂移基准")
        }

        return EnvironmentDriftExplanation(
            summary: report.summaryLine,
            narrative: narrativeParts.joined(separator: " "),
            suggestedActions: Array(actions.prefix(4)),
            sourceLabel: "规则解读"
        )
    }

    static func explain(
        from payload: DriftExplanationPayload,
        report: EnvironmentDriftReport,
        sourceLabel: String
    ) -> EnvironmentDriftExplanation {
        let summary = payload.summary?.nilIfEmpty ?? report.summaryLine
        let narrative = payload.narrative?.nilIfEmpty ?? explainRules(report: report, baselineLabel: "基准").narrative
        let actions = (payload.suggestedActions ?? []).filter { !$0.isEmpty }
        return EnvironmentDriftExplanation(
            summary: summary,
            narrative: narrative,
            suggestedActions: actions.isEmpty ? explainRules(report: report, baselineLabel: "基准").suggestedActions : Array(actions.prefix(4)),
            sourceLabel: sourceLabel
        )
    }

    static func explainWithLLM(
        report: EnvironmentDriftReport,
        baselineLabel: String,
        apiKey: String,
        model: String,
        baseURL: String
    ) async throws -> EnvironmentDriftExplanation? {
        let prompt = promptText(report: report, baselineLabel: baselineLabel)

        let system = """
        你是 Mac 开发环境漂移解读助手。根据 drift diff 用通俗中文解释「发生了什么、是否严重、下一步做什么」。
        只输出一行 JSON，不要 markdown。
        格式：{"summary":"一句话","narrative":"2-4句人话解释","suggested_actions":["建议1","建议2"]}
        suggested_actions 最多 4 条，可操作、面向 Kidux 用户（brew/岗位/基准/快照）。
        """

        let client = SiliconFlowClient()
        let raw = try await client.chat(
            apiKey: apiKey,
            messages: [("system", system), ("user", prompt)],
            parameters: AIChatParameters(model: model, temperature: 0.3, maxTokens: 512, stream: false, baseURL: baseURL)
        )

        guard let payload = parseLLMJSON(from: raw) else { return nil }

        return explain(
            from: DriftExplanationPayload(
                summary: payload.summary,
                narrative: payload.narrative,
                suggestedActions: payload.suggested_actions
            ),
            report: report,
            sourceLabel: "AI 解读"
        )
    }

    struct DriftExplanationPayload: Sendable {
        var summary: String?
        var narrative: String?
        var suggestedActions: [String]?
    }

    private struct LLMDriftPayload: Decodable {
        let summary: String?
        let narrative: String?
        let suggested_actions: [String]?
    }

    private static func parseLLMJSON(from text: String) -> LLMDriftPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder().decode(LLMDriftPayload.self, from: data) {
            return payload
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else { return nil }
        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMDriftPayload.self, from: data)
    }

    private static func kindLabel(_ kind: EnvironmentDriftItem.Kind) -> String {
        switch kind {
        case .missing: return "缺失"
        case .extra: return "多出"
        case .changed: return "变更"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

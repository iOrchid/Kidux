#if canImport(FoundationModels)
import FoundationModels
import Foundation

/// S18-05 — 环境漂移人话解释，优先 Apple Intelligence 端侧模型。
@available(macOS 26.0, *)
enum AppleIntelligenceDriftExplanation {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    @Generable
    struct DriftPayload {
        @Guide(description: "一句话摘要")
        var summary: String

        @Guide(description: "2-4 句通俗中文，解释漂移含义与严重程度")
        var narrative: String

        @Guide(description: "最多 4 条可操作建议")
        var suggestedActions: [String]
    }

    static func explain(
        report: EnvironmentDriftReport,
        baselineLabel: String
    ) async throws -> EnvironmentDriftExplanation? {
        guard isAvailable else { return nil }

        let prompt = EnvironmentDriftExplanationService.promptText(
            report: report,
            baselineLabel: baselineLabel
        )

        let session = LanguageModelSession {
            """
            你是 Mac 开发环境漂移解读助手。用非技术同事也能懂的中文解释 drift diff。
            说明：少了什么、多了什么、Git/运行时变更意味着什么；给出可操作建议（补装、设基准、核对 Git 等）。
            """
        }

        let response = try await session.respond(
            to: "环境漂移对比:\n\(prompt)",
            generating: DriftPayload.self
        )
        let payload = response.content

        return EnvironmentDriftExplanationService.explain(
            from: EnvironmentDriftExplanationService.DriftExplanationPayload(
                summary: payload.summary.nilIfEmpty,
                narrative: payload.narrative.nilIfEmpty,
                suggestedActions: payload.suggestedActions.isEmpty ? nil : Array(payload.suggestedActions.prefix(4))
            ),
            report: report,
            sourceLabel: "本机 AI 解读"
        )
    }
}

@available(macOS 26.0, *)
private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif

#if canImport(FoundationModels)
import FoundationModels
import Foundation

/// S18-02 — 安装失败日志诊断，优先 Apple Intelligence 端侧模型。
@available(macOS 26.0, *)
enum AppleIntelligenceInstallDiagnosis {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    @Generable
    struct DiagnosisPayload {
        @Guide(description: "一句话摘要")
        var summary: String

        @Guide(description: "可能原因，每条一句，2-5 条")
        var causes: [String]

        @Guide(description: "建议切换国内镜像时为 true")
        var suggestSwitchMirror: Bool

        @Guide(description: "建议重试失败项时为 true")
        var suggestRetry: Bool

        @Guide(description: "建议到已安装页核对时为 true")
        var suggestCheckInstalled: Bool

        @Guide(description: "建议修复 Gatekeeper/xattr 时为 true")
        var suggestGatekeeperFix: Bool
    }

    static func diagnose(logs: String) async throws -> AIAssistantReply? {
        guard isAvailable else { return nil }

        let logText = InstallDiagnosisService.trimmedLog(logs)

        let session = LanguageModelSession {
            """
            你是 Mac Homebrew 安装失败诊断助手。根据日志输出结构化诊断。
            causes 用简洁中文；网络/超时类问题 suggestSwitchMirror 为 true；
            quarantine/damaged 时 suggestGatekeeperFix 为 true。
            """
        }

        let prompt = """
        安装失败日志:
        \(logText)
        """

        let response = try await session.respond(to: prompt, generating: DiagnosisPayload.self)
        let payload = response.content

        return InstallDiagnosisService.reply(
            from: InstallDiagnosisPayload(
                summary: payload.summary.nilIfEmpty,
                causes: payload.causes.isEmpty ? nil : payload.causes,
                suggestSwitchMirror: payload.suggestSwitchMirror,
                suggestRetry: payload.suggestRetry,
                suggestCheckInstalled: payload.suggestCheckInstalled,
                suggestGatekeeperFix: payload.suggestGatekeeperFix
            ),
            summaryPrefix: "本机 AI 诊断",
            logText: logText
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

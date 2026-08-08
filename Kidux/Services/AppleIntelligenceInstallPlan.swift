#if canImport(FoundationModels)
import FoundationModels
import Foundation

/// S18-01 — AI 装机意图，优先使用 Apple Intelligence 端侧模型。
@available(macOS 26.0, *)
enum AppleIntelligenceInstallPlan {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    @Generable
    struct InstallPayload {
        @Guide(description: "岗位 bundle id，无则留空")
        var roleID: String

        @Guide(description: "最多 8 个 catalog tool id")
        var toolIDs: [String]

        @Guide(description: "用户要求直接/一键安装时为 true，否则 false")
        var autoInstall: Bool
    }

    static func plan(
        input: String,
        roles: [RoleBundle],
        catalog: [DevTool]
    ) async throws -> NLInstallPlan? {
        guard isAvailable else { return nil }

        let roleLines = roles.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
        let sampleTools = catalog.prefix(40).map { "- \($0.id): \($0.name)" }.joined(separator: "\n")

        let session = LanguageModelSession {
            """
            你是 Mac 装机助手。根据用户自然语言，输出结构化装机意图。
            roleID 必须从岗位 id 选择或留空；toolIDs 必须从 catalog id 选择，最多 8 个。
            autoInstall 在用户要求直接/一键/马上安装时为 true。
            """
        }

        let prompt = """
        可选岗位:
        \(roleLines)

        Catalog 示例（共 \(catalog.count) 款）:
        \(sampleTools)

        用户需求: \(input)
        """

        let response = try await session.respond(to: prompt, generating: InstallPayload.self)
        let payload = response.content

        return AIInstallOrchestrator.plan(
            from: AIInstallOrchestrator.NLInstallPayload(
                roleID: payload.roleID.nilIfEmpty,
                toolIDs: payload.toolIDs.isEmpty ? nil : Array(payload.toolIDs.prefix(8)),
                autoInstall: payload.autoInstall
            ),
            roles: roles,
            catalog: catalog,
            summaryPrefix: "本机 AI 解析",
            fallbackInput: input
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

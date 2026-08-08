#if canImport(FoundationModels)
import FoundationModels
import Foundation

/// S14-04 — 发现页 NL 筛选，优先使用 Apple Intelligence 端侧模型。
@available(macOS 26.0, *)
enum AppleIntelligenceCatalogFilter {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static var unavailableReasonDescription: String? {
        guard !isAvailable else { return nil }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return "请在系统设置中启用 Apple Intelligence"
            case .deviceNotEligible:
                return "当前设备不支持 Apple Intelligence"
            case .modelNotReady:
                return "本地模型尚未就绪，请稍后再试"
            @unknown default:
                return "Apple Intelligence 暂不可用"
            }
        @unknown default:
            return "Apple Intelligence 暂不可用"
        }
    }

    @Generable
    struct FilterPayload {
        @Guide(description: "ToolCategory rawValue，无则留空")
        var category: String

        @Guide(description: "all、installable 或 manual，无则 all")
        var sourceFilter: String

        @Guide(description: "all、popular 或 role，无则 all")
        var scopeFilter: String

        @Guide(description: "岗位 bundle id，无则留空")
        var roleID: String

        @Guide(description: "cli 或 gui，无则留空")
        var kind: String

        @Guide(description: "formula、cask、mas、script 或 link，无则留空")
        var sourceType: String

        @Guide(description: "剩余搜索关键词，无则留空")
        var keywords: String

        @Guide(description: "最多 8 个 catalog tool id")
        var toolIDs: [String]
    }

    static func plan(
        input: String,
        catalog: [DevTool],
        roles: [RoleBundle]
    ) async throws -> DiscoverNLFilterPlan? {
        guard isAvailable else { return nil }

        let categories = ToolCategory.allCases.filter { $0 != .all }.map { $0.rawValue }.joined(separator: ", ")
        let roleLines = roles.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
        let sampleTools = catalog.prefix(36).map { "- \($0.id): \($0.name)" }.joined(separator: "\n")

        let session = LanguageModelSession {
            """
            你是 Mac 软件目录筛选助手。根据用户自然语言，输出结构化筛选条件。
            category 必须从给定列表选择或留空；toolIDs 必须从 catalog id 选择，最多 8 个。
            """
        }

        let prompt = """
        可选 category: \(categories)
        岗位:
        \(roleLines)

        Catalog 示例（共 \(catalog.count) 款）:
        \(sampleTools)

        用户需求: \(input)
        """

        let response = try await session.respond(to: prompt, generating: FilterPayload.self)
        let payload = response.content

        return CatalogNLFilterService.plan(
            from: CatalogNLFilterService.NLFilterPayload(
                category: payload.category.nilIfEmpty,
                sourceFilter: payload.sourceFilter.nilIfEmpty,
                scopeFilter: payload.scopeFilter.nilIfEmpty,
                roleID: payload.roleID.nilIfEmpty,
                kind: payload.kind.nilIfEmpty,
                sourceType: payload.sourceType.nilIfEmpty,
                keywords: payload.keywords.nilIfEmpty,
                toolIDs: payload.toolIDs.isEmpty ? nil : Array(payload.toolIDs.prefix(8))
            ),
            catalog: catalog,
            summaryPrefix: "本机 AI 筛选"
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

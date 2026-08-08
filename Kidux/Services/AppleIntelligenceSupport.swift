import Foundation

/// Apple Intelligence 能力探测与统一入口（S14-04+）。
enum AppleIntelligenceSupport {
    static var isCatalogFilterAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return AppleIntelligenceCatalogFilter.isAvailable
        }
        #endif
        return false
    }

    static var catalogFilterStatusLine: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if AppleIntelligenceCatalogFilter.isAvailable {
                return "Apple Intelligence 可用于发现页筛选、装机意图、失败诊断与环境漂移解读（端侧、无需 API Key）"
            }
            if let reason = AppleIntelligenceCatalogFilter.unavailableReasonDescription {
                return reason
            }
        }
        #endif
        if #available(macOS 26.0, *) {
            return "Apple Intelligence 未就绪"
        }
        return "发现页筛选与装机意图的本机 AI 需要 macOS 26 或更高版本"
    }

    static func planInstallIntent(
        input: String,
        roles: [RoleBundle],
        catalog: [DevTool]
    ) async throws -> NLInstallPlan? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await AppleIntelligenceInstallPlan.plan(
                input: input,
                roles: roles,
                catalog: catalog
            )
        }
        #endif
        return nil
    }

    static func planCatalogFilter(
        input: String,
        catalog: [DevTool],
        roles: [RoleBundle]
    ) async throws -> DiscoverNLFilterPlan? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await AppleIntelligenceCatalogFilter.plan(
                input: input,
                catalog: catalog,
                roles: roles
            )
        }
        #endif
        return nil
    }

    static func diagnoseInstallFailures(logs: String) async throws -> AIAssistantReply? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await AppleIntelligenceInstallDiagnosis.diagnose(logs: logs)
        }
        #endif
        return nil
    }

    static func explainEnvironmentDrift(
        report: EnvironmentDriftReport,
        baselineLabel: String
    ) async throws -> EnvironmentDriftExplanation? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await AppleIntelligenceDriftExplanation.explain(
                report: report,
                baselineLabel: baselineLabel
            )
        }
        #endif
        return nil
    }
}

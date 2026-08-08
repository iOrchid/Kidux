import Foundation

/// OpenAI 兼容 API 服务商
enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case siliconFlow
    case deepseek
    case dashscope
    case doubao
    case moonshot
    case hunyuan
    case minimax
    case zhipu
    case openAI
    case anthropic
    case google
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .siliconFlow: return "硅基流动"
        case .deepseek: return "DeepSeek 官方"
        case .dashscope: return "通义千问（DashScope）"
        case .doubao: return "豆包（火山方舟）"
        case .moonshot: return "Kimi（月之暗面）"
        case .hunyuan: return "腾讯混元"
        case .minimax: return "MiniMax"
        case .zhipu: return "智谱 AI"
        case .openAI: return "OpenAI"
        case .anthropic: return "Claude（Anthropic）"
        case .google: return "Gemini（Google）"
        case .custom: return "自定义（OpenAI 兼容）"
        }
    }

    var consoleURL: String {
        switch self {
        case .siliconFlow: return "https://cloud.siliconflow.cn/"
        case .deepseek: return "https://platform.deepseek.com/"
        case .dashscope: return "https://dashscope.console.aliyun.com/"
        case .doubao: return "https://console.volcengine.com/ark"
        case .moonshot: return "https://platform.moonshot.cn/"
        case .hunyuan: return "https://cloud.tencent.com/product/hunyuan"
        case .minimax: return "https://platform.minimaxi.com/"
        case .zhipu: return "https://open.bigmodel.cn/"
        case .openAI: return "https://platform.openai.com/api-keys"
        case .anthropic: return "https://console.anthropic.com/"
        case .google: return "https://aistudio.google.com/apikey"
        case .custom: return "https://platform.openai.com/docs/api-reference"
        }
    }

    /// OpenAI 兼容 chat/completions 根路径（不含尾部斜杠）
    var defaultBaseURL: String {
        switch self {
        case .siliconFlow: return "https://api.siliconflow.cn/v1"
        case .deepseek: return "https://api.deepseek.com"
        case .dashscope: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3"
        case .moonshot: return "https://api.moonshot.cn/v1"
        case .hunyuan: return "https://api.hunyuan.cloud.tencent.com/v1"
        case .minimax: return "https://api.minimax.chat/v1"
        case .zhipu: return "https://open.bigmodel.cn/api/paas/v4"
        case .openAI: return "https://api.openai.com/v1"
        // Anthropic / Google 官方原生协议不同；此处提供常见 OpenAI 兼容网关默认值，可在自定义中改。
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .custom: return "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        AIModelCatalogService.defaultModel(for: self)
    }

    var keyPlaceholder: String {
        switch self {
        case .siliconFlow, .deepseek, .openAI: return "sk-…"
        case .dashscope: return "sk-…（DashScope API Key）"
        case .doubao: return "方舟 API Key"
        case .moonshot: return "sk-…（Moonshot API Key）"
        case .hunyuan: return "腾讯混元 API Key"
        case .minimax: return "MiniMax API Key"
        case .zhipu: return "智谱 API Key"
        case .anthropic: return "sk-ant-…"
        case .google: return "AIza…（Google AI Studio）"
        case .custom: return "API Key"
        }
    }

    /// 来自可热更新的模型目录（内置最新 + 远程 JSON）。
    var modelPresets: [(id: String, name: String)] {
        AIModelCatalogService.models(for: self)
    }

    func resolvedModelPresets(customModel: String) -> [(id: String, name: String)] {
        var presets = modelPresets
        let migrated = AIModelCatalogService.migrateModelID(customModel)
        if !migrated.isEmpty, !presets.contains(where: { $0.id == migrated }) {
            presets.append((migrated, migrated))
        }
        return presets
    }
}

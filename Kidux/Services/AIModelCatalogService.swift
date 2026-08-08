import Foundation

/// AI 模型目录：内置最新预设 + 可从远程 JSON 热更新（无需发版）。
final class AIModelCatalogStore: @unchecked Sendable {
    static let shared = AIModelCatalogStore()

    /// AI 模型远程目录（见 `RepositoryConfig`）。
    static let remoteCatalogURL = RepositoryConfig.aiModelCatalogURL

    private let lock = NSLock()
    private var catalog: AIModelCatalog = .builtin
    private var sourceLabelStorage: String = "内置"
    private var lastStatusMessageStorage: String?

    private let cacheFileName = "ai-model-catalog.json"
    private let cachedVersionKey = "ai.modelCatalog.cachedVersion"
    private let cachedUpdatedAtKey = "ai.modelCatalog.cachedUpdatedAt"
    private let lastCheckKey = "ai.modelCatalog.lastCheckAt"

    var currentCatalog: AIModelCatalog {
        lock.lock(); defer { lock.unlock() }
        return catalog
    }

    var sourceLabel: String {
        lock.lock(); defer { lock.unlock() }
        return sourceLabelStorage
    }

    var lastStatusMessage: String? {
        lock.lock(); defer { lock.unlock() }
        return lastStatusMessageStorage
    }

    func bootstrap() {
        if let cached = loadCachedCatalog(), cached.version >= AIModelCatalog.builtin.version {
            setCatalog(cached, source: "已缓存 v\(cached.version)")
        } else {
            setCatalog(.builtin, source: "内置 v\(AIModelCatalog.builtin.version)")
        }
        Task { @MainActor in
            Self.migrateStoredModelIfNeeded()
        }
    }

    /// 设置页「更新模型列表」与启动后台检查共用。
    func refreshFromRemote(force: Bool = false) async -> String {
        if !force,
           let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 6 * 3600 {
            let msg = "模型列表仍是最新（\(sourceLabel)）"
            setStatus(msg)
            return msg
        }

        do {
            var request = URLRequest(url: Self.remoteCatalogURL)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let remote = try JSONDecoder().decode(AIModelCatalog.self, from: data)
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            if remote.version >= currentCatalog.version {
                try storeCache(data: data, catalog: remote)
                setCatalog(remote, source: "远程 v\(remote.version)")
                await MainActor.run { Self.migrateStoredModelIfNeeded() }
                let msg = "已更新到 v\(remote.version)（\(remote.updatedAt)）"
                setStatus(msg)
                return msg
            } else {
                let msg = "远程版本较旧，继续使用 \(sourceLabel)"
                setStatus(msg)
                return msg
            }
        } catch {
            let msg = "更新失败：\(error.localizedDescription)。仍使用 \(sourceLabel)"
            setStatus(msg)
            return msg
        }
    }

    func models(for provider: AIProvider) -> [(id: String, name: String)] {
        currentCatalog.providers[provider.rawValue]?.models.map { ($0.id, $0.name) } ?? []
    }

    func defaultModel(for provider: AIProvider) -> String {
        currentCatalog.providers[provider.rawValue]?.defaultModel
            ?? AIModelCatalog.builtin.providers[provider.rawValue]?.defaultModel
            ?? "gpt-5.6"
    }

    func migrateModelID(_ id: String) -> String {
        let cat = currentCatalog
        return cat.migrations[id] ?? AIModelCatalog.builtin.migrations[id] ?? id
    }

    private func setCatalog(_ value: AIModelCatalog, source: String) {
        lock.lock()
        catalog = value
        sourceLabelStorage = source
        lock.unlock()
    }

    private func setStatus(_ message: String) {
        lock.lock()
        lastStatusMessageStorage = message
        lock.unlock()
    }

    @MainActor
    private static func migrateStoredModelIfNeeded() {
        let settings = AppSettings.shared
        let current = settings.aiModel
        let migrated = AIModelCatalogStore.shared.migrateModelID(current)
        if migrated != current {
            settings.aiModel = migrated
        }
    }

    private func cacheURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Kidux", isDirectory: true)
            .appendingPathComponent(cacheFileName)
    }

    private func loadCachedCatalog() -> AIModelCatalog? {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AIModelCatalog.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func storeCache(data: Data, catalog: AIModelCatalog) throws {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Kidux", isDirectory: true) else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(cacheFileName)
        try data.write(to: url, options: .atomic)
        UserDefaults.standard.set(catalog.version, forKey: cachedVersionKey)
        UserDefaults.standard.set(catalog.updatedAt, forKey: cachedUpdatedAtKey)
    }
}

enum AIModelCatalogService {
    static func bootstrap() { AIModelCatalogStore.shared.bootstrap() }

    static func refreshFromRemote(force: Bool = false) async -> String {
        await AIModelCatalogStore.shared.refreshFromRemote(force: force)
    }

    static var sourceLabel: String { AIModelCatalogStore.shared.sourceLabel }

    static func models(for provider: AIProvider) -> [(id: String, name: String)] {
        AIModelCatalogStore.shared.models(for: provider)
    }

    static func defaultModel(for provider: AIProvider) -> String {
        AIModelCatalogStore.shared.defaultModel(for: provider)
    }

    static func migrateModelID(_ id: String) -> String {
        AIModelCatalogStore.shared.migrateModelID(id)
    }
}

struct AIModelCatalog: Codable, Sendable {
    var version: Int
    var updatedAt: String
    var providers: [String: ProviderEntry]
    var migrations: [String: String]

    struct ProviderEntry: Codable, Sendable {
        var defaultModel: String
        var models: [ModelEntry]
    }

    struct ModelEntry: Codable, Sendable {
        var id: String
        var name: String
    }

    static let builtin = AIModelCatalog(
        version: 4,
        updatedAt: "2026-08-07",
        providers: [
            "siliconFlow": .init(defaultModel: "deepseek-ai/DeepSeek-V4-Pro", models: [
                .init(id: "deepseek-ai/DeepSeek-V4-Pro", name: "DeepSeek V4 Pro"),
                .init(id: "deepseek-ai/DeepSeek-V4-Flash", name: "DeepSeek V4 Flash"),
                .init(id: "deepseek-ai/DeepSeek-V3.2", name: "DeepSeek V3.2"),
                .init(id: "deepseek-ai/DeepSeek-R1", name: "DeepSeek R1"),
                .init(id: "Qwen/Qwen3-32B", name: "Qwen3 32B"),
                .init(id: "Qwen/Qwen3-14B", name: "Qwen3 14B"),
                .init(id: "Qwen/Qwen3-8B", name: "Qwen3 8B"),
                .init(id: "zai-org/GLM-4.7", name: "GLM-4.7"),
                .init(id: "zai-org/GLM-4.6", name: "GLM-4.6"),
                .init(id: "zai-org/GLM-4.5-Air", name: "GLM-4.5 Air")
            ]),
            "deepseek": .init(defaultModel: "deepseek-v4-pro", models: [
                .init(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro"),
                .init(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash")
            ]),
            "dashscope": .init(defaultModel: "qwen-plus", models: [
                .init(id: "qwen-plus", name: "Qwen Plus"),
                .init(id: "qwen-max", name: "Qwen Max"),
                .init(id: "qwen-turbo", name: "Qwen Turbo"),
                .init(id: "qwen-long", name: "Qwen Long"),
                .init(id: "qwq-plus", name: "QwQ Plus"),
                .init(id: "qwen3-coder-plus", name: "Qwen3 Coder Plus")
            ]),
            "doubao": .init(defaultModel: "doubao-seed-1-6-250615", models: [
                .init(id: "doubao-seed-1-6-250615", name: "豆包 Seed 1.6"),
                .init(id: "doubao-seed-1-6-flash-250615", name: "豆包 Seed 1.6 Flash"),
                .init(id: "doubao-1-5-pro-32k-250115", name: "豆包 1.5 Pro 32K"),
                .init(id: "doubao-1-5-lite-32k-250115", name: "豆包 1.5 Lite 32K")
            ]),
            "minimax": .init(defaultModel: "MiniMax-Text-01", models: [
                .init(id: "MiniMax-Text-01", name: "MiniMax Text 01"),
                .init(id: "MiniMax-M1", name: "MiniMax M1")
            ]),
            "zhipu": .init(defaultModel: "glm-4.5-flash", models: [
                .init(id: "glm-4.5", name: "GLM-4.5"),
                .init(id: "glm-4.5-air", name: "GLM-4.5 Air"),
                .init(id: "glm-4.5-flash", name: "GLM-4.5 Flash"),
                .init(id: "glm-4-plus", name: "GLM-4 Plus"),
                .init(id: "glm-4-air", name: "GLM-4 Air")
            ]),
            "moonshot": .init(defaultModel: "kimi-latest", models: [
                .init(id: "kimi-latest", name: "Kimi Latest"),
                .init(id: "moonshot-v1-128k", name: "Moonshot V1 128K"),
                .init(id: "moonshot-v1-32k", name: "Moonshot V1 32K"),
                .init(id: "moonshot-v1-8k", name: "Moonshot V1 8K")
            ]),
            "hunyuan": .init(defaultModel: "hunyuan-turbos-latest", models: [
                .init(id: "hunyuan-turbos-latest", name: "混元 TurboS"),
                .init(id: "hunyuan-t1-latest", name: "混元 T1"),
                .init(id: "hunyuan-large", name: "混元 Large"),
                .init(id: "hunyuan-standard", name: "混元 Standard"),
                .init(id: "hunyuan-lite", name: "混元 Lite")
            ]),
            "openAI": .init(defaultModel: "gpt-5.6", models: [
                .init(id: "gpt-5.6", name: "GPT-5.6（Sol）"),
                .init(id: "gpt-5.6-sol", name: "GPT-5.6 Sol"),
                .init(id: "gpt-5.6-terra", name: "GPT-5.6 Terra"),
                .init(id: "gpt-5.6-luna", name: "GPT-5.6 Luna")
            ]),
            "anthropic": .init(defaultModel: "claude-sonnet-5", models: [
                .init(id: "claude-sonnet-5", name: "Claude Sonnet 5"),
                .init(id: "claude-opus-4-8", name: "Claude Opus 4.8"),
                .init(id: "claude-haiku-4-5", name: "Claude Haiku 4.5")
            ]),
            "google": .init(defaultModel: "gemini-2.5-pro", models: [
                .init(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro"),
                .init(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash"),
                .init(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash")
            ]),
            "custom": .init(defaultModel: "gpt-5.6", models: [
                .init(id: "gpt-5.6", name: "GPT-5.6（Sol）"),
                .init(id: "claude-sonnet-5", name: "Claude Sonnet 5"),
                .init(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro"),
                .init(id: "kimi-latest", name: "Kimi Latest")
            ])
        ],
        migrations: [
            "deepseek-chat": "deepseek-v4-flash",
            "deepseek-reasoner": "deepseek-v4-pro",
            "deepseek-ai/DeepSeek-V3": "deepseek-ai/DeepSeek-V4-Pro",
            "deepseek-ai/DeepSeek-V3.2": "deepseek-ai/DeepSeek-V4-Pro",
            "gpt-4o": "gpt-5.6",
            "gpt-4o-mini": "gpt-5.6-luna",
            "gpt-4.1": "gpt-5.6",
            "gpt-4.1-mini": "gpt-5.6-terra",
            "o4-mini": "gpt-5.6-luna",
            "claude-sonnet-4-20250514": "claude-sonnet-5",
            "claude-3-5-haiku-20241022": "claude-haiku-4-5",
            "doubao-pro-32k": "doubao-seed-1-6-250615",
            "doubao-lite-32k": "doubao-seed-1-6-flash-250615",
            "abab6.5s-chat": "MiniMax-Text-01",
            "abab6.5g-chat": "MiniMax-M1",
            "glm-4-flash": "glm-4.5-flash",
            "moonshot-v1-auto": "kimi-latest",
            "kimi-k2.5": "kimi-latest"
        ]
    )
}

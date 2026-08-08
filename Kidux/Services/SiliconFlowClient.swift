import Foundation

enum LLMClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先在设置中填写 API Key"
        case .invalidResponse: return "AI 服务返回格式异常"
        case .apiError(let msg): return msg
        case .cancelled: return "已取消生成"
        }
    }
}

typealias SiliconFlowError = LLMClientError

struct AIChatParameters: Sendable {
    var model: String = AIProvider.siliconFlow.defaultModel
    var temperature: Double = 0.7
    var maxTokens: Int = 1024
    var stream: Bool = true
    var baseURL: String = AIProvider.siliconFlow.defaultBaseURL
}

struct LLMToolCall: Sendable, Equatable {
    let id: String
    let name: String
    let arguments: String
}

struct LLMChatCompletion: Sendable {
    let content: String?
    let toolCalls: [LLMToolCall]
}

enum LLMConversationMessage: Sendable {
    case system(String)
    case user(String)
    case assistant(String)
    case assistantToolCalls([LLMToolCall])
    case toolResult(callID: String, content: String)
}

/// OpenAI 兼容 Chat Completions 客户端（硅基流动 / DeepSeek / 千问等）
actor SiliconFlowClient {
    static let defaultBaseURL = AIProvider.siliconFlow.defaultBaseURL
    static let defaultModel = AIProvider.siliconFlow.defaultModel

    static var modelPresets: [(id: String, name: String)] {
        AIProvider.siliconFlow.modelPresets
    }

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String?
            let tool_calls: [ToolCallPayload]?
            let tool_call_id: String?

            init(role: String, content: String?) {
                self.role = role
                self.content = content
                self.tool_calls = nil
                self.tool_call_id = nil
            }

            init(role: String, content: String?, toolCalls: [ToolCallPayload]) {
                self.role = role
                self.content = content
                self.tool_calls = toolCalls
                self.tool_call_id = nil
            }

            init(toolCallID: String, content: String) {
                self.role = "tool"
                self.content = content
                self.tool_calls = nil
                self.tool_call_id = toolCallID
            }
        }

        struct ToolCallPayload: Encodable {
            struct FunctionPayload: Encodable {
                let name: String
                let arguments: String
            }

            let id: String
            let type: String
            let function: FunctionPayload
        }

        struct ToolDefinition: Encodable {
            struct FunctionDefinition: Encodable {
                let name: String
                let description: String
                let parameters: [String: AnyEncodable]
            }

            let type: String
            let function: FunctionDefinition
        }

        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int
        let stream: Bool
        let tools: [ToolDefinition]?
        let tool_choice: String?
    }

    private struct AnyEncodable: Encodable {
        let value: Any

        init(_ value: Any) {
            self.value = value
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch value {
            case let v as String: try container.encode(v)
            case let v as Int: try container.encode(v)
            case let v as Bool: try container.encode(v)
            case let v as [String: AnyEncodable]: try container.encode(v)
            case let v as [AnyEncodable]: try container.encode(v)
            default:
                throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
            }
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                struct ToolCallResponse: Decodable {
                    struct FunctionResponse: Decodable {
                        let name: String
                        let arguments: String
                    }

                    let id: String
                    let function: FunctionResponse
                }

                let content: String?
                let tool_calls: [ToolCallResponse]?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta
        }
        let choices: [Choice]
    }

    private struct APIErrorBody: Decodable {
        struct Detail: Decodable {
            let message: String?
        }
        let error: Detail?
        let message: String?
    }

    func chat(
        apiKey: String,
        messages: [(role: String, content: String)],
        parameters: AIChatParameters = AIChatParameters()
    ) async throws -> String {
        var params = parameters
        params.stream = false
        return try await requestText(apiKey: apiKey, messages: messages, parameters: params)
    }

    func chatCompletion(
        apiKey: String,
        messages: [LLMConversationMessage],
        parameters: AIChatParameters = AIChatParameters()
    ) async throws -> LLMChatCompletion {
        var params = parameters
        params.stream = false
        return try await requestCompletion(
            apiKey: apiKey,
            messages: messages.map { Self.encodeMessage($0) },
            parameters: params,
            tools: Self.buildAgentTools()
        )
    }

    private static func buildAgentTools() -> [ChatRequest.ToolDefinition] {
        func object(_ pairs: [(String, AnyEncodable)]) -> [String: AnyEncodable] {
            Dictionary(uniqueKeysWithValues: pairs)
        }

        let emptyObject = object([
            ("type", AnyEncodable("object")),
            ("properties", AnyEncodable(object([])))
        ])
        let querySchema = object([
            ("type", AnyEncodable("object")),
            ("properties", AnyEncodable(object([
                ("query", AnyEncodable(object([
                    ("type", AnyEncodable("string")),
                    ("description", AnyEncodable("搜索关键词"))
                ])))
            ]))),
            ("required", AnyEncodable([AnyEncodable("query")]))
        ])
        let roleSchema = object([
            ("type", AnyEncodable("object")),
            ("properties", AnyEncodable(object([
                ("role_id", AnyEncodable(object([
                    ("type", AnyEncodable("string")),
                    ("description", AnyEncodable("岗位 id"))
                ])))
            ]))),
            ("required", AnyEncodable([AnyEncodable("role_id")]))
        ])
        let installSchema = object([
            ("type", AnyEncodable("object")),
            ("properties", AnyEncodable(object([
                ("tool_ids", AnyEncodable(object([
                    ("type", AnyEncodable("array")),
                    ("items", AnyEncodable(object([("type", AnyEncodable("string"))]))),
                    ("description", AnyEncodable("Catalog 工具 id 列表"))
                ]))),
                ("auto_install", AnyEncodable(object([
                    ("type", AnyEncodable("boolean")),
                    ("description", AnyEncodable("是否立即开始安装"))
                ])))
            ]))),
            ("required", AnyEncodable([AnyEncodable("tool_ids")]))
        ])

        return [
            .init(type: "function", function: .init(
                name: "search_catalog",
                description: "在软件目录中搜索，返回匹配的 tool id 与名称",
                parameters: querySchema
            )),
            .init(type: "function", function: .init(
                name: "scan_installed",
                description: "扫描本机已安装应用与 brew/mas 状态",
                parameters: emptyObject
            )),
            .init(type: "function", function: .init(
                name: "select_role",
                description: "选择岗位 Bundle 并进入工具清单",
                parameters: roleSchema
            )),
            .init(type: "function", function: .init(
                name: "install_tools",
                description: "将工具加入安装清单，可选立即安装",
                parameters: installSchema
            ))
        ]
    }

    func chatStream(
        apiKey: String,
        messages: [(role: String, content: String)],
        parameters: AIChatParameters = AIChatParameters(),
        onDelta: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        try await requestText(apiKey: apiKey, messages: messages, parameters: parameters, onDelta: onDelta)
    }

    /// 测试 API Key 是否有效
    func testConnection(apiKey: String, model: String, baseURL: String) async throws -> String {
        let text = try await chat(
            apiKey: apiKey,
            messages: [("user", "回复 OK 两个字母即可")],
            parameters: AIChatParameters(model: model, temperature: 0, maxTokens: 16, stream: false, baseURL: baseURL)
        )
        return text
    }

    private func requestText(
        apiKey: String,
        messages: [(role: String, content: String)],
        parameters: AIChatParameters,
        onDelta: @Sendable @escaping (String) -> Void = { _ in }
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMClientError.missingAPIKey }

        guard let url = URL(string: "\(parameters.baseURL)/chat/completions") else {
            throw LLMClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body = ChatRequest(
            model: parameters.model,
            messages: messages.map { ChatRequest.Message(role: $0.role, content: $0.content) },
            temperature: parameters.temperature,
            max_tokens: parameters.maxTokens,
            stream: parameters.stream,
            tools: nil,
            tool_choice: nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        if parameters.stream {
            return try await streamRequest(request: request, onDelta: onDelta)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw LLMClientError.invalidResponse
        }
        return text
    }

    private func requestCompletion(
        apiKey: String,
        messages: [ChatRequest.Message],
        parameters: AIChatParameters,
        tools: [ChatRequest.ToolDefinition]?
    ) async throws -> LLMChatCompletion {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMClientError.missingAPIKey }

        guard let url = URL(string: "\(parameters.baseURL)/chat/completions") else {
            throw LLMClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body = ChatRequest(
            model: parameters.model,
            messages: messages,
            temperature: parameters.temperature,
            max_tokens: parameters.maxTokens,
            stream: false,
            tools: tools,
            tool_choice: tools == nil ? nil : "auto"
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let message = decoded.choices.first?.message else {
            throw LLMClientError.invalidResponse
        }

        let toolCalls = (message.tool_calls ?? []).map {
            LLMToolCall(id: $0.id, name: $0.function.name, arguments: $0.function.arguments)
        }
        let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = (content?.isEmpty == false) ? content : nil

        if normalizedContent == nil, toolCalls.isEmpty {
            throw LLMClientError.invalidResponse
        }
        return LLMChatCompletion(content: normalizedContent, toolCalls: toolCalls)
    }

    private func request(
        apiKey: String,
        messages: [(role: String, content: String)],
        parameters: AIChatParameters,
        onDelta: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        try await requestText(apiKey: apiKey, messages: messages, parameters: parameters, onDelta: onDelta)
    }

    private static func encodeMessage(_ message: LLMConversationMessage) -> ChatRequest.Message {
        switch message {
        case .system(let text), .user(let text), .assistant(let text):
            let role: String
            switch message {
            case .system: role = "system"
            case .user: role = "user"
            case .assistant: role = "assistant"
            default: role = "user"
            }
            return ChatRequest.Message(role: role, content: text)
        case .assistantToolCalls(let calls):
            return ChatRequest.Message(
                role: "assistant",
                content: nil,
                toolCalls: calls.map {
                    ChatRequest.ToolCallPayload(
                        id: $0.id,
                        type: "function",
                        function: .init(name: $0.name, arguments: $0.arguments)
                    )
                }
            )
        case .toolResult(let callID, let content):
            return ChatRequest.Message(toolCallID: callID, content: content)
        }
    }

    private func streamRequest(
        request: URLRequest,
        onDelta: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            try validateHTTP(response: response, data: data)
            throw LLMClientError.invalidResponse
        }

        var fullText = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let piece = chunk.choices.first?.delta.content,
                  !piece.isEmpty
            else { continue }
            fullText += piece
            onDelta(piece)
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMClientError.invalidResponse }
        return trimmed
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if let err = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                let msg = err.error?.message ?? err.message ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw LLMClientError.apiError(msg)
            }
            throw LLMClientError.apiError("HTTP \(http.statusCode)")
        }
    }
}

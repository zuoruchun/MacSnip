import Foundation

public enum LLMServiceError: LocalizedError {
    case invalidURL(String)
    case missingAPIKey
    case networkError(String)
    case httpError(statusCode: Int, message: String)
    case invalidResponse
    case decodingError(String)
    case emptyResult
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效的 API 地址: \(url)"
        case .missingAPIKey:
            return "未配置 API Key，请在设置中添加。"
        case .networkError(let message):
            return "网络请求失败: \(message)"
        case .httpError(let statusCode, let message):
            return "API 请求错误 (HTTP \(statusCode)): \(message)"
        case .invalidResponse:
            return "服务器返回了无效的数据格式。"
        case .decodingError(let message):
            return "解析服务器响应失败: \(message)"
        case .emptyResult:
            return "翻译结果为空。"
        }
    }
}

public final class LLMService {
    public static let shared = LLMService()
    
    private let urlSession: URLSession
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: configuration)
    }
    
    /// 执行翻译请求
    public func translate(
        text: String,
        profile: LLMProfile,
        apiKey: String
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw LLMServiceError.missingAPIKey
        }
        
        switch profile.format {
        case .openAICompatible:
            return try await requestOpenAI(text: text, profile: profile, apiKey: trimmedKey)
        case .anthropicNative:
            return try await requestAnthropic(text: text, profile: profile, apiKey: trimmedKey)
        }
    }
    
    // MARK: - OpenAI 兼容格式
    
    private func requestOpenAI(
        text: String,
        profile: LLMProfile,
        apiKey: String
    ) async throws -> String {
        var base = profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") {
            base.removeLast()
        }
        
        let endpoint: String
        if base.hasSuffix("/v1") || base.hasSuffix("/v1/chat/completions") {
            endpoint = base.hasSuffix("/v1/chat/completions") ? base : "\(base)/chat/completions"
        } else {
            endpoint = "\(base)/v1/chat/completions"
        }
        
        guard let url = URL(string: endpoint) else {
            throw LLMServiceError.invalidURL(endpoint)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let payload: [String: Any] = [
            "model": profile.modelName,
            "messages": [
                ["role": "system", "content": TranslationConstants.defaultSystemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            throw LLMServiceError.decodingError("无法序列化请求 JSON")
        }
        request.httpBody = httpBody
        
        let (data, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message?
            }
            let choices: [Choice]?
        }
        
        do {
            let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            guard let content = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
                throw LLMServiceError.emptyResult
            }
            return content
        } catch {
            throw LLMServiceError.decodingError(error.localizedDescription)
        }
    }
    
    // MARK: - Anthropic 原生格式
    
    private func requestAnthropic(
        text: String,
        profile: LLMProfile,
        apiKey: String
    ) async throws -> String {
        var base = profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") {
            base.removeLast()
        }
        
        let endpoint: String
        if base.hasSuffix("/v1") || base.hasSuffix("/v1/messages") {
            endpoint = base.hasSuffix("/v1/messages") ? base : "\(base)/messages"
        } else {
            endpoint = "\(base)/v1/messages"
        }
        
        guard let url = URL(string: endpoint) else {
            throw LLMServiceError.invalidURL(endpoint)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let payload: [String: Any] = [
            "model": profile.modelName,
            "system": TranslationConstants.defaultSystemPrompt,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            throw LLMServiceError.decodingError("无法序列化请求 JSON")
        }
        request.httpBody = httpBody
        
        let (data, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = String(data: data, encoding: .utf8) ?? "未知错误"
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        struct AnthropicResponse: Decodable {
            struct ContentBlock: Decodable {
                let type: String?
                let text: String?
            }
            let content: [ContentBlock]?
        }
        
        do {
            let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            let resultText = decoded.content?
                .compactMap { $0.text }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let result = resultText, !result.isEmpty else {
                throw LLMServiceError.emptyResult
            }
            return result
        } catch {
            throw LLMServiceError.decodingError(error.localizedDescription)
        }
    }
    
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw LLMServiceError.networkError(error.localizedDescription)
        }
    }
}

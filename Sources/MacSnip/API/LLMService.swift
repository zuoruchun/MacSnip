import Foundation
import CommonCrypto

public enum LLMServiceError: LocalizedError {
    case invalidURL(String)
    case missingAPIKey
    case invalidAPIKeyFormat(String)
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
        case .invalidAPIKeyFormat(let msg):
            return "API Key 格式错误: \(msg)"
        case .networkError(let message):
            return "网络请求失败: \(message)"
        case .httpError(let statusCode, let message):
            return "API 响应错误 (HTTP \(statusCode)): \(message)"
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
        case .aliyunMT:
            return try await requestAliyunMT(text: text, profile: profile, apiKey: trimmedKey)
        }
    }
    
    // MARK: - 1. OpenAI 兼容格式
    
    /// 智能拼接 OpenAI 兼容接口 endpoint
    private func buildOpenAIEndpoint(from baseURL: String) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        
        // 1. 如果用户已填写完整的 chat/completions 路径，直接使用
        if base.hasSuffix("/chat/completions") {
            return base
        }
        
        guard let url = URL(string: base) else {
            return "\(base)/chat/completions"
        }
        
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // 2. 如果路径已经包含版本段或已有 path（例如 "api/paas/v4" 或 "compatible-mode/v1" 或 "v1"）
        if !path.isEmpty {
            return "\(base)/chat/completions"
        } else {
            // 3. 纯域名（如 https://api.openai.com 或 https://api.deepseek.com）
            return "\(base)/v1/chat/completions"
        }
    }
    
    private func requestOpenAI(
        text: String,
        profile: LLMProfile,
        apiKey: String
    ) async throws -> String {
        let endpoint = buildOpenAIEndpoint(from: profile.baseURL)
        
        guard let url = URL(string: endpoint) else {
            throw LLMServiceError.invalidURL(endpoint)
        }
        
        print("[AI Request] URL: \(endpoint) | Method: POST | Model: \(profile.modelName) | Key: \(maskAPIKey(apiKey))")
        
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
        
        print("[AI Response] Status: \(httpResponse.statusCode) | Bytes: \(data.count)")
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            print("[AI Response Error] Body: \(errorBody)")
            
            let parsedMessage = parseErrorMessage(from: data) ?? errorBody
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, message: parsedMessage)
        }
        
        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                    let reasoning_content: String?
                }
                let message: Message?
            }
            let choices: [Choice]?
        }
        
        do {
            let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            let rawContent = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackContent = decoded.choices?.first?.message?.reasoning_content?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let content = (rawContent?.isEmpty == false ? rawContent : fallbackContent), !content.isEmpty else {
                throw LLMServiceError.emptyResult
            }
            return content
        } catch let err as LLMServiceError {
            throw err
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            print("[AI Decoding Error] \(error.localizedDescription) | Raw: \(rawBody)")
            throw LLMServiceError.decodingError("解析响应失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 2. Anthropic 原生格式
    
    /// 智能拼接 Anthropic 原生接口 endpoint
    private func buildAnthropicEndpoint(from baseURL: String) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        
        if base.hasSuffix("/messages") {
            return base
        }
        
        guard let url = URL(string: base) else {
            return "\(base)/messages"
        }
        
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty {
            return "\(base)/messages"
        } else {
            return "\(base)/v1/messages"
        }
    }
    
    private func requestAnthropic(
        text: String,
        profile: LLMProfile,
        apiKey: String
    ) async throws -> String {
        let endpoint = buildAnthropicEndpoint(from: profile.baseURL)
        
        guard let url = URL(string: endpoint) else {
            throw LLMServiceError.invalidURL(endpoint)
        }
        
        print("[AI Request] URL: \(endpoint) | Method: POST | Model: \(profile.modelName) | Key: \(maskAPIKey(apiKey))")
        
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
        
        print("[AI Response] Status: \(httpResponse.statusCode) | Bytes: \(data.count)")
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            print("[AI Response Error] Body: \(errorBody)")
            
            let parsedMessage = parseErrorMessage(from: data) ?? errorBody
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, message: parsedMessage)
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
        } catch let err as LLMServiceError {
            throw err
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            print("[AI Decoding Error] \(error.localizedDescription) | Raw: \(rawBody)")
            throw LLMServiceError.decodingError("解析响应失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 3. 阿里云通用机器翻译 (Alibaba Cloud Machine Translation)
    
    private func requestAliyunMT(
        text: String,
        profile: LLMProfile,
        apiKey: String
    ) async throws -> String {
        // API Key 格式: AccessKeyId:AccessKeySecret
        let keyParts = apiKey.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard keyParts.count == 2 else {
            throw LLMServiceError.invalidAPIKeyFormat("阿里云机器翻译需要同时提供 AccessKey ID 和 AccessKey Secret，格式为: AccessKeyId:AccessKeySecret")
        }
        
        let accessKeyId = String(keyParts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKeySecret = String(keyParts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !accessKeyId.isEmpty, !accessKeySecret.isEmpty else {
            throw LLMServiceError.invalidAPIKeyFormat("AccessKey ID 或 AccessKey Secret 不能为空。")
        }
        
        var base = profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if base.isEmpty {
            base = "https://mt.aliyuncs.com"
        }
        
        let action = profile.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "TranslateGeneral" : profile.modelName
        
        // 构造阿里云 POP RPC 请求参数
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let timestamp = dateFormatter.string(from: Date())
        let signatureNonce = UUID().uuidString
        
        var params: [String: String] = [
            "Action": action,
            "Format": "JSON",
            "Version": "2018-10-12",
            "AccessKeyId": accessKeyId,
            "SignatureMethod": "HMAC-SHA1",
            "Timestamp": timestamp,
            "SignatureVersion": "1.0",
            "SignatureNonce": signatureNonce,
            "FormatType": "text",
            "SourceLanguage": "auto",
            "TargetLanguage": "zh",
            "SourceText": text,
            "Scene": "general"
        ]
        
        // 计算签名 (POP RPC 签名算法)
        let signature = generateAliyunSignature(params: params, secret: accessKeySecret, httpMethod: "POST")
        params["Signature"] = signature
        
        // 构建 POST Body (x-www-form-urlencoded)
        let bodyString = params.map { "\($0.key)=\(percentEncode($0.value))" }.joined(separator: "&")
        guard let bodyData = bodyString.data(using: .utf8), let url = URL(string: base) else {
            throw LLMServiceError.invalidURL(base)
        }
        
        print("[AI Request] URL: \(base) (Aliyun MT) | Action: \(action) | AK: \(maskAPIKey(accessKeyId))")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        let (data, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse
        }
        
        print("[AI Response] Status: \(httpResponse.statusCode) | Bytes: \(data.count)")
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            print("[AI Response Error] Body: \(errorBody)")
            
            let parsedMessage = parseErrorMessage(from: data) ?? errorBody
            throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, message: parsedMessage)
        }
        
        struct AliyunMTResponse: Decodable {
            struct DataBlock: Decodable {
                let Translated: String?
                let WordCount: String?
            }
            let Code: String?
            let Message: String?
            let Data: DataBlock?
        }
        
        do {
            let decoded = try JSONDecoder().decode(AliyunMTResponse.self, from: data)
            if let code = decoded.Code, code != "200" {
                let msg = decoded.Message ?? "错误码 \(code)"
                throw LLMServiceError.httpError(statusCode: httpResponse.statusCode, message: msg)
            }
            guard let translated = decoded.Data?.Translated?.trimmingCharacters(in: .whitespacesAndNewlines), !translated.isEmpty else {
                throw LLMServiceError.emptyResult
            }
            return translated
        } catch let err as LLMServiceError {
            throw err
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            print("[AI Decoding Error] \(error.localizedDescription) | Raw: \(rawBody)")
            throw LLMServiceError.decodingError("解析阿里云响应失败: \(error.localizedDescription)")
        }
    }
    
    /// 阿里云 POP 规范化 Percent-Encoding (RFC 3986)
    private func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
    
    /// 阿里云 POP API 签名计算 (HMAC-SHA1)
    private func generateAliyunSignature(params: [String: String], secret: String, httpMethod: String) -> String {
        // 1. 字典序排列
        let sortedKeys = params.keys.sorted()
        let canonicalizedQuery = sortedKeys.map { key in
            "\(percentEncode(key))=\(percentEncode(params[key]!))"
        }.joined(separator: "&")
        
        // 2. 构造待签名字符串
        let stringToSign = "\(httpMethod)&%2F&" + percentEncode(canonicalizedQuery)
        
        // 3. HMAC-SHA1 计算
        let key = secret + "&"
        guard let keyData = key.data(using: .utf8),
              let stringData = stringToSign.data(using: .utf8) else {
            return ""
        }
        
        var result = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        stringData.withUnsafeBytes { strBytes in
            keyData.withUnsafeBytes { keyBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), keyBytes.baseAddress, keyData.count, strBytes.baseAddress, stringData.count, &result)
            }
        }
        
        return Data(result).base64EncodedString()
    }
    
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw LLMServiceError.networkError(error.localizedDescription)
        }
    }
    
    // MARK: - 辅助方法
    
    private func maskAPIKey(_ key: String) -> String {
        guard key.count > 8 else { return "******" }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)...\(suffix)"
    }
    
    private func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let errorObj = json["error"] as? [String: Any], let msg = errorObj["message"] as? String, !msg.isEmpty {
            return msg
        }
        if let msg = json["message"] as? String, !msg.isEmpty {
            return msg
        }
        if let msg = json["Message"] as? String, !msg.isEmpty {
            return msg
        }
        return nil
    }
}

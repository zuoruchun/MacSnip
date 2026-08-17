import Foundation

/// LLM 接口协议格式
public enum LLMProviderFormat: String, Codable, CaseIterable, Identifiable {
    case openAICompatible = "openai"
    case anthropicNative = "anthropic"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI 兼容"
        case .anthropicNative:
            return "Anthropic 原生"
        }
    }
}

/// 单套 LLM 供应商配置模型
public struct LLMProfile: Identifiable, Codable, Hashable, Equatable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var modelName: String
    public var format: LLMProviderFormat
    public var createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        modelName: String,
        format: LLMProviderFormat = .openAICompatible,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.modelName = modelName
        self.format = format
        self.createdAt = createdAt
    }
}

/// 预置供应商模板 — 2026年8月最新最便宜模型
public struct LLMPresetTemplate: Identifiable {
    public var id: String
    public var title: String
    public var defaultName: String
    public var defaultBaseURL: String
    public var defaultModelName: String
    public var format: LLMProviderFormat
    public var notes: String
    
    public static let allPresets: [LLMPresetTemplate] = [
        // 1. DeepSeek V4-Flash — 旧别名 deepseek-chat 已于 2026-07-24 停用
        LLMPresetTemplate(
            id: "deepseek",
            title: "DeepSeek V4-Flash",
            defaultName: "DeepSeek",
            defaultBaseURL: "https://api.deepseek.com",
            defaultModelName: "deepseek-v4-flash",
            format: .openAICompatible,
            notes: "DeepSeek 最新旗舰轻量版，极高性价比"
        ),
        
        // 2. 智谱 GLM-4.7-Flash — 免费额度，极速
        LLMPresetTemplate(
            id: "glm_flash",
            title: "智谱 GLM-4.7-Flash",
            defaultName: "GLM",
            defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4",
            defaultModelName: "glm-4.7-flash",
            format: .openAICompatible,
            notes: "智谱最新轻量免费模型，极速响应"
        ),
        
        // 3. 阿里云通义千问 Qwen3.7-Flash — 目前最低价
        LLMPresetTemplate(
            id: "qwen_flash",
            title: "通义千问 Qwen3.7-Flash",
            defaultName: "Qwen",
            defaultBaseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
            defaultModelName: "qwen3.7-flash",
            format: .openAICompatible,
            notes: "$0.03/$0.13 per 1M tokens，Qwen3 系列最便宜"
        ),
        
        // 4. OpenAI GPT-5.6 Luna — 最新最便宜 OpenAI 模型
        LLMPresetTemplate(
            id: "openai",
            title: "OpenAI GPT-5.6 Luna",
            defaultName: "OpenAI",
            defaultBaseURL: "https://api.openai.com",
            defaultModelName: "gpt-5.6-luna",
            format: .openAICompatible,
            notes: "$0.20/$1.20 per 1M tokens"
        ),
        
        // 5. Anthropic Claude Haiku 4.5 — 最新最便宜 Claude
        LLMPresetTemplate(
            id: "claude",
            title: "Claude Haiku 4.5",
            defaultName: "Claude",
            defaultBaseURL: "https://api.anthropic.com",
            defaultModelName: "claude-haiku-4-5-20251001",
            format: .anthropicNative,
            notes: "$1.00/$5.00 per 1M tokens"
        ),
        
        // 6. Moonshot Kimi
        LLMPresetTemplate(
            id: "moonshot",
            title: "Kimi (月之暗面)",
            defaultName: "Kimi",
            defaultBaseURL: "https://api.moonshot.cn/v1",
            defaultModelName: "moonshot-v1-8k",
            format: .openAICompatible,
            notes: "月之暗面官方接口，长文本中文表现优秀"
        ),
        
        // 7. 自定义中转聚合站
        LLMPresetTemplate(
            id: "custom_relay",
            title: "中转聚合站",
            defaultName: "中转 API",
            defaultBaseURL: "https://api.openai-proxy.org",
            defaultModelName: "deepseek-v4-flash",
            format: .openAICompatible,
            notes: "适用于各类 OneAPI / NewAPI 中转代理"
        )
    ]
}

/// 翻译常量
public enum TranslationConstants {
    public static let defaultSystemPrompt = "你是专业翻译，将用户提供的文本翻译为简体中文，只输出译文，不要解释"
}

import Foundation

// 对话域网络 DTO：字段名与可空性照 `hos/entry/src/main/ets/core/net/ChatDtos.ets` 逐项迁移。
// 服务端 snake_case 由 `HTTPClient.decode` 的 `convertFromSnakeCase` 统一转换；
// 数组/子对象一律可选，使用处兜底（契约 §2.8）。
// 这里只承载服务端形状，页面态模型（跨页参数、气泡模型）由 Features/Chat 自己定义。

// MARK: - 纠正与发音（§2.5 / §2.6）

/// 一轮里的「更自然」提示（`POST chat/sessions/:id/turn`、`GET .../messages` 共用）。
struct ChatCorrectionDTO: Decodable, Sendable {
    let hasError: Bool?
    /// grammar | vocabulary | politeness | pronunciation | none
    let type: String?
    let original: String?
    let better: String?
    let explainZh: String?
    /// low | medium | high
    let severity: String?
}

/// 最弱音：儿童账号 `ipa` 恒为 nil，只留 `label`（§2.6）。
struct ChatWeakPhonemeDTO: Decodable, Sendable {
    let ipa: String?
    let label: String?
    let score: Double?
}

struct ChatWordScoreDTO: Decodable, Sendable {
    let word: String?
    let score: Double?
}

/// 发音评分：只在 `GET chat/sessions/:id/messages` 里出现（§2.6）。
struct ChatPronDTO: Decodable, Sendable {
    let pron: Double?
    let accuracy: Double?
    let fluency: Double?
    let completeness: Double?
    let weakPhonemes: [ChatWeakPhonemeDTO]?
    let words: [ChatWordScoreDTO]?
}

// MARK: - 场景（§2.2 / §2.3 / §2.4）

/// 开会话时抽到的变体（§2.4）。
struct ChatVariationDTO: Decodable, Sendable {
    let persona: String?
    let place: String?
    let detail: String?
    let goal: String?
    let openingLine: String?
}

/// 对话场景。开会话后 `openingLine` 是抽到的变体开场白（显示与朗读都用它）。
struct ChatScenarioDTO: Decodable, Sendable {
    let id: String
    /// child | adult
    let audience: String?
    let isCustom: Bool?
    let title: String?
    let titleZh: String?
    let settingZh: String?
    let openingLine: String?
    let level: String?
    let minAge: Int?
    let tags: [String]?
    /// 仅自定义场景有效（0–5）
    let variationCount: Int?
    let variation: ChatVariationDTO?
    /// 新版服务端可能带自定义场景角色设定（列表不保证有）
    let rolePrompt: String?
}

/// `GET chat/scenarios[?include_child=1]` 的完整包体（分组与「已隐藏 N 个」提示要用）。
struct ChatScenarioListDTO: Decodable, Sendable {
    let age: Int?
    let isChild: Bool?
    /// 当前账号该看哪一类
    let audience: String?
    let includeChild: Bool?
    let count: Int?
    let customCount: Int?
    let hiddenCount: Int?
    let scenarios: [ChatScenarioDTO]?
}

/// `POST chat/scenarios` / `PATCH` / `DELETE chat/scenarios/:id` 的响应。
struct ChatScenarioMutationDTO: Decodable, Sendable {
    let ok: Bool?
    let id: String?
    let isCustom: Bool?
    let audience: String?
    let deleted: String?
}

// MARK: - 会话与消息（§2.4–§2.9）

struct ChatMessageDTO: Decodable, Sendable {
    let id: String
    /// user | assistant
    let role: String?
    let text: String?
    let textZh: String?
    let createdAt: String?
    let correction: ChatCorrectionDTO?
    /// 后台异步写入；只有 `GET .../messages` 带（§2.6）
    let pron: ChatPronDTO?
    let audioUrl: String?
    /// ok | unsafe_filtered | off_topic
    let flag: String?
}

struct ChatMessageListDTO: Decodable, Sendable {
    let sessionId: String?
    let messages: [ChatMessageDTO]?
}

/// `POST chat/sessions` 201（内置场景分支含 age/turn_count/messages；自定义分支更瘦）。
struct ChatSessionDTO: Decodable, Sendable {
    let sessionId: String
    let scenario: ChatScenarioDTO?
    let age: Int?
    let turnCount: Int?
    let messages: [ChatMessageDTO]?
    let isCustom: Bool?
}

/// `POST chat/sessions/:id/turn` 200（**不带 TTS 音频、不带发音分**）。
struct ChatTurnDTO: Decodable, Sendable {
    let sessionId: String?
    let provider: String?
    /// true = 本条是固定话术，不是大模型
    let degradedLlm: Bool?
    /// true = 调用失败降级到本地话术
    let degraded: Bool?
    let capabilities: ChatCapabilitiesDTO?
    let reply: String?
    let replyZh: String?
    let correction: ChatCorrectionDTO?
    let suggestedReplies: [String]?
    let targetWords: [String]?
    /// ok | unsafe_filtered | off_topic
    let flag: String?
    /// true = 本场景自然收尾
    let done: Bool?
    let turnIndex: Int?
    let messageId: String?
    let userMessageId: String?
    let userAudioUrl: String?
}

struct ChatCapabilitiesDTO: Decodable, Sendable {
    let phonemeLevel: Bool?
    let prosody: Bool?
    let intonationCurve: Bool?
    let ssml: Bool?
    let ocr: Bool?
    let image: Bool?
    let audioConcat: Bool?
    let chatDoneTurnIndex: Int?
    let features: [String]?
}

/// `POST chat/sessions/:id/end` 200（幂等）。
struct ChatEndDTO: Decodable, Sendable {
    let ok: Bool?
    let sessionId: String?
    let ended: Bool?
}

/// `GET chat/sessions/:id/audio/status`（只读，绝不触发构建）。
struct ChatAudioStatusDTO: Decodable, Sendable {
    /// ready | building | failed
    let status: String?
    let turnCount: Int?
    let autoRetry: Bool?
    let durationMs: Int?
    let error: String?
    let errorCode: String?
    let attempts: Int?
}

/// `GET chat/sessions/:id/audio` 202（构建中）的响应体。
struct ChatAudioBuildingDTO: Decodable, Sendable {
    let status: String?
    let turnCount: Int?
    let retryAfterMs: Int?
    let forced: Bool?
}

/// `GET chat/sessions` 列表项（§2.9）。
struct ChatSessionListItemDTO: Decodable, Sendable {
    let id: String
    let scenarioId: String?
    let scenarioTitle: String?
    let scenarioTitleZh: String?
    let startedAt: String?
    let endedAt: String?
    let turnCount: Int?
    let lastMessage: String?
}

struct ChatSessionListDTO: Decodable, Sendable {
    let sessions: [ChatSessionListItemDTO]?
}

/// `GET chat/sessions/:id` 详情（**无 pron**，pron 只能轮询 `/messages`）。
struct ChatSessionDetailDTO: Decodable, Sendable {
    let sessionId: String?
    let scenarioId: String?
    let scenarioTitle: String?
    let scenarioTitleZh: String?
    let turnCount: Int?
    let startedAt: String?
    let endedAt: String?
    let messages: [ChatMessageDTO]?
}

// MARK: - ASR（§2.5 第 ① 步）

/// `POST asr` 响应：`{text}`（部分版本叫 `transcript`）。
struct ChatAsrDTO: Decodable, Sendable {
    let text: String?
    let transcript: String?
}

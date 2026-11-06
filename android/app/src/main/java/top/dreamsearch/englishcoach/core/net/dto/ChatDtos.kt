package top.dreamsearch.englishcoach.core.net.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 对话训练 DTO（场景 / 会话 / 消息 / 一轮回复 / ASR）。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/net/ChatDtos.ets`。
 * 数据来源：`.specs/chat-story.md` §2（web 源码级契约）。
 *
 * 关键约定：
 * - 发音评分 `pron` **只**出现在 `GET /chat/sessions/:id/messages` 里，
 *   一轮 `turn` 的响应不含分数（§2.6）；
 * - 儿童账号的 `ChatWeakPhonemeDto.ipa` 恒为 null，只留 label；
 * - 请求体（`ChatScenarioBodyDto` 等）里 null 字段不序列化 ——
 *   PATCH 时「未传字段 = 取原值」，空串也按「不传」处理（与 hos 一致）。
 */

// ---------------------------------------------------------------------------
// 纠正与发音（§2.5 / §2.6）
// ---------------------------------------------------------------------------

/** 一轮里的「更自然」提示。 */
@Serializable
data class ChatCorrectionDto(
    @SerialName("has_error") val hasError: Boolean = false,
    /** grammar | vocabulary | politeness | pronunciation | none */
    val type: String = "",
    val original: String = "",
    val better: String = "",
    @SerialName("explain_zh") val explainZh: String = "",
    /** low | medium | high */
    val severity: String = "",
)

/** 最弱音：儿童账号 `ipa` 恒为 null，只留 label（§2.6）。 */
@Serializable
data class ChatWeakPhonemeDto(
    val ipa: String? = null,
    val label: String = "",
    val score: Double? = null,
)

@Serializable
data class ChatWordScoreDto(
    val word: String = "",
    val score: Double? = null,
)

/** 发音评分：只在 `GET /chat/sessions/:id/messages` 里出现（§2.6）。 */
@Serializable
data class ChatPronDto(
    val pron: Double? = null,
    val accuracy: Double? = null,
    val fluency: Double? = null,
    val completeness: Double? = null,
    @SerialName("weak_phonemes") val weakPhonemes: List<ChatWeakPhonemeDto> = emptyList(),
    val words: List<ChatWordScoreDto> = emptyList(),
)

// ---------------------------------------------------------------------------
// 场景（§2.2 / §2.3 / §2.4）
// ---------------------------------------------------------------------------

/** 开会话时抽到的变体（§2.4）。 */
@Serializable
data class ChatVariationDto(
    val persona: String = "",
    val place: String = "",
    val detail: String = "",
    val goal: String = "",
    @SerialName("opening_line") val openingLine: String = "",
)

/** 对话场景。`opening_line` 在开会话后是抽到的变体开场白（显示与朗读都用它）。 */
@Serializable
data class ChatScenarioDto(
    val id: String = "",
    /** child | adult */
    val audience: String = "",
    @SerialName("is_custom") val isCustom: Boolean = false,
    val title: String = "",
    @SerialName("title_zh") val titleZh: String = "",
    @SerialName("setting_zh") val settingZh: String = "",
    @SerialName("opening_line") val openingLine: String = "",
    val level: String = "",
    @SerialName("min_age") val minAge: Int = 0,
    val tags: List<String> = emptyList(),
    /** 仅自定义场景有效（0–5） */
    @SerialName("variation_count") val variationCount: Int = 0,
    val variation: ChatVariationDto? = null,
    /** 新版服务端可能带自定义场景角色设定（列表不保证有） */
    @SerialName("role_prompt") val rolePrompt: String = "",
)

/** `GET /api/chat/scenarios[?include_child=1]` */
@Serializable
data class ChatScenarioListDto(
    val age: Int = 0,
    @SerialName("is_child") val isChild: Boolean = false,
    /** 当前账号该看哪一类 */
    val audience: String = "",
    @SerialName("include_child") val includeChild: Boolean = false,
    val count: Int = 0,
    @SerialName("custom_count") val customCount: Int = 0,
    @SerialName("hidden_count") val hiddenCount: Int = 0,
    val scenarios: List<ChatScenarioDto> = emptyList(),
)

/** `POST /api/chat/scenarios` 201 / PATCH / DELETE 的响应。 */
@Serializable
data class ChatScenarioMutationDto(
    val ok: Boolean = false,
    val id: String = "",
    @SerialName("is_custom") val isCustom: Boolean = false,
    val audience: String = "",
    val deleted: String = "",
)

// ---------------------------------------------------------------------------
// 会话 / 消息（§2.4–§2.9）
// ---------------------------------------------------------------------------

@Serializable
data class ChatMessageDto(
    val id: String = "",
    /** user | assistant */
    val role: String = "",
    val text: String = "",
    @SerialName("text_zh") val textZh: String? = null,
    @SerialName("created_at") val createdAt: String = "",
    val correction: ChatCorrectionDto? = null,
    val pron: ChatPronDto? = null,
    @SerialName("audio_url") val audioUrl: String? = null,
    /** ok | unsafe_filtered | off_topic */
    val flag: String = "",
)

@Serializable
data class ChatMessageListDto(
    @SerialName("session_id") val sessionId: String = "",
    val messages: List<ChatMessageDto> = emptyList(),
)

/** `POST /api/chat/sessions` 201（内置场景分支含 age/turn_count/messages；自定义分支更瘦）。 */
@Serializable
data class ChatSessionDto(
    @SerialName("session_id") val sessionId: String = "",
    val scenario: ChatScenarioDto? = null,
    val age: Int = 0,
    @SerialName("turn_count") val turnCount: Int = 0,
    val messages: List<ChatMessageDto> = emptyList(),
    @SerialName("is_custom") val isCustom: Boolean = false,
)

/** `POST /api/chat/sessions/:id/turn` 200（不含 TTS 音频）。 */
@Serializable
data class ChatTurnDto(
    @SerialName("session_id") val sessionId: String = "",
    val provider: String = "",
    /** true = 本条是固定话术，不是大模型 */
    @SerialName("degraded_llm") val degradedLlm: Boolean = false,
    /** true = 调用失败降级到本地话术 */
    val degraded: Boolean = false,
    val capabilities: ChatCapabilitiesDto? = null,
    val reply: String = "",
    @SerialName("reply_zh") val replyZh: String = "",
    val correction: ChatCorrectionDto? = null,
    @SerialName("suggested_replies") val suggestedReplies: List<String> = emptyList(),
    @SerialName("target_words") val targetWords: List<String> = emptyList(),
    /** ok | unsafe_filtered | off_topic */
    val flag: String = "",
    /** true = 本场景自然收尾 */
    val done: Boolean = false,
    @SerialName("turn_index") val turnIndex: Int = 0,
    @SerialName("message_id") val messageId: String = "",
    @SerialName("user_message_id") val userMessageId: String = "",
    @SerialName("user_audio_url") val userAudioUrl: String? = null,
)

@Serializable
data class ChatCapabilitiesDto(
    @SerialName("phoneme_level") val phonemeLevel: Boolean = false,
    val prosody: Boolean = false,
    @SerialName("intonation_curve") val intonationCurve: Boolean = false,
    val ssml: Boolean = false,
    val ocr: Boolean = false,
    val image: Boolean = false,
    @SerialName("audio_concat") val audioConcat: Boolean = false,
    @SerialName("chat_done_turn_index") val chatDoneTurnIndex: Int = 0,
    val features: List<String> = emptyList(),
)

/** `POST /:id/end` 200（幂等）。 */
@Serializable
data class ChatEndDto(
    val ok: Boolean = false,
    @SerialName("session_id") val sessionId: String = "",
    val ended: Boolean = false,
)

/** `GET /:id/audio/status`（只读，绝不触发构建）。 */
@Serializable
data class ChatAudioStatusDto(
    /** ready | building | failed */
    val status: String = "",
    @SerialName("turn_count") val turnCount: Int = 0,
    @SerialName("auto_retry") val autoRetry: Boolean = false,
    @SerialName("duration_ms") val durationMs: Int = 0,
    val error: String? = null,
    @SerialName("error_code") val errorCode: String? = null,
    val attempts: Int = 0,
)

/** `GET /:id/audio` 202（构建中）响应体。 */
@Serializable
data class ChatAudioBuildingDto(
    val status: String = "",
    @SerialName("turn_count") val turnCount: Int = 0,
    @SerialName("retry_after_ms") val retryAfterMs: Int = 0,
    val forced: Boolean = false,
)

/**
 * `GET /api/chat/sessions` 列表项（§2.9）。
 * 命名说明：契约 §3.2 写作 `ChatSessionSummaryDto`，hos 原名 `ChatSessionListItemDto`，
 * 这里以契约名为主并提供 [ChatSessionListItemDto] 别名，两种写法都能用。
 */
@Serializable
data class ChatSessionSummaryDto(
    val id: String = "",
    @SerialName("scenario_id") val scenarioId: String = "",
    @SerialName("scenario_title") val scenarioTitle: String = "",
    @SerialName("scenario_title_zh") val scenarioTitleZh: String = "",
    @SerialName("started_at") val startedAt: String = "",
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("turn_count") val turnCount: Int = 0,
    @SerialName("last_message") val lastMessage: String? = null,
)

/** hos 原名别名（`ChatDtos.ets` 的 `ChatSessionListItemDto`）。 */
typealias ChatSessionListItemDto = ChatSessionSummaryDto

@Serializable
data class ChatSessionListDto(
    val sessions: List<ChatSessionSummaryDto> = emptyList(),
)

/** `GET /api/chat/sessions/:id`（详情，**无 pron**；pron 走 /messages）。 */
@Serializable
data class ChatSessionDetailDto(
    @SerialName("session_id") val sessionId: String = "",
    @SerialName("scenario_id") val scenarioId: String = "",
    @SerialName("scenario_title") val scenarioTitle: String = "",
    @SerialName("scenario_title_zh") val scenarioTitleZh: String = "",
    @SerialName("turn_count") val turnCount: Int = 0,
    @SerialName("started_at") val startedAt: String = "",
    @SerialName("ended_at") val endedAt: String? = null,
    val messages: List<ChatMessageDto> = emptyList(),
)

/**
 * `POST /api/asr` 响应：`{text}`（部分版本叫 `transcript`）。
 * 两个字段都可空 —— 用「哪个存在用哪个」还原 hos 的 `!== undefined` 判断。
 */
@Serializable
data class ChatAsrDto(
    val text: String? = null,
    val transcript: String? = null,
)

// ---------------------------------------------------------------------------
// 请求体
// ---------------------------------------------------------------------------

/**
 * 创建 / 编辑对话场景的请求体。
 * 空字段一律置 null（不序列化）：PATCH 语义「未传取原值」，与 hos 的 `scenarioBody` 一致。
 */
@Serializable
data class ChatScenarioBodyDto(
    val title: String? = null,
    @SerialName("title_zh") val titleZh: String? = null,
    @SerialName("setting_zh") val settingZh: String? = null,
    @SerialName("role_prompt") val rolePrompt: String? = null,
    @SerialName("opening_line") val openingLine: String? = null,
    val level: String? = null,
    val audience: String? = null,
)

/** `POST /api/chat/sessions` 请求体。 */
@Serializable
data class ChatSessionCreateBodyDto(
    @SerialName("scenario_id") val scenarioId: String = "",
)

/** `POST /api/chat/sessions/:id/turn` 的纯文本请求体（带录音时走 multipart）。 */
@Serializable
data class ChatTurnBodyDto(
    val text: String = "",
)

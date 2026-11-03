package top.dreamsearch.englishcoach.core.net.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import top.dreamsearch.englishcoach.core.model.UsageDto

/**
 * 服务端通用契约 DTO（跟读评测 / 健康检查 / 材料 / 异步评分）。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/net/Dtos.ets`（逐字段对照）。
 * 数据来源：`.specs/practice-flow.md`（web 源码级契约）。
 *
 * 约定（android/CONTRACT.md §3.1）：
 * - 所有字段带默认值 —— 服务端缺字段不炸，`coerceInputValues` 兜底 null；
 * - 服务端 snake_case 字段用 `@SerialName` 映射成 Kotlin camelCase 属性；
 * - `Array<[number, number|null]>`（F0 语调曲线）用 [F0Point] = `List<Double?>`；
 * - `UserDto` / `UsageDto` / `MeResponseDto` / `TokenResponseDto` / `LoginBodyDto`
 *   已在 `core/model/UserModels.kt` 定义，这里**不重复定义**，直接复用。
 */

/** 语调曲线上的一个点：`[time_ms, f0_hz|null]`（hos `F0Point`）。 */
typealias F0Point = List<Double?>

// ---------------------------------------------------------------------------
// 语料（GET /sentences）
// ---------------------------------------------------------------------------

/** 一句跟读语料。儿童账号服务端会剥离 `focus_phonemes`（返回空数组）。 */
@Serializable
data class SentenceDto(
    val id: String = "",
    val text: String = "",
    @SerialName("translation_zh") val translationZh: String = "",
    val level: String = "",
    /** 儿童账号服务端返回空数组 */
    @SerialName("focus_phonemes") val focusPhonemes: List<String> = emptyList(),
    val tags: List<String> = emptyList(),
    val source: String = "",
    @SerialName("owner_user_id") val ownerUserId: String? = null,
    val mine: Boolean = false,
    @SerialName("sort_order") val sortOrder: Int = 0,
)

/** `GET /api/sentences?level=` 的包装形状。 */
@Serializable
data class SentenceListDto(
    val level: String? = null,
    val count: Int = 0,
    val sentences: List<SentenceDto> = emptyList(),
    @SerialName("user_level") val userLevel: String = "",
    @SerialName("official_count") val officialCount: Int = 0,
    @SerialName("custom_count") val customCount: Int = 0,
    @SerialName("mine_count") val mineCount: Int = 0,
)

// ---------------------------------------------------------------------------
// 评测结果（POST /attempts、GET /attempts、GET /attempts/status）
// ---------------------------------------------------------------------------

/** 综合分：0–100，不可得为 null（**不是** 0）。 */
@Serializable
data class ScoresDto(
    val pron: Double? = null,
    val accuracy: Double? = null,
    val fluency: Double? = null,
    val completeness: Double? = null,
    val prosody: Double? = null,
)

/** n-best 音素候选。 */
@Serializable
data class NBestDto(
    val phoneme: String = "",
    val score: Double? = null,
)

/** 音素级明细（仅同步 `/attempts` 有；`/attempts/status` 的 words 不带）。 */
@Serializable
data class PhonemeScoreDto(
    val phoneme: String = "",
    val score: Double? = null,
    @SerialName("start_ms") val startMs: Int? = null,
    @SerialName("end_ms") val endMs: Int? = null,
    val nbest: List<NBestDto> = emptyList(),
)

@Serializable
data class WordScoreDto(
    val word: String = "",
    val score: Double? = null,
    @SerialName("error_type") val errorType: String? = null,
    @SerialName("start_ms") val startMs: Int? = null,
    @SerialName("end_ms") val endMs: Int? = null,
    /** 音素级明细（只有同步评测有） */
    val phonemes: List<PhonemeScoreDto> = emptyList(),
)

@Serializable
data class IssueDto(
    val type: String = "",
    val severity: String = "",
    val word: String = "",
    val phoneme: String? = null,
    val expected: String? = null,
    val actual: String? = null,
    val score: Double? = null,
    @SerialName("hint_key") val hintKey: String? = null,
    @SerialName("start_ms") val startMs: Int? = null,
    @SerialName("end_ms") val endMs: Int? = null,
)

/** 语调最差区间。 */
@Serializable
data class IntonationRegionDto(
    @SerialName("start_ms") val startMs: Int? = null,
    @SerialName("end_ms") val endMs: Int? = null,
    val text: String = "",
    val issue: String = "",
    @SerialName("user_slope") val userSlope: Double? = null,
    @SerialName("ref_slope") val refSlope: Double? = null,
)

/** 语调曲线：user/reference 同时间轴、同长度（已 DTW 对齐）。 */
@Serializable
data class IntonationDto(
    val available: Boolean = false,
    @SerialName("dtw_distance") val dtwDistance: Double? = null,
    @SerialName("user_f0") val userF0: List<F0Point> = emptyList(),
    @SerialName("reference_f0") val referenceF0: List<F0Point> = emptyList(),
    @SerialName("worst_regions") val worstRegions: List<IntonationRegionDto> = emptyList(),
    @SerialName("reference_audio_url") val referenceAudioUrl: String? = null,
)

/** 发音评测明细（provider 返回形状）。 */
@Serializable
data class PronounceResultDto(
    val provider: String = "",
    val granularity: String = "",
    val mode: String = "",
    @SerialName("reference_text") val referenceText: String = "",
    @SerialName("recognized_text") val recognizedText: String = "",
    @SerialName("duration_ms") val durationMs: Int = 0,
    val scores: ScoresDto? = null,
    val words: List<WordScoreDto> = emptyList(),
    val issues: List<IssueDto> = emptyList(),
    val intonation: IntonationDto? = null,
    val warnings: List<String> = emptyList(),
)

/** 中文反馈里的一条建议。 */
@Serializable
data class FeedbackPointDto(
    val title: String = "",
    val why: String = "",
    val how: String = "",
    @SerialName("practice_words") val practiceWords: List<String> = emptyList(),
    @SerialName("demo_text") val demoText: String? = null,
    val severity: String = "",
)

@Serializable
data class FeedbackDto(
    val provider: String = "",
    val summary: String = "",
    val praise: String = "",
    val points: List<FeedbackPointDto> = emptyList(),
    val closing: String = "",
)

/** 盲测进度。 */
@Serializable
data class BlindProgressDto(
    val done: Int = 0,
    val total: Int = 0,
)

/**
 * `POST /api/attempts` 响应（web 自己的形状）。
 * 盲测时服务端**只**返回 `attempt_id/blind/progress`，不含分数。
 */
@Serializable
data class AttemptResponseDto(
    @SerialName("attempt_id") val attemptId: String = "",
    val blind: Boolean = false,
    val degraded: Boolean = false,
    val retryable: Boolean = false,
    val message: String = "",
    val result: PronounceResultDto? = null,
    val feedback: FeedbackDto? = null,
    val usage: UsageDto? = null,
    val progress: BlindProgressDto? = null,
)

/** `GET /api/attempts?limit=N` 列表中的一条（历史 / 进步曲线数据源）。 */
@Serializable
data class AttemptItemDto(
    val id: String = "",
    @SerialName("sentence_id") val sentenceId: String? = null,
    val mode: String = "",
    @SerialName("reference_text") val referenceText: String = "",
    val blind: Boolean = false,
    @SerialName("blind_test_id") val blindTestId: String? = null,
    val pending: Boolean = false,
    @SerialName("recognized_text") val recognizedText: String = "",
    val scores: ScoresDto? = null,
    val issues: List<IssueDto> = emptyList(),
    val intonation: IntonationDto? = null,
    val feedback: FeedbackDto? = null,
    @SerialName("audio_url") val audioUrl: String? = null,
    @SerialName("ref_audio_url") val refAudioUrl: String? = null,
    @SerialName("duration_ms") val durationMs: Int = 0,
    val warnings: List<String> = emptyList(),
    @SerialName("created_at") val createdAt: String = "",
)

@Serializable
data class AttemptListDto(
    val attempts: List<AttemptItemDto> = emptyList(),
)

/**
 * `POST /api/attempts/async` → 201。
 * 普通提交返回 `id/status`，盲测提交返回 `attempt_id/blind/progress`，两种键名都收。
 */
@Serializable
data class AsyncSubmitDto(
    val id: String = "",
    @SerialName("attempt_id") val attemptId: String = "",
    val blind: Boolean = false,
    val status: String = "",
    val progress: BlindProgressDto? = null,
) {
    /** 普通 / 盲测两种键名的统一取值（都缺失时为空串）。 */
    val resolvedId: String get() = attemptId.ifEmpty { id }
}

/** `/attempts/status` 的 result：words 只有 word/score/start_ms/end_ms/error_type，没有 phonemes。 */
@Serializable
data class AsyncResultDto(
    val scores: ScoresDto? = null,
    val words: List<WordScoreDto> = emptyList(),
    val issues: List<IssueDto> = emptyList(),
    val intonation: IntonationDto? = null,
    val feedback: FeedbackDto? = null,
    @SerialName("recognized_text") val recognizedText: String = "",
)

/** `GET /api/attempts/status?ids=a,b,c` 的单项。 */
@Serializable
data class AsyncStatusItemDto(
    val id: String = "",
    /** pending | scoring | done | failed */
    val status: String = "",
    val error: String? = null,
    @SerialName("scored_at") val scoredAt: String? = null,
    val result: AsyncResultDto? = null,
)

@Serializable
data class AsyncStatusDto(
    val items: List<AsyncStatusItemDto> = emptyList(),
)

// ---------------------------------------------------------------------------
// 健康检查（GET /health，无需登录）
// ---------------------------------------------------------------------------

@Serializable
data class HealthCapabilitiesDto(
    @SerialName("phoneme_level") val phonemeLevel: Boolean = false,
    val prosody: Boolean = false,
    @SerialName("intonation_curve") val intonationCurve: Boolean = false,
    @SerialName("nbest_phonemes") val nbestPhonemes: Boolean = false,
    val ssml: Boolean = false,
    val ocr: Boolean = false,
    /** 图像能力（插画/形象）；false 时客户端隐藏「给我画一张」 */
    val image: Boolean = false,
    @SerialName("image_provider") val imageProvider: String? = null,
    @SerialName("image_avatar") val imageAvatar: Boolean = false,
    @SerialName("avatar_presets") val avatarPresets: Boolean = false,
    @SerialName("audio_concat") val audioConcat: Boolean = false,
    @SerialName("word_ipa") val wordIpa: Boolean = false,
    @SerialName("asr_providers") val asrProviders: List<String> = emptyList(),
    @SerialName("chat_done_turn_index") val chatDoneTurnIndex: Int = 0,
)

@Serializable
data class HealthVoiceDto(
    val reachable: Boolean = false,
    val mode: String = "",
    val capabilities: HealthCapabilitiesDto? = null,
    val hint: String? = null,
)

@Serializable
data class HealthDbDto(
    val ok: Boolean = false,
    val error: String? = null,
)

/** `GET /api/health`（早期简化版；全字段版见 `StatsDtos.kt` 的 `HealthFullDto`）。 */
@Serializable
data class HealthDto(
    val status: String = "",
    val service: String = "",
    val version: String = "",
    val time: String = "",
    val db: HealthDbDto? = null,
    val voice: HealthVoiceDto? = null,
)

// ---------------------------------------------------------------------------
// 材料 / 书页（GET/POST/PATCH /materials）
// ---------------------------------------------------------------------------

/** 材料（故事 / 书页）列表项 summary。 */
@Serializable
data class MaterialDto(
    val id: String = "",
    val title: String = "",
    @SerialName("created_by_name") val createdByName: String = "",
    @SerialName("created_by_avatar_url") val createdByAvatarUrl: String? = null,
    @SerialName("sentence_count") val sentenceCount: Int = 0,
    @SerialName("has_image") val hasImage: Boolean = false,
    val source: String = "",
    val kind: String = "",
    val level: String? = null,
    @SerialName("has_source_zh") val hasSourceZh: Boolean = false,
    @SerialName("created_by") val createdBy: String = "",
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
)

@Serializable
data class MaterialListDto(
    val count: Int = 0,
    val items: List<MaterialDto> = emptyList(),
)

/** `GET /materials/:id` 详情（多 text / source_zh / image_* 字段）。 */
@Serializable
data class MaterialDetailDto(
    val id: String = "",
    val title: String = "",
    val text: String = "",
    @SerialName("source_zh") val sourceZh: String? = null,
    val kind: String = "",
    val level: String? = null,
    @SerialName("image_b64") val imageB64: String? = null,
    @SerialName("created_by_name") val createdByName: String = "",
    @SerialName("created_at") val createdAt: String = "",
)

/** `POST /materials` 请求体（连读书页 / 故事共用；kind=page|story）。 */
@Serializable
data class MaterialCreateBodyDto(
    val title: String = "",
    val text: String = "",
    val kind: String = "page",
    @SerialName("source_zh") val sourceZh: String? = null,
    val level: String? = null,
    val source: String = "text",
)

/** `PATCH /materials/:id` 请求体（只改标题 / 正文；null 字段不序列化）。 */
@Serializable
data class MaterialPatchBodyDto(
    val title: String? = null,
    val text: String? = null,
)

// ---------------------------------------------------------------------------
// OCR（POST /ocr）
// ---------------------------------------------------------------------------

@Serializable
data class OcrResultDto(
    val provider: String = "",
    val text: String = "",
    val lines: List<String> = emptyList(),
    val width: Int = 0,
    val height: Int = 0,
    @SerialName("elapsed_ms") val elapsedMs: Int = 0,
    val warnings: List<String> = emptyList(),
    @SerialName("image_jpeg_b64") val imageJpegB64: String? = null,
)

// ---------------------------------------------------------------------------
// TTS 音色（/tts/voices 线上 404，仅保留 DTO；音色用 core/audio/Voices.kt 内置常量）
// ---------------------------------------------------------------------------

@Serializable
data class TtsVoiceDto(
    val id: String = "",
    @SerialName("label_zh") val labelZh: String = "",
    val lang: String = "",
    val sample: String = "",
)

@Serializable
data class TtsVoiceListDto(
    val count: Int = 0,
    val voices: List<TtsVoiceDto> = emptyList(),
)

// ---------------------------------------------------------------------------
// 请求体（与 hos 内联拼接的 JSON 对应）
// ---------------------------------------------------------------------------

/** `POST /api/tts` 请求体（`voice` 为 null 时不序列化，走 provider 默认音色）。 */
@Serializable
data class TtsBodyDto(
    val text: String = "",
    val rate: String = "normal",
    val format: String = "wav",
    val voice: String? = null,
)

/** `POST /api/warmup` 请求体（fire-and-forget 预热，最多 12 条）。 */
@Serializable
data class WarmupBodyDto(
    val texts: List<String> = emptyList(),
    val rate: String = "normal",
)

/** `POST /api/auth/refresh` 请求体。 */
@Serializable
data class RefreshBodyDto(
    @SerialName("refresh_token") val refreshToken: String = "",
)

/** `POST /api/auth/revoke` 请求体。 */
@Serializable
data class RevokeBodyDto(
    @SerialName("refresh_token") val refreshToken: String = "",
)

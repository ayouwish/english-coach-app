package top.dreamsearch.englishcoach.core.net.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 故事模式 DTO（材料 / 转录 / 改写 / 复述 / 插画 / 整段朗读回放）。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/net/StoryDtos.ets`。
 * 数据来源：`.specs/chat-story.md` §3（web 源码级契约，2026-11-03）。
 *
 * 线上降级（2026-11-03 实测，必须照抄）：
 * - `POST /api/story/recordings` 是 404 → 录音转写一律走 `POST /api/asr?language=zh-CN`；
 * - 复述 = 两步：先 `POST /api/asr?language=en-US` 拿 transcript，再 `POST /api/story/retell`。
 *
 * 说明：hos 文件尾部的展示模型（StoryCardItem / StoryGroup / StoryRetellRecord 等）
 * 属于页面 VM 自己的形状，不是网络契约，这里不移植（数据层只承载服务端 DTO）。
 */

// ---------------------------------------------------------------------------
// /api/materials（kind=story）
// ---------------------------------------------------------------------------

/** 故事/书页（材料）：列表项是 summary，详情多 text / source_zh / image_* 字段。 */
@Serializable
data class StoryMaterialDto(
    val id: String = "",
    val title: String = "",
    /** 英文正文（详情才有；句子以换行分隔） */
    val text: String = "",
    /** 中文原文（详情才有） */
    @SerialName("source_zh") val sourceZh: String? = null,
    val kind: String = "",
    val level: String? = null,
    @SerialName("sentence_count") val sentenceCount: Int = 0,
    val source: String = "",
    @SerialName("has_image") val hasImage: Boolean = false,
    @SerialName("has_source_zh") val hasSourceZh: Boolean = false,
    /** 详情：`/api/materials/:id/image`（需要 Bearer，不能直接给 Image 用） */
    @SerialName("image_url") val imageUrl: String? = null,
    /** 详情：上次生成插画用的提示词 */
    @SerialName("image_prompt") val imagePrompt: String? = null,
    @SerialName("image_character_used") val imageCharacterUsed: Boolean = false,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_by_name") val createdByName: String = "",
    @SerialName("created_by_avatar_url") val createdByAvatarUrl: String? = null,
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
)

@Serializable
data class StoryMaterialListDto(
    val count: Int = 0,
    val items: List<StoryMaterialDto> = emptyList(),
)

/** `POST /api/materials` 请求体（kind=story）。 */
@Serializable
data class StoryMaterialCreateDto(
    val title: String = "",
    val text: String = "",
    val kind: String = "story",
    @SerialName("source_zh") val sourceZh: String? = null,
    val level: String? = null,
    val source: String = "text",
)

/** `POST /api/materials` 响应（201，summary + limits）。 */
@Serializable
data class StoryMaterialCreatedDto(
    val id: String = "",
    val title: String = "",
    @SerialName("created_by_name") val createdByName: String = "",
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

// ---------------------------------------------------------------------------
// /api/asr（降级路径：中文 / 英文转录）
// ---------------------------------------------------------------------------

@Serializable
data class StoryAsrDto(
    val text: String = "",
    val language: String = "",
    val provider: String = "",
    @SerialName("duration_ms") val durationMs: Int = 0,
    val error: String? = null,
)

// ---------------------------------------------------------------------------
// /api/story/rewrite
// ---------------------------------------------------------------------------

@Serializable
data class StoryReadabilityDto(
    @SerialName("sentence_count") val sentenceCount: Int = 0,
    @SerialName("avg_words") val avgWords: Double = 0.0,
    @SerialName("max_words") val maxWords: Int = 0,
    @SerialName("unknown_words") val unknownWords: List<String> = emptyList(),
    val ok: Boolean = false,
)

/** `POST /api/story/rewrite` 请求体（中文 → 分级英文）。 */
@Serializable
data class StoryRewriteBodyDto(
    @SerialName("text_zh") val textZh: String = "",
    val level: String = "A2",
    @SerialName("max_sentences") val maxSentences: Int = 0,
    @SerialName("weak_phonemes") val weakPhonemes: List<String>? = null,
    @SerialName("use_weak_phonemes") val useWeakPhonemes: Boolean = false,
    /** auto | past | present（叙事默认一般过去时） */
    val tense: String = "auto",
)

@Serializable
data class StoryRewriteDto(
    @SerialName("title_en") val titleEn: String = "",
    val sentences: List<String> = emptyList(),
    @SerialName("text_en") val textEn: String = "",
    val level: String = "",
    val readability: StoryReadabilityDto? = null,
    val warnings: List<String> = emptyList(),
    val provider: String = "",
    @SerialName("weak_phonemes_used") val weakPhonemesUsed: List<String> = emptyList(),
)

// ---------------------------------------------------------------------------
// /api/story/retell
// ---------------------------------------------------------------------------

/** `POST /api/story/retell` 请求体。 */
@Serializable
data class StoryRetellBodyDto(
    @SerialName("material_id") val materialId: String? = null,
    @SerialName("story_sentences") val storySentences: List<String> = emptyList(),
    val transcript: String = "",
    /** A1|A2|B1|B2|C1；非法值服务端静默回落 A2 */
    val level: String = "A2",
)

@Serializable
data class StoryRetellDto(
    val id: String = "",
    /** 0–1 的覆盖率（儿童端不显示百分比）；无值为 null */
    val coverage: Double? = null,
    @SerialName("covered_points") val coveredPoints: List<String> = emptyList(),
    @SerialName("missing_points") val missingPoints: List<String> = emptyList(),
    @SerialName("feedback_zh") val feedbackZh: String = "",
    @SerialName("feedback_en") val feedbackEn: String = "",
    val warnings: List<String> = emptyList(),
    val provider: String = "",
)

// ---------------------------------------------------------------------------
// POST /api/story/:id/illustrate
// ---------------------------------------------------------------------------

@Serializable
data class StoryIllustrateBodyDto(
    val force: Boolean = false,
    val style: String = "watercolor",
)

@Serializable
data class StoryIllustrationDto(
    val ok: Boolean = false,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("image_path") val imagePath: String = "",
    val mime: String = "",
    val provider: String = "",
    val model: String = "",
    val size: String = "",
    @SerialName("elapsed_ms") val elapsedMs: Int = 0,
    val warnings: List<String> = emptyList(),
    @SerialName("prompt_used") val promptUsed: String = "",
    @SerialName("character_used") val characterUsed: Boolean = false,
    @SerialName("character_desc_used") val characterDescUsed: String = "",
    @SerialName("character_style_used") val characterStyleUsed: String = "",
    val force: Boolean = false,
)

// ---------------------------------------------------------------------------
// GET /api/story/:id/audio/status（整段朗读回放）
// ---------------------------------------------------------------------------

/**
 * 服务端状态：ready | building | failed。
 * 客户端补充两个：no_audio（404，没有任何朗读录音）、checking（本地占位）。
 */
@Serializable
data class StoryAudioStatusDto(
    val status: String = "",
    @SerialName("attempt_count") val attemptCount: Int = 0,
    val single: Boolean = false,
    @SerialName("duration_ms") val durationMs: Int = 0,
    val error: String = "",
    @SerialName("error_code") val errorCode: String = "",
    @SerialName("retry_after_ms") val retryAfterMs: Int = 0,
)

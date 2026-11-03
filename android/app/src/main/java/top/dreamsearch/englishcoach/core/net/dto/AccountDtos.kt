package top.dreamsearch.englishcoach.core.net.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import top.dreamsearch.englishcoach.core.model.UserDto
import top.dreamsearch.englishcoach.core.model.UsageDto

/**
 * 账号 / 设置 / 家庭成员 / 家长面板 / 建议箱 / 虚拟形象 DTO。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/net/AccountDtos.ets`。
 * 数据来源：`.specs/account-misc.md` §3–§9、`.specs/chat-story.md` §4（web 源码逐行读出）。
 *
 * 关键字段名差异（易错）：
 * - `GET /settings` 返回的 `user` / `prefs` 是 **camelCase**（`UserDto` 直接复用 core/model）；
 * - `PATCH /settings` 的请求体是 **snake_case**（`display_name`、`daily_limit_minutes`…）；
 * - 家庭成员列表提交/返回都是 snake_case，与 `/auth/me` 的 camelCase user 是两套 DTO。
 * - 儿童 PATCH /settings **绝不能**带 `daily_limit_minutes` / `allow_free_chat`（服务端 403），
 *   所以这两个字段在请求体里是可空类型，由 VM 决定是否传。
 */

// ---------------------------------------------------------------------------
// /api/settings
// ---------------------------------------------------------------------------

/** prefs 是 camelCase（PATCH 入参才是 snake_case），属性名与服务端一致，不需要 @SerialName。 */
@Serializable
data class PrefsDto(
    /** gentle | standard | none */
    val correctionLevel: String = "",
    /** 9 个音色 id 或 null（provider 默认） */
    val ttsVoice: String? = null,
    /** slow | normal */
    val ttsRate: String = "",
    /** 点单词显示音标（null = 默认开） */
    val showWordIpa: Boolean? = null,
)

/** `GET /api/settings` —— user（全量，复用 core/model/[UserDto]）+ prefs + usage。 */
@Serializable
data class SettingsResponseDto(
    val user: UserDto? = null,
    val prefs: PrefsDto? = null,
    val usage: UsageDto? = null,
)

/**
 * `PATCH /api/settings` 请求体（**全 snake_case**；null 字段不序列化）。
 * 儿童绝不能带 `daily_limit_minutes` / `allow_free_chat`。
 */
@Serializable
data class SettingsPatchBodyDto(
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("daily_limit_minutes") val dailyLimitMinutes: Int? = null,
    @SerialName("allow_free_chat") val allowFreeChat: Boolean? = null,
    @SerialName("auto_illustrate") val autoIllustrate: Boolean? = null,
    val gender: String? = null,
    @SerialName("story_sentences") val storySentences: Int? = null,
    @SerialName("correction_level") val correctionLevel: String? = null,
    @SerialName("tts_rate") val ttsRate: String? = null,
    @SerialName("tts_voice") val ttsVoice: String? = null,
    /** 点单词显示音标（null = 默认开） */
    @SerialName("show_word_ipa") val showWordIpa: Boolean? = null,
)

// ---------------------------------------------------------------------------
// /api/family/members
// ---------------------------------------------------------------------------

@Serializable
data class FamilyMemberStatsDto(
    val attempts: Int = 0,
    @SerialName("last_active_at") val lastActiveAt: String? = null,
)

/** 家庭成员（snake_case；与 `/auth/me` 的 camelCase user 是两套 DTO）。 */
@Serializable
data class FamilyMemberDto(
    val id: String = "",
    val email: String = "",
    @SerialName("display_name") val displayName: String = "",
    val role: String = "",
    @SerialName("age_band") val ageBand: String = "",
    @SerialName("cefr_level") val cefrLevel: String = "",
    val avatar: String? = null,
    @SerialName("birth_year") val birthYear: Int? = null,
    @SerialName("daily_limit_minutes") val dailyLimitMinutes: Int = 0,
    @SerialName("allow_free_chat") val allowFreeChat: Boolean = false,
    @SerialName("created_at") val createdAt: String = "",
    val stats: FamilyMemberStatsDto? = null,
)

@Serializable
data class FamilyMemberListDto(
    val items: List<FamilyMemberDto> = emptyList(),
    val count: Int = 0,
)

/** `POST /api/family/members` 请求体（login 可只写简称，服务端补 @family.local）。 */
@Serializable
data class FamilyCreateBodyDto(
    @SerialName("display_name") val displayName: String = "",
    val login: String = "",
    val password: String = "",
    /** parent | child */
    val role: String = "child",
    /** A1 | A2 | B1 | B2 | C1 */
    @SerialName("cefr_level") val cefrLevel: String = "A1",
    @SerialName("birth_year") val birthYear: Int? = null,
    val avatar: String? = null,
    @SerialName("daily_limit_minutes") val dailyLimitMinutes: Int? = null,
    @SerialName("allow_free_chat") val allowFreeChat: Boolean? = null,
)

/** `PATCH /family/members/:id` 可写字段；传 role 会 400。 */
@Serializable
data class FamilyPatchBodyDto(
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("cefr_level") val cefrLevel: String? = null,
    @SerialName("daily_limit_minutes") val dailyLimitMinutes: Int? = null,
    @SerialName("allow_free_chat") val allowFreeChat: Boolean? = null,
    val avatar: String? = null,
)

@Serializable
data class FamilyMemberResponseDto(
    val ok: Boolean = false,
    val member: FamilyMemberDto? = null,
)

@Serializable
data class ResetPasswordBodyDto(
    @SerialName("new_password") val newPassword: String = "",
)

// ---------------------------------------------------------------------------
// /api/parent/summary
// ---------------------------------------------------------------------------

@Serializable
data class ParentChildDto(
    val id: String = "",
    @SerialName("display_name") val displayName: String = "",
    @SerialName("remaining_minutes") val remainingMinutes: Int? = null,
    @SerialName("limit_minutes") val limitMinutes: Int? = null,
)

@Serializable
data class ParentFamilyDto(
    val members: Int = 0,
    @SerialName("minutes_today") val minutesToday: Int = 0,
    @SerialName("minutes_7d") val minutes7d: Int = 0,
    @SerialName("sentence_count") val sentenceCount: Int = 0,
    @SerialName("scenario_count") val scenarioCount: Int = 0,
    val children: List<ParentChildDto> = emptyList(),
)

@Serializable
data class ParentTodayDto(
    val minutes: Int = 0,
    @SerialName("blind_minutes") val blindMinutes: Int = 0,
    @SerialName("total_minutes") val totalMinutes: Int = 0,
    @SerialName("attempt_count") val attemptCount: Int = 0,
    @SerialName("chat_turns") val chatTurns: Int = 0,
    /** 仅 role==='child' 有值，家长为 null */
    @SerialName("remaining_minutes") val remainingMinutes: Int? = null,
    val exceeded: Boolean = false,
)

@Serializable
data class ParentWeekDto(
    val minutes: Int = 0,
    val attempts: Int = 0,
    @SerialName("avg_pron") val avgPron: Double? = null,
)

@Serializable
data class ParentTotalsDto(
    val attempts: Int = 0,
    @SerialName("chat_sessions") val chatSessions: Int = 0,
    @SerialName("phoneme_rows") val phonemeRows: Int = 0,
    @SerialName("avg_pron") val avgPron: Double? = null,
)

@Serializable
data class ParentTrendPointDto(
    val date: String = "",
    val attempts: Int = 0,
    @SerialName("avg_pron") val avgPron: Double? = null,
)

/** 盲测成绩块（current / previous / series / trend 共用）。 */
@Serializable
data class ParentBlindScoreDto(
    @SerialName("blind_test_id") val blindTestId: String = "",
    @SerialName("ended_at") val endedAt: String = "",
    @SerialName("avg_pron") val avgPron: Double? = null,
    @SerialName("avg_accuracy") val avgAccuracy: Double? = null,
    @SerialName("avg_fluency") val avgFluency: Double? = null,
    @SerialName("avg_intonation_distance") val avgIntonationDistance: Double? = null,
    @SerialName("item_count") val itemCount: Int = 0,
)

@Serializable
data class ParentBlindDto(
    val weeks: Int = 0,
    val current: ParentBlindScoreDto? = null,
    val previous: ParentBlindScoreDto? = null,
    @SerialName("delta_pron") val deltaPron: Double? = null,
    val series: List<ParentBlindScoreDto> = emptyList(),
    @SerialName("in_progress_id") val inProgressId: String? = null,
)

@Serializable
data class ParentPhonemeDto(
    val phoneme: String = "",
    val count: Int = 0,
    @SerialName("avg_score") val avgScore: Double? = null,
    @SerialName("hard_hits") val hardHits: Int = 0,
    @SerialName("title_zh") val titleZh: String = "",
)

@Serializable
data class ParentWordDto(
    val word: String = "",
    val count: Int = 0,
    @SerialName("avg_score") val avgScore: Double? = null,
    val coarse: Boolean = false,
)

@Serializable
data class ParentMemberDto(
    val id: String = "",
    @SerialName("display_name") val displayName: String = "",
    val avatar: String? = null,
    val role: String = "",
    @SerialName("age_band") val ageBand: String = "",
    @SerialName("cefr_level") val cefrLevel: String = "",
    @SerialName("birth_year") val birthYear: Int? = null,
    @SerialName("daily_limit_minutes") val dailyLimitMinutes: Int = 0,
    val today: ParentTodayDto? = null,
    val week: ParentWeekDto? = null,
    val totals: ParentTotalsDto? = null,
    val trend: List<ParentTrendPointDto> = emptyList(),
    val blind: ParentBlindDto? = null,
    @SerialName("top_phonemes") val topPhonemes: List<ParentPhonemeDto> = emptyList(),
    @SerialName("top_words") val topWords: List<ParentWordDto> = emptyList(),
)

@Serializable
data class ParentSummaryDto(
    @SerialName("generated_at") val generatedAt: String = "",
    val family: ParentFamilyDto? = null,
    val members: List<ParentMemberDto> = emptyList(),
)

// ---------------------------------------------------------------------------
// /api/suggestions
// ---------------------------------------------------------------------------

@Serializable
data class SuggestionViewportDto(
    val w: Int? = null,
    val h: Int? = null,
)

/** 建议附带的上下文（请求体里 null 字段不序列化）。 */
@Serializable
data class SuggestionContextDto(
    val ua: String? = null,
    @SerialName("app_version") val appVersion: String? = null,
    @SerialName("voice_mode") val voiceMode: String? = null,
    val viewport: SuggestionViewportDto? = null,
    @SerialName("story_id") val storyId: String? = null,
    @SerialName("story_title") val storyTitle: String? = null,
    val style: String? = null,
    val prompt: String? = null,
    val kind: String? = null,
)

@Serializable
data class SuggestionDto(
    val id: String = "",
    /** child | parent */
    @SerialName("user_role") val userRole: String = "",
    val page: String = "",
    /** experience | content | feature | bug | other */
    val category: String = "",
    val content: String = "",
    /** open | read | resolved */
    val status: String = "",
    @SerialName("created_at") val createdAt: String = "",
    @SerialName("handled_at") val handledAt: String? = null,
    val context: SuggestionContextDto? = null,
)

@Serializable
data class SuggestionCountsDto(
    val open: Int = 0,
    val read: Int = 0,
    val resolved: Int = 0,
)

@Serializable
data class SuggestionListDto(
    val items: List<SuggestionDto> = emptyList(),
    val counts: SuggestionCountsDto? = null,
    val total: Int = 0,
    @SerialName("generated_at") val generatedAt: String = "",
    @SerialName("max_length") val maxLength: Int = 0,
)

/** `POST /api/suggestions` 请求体（所有人含儿童都能提）。 */
@Serializable
data class SuggestionCreateBodyDto(
    val category: String = "",
    val content: String = "",
    val page: String? = null,
    val context: SuggestionContextDto? = null,
)

@Serializable
data class SuggestionCreateResultDto(
    val ok: Boolean = false,
    val id: String = "",
    @SerialName("max_length") val maxLength: Int = 0,
)

@Serializable
data class SuggestionPatchBodyDto(
    val status: String = "open",
)

// ---------------------------------------------------------------------------
// /api/avatar + /api/avatar/presets
// ---------------------------------------------------------------------------

/** 5 种风格的中文名映射（`/avatar` 的 styles 字段，值是中文名而不是对象）。 */
@Serializable
data class AvatarStyleLabelsDto(
    val watercolor: String = "",
    val cartoon: String = "",
    val pixel: String = "",
    val papercut: String = "",
    val clay: String = "",
)

@Serializable
data class AvatarStyleDto(
    val id: String = "",
    @SerialName("label_zh") val labelZh: String = "",
)

/**
 * 角色图映射：键固定为 5 个风格 id，值是**站内绝对路径**（`/avatars/presets/...`）。
 * 移动端必须拼上 `AppConfig.baseUrl` 才能用 Image 加载（静态图无需鉴权）。
 */
@Serializable
data class AvatarImagesDto(
    val watercolor: String = "",
    val cartoon: String = "",
    val pixel: String = "",
    val papercut: String = "",
    val clay: String = "",
)

@Serializable
data class AvatarPresetCharacterDto(
    val id: String = "",
    @SerialName("label_zh") val labelZh: String = "",
    @SerialName("desc_en") val descEn: String = "",
    /** girl | boy | woman | man | other */
    val gender: String = "",
    /** child | adult */
    val audience: String = "",
    val images: AvatarImagesDto? = null,
)

@Serializable
data class AvatarPresetsDto(
    val count: Int = 0,
    /** true = 服务端用的是占位图，UI 要提示「预览图」 */
    val placeholder: Boolean = false,
    val styles: List<AvatarStyleDto> = emptyList(),
    val characters: List<AvatarPresetCharacterDto> = emptyList(),
)

/** GET/POST/PATCH /avatar 的返回（PATCH 多一个 message）。 */
@Serializable
data class AvatarStateDto(
    val ok: Boolean = false,
    /** 预置图 → 静态路径；自定义图 → /api/avatar/image?...（当前策略下不会出现） */
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("preset_id") val presetId: String? = null,
    val style: String? = null,
    @SerialName("character_desc") val characterDesc: String? = null,
    @SerialName("prompt_used") val promptUsed: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    val styles: AvatarStyleLabelsDto? = null,
    val message: String = "",
)

/** `POST /avatar` 请求体 —— 立即生效，不生成图片。 */
@Serializable
data class AvatarSelectBodyDto(
    @SerialName("preset_id") val presetId: String = "",
    val style: String = "",
)

/** `PATCH /avatar` 请求体 —— 只允许改角色卡。 */
@Serializable
data class AvatarDescBodyDto(
    @SerialName("character_desc") val characterDesc: String = "",
)

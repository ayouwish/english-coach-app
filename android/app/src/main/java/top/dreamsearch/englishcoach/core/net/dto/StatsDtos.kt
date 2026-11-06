package top.dreamsearch.englishcoach.core.net.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 诊断 / 错音本 / 盲测 / 健康检查（全字段）DTO。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/net/StatsDtos.ets`。
 * 数据来源：`.specs/practice-flow.md` §2.14–§2.16、`.specs/account-misc.md` §7（web 源码级契约）。
 *
 * 命名说明：契约 §3.2 写作 `DiagnosisDto` / `ReviewDto` / `BlindTestFinishDto`，
 * hos 原名为 `DiagnosisResponseDto` / `ReviewResponseDto` / `BlindFinishDto`；
 * 这里以 hos 名为主，并提供契约名的 typealias（两种写法都能编译）。
 */

// ---------------------------------------------------------------------------
// GET /api/diagnosis（scope=all | recent | attempt | batch）
// ---------------------------------------------------------------------------

@Serializable
data class DiagnosisCountsDto(
    val weak: Int = 0,
    val watch: Int = 0,
    val ok: Int = 0,
)

@Serializable
data class DiagnosisTrendDto(
    /** improving | flat | declining */
    val direction: String = "",
    val delta: Double = 0.0,
    val points: List<Double> = emptyList(),
)

@Serializable
data class DiagnosisErrorWordDto(
    val word: String = "",
    val score: Double? = null,
)

@Serializable
data class DiagnosisContrastDto(
    /** 儿童为空串 */
    val phoneme: String = "",
    /** 已跨音素全局去重并排序 */
    val pair: List<String> = emptyList(),
    val note: String = "",
)

/** 一个音素的诊断行。status: weak(avg<65) / watch(65–80) / ok(≥80)。 */
@Serializable
data class DiagnosisItemDto(
    /** 儿童为空串（服务端已剥离 IPA，客户端也不显示） */
    val phoneme: String = "",
    @SerialName("child_label") val childLabel: String = "",
    @SerialName("focus_token") val focusToken: String = "",
    val status: String = "",
    val attempts: Int = 0,
    @SerialName("avg_score") val avgScore: Double? = null,
    @SerialName("last_score") val lastScore: Double? = null,
    @SerialName("best_score") val bestScore: Double? = null,
    val trend: DiagnosisTrendDto? = null,
    @SerialName("error_words") val errorWords: List<DiagnosisErrorWordDto> = emptyList(),
    @SerialName("practice_count") val practiceCount: Int = 0,
    @SerialName("tip_zh") val tipZh: String = "",
    @SerialName("tip_child_zh") val tipChildZh: String = "",
    /** 儿童版不展示（服务端已剥离） */
    @SerialName("common_errors") val commonErrors: List<String> = emptyList(),
    val examples: List<String> = emptyList(),
    val contrasts: List<DiagnosisContrastDto> = emptyList(),
)

@Serializable
data class DiagnosisRangeDto(
    val scope: String = "",
    @SerialName("attempt_count") val attemptCount: Int = 0,
    @SerialName("attempt_ids") val attemptIds: List<String> = emptyList(),
)

/** `GET /api/diagnosis` 响应（契约 §3.2 称 `DiagnosisDto`）。 */
@Serializable
data class DiagnosisResponseDto(
    @SerialName("generated_at") val generatedAt: String = "",
    @SerialName("min_samples") val minSamples: Int = 0,
    @SerialName("total_phonemes") val totalPhonemes: Int = 0,
    @SerialName("counted_phonemes") val countedPhonemes: Int = 0,
    val counts: DiagnosisCountsDto? = null,
    @SerialName("summary_zh") val summaryZh: String = "",
    @SerialName("focus_phonemes") val focusPhonemes: List<String> = emptyList(),
    val items: List<DiagnosisItemDto> = emptyList(),
    val scope: String = "",
    val range: DiagnosisRangeDto? = null,
)

/** 契约名别名。 */
typealias DiagnosisDto = DiagnosisResponseDto

// ---------------------------------------------------------------------------
// GET/POST /api/review（错音本 SRS）
// ---------------------------------------------------------------------------

@Serializable
data class ReviewStatsDto(
    @SerialName("total_cards") val totalCards: Int = 0,
    @SerialName("due_cards") val dueCards: Int = 0,
    @SerialName("phoneme_rows") val phonemeRows: Int = 0,
    @SerialName("phoneme_level") val phonemeLevel: Boolean = false,
    @SerialName("voice_reachable") val voiceReachable: Boolean = false,
)

@Serializable
data class ReviewDisplayDto(
    val text: String = "",
)

/** 一张 SRS 卡片。儿童：phoneme=null、ref=""，只显示 label/why_zh/how_zh。 */
@Serializable
data class ReviewCardDto(
    val id: String = "",
    /** phoneme | word | sentence */
    val kind: String = "",
    val ref: String = "",
    @SerialName("due_at") val dueAt: String = "",
    val ease: Double? = null,
    @SerialName("interval_days") val intervalDays: Int = 0,
    val reps: Int = 0,
    val lapses: Int = 0,
    @SerialName("last_grade") val lastGrade: String? = null,
    @SerialName("is_phoneme") val isPhoneme: Boolean = false,
    val phoneme: String? = null,
    @SerialName("hint_key") val hintKey: String? = null,
    val label: String = "",
    @SerialName("why_zh") val whyZh: String = "",
    @SerialName("how_zh") val howZh: String = "",
    @SerialName("practice_words") val practiceWords: List<String> = emptyList(),
    @SerialName("demo_text") val demoText: String = "",
    val display: ReviewDisplayDto? = null,
)

@Serializable
data class ReviewWeakPhonemeTrendDto(
    val t: String = "",
    val s: Double? = null,
)

@Serializable
data class ReviewWeakPhonemeDto(
    val phoneme: String = "",
    @SerialName("hint_key") val hintKey: String? = null,
    val attempts: Int = 0,
    @SerialName("avg_score") val avgScore: Double? = null,
    @SerialName("best_score") val bestScore: Double? = null,
    @SerialName("last_score") val lastScore: Double? = null,
    val trend: List<ReviewWeakPhonemeTrendDto> = emptyList(),
    val label: String = "",
)

@Serializable
data class ReviewWordErrorDto(
    val word: String = "",
    val count: Int = 0,
    @SerialName("avg_score") val avgScore: Double? = null,
    val coarse: Boolean = false,
)

@Serializable
data class ReviewGradeDto(
    /** again | hard | good | easy */
    val grade: String = "",
    @SerialName("label_zh") val labelZh: String = "",
)

/** `GET /api/review?limit=N` 响应（契约 §3.2 称 `ReviewDto`）。 */
@Serializable
data class ReviewResponseDto(
    val now: String = "",
    val stats: ReviewStatsDto? = null,
    @SerialName("due_cards") val dueCards: List<ReviewCardDto> = emptyList(),
    @SerialName("weak_phonemes") val weakPhonemes: List<ReviewWeakPhonemeDto> = emptyList(),
    @SerialName("word_level_errors") val wordLevelErrors: List<ReviewWordErrorDto> = emptyList(),
    val grades: List<ReviewGradeDto> = emptyList(),
)

/** 契约名别名。 */
typealias ReviewDto = ReviewResponseDto

/** `POST /api/review` 请求体（grade ∈ again | hard | good | easy）。 */
@Serializable
data class ReviewGradeBodyDto(
    @SerialName("card_id") val cardId: String = "",
    val grade: String = "good",
)

@Serializable
data class ReviewGradeResultDto(
    @SerialName("card_id") val cardId: String = "",
    val grade: String = "",
    @SerialName("next_due_at") val nextDueAt: String = "",
    @SerialName("interval_days") val intervalDays: Int = 0,
    val ease: Double? = null,
    val reps: Int = 0,
    val lapses: Int = 0,
)

// ---------------------------------------------------------------------------
// /api/blind-tests（盲测）
// ---------------------------------------------------------------------------

@Serializable
data class BlindTestDto(
    val id: String = "",
    @SerialName("user_id") val userId: String = "",
    @SerialName("started_at") val startedAt: String = "",
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("item_count") val itemCount: Int = 0,
    @SerialName("avg_pron") val avgPron: Double? = null,
    @SerialName("avg_accuracy") val avgAccuracy: Double? = null,
    @SerialName("avg_fluency") val avgFluency: Double? = null,
    @SerialName("avg_intonation_distance") val avgIntonationDistance: Double? = null,
    @SerialName("sentence_ids") val sentenceIds: List<String> = emptyList(),
    /** 异步评分进度（tests[] / in_progress 都额外带这两个字段） */
    val scored: Int = 0,
    val pending: Int = 0,
)

@Serializable
data class BlindTestStartDto(
    @SerialName("blind_test_id") val blindTestId: String = "",
    @SerialName("sentence_ids") val sentenceIds: List<String> = emptyList(),
    val total: Int = 0,
    /** true = 复用了进行中的批次（HTTP 200）；false = 新建（201） */
    val resumed: Boolean = false,
    @SerialName("started_at") val startedAt: String = "",
)

@Serializable
data class BlindTrendScoreDto(
    @SerialName("blind_test_id") val blindTestId: String = "",
    @SerialName("ended_at") val endedAt: String = "",
    @SerialName("avg_pron") val avgPron: Double? = null,
    @SerialName("avg_accuracy") val avgAccuracy: Double? = null,
    @SerialName("avg_fluency") val avgFluency: Double? = null,
    @SerialName("avg_intonation_distance") val avgIntonationDistance: Double? = null,
    @SerialName("item_count") val itemCount: Int = 0,
)

@Serializable
data class BlindTrendDto(
    val current: BlindTrendScoreDto? = null,
    val previous: BlindTrendScoreDto? = null,
    @SerialName("delta_pron") val deltaPron: Double? = null,
    @SerialName("delta_accuracy") val deltaAccuracy: Double? = null,
    @SerialName("delta_fluency") val deltaFluency: Double? = null,
    @SerialName("delta_intonation_distance") val deltaIntonationDistance: Double? = null,
    /** 已完成批次数 */
    val weeks: Int = 0,
)

@Serializable
data class BlindTestListDto(
    @SerialName("user_id") val userId: String = "",
    val tests: List<BlindTestDto> = emptyList(),
    @SerialName("in_progress") val inProgress: BlindTestDto? = null,
    @SerialName("pending_total") val pendingTotal: Int = 0,
    val trend: BlindTrendDto? = null,
    /** 按时间正序（画柱状图用） */
    val series: List<BlindTrendScoreDto> = emptyList(),
)

/** `POST /api/blind-tests/:id/finish` 响应（契约 §3.2 称 `BlindTestFinishDto`）。 */
@Serializable
data class BlindFinishDto(
    @SerialName("blind_test_id") val blindTestId: String = "",
    @SerialName("user_id") val userId: String = "",
    @SerialName("started_at") val startedAt: String = "",
    @SerialName("ended_at") val endedAt: String = "",
    @SerialName("item_count") val itemCount: Int = 0,
    val submitted: Int = 0,
    val scored: Int = 0,
    val pending: Int = 0,
    /** 只有全评完才是 null；有值时必须展示黄条 */
    val notice: String? = null,
    @SerialName("avg_pron") val avgPron: Double? = null,
    @SerialName("avg_accuracy") val avgAccuracy: Double? = null,
    @SerialName("avg_fluency") val avgFluency: Double? = null,
    @SerialName("avg_intonation_distance") val avgIntonationDistance: Double? = null,
    val previous: BlindTrendScoreDto? = null,
    @SerialName("delta_pron") val deltaPron: Double? = null,
    @SerialName("delta_accuracy") val deltaAccuracy: Double? = null,
    @SerialName("delta_fluency") val deltaFluency: Double? = null,
    @SerialName("delta_intonation_distance") val deltaIntonationDistance: Double? = null,
)

/** 契约名别名。 */
typealias BlindTestFinishDto = BlindFinishDto

// ---------------------------------------------------------------------------
// GET /api/health（全字段；Dtos.kt 里的 HealthDto 是早期简化版，这里补全）
// ---------------------------------------------------------------------------

@Serializable
data class HealthFeaturesDto(
    @SerialName("chat_unlimited_turns") val chatUnlimitedTurns: Boolean = false,
    @SerialName("chat_audio_replay") val chatAudioReplay: Boolean = false,
    @SerialName("chat_scenarios_audience") val chatScenariosAudience: Boolean = false,
    @SerialName("avatar_presets") val avatarPresets: Boolean = false,
    @SerialName("story_mode") val storyMode: Boolean = false,
    @SerialName("async_scoring") val asyncScoring: Boolean = false,
)

@Serializable
data class HealthCapabilitiesFullDto(
    @SerialName("phoneme_level") val phonemeLevel: Boolean = false,
    val prosody: Boolean = false,
    @SerialName("intonation_curve") val intonationCurve: Boolean = false,
    @SerialName("nbest_phonemes") val nbestPhonemes: Boolean = false,
    val ssml: Boolean = false,
    val gpu: Boolean = false,
    val ocr: Boolean = false,
    @SerialName("ocr_provider") val ocrProvider: String? = null,
    val heic: Boolean = false,
    val image: Boolean = false,
    @SerialName("image_provider") val imageProvider: String? = null,
    /** false = 照片生成形象已按隐私策略关闭（隐藏入口） */
    @SerialName("image_avatar") val imageAvatar: Boolean = false,
    @SerialName("avatar_presets") val avatarPresets: Boolean = false,
    @SerialName("audio_concat") val audioConcat: Boolean = false,
    @SerialName("chat_done_turn_index") val chatDoneTurnIndex: Int = 0,
    /** voice 侧已实现的端点清单（排障用） */
    val features: List<String> = emptyList(),
)

@Serializable
data class HealthVoiceFullDto(
    val reachable: Boolean = false,
    /** hybrid | cloud | local | unreachable */
    val mode: String = "",
    /** 服务端容器内地址，不是客户端可用地址 */
    val url: String = "",
    val capabilities: HealthCapabilitiesFullDto? = null,
    val hint: String? = null,
)

@Serializable
data class HealthFullDto(
    /** ok | degraded（只看 DB；voice 挂了仍是 ok） */
    val status: String = "",
    val service: String = "",
    val version: String = "",
    val time: String = "",
    val db: HealthDbDto? = null,
    val features: HealthFeaturesDto? = null,
    val voice: HealthVoiceFullDto? = null,
)

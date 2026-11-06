package top.dreamsearch.englishcoach.core.net.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 连读模式（/flow）专用 DTO。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/net/FlowDtos.ets`。
 * 数据来源：`.specs/practice-flow.md` §2.14 —— `GET /diagnosis?scope=batch&attempt_ids=`
 * （连读汇总页「这一批的问题」；≤20 个 attempt id）。
 *
 * 与 [Dtos.kt] 的关系：连读还复用了其中的 `/attempts/async`、`/attempts/status`、
 * `/materials`、`/ocr` DTO；这里只补 batch 诊断这一份。
 * 字段名保持服务端原样，可能缺失的字段一律给默认值。
 */

@Serializable
data class FlowDiagnosisCountsDto(
    val weak: Int = 0,
    val watch: Int = 0,
    val ok: Int = 0,
)

@Serializable
data class FlowDiagnosisTrendDto(
    /** improving | flat | declining */
    val direction: String = "",
    val delta: Double = 0.0,
    /** 最近 3 次的分数点 */
    val points: List<Double> = emptyList(),
)

@Serializable
data class FlowDiagnosisErrorWordDto(
    val word: String = "",
    val score: Double? = null,
)

@Serializable
data class FlowDiagnosisContrastDto(
    /** 儿童账号服务端返回空串 */
    val phoneme: String = "",
    /** 已排序的对比音素对，例如 ["θ","s"] */
    val pair: List<String> = emptyList(),
    val note: String = "",
)

/** 一个音素的诊断行（status: weak / watch / ok）。 */
@Serializable
data class FlowDiagnosisItemDto(
    /** 儿童账号为空串（服务端已剥离 IPA） */
    val phoneme: String = "",
    /** 儿童可见的口语化名字；成人也有，可作补充 */
    @SerialName("child_label") val childLabel: String = "",
    @SerialName("focus_token") val focusToken: String = "",
    /** weak | watch | ok */
    val status: String = "",
    val attempts: Int = 0,
    @SerialName("avg_score") val avgScore: Double? = null,
    @SerialName("last_score") val lastScore: Double? = null,
    @SerialName("best_score") val bestScore: Double? = null,
    val trend: FlowDiagnosisTrendDto? = null,
    @SerialName("error_words") val errorWords: List<FlowDiagnosisErrorWordDto> = emptyList(),
    @SerialName("practice_count") val practiceCount: Int = 0,
    @SerialName("tip_zh") val tipZh: String = "",
    @SerialName("tip_child_zh") val tipChildZh: String = "",
    @SerialName("common_errors") val commonErrors: List<String> = emptyList(),
    val examples: List<String> = emptyList(),
    val contrasts: List<FlowDiagnosisContrastDto> = emptyList(),
)

@Serializable
data class FlowDiagnosisRangeDto(
    val scope: String = "",
    /** 本次参与统计的 attempt 数 */
    @SerialName("attempt_count") val attemptCount: Int = 0,
    @SerialName("attempt_ids") val attemptIds: List<String> = emptyList(),
)

/** `GET /diagnosis?scope=batch&attempt_ids=a,b,c`（≤20）的响应。 */
@Serializable
data class FlowDiagnosisDto(
    @SerialName("generated_at") val generatedAt: String = "",
    @SerialName("min_samples") val minSamples: Int = 0,
    @SerialName("total_phonemes") val totalPhonemes: Int = 0,
    @SerialName("counted_phonemes") val countedPhonemes: Int = 0,
    val counts: FlowDiagnosisCountsDto? = null,
    @SerialName("summary_zh") val summaryZh: String = "",
    @SerialName("focus_phonemes") val focusPhonemes: List<String> = emptyList(),
    val items: List<FlowDiagnosisItemDto> = emptyList(),
    val scope: String = "",
    val range: FlowDiagnosisRangeDto? = null,
)

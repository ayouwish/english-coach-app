package top.dreamsearch.englishcoach.ui.page.stats

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.dto.ReviewCardDto
import top.dreamsearch.englishcoach.core.net.dto.ReviewWeakPhonemeDto
import top.dreamsearch.englishcoach.core.net.dto.ReviewWordErrorDto
import top.dreamsearch.englishcoach.core.net.dto.ReviewGradeResultDto
import top.dreamsearch.englishcoach.core.session.SessionState

/**
 * 错音本（SRS 复习）页状态：`GET/POST /api/review`。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/viewmodel/StatsVM.ets` 的 `ReviewVM`
 * 与 `hos/entry/src/main/ets/pages/ReviewPage.ets`。
 *
 * 交互照抄 hos / 规格 §6.2：
 * - 评分成功后**本地移除该卡**并把 due_cards - 1（不重新拉列表）；
 * - 提示「下次复习：N 天后 ✅」/「10 分钟后再来一次 🔁」，以服务端 `interval_days/next_due_at` 为准；
 * - 儿童：卡片只显示服务端已儿童化的 label/why_zh/how_zh，不显示 IPA 与低分数字。
 */
data class ReviewUiState(
    val loading: Boolean = false,
    val loadedOnce: Boolean = false,
    val error: UiError? = null,
    /** 待复习卡片（当前卡 = firstOrNull），按服务端排期顺序 */
    val cards: List<ReviewCardDto> = emptyList(),
    val weakPhonemes: List<ReviewWeakPhonemeDto> = emptyList(),
    val wordErrors: List<ReviewWordErrorDto> = emptyList(),
    val totalCards: Int = 0,
    val dueCards: Int = 0,
    val phonemeRows: Int = 0,
    val phonemeLevel: Boolean = true,
    val voiceReachable: Boolean = true,
    /** 正在提交评分的卡片 id（非空时四个按钮都禁用） */
    val gradingCardId: String = "",
    /** 上一次评分结果文案（成功后显示，下次评分前清空） */
    val gradeNotice: String = "",
    /** 评分失败（页内可见 + 可关掉；不覆盖整页错误） */
    val gradeError: UiError? = null,
) {
    val currentCard: ReviewCardDto? get() = cards.firstOrNull()
    val gradedCount: Int get() = cards.size
}

class ReviewViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(ReviewUiState())
    val state: StateFlow<ReviewUiState> = _state.asStateFlow()

    /** 服务端返回的评分按钮文案（`grades[].label_zh`）；缺失时用内置文案兜底。 */
    private var serverGradeLabels: Map<String, String> = emptyMap()

    init {
        load()
    }

    fun load() {
        if (_state.value.loading) return
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            try {
                val dto = c.stats.review(limit = REVIEW_LIMIT)
                val stats = dto.stats
                serverGradeLabels = dto.grades
                    .mapNotNull { grade -> grade.labelZh.takeIf { it.isNotBlank() }?.let { grade.grade to it } }
                    .toMap()
                _state.update {
                    it.copy(
                        loading = false,
                        loadedOnce = true,
                        error = null,
                        cards = dto.dueCards,
                        weakPhonemes = dto.weakPhonemes,
                        wordErrors = dto.wordLevelErrors,
                        totalCards = stats?.totalCards ?: 0,
                        dueCards = stats?.dueCards ?: dto.dueCards.size,
                        phonemeRows = stats?.phonemeRows ?: 0,
                        phonemeLevel = stats?.phonemeLevel ?: true,
                        voiceReachable = stats?.voiceReachable ?: true,
                    )
                }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(loading = false, error = c.session.toUiError(e))
                }
            }
        }
    }

    fun dismissGradeError() {
        _state.update { it.copy(gradeError = null) }
    }

    /**
     * 提交一次评分。
     *
     * 成功：移除卡片、due_cards-1、写入「下次复习」提示；
     * 失败：保留当前卡，把 [UiError] 展示在卡片上（可关掉），不静默。
     */
    fun grade(cardId: String, grade: String) {
        if (cardId.isEmpty() || _state.value.gradingCardId.isNotEmpty()) return
        _state.update { it.copy(gradingCardId = cardId, gradeError = null, gradeNotice = "") }
        viewModelScope.launch {
            try {
                val result = c.stats.gradeReview(cardId, grade)
                _state.update {
                    val remaining = it.cards.filterNot { card -> card.id == cardId }
                    it.copy(
                        cards = remaining,
                        dueCards = (it.dueCards - 1).coerceAtLeast(0),
                        gradeNotice = nextDueText(result),
                        gradeError = null,
                    )
                }
            } catch (e: Throwable) {
                _state.update { it.copy(gradeError = c.session.toUiError(e)) }
            } finally {
                _state.update { it.copy(gradingCardId = "") }
            }
        }
    }

    // ------------------------------------------------------------------ 展示文案

    /** 卡片标题：成人 `/ipa/ · label`，儿童只用 label（服务端已剥离 phoneme）。 */
    fun cardTitle(card: ReviewCardDto, isChild: Boolean): String {
        if (isChild) return card.label.ifEmpty { "这一张" }
        if (card.phoneme.isNullOrEmpty()) return card.label
        return card.label.ifEmpty { "/${card.phoneme}/" }
    }

    /** 音素徽标：仅成人且 is_phoneme 且有音素符号时显示。 */
    fun badgeText(card: ReviewCardDto, isChild: Boolean): String {
        if (isChild || !card.isPhoneme) return ""
        return card.phoneme?.takeIf { it.isNotEmpty() }?.let { "/$it/" } ?: ""
    }

    /** 卡片元信息（仅成人展示：kind / 复习次数 / 遗忘次数 / ease / 上次评分）。 */
    fun metaText(card: ReviewCardDto): String {
        val kind = when (card.kind) {
            "phoneme" -> "音素"
            "word" -> "单词"
            "sentence" -> "句子"
            else -> card.kind.ifEmpty { "卡片" }
        }
        val last = card.lastGrade ?: "未复习"
        val ease = card.ease?.let { formatEase(it) } ?: "—"
        return "$kind · 已复习 ${card.reps} 次 · 遗忘 ${card.lapses} 次 · 难度 $ease · 上次：$last"
    }

    /** 四个评分按钮的文案（成人优先服务端 `grades[].label_zh`；儿童用任务定的口语版）。 */
    fun gradeLabel(grade: String, isChild: Boolean): String {
        if (isChild) {
            return when (grade) {
                "again" -> "再练"
                "hard" -> "有点难"
                "good" -> "会了"
                else -> "太简单"
            }
        }
        serverGradeLabels[grade]?.let { if (it.isNotBlank()) return it }
        return when (grade) {
            "again" -> "再来一次"
            "hard" -> "有点难"
            "good" -> "记住了"
            else -> "太简单"
        }
    }

    fun weakPhonemeLabel(item: ReviewWeakPhonemeDto, isChild: Boolean): String {
        if (item.label.isNotEmpty()) return item.label
        if (isChild) return "这个音"
        return item.phoneme.takeIf { it.isNotEmpty() }?.let { "/$it/" } ?: "—"
    }

    /** 掌握度条比例（0..1；null 时给 2% 的可见底线，与 hos 一致，不把 null 当 0 分）。 */
    fun weakBarFraction(item: ReviewWeakPhonemeDto): Float {
        val score = item.avgScore ?: return 0.02f
        return (score.coerceIn(0.0, 100.0) / 100.0).toFloat().coerceAtLeast(0.02f)
    }

    /** 今日/剩余时长文案（保留 1 位小数）。 */
    fun minutesText(session: SessionState): String = formatOneDecimal(session.minutesToday.toDouble())

    fun minutesLeft(session: SessionState): String = formatOneDecimal(session.remainingMinutes.toDouble())

    /** 「下次复习：N 天后 ✅」等文案，规则照抄 hos `ReviewVM.nextDueText`。 */
    fun nextDueText(result: ReviewGradeResultDto): String {
        if (result.intervalDays > 0) return "下次复习：${result.intervalDays} 天后 ✅"
        if (result.nextDueAt.isNotEmpty()) return "10 分钟后再来一次 🔁"
        return "已记录 ✅"
    }

    companion object {
        /** 服务端上限 50；hos 默认 20。 */
        private const val REVIEW_LIMIT = 20

        private fun formatEase(ease: Double): String {
            val rounded = kotlin.math.round(ease * 100) / 100.0
            return if (rounded % 1.0 == 0.0) rounded.toInt().toString() else rounded.toString()
        }

        private fun formatOneDecimal(value: Double): String {
            val rounded = kotlin.math.round(value * 10) / 10.0
            return if (rounded % 1.0 == 0.0) rounded.toInt().toString() else rounded.toString()
        }
    }
}

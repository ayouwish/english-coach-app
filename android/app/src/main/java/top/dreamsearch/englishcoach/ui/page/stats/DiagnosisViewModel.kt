package top.dreamsearch.englishcoach.ui.page.stats

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.dto.DiagnosisCountsDto
import top.dreamsearch.englishcoach.core.net.dto.DiagnosisItemDto
import top.dreamsearch.englishcoach.core.net.dto.DiagnosisResponseDto
import top.dreamsearch.englishcoach.ui.design.EcScore
import top.dreamsearch.englishcoach.ui.nav.NavParams
import kotlin.math.abs
import kotlin.math.round

/**
 * 发音诊断页状态（`GET /api/diagnosis` 的 4 个 scope）。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/viewmodel/StatsVM.ets` 的 `DiagnosisVM`
 * 与 `hos/entry/src/main/ets/pages/DiagnosisPage.ets`。差异（Android 端新增）：
 * - hos 页只做 `recent` / `all` 两个 tab；按本端任务要求补上
 *   `attempt`（最近一次评完的评测）与 `batch`（连读这一批，≤20 条）。
 * - `batch` 优先用连读汇总页跳转前写入的 `NavParams.diagnosisAttemptIds`（读完置 null）；
 *   没有时回落到「最近 20 条评完的非盲测记录」。
 * - 排序、阈值配色全部沿用服务端口径（weak<65 / watch 65–80 / ok≥80）；
 *   客户端只按 weak → watch → ok 排序，不重算 status。
 *
 * 数据流：页面只读 [DiagnosisUiState]；错误一律转成 [UiError]（由 SessionStore 做儿童/成人文案）。
 */
enum class DiagnosisScope(val apiScope: String, val label: String) {
    ATTEMPT("attempt", "单句"),
    BATCH("batch", "连读这一批"),
    RECENT("recent", "最近 7 天"),
    ALL("all", "全部累计"),
}

data class DiagnosisUiState(
    val scope: DiagnosisScope = DiagnosisScope.RECENT,
    val loading: Boolean = false,
    val loadedOnce: Boolean = false,
    val error: UiError? = null,
    /** 空态文案（按 scope / 儿童口径生成，见 [DiagnosisViewModel]） */
    val emptyHint: String = "",
    val summaryZh: String = "",
    val minSamples: Int = 2,
    val countedPhonemes: Int = 0,
    val totalPhonemes: Int = 0,
    val weakCount: Int = 0,
    val watchCount: Int = 0,
    val okCount: Int = 0,
    val focusPhonemes: List<String> = emptyList(),
    /** 需要练的（weak + watch），已按 weak → watch、同档均分升序排好 */
    val items: List<DiagnosisItemDto> = emptyList(),
    /** 已掌握（ok），默认折叠 */
    val okItems: List<DiagnosisItemDto> = emptyList(),
    val attemptCount: Int = 0,
    val generatedAt: String = "",
    val showOk: Boolean = false,
) {
    val hasItems: Boolean get() = items.isNotEmpty() || okItems.isNotEmpty()

    /**
     * 空态判定：`counted_phonemes == 0`（任务硬要求）或没有任何可展示的行。
     * 服务端 `min_samples` 口径下 0 个音素计入时，items 必然为空。
     */
    val isEmptyResult: Boolean get() = loadedOnce && (countedPhonemes == 0 || !hasItems)
}

class DiagnosisViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(DiagnosisUiState())
    val state: StateFlow<DiagnosisUiState> = _state.asStateFlow()

    private var loadJob: Job? = null

    /**
     * 「连读这一批」的入参通道：连读汇总页跳转前写 `NavParams.diagnosisAttemptIds`，
     * 本页取走后（NavParams 立即置 null）缓存到本次 scope 会话里；离开 batch 时丢弃。
     */
    private var batchAttemptIdsOverride: List<String> = emptyList()

    init {
        // 有 NavParams 批次 id 时首屏直接展示「连读这一批」
        batchAttemptIdsOverride = takeNavAttemptIds()
        if (batchAttemptIdsOverride.isNotEmpty()) {
            _state.update { it.copy(scope = DiagnosisScope.BATCH) }
        }
        load()
    }

    /** 重新加载当前 scope（错误重试用）。 */
    fun load() {
        val scope = _state.value.scope
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null, emptyHint = "") }
            try {
                loadDiagnosis(scope)
            } catch (e: Throwable) {
                _state.update {
                    it.copy(loading = false, error = c.session.toUiError(e))
                }
            }
        }
    }

    /** 切换统计范围；同 scope 不重复请求（交给 [load] 重试）。 */
    fun switchScope(scope: DiagnosisScope) {
        if (scope == _state.value.scope) return
        if (scope == DiagnosisScope.BATCH) {
            // 切到批次时再取一次 NavParams（连读汇总页可能在页面存活期间写入新批次）
            takeNavAttemptIds().takeIf { it.isNotEmpty() }?.let { batchAttemptIdsOverride = it }
        } else {
            batchAttemptIdsOverride = emptyList()
        }
        _state.update {
            it.copy(
                scope = scope,
                items = emptyList(),
                okItems = emptyList(),
                loadedOnce = false,
                error = null,
                emptyHint = "",
                showOk = false,
                summaryZh = "",
            )
        }
        load()
    }

    fun toggleOk() {
        _state.update { it.copy(showOk = !it.showOk) }
    }

    // ------------------------------------------------------------------ 加载

    private suspend fun loadDiagnosis(scope: DiagnosisScope) {
        when (scope) {
            DiagnosisScope.ATTEMPT -> {
                val attemptId = recentDoneAttemptIds().firstOrNull()
                if (attemptId == null) {
                    applyEmpty(scope)
                    return
                }
                applyDiagnosis(
                    c.stats.diagnosis(scope = DiagnosisScope.ATTEMPT.apiScope, attemptId = attemptId),
                    scope,
                    attemptCount = 1,
                )
            }

            DiagnosisScope.BATCH -> {
                // 优先用连读汇总页写入 NavParams 的批次 id（≤20）；
                // 没有时回落到「最近 20 条评完的非盲测记录」（线上无单句历史接口，CONTRACT §3.2）。
                val ids = (batchAttemptIdsOverride.ifEmpty { recentDoneAttemptIds() }).take(BATCH_MAX)
                if (ids.isEmpty()) {
                    applyEmpty(scope)
                    return
                }
                applyDiagnosis(
                    c.stats.diagnosis(scope = DiagnosisScope.BATCH.apiScope, attemptIds = ids),
                    scope,
                    attemptCount = ids.size,
                )
            }

            DiagnosisScope.RECENT ->
                applyDiagnosis(
                    c.stats.diagnosis(scope = DiagnosisScope.RECENT.apiScope, days = RECENT_DAYS),
                    scope,
                    attemptCount = 0,
                )

            DiagnosisScope.ALL ->
                applyDiagnosis(
                    c.stats.diagnosis(scope = DiagnosisScope.ALL.apiScope),
                    scope,
                    attemptCount = 0,
                )
        }
    }

    /** 最近「已评完且非盲测」的记录 id（attempt/batch 的兜底数据源）。 */
    private suspend fun recentDoneAttemptIds(): List<String> =
        c.practice.attempts(limit = ATTEMPT_FETCH_LIMIT)
            .filter { it.id.isNotEmpty() && !it.blind && !it.pending }
            .map { it.id }

    /** 读取并清空 `NavParams.diagnosisAttemptIds`（读完即置 null，符合跨页参数约定）。 */
    private fun takeNavAttemptIds(): List<String> {
        val ids = NavParams.diagnosisAttemptIds
        NavParams.diagnosisAttemptIds = null
        return ids.orEmpty().filter { it.isNotBlank() }.take(BATCH_MAX)
    }

    private fun applyDiagnosis(dto: DiagnosisResponseDto, scope: DiagnosisScope, attemptCount: Int) {
        val all = dto.items
        val weakWatch = all.filter { it.status != STATUS_OK }.sortedWith(itemComparator(okGroup = false))
        val okItems = all.filter { it.status == STATUS_OK }.sortedWith(itemComparator(okGroup = true))
        val counts = dto.counts ?: DiagnosisCountsDto()
        val counted = dto.countedPhonemes
        _state.update {
            it.copy(
                scope = scope,
                loading = false,
                loadedOnce = true,
                error = null,
                emptyHint = emptyHintFor(scope, counted),
                summaryZh = dto.summaryZh,
                minSamples = if (dto.minSamples > 0) dto.minSamples else 2,
                countedPhonemes = counted,
                totalPhonemes = dto.totalPhonemes,
                weakCount = counts.weak,
                watchCount = counts.watch,
                okCount = counts.ok,
                focusPhonemes = dto.focusPhonemes,
                items = weakWatch,
                okItems = okItems,
                attemptCount = if (attemptCount > 0) attemptCount else (dto.range?.attemptCount ?: 0),
                generatedAt = dto.generatedAt,
            )
        }
    }

    private fun applyEmpty(scope: DiagnosisScope) {
        _state.update {
            it.copy(
                scope = scope,
                loading = false,
                loadedOnce = true,
                error = null,
                emptyHint = emptyHintFor(scope, countedPhonemes = 0),
                summaryZh = "",
                countedPhonemes = 0,
                totalPhonemes = 0,
                weakCount = 0,
                watchCount = 0,
                okCount = 0,
                focusPhonemes = emptyList(),
                items = emptyList(),
                okItems = emptyList(),
                attemptCount = 0,
            )
        }
    }

    // ------------------------------------------------------------------ 展示文案

    /** 统计口径小字。 */
    fun metricText(s: DiagnosisUiState): String {
        val weak = s.weakCount
        val watch = s.watchCount
        val ok = s.okCount
        return when (s.scope) {
            DiagnosisScope.ATTEMPT ->
                "统计口径：最近一次评测 · ${s.countedPhonemes} 个音素计入（薄弱 $weak / 待巩固 $watch / 已掌握 $ok）。"

            DiagnosisScope.BATCH ->
                "统计口径：这一批 ${s.attemptCount} 条记录 · ${s.countedPhonemes} 个音素计入" +
                    "（薄弱 $weak / 待巩固 $watch / 已掌握 $ok）。"

            DiagnosisScope.RECENT ->
                "统计口径：最近 $RECENT_DAYS 天 · ${s.countedPhonemes} 个音素计入" +
                    "（薄弱 $weak / 待巩固 $watch / 已掌握 $ok）。"

            DiagnosisScope.ALL ->
                "统计口径：每个音素至少 ${s.minSamples} 次记录才计入" +
                    "（共 ${s.countedPhonemes} 个达标，薄弱 $weak / 待巩固 $watch / 已掌握 $ok）。"
        }
    }

    /** 音素行标题：成人 `/<ipa>/ · 咬舌的 th`，儿童只有 child_label。 */
    fun itemTitle(item: DiagnosisItemDto, isChild: Boolean): String {
        if (isChild) return item.childLabel.ifEmpty { "这个音" }
        if (item.phoneme.isEmpty()) return item.childLabel
        return if (item.childLabel.isEmpty()) "/${item.phoneme}/" else "/${item.phoneme}/ · ${item.childLabel}"
    }

    /**
     * 分数行：成人 `61.2 分 · 5 次记录`；儿童按 [EcScore.showNumber] 规则
     * （<60 不显示数字，只显示练习次数），>=60 才带平均分。
     */
    fun scoreLine(item: DiagnosisItemDto, isChild: Boolean): String {
        if (isChild) {
            val avg = item.avgScore
            return if (avg != null && EcScore.showNumber(avg, true)) {
                "平均 ${formatScore(avg)} 分 · 练过 ${item.attempts} 次"
            } else {
                "练过 ${item.attempts} 次"
            }
        }
        val avg = item.avgScore?.let { formatScore(it) } ?: "—"
        return "$avg 分 · ${item.attempts} 次记录"
    }

    /** 趋势文案（成人含数字，儿童只用趋势方向）。 */
    fun trendText(item: DiagnosisItemDto, isChild: Boolean): String {
        val trend = item.trend ?: return ""
        return if (isChild) {
            when (trend.direction) {
                "improving" -> "最近在进步 ↗"
                "declining" -> "最近有点下滑 ↘"
                else -> "最近比较稳定 →"
            }
        } else {
            val delta = abs(round(trend.delta)).toInt()
            when (trend.direction) {
                "improving" -> "近 3 次 ↗ 在进步（+$delta）"
                "declining" -> "近 3 次 ↘ 略有下滑（-$delta）"
                else -> "近 3 次 → 基本持平"
            }
        }
    }

    fun statusLabel(status: String): String = when (status) {
        "weak" -> "需要练"
        "watch" -> "待巩固"
        else -> "已掌握"
    }

    /** 第一优先级 focus token（顶部主按钮用）。儿童也返回 API 用的 token，不返回展示 label。 */
    fun firstFocusToken(s: DiagnosisUiState): String {
        s.focusPhonemes.firstOrNull { it.isNotBlank() }?.let { return it }
        s.items.firstOrNull()?.focusToken?.takeIf { it.isNotBlank() }?.let { return it }
        return s.items.firstOrNull()?.phoneme.orEmpty()
    }

    /** 单张卡片的强化练习 token：focus_token 优先，退回音素符号。 */
    fun focusTokenOf(item: DiagnosisItemDto): String =
        item.focusToken.ifBlank { item.phoneme }

    // ------------------------------------------------------------------ 内部

    private fun itemComparator(okGroup: Boolean): Comparator<DiagnosisItemDto> = Comparator { a, b ->
        if (okGroup) {
            // ok 档：均分高的在前（null 排最后）
            compareScoreDesc(a.avgScore, b.avgScore)
        } else {
            // weak(0) → watch(1)；同档均分低的在前（null 排最后）
            val rankA = statusRank(a.status)
            val rankB = statusRank(b.status)
            if (rankA != rankB) rankA - rankB else compareScoreAsc(a.avgScore, b.avgScore)
        }
    }

    private fun statusRank(status: String): Int = when (status) {
        "weak" -> 0
        "watch" -> 1
        else -> 2
    }

    private fun compareScoreAsc(a: Double?, b: Double?): Int = when {
        a == null && b == null -> 0
        a == null -> 1
        b == null -> -1
        else -> a.compareTo(b)
    }

    private fun compareScoreDesc(a: Double?, b: Double?): Int = -compareScoreAsc(a, b)

    companion object {
        /** 最近 7 天（服务端默认 scope=recent&days=7）。 */
        const val RECENT_DAYS = 7

        /** batch 诊断服务端硬上限（CONTRACT §3.2：≤20 个 attempt id）。 */
        private const val BATCH_MAX = 20

        /** 单句/批次需要从 `/attempts` 自己攒 id；取最近 20 条足够覆盖。 */
        private const val ATTEMPT_FETCH_LIMIT = 20

        private const val STATUS_OK = "ok"

        /** 空态文案：counted_phonemes==0 时按任务口径提示"每个音至少 2 次记录"。 */
        fun emptyHintFor(scope: DiagnosisScope, countedPhonemes: Int): String = when (scope) {
            DiagnosisScope.ATTEMPT ->
                if (countedPhonemes == 0) "这一句还没有可统计的音，去跟读再读一句吧" else ""

            DiagnosisScope.BATCH ->
                if (countedPhonemes == 0) "这一批还没有可统计的记录，再去连读几句吧" else ""

            else ->
                if (countedPhonemes == 0) "每个音至少要有 2 次记录，先去跟读几句吧" else ""
        }

        /** 分数显示（保留 1 位小数；整数不带 `.0`），与 hos 的 `Math.round(x*10)/10` 一致。 */
        fun formatScore(score: Double): String {
            val rounded = round(score * 10) / 10.0
            return if (rounded % 1.0 == 0.0) rounded.toInt().toString() else rounded.toString()
        }
    }
}

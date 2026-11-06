package top.dreamsearch.englishcoach.ui.page.account

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
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.dto.ParentFamilyDto
import top.dreamsearch.englishcoach.core.net.dto.ParentMemberDto

/**
 * 家长面板 VM（对应 hos `ParentVM`，`hos/entry/.../viewmodel/AccountVM.ets` L678-959）。
 *
 * 数据来源：`AccountService.parentSummary()`（`GET /api/parent/summary`，仅家长）。
 * 关键约定：
 * - **儿童/非家长**：客户端先看 `session.role`，直接显示「只有家长能看」；
 *   若客户端判断被绕过，服务端 403 也会落到同一 forbidden 视图（**不跳登录**）；
 * - 数字一律经 [AccountFormat] 兜底为「—」，`null` 不画成 0；
 * - 刷新时保留旧数据（不闪白）：`loading` 只用于首屏，`refreshing` 用于右上角动作。
 */
data class ParentUiState(
    /** 首屏加载（骨架） */
    val loading: Boolean = true,
    /** 手动刷新（保留旧数据 + 顶部提示） */
    val refreshing: Boolean = false,
    val loadedOnce: Boolean = false,
    /** 非家长（客户端判断或服务端 403） */
    val forbidden: Boolean = false,
    val error: UiError? = null,
    val isParent: Boolean = false,
    val family: ParentFamilyDto? = null,
    val members: List<ParentMemberDto> = emptyList(),
)

class ParentViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(ParentUiState())
    val state: StateFlow<ParentUiState> = _state.asStateFlow()

    private var loadJob: Job? = null

    init {
        // 角色变化（切账号/会话恢复）→ 立刻决定是否显示 forbidden；非家长不发请求
        viewModelScope.launch {
            c.session.state.collect { session ->
                // 会话还没恢复（userId 为空）时先不判定角色，避免启动瞬间误报「只有家长能看」
                if (session.userId.isEmpty()) return@collect
                val isParent = session.role == "parent" && !session.isChild
                _state.update { current ->
                    if (!isParent) {
                        current.copy(
                            isParent = false,
                            forbidden = true,
                            loading = false,
                            refreshing = false,
                            loadedOnce = true,
                        )
                    } else {
                        current.copy(isParent = true, forbidden = false)
                    }
                }
            }
        }
        // 会话已知是儿童/非家长时不必发请求（服务端也会 403）；会话还没恢复时先试一次
        val session = c.session.state.value
        if (session.role == "parent" && !session.isChild || session.userId.isEmpty()) {
            load()
        }
    }

    /** 拉取汇总；[manual] = 用户点「刷新」（保留旧数据）。 */
    fun load(manual: Boolean = false) {
        if (_state.value.forbidden) return
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _state.update {
                it.copy(
                    loading = !manual && !it.loadedOnce,
                    refreshing = manual,
                    error = null,
                )
            }
            try {
                val dto = c.account.parentSummary()
                _state.update {
                    it.copy(
                        loading = false,
                        refreshing = false,
                        loadedOnce = true,
                        forbidden = false,
                        error = null,
                        family = dto.family,
                        members = dto.members,
                    )
                }
            } catch (e: Throwable) {
                val apiError = e as? ApiError
                if (apiError != null && apiError.status == 403) {
                    _state.update {
                        it.copy(
                            loading = false,
                            refreshing = false,
                            loadedOnce = true,
                            forbidden = true,
                            error = UiError(
                                message = apiError.detail.ifEmpty { "家长面板仅对家长账号开放" },
                                code = ApiErrorCode.FORBIDDEN,
                            ),
                        )
                    }
                } else {
                    val ui = c.session.toUiErrorAsync(e)
                    _state.update {
                        it.copy(
                            loading = false,
                            refreshing = false,
                            loadedOnce = true,
                            error = ui,
                        )
                    }
                }
            }
        }
    }

    fun refresh() = load(manual = true)

    // ------------------------------------------------------------------ 展示用派生值

    /** 全家一行摘要（对应 hos `ParentVM.familyText`）。 */
    fun familyText(family: ParentFamilyDto?): String {
        if (family == null) return "还没有家庭数据"
        val today = AccountFormat.minutes(family.minutesToday)
        val week = AccountFormat.minutes(family.minutes7d)
        return "全家今天共练习 $today 分钟，近 7 天 $week 分钟 · " +
            "语料 ${family.sentenceCount} 句 · 对话场景 ${family.scenarioCount} 个"
    }

    /** 今日一行：练习 + 盲测 + 跟读次数 + 对话轮数 + 剩余时长（儿童才有 remaining）。 */
    fun todayText(member: ParentMemberDto): String {
        val today = member.today ?: return "今日暂无练习"
        val minutes = AccountFormat.minutes(today.minutes)
        val parts = StringBuilder("今日练习 $minutes 分钟")
        if (today.blindMinutes > 0) parts.append(" + 盲测 ${AccountFormat.minutes(today.blindMinutes)} 分钟")
        parts.append(" · 跟读 ${today.attemptCount} 次 · 对话 ${today.chatTurns} 轮")
        today.remainingMinutes?.let { parts.append(" · 剩余 ${AccountFormat.minutes(it)} 分钟") }
        if (today.exceeded) parts.append(" · 今日已用满")
        return parts.toString()
    }

    /** 周/累计一行（对应 hos `ParentVM.memberWeekText`）。 */
    fun weekText(member: ParentMemberDto): String {
        val week = member.week
        val totals = member.totals
        if (week == null && totals == null) return ""
        val minutes = AccountFormat.minutes(week?.minutes ?: 0)
        val attempts = week?.attempts ?: 0
        val avg = AccountFormat.scoreText(week?.avgPron)
        val totalAttempts = totals?.attempts ?: 0
        val sessions = totals?.chatSessions ?: 0
        return "近 7 天时长 $minutes 分钟 · 近 7 天练习 $attempts 次 · 近 7 天平均分 $avg · " +
            "累计 $totalAttempts 次跟读 / $sessions 场对话"
    }

    /** 盲测最近一次综合分（null = 还没做）。 */
    fun blindCurrentPron(member: ParentMemberDto): Double? = member.blind?.current?.avgPron

    /** 盲测环比（涨/跌/持平/首次）。 */
    fun blindDeltaText(member: ParentMemberDto): String =
        AccountFormat.blindDeltaText(member.blind?.deltaPron)

    /** 已完成盲测次数。 */
    fun blindWeeks(member: ParentMemberDto): Int = member.blind?.weeks ?: 0

    /** 盲测柱状图：历次 avg_pron。 */
    fun blindBarValues(member: ParentMemberDto): List<Float> =
        (member.blind?.series ?: emptyList()).mapNotNull { it.avgPron?.toFloat() }

    /** 盲测柱状图 X 轴：历次日期。 */
    fun blindBarLabels(member: ParentMemberDto): List<String> =
        (member.blind?.series ?: emptyList()).map { AccountFormat.dateText(it.endedAt) }

    /** 盲测子项（准确/流利/语调差异）。 */
    fun blindAccuracy(member: ParentMemberDto): Double? = member.blind?.current?.avgAccuracy

    fun blindFluency(member: ParentMemberDto): Double? = member.blind?.current?.avgFluency

    fun blindIntonation(member: ParentMemberDto): Double? = member.blind?.current?.avgIntonationDistance

    /** 正在做盲测（显示「正在做盲测…」标签）。 */
    fun blindInProgress(member: ParentMemberDto): Boolean =
        !member.blind?.inProgressId.isNullOrEmpty()

    /** 近 14 天趋势文字（最后 3 天，对应 hos `trendTail`）。 */
    fun trendTail(member: ParentMemberDto): String {
        val points = member.trend
        if (points.isEmpty()) return "暂无数据"
        val start = if (points.size > 3) points.size - 3 else 0
        return points.drop(start).joinToString(" · ") { point ->
            "${AccountFormat.dateText(point.date)}: ${AccountFormat.scoreText(point.avgPron)}"
        }
    }

    /** 薄弱音素一行：`/θ/ 舌齿音 · 均 61 · 12 次 · 低于60 8 次`。 */
    fun phonemeText(item: top.dreamsearch.englishcoach.core.net.dto.ParentPhonemeDto): String {
        val title = item.titleZh
        val head = if (title.isEmpty()) item.phoneme else "${item.phoneme} $title"
        return "$head · 均 ${AccountFormat.scoreText(item.avgScore)} · ${item.count} 次 · " +
            "低于60 ${item.hardHits} 次"
    }

    /** 高频错词一行：`think × 4（均 55）`。 */
    fun wordText(item: top.dreamsearch.englishcoach.core.net.dto.ParentWordDto): String =
        "${item.word} × ${item.count}（均 ${AccountFormat.scoreText(item.avgScore)}）"
}

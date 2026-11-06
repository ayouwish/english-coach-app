package top.dreamsearch.englishcoach.ui.page.stats

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.dto.BlindFinishDto
import top.dreamsearch.englishcoach.core.net.dto.BlindTestDto
import top.dreamsearch.englishcoach.core.net.dto.BlindTestListDto
import top.dreamsearch.englishcoach.core.net.dto.BlindTrendDto
import top.dreamsearch.englishcoach.core.net.dto.BlindTrendScoreDto
import java.io.File
import kotlin.math.round

/**
 * 盲测页状态：`GET/POST /api/blind-tests` + 运行中提交同步评测 `POST /attempts`（带 blind_test_id）。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/viewmodel/StatsVM.ets` 的 `BlindTestVM`；
 * 交互按本端任务扩展为「Intro → Running（在盲测页内直接录音提交）→ Finish」一页闭环
 * （hos 是在跟读页的盲测模式里录音，本端按任务要求合并进盲测页）。
 *
 * 提交方式（Lead 2026-11-04 修正，与 hos 实际实现一致）：
 * - 用 `PracticeService.evaluate(...)`（同步 `POST /attempts`，multipart 带 `blind_test_id`），
 *   **不用** `FlowService.submitAsync`；盲测响应同样只有 `attempt_id/blind/progress`，不含分数。
 *
 * 防作弊硬规则（.specs/practice-flow.md §6.3）：
 * - 进行中**绝不读取/展示任何分数**，轮询只更新 `scored / pending` 计数；
 * - 不使用 `retryAttempt`（服务端对盲测记录返回 409）；
 * - 结束后才展示 `avg_pron / delta_pron / notice`。
 *
 * 限额前置（CONTRACT §6.4，比 hos 更严）：`session.exceeded == true` 时开始/提交直接本地拒绝，
 * 不等服务端 429；页面同时禁用按钮并提示剩余时长。
 *
 * 轮询生命周期：`startPolling()` 在 [viewModelScope] 内每 2s 拉一次列表；
 * 页面离开（onDispose）或结束时调用 [stopPolling]；[onCleared] 兜底取消。
 */
enum class BlindPhase { INTRO, RUNNING, FINISH }

/** 运行中的句子（id + 参考原文；原文从历史 attempts / 语料兜底解析）。 */
data class BlindSentenceUi(
    val id: String,
    val text: String = "",
)

data class BlindTestUiState(
    val loading: Boolean = false,
    val loadedOnce: Boolean = false,
    val error: UiError? = null,
    val phase: BlindPhase = BlindPhase.INTRO,
    val tests: List<BlindTestDto> = emptyList(),
    val inProgress: BlindTestDto? = null,
    val pendingTotal: Int = 0,
    val trend: BlindTrendDto? = null,
    val series: List<BlindTrendScoreDto> = emptyList(),
    val starting: Boolean = false,
    val startError: UiError? = null,
    // ---- Running ----
    val blindTestId: String = "",
    val sentences: List<BlindSentenceUi> = emptyList(),
    val total: Int = 0,
    /** 已提交句数（本地成功提交计数；进入/恢复时用服务端 scored+pending 播种） */
    val submitted: Int = 0,
    /** 服务端已评完句数（轮询更新） */
    val scored: Int = 0,
    /** 服务端仍在后台评分的句数（轮询更新） */
    val pending: Int = 0,
    val submitting: Boolean = false,
    val submitError: UiError? = null,
    // ---- Finish ----
    val finishing: Boolean = false,
    val finishError: UiError? = null,
    val finish: BlindFinishDto? = null,
) {
    val isRunning: Boolean get() = phase == BlindPhase.RUNNING
    val isFinished: Boolean get() = phase == BlindPhase.FINISH
    val allSubmitted: Boolean get() = total > 0 && submitted >= total
    val currentSentence: BlindSentenceUi? get() = sentences.getOrNull(submitted)
    val progress: Float
        get() = if (total <= 0) 0f else (submitted.toFloat() / total.toFloat()).coerceIn(0f, 1f)
}

class BlindTestViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(BlindTestUiState())
    val state: StateFlow<BlindTestUiState> = _state.asStateFlow()

    private var pollJob: Job? = null

    init {
        load()
    }

    // ------------------------------------------------------------------ 列表 / 开始 / 结束

    fun load() {
        if (_state.value.loading) return
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            try {
                val dto = c.stats.blindTests()
                applyList(dto)
                _state.update { it.copy(loading = false, loadedOnce = true, error = null) }
            } catch (e: Throwable) {
                _state.update { it.copy(loading = false, error = c.session.toUiError(e)) }
            }
        }
    }

    /** 开始或恢复一次盲测（服务端已有进行中时返回同一批次，`resumed=true`）。 */
    fun start() {
        if (_state.value.starting) return
        // 限额前置：今日时长用完时本地直接拒绝（不等 429 / daily_limit_reached）
        if (c.session.state.value.exceeded) {
            _state.update { it.copy(startError = dailyLimitError()) }
            return
        }
        _state.update { it.copy(starting = true, startError = null) }
        viewModelScope.launch {
            try {
                val dto = c.stats.startBlindTest()
                val ids = dto.sentenceIds
                val total = if (dto.total > 0) dto.total else ids.size
                enterRunning(
                    blindTestId = dto.blindTestId,
                    sentenceIds = ids,
                    total = total,
                    submitted = 0,
                    scored = 0,
                    pending = 0,
                )
                // resumed：服务端复用了已有批次，用列表里的进度校准已提交句数
                if (dto.resumed) {
                    val list = runCatching { c.stats.blindTests() }.getOrNull()
                    if (list != null) {
                        applyList(list)
                        val ip = list.inProgress
                        if (ip != null && ip.id == dto.blindTestId) {
                            _state.update {
                                it.copy(
                                    submitted = it.submitted + ip.scored + ip.pending,
                                    scored = ip.scored,
                                    pending = ip.pending,
                                )
                            }
                        }
                    }
                } else {
                    runCatching { applyList(c.stats.blindTests()) }
                }
            } catch (e: Throwable) {
                _state.update { it.copy(startError = c.session.toUiError(e)) }
            } finally {
                _state.update { it.copy(starting = false) }
            }
        }
    }

    /** Intro 上「继续」：用列表里的进行中批次进入 Running。 */
    fun continueRun() {
        val progress = _state.value.inProgress ?: return
        enterRunning(
            blindTestId = progress.id,
            sentenceIds = progress.sentenceIds,
            total = progress.itemCount,
            submitted = progress.scored + progress.pending,
            scored = progress.scored,
            pending = progress.pending,
        )
    }

    /** 结束当前批次并拿到周报（`POST /blind-tests/:id/finish`，幂等）。 */
    fun finish() {
        val s = _state.value
        if (s.finishing || s.blindTestId.isEmpty()) return
        _state.update { it.copy(finishing = true, finishError = null) }
        viewModelScope.launch {
            try {
                val dto = c.stats.finishBlindTest(s.blindTestId)
                stopPolling()
                _state.update {
                    it.copy(
                        finishing = false,
                        phase = BlindPhase.FINISH,
                        finish = dto,
                        inProgress = null,
                        finishError = null,
                    )
                }
                // 刷新周报列表/趋势（失败不影响本次完成卡）
                runCatching { applyList(c.stats.blindTests()) }
            } catch (e: Throwable) {
                _state.update { it.copy(finishing = false, finishError = c.session.toUiError(e)) }
            }
        }
    }

    // ------------------------------------------------------------------ Running

    /**
     * 提交一句盲测录音：读完录音文件 → 同步 `POST /attempts`（带 blind_test_id）。
     *
     * 与 hos 一致用 [PracticeService.evaluate]（同步评测），响应只有 `attempt_id/blind/progress`，
     * 这里**不读取也不保存任何分数**（盲测期间服务端也不返回）。
     * 成功后立刻进入下一句（UI 不等评分）；失败保留当前句并展示 [UiError]。
     */
    fun submitRecording(file: File, durationMs: Long) {
        val s = _state.value
        if (s.submitting) return
        if (c.session.state.value.exceeded) {
            _state.update { it.copy(submitError = dailyLimitError()) }
            return
        }
        val sentence = s.currentSentence ?: return
        if (sentence.text.isBlank()) {
            _state.update {
                it.copy(
                    submitting = false,
                    submitError = UiError.of("bad_request", "这一句的原文暂时取不到，先跳过这一句吧", false),
                )
            }
            return
        }
        if (s.blindTestId.isEmpty()) return
        _state.update { it.copy(submitting = true, submitError = null) }
        viewModelScope.launch {
            try {
                val bytes = withContext(Dispatchers.IO) { file.readBytes() }
                val result = c.practice.evaluate(
                    audio = bytes,
                    sentenceId = sentence.id,
                    referenceText = sentence.text,
                    durationMs = durationMs.toInt(),
                    blindTestId = s.blindTestId,
                )
                // 完成即同步用量（CONTRACT §6.5）；盲测响应不含分数，只用 usage。
                result.usage?.let { c.session.updateUsage(it) }
                _state.update { it.copy(submitting = false, submitted = it.submitted + 1) }
            } catch (e: Throwable) {
                _state.update { it.copy(submitting = false, submitError = c.session.toUiError(e)) }
            } finally {
                runCatching { file.delete() }
            }
        }
    }

    /** 原文拿不到时跳过当前句（不提交，不计入服务端，只推进本地进度）。 */
    fun skipCurrent() {
        val s = _state.value
        if (s.submitted >= s.total) return
        _state.update { it.copy(submitted = it.submitted + 1, submitError = null) }
    }

    fun dismissStartError() {
        _state.update { it.copy(startError = null) }
    }

    fun dismissSubmitError() {
        _state.update { it.copy(submitError = null) }
    }

    fun dismissFinishError() {
        _state.update { it.copy(finishError = null) }
    }

    // ------------------------------------------------------------------ 轮询

    /** 每 2s 轮询 `GET /blind-tests`，只读 `in_progress.scored / pending` 计数。 */
    private fun startPolling() {
        pollJob?.cancel()
        pollJob = viewModelScope.launch {
            while (isActive) {
                delay(POLL_INTERVAL_MS)
                if (_state.value.phase != BlindPhase.RUNNING) break
                val dto = runCatching { c.stats.blindTests() }.getOrNull() ?: continue
                applyList(dto)
            }
        }
    }

    /** 页面离开 / 结束批次时取消轮询（幂等）。 */
    fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    override fun onCleared() {
        stopPolling()
        super.onCleared()
    }

    // ------------------------------------------------------------------ 内部

    private fun enterRunning(
        blindTestId: String,
        sentenceIds: List<String>,
        total: Int,
        submitted: Int,
        scored: Int,
        pending: Int,
    ) {
        val safeTotal = maxOf(total, sentenceIds.size)
        _state.update {
            it.copy(
                phase = BlindPhase.RUNNING,
                blindTestId = blindTestId,
                sentences = sentenceIds.map { id -> BlindSentenceUi(id = id, text = "") },
                total = safeTotal,
                submitted = submitted.coerceIn(0, safeTotal),
                scored = scored,
                pending = pending,
                submitting = false,
                submitError = null,
                startError = null,
                finish = null,
                finishError = null,
            )
        }
        startPolling()
        loadSentenceTexts(blindTestId, sentenceIds)
    }

    /** 解析每句的参考原文：优先历史 attempts 的 reference_text，再用当前等级语料兜底。 */
    private fun loadSentenceTexts(blindTestId: String, sentenceIds: List<String>) {
        if (sentenceIds.isEmpty()) return
        viewModelScope.launch {
            val texts = resolveSentenceTexts(sentenceIds)
            if (_state.value.blindTestId == blindTestId) {
                _state.update { it.copy(sentences = texts) }
            }
        }
    }

    private suspend fun resolveSentenceTexts(sentenceIds: List<String>): List<BlindSentenceUi> {
        val known = LinkedHashMap<String, String>()
        runCatching { c.practice.attempts(limit = 100) }.getOrNull()?.forEach { attempt ->
            val sid = attempt.sentenceId
            if (sid.isNullOrEmpty() || attempt.referenceText.isBlank()) return@forEach
            if (!known.containsKey(sid)) known[sid] = attempt.referenceText
        }
        if (sentenceIds.any { !known.containsKey(it) }) {
            runCatching { c.practice.sentences(level = c.session.state.value.cefrLevel) }
                .getOrNull()
                ?.forEach { sentence ->
                    if (sentence.id.isNotEmpty() && sentence.text.isNotBlank()) {
                        known.putIfAbsent(sentence.id, sentence.text)
                    }
                }
        }
        return sentenceIds.map { id -> BlindSentenceUi(id = id, text = known[id].orEmpty()) }
    }

    /** 列表数据落到 state；Running 时只同步评分计数（不改已提交句数，避免跳句）。 */
    private fun applyList(dto: BlindTestListDto) {
        _state.update { current ->
            val inProgress = dto.inProgress
            var next = current.copy(
                tests = dto.tests,
                inProgress = inProgress,
                pendingTotal = dto.pendingTotal,
                trend = dto.trend,
                series = dto.series,
            )
            if (current.phase == BlindPhase.RUNNING && inProgress != null) {
                next = next.copy(scored = inProgress.scored, pending = inProgress.pending)
            }
            next
        }
    }

    // ------------------------------------------------------------------ 展示文案

    /** 日期标签 `M/d`（解析失败时退化为 ISO 前 10 位）。 */
    fun dateLabel(iso: String?): String {
        if (iso.isNullOrEmpty()) return "—"
        return runCatching {
            val parsed = java.time.OffsetDateTime.parse(iso)
            "${parsed.monthValue}/${parsed.dayOfMonth}"
        }.recoverCatching {
            val parsed = java.time.LocalDateTime.parse(iso.removeSuffix("Z"))
            "${parsed.monthValue}/${parsed.dayOfMonth}"
        }.getOrElse { iso.take(10) }
    }

    fun formatScore(score: Double?): String {
        if (score == null) return "—"
        val rounded = round(score * 10) / 10.0
        return if (rounded % 1.0 == 0.0) rounded.toInt().toString() else rounded.toString()
    }

    /** 与上次相比的文案（成人）：`▲ +4.4` / `▼ -2` / `＝ 0` / `首次（无对比）`。 */
    fun deltaText(delta: Double?): String {
        if (delta == null) return "首次（无对比）"
        return when {
            delta > 0 -> "▲ +${formatScore(delta)}"
            delta < 0 -> "▼ ${formatScore(delta)}"
            else -> "＝ 0"
        }
    }

    companion object {
        /** 进度轮询间隔（web 规格 2000ms）。 */
        private const val POLL_INTERVAL_MS = 2_000L
    }

    /** 限额前置的统一错误（成人 / 儿童两套文案，附带剩余时长）。 */
    private fun dailyLimitError(): UiError {
        val session = c.session.state.value
        val minutes = session.remainingMinutes.coerceAtLeast(0)
        return if (session.isChild) {
            UiError.of(
                ApiErrorCode.DAILY_LIMIT_REACHED,
                "今天已经练得很棒啦，还剩 $minutes 分钟，明天再来 🌙",
                false,
            )
        } else {
            UiError.of(
                ApiErrorCode.DAILY_LIMIT_REACHED,
                "今天的练习时长已达上限（剩余 $minutes 分钟），明天再来",
                false,
            )
        }
    }
}

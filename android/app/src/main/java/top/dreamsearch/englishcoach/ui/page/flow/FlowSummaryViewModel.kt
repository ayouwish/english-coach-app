package top.dreamsearch.englishcoach.ui.page.flow

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import top.dreamsearch.englishcoach.core.audio.Voices
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.dto.FlowDiagnosisItemDto
import top.dreamsearch.englishcoach.ui.design.EcScore

/**
 * 连读汇总页（push 出来的二级页）的 ViewModel。
 *
 * 对应 hos：`hos/entry/src/main/ets/pages/FlowSummaryPage.ets`（页面内直接读 FlowRunStore 与调服务）+
 * `FlowVM.buildSummary()` 的快照数据。
 *
 * 数据来源：
 * - 本轮运行态：进程内 [FlowRunStore] 里的 [FlowViewModel]（与连读 Tab 共享同一份状态），
 *   打开页面时构建一次 [FlowSummaryData] 快照（含 materialId / 是否来自故事材料）；
 * - 这一批的问题：`FlowService.diagnosisBatch(attemptIds)`（`GET /diagnosis?scope=batch`，≤20 个 id）；
 * - 保存自定义文本：`FlowService.createPage(title, text)`；
 * - 听鼓励语：`PracticeService.tts()`（中文/英文两句）→ `AudioController.playBytes()`，音色/语速走 `VoicePrefs`；
 * - 待补评分队列条数：`AppGraph.container.pendingUploads.count()`（第二轮离线能力）。
 *
 * 「再读一遍 / 重录这句 / 再读一段」直接改共享运行态，然后由页面回调 [FlowSummaryScreen.onOpenFlowTab]
 * 切回连读 Tab（与 hos `NavigationService.pop()` 等价）；「复述这个故事」由页面回调
 * [FlowSummaryScreen.onOpenReview]（仅本轮来自故事材料时显示）。
 */
class FlowSummaryViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(FlowSummaryUiState())
    val state: StateFlow<FlowSummaryUiState> = _state.asStateFlow()

    init {
        val run = FlowRunStore.current()
        if (run == null) {
            _state.value = FlowSummaryUiState(ready = false)
        } else {
            val runState = run.state.value
            val summary = run.buildSummary()
            _state.value = FlowSummaryUiState(
                ready = true,
                isChild = runState.isChild,
                summary = summary,
                items = summary.items,
                customText = run.customTextForSave(),
                saveTitle = run.suggestedPageTitle(),
                savedPageId = runState.savedPageId,
                savedPageTitle = runState.savedPageTitle,
            )
            loadDiagnosis()
            refreshPendingUploads()
        }
    }

    override fun onCleared() {
        runCatching { c.audio.stopPlayback() }
        super.onCleared()
    }

    // ---------------------------------------------------------------- 待补评分队列

    /**
     * 刷新「待补评分」条数（`PendingUploadQueue.count()`，含历史批次）。
     * 汇总页打开时调用一次；从「待补评分」页返回时页面再调一次（导航 pop 会重建本页 composition）。
     */
    fun refreshPendingUploads() {
        val count = runCatching { c.pendingUploads.count() }.getOrDefault(0)
        _state.update { it.copy(pendingUploads = count) }
    }

    // ---------------------------------------------------------------- 诊断

    /** 这一批的问题（`GET /diagnosis?scope=batch&attempt_ids=`，≤20；没有已评分句子就不请求）。 */
    fun loadDiagnosis() {
        val ids = _state.value.summary?.attemptIds.orEmpty()
        if (ids.isEmpty() || _state.value.diagLoading) return
        val child = _state.value.isChild
        viewModelScope.launch {
            _state.update { it.copy(diagLoading = true, diagError = "") }
            try {
                val dto = c.flow.diagnosisBatch(ids)
                val chips = dto.items.take(5).mapNotNull { diagnosisChip(it, child) }
                var summary = dto.summaryZh
                if (chips.isEmpty() && summary.isEmpty()) {
                    summary = if (child) "这一批读得不错，继续保持" else "这一批没有明显的薄弱音素，保持就好 👍"
                }
                _state.update {
                    it.copy(diagLoading = false, diagSummary = summary, diagChips = chips)
                }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(
                        diagLoading = false,
                        diagError = if (child) {
                            "这一批的问题暂时没有读到，可以稍后再看"
                        } else {
                            "读取这一批的诊断失败，可以稍后再试"
                        },
                    )
                }
            }
        }
    }

    /** 诊断标签：儿童只认 child_label（绝不出现 IPA）；成人显示 /音素/ + 平均分。 */
    private fun diagnosisChip(item: FlowDiagnosisItemDto, isChild: Boolean): DiagChip? {
        val label = when {
            isChild -> item.childLabel
            item.phoneme.isNotEmpty() -> "/${item.phoneme}/" +
                if (item.childLabel.isNotEmpty()) " ${item.childLabel}" else ""
            else -> item.childLabel
        }
        if (label.isEmpty()) return null
        val avg = item.avgScore
        val text = if (avg != null && EcScore.showNumber(avg, isChild)) {
            "$label · ${EcScore.numberText(avg)} 分"
        } else {
            label
        }
        return DiagChip(label = text, tone = diagnosisTone(item.status, isChild))
    }

    private fun diagnosisTone(status: String, isChild: Boolean): DiagTone = when (status) {
        "weak" -> if (isChild) DiagTone.WARN else DiagTone.BAD
        "watch" -> DiagTone.WARN
        "ok" -> DiagTone.GOOD
        else -> DiagTone.NEUTRAL
    }

    // ---------------------------------------------------------------- 逐条列表

    fun toggleExpanded(index: Int) {
        _state.update { it.copy(expandedIndex = if (it.expandedIndex == index) -1 else index) }
    }

    // ---------------------------------------------------------------- 运行态操作

    /** 「重录这句」：重置该句并跳回连读 Tab（返回 false = 运行态已不存在，页面直接返回）。 */
    fun redo(index: Int): Boolean {
        val run = FlowRunStore.current() ?: return false
        run.retryItem(index)
        return true
    }

    /** 「再读一遍」：同一批句子重置（round+1），不重新抽句。 */
    fun reread(): Boolean {
        val run = FlowRunStore.current() ?: return false
        run.reread()
        return true
    }

    /** 「再读一段」：清空本轮，回 setup。 */
    fun backToSetup(): Boolean {
        val run = FlowRunStore.current() ?: return false
        run.backToSetup()
        return true
    }

    // ---------------------------------------------------------------- 保存本次自定义文本

    fun setSaveTitle(title: String) {
        _state.update { it.copy(saveTitle = title) }
    }

    fun clearSaveError() {
        _state.update { it.copy(saveError = null) }
    }

    /** 💾 把这次读的自定义文本保存成书页（POST /materials，只存文字）。 */
    fun saveCustomPage() {
        val s = _state.value
        if (s.saveBusy || s.savedPageId.isNotEmpty()) return
        val text = s.customText.trim()
        if (text.isEmpty()) {
            _state.update { it.copy(saveError = UiError.of("bad_request", "还没有可保存的文字", false)) }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(saveBusy = true, saveError = null) }
            try {
                val title = s.saveTitle.trim().ifEmpty { "未命名书页" }
                val created = c.flow.createPage(title, text)
                _state.update { it.copy(saveBusy = false, savedPageId = created.id, savedPageTitle = title) }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(saveBusy = false, saveError = ui) }
            }
        }
    }

    // ---------------------------------------------------------------- 听鼓励语

    /**
     * 🔊 听鼓励语：中文 → 英文顺序播放；失败只提示文字照常看。
     * 第二轮：语速/英语音色统一走 `VoicePrefs.resolve(isChild)`（儿童强制 slow），
     * 中文句仍用内置中文音色（账号偏好是英语音色，不适合读中文）。
     */
    fun playEncouragement() {
        val s = _state.value
        val data = s.summary ?: return
        if (s.encPlaying) return
        val zh = encouragementZhText(data)
        val en = data.encouragement.en
        if (zh.isEmpty() && en.isEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(encPlaying = true, encError = "") }
            try {
                val choice = c.voicePrefs.resolve(s.isChild)
                if (zh.isNotEmpty()) {
                    playAndWait(c.practice.tts(zh, choice.rate, zhVoiceId(), "mp3"))
                }
                if (en.isNotEmpty()) {
                    playAndWait(c.practice.tts(en, choice.rate, choice.voice, "mp3"))
                }
            } catch (e: Throwable) {
                _state.update { it.copy(encError = "语音暂时不可用，文字照常看就行") }
            } finally {
                _state.update { it.copy(encPlaying = false) }
            }
        }
    }

    /** `playBytes` 没有完成回调：播放开始后等 `AudioController.playing` 变 false（带超时兜底）。 */
    private suspend fun playAndWait(bytes: ByteArray) {
        c.audio.playBytes(bytes, "flow_encouragement.wav")
        withTimeoutOrNull(PLAY_WAIT_TIMEOUT_MS) { c.audio.playing.first { !it } }
    }

    /** 中文音色：内置 9 音色里的默认中文女声（`core/audio/Voices.kt`；语速取 VoicePrefs）。 */
    private fun zhVoiceId(): String =
        Voices.ALL.firstOrNull { !it.isEnglish }?.id ?: "zh-CN-XiaoxiaoNeural"

    private companion object {
        /** 单段鼓励语播放最长等待（防止播放器异常导致按钮一直转圈）。 */
        const val PLAY_WAIT_TIMEOUT_MS = 60_000L
    }
}

/**
 * 汇总页 UI 状态。
 *
 * @property ready false = 进程内没有连读运行态（直接打开/进程被杀），页面展示空态并返回
 * @property summary 打开页面时构建的本轮快照（完成句数 / 平均分 / 最差句 / 鼓励语）
 * @property items 逐条列表（含失败原因与重录入口）
 * @property customText 本次「自己输入 / OCR / 书页正文」，为空时不展示保存卡片
 */
data class FlowSummaryUiState(
    val ready: Boolean = false,
    val isChild: Boolean = false,
    val summary: FlowSummaryData? = null,
    val items: List<FlowItem> = emptyList(),
    val expandedIndex: Int = -1,
    val diagLoading: Boolean = false,
    val diagError: String = "",
    val diagSummary: String = "",
    val diagChips: List<DiagChip> = emptyList(),
    val customText: String = "",
    val saveTitle: String = "",
    val saveBusy: Boolean = false,
    val saveError: UiError? = null,
    val savedPageId: String = "",
    val savedPageTitle: String = "",
    /** 本机「待补评分」队列总条数（含历史批次；>0 时汇总页显示去处理入口） */
    val pendingUploads: Int = 0,
    val encPlaying: Boolean = false,
    val encError: String = "",
)

package top.dreamsearch.englishcoach.ui.page.practice

import android.os.SystemClock
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.dreamsearch.englishcoach.core.audio.AudioController
import top.dreamsearch.englishcoach.core.audio.MicPermission
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.dto.AttemptResponseDto
import top.dreamsearch.englishcoach.core.net.dto.SentenceDto
import top.dreamsearch.englishcoach.core.util.FileUtil
import top.dreamsearch.englishcoach.ui.nav.NavParams
import java.io.File

/**
 * 跟读页状态（Tab 根页，对应 hos `viewmodel/PracticeVM.ets` + `pages/PracticePage.ets`）。
 *
 * 覆盖：
 * - 语料加载（**缓存优先**，先显示后刷新）、等级切换、诊断页带进来的 focus 过滤；
 * - 示范音（`PracticeService.tts` → `CacheStore.ttsFile` → `AudioController.playFile`）；
 * - 「跟我读」（播完停 250ms 自动开录）；
 * - 录音计时（0.6–60s，60s 自动停）；
 * - 同步提交（`PracticeService.evaluate`）+ 进度文案（按耗时切换，不显示假百分比）；
 * - 结果（总分/子项/逐词/纠错/语调/历史）、degraded 重试评测、429 额度提示；
 * - 单句历史（`attempts(100)` 过滤 sentence_id，逐条可回放）；练习游标（`AppPrefs`）。
 *
 * ROUND2 补齐（详见 `android/ROUND2_CONTRACT.md` §4）：
 * - ①结果区能力雷达（成人；values = scores 五项）→ 见 [buildResultUi]；
 * - ②全屏结果页（页内 overlay，`overlayVisible`，不新增路由）；
 * - ③历史逐条回放（`PracticeService.audioByUrl` → `AudioController.playBytes`）；
 * - ④左右滑动切句（页面 HorizontalPager → [onPageSettled]）；
 * - ⑤语音偏好统一走 `VoicePrefs.resolve(isChild)`（`AppGraph.container.voicePrefs`）；
 * - ⑥提交网络/5xx 失败 → `PendingUploadQueue.enqueue(...)` 入队待补评分。
 */
class PracticeViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(PracticeUiState())
    val state: StateFlow<PracticeUiState> = _state.asStateFlow()

    /** 记住「上一次失败的操作」，让错误条上的重试按钮能重试对应动作（照抄 hos PracticeAction）。 */
    private enum class LastAction { NONE, DEMO, FOLLOW, RECORD, RETRY_EVALUATE, PLAY_RECORDING }

    private var lastAction = LastAction.NONE

    private var loadJob: Job? = null
    private var demoJob: Job? = null
    private var submitJob: Job? = null
    private var followRecordJob: Job? = null
    private var recordTimerJob: Job? = null
    private var progressTimerJob: Job? = null

    /** 权限缺失时先申请，授权后自动开录（「跟我读」链路用）。 */
    private var pendingStartAfterPermission = false

    init {
        // 会话用量/儿童态：底部额度提示、是否禁用录音都依赖它
        viewModelScope.launch {
            c.session.state.collect { session ->
                _state.update {
                    it.copy(
                        isChild = session.isChild,
                        displayName = session.displayName,
                        minutesToday = session.minutesToday,
                        dailyLimitMinutes = session.dailyLimitMinutes,
                        remainingMinutes = session.remainingMinutes,
                        exceeded = session.exceeded,
                    )
                }
            }
        }
        val initialLevel = c.config.levelForCefr(c.session.state.value.cefrLevel)
        _state.update { it.copy(level = initialLevel) }
        // 普通进入（无跨页参数）→ 直接加载账号等级语料；有参数则由 syncFromNavParams 决定
        val hadNavParams = NavParams.practiceLevel != null ||
            NavParams.practiceFocus != null ||
            NavParams.practiceSentenceId != null
        syncFromNavParams()
        if (!hadNavParams) load(level = initialLevel)
    }

    // ------------------------------------------------------------------ 跨页参数 / 语料

    /**
     * 读取 [NavParams]（诊断页 focus、句子列表选句）并立即清空。
     * 页面在每次进入组合（`LaunchedEffect(Unit)`）时调用一次。
     */
    fun syncFromNavParams() {
        val navLevel = NavParams.practiceLevel
        val navFocus = NavParams.practiceFocus
        val navSentenceId = NavParams.practiceSentenceId
        NavParams.clearPractice()
        if (navLevel == null && navFocus == null && navSentenceId == null) return

        val level = navLevel?.uppercase()?.takeIf { it in PracticeLevels.ALL } ?: _state.value.level
        when {
            // 诊断页「专项练习」：按 focus 重新拉语料（可能同时指定句子）
            !navFocus.isNullOrEmpty() -> load(
                level = level,
                focus = navFocus,
                selectSentenceId = navSentenceId,
                force = true,
            )

            // 句子列表切了等级：按新等级重载并定位到选中句
            navLevel != null && level != _state.value.level -> load(
                level = level,
                focus = _state.value.focusToken,
                selectSentenceId = navSentenceId,
                force = true,
            )

            // 句子列表选了一句：直接在当前列表里定位（找不到再重载）
            !navSentenceId.isNullOrEmpty() -> selectSentenceById(navSentenceId)

            // 等级没变、也没有指定句（例如从列表返回但没选）：不打断当前状态
            else -> Unit
        }
    }

    /** 重新加载当前等级/专项（错误条 / 「↻ 换一批」）。 */
    fun reload() {
        if (_state.value.busy) return
        load(level = _state.value.level, focus = _state.value.focusToken, force = true)
    }

    /** 切换等级：重载该等级语料（后台刷新，缓存先显示）。录音/提交中不允许切（避免打断）。 */
    fun selectLevel(level: String) {
        if (level == _state.value.level || level !in PracticeLevels.ALL) return
        if (_state.value.busy) return
        load(level = level, focus = _state.value.focusToken)
    }

    /** 退出诊断页带来的专项练习，回到普通语料。 */
    fun clearFocus() {
        if (_state.value.focusToken.isEmpty() || _state.value.busy) return
        load(level = _state.value.level, focus = "", force = true)
    }

    /**
     * 加载语料（缓存优先）：
     * 1. 有缓存立即渲染（`loading=false, refreshing=true`），不整屏白；
     * 2. 再请求网络刷新并写缓存；
     * 3. 无缓存且网络失败 → 整页错误态（`sentences` 为空 + `error`）。
     */
    private fun load(
        level: String = _state.value.level,
        focus: String = _state.value.focusToken,
        selectSentenceId: String? = null,
        force: Boolean = false,
    ) {
        val isChild = c.session.isChild
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            // force = 跳过缓存直接请求（退出专项 / 「换一批」时避免先闪一屏旧数据）
            val cached = if (force) emptyList() else withContext(Dispatchers.IO) {
                readSentencesCache(c.cache, level, focus)
            }
            val hasCached = cached.isNotEmpty()
            _state.update {
                it.copy(
                    level = level,
                    focusToken = focus,
                    loading = !hasCached,
                    refreshing = hasCached,
                    error = null,
                    notice = null,
                )
            }
            if (hasCached) applySentences(cached, selectSentenceId, isChild)
            try {
                val list = c.practice.sentences(level, focus)
                withContext(Dispatchers.IO) { writeSentencesCache(c.cache, level, focus, list) }
                applySentences(list, selectSentenceId, isChild)
                _state.update { it.copy(loading = false, refreshing = false) }
                warmupNeighbors(list)
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                if (hasCached) {
                    // 有缓存：保留已显示的句子，只提示刷新失败（可重试）
                    _state.update { it.copy(loading = false, refreshing = false, error = ui) }
                } else {
                    _state.update {
                        it.copy(
                            loading = false,
                            refreshing = false,
                            error = ui,
                            sentences = emptyList(),
                            index = 0,
                        )
                    }
                }
            }
        }
    }

    /** 应用一份语料：按游标/指定句决定当前句，重置当前句的录音/结果状态。 */
    private fun applySentences(
        list: List<SentenceDto>,
        selectSentenceId: String?,
        isChild: Boolean,
    ) {
        val sentences = list.mapIndexed { i, dto -> dto.toPracticeUi(i, list.size, isChild) }
        val level = _state.value.level
        val focus = _state.value.focusToken
        val saved = c.prefs.getString(practiceCursorKey(level), "")
        val savedIndex = sentences.indexOfFirst { it.id == saved }
        val resumeIndex = if (focus.isEmpty() && selectSentenceId == null && savedIndex > 0) savedIndex else -1
        val selectedIndex = selectSentenceId
            ?.let { id -> sentences.indexOfFirst { it.id == id } }
            ?.takeIf { it >= 0 }
            ?: 0
        resetCurrentState()
        _state.update {
            it.copy(
                sentences = sentences,
                index = if (sentences.isEmpty()) 0 else selectedIndex,
                resumeIndex = resumeIndex,
            )
        }
        // 只有「句子列表指定句」才把游标记到指定句；普通加载/继续上次时不覆盖游标
        if (selectSentenceId != null) {
            sentences.getOrNull(selectedIndex)?.let { writeCursor(it.id) }
        }
    }

    /** 预热当前句与后续 5 句的示范音（fire-and-forget，失败静默）。 */
    private fun warmupNeighbors(list: List<SentenceDto>) {
        val start = _state.value.index.coerceIn(0, maxOf(0, list.size - 1))
        val texts = list.drop(start).take(WARMUP_COUNT).map { it.text }.filter { it.isNotEmpty() }
        if (texts.isEmpty()) return
        val rate = if (c.session.isChild) "slow" else "normal"
        viewModelScope.launch { runCatching { c.practice.warmup(texts, rate) } }
    }

    // ------------------------------------------------------------------ 切句

    /** 下一句（列表顺序）；到末尾提示「这一组读完啦」。 */
    fun nextSentence() {
        val s = _state.value
        if (s.busy) return
        if (s.index + 1 < s.sentences.size) {
            goTo(s.index + 1)
        } else if (s.sentences.isNotEmpty()) {
            val message = if (s.isChild) {
                "这一组读完啦 🌟 想再读一遍就点下面的按钮"
            } else {
                "这一组读完啦，可以换等级、去句子列表挑一句，或从第一句再读一遍"
            }
            _state.update { it.copy(notice = message) }
        }
    }

    /** 上一句。 */
    fun previousSentence() {
        val s = _state.value
        if (s.busy || s.index <= 0) return
        goTo(s.index - 1)
    }

    /**
     * 左右滑动（HorizontalPager）落定后同步当前句：
     * - 页码没变 → 什么都不做；
     * - 页码变了 → 走 [goTo]，会清空当前结果/历史并写练习游标。
     *   即「显示结果时滑动 = 关结果并翻到新句」，录音/提交中 Pager 已禁用滑动。
     */
    fun onPageSettled(page: Int) {
        val s = _state.value
        if (page == s.index || page !in s.sentences.indices) return
        goTo(page)
    }

    // ------------------------------------------------------------------ 全屏结果页（页内 overlay）

    /** 打开「完整结果」全屏页（没有结果时忽略）。 */
    fun openOverlay() {
        if (_state.value.result == null) return
        _state.update { it.copy(overlayVisible = true) }
    }

    /** 关闭全屏结果页（返回键 / 顶部关闭 / 下一句时都会调）。 */
    fun closeOverlay() {
        _state.update { it.copy(overlayVisible = false) }
    }

    /** 句子列表点选后回来：切到指定句（找不到时重载一次再定位）。 */
    private fun selectSentenceById(sentenceId: String) {
        val index = _state.value.sentences.indexOfFirst { it.id == sentenceId }
        if (index >= 0) goTo(index) else load(selectSentenceId = sentenceId, force = true)
    }

    private fun goTo(index: Int) {
        val s = _state.value
        if (index !in s.sentences.indices) return
        if (s.recording || s.submitting) return
        resetCurrentState()
        _state.update { it.copy(index = index, resumeIndex = -1, notice = null) }
        writeCursor(s.sentences[index].id)
    }

    /** 「继续上次」横幅：跳到上次那句。 */
    fun resumeFromBanner() {
        val index = _state.value.resumeIndex
        if (index in _state.value.sentences.indices) goTo(index)
        _state.update { it.copy(resumeIndex = -1) }
    }

    /** 「从头开始」：清掉该等级游标，回到第一句。 */
    fun startFromBeginning() {
        val s = _state.value
        c.prefs.putString(practiceCursorKey(s.level), "")
        _state.update { it.copy(resumeIndex = -1) }
        goTo(0)
    }

    /** 记住「每等级上次读到哪句」；专项练习不污染游标。 */
    private fun writeCursor(sentenceId: String) {
        if (sentenceId.isEmpty()) return
        if (_state.value.focusToken.isNotEmpty()) return
        c.prefs.putString(practiceCursorKey(_state.value.level), sentenceId)
    }

    // ------------------------------------------------------------------ 示范音 / 回放

    /**
     * 听示范。`autoRecord = true` 时播完停 250ms 自动开录（「跟我读」）。
     * 重复点：先停当前播放再播（契约 §5 / screens.md §3 交互 4）。
     */
    fun playDemo(autoRecord: Boolean) {
        val s = _state.value
        val sentence = s.current ?: return
        if (s.submitting || s.recording || s.preparing) return
        if (s.limitReached && autoRecord) return
        lastAction = if (autoRecord) LastAction.FOLLOW else LastAction.DEMO
        demoJob?.cancel()
        followRecordJob?.cancel()
        c.audio.stopPlayback()
        demoJob = viewModelScope.launch {
            _state.update {
                it.copy(
                    ttsLoading = true,
                    playing = false,
                    playingRecording = false,
                    playingHistoryId = "",
                    error = null,
                )
            }
            try {
                // 语音偏好统一入口：儿童强制 slow/内置童声，成人用账号偏好（ROUND2 §1.2）
                val voiceChoice = c.voicePrefs.resolve(c.session.isChild)
                val rate = voiceChoice.rate
                val voice = voiceChoice.voice
                val file = c.cache.ttsFile("demo_${sentence.id}_${rate}_${voice ?: "default"}")
                val cached = withContext(Dispatchers.IO) { FileUtil.readBytes(file) }
                if (cached == null || cached.size <= MIN_AUDIO_BYTES) {
                    // 服务返回的是音频字节：先落 CacheStore（成功后重复播放不再走网络）
                    val bytes = c.practice.tts(text = sentence.text, rate = rate, voice = voice)
                    withContext(Dispatchers.IO) { FileUtil.writeBytesAtomic(file, bytes) }
                }
                playDemoFile(file, autoRecord)
            } catch (e: Throwable) {
                _state.update {
                    it.copy(ttsLoading = false, playing = false, error = c.session.toUiError(e))
                }
            }
        }
    }

    private fun playDemoFile(file: File, autoRecord: Boolean) {
        try {
            _state.update { it.copy(ttsLoading = false, playing = true) }
            c.audio.playFile(file) {
                _state.update { it.copy(playing = false) }
                if (autoRecord) scheduleAutoRecord()
            }
        } catch (e: Throwable) {
            _state.update { it.copy(ttsLoading = false, playing = false, error = c.session.toUiError(e)) }
        }
    }

    /** 「跟我读」：示范播完停 200–300ms 再自动开录（照抄 hos 的 250ms）。 */
    private fun scheduleAutoRecord() {
        followRecordJob?.cancel()
        followRecordJob = viewModelScope.launch {
            delay(AUTO_RECORD_DELAY_MS)
            startRecording()
        }
    }

    /** 回放本次录音（`GET /audio/:attemptId`，落盘缓存后播放）。 */
    fun playRecording() {
        val s = _state.value
        val attemptId = s.result?.attemptId ?: s.retryAttemptId
        if (attemptId.isEmpty() || s.recording || s.submitting) return
        lastAction = LastAction.PLAY_RECORDING
        c.audio.stopPlayback()
        viewModelScope.launch {
            try {
                _state.update {
                    it.copy(
                        playingRecording = true,
                        playing = false,
                        ttsLoading = false,
                        playingHistoryId = "",
                        error = null,
                    )
                }
                val file = c.cache.audioFile("rec_$attemptId", "m4a")
                if (withContext(Dispatchers.IO) { FileUtil.readBytes(file) } == null) {
                    val bytes = c.practice.audio(attemptId)
                    withContext(Dispatchers.IO) { FileUtil.writeBytesAtomic(file, bytes) }
                }
                c.audio.playFile(file) { _state.update { it.copy(playingRecording = false) } }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(playingRecording = false, error = c.session.toUiError(e))
                }
            }
        }
    }

    /**
     * 单句历史逐条回放（ROUND2 §1.5 `PracticeService.audioByUrl`）：
     * 用 `AttemptItemDto.audioUrl` 下载录音字节 → `AudioController.playBytes`。
     * 历史没有 audioUrl 的条目不调用（UI 也不显示「回放」）；儿童保留回放（不看分数）。
     */
    fun playHistoryAudio(item: HistoryItemUi) {
        val s = _state.value
        if (item.audioUrl.isEmpty() || s.recording || s.preparing) return
        if (s.playingHistoryId == item.attemptId) return
        c.audio.stopPlayback()
        viewModelScope.launch {
            try {
                _state.update {
                    it.copy(
                        playingHistoryId = item.attemptId,
                        playing = false,
                        playingRecording = false,
                        ttsLoading = false,
                        error = null,
                    )
                }
                val bytes = c.practice.audioByUrl(item.audioUrl)
                c.audio.playBytes(bytes, "history_${item.attemptId}.m4a")
                // playBytes 无 onComplete：等引擎播放态落回 false（播完/被停都会清标记）
                c.audio.playing.first { !it }
                _state.update { it.copy(playingHistoryId = "") }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(playingHistoryId = "", error = c.session.toUiError(e))
                }
            }
        }
    }

    // ------------------------------------------------------------------ 录音

    /**
     * 开始录音。首次调用若没有麦克风权限，会置 `micPermissionRequest=true`，
     * 由页面用 `rememberMicPermission()` 申请；授权后页面回调 [onMicPermissionGranted]。
     */
    fun startRecording() {
        val s = _state.value
        if (s.current == null || s.recording || s.preparing || s.submitting) return
        if (s.limitReached) {
            _state.update {
                it.copy(error = UiError.of(ApiErrorCode.DAILY_LIMIT_REACHED, quotaMessage(it), false))
            }
            return
        }
        if (!MicPermission.isGranted(c.appContextRef)) {
            pendingStartAfterPermission = true
            _state.update { it.copy(micPermissionRequest = true) }
            return
        }
        pendingStartAfterPermission = false
        lastAction = LastAction.RECORD
        // 录音引擎会先停播放（蓝牙铁律）：这里同步清掉播放态，避免 UI 残留「播放中」
        followRecordJob?.cancel()
        demoJob?.cancel()
        _state.update {
            it.copy(
                preparing = true,
                error = null,
                playing = false,
                ttsLoading = false,
                playingRecording = false,
                playingHistoryId = "",
                overlayVisible = false,
            )
        }
        viewModelScope.launch {
            try {
                c.audio.startRecording("practice")
                _state.update {
                    it.copy(preparing = false, recording = true, elapsedMs = 0L, error = null)
                }
                startRecordTimer()
            } catch (e: Throwable) {
                _state.update {
                    it.copy(preparing = false, recording = false, error = c.session.toUiError(e))
                }
            }
        }
    }

    /** 页面已拉起权限申请（清掉一次性标记，避免重复弹框）。 */
    fun onMicRequestLaunched() {
        _state.update { it.copy(micPermissionRequest = false) }
    }

    /** 权限结果回调：用户授权后，如果是因为点录音触发的，直接开始录。 */
    fun onMicPermissionGranted() {
        if (!MicPermission.isGranted(c.appContextRef)) return
        if (pendingStartAfterPermission) {
            pendingStartAfterPermission = false
            startRecording()
        }
    }

    /** 说完啦：停止录音 → 校验时长（引擎内 0.6–60s）→ 上传评测。 */
    fun stopRecordingAndSubmit() {
        if (!_state.value.recording) return
        stopRecordTimer()
        _state.update { it.copy(recording = false) }
        viewModelScope.launch {
            val recorded = try {
                c.audio.stopRecording()
            } catch (e: Throwable) {
                _state.update {
                    it.copy(elapsedMs = 0L, error = c.session.toUiError(e))
                }
                return@launch
            }
            submit(recorded.file, recorded.durationMs)
        }
    }

    /** 「不要了」：丢弃录音，不提交。 */
    fun cancelRecording() {
        stopRecordTimer()
        runCatching { c.audio.cancelRecording() }
        _state.update { it.copy(recording = false, elapsedMs = 0L) }
    }

    private fun startRecordTimer() {
        stopRecordTimer()
        val startedAt = SystemClock.elapsedRealtime()
        recordTimerJob = viewModelScope.launch {
            while (isActive) {
                delay(RECORD_TICK_MS)
                val elapsed = SystemClock.elapsedRealtime() - startedAt
                _state.update { it.copy(elapsedMs = elapsed) }
                if (elapsed >= AudioController.MAX_DURATION_MS) {
                    // 60s 上限：页面计时器到点自动提交（CONTRACT §4.1）
                    stopRecordingAndSubmit()
                    break
                }
            }
        }
    }

    private fun stopRecordTimer() {
        recordTimerJob?.cancel()
        recordTimerJob = null
    }

    // ------------------------------------------------------------------ 提交 / 结果

    /**
     * 同步提交：`PracticeService.evaluate(...)`（multipart，最长约 100s）。
     * - 进度文案按耗时切换：上传录音… → 识别中… → 评分中… → 生成建议…（不显示假百分比）；
     * - 成功：`session.updateUsage(resp.usage)`（有 usage 时）→ 应用结果 → 拉取单句历史；
     * - 失败：4xx 业务错误展示 `UiError`；**网络/5xx** 且本地有录音时自动进
     *   [PendingUploadQueue][top.dreamsearch.englishcoach.core.offline.PendingUploadQueue]
     *   待补评分（离线能力），并提示用户去补评分页。
     */
    private suspend fun submit(file: File, durationMs: Long) {
        val sentence = _state.value.current ?: return
        val audio = withContext(Dispatchers.IO) { FileUtil.readBytes(file) }
        if (audio == null || audio.isEmpty()) {
            _state.update {
                it.copy(
                    error = c.session.toUiError(
                        ApiError.local(ApiErrorCode.RECORD_FAILED, "录音文件为空")
                    )
                )
            }
            return
        }
        submitJob?.cancel()
        submitJob = viewModelScope.launch {
            lastAction = LastAction.RECORD
            _state.update {
                it.copy(
                    submitting = true,
                    error = null,
                    result = null,
                    degradedNotice = null,
                    canRetryEvaluate = false,
                    pendingSaved = false,
                    pendingNotice = null,
                    overlayVisible = false,
                    progressText = PROGRESS_UPLOADING,
                )
            }
            startProgressTimer()
            try {
                val resp = c.practice.evaluate(
                    audio = audio,
                    sentenceId = sentence.id,
                    referenceText = sentence.text,
                    durationMs = durationMs.toInt(),
                )
                resp.usage?.let { c.session.updateUsage(it) }
                applyAttempt(resp)
                // 上传成功后删本地录音（回放走 /audio/:id），避免占满 recordings 目录
                runCatching { file.delete() }
                loadHistory()
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                // 只有「今日额度用完」才禁用录音；too_many_requests 是瞬时限流，允许稍后重试
                val quotaLimited = ui.code == ApiErrorCode.DAILY_LIMIT_REACHED
                // 离线能力（ROUND2 §1.3）：网络错误（status=0）或 5xx 且本地有录音 → 入队待补评分。
                // 4xx 业务错误（额度/参数/权限…）重发也不会成功，不入队，直接展示错误。
                val offlineFailure = e is ApiError && (e.status == 0 || e.status >= 500)
                val enqueued = offlineFailure && withContext(Dispatchers.IO) {
                    runCatching {
                        c.pendingUploads.enqueue(
                            audioFile = file,
                            sentenceId = sentence.id,
                            referenceText = sentence.text,
                            durationMs = durationMs.toInt(),
                        )
                    }.getOrDefault(false)
                }
                if (enqueued) {
                    // 队列已拷贝一份录音：原文件可删，避免占满 recordings 目录
                    runCatching { file.delete() }
                    _state.update {
                        it.copy(
                            error = null,
                            pendingSaved = true,
                            pendingNotice = if (it.isChild) {
                                "录音先存在手机里啦，等网络好了再补评分"
                            } else {
                                "录音已保存到本机，稍后可在「待补评分」里补评分"
                            },
                            quotaReached = quotaLimited || it.quotaReached,
                            quotaText = if (quotaLimited) ui.message else it.quotaText,
                        )
                    }
                } else {
                    _state.update {
                        it.copy(
                            error = ui,
                            quotaReached = quotaLimited || it.quotaReached,
                            quotaText = if (quotaLimited) ui.message else it.quotaText,
                        )
                    }
                }
            } finally {
                stopProgressTimer()
                _state.update { it.copy(submitting = false, progressText = "") }
            }
        }
    }

    /** degraded 时用已存录音重评（`retryAttempt`，不重录、不重复上传）。 */
    fun retryEvaluate() {
        val attemptId = _state.value.retryAttemptId
        if (attemptId.isEmpty() || _state.value.submitting) return
        submitJob?.cancel()
        submitJob = viewModelScope.launch {
            lastAction = LastAction.RETRY_EVALUATE
            _state.update {
                it.copy(
                    submitting = true,
                    error = null,
                    progressText = PROGRESS_RETRY,
                    degradedNotice = null,
                )
            }
            startProgressTimer()
            try {
                val resp = c.practice.retryAttempt(attemptId)
                resp.usage?.let { c.session.updateUsage(it) }
                applyAttempt(resp)
                loadHistory()
            } catch (e: Throwable) {
                _state.update { it.copy(error = c.session.toUiErrorAsync(e)) }
            } finally {
                stopProgressTimer()
                _state.update { it.copy(submitting = false, progressText = "") }
            }
        }
    }

    private fun applyAttempt(resp: AttemptResponseDto) {
        val isChild = c.session.isChild
        val result = buildResultUi(resp, isChild)
        if (result == null) {
            // degraded / 无结果：录音已保存，给「重试评测」
            val message = when {
                isChild -> "录音先存好啦，等评分老师有空再打分"
                resp.message.isNotEmpty() -> resp.message
                else -> "录音已保存，评测服务暂时不可用，稍后可重试"
            }
            _state.update {
                it.copy(
                    result = null,
                    degradedNotice = message,
                    canRetryEvaluate = resp.degraded,
                    retryAttemptId = resp.attemptId,
                    quotaReached = false,
                    quotaText = null,
                    pendingSaved = false,
                    pendingNotice = null,
                    overlayVisible = false,
                )
            }
            return
        }
        _state.update {
            it.copy(
                result = result,
                canRetryEvaluate = resp.degraded,
                retryAttemptId = resp.attemptId,
                degradedNotice = if (resp.degraded) {
                    "评分服务刚刚不稳定，这条结果是降级结果，可以点「重试评测」"
                } else {
                    null
                },
                quotaReached = false,
                quotaText = null,
                pendingSaved = false,
                pendingNotice = null,
                error = null,
            )
        }
    }

    /** 结果进度文案：按耗时切换（0–2s 上传、2–8s 识别、8–20s 评分、>20s 生成建议）。 */
    private fun startProgressTimer() {
        stopProgressTimer()
        val startedAt = SystemClock.elapsedRealtime()
        progressTimerJob = viewModelScope.launch {
            while (isActive) {
                delay(PROGRESS_TICK_MS)
                val elapsed = SystemClock.elapsedRealtime() - startedAt
                val text = when {
                    elapsed > 20_000L -> PROGRESS_FEEDBACK
                    elapsed > 8_000L -> PROGRESS_SCORING
                    elapsed > 2_000L -> PROGRESS_RECOGNIZING
                    else -> PROGRESS_UPLOADING
                }
                _state.update { it.copy(progressText = text) }
            }
        }
    }

    private fun stopProgressTimer() {
        progressTimerJob?.cancel()
        progressTimerJob = null
    }

    // ------------------------------------------------------------------ 单句历史

    /** 手动刷新这一句的历史（成人看趋势，儿童只看逐条回放）。 */
    fun refreshHistory() {
        viewModelScope.launch { loadHistory() }
    }

    /**
     * 单句历史：线上没有 `/sentences/:id/attempts`，用 `attempts(limit)` 过滤 `sentence_id`。
     * 儿童同样加载（保留逐条回放），但结果里分数置 null、不展示趋势（见 [buildHistoryUi]）。
     * 历史只是附加信息，失败静默（不覆盖主流程错误）。
     */
    private suspend fun loadHistory() {
        val sentence = _state.value.current ?: return
        val isChild = c.session.isChild
        _state.update { it.copy(historyLoading = true) }
        try {
            val items = c.practice.attempts(HISTORY_FETCH_LIMIT)
            _state.update {
                it.copy(
                    history = buildHistoryUi(items, sentence.id, isChild),
                    historyLoading = false,
                )
            }
        } catch (ignored: Throwable) {
            _state.update { it.copy(historyLoading = false) }
        }
    }

    // ------------------------------------------------------------------ 错误 / 生命周期

    /** 错误条上的动作：按最后一次操作重试；麦克风被拒时去申请/去设置。 */
    fun onErrorAction() {
        val s = _state.value
        if (s.error?.code == ApiErrorCode.MIC_DENIED) {
            pendingStartAfterPermission = true
            _state.update { it.copy(error = null, micPermissionRequest = true) }
            return
        }
        if (s.canRetryEvaluate) {
            retryEvaluate()
            return
        }
        val action = lastAction
        _state.update { it.copy(error = null) }
        when (action) {
            LastAction.DEMO -> playDemo(false)
            LastAction.FOLLOW -> playDemo(true)
            LastAction.PLAY_RECORDING -> playRecording()
            else -> Unit
        }
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }

    fun dismissNotice() {
        _state.update { it.copy(notice = null) }
    }

    /** 页面离开组合（切 Tab / push 二级页）时调用：停录音、停播放、停计时（照抄 hos aboutToDisappear）。 */
    fun onLeaveUi() {
        if (_state.value.recording) cancelRecording()
        stopRecordTimer()
        stopProgressTimer()
        followRecordJob?.cancel()
        demoJob?.cancel()
        c.audio.stopPlayback()
        _state.update {
            it.copy(
                playing = false,
                ttsLoading = false,
                playingRecording = false,
                playingHistoryId = "",
                preparing = false,
            )
        }
    }

    override fun onCleared() {
        stopRecordTimer()
        stopProgressTimer()
        loadJob?.cancel()
        demoJob?.cancel()
        submitJob?.cancel()
        followRecordJob?.cancel()
        runCatching { c.audio.release() }
        super.onCleared()
    }

    /** 重置当前句的录音/结果/历史展示状态（切句、换等级时）。 */
    private fun resetCurrentState() {
        stopRecordTimer()
        stopProgressTimer()
        followRecordJob?.cancel()
        demoJob?.cancel()
        c.audio.stopPlayback()
        _state.update {
            it.copy(
                result = null,
                history = null,
                historyLoading = false,
                degradedNotice = null,
                canRetryEvaluate = false,
                retryAttemptId = "",
                playing = false,
                ttsLoading = false,
                playingRecording = false,
                playingHistoryId = "",
                recording = false,
                preparing = false,
                submitting = false,
                progressText = "",
                elapsedMs = 0L,
                error = null,
                notice = null,
                overlayVisible = false,
                pendingSaved = false,
                pendingNotice = null,
            )
        }
    }

    private fun quotaMessage(s: PracticeUiState): String = when {
        s.isChild -> "今天已经练得很棒啦，明天再来 🌙"
        s.remainingMinutes > 0 -> "今天的练习时间用完了（剩余 ${s.remainingMinutes} 分钟），明天再来吧"
        else -> "今天的练习时长已达上限，明天再来"
    }

    companion object {
        private const val AUTO_RECORD_DELAY_MS = 250L
        private const val RECORD_TICK_MS = 200L
        private const val PROGRESS_TICK_MS = 500L
        private const val HISTORY_FETCH_LIMIT = 100
        private const val WARMUP_COUNT = 6
        private const val MIN_AUDIO_BYTES = 64

        private const val PROGRESS_UPLOADING = "上传录音…"
        private const val PROGRESS_RECOGNIZING = "识别中…"
        private const val PROGRESS_SCORING = "评分中…"
        private const val PROGRESS_FEEDBACK = "生成建议…"
        private const val PROGRESS_RETRY = "重新评测…"
    }
}

/**
 * 跟读页完整 UI 状态（单卡片流：一次一句）。
 *
 * 页面只渲染这里的数据；业务动作都走 ViewModel 方法。
 */
data class PracticeUiState(
    // ---- 加载 / 错误
    val loading: Boolean = true,
    /** 有缓存先显示、后台刷新中（顶部细提示，不阻塞交互） */
    val refreshing: Boolean = false,
    val error: UiError? = null,

    // ---- 会话（儿童规则 / 今日用量 / 额度）
    val isChild: Boolean = false,
    val displayName: String = "",
    val minutesToday: Int = 0,
    val dailyLimitMinutes: Int = 20,
    val remainingMinutes: Int = 0,
    val exceeded: Boolean = false,

    // ---- 语料
    val level: String = "A1",
    val levels: List<String> = PracticeLevels.ALL,
    /** 诊断页带进来的 focus 音素（空 = 普通练习） */
    val focusToken: String = "",
    val sentences: List<PracticeSentenceUi> = emptyList(),
    val index: Int = 0,
    /** 上次练到的句子下标（>0 时显示「继续上次」横幅） */
    val resumeIndex: Int = -1,
    /** 轻提示（读完一组 / 换批结果等） */
    val notice: String? = null,

    // ---- 额度（429 / daily_limit_reached）
    val quotaReached: Boolean = false,
    val quotaText: String? = null,

    // ---- 音频 / 录音状态
    val ttsLoading: Boolean = false,
    val playing: Boolean = false,
    val preparing: Boolean = false,
    val recording: Boolean = false,
    val elapsedMs: Long = 0L,
    val submitting: Boolean = false,
    val progressText: String = "",

    // ---- 结果
    val result: PracticeResultUi? = null,
    val history: HistoryUi? = null,
    val historyLoading: Boolean = false,
    /** degraded / 无结果时的提示（录音已保存…） */
    val degradedNotice: String? = null,
    val canRetryEvaluate: Boolean = false,
    val retryAttemptId: String = "",
    val playingRecording: Boolean = false,
    /** 正在回放的历史记录 attempt id（空 = 无）；用于「▶ 回放 / 播放中…」切换 */
    val playingHistoryId: String = "",
    /** 全屏结果页（页内 overlay，不新增路由）是否打开 */
    val overlayVisible: Boolean = false,

    // ---- 离线能力：提交失败入队（ROUND2 §1.3）
    /** 本次提交已入队待补评分 */
    val pendingSaved: Boolean = false,
    /** 入队提示文案（页面展示 + 「去补评分」入口） */
    val pendingNotice: String? = null,

    // ---- 权限（页面观察到 true 时拉起 rememberMicPermission().request()）
    val micPermissionRequest: Boolean = false,
) {
    val current: PracticeSentenceUi? get() = sentences.getOrNull(index)

    val total: Int get() = sentences.size

    /** 录音/提交中：按钮禁用、禁止切句与切等级。 */
    val busy: Boolean get() = submitting || preparing || recording

    /** 今日额度用完（会话 exceeded 或本次提交被 429 拒绝）：禁用录音。 */
    val limitReached: Boolean get() = exceeded || quotaReached
}

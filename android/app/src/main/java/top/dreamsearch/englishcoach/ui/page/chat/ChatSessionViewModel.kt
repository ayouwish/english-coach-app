package top.dreamsearch.englishcoach.ui.page.chat

import android.os.SystemClock
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import top.dreamsearch.englishcoach.core.audio.AudioController
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.dto.ChatMessageDto
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioDto
import top.dreamsearch.englishcoach.core.net.dto.ChatSessionDto
import top.dreamsearch.englishcoach.core.net.dto.ChatTurnDto
import top.dreamsearch.englishcoach.core.util.FileUtil
import top.dreamsearch.englishcoach.ui.nav.NavParams
import java.io.File

/**
 * 对话会话页 / 历史详情页 ViewModel（两页共用，对应 hos `ChatVM` 的两种初始化模式）。
 *
 * 数据来源：
 * - 实时会话：[ChatSessionHandoff]（`POST /chat/sessions` 响应）+ `POST /asr` → `POST /turn` → `POST /tts`；
 * - 历史详情：`GET /chat/sessions/:id`（meta）+ `GET /:id/messages`（含 pron/correction）；
 * - pron 补分：**4 次**轮询 `GET /chat/sessions/:id/messages`（turn 响应不含分数）；
 * - 整段回放：`GET /:id/audio/status` → `GET /:id/audio`（202 = 构建中，返回 null 再轮询）。
 *
 * 硬性交互（任务要求）：
 * 1. 进入会话先显示开场白并朗读（可点「再听」）；
 * 2. 一轮 = 录音（0.6–60s）→ ASR → **显示识别文本，用户点「重说/发送」才提交** → turn →
 *    文本先渲染 → TTS 播放回复（失败不影响文字）→ 轮询补 pron；
 * 3. 用户气泡可回放（本地文件优先，其次 `ChatService.messageAudio(audioUrl)`）；
 * 4. 建议回复 chips 点击**只朗读、不发送**；
 * 5. 一轮未完成禁用录音、不允许并发 turn；
 * 6. 结束（手动或 done=true）→ `POST /:id/end` → 结束卡 + 整段回放。
 */
data class ChatSessionUiState(
    val sessionId: String = "",
    val scenarioId: String = "",
    val titleEn: String = "",
    val titleZh: String = "",
    val settingZh: String = "",
    val level: String = "",
    val isChild: Boolean = false,
    /** 历史详情（只读：不录音、不结束） */
    val readOnly: Boolean = false,
    val turnCount: Int = 0,
    val startedAt: String = "",
    val endedAt: String = "",
    val messages: List<ChatMessageUi> = emptyList(),

    // 加载
    val loading: Boolean = true,
    val loadError: UiError? = null,

    // 录音 / 一轮
    val busy: Boolean = false,
    val progressText: String = "",
    val preparing: Boolean = false,
    val recording: Boolean = false,
    val elapsedMs: Long = 0L,
    /** ASR 识别结果：非空时页面展示「重说 / 发送」，不自动发送 */
    val pendingText: String = "",
    val ending: Boolean = false,
    val ended: Boolean = false,
    val done: Boolean = false,
    val degradedLlm: Boolean = false,
    val degraded: Boolean = false,
    val quotaExceeded: Boolean = false,
    val quotaText: String = "",

    // 建议回复 / 提示句
    val suggestedReplies: List<String> = emptyList(),
    val hintText: String = "",
    val voiceNotice: String = "",

    // 错误（error + retryAction 决定「重试」做什么）
    val error: UiError? = null,
    val retryAction: ChatRetryAction = ChatRetryAction.NONE,

    // 整段回放
    val replayStatus: ChatReplayStatus = ChatReplayStatus.IDLE,
    val replayError: String = "",
    val replayPlaying: Boolean = false,
    val replayDurationMs: Long = 0L,

    // 全局会话（限额 / 儿童）
    val sessionExceeded: Boolean = false,
    val remainingMinutes: Int = 0,

    // TTS 偏好
    val ttsRate: String = "normal",
    val ttsVoice: String = "",
    val autoRead: Boolean = true,
) {
    /**
     * 是否允许点录音按钮：
     * - 一轮未完成（识别/回复中）或已有待确认识别结果时不允许「开始新录音」；
     * - 录音中允许点（用于「说完啦」停止）。
     */
    val canRecord: Boolean
        get() = !busy && !preparing && !ending && !ended &&
            !quotaExceeded && !sessionExceeded && pendingText.isEmpty()
}

class ChatSessionViewModel(
    private val c: AppContainer,
    private val mode: Mode = Mode.LIVE,
) : ViewModel() {

    enum class Mode { LIVE, HISTORY }

    private val _state = MutableStateFlow(ChatSessionUiState())
    val state: StateFlow<ChatSessionUiState> = _state.asStateFlow()

    private var recordTimer: Job? = null
    private var progressTimer: Job? = null
    private var pronPollJob: Job? = null
    private var replayTimer: Job? = null
    private var recordStartedAtElapsed: Long = 0L
    private var replayTries: Int = 0
    private var replayFile: File? = null

    private val ttsCache = HashMap<String, ByteArray>()
    private val userAudioCache = HashMap<String, File>()
    private var pendingRecording: RecordingHolder? = null
    private var pendingTurn: PendingTurn? = null
    private var lastFailedPlayId: String = ""

    private data class RecordingHolder(val file: File, val durationMs: Long)
    private data class PendingTurn(val text: String, val file: File, val userMsgId: String)

    init {
        val session = c.session.state.value
        val prefs = ChatVoicePrefs.load(c.prefs, session.isChild)
        _state.update {
            it.copy(
                isChild = session.isChild,
                autoRead = prefs.autoRead,
                ttsRate = prefs.rate,
                ttsVoice = prefs.voice,
                sessionExceeded = session.exceeded,
                remainingMinutes = session.remainingMinutes,
            )
        }
        viewModelScope.launch {
            c.session.state.collect { s ->
                _state.update {
                    it.copy(
                        isChild = s.isChild,
                        sessionExceeded = s.exceeded,
                        remainingMinutes = s.remainingMinutes,
                    )
                }
            }
        }
        if (mode == Mode.LIVE) initLiveFromNav() else initHistoryFromNav()
    }

    // ------------------------------------------------------------------ 初始化

    /** 实时会话：从 `NavParams.chatSessionId` + 内存交接数据启动；取不到就退化为只读重看。 */
    private fun initLiveFromNav() {
        val sessionId = NavParams.chatSessionId.orEmpty()
        NavParams.chatSessionId = null
        if (sessionId.isEmpty()) {
            _state.update {
                it.copy(
                    loading = false,
                    loadError = UiError(
                        message = "会话信息不见了，返回重新选一个场景开始吧",
                        actionLabel = "返回",
                        retryable = false,
                        code = "chat_session_missing",
                    ),
                )
            }
            return
        }
        val handoff = ChatSessionHandoff.take(sessionId)
        if (handoff != null) {
            initLive(handoff.session, handoff.scenario)
        } else {
            // 进程内没拿到开会话数据（热重载/异常）：退化成只读重看，避免空白页（同 hos）
            initHistory(sessionId)
        }
    }

    /** 历史详情：从 `NavParams.chatDetailId` 启动。 */
    private fun initHistoryFromNav() {
        val sessionId = NavParams.chatDetailId.orEmpty()
        NavParams.chatDetailId = null
        if (sessionId.isEmpty()) {
            _state.update {
                it.copy(
                    loading = false,
                    loadError = UiError(
                        message = "没有拿到这次对话的 ID，返回历史列表重新点一次吧",
                        actionLabel = "返回",
                        retryable = false,
                        code = "chat_detail_missing",
                    ),
                )
            }
            return
        }
        initHistory(sessionId)
    }

    /** 实时会话初始化：开场白立即显示（并自动朗读，可点「再听」）。 */
    private fun initLive(session: ChatSessionDto, handoffScenario: ChatScenarioDto?) {
        val scenario = session.scenario ?: handoffScenario
        val opening = openingLineOf(session, scenario)
        val openingMsg = openingNode(opening)
        _state.update {
            it.copy(
                sessionId = session.sessionId,
                scenarioId = scenario?.id.orEmpty(),
                titleEn = scenario?.title.orEmpty(),
                titleZh = scenario?.titleZh.orEmpty(),
                settingZh = scenario?.settingZh.orEmpty(),
                level = scenario?.level.orEmpty(),
                turnCount = session.turnCount,
                messages = listOfNotNull(openingMsg),
                loading = false,
                loadError = null,
                readOnly = false,
            )
        }
        if (openingMsg != null && _state.value.autoRead) playMessage(openingMsg.id)
    }

    /** 历史详情初始化：meta 失败不阻塞消息列表（同 hos）。 */
    fun initHistory(sessionId: String) {
        _state.update {
            it.copy(
                sessionId = sessionId,
                readOnly = true,
                ended = true,
                loading = true,
                loadError = null,
                messages = emptyList(),
            )
        }
        viewModelScope.launch {
            try {
                val meta = try {
                    c.chat.sessionDetail(sessionId)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    null
                }
                if (meta != null) {
                    _state.update {
                        it.copy(
                            scenarioId = meta.scenarioId,
                            titleEn = it.titleEn.ifEmpty { meta.scenarioTitle },
                            titleZh = it.titleZh.ifEmpty { meta.scenarioTitleZh },
                            turnCount = meta.turnCount,
                            startedAt = meta.startedAt,
                            endedAt = meta.endedAt.orEmpty(),
                        )
                    }
                }
                val list = c.chat.messages(sessionId)
                val isChild = _state.value.isChild
                _state.update {
                    it.copy(
                        messages = list.map { dto -> ChatMsgFactory.fromDto(dto, isChild) },
                        loading = false,
                        loadError = null,
                    )
                }
                beginReplay()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update {
                    it.copy(
                        loading = false,
                        loadError = ui.copy(actionLabel = "重试", retryable = true),
                    )
                }
            }
        }
    }

    /** 加载失败后的重试：重新拉历史线程；实时会话取不到数据时由页面返回。 */
    fun reloadThread() {
        val sessionId = _state.value.sessionId
        if (sessionId.isEmpty()) return
        initHistory(sessionId)
    }

    // ------------------------------------------------------------------ 录音

    fun startRecording() {
        val snapshot = _state.value
        if (snapshot.recording) return
        if (!snapshot.canRecord) return
        if (snapshot.pendingText.isNotEmpty()) return
        clearError()
        discardPendingRecording()
        _state.update { it.copy(preparing = true, voiceNotice = "") }
        try {
            c.audio.startRecording("chat")
        } catch (e: Throwable) {
            _state.update { it.copy(preparing = false) }
            handleError(e, ChatRetryAction.RECORD)
            return
        }
        recordStartedAtElapsed = SystemClock.elapsedRealtime()
        _state.update { it.copy(preparing = false, recording = true, elapsedMs = 0L) }
        startRecordTimer()
    }

    /** 点录音按钮结束：停录 → ASR（识别文本不自动发送）。 */
    fun stopAndRecognize() {
        if (!_state.value.recording) return
        recordTimer?.cancel()
        recordTimer = null
        _state.update { it.copy(recording = false, elapsedMs = 0L) }
        val result = try {
            c.audio.stopRecording()
        } catch (e: Throwable) {
            handleError(e, ChatRetryAction.RECORD)
            return
        }
        recognize(RecordingHolder(result.file, result.durationMs))
    }

    /** 用户主动放弃这次录音。 */
    fun cancelRecording() {
        if (!_state.value.recording) return
        recordTimer?.cancel()
        recordTimer = null
        _state.update { it.copy(recording = false, elapsedMs = 0L, pendingText = "") }
        runCatching { c.audio.cancelRecording() }
        discardPendingRecording()
    }

    /** 「重说」：丢掉本次识别结果与录音，重新开始录。 */
    fun reRecord() {
        if (_state.value.busy) return
        discardPendingRecording()
        _state.update { it.copy(pendingText = "", elapsedMs = 0L) }
        startRecording()
    }

    /** ASR：失败保留录音，错误条「重试」可重新识别。 */
    private fun recognize(rec: RecordingHolder) {
        if (_state.value.busy) return
        pendingRecording = rec
        viewModelScope.launch {
            _state.update {
                it.copy(busy = true, progressText = "识别中…", error = null, retryAction = ChatRetryAction.NONE)
            }
            scheduleProgressHint("识别中…")
            try {
                val bytes = withContext(Dispatchers.IO) { rec.file.readBytes() }
                val text = c.chat.asr(bytes, "en").trim()
                if (text.isEmpty()) {
                    rec.file.delete()
                    pendingRecording = null
                    stopProgress()
                    _state.update { it.copy(busy = false) }
                    setError(
                        UiError(
                            message = if (_state.value.isChild) "没听清，再说一次好吗" else "没听清，请再说一次",
                            actionLabel = if (_state.value.isChild) "再说一次" else "重试",
                            retryable = true,
                            code = "asr_empty",
                        ),
                        ChatRetryAction.RECORD,
                    )
                    return@launch
                }
                stopProgress()
                // 关键交互：只显示识别文本，等用户点「发送」；不自动进 LLM
                _state.update { it.copy(busy = false, pendingText = text) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                stopProgress()
                _state.update { it.copy(busy = false) }
                handleError(e, ChatRetryAction.ASR)
            }
        }
    }

    // ------------------------------------------------------------------ 一轮（发送 → turn → TTS → 补 pron）

    /** 用户确认识别文本后提交：插入用户气泡 → `POST /turn`。 */
    fun confirmSend() {
        val snapshot = _state.value
        val rec = pendingRecording ?: return
        val text = snapshot.pendingText.trim()
        if (text.isEmpty() || snapshot.busy || snapshot.ended) return
        val userMsg = ChatMessageUi(
            id = "u_${System.currentTimeMillis()}",
            role = "user",
            text = text.take(MAX_TURN_TEXT),
            localAudio = rec.file,
        )
        pendingRecording = null
        _state.update {
            it.copy(
                pendingText = "",
                hintText = "",
                recording = false,
                messages = it.messages + userMsg,
            )
        }
        sendTurn(PendingTurn(text = userMsg.text, file = rec.file, userMsgId = userMsg.id))
    }

    private fun sendTurn(turn: PendingTurn) {
        if (_state.value.busy) return
        pendingTurn = turn
        viewModelScope.launch {
            _state.update {
                it.copy(busy = true, progressText = "回复中…", error = null, retryAction = ChatRetryAction.NONE)
            }
            scheduleProgressHint("回复中…")
            try {
                val audio = withContext(Dispatchers.IO) {
                    turn.file.takeIf { it.exists() && it.length() > 0L }?.readBytes()
                }
                val response = c.chat.turn(_state.value.sessionId, audio, turn.text)
                pendingTurn = null
                stopProgress()
                _state.update { it.copy(busy = false) }
                applyTurn(response, turn.userMsgId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                stopProgress()
                _state.update { it.copy(busy = false) }
                handleError(e, ChatRetryAction.TURN)
            }
        }
    }

    private fun applyTurn(turn: ChatTurnDto, userMsgId: String) {
        val snapshot = _state.value
        val assistant = ChatMsgFactory.applyCorrection(
            ChatMessageUi(
                id = turn.messageId.ifEmpty { "a_${System.currentTimeMillis()}" },
                role = "assistant",
                text = turn.reply,
                textZh = turn.replyZh,
                unsafeFiltered = turn.flag == "unsafe_filtered",
            ),
            turn.correction,
        )
        val nextTurn = if (turn.turnIndex > 0) turn.turnIndex else snapshot.turnCount + 1
        _state.update {
            it.copy(
                turnCount = nextTurn,
                degradedLlm = turn.degradedLlm,
                degraded = turn.degraded,
                messages = it.messages + assistant,
                suggestedReplies = turn.suggestedReplies.take(3),
                hintText = "",
                done = turn.done,
            )
        }
        if (turn.done) {
            // 场景自然收尾：不显示录音区，直接汇总 + 整段回放
            _state.update { it.copy(ended = true, suggestedReplies = emptyList()) }
            endSession()
            return
        }
        if (turn.reply.isNotEmpty() && _state.value.autoRead) {
            playMessage(assistant.id)
        }
        startPronPoll(userMsgId, assistant.id)
    }

    /**
     * 后台轮询补 pron：4 次（0.7/1.1/1.5/1.9s），拿不到就放弃，不报错、不回滚消息。
     * 后端把本轮 pron 写在用户消息上（turn 的 after() 异步评测）；部分版本落在助手消息上，
     * 所以两边都尝试，同时顺带补齐助手的 correction（历史回看也还在）。
     */
    private fun startPronPoll(userMsgId: String, assistantId: String) {
        pronPollJob?.cancel()
        pronPollJob = viewModelScope.launch {
            for (delayMs in PRON_POLL_DELAYS) {
                delay(delayMs)
                val list = try {
                    c.chat.messages(_state.value.sessionId)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    null
                } ?: continue
                if (applyPronFromMessages(list, userMsgId, assistantId)) return@launch
            }
        }
    }

    /** @return true = 本轮已拿到 pron（停止轮询） */
    private fun applyPronFromMessages(
        list: List<ChatMessageDto>,
        userMsgId: String,
        assistantId: String,
    ): Boolean {
        val snapshot = _state.value
        val isChild = snapshot.isChild
        val userMsg = snapshot.messages.firstOrNull { it.id == userMsgId }
        val assistantMsg = snapshot.messages.firstOrNull { it.id == assistantId }
        var updated = snapshot.messages
        var gotRoundPron = userMsg?.hasPron == true || assistantMsg?.hasPron == true

        // 1) 本轮用户消息的 pron
        val userDto = list.lastOrNull { dto ->
            dto.role == "user" && (dto.id == userMsgId || (userMsg != null && dto.text == userMsg.text))
        }
        val userPron = userDto?.pron
        if (userPron != null && userMsg != null) {
            updated = updated.map { msg ->
                if (msg.id == userMsgId) ChatMsgFactory.applyPron(msg, userPron, isChild) else msg
            }
            gotRoundPron = true
        }

        // 2) 本轮助手消息的 pron（部分版本把分数落在助手消息上）
        val assistantDto = list.firstOrNull { it.id == assistantId }
            ?: list.lastOrNull { dto ->
                dto.role == "assistant" && assistantMsg != null && dto.text == assistantMsg.text
            }
        val assistantPron = assistantDto?.pron
        if (assistantPron != null && assistantMsg != null) {
            updated = updated.map { msg ->
                if (msg.id == assistantId) ChatMsgFactory.applyPron(msg, assistantPron, isChild) else msg
            }
            gotRoundPron = true
        }

        // 3) 顺带补 correction（历史回看也还在）
        updated = updated.map { msg ->
            if (msg.role != "assistant" || msg.hasCorrection) {
                msg
            } else {
                val dto = list.firstOrNull { it.id == msg.id }
                if (dto?.correction == null) msg else ChatMsgFactory.applyCorrection(msg, dto.correction)
            }
        }

        if (updated != snapshot.messages) {
            _state.update { it.copy(messages = updated) }
        }
        return gotRoundPron
    }

    // ------------------------------------------------------------------ 结束会话

    /** 手动「结束对话」或 done=true：`POST /:id/end` → 结束卡 + 整段回放。 */
    fun endSession() {
        val snapshot = _state.value
        if (snapshot.ending || snapshot.sessionId.isEmpty() || snapshot.readOnly) return
        viewModelScope.launch {
            _state.update { it.copy(ending = true, recording = false, suggestedReplies = emptyList(), hintText = "") }
            recordTimer?.cancel()
            recordTimer = null
            pronPollJob?.cancel()
            if (c.audio.recording.value) runCatching { c.audio.cancelRecording() }
            discardPendingRecording()
            pendingTurn = null
            runCatching { c.audio.stopPlayback() }
            resetMessagePlayStates()
            try {
                c.chat.end(snapshot.sessionId)
                _state.update { it.copy(ending = false, ended = true) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(ending = false, ended = true) }
                handleError(e, ChatRetryAction.END)
            }
            beginReplay()
        }
    }

    /** 结束卡的「再聊一次」：用同一个场景重新开会话（服务端已关闭旧会话）。 */
    fun restartSession() {
        val snapshot = _state.value
        val scenarioId = snapshot.scenarioId
        if (snapshot.busy || snapshot.loading || scenarioId.isEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(loading = true, loadError = null) }
            try {
                val session = c.chat.createSession(scenarioId)
                resetForLive(session)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(loading = false) }
                handleError(e, ChatRetryAction.RESTART)
            }
        }
    }

    private fun resetForLive(session: ChatSessionDto) {
        recordTimer?.cancel()
        progressTimer?.cancel()
        pronPollJob?.cancel()
        replayTimer?.cancel()
        recordTimer = null
        progressTimer = null
        pronPollJob = null
        replayTimer = null
        discardPendingRecording()
        pendingTurn = null
        ttsCache.clear()
        userAudioCache.clear()
        lastFailedPlayId = ""
        replayFile = null
        replayTries = 0
        runCatching { c.audio.stopPlayback() }
        val scenario = session.scenario
        val opening = openingLineOf(session, scenario)
        val openingMsg = openingNode(opening)
        val previous = _state.value
        _state.update {
            it.copy(
                sessionId = session.sessionId,
                titleEn = scenario?.title?.takeIf { value -> value.isNotEmpty() } ?: previous.titleEn,
                titleZh = scenario?.titleZh?.takeIf { value -> value.isNotEmpty() } ?: previous.titleZh,
                settingZh = scenario?.settingZh?.takeIf { value -> value.isNotEmpty() } ?: previous.settingZh,
                level = scenario?.level?.takeIf { value -> value.isNotEmpty() } ?: previous.level,
                messages = listOfNotNull(openingMsg),
                loading = false,
                loadError = null,
                busy = false,
                progressText = "",
                preparing = false,
                recording = false,
                elapsedMs = 0L,
                pendingText = "",
                ending = false,
                ended = false,
                done = false,
                degradedLlm = false,
                degraded = false,
                quotaExceeded = false,
                quotaText = "",
                suggestedReplies = emptyList(),
                hintText = "",
                voiceNotice = "",
                error = null,
                retryAction = ChatRetryAction.NONE,
                replayStatus = ChatReplayStatus.IDLE,
                replayError = "",
                replayPlaying = false,
                replayDurationMs = 0L,
                readOnly = false,
                turnCount = session.turnCount,
                startedAt = "",
                endedAt = "",
            )
        }
        if (openingMsg != null && _state.value.autoRead) playMessage(openingMsg.id)
    }

    // ------------------------------------------------------------------ 建议回复（只朗读，不发送）

    fun speakSuggestion(text: String) {
        val snapshot = _state.value
        if (text.isBlank() || snapshot.recording || snapshot.preparing || snapshot.ended) return
        _state.update { it.copy(hintText = text, voiceNotice = "") }
        viewModelScope.launch {
            try {
                runCatching { c.audio.stopPlayback() }
                resetMessagePlayStates()
                val bytes = c.practice.tts(
                    text = text.take(MAX_TURN_TEXT),
                    rate = _state.value.ttsRate,
                    voice = _state.value.ttsVoice.ifEmpty { null },
                    format = "mp3",
                )
                c.audio.playBytes(bytes, "chat_suggestion.mp3")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update {
                    it.copy(
                        voiceNotice = if (it.isChild) "这句话的声音没出来，再点一次试试" else "提示句暂时读不出来，可以先自己说",
                    )
                }
            }
        }
    }

    fun clearHint() {
        _state.update { it.copy(hintText = "") }
    }

    // ------------------------------------------------------------------ 单条播放

    /** 播放一条气泡（用户语音 / 助手 TTS）；播放中再点 = 停止。 */
    fun playMessage(messageId: String) {
        val snapshot = _state.value
        if (snapshot.recording || snapshot.preparing) return
        val msg = snapshot.messages.firstOrNull { it.id == messageId } ?: return
        if (msg.role == "assistant" && msg.text.isBlank()) return
        if (msg.playState == ChatPlayState.PLAYING) {
            runCatching { c.audio.stopPlayback() }
            updatePlayState(messageId, ChatPlayState.NONE)
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(voiceNotice = "", replayPlaying = false) }
            resetMessagePlayStates()
            updatePlayState(messageId, ChatPlayState.LOADING)
            try {
                val bytes = if (msg.role == "user") ensureUserAudio(msg) else ensureTts(msg)
                if (bytes.isEmpty()) {
                    throw ApiError.local(ApiErrorCode.AUDIO_NOT_FOUND, "这条还没有录音回放")
                }
                updatePlayState(messageId, ChatPlayState.PLAYING)
                val hint = if (msg.role == "user") "chat_user_${msg.id}.m4a" else "chat_reply_${msg.id}.mp3"
                c.audio.playBytes(bytes, hint)
                // playBytes 没有完成回调：等 playing 归零（带超时兜底，避免极端情况下按钮卡在播放态）
                withTimeoutOrNull(MESSAGE_PLAY_WAIT_MS) { c.audio.playing.first { !it } }
                updatePlayState(messageId, ChatPlayState.NONE)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                updatePlayState(messageId, ChatPlayState.FAILED)
                lastFailedPlayId = messageId
                _state.update {
                    it.copy(
                        voiceNotice = if (it.isChild) "声音没出来，再点一次试试" else "语音没出来，点气泡上的播放再试一次",
                    )
                }
            }
        }
    }

    private suspend fun ensureTts(msg: ChatMessageUi): ByteArray {
        ttsCache[msg.id]?.let { return it }
        val snapshot = _state.value
        val bytes = c.practice.tts(
            text = msg.text,
            rate = snapshot.ttsRate,
            voice = snapshot.ttsVoice.ifEmpty { null },
            format = "mp3",
        )
        ttsCache[msg.id] = bytes
        return bytes
    }

    private suspend fun ensureUserAudio(msg: ChatMessageUi): ByteArray {
        val local = msg.localAudio
        if (local != null && local.exists() && local.length() > 0L) {
            return withContext(Dispatchers.IO) { local.readBytes() }
        }
        if (msg.audioUrl.isNotEmpty()) {
            val cached = userAudioCache.getOrPut(msg.id) { c.cache.audioFile("chatmsg_${msg.id}", "m4a") }
            if (!cached.exists() || cached.length() == 0L) {
                val bytes = c.chat.messageAudio(msg.audioUrl)
                withContext(Dispatchers.IO) { FileUtil.writeBytesAtomic(cached, bytes) }
            }
            return withContext(Dispatchers.IO) { cached.readBytes() }
        }
        throw ApiError.local(ApiErrorCode.AUDIO_NOT_FOUND, "这条还没有录音回放")
    }

    private fun updatePlayState(messageId: String, playState: ChatPlayState) {
        _state.update { snapshot ->
            snapshot.copy(
                messages = snapshot.messages.map { msg ->
                    if (msg.id == messageId) msg.copy(playState = playState) else msg
                },
            )
        }
    }

    private fun resetMessagePlayStates() {
        _state.update { snapshot ->
            snapshot.copy(
                messages = snapshot.messages.map { msg ->
                    if (msg.playState == ChatPlayState.PLAYING || msg.playState == ChatPlayState.LOADING) {
                        msg.copy(playState = ChatPlayState.NONE)
                    } else {
                        msg
                    }
                },
            )
        }
    }

    // ------------------------------------------------------------------ 整段回放（§2.8）

    /** 开始轮询整段回放：status → ready 则下载 audio；building 每 2s 一次，最多约 60s。 */
    fun beginReplay() {
        if (_state.value.sessionId.isEmpty()) return
        replayTimer?.cancel()
        replayTimer = null
        replayTries = 0
        _state.update {
            it.copy(replayStatus = ChatReplayStatus.LOADING, replayError = "", replayPlaying = false)
        }
        viewModelScope.launch { checkReplay(allowTrigger = true) }
    }

    private suspend fun checkReplay(allowTrigger: Boolean) {
        val sessionId = _state.value.sessionId
        if (sessionId.isEmpty()) return
        replayTries += 1
        try {
            val status = c.chat.audioStatus(sessionId)
            when (status.status) {
                "ready" -> {
                    _state.update { it.copy(replayStatus = ChatReplayStatus.LOADING) }
                    val bytes = c.chat.audio(sessionId, force = false)
                    if (bytes != null) {
                        val file = c.cache.audioFile("chat_replay_$sessionId", "wav")
                        withContext(Dispatchers.IO) { FileUtil.writeBytesAtomic(file, bytes) }
                        replayFile = file
                        _state.update {
                            it.copy(
                                replayStatus = ChatReplayStatus.READY,
                                replayDurationMs = status.durationMs.toLong(),
                                replayError = "",
                            )
                        }
                        return
                    }
                    _state.update { it.copy(replayStatus = ChatReplayStatus.BUILDING) }
                    scheduleReplay()
                }

                "failed" -> failReplay(
                    status.error?.takeIf { it.isNotEmpty() } ?: fallbackReplayError(),
                )

                else -> {
                    // building / pending：首次补发一次 GET audio 触发构建（老会话没有 sidecar）
                    _state.update { it.copy(replayStatus = ChatReplayStatus.BUILDING) }
                    if (allowTrigger) {
                        try {
                            c.chat.audio(sessionId, force = false)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Throwable) {
                            // 202/网络抖动都不算错误，继续轮询
                        }
                    }
                    scheduleReplay()
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            failReplay(c.session.toUiError(e).message)
        }
    }

    private fun scheduleReplay() {
        if (_state.value.replayStatus != ChatReplayStatus.BUILDING) return
        replayTimer?.cancel()
        replayTimer = null
        if (replayTries >= REPLAY_MAX_TRIES) {
            failReplay(
                if (_state.value.isChild) {
                    "回放还没准备好，等一下再点这里试试"
                } else {
                    "整段回放生成超时了，可以点「重新生成」"
                },
            )
            return
        }
        replayTimer = viewModelScope.launch {
            delay(REPLAY_POLL_INTERVAL_MS)
            checkReplay(allowTrigger = false)
        }
    }

    /** 「🔄 重新生成」：`GET audio?force=1` 后再轮询（auto_retry=false 时只能用户点）。 */
    fun regenerateReplay() {
        val snapshot = _state.value
        if (snapshot.sessionId.isEmpty() || snapshot.replayStatus == ChatReplayStatus.LOADING) return
        replayTimer?.cancel()
        replayTimer = null
        replayTries = 0
        replayFile = null
        _state.update {
            it.copy(replayStatus = ChatReplayStatus.LOADING, replayError = "", replayPlaying = false)
        }
        viewModelScope.launch {
            try {
                val bytes = c.chat.audio(snapshot.sessionId, force = true)
                if (bytes != null) {
                    val file = c.cache.audioFile("chat_replay_${snapshot.sessionId}", "wav")
                    withContext(Dispatchers.IO) { FileUtil.writeBytesAtomic(file, bytes) }
                    replayFile = file
                    _state.update { it.copy(replayStatus = ChatReplayStatus.READY) }
                    return@launch
                }
                _state.update { it.copy(replayStatus = ChatReplayStatus.BUILDING) }
                scheduleReplay()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                failReplay(c.session.toUiError(e).message)
            }
        }
    }

    fun playReplay() {
        val file = replayFile ?: return
        if (_state.value.replayPlaying) {
            runCatching { c.audio.stopPlayback() }
            _state.update { it.copy(replayPlaying = false) }
            return
        }
        viewModelScope.launch {
            resetMessagePlayStates()
            _state.update { it.copy(replayPlaying = true, voiceNotice = "") }
            try {
                c.audio.playFile(file)
                withTimeoutOrNull(REPLAY_PLAY_WAIT_MS) { c.audio.playing.first { !it } }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(voiceNotice = c.session.toUiError(e).message) }
            } finally {
                _state.update { it.copy(replayPlaying = false) }
            }
        }
    }

    private fun failReplay(message: String) {
        replayTimer?.cancel()
        replayTimer = null
        _state.update { it.copy(replayStatus = ChatReplayStatus.FAILED, replayError = message) }
    }

    private fun fallbackReplayError(): String = if (_state.value.isChild) {
        "回放还在准备，等一下再点这里试试"
    } else {
        "整段回放暂时生成不了，可以先看文字记录"
    }

    // ------------------------------------------------------------------ 错误

    fun clearError() {
        _state.update { it.copy(error = null, retryAction = ChatRetryAction.NONE) }
    }

    /** 错误条「重试」：按 [ChatRetryAction] 真正重做对应动作（MIC_DENIED 由页面拉权限）。 */
    fun retryError() {
        val snapshot = _state.value
        val error = snapshot.error ?: return
        if (error.code == ApiErrorCode.MIC_DENIED) return
        val action = snapshot.retryAction
        clearError()
        when (action) {
            ChatRetryAction.RECORD -> startRecording()
            ChatRetryAction.ASR -> pendingRecording?.let { recognize(it) }
            ChatRetryAction.TURN -> pendingTurn?.let { sendTurn(it) }
            ChatRetryAction.PLAY_TTS -> if (lastFailedPlayId.isNotEmpty()) playMessage(lastFailedPlayId)
            ChatRetryAction.REPLAY -> regenerateReplay()
            ChatRetryAction.END -> endSession()
            ChatRetryAction.RESTART -> restartSession()
            ChatRetryAction.NONE -> Unit
        }
    }

    private fun setError(error: UiError, action: ChatRetryAction) {
        _state.update { it.copy(error = error, retryAction = action) }
    }

    /**
     * 统一错误处理（§1.2）：
     * - 429 = 额度业务态（横幅 + 禁用录音），不弹错误条；
     * - 409 / session_closed = 会话已结束（切结束态）；
     * - 其余展示可读 message + 可重试动作。
     */
    private fun handleError(err: Throwable, action: ChatRetryAction) {
        val ui = c.session.toUiError(err)
        if (ui.code == ApiErrorCode.UNAUTHORIZED) {
            viewModelScope.launch { runCatching { c.session.expire() } }
        }
        val apiErr = err as? ApiError
        if (apiErr?.status == 429) {
            _state.update {
                it.copy(
                    quotaExceeded = true,
                    quotaText = ui.message.ifEmpty {
                        if (it.isChild) "今天已经练得很棒啦，明天再来 🌙" else "今天的练习时间到了，明天再来"
                    },
                )
            }
            return
        }
        if (apiErr != null && (apiErr.code == "session_closed" || apiErr.status == 409)) {
            _state.update { it.copy(ended = true, suggestedReplies = emptyList()) }
        }
        val label = when {
            ui.code == ApiErrorCode.MIC_DENIED -> "去设置"
            ui.actionLabel.isNotEmpty() -> ui.actionLabel
            action != ChatRetryAction.NONE -> if (_state.value.isChild) "再试一次" else "重试"
            else -> ""
        }
        setError(
            ui.copy(actionLabel = label, retryable = action != ChatRetryAction.NONE || label.isNotEmpty()),
            action,
        )
    }

    // ------------------------------------------------------------------ 进度提示

    private fun scheduleProgressHint(base: String) {
        progressTimer?.cancel()
        progressTimer = viewModelScope.launch {
            delay(8_000)
            _state.update { if (it.busy) it.copy(progressText = base + "（有点慢，再等一下）") else it }
        }
    }

    private fun stopProgress() {
        progressTimer?.cancel()
        progressTimer = null
        _state.update { it.copy(progressText = "") }
    }

    private fun startRecordTimer() {
        recordTimer?.cancel()
        recordTimer = viewModelScope.launch {
            while (isActive) {
                delay(200)
                val elapsed = SystemClock.elapsedRealtime() - recordStartedAtElapsed
                _state.update { it.copy(elapsedMs = elapsed) }
                if (elapsed >= AudioController.MAX_DURATION_MS) {
                    // 60s 上限：自动停录并进入识别
                    stopAndRecognize()
                    return@launch
                }
            }
        }
    }

    private fun discardPendingRecording() {
        val rec = pendingRecording ?: return
        pendingRecording = null
        if (rec.file.exists()) rec.file.delete()
    }

    // ------------------------------------------------------------------ 内部

    private fun openingLineOf(session: ChatSessionDto, scenario: ChatScenarioDto?): String {
        val fromScenario = scenario?.openingLine.orEmpty()
        if (fromScenario.isNotEmpty()) return fromScenario
        // 自定义场景分支没有 messages；messages[0] 只是占位，显示/朗读一律用 scenario.opening_line
        return session.messages.firstOrNull()?.text.orEmpty()
    }

    private fun openingNode(opening: String): ChatMessageUi? =
        if (opening.isEmpty()) null else ChatMessageUi(id = "opening", role = "assistant", text = opening)

    /** 页面离开时：停录音/播放，避免回到场景页还在录（对应 hos `dispose`）。 */
    fun onLeave() {
        recordTimer?.cancel()
        recordTimer = null
        progressTimer?.cancel()
        progressTimer = null
        pronPollJob?.cancel()
        pronPollJob = null
        replayTimer?.cancel()
        replayTimer = null
        if (_state.value.recording) {
            runCatching { c.audio.cancelRecording() }
        }
        discardPendingRecording()
        runCatching { c.audio.stopPlayback() }
        _state.update {
            it.copy(recording = false, elapsedMs = 0L, preparing = false, replayPlaying = false)
        }
    }

    override fun onCleared() {
        super.onCleared()
        recordTimer?.cancel()
        progressTimer?.cancel()
        pronPollJob?.cancel()
        replayTimer?.cancel()
        runCatching { c.audio.release() }
    }

    companion object {
        /** turn 的 text 上限（服务端约束），ASR 文本正常远小于它。 */
        private const val MAX_TURN_TEXT = 500

        /** 轮询补 pron 的节奏（共 4 次，拿不到就放弃、不报错）。 */
        private val PRON_POLL_DELAYS = listOf(700L, 1100L, 1500L, 1900L)

        /** 整段回放轮询：2s 一次，最多 30 次（约 60s）。 */
        private const val REPLAY_POLL_INTERVAL_MS = 2_000L
        private const val REPLAY_MAX_TRIES = 30

        /** 等单条气泡播放结束的超时（TTS 短音频，2 分钟足够兜底）。 */
        private const val MESSAGE_PLAY_WAIT_MS = 120_000L

        /** 等整段回放结束的超时（服务端上限 900s，给 20 分钟兜底）。 */
        private const val REPLAY_PLAY_WAIT_MS = 20 * 60_000L
    }
}

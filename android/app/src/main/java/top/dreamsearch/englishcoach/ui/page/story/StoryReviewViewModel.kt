package top.dreamsearch.englishcoach.ui.page.story

import android.os.SystemClock
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
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
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.util.FileUtil
import top.dreamsearch.englishcoach.ui.nav.NavParams
import java.io.File

/** 复述页的重试动作。 */
enum class StoryReviewRetry { NONE, ASR, RETELL }

data class StoryReviewUiState(
    val loading: Boolean = true,
    val loadError: UiError? = null,
    val isChild: Boolean = false,
    val exceeded: Boolean = false,
    val storyId: String = "",
    val storyTitle: String = "",
    /** A1–C1 */
    val level: String = "A2",
    val storySentences: List<String> = emptyList(),
    /** false = 录音复述；true = 打字复述 */
    val textMode: Boolean = false,
    val typedText: String = "",
    val transcript: String = "",
    val preparing: Boolean = false,
    val recording: Boolean = false,
    val elapsedMs: Long = 0L,
    val busy: Boolean = false,
    val busyText: String = "",
    val hasResult: Boolean = false,
    /** 覆盖率百分比；-1 = 服务端没给（页面显示「—」） */
    val coveragePercent: Int = -1,
    val coveredPoints: List<String> = emptyList(),
    val missingPoints: List<String> = emptyList(),
    val feedbackZh: String = "",
    val feedbackEn: String = "",
    val recordingPlaying: Boolean = false,
    /** 本次录音已落盘，可回放（失败重试时也不丢） */
    val canPlayRecording: Boolean = false,
    val error: UiError? = null,
    val retry: StoryReviewRetry = StoryReviewRetry.NONE,
)

/**
 * 复述故事的 ViewModel（对应 hos `StoryReviewVM`）。
 *
 * 规则（docs/screens.md §6.3、CONTRACT §5）：
 * 1. 录音 0.6–60s → `StoryService.asr(bytes, "en-US")` 拿 transcript；
 * 2. `StoryService.retell(materialId, storySentences, transcript, level)`；
 * 3. 展示 `coverage / covered_points / missing_points / feedback_zh / feedback_en`，
 *    **不显示任何发音分**；儿童只显示「讲到了 / 还可以讲」，不显示百分比低分。
 * 失败保留录音（[StoryReviewRetry.ASR] 可只重识别；[StoryReviewRetry.RETELL] 只用 transcript 重提交）。
 */
class StoryReviewViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(StoryReviewUiState())
    val state: StateFlow<StoryReviewUiState> = _state.asStateFlow()

    private var recordingFile: File? = null
    private var lastTranscript: String = ""
    private var timerJob: Job? = null
    private var recordStartedAt = 0L

    init {
        val materialId = NavParams.storyMaterialId.orEmpty()
        NavParams.storyMaterialId = null

        viewModelScope.launch {
            val session = c.session.state.first()
            _state.update {
                it.copy(
                    isChild = session.isChild,
                    exceeded = session.exceeded,
                    level = StoryText.normalizeRetellLevel(session.cefrLevel),
                )
            }
        }
        viewModelScope.launch {
            c.session.state.collect { session ->
                _state.update { it.copy(isChild = session.isChild, exceeded = session.exceeded) }
            }
        }

        if (materialId.isEmpty()) {
            _state.update {
                it.copy(
                    loading = false,
                    loadError = UiError.of("not_found", "没有找到这个故事，返回详情页重新进入试试", false),
                )
            }
        } else {
            load(materialId)
        }
    }

    // ------------------------------------------------------------------ 加载故事原文

    fun load(id: String) {
        if (id.isEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(storyId = id, loading = true, loadError = null) }
            try {
                val dto = c.story.materialDetail(id)
                val sentences = StoryText.splitSentences(dto.text)
                val level = dto.level?.takeIf { it.isNotBlank() }?.let(StoryText::normalizeRetellLevel)
                _state.update {
                    it.copy(
                        loading = false,
                        loadError = null,
                        storyId = id,
                        storyTitle = dto.title.trim().ifEmpty { "这个故事" },
                        level = level ?: it.level,
                        storySentences = sentences,
                    )
                }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(loading = false, loadError = ui) }
            }
        }
    }

    fun retryLoad() {
        val id = _state.value.storyId
        if (id.isNotEmpty()) load(id)
    }

    // ------------------------------------------------------------------ 输入方式

    fun setTextMode(value: Boolean) {
        _state.update { it.copy(textMode = value) }
    }

    fun setTypedText(value: String) {
        _state.update { it.copy(typedText = value) }
    }

    // ------------------------------------------------------------------ 录音 → ASR(en) → retell

    fun startRecording() {
        val current = _state.value
        if (current.recording || current.preparing || current.busy) return
        if (current.exceeded) {
            setLocalError(ApiErrorCode.DAILY_LIMIT_REACHED, "今天的练习时长已达上限，明天再来 🌙")
            return
        }
        _state.update { it.copy(preparing = true, error = null) }
        try {
            c.audio.startRecording("retell")
            recordStartedAt = SystemClock.elapsedRealtime()
            _state.update { it.copy(preparing = false, recording = true, elapsedMs = 0L) }
            startTimer()
        } catch (e: Throwable) {
            failAsync(e, StoryReviewRetry.NONE)
        }
    }

    fun stopRecordingAndSubmit() {
        if (!_state.value.recording) return
        stopTimer()
        _state.update { it.copy(recording = false) }
        val result = try {
            c.audio.stopRecording()
        } catch (e: Throwable) {
            failAsync(e, StoryReviewRetry.NONE)
            return
        }
        recordingFile = result.file
        _state.update { it.copy(canPlayRecording = true) }
        recognizeAndSubmit(result.file)
    }

    fun cancelRecording() {
        stopTimer()
        _state.update { it.copy(recording = false, elapsedMs = 0L) }
        c.audio.cancelRecording()
    }

    /** 失败保留录音：只重跑 ASR + retell。 */
    fun retryRecognize() {
        val file = recordingFile ?: return
        if (_state.value.busy) return
        recognizeAndSubmit(file)
    }

    fun playRecording() {
        val file = recordingFile ?: return
        if (!file.exists()) {
            _state.update { it.copy(error = UiError.of(ApiErrorCode.AUDIO_GONE, "录音文件已不存在，再讲一次吧", false)) }
            return
        }
        c.audio.stopPlayback()
        _state.update { it.copy(recordingPlaying = true) }
        try {
            c.audio.playFile(file) {
                _state.update { state -> state.copy(recordingPlaying = false) }
            }
        } catch (e: Throwable) {
            _state.update { it.copy(recordingPlaying = false) }
            failAsync(e, StoryReviewRetry.NONE)
        }
    }

    private fun recognizeAndSubmit(file: File) {
        val bytes = FileUtil.readBytes(file)
        if (bytes == null || bytes.isEmpty()) {
            setLocalError(ApiErrorCode.RECORD_FAILED, "录音文件读不出来，再讲一次吧")
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(busy = true, busyText = "正在听懂你的复述… ⏳", error = null) }
            val transcript = try {
                c.story.asr(bytes, "en-US")
            } catch (e: Throwable) {
                applyError(e, StoryReviewRetry.ASR)
                return@launch
            }
            _state.update { it.copy(busy = false, busyText = "", transcript = transcript) }
            submitTranscript(transcript)
        }
    }

    // ------------------------------------------------------------------ 提交复述

    fun submitTyped() {
        val text = _state.value.typedText.trim()
        if (text.isEmpty()) {
            setLocalError(ApiErrorCode.BAD_REQUEST, if (_state.value.isChild) "先写一句你想说的吧" else "请先输入你的复述")
            return
        }
        submitTranscript(text)
    }

    private fun submitTranscript(transcript: String) {
        val current = _state.value
        if (current.busy) return
        val text = transcript.trim()
        if (text.isEmpty()) {
            setLocalError(ApiErrorCode.BAD_REQUEST, "没有听到你的复述，再讲一次吧")
            return
        }
        if (current.storySentences.isEmpty()) {
            setLocalError(ApiErrorCode.BAD_REQUEST, "缺少故事原文，返回详情页重新进入试试")
            return
        }
        lastTranscript = text
        viewModelScope.launch {
            _state.update {
                it.copy(busy = true, busyText = "老师在看你讲得怎么样… ⏳", error = null, retry = StoryReviewRetry.NONE)
            }
            try {
                val dto = c.story.retell(
                    materialId = current.storyId,
                    storySentences = current.storySentences,
                    transcript = text,
                    level = current.level,
                )
                val covered = dto.coveredPoints
                val missing = dto.missingPoints
                val coveragePercent = StoryText.coveragePercentOf(dto.coverage)
                StoryRuntime.addRetell(
                    cache = c.cache,
                    materialId = current.storyId,
                    record = StoryRuntime.RetellRecord(
                        createdAt = StoryText.clockTextNow(),
                        coveragePercent = coveragePercent,
                        coveredPoints = covered,
                        missingPoints = missing,
                        feedbackZh = dto.feedbackZh,
                        feedbackEn = dto.feedbackEn,
                        transcript = text,
                    ),
                )
                _state.update {
                    it.copy(
                        busy = false,
                        busyText = "",
                        hasResult = true,
                        coveragePercent = coveragePercent,
                        coveredPoints = covered,
                        missingPoints = missing,
                        feedbackZh = dto.feedbackZh,
                        feedbackEn = dto.feedbackEn,
                        error = null,
                        retry = StoryReviewRetry.NONE,
                    )
                }
            } catch (e: Throwable) {
                applyError(e, StoryReviewRetry.RETELL)
            }
        }
    }

    // ------------------------------------------------------------------ 错误 / 重试

    fun retry() {
        val retry = _state.value.retry
        clearError()
        when (retry) {
            StoryReviewRetry.ASR -> retryRecognize()
            StoryReviewRetry.RETELL -> submitTranscript(lastTranscript)
            StoryReviewRetry.NONE -> Unit
        }
    }

    fun clearError() {
        _state.update { it.copy(error = null, retry = StoryReviewRetry.NONE) }
    }

    private fun setLocalError(code: String, message: String) {
        _state.update { it.copy(error = UiError.of(code, message, false), retry = StoryReviewRetry.NONE) }
    }

    private suspend fun applyError(err: Throwable, retry: StoryReviewRetry) {
        val ui = c.session.toUiErrorAsync(err)
        _state.update {
            it.copy(
                busy = false,
                busyText = "",
                preparing = false,
                recording = false,
                error = ui,
                retry = retry,
            )
        }
    }

    private fun failAsync(err: Throwable, retry: StoryReviewRetry) {
        viewModelScope.launch { applyError(err, retry) }
    }

    // ------------------------------------------------------------------ 计时

    private fun startTimer() {
        stopTimer()
        timerJob = viewModelScope.launch {
            while (isActive) {
                val elapsed = SystemClock.elapsedRealtime() - recordStartedAt
                _state.update { it.copy(elapsedMs = elapsed) }
                if (elapsed >= MAX_RECORD_MS) {
                    stopRecordingAndSubmit()
                    return@launch
                }
                delay(200)
            }
        }
    }

    private fun stopTimer() {
        timerJob?.cancel()
        timerJob = null
    }

    override fun onCleared() {
        stopTimer()
        if (_state.value.recording) c.audio.cancelRecording()
        c.audio.stopPlayback()
        super.onCleared()
    }

    companion object {
        /** 复述录音上限 60s（CONTRACT §4.1 的 0.6–60s） */
        const val MAX_RECORD_MS = 60_000L
    }
}

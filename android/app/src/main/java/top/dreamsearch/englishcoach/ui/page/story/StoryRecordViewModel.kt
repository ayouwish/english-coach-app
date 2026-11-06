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
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.dto.StoryRewriteDto
import top.dreamsearch.englishcoach.core.util.FileUtil
import java.io.File

/** 重试动作：错误条上的「重试」按最近一次失败的操作分派。 */
enum class StoryRecordRetry { NONE, ASR, REWRITE, SAVE }

/** 可编辑的一句英文（index 从 1 开始，仅用于展示序号）。 */
data class StorySentenceEdit(val index: Int, val en: String)

data class StoryRecordUiState(
    val isChild: Boolean = false,
    val exceeded: Boolean = false,
    /** 中文故事稿（≤2000 字） */
    val textZh: String = "",
    val level: String = "A2",
    val maxSentences: Int = 8,
    /** auto | past | present */
    val tense: String = "past",
    /** 仅成人；把 weakest 音练进故事 */
    val useWeakPhonemes: Boolean = false,
    val recording: Boolean = false,
    val preparing: Boolean = false,
    val elapsedMs: Long = 0L,
    val busy: Boolean = false,
    val busyText: String = "",
    val notice: String = "",
    /** 503 story_unavailable 时允许手动写英文 */
    val manualMode: Boolean = false,
    val manualTitle: String = "",
    val manualText: String = "",
    val hasResult: Boolean = false,
    val title: String = "",
    val sentences: List<StorySentenceEdit> = emptyList(),
    val readabilityText: String = "",
    val unknownWordsText: String = "",
    val warningText: String = "",
    val weakPhonemes: List<String> = emptyList(),
    val saving: Boolean = false,
    /** 保存成功后的 material id（非空表示已保存） */
    val savedId: String = "",
    /** health.capabilities.image != false 才显示「画一张插画」 */
    val imageCapable: Boolean = true,
    /** 账号设置 `auto_illustrate`：开启时保存成功后自动画一张（默认关，开启即知情） */
    val autoIllustrate: Boolean = false,
    val illustrating: Boolean = false,
    val illustrationDone: Boolean = false,
    val illustrationError: String = "",
    /** 插画版本号：RemoteImage 的 URL 加 `?v=` 破除缓存 */
    val imageVersion: Int = 0,
    val error: UiError? = null,
    val retry: StoryRecordRetry = StoryRecordRetry.NONE,
)

/**
 * 新建故事的 ViewModel（对应 hos `StoryRecordVM`，`hos/entry/.../viewmodel/StoryVM.ets`）。
 *
 * 流程（线上降级路径照抄 hos）：
 * 中文打字/录音 → `StoryService.asr(bytes, "zh-CN")` 追加文本 → [rewrite]（`/story/rewrite`，
 * 显示「正在把故事变成英文…」不显示假进度）→ 可编辑标题/句子 → [save]（`POST /materials`）。
 * 503 `story_unavailable` → [manualMode] 打开手动英文输入，保存后同样可连读/复述。
 *
 * 录音在保存时交给 [StoryRuntime] 落盘（原声复制到缓存目录），详情页重进仍可回放「当时的原话」。
 */
class StoryRecordViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(StoryRecordUiState())
    val state: StateFlow<StoryRecordUiState> = _state.asStateFlow()

    private var originalFile: File? = null
    private var timerJob: Job? = null
    private var recordStartedAt = 0L

    init {
        // 会话：儿童/成人文案与默认句数；首次拿到会话后读取账号偏好（story_sentences）
        viewModelScope.launch {
            val session = c.session.state.first()
            val child = session.isChild
            _state.update {
                it.copy(
                    isChild = child,
                    exceeded = session.exceeded,
                    level = StoryText.storyLevelForCefr(session.cefrLevel),
                    maxSentences = if (child) CHILD_DEFAULT_SENTENCES else ADULT_DEFAULT_SENTENCES,
                )
            }
            loadAccountPrefs()
        }
        // 用量/儿童状态变化（进入页面后超限也要禁用录音）
        viewModelScope.launch {
            c.session.state.collect { session ->
                _state.update { it.copy(isChild = session.isChild, exceeded = session.exceeded) }
            }
        }
        loadImageCapability()
    }

    // ------------------------------------------------------------------ 输入 / 选项

    fun setTextZh(value: String) {
        _state.update { it.copy(textZh = value.take(MAX_ZH_CHARS)) }
    }

    /** 改难度：已有结果时按规格自动重新生成（照抄 hos）。 */
    fun selectLevel(value: String) {
        if (value == _state.value.level) return
        _state.update { it.copy(level = value) }
        if (_state.value.hasResult && !_state.value.busy) rewrite()
    }

    fun adjustLevel(direction: Int) {
        val index = LEVELS.indexOf(_state.value.level).let { if (it < 0) 0 else it }
        val next = (index + direction).coerceIn(0, LEVELS.size - 1)
        selectLevel(LEVELS[next])
    }

    fun setMaxSentences(value: Int) {
        if (value in MIN_SENTENCES..MAX_SENTENCES) _state.update { it.copy(maxSentences = value) }
    }

    fun setTense(value: String) {
        if (value in TENSES) _state.update { it.copy(tense = value) }
    }

    fun setUseWeakPhonemes(value: Boolean) {
        if (_state.value.isChild) return
        _state.update { it.copy(useWeakPhonemes = value) }
    }

    // ------------------------------------------------------------------ 录音 / 中文识别

    fun startRecording() {
        val current = _state.value
        if (current.recording || current.preparing || current.busy) return
        if (current.exceeded) {
            setLocalError(ApiErrorCode.DAILY_LIMIT_REACHED, "今天的练习时长已达上限，明天再来 🌙")
            return
        }
        _state.update { it.copy(preparing = true, error = null, notice = "") }
        try {
            c.audio.startRecording("story")
            recordStartedAt = SystemClock.elapsedRealtime()
            _state.update { it.copy(preparing = false, recording = true, elapsedMs = 0L) }
            startTimer()
        } catch (e: Throwable) {
            failAsync(e, StoryRecordRetry.NONE)
        }
    }

    fun stopRecordingAndRecognize() {
        if (!_state.value.recording) return
        stopTimer()
        _state.update { it.copy(recording = false) }
        val result = try {
            c.audio.stopRecording()
        } catch (e: Throwable) {
            failAsync(e, StoryRecordRetry.NONE)
            return
        }
        originalFile = result.file
        recognize(result.file)
    }

    fun cancelRecording() {
        stopTimer()
        _state.update { it.copy(recording = false, elapsedMs = 0L) }
        c.audio.cancelRecording()
    }

    /** 录音已落盘时重试识别（不用重录）。 */
    fun retryRecognize() {
        val file = originalFile ?: return
        if (_state.value.busy) return
        recognize(file)
    }

    private fun recognize(file: File) {
        val bytes = FileUtil.readBytes(file)
        if (bytes == null || bytes.isEmpty()) {
            setLocalError(ApiErrorCode.RECORD_FAILED, "录音文件读不出来，再录一次吧")
            return
        }
        viewModelScope.launch {
            _state.update {
                it.copy(
                    busy = true,
                    busyText = if (it.isChild) "正在听懂你的话… ⏳" else "正在识别中文录音…",
                    error = null,
                    notice = "",
                )
            }
            try {
                val text = c.story.asr(bytes, "zh-CN")
                val current = _state.value.textZh.trim()
                val merged = if (current.isEmpty()) text else current + "\n" + text
                _state.update {
                    it.copy(
                        busy = false,
                        busyText = "",
                        textZh = merged.take(MAX_ZH_CHARS),
                        notice = "听到啦，已经写进上面的框里了 ✅",
                        error = null,
                        retry = StoryRecordRetry.NONE,
                    )
                }
            } catch (e: Throwable) {
                applyError(e, StoryRecordRetry.ASR)
            }
        }
    }

    // ------------------------------------------------------------------ 改写

    fun rewrite() {
        val current = _state.value
        if (current.busy || current.recording) return
        val text = current.textZh.trim()
        if (text.isEmpty()) {
            setLocalError(ApiErrorCode.BAD_REQUEST, if (current.isChild) "先讲讲你的故事吧 🙂" else "请先用中文讲讲你的故事（不能为空）")
            return
        }
        if (text.length > MAX_ZH_CHARS) {
            setLocalError(ApiErrorCode.BAD_REQUEST, "故事太长了（${text.length} 字），最多 $MAX_ZH_CHARS 字")
            return
        }
        _state.update {
            it.copy(
                busy = true,
                busyText = if (it.isChild) "✍️ 正在把故事变成英文… 大约几秒" else "✍️ 正在把你的故事变成英文…",
                notice = "",
                error = null,
                retry = StoryRecordRetry.NONE,
                // 先清旧预览，避免沿用上一次的句子控件
                hasResult = false,
                sentences = emptyList(),
            )
        }
        viewModelScope.launch {
            try {
                val dto = c.story.rewrite(
                    textZh = text,
                    level = _state.value.level,
                    maxSentences = _state.value.maxSentences,
                    tense = _state.value.tense,
                    useWeakPhonemes = _state.value.useWeakPhonemes && !_state.value.isChild,
                )
                applyRewrite(dto)
                _state.update { it.copy(busy = false, busyText = "") }
            } catch (e: Throwable) {
                if (e is ApiError && (e.code == "story_unavailable" || e.status == 503)) {
                    // 503：允许手动写英文（不阻断主流程）
                    val ui = UiError(
                        title = "AI 暂时写不了",
                        message = "可以先自己写英文，保存后一样能连读、复述。",
                        actionLabel = "重试",
                        retryable = true,
                        code = e.code,
                    )
                    _state.update {
                        it.copy(
                            busy = false,
                            busyText = "",
                            manualMode = true,
                            hasResult = false,
                            error = ui,
                            retry = StoryRecordRetry.REWRITE,
                        )
                    }
                } else {
                    applyError(e, StoryRecordRetry.REWRITE)
                }
            }
        }
    }

    private fun applyRewrite(dto: StoryRewriteDto) {
        val items = ArrayList<String>()
        dto.sentences.map { it.trim() }.filter { it.isNotEmpty() }.forEach { items.add(it) }
        if (items.isEmpty()) {
            StoryText.splitSentences(dto.textEn).forEach { items.add(it) }
        }
        val sentences = items.mapIndexed { index, en -> StorySentenceEdit(index + 1, en) }
        if (sentences.isEmpty()) {
            setLocalError(ApiErrorCode.BAD_RESPONSE, "生成结果为空，请重试")
            return
        }
        val readability = dto.readability
        val readabilityText = if (readability == null) {
            ""
        } else {
            val count = if (readability.sentenceCount > 0) readability.sentenceCount else sentences.size
            val avg = Math.round(readability.avgWords * 10) / 10.0
            "可读性：$count 句 · 平均 $avg 词/句 · 最长 ${readability.maxWords} 词"
        }
        val unknownWordsText = if (readability == null || readability.unknownWords.isEmpty()) {
            ""
        } else {
            "可能偏难的词：" + readability.unknownWords.joinToString("、")
        }
        var warningText = ""
        if (dto.warnings.contains("too_hard")) {
            warningText = "这段可能有点难，要不要点「再简单一点」？"
        }
        if (dto.warnings.contains("too_many_sentences")) {
            warningText = "故事偏长（超过设定的句数），可以调高句子数，或删掉几句再保存"
        }
        if (dto.warnings.contains("tense_mismatch")) {
            warningText = "时态可能和中文原意不一致（叙事一般用过去时），可以点「重新生成」再试一次"
        }
        _state.update {
            it.copy(
                hasResult = true,
                manualMode = false,
                title = dto.titleEn.trim().ifEmpty { "My Story" },
                sentences = sentences,
                readabilityText = readabilityText,
                unknownWordsText = unknownWordsText,
                warningText = warningText,
                weakPhonemes = dto.weakPhonemesUsed,
                error = null,
                retry = StoryRecordRetry.NONE,
            )
        }
    }

    fun setTitle(value: String) {
        _state.update { it.copy(title = value) }
    }

    fun setSentenceEn(index: Int, value: String) {
        _state.update { state ->
            if (index !in state.sentences.indices) return@update state
            val next = state.sentences.toMutableList()
            next[index] = next[index].copy(en = value)
            state.copy(sentences = next)
        }
    }

    // ------------------------------------------------------------------ 手动英文（503 兜底）

    fun enterManualMode() {
        _state.update {
            it.copy(manualMode = true, hasResult = false, error = null, retry = StoryRecordRetry.NONE)
        }
    }

    fun setManualTitle(value: String) {
        _state.update { it.copy(manualTitle = value) }
    }

    fun setManualText(value: String) {
        _state.update { it.copy(manualText = value) }
    }

    // ------------------------------------------------------------------ 保存

    /** 保存到家庭书架；成功写 [StoryRecordUiState.savedId]，由页面给出「去连读 / 画一张插画」。 */
    fun save() {
        val current = _state.value
        if (current.saving || current.busy) return
        val title = (if (current.hasResult) current.title else current.manualTitle).trim()
        if (title.isEmpty()) {
            setLocalError(ApiErrorCode.BAD_REQUEST, "给故事起个标题吧")
            return
        }
        val text = when {
            current.hasResult -> current.sentences
                .map { it.en.trim() }
                .filter { it.isNotEmpty() }
                .joinToString("\n")

            current.manualMode -> current.manualText
                .lines()
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .joinToString("\n")

            else -> ""
        }
        if (text.isEmpty()) {
            setLocalError(
                ApiErrorCode.BAD_REQUEST,
                if (current.hasResult) "英文故事不能为空，先点「重新生成」试试" else "先写几句英文再保存",
            )
            return
        }
        val sourceZh = current.textZh.trim()
        viewModelScope.launch {
            _state.update { it.copy(saving = true, error = null, notice = "") }
            try {
                val created = c.story.createMaterial(
                    title = title,
                    text = text,
                    sourceZh = sourceZh,
                    level = _state.value.level,
                )
                originalFile?.takeIf { it.exists() && it.length() > 0 }?.let { file ->
                    // 原声落盘：复制到稳定的缓存文件，避开「上传目录被清」；复制失败就存原路径（详情页会校验可播性）
                    val stable = c.cache.audioFile("story_orig_${created.id}", "m4a")
                    val storedPath = runCatching {
                        file.copyTo(stable, overwrite = true)
                        stable.absolutePath
                    }.getOrDefault(file.absolutePath)
                    StoryRuntime.saveOriginal(c.cache, created.id, sourceZh, storedPath)
                }
                StoryRuntime.notifySaved()
                _state.update {
                    it.copy(saving = false, savedId = created.id, notice = "已保存到家庭书架 ✅")
                }
                // 尊重账号设置：auto_illustrate=true 且能力可用 → 自动画一张（失败不影响已保存的故事）
                maybeAutoIllustrate()
            } catch (e: Throwable) {
                applyError(e, StoryRecordRetry.SAVE)
            }
        }
    }

    /** 保存成功后的自动插图（第二轮）；设置默认关，开启时页面会先显示「正在生成插画…」。 */
    private fun maybeAutoIllustrate() {
        val current = _state.value
        if (!current.autoIllustrate) return
        // 能力开关优先读 `CapabilityCache` 的最新缓存（没有缓存则用 VM 初始化时解析的结果）
        val cachedImage = runCatching { c.capability.cached() }.getOrNull()?.image
        val imageOk = cachedImage ?: current.imageCapable
        if (!imageOk) {
            _state.update {
                it.copy(imageCapable = false, illustrationError = "插画服务暂未启用，未自动生成插画")
            }
            return
        }
        if (!current.imageCapable) {
            _state.update { it.copy(imageCapable = true) }
        }
        illustrate()
    }

    // ------------------------------------------------------------------ 插画（保存后）

    fun illustrate() {
        val current = _state.value
        if (current.savedId.isEmpty() || current.illustrating || !current.imageCapable) return
        _state.update { it.copy(illustrating = true, illustrationError = "") }
        viewModelScope.launch {
            try {
                c.story.illustrate(current.savedId, force = false)
                _state.update {
                    it.copy(
                        illustrating = false,
                        illustrationDone = true,
                        imageVersion = it.imageVersion + 1,
                    )
                }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(illustrating = false, illustrationError = ui.message) }
            }
        }
    }

    /** 只重新拉取已生成的插画（不重新生成、不扣费）。 */
    fun reloadIllustration() {
        if (!_state.value.illustrationDone) return
        _state.update { it.copy(illustrationError = "", imageVersion = it.imageVersion + 1) }
    }

    // ------------------------------------------------------------------ 错误 / 重试

    fun retry() {
        val retry = _state.value.retry
        clearError()
        when (retry) {
            StoryRecordRetry.ASR -> retryRecognize()
            StoryRecordRetry.REWRITE -> rewrite()
            StoryRecordRetry.SAVE -> save()
            StoryRecordRetry.NONE -> Unit
        }
    }

    fun clearError() {
        _state.update { it.copy(error = null, retry = StoryRecordRetry.NONE) }
    }

    private fun setLocalError(code: String, message: String) {
        _state.update { it.copy(error = UiError.of(code, message, false), retry = StoryRecordRetry.NONE) }
    }

    private suspend fun applyError(err: Throwable, retry: StoryRecordRetry) {
        val ui = c.session.toUiErrorAsync(err)
        _state.update {
            it.copy(
                busy = false,
                busyText = "",
                preparing = false,
                recording = false,
                saving = false,
                error = ui,
                retry = retry,
            )
        }
    }

    private fun failAsync(err: Throwable, retry: StoryRecordRetry) {
        viewModelScope.launch { applyError(err, retry) }
    }

    // ------------------------------------------------------------------ 内部

    private fun loadAccountPrefs() {
        viewModelScope.launch {
            runCatching { c.account.settings() }.getOrNull()?.let { settings ->
                val user = settings.user
                val count = user?.storySentences ?: 0
                _state.update {
                    it.copy(
                        maxSentences = if (count in MIN_SENTENCES..MAX_SENTENCES) count else it.maxSentences,
                        autoIllustrate = user?.autoIllustrate == true,
                    )
                }
            }
        }
    }

    /** 能力开关统一走 `CapabilityCache`（第二轮）；拿不到时默认允许，避免误伤功能。 */
    private fun loadImageCapability() {
        viewModelScope.launch {
            val cached = runCatching { c.capability.cached() }.getOrNull()
            if (cached != null) {
                _state.update { it.copy(imageCapable = cached.image) }
                return@launch
            }
            val image = runCatching { c.capability.refresh() }.getOrNull()?.image ?: true
            _state.update { it.copy(imageCapable = image) }
        }
    }

    private fun startTimer() {
        stopTimer()
        timerJob = viewModelScope.launch {
            while (isActive) {
                val elapsed = SystemClock.elapsedRealtime() - recordStartedAt
                _state.update { it.copy(elapsedMs = elapsed) }
                if (elapsed >= MAX_RECORD_MS) {
                    stopRecordingAndRecognize()
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
        /** 中文故事稿上限（与 Web/鸿蒙一致） */
        const val MAX_ZH_CHARS = 2000

        /** 中文讲述录音上限：120s（听故事比跟读句子长） */
        const val MAX_RECORD_MS = 120_000L

        val LEVELS: List<String> = listOf("A1", "A2", "B1", "B2", "C1")
        val TENSES: List<String> = listOf("auto", "past", "present")
        private const val MIN_SENTENCES = 3
        private const val MAX_SENTENCES = 12
        private const val CHILD_DEFAULT_SENTENCES = 5
        private const val ADULT_DEFAULT_SENTENCES = 8
    }
}

package top.dreamsearch.englishcoach.ui.page.story

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.util.FileUtil
import top.dreamsearch.englishcoach.ui.nav.NavParams
import java.io.File

/** 详情页的一句英文。 */
data class StorySentenceItem(val index: Int, val en: String)

const val STORY_AUDIO_CHECKING = "checking"
const val STORY_AUDIO_BUILDING = "building"
const val STORY_AUDIO_READY = "ready"
const val STORY_AUDIO_FAILED = "failed"
const val STORY_AUDIO_NONE = "no_audio"

data class StoryDetailUiState(
    val loading: Boolean = true,
    val error: UiError? = null,
    val isChild: Boolean = false,
    val storyId: String = "",
    val title: String = "",
    val level: String = "",
    val dateText: String = "",
    val sentenceCount: Int = 0,
    val authorName: String = "",
    val sentences: List<StorySentenceItem> = emptyList(),
    val sourceZh: String = "",
    val hasSourceZh: Boolean = false,
    val showSource: Boolean = false,
    val hasImage: Boolean = false,
    val imageVersion: Int = 0,
    val imagePrompt: String = "",
    val showPrompt: Boolean = false,
    val imageLoading: Boolean = false,
    val imageError: String = "",
    val imageCapable: Boolean = true,
    val canEdit: Boolean = false,
    /** checking | building | ready | failed | no_audio */
    val audioState: String = STORY_AUDIO_CHECKING,
    val audioStatusText: String = "",
    val audioDurationText: String = "",
    val audioLoading: Boolean = false,
    val audioPlaying: Boolean = false,
    val audioError: String = "",
    /** 正在朗读的句子下标；-1 = 没在播 */
    val playingSentenceIndex: Int = -1,
    /** 正在取 TTS 的句子下标；-1 = 空闲 */
    val ttsLoadingIndex: Int = -1,
    val originalPath: String = "",
    val originalText: String = "",
    val originalPlaying: Boolean = false,
    /** 本机保存的「最近一次复述」（服务端无历史接口；杀进程后仍在） */
    val lastRetell: StoryRuntime.RetellRecord? = null,
    /** 本机是否有可清除的记录（原声路径或复述记录） */
    val hasLocalRecords: Boolean = false,
    val confirmClearRecords: Boolean = false,
    val recordsNotice: String = "",
    /** building 超过阈值（约 30s）→ 页面给「重新生成」 */
    val audioSlow: Boolean = false,
    val renaming: Boolean = false,
    val renameText: String = "",
    val renameSaving: Boolean = false,
    val confirmDelete: Boolean = false,
    val deleting: Boolean = false,
    val actionError: String = "",
    val deleted: Boolean = false,
)

/**
 * 故事详情的 ViewModel（对应 hos `StoryDetailVM`）。
 *
 * 数据来源：`StoryService.materialDetail(id)`（id 由 [NavParams.storyMaterialId] 传入，读完清空）。
 * 能力点：
 * - 逐句朗读：`PracticeService.tts` → 落 `CacheStore.tts` → `AudioController.playFile`（顺带预取下一句）；
 * - 整段朗读回放：`audioStatus` 只读检查（building 每 2s 轮询，最多 30 次；**超过约 30s** 给「重新生成」）
 *   → `storyAudio` 取字节落盘再播；
 * - 插画：`RemoteImage("/materials/{id}/image", withAuth=true)`；`illustrate(force)` 换一张（有费用提示）；
 * - 原声回顾 + 上次复述：读 [StoryRuntime] 落盘的 JSON（原声文件丢失时只隐藏回放、保留中文原文），
 *   并提供「清除本机记录」；
 * - 复制全文：标题 + 逐句英文（可选中文对照）；
 * - 改名/删除：仅 creator/parent（服务端 403 兜底）。
 *
 * 不显示任何发音分；儿童隐藏提示词等技术细节。
 */
class StoryDetailViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(StoryDetailUiState())
    val state: StateFlow<StoryDetailUiState> = _state.asStateFlow()

    private var userId: String = ""
    private var role: String = ""
    private var isChild: Boolean = false
    private var createdById: String = ""
    private var audioPollJob: Job? = null

    init {
        val materialId = NavParams.storyMaterialId.orEmpty()
        NavParams.storyMaterialId = null

        viewModelScope.launch {
            c.session.state.collect { session ->
                userId = session.userId
                role = session.role
                isChild = session.isChild
                _state.update { it.copy(isChild = session.isChild) }
                recomputeCanEdit()
            }
        }
        viewModelScope.launch {
            StoryRuntime.retellTick.collect { tick ->
                if (tick > 0) {
                    _state.update {
                        val snapshot = StoryRuntime.load(c.cache, it.storyId)
                        it.copy(
                            lastRetell = snapshot.retell,
                            hasLocalRecords = snapshot.originalPath.isNotEmpty() || snapshot.retell != null,
                        )
                    }
                }
            }
        }
        loadCapabilities()

        if (materialId.isEmpty()) {
            _state.update {
                it.copy(
                    loading = false,
                    error = UiError.of("not_found", "没有找到这个故事，回到故事集重新打开试试", false),
                )
            }
        } else {
            load(materialId)
        }
    }

    // ------------------------------------------------------------------ 加载

    fun load(id: String) {
        if (id.isEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(storyId = id, loading = true, error = null) }
            try {
                val dto = c.story.materialDetail(id)
                createdById = dto.createdBy.orEmpty()
                val sentences = StoryText.splitSentences(dto.text)
                    .mapIndexed { index, en -> StorySentenceItem(index + 1, en) }
                // 本机记录：原声路径（校验可播）+ source_zh 兜底 + 最近一次复述
                val snapshot = StoryRuntime.load(c.cache, id)
                val original = StoryRuntime.original(c.cache, id)
                val storedSourceZh = snapshot.sourceZh
                val sourceZh = dto.sourceZh?.takeIf { it.isNotBlank() } ?: storedSourceZh
                _state.update {
                    it.copy(
                        loading = false,
                        error = null,
                        title = dto.title.trim().ifEmpty { "未命名故事" },
                        level = dto.level.orEmpty(),
                        dateText = StoryText.dateTextOf(dto.createdAt),
                        sentenceCount = if (dto.sentenceCount > 0) dto.sentenceCount else sentences.size,
                        authorName = dto.createdByName,
                        sentences = sentences,
                        sourceZh = sourceZh,
                        hasSourceZh = dto.hasSourceZh || sourceZh.isNotBlank(),
                        hasImage = dto.hasImage || !dto.imageUrl.isNullOrBlank(),
                        imagePrompt = dto.imagePrompt.orEmpty(),
                        // 文件被清（换机/清缓存）时隐藏回放，但保留中文原文
                        originalPath = if (original?.playable == true) original.path else "",
                        originalText = original?.textZh ?: storedSourceZh,
                        lastRetell = snapshot.retell,
                        hasLocalRecords = snapshot.originalPath.isNotEmpty() || snapshot.retell != null,
                        audioSlow = false,
                    )
                }
                recomputeCanEdit()
                checkAudio(reset = false)
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(loading = false, error = ui) }
            }
        }
    }

    fun retryLoad() {
        val id = _state.value.storyId
        if (id.isNotEmpty()) load(id)
    }

    private fun loadCapabilities() {
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

    private fun recomputeCanEdit() {
        val canEdit = createdById.isNotEmpty() && (createdById == userId || role == "parent")
        _state.update { it.copy(canEdit = canEdit) }
    }

    // ------------------------------------------------------------------ 展开/收起

    fun toggleSource() {
        _state.update { it.copy(showSource = !it.showSource) }
    }

    fun togglePrompt() {
        _state.update { it.copy(showPrompt = !it.showPrompt) }
    }

    // ------------------------------------------------------------------ 整段朗读回放

    private fun checkAudio(reset: Boolean) {
        val id = _state.value.storyId
        if (id.isEmpty()) return
        audioPollJob?.cancel()
        if (reset) {
            _state.update {
                it.copy(
                    audioState = STORY_AUDIO_CHECKING,
                    audioStatusText = "正在检查朗读录音…",
                    audioSlow = false,
                )
            }
        }
        audioPollJob = viewModelScope.launch {
            var polls = 0
            while (isActive) {
                val keepPolling = fetchAudioStatus(id)
                if (!keepPolling) return@launch
                polls++
                // building 太久（约 30s）→ 给「重新生成」，但仍继续轮询；成功后自动消失
                if (polls == AUDIO_SLOW_POLLS) {
                    _state.update { it.copy(audioSlow = true) }
                }
                if (polls > MAX_AUDIO_POLLS) {
                    _state.update {
                        it.copy(
                            audioState = STORY_AUDIO_FAILED,
                            audioStatusText = "生成超时了，可以点「重新生成」再试",
                            audioSlow = false,
                        )
                    }
                    return@launch
                }
                delay(AUDIO_POLL_INTERVAL_MS)
            }
        }
    }

    /** 拉一次 status；返回 true 表示还在 building，需要继续轮询。 */
    private suspend fun fetchAudioStatus(id: String): Boolean {
        return try {
            val dto = c.story.audioStatus(id)
            val status = dto.status.ifEmpty { STORY_AUDIO_BUILDING }
            when (status) {
                STORY_AUDIO_READY -> {
                    val durationText = if (dto.durationMs > 0) {
                        "时长 ${Math.round(dto.durationMs / 1000.0).toInt()} 秒"
                    } else {
                        ""
                    }
                    _state.update {
                        it.copy(
                            audioState = STORY_AUDIO_READY,
                            audioDurationText = durationText,
                            audioStatusText = if (isChild) "听一听我读的故事" else "整段朗读回放",
                            audioSlow = false,
                        )
                    }
                    false
                }

                STORY_AUDIO_BUILDING -> {
                    _state.update {
                        it.copy(
                            audioState = STORY_AUDIO_BUILDING,
                            audioStatusText = "正在生成整段回放…（可以先看文字）",
                        )
                    }
                    true
                }

                STORY_AUDIO_FAILED -> {
                    if (dto.attemptCount == 0) {
                        // 服务端对「没有任何朗读录音」的故事也回 failed：没有源，不给「重新生成」
                        _state.update {
                            it.copy(
                                audioState = STORY_AUDIO_NONE,
                                audioStatusText = if (isChild) {
                                    "先读一遍这个故事，才能听整段朗读哦"
                                } else {
                                    "这个故事还没有可回放的朗读录音，先读一遍再来听吧"
                                },
                                audioSlow = false,
                            )
                        }
                    } else {
                        _state.update {
                            it.copy(
                                audioState = STORY_AUDIO_FAILED,
                                audioStatusText = dto.error.ifEmpty { "整段朗读生成失败了，可以点「重新生成」" },
                                audioSlow = false,
                            )
                        }
                    }
                    false
                }

                else -> {
                    _state.update {
                        it.copy(
                            audioState = STORY_AUDIO_NONE,
                            audioStatusText = dto.error.ifEmpty { "这个故事还没有可回放的朗读录音，先读一遍再来听吧" },
                            audioSlow = false,
                        )
                    }
                    false
                }
            }
        } catch (e: Throwable) {
            val ui = c.session.toUiErrorAsync(e)
            _state.update { it.copy(audioState = STORY_AUDIO_FAILED, audioStatusText = ui.message) }
            false
        }
    }

    fun playAudio() {
        val current = _state.value
        if (current.audioLoading || current.storyId.isEmpty()) return
        if (current.audioState != STORY_AUDIO_READY) return
        stopLocalPlayback()
        _state.update { it.copy(audioLoading = true, audioError = "") }
        viewModelScope.launch {
            val id = _state.value.storyId
            try {
                val file = c.cache.audioFile("story_${id}_read", "wav")
                if (!file.exists() || file.length() <= 0L) {
                    val bytes = c.story.storyAudio(id, force = false)
                    if (bytes == null) {
                        _state.update {
                            it.copy(
                                audioLoading = false,
                                audioState = STORY_AUDIO_BUILDING,
                                audioStatusText = "正在生成整段回放…（可以先看文字）",
                            )
                        }
                        checkAudio(reset = false)
                        return@launch
                    }
                    FileUtil.writeBytesAtomic(file, bytes)
                }
                _state.update { it.copy(audioLoading = false, audioPlaying = true) }
                c.audio.playFile(file) {
                    _state.update { state -> state.copy(audioPlaying = false) }
                }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update {
                    it.copy(
                        audioLoading = false,
                        audioPlaying = false,
                        audioError = ui.message,
                        audioState = STORY_AUDIO_FAILED,
                        audioStatusText = ui.message,
                    )
                }
            }
        }
    }

    /** failed 时先 `GET /story/:id/audio?force=1` 触发重建，再回落到 status 轮询。 */
    fun retryAudio() {
        val current = _state.value
        if (current.storyId.isEmpty()) return
        stopLocalPlayback()
        _state.update {
            it.copy(
                audioState = STORY_AUDIO_BUILDING,
                audioStatusText = "正在重新生成整段朗读…",
                audioError = "",
                audioSlow = false,
            )
        }
        viewModelScope.launch {
            val id = _state.value.storyId
            try {
                val file = c.cache.audioFile("story_${id}_read", "wav")
                if (file.exists()) file.delete()
                val bytes = c.story.storyAudio(id, force = true)
                if (bytes != null) {
                    FileUtil.writeBytesAtomic(file, bytes)
                    _state.update {
                        it.copy(
                            audioState = STORY_AUDIO_READY,
                            audioStatusText = if (isChild) "听一听我读的故事" else "整段朗读回放",
                        )
                    }
                    return@launch
                }
            } catch (ignored: Throwable) {
                // force 重建失败（no_audio / audio_failed）→ 交给 status 给出可读提示
            }
            checkAudio(reset = true)
        }
    }

    // ------------------------------------------------------------------ 逐句朗读

    fun playSentence(index: Int) {
        val current = _state.value
        val sentence = current.sentences.getOrNull(index) ?: return
        if (current.ttsLoadingIndex >= 0) return
        stopLocalPlayback()
        _state.update { it.copy(ttsLoadingIndex = index, audioError = "") }
        viewModelScope.launch {
            try {
                val file = ttsFileFor(sentence.en)
                if (!file.exists() || file.length() <= 0L) {
                    val bytes = c.practice.tts(
                        text = sentence.en,
                        rate = ttsRate(),
                        voice = null,
                        format = "wav",
                    )
                    FileUtil.writeBytesAtomic(file, bytes)
                }
                _state.update { it.copy(ttsLoadingIndex = -1, playingSentenceIndex = index) }
                c.audio.playFile(file) {
                    _state.update { state ->
                        if (state.playingSentenceIndex == index) state.copy(playingSentenceIndex = -1) else state
                    }
                }
                prefetchSentence(index + 1)
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(ttsLoadingIndex = -1, playingSentenceIndex = -1, audioError = ui.message) }
            }
        }
    }

    /** 预取下一句 TTS（失败静默，不打扰阅读）。 */
    private fun prefetchSentence(index: Int) {
        val sentence = _state.value.sentences.getOrNull(index) ?: return
        viewModelScope.launch {
            runCatching {
                val file = ttsFileFor(sentence.en)
                if (!file.exists() || file.length() <= 0L) {
                    val bytes = c.practice.tts(
                        text = sentence.en,
                        rate = ttsRate(),
                        voice = null,
                        format = "wav",
                    )
                    FileUtil.writeBytesAtomic(file, bytes)
                }
            }
        }
    }

    private fun ttsFileFor(text: String): File =
        c.cache.ttsFile("story_tts_${ttsRate()}_" + text)

    private fun ttsRate(): String = if (isChild) "slow" else "normal"

    // ------------------------------------------------------------------ 原声回顾

    fun playOriginal() {
        val path = _state.value.originalPath
        if (path.isEmpty()) return
        val file = File(path)
        if (!file.exists()) {
            _state.update { it.copy(audioError = "本次录音已经不在了，重新讲一次故事吧") }
            return
        }
        stopLocalPlayback()
        _state.update { it.copy(originalPlaying = true, audioError = "") }
        try {
            c.audio.playFile(file) {
                _state.update { state -> state.copy(originalPlaying = false) }
            }
        } catch (e: Throwable) {
            _state.update { it.copy(originalPlaying = false) }
            viewModelScope.launch {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(audioError = ui.message) }
            }
        }
    }

    private fun stopLocalPlayback() {
        c.audio.stopPlayback()
        _state.update {
            it.copy(audioPlaying = false, originalPlaying = false, playingSentenceIndex = -1)
        }
    }

    /** 页面上的「停止播放」（整段/逐句/原声共用一个播放器）。 */
    fun stopPlayback() {
        stopLocalPlayback()
    }

    // ------------------------------------------------------------------ 插画

    fun illustrate(force: Boolean) {
        val current = _state.value
        if (current.imageLoading || current.storyId.isEmpty()) return
        if (!force && current.hasImage) return
        if (!current.imageCapable) return
        _state.update { it.copy(imageLoading = true, imageError = "") }
        viewModelScope.launch {
            try {
                val dto = c.story.illustrate(current.storyId, force)
                _state.update {
                    it.copy(
                        imageLoading = false,
                        hasImage = true,
                        imageVersion = it.imageVersion + 1,
                        imagePrompt = dto.promptUsed.ifEmpty { it.imagePrompt },
                        imageError = "",
                    )
                }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(imageLoading = false, imageError = ui.message) }
            }
        }
    }

    /** 只重新下载已有插画（不触发生成、不扣费）。 */
    fun reloadImage() {
        if (!_state.value.hasImage) return
        _state.update { it.copy(imageError = "", imageVersion = it.imageVersion + 1) }
    }

    // ------------------------------------------------------------------ 复制全文 / 本机记录

    /** 「复制全文」：标题 + 逐句英文；详情页开了中文对照时附带 `source_zh`（第二位轮）。 */
    fun copyText(): String {
        val s = _state.value
        val builder = StringBuilder()
        if (s.title.isNotBlank()) builder.append(s.title).append("\n\n")
        s.sentences.forEach { builder.append(it.index).append(". ").append(it.en).append('\n') }
        if (s.showSource && s.hasSourceZh && s.sourceZh.isNotBlank()) {
            builder.append("\n【中文原文】\n").append(s.sourceZh).append('\n')
        }
        return builder.toString().trim()
    }

    fun askClearRecords() {
        if (!_state.value.hasLocalRecords) return
        _state.update { it.copy(confirmClearRecords = true, recordsNotice = "") }
    }

    fun cancelClearRecords() {
        _state.update { it.copy(confirmClearRecords = false) }
    }

    /** 清除本机保存的原声/复述记录；服务端故事不变，中文原文仍来自 story 详情。 */
    fun clearRecords() {
        val current = _state.value
        if (current.storyId.isEmpty()) return
        StoryRuntime.clear(c.cache, current.storyId)
        _state.update {
            it.copy(
                confirmClearRecords = false,
                originalPath = "",
                lastRetell = null,
                hasLocalRecords = false,
                recordsNotice = "已清除本机记录（服务端故事不受影响）",
            )
        }
    }

    // ------------------------------------------------------------------ 改名 / 删除

    fun startRename() {
        val current = _state.value
        if (!current.canEdit) return
        _state.update { it.copy(renaming = true, renameText = current.title, actionError = "") }
    }

    fun cancelRename() {
        _state.update { it.copy(renaming = false, actionError = "") }
    }

    fun setRenameText(value: String) {
        _state.update { it.copy(renameText = value) }
    }

    fun saveRename() {
        val current = _state.value
        if (current.renameSaving) return
        val title = current.renameText.trim()
        if (title.isEmpty()) {
            _state.update { it.copy(actionError = "标题不能为空") }
            return
        }
        _state.update { it.copy(renameSaving = true, actionError = "") }
        viewModelScope.launch {
            try {
                c.story.renameMaterial(current.storyId, title)
                StoryRuntime.notifySaved()
                _state.update { it.copy(renameSaving = false, renaming = false, title = title) }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(renameSaving = false, actionError = ui.message) }
            }
        }
    }

    fun askDelete() {
        if (!_state.value.canEdit) return
        _state.update { it.copy(confirmDelete = true, actionError = "") }
    }

    fun cancelDelete() {
        _state.update { it.copy(confirmDelete = false) }
    }

    fun delete() {
        val current = _state.value
        if (current.deleting || current.storyId.isEmpty()) return
        _state.update { it.copy(deleting = true, actionError = "") }
        viewModelScope.launch {
            try {
                c.story.deleteMaterial(current.storyId)
                StoryRuntime.clear(c.cache, current.storyId)
                StoryRuntime.notifySaved()
                _state.update { it.copy(deleting = false, confirmDelete = false, deleted = true) }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(deleting = false, confirmDelete = false, actionError = ui.message) }
            }
        }
    }

    override fun onCleared() {
        audioPollJob?.cancel()
        c.audio.stopPlayback()
        super.onCleared()
    }

    companion object {
        private const val MAX_AUDIO_POLLS = 30
        private const val AUDIO_POLL_INTERVAL_MS = 2_000L
        /** building 超过约 30 秒 → 页面给「重新生成」 */
        private const val AUDIO_SLOW_POLLS = 15
    }
}

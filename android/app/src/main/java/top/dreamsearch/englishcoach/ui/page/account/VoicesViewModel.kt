package top.dreamsearch.englishcoach.ui.page.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.audio.TtsVoice
import top.dreamsearch.englishcoach.core.audio.Voices
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.dto.SettingsPatchBodyDto
import top.dreamsearch.englishcoach.core.util.FileUtil

/**
 * 音色 VM（对应 hos `VoicesVM`，`hos/entry/.../viewmodel/AccountVM.ets` L1490-1596）。
 *
 * 数据来源：
 * - 清单 = **内置 9 音色常量** [Voices.ALL]（`GET /api/tts/voices` 线上 404，不请求）；
 * - 当前值 = `GET /api/settings` 的 `prefs.ttsVoice / prefs.ttsRate`；
 * - 试听 = `POST /api/tts`（mp3，voice=id）→ 落缓存 → `AudioController.playFile`；
 * - 保存 = `PATCH /api/settings {tts_voice}`（空 id → null = 恢复 provider 默认）。
 *
 * 状态：loading（首屏）/ error + 重试 / 试听中 / 保存中 / 保存失败（含 PATCH 不支持的可读提示）。
 */
data class VoicesUiState(
    val loading: Boolean = true,
    val loadedOnce: Boolean = false,
    val error: UiError? = null,
    val isChild: Boolean = false,
    /** '' = 默认音色（provider 决定，服务端存 null） */
    val currentVoice: String = "",
    /** slow | normal */
    val rate: String = "normal",
    /** 正在试听的音色 id（空 = 没在试听） */
    val previewingId: String = "",
    val previewLoading: Boolean = false,
    val previewError: String = "",
    val saving: Boolean = false,
    val notice: String = "",
    val saveError: String = "",
)

class VoicesViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(VoicesUiState())
    val state: StateFlow<VoicesUiState> = _state.asStateFlow()

    val englishVoices: List<TtsVoice> = Voices.ALL.filter { it.isEnglish }
    val chineseVoices: List<TtsVoice> = Voices.ALL.filter { !it.isEnglish }

    init {
        // 儿童 → 默认语速 slow / 文案差异
        viewModelScope.launch {
            c.session.state.collect { session ->
                _state.update { it.copy(isChild = session.isChild) }
            }
        }
        load()
    }

    fun load() {
        _state.update { it.copy(loading = !it.loadedOnce, error = null) }
        viewModelScope.launch {
            try {
                val dto = c.account.settings()
                val prefs = dto.prefs
                val savedVoice = prefs?.ttsVoice.orEmpty()
                val savedRate = prefs?.ttsRate.orEmpty()
                val isChild = _state.value.isChild
                val resolvedRate = savedRate.ifEmpty { if (isChild) "slow" else "normal" }
                // 本机语音镜像与账号偏好对齐（示范音/对话朗读统一走 voicePrefs.resolve）
                c.voicePrefs.syncFromAccount(savedVoice.takeIf { it.isNotEmpty() }, resolvedRate)
                _state.update {
                    it.copy(
                        loading = false,
                        loadedOnce = true,
                        error = null,
                        currentVoice = savedVoice,
                        rate = resolvedRate,
                    )
                }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(loading = false, loadedOnce = true, error = c.session.toUiErrorAsync(e))
                }
            }
        }
    }

    fun retry() = load()

    fun clearNotice() = _state.update { it.copy(notice = "", saveError = "", previewError = "") }

    /**
     * 试听 / 再点一次停止。
     *
     * 先 `POST /tts` 拿 mp3 字节（失败给可读文案）→ 落 `cacheDir/audio` → `AudioController.playFile`
     * 播放；**播完的回调里复位**「试听中」（不用监听 playing，避免新一次播放开始瞬间被旧回调清掉）。
     */
    fun togglePreview(voice: TtsVoice) {
        val s = _state.value
        if (s.previewingId == voice.id) {
            stopPreview()
            return
        }
        if (s.previewLoading) return
        viewModelScope.launch {
            _state.update {
                it.copy(previewingId = voice.id, previewLoading = true, previewError = "", notice = "")
            }
            try {
                val bytes = c.practice.tts(
                    text = voice.sample,
                    rate = _state.value.rate,
                    voice = voice.id,
                    format = "mp3",
                )
                val file = c.cache.audioFile("voice_preview_${voice.id}", "mp3")
                FileUtil.writeBytesAtomic(file, bytes)
                c.audio.playFile(file) {
                    _state.update { current ->
                        if (current.previewingId == voice.id) current.copy(previewingId = "") else current
                    }
                }
                _state.update { it.copy(previewLoading = false) }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(
                        previewLoading = false,
                        previewingId = "",
                        previewError = c.session.toUiErrorAsync(e).message,
                    )
                }
            }
        }
    }

    /** 停止试听（切音色 / 离页时调用；本页只有试听一种播放，直接停播放器）。 */
    fun stopPreview() {
        c.audio.stopPlayback()
        _state.update { it.copy(previewingId = "", previewLoading = false) }
    }

    /** 保存音色偏好；[voiceId] 空串 = 恢复默认（服务端存 null）。 */
    fun save(voiceId: String) {
        val s = _state.value
        if (s.saving) return
        viewModelScope.launch {
            _state.update { it.copy(saving = true, notice = "", saveError = "") }
            try {
                if (voiceId.isEmpty()) {
                    // 「恢复默认音色」= 服务端存 null。`SettingsPatchBodyDto(ttsVoice = null)` 会被
                    // EcJson 的 explicitNulls=false 丢掉，服务端按「未传=不改」处理，所以这里直接下发裸 JSON
                    // （与 hos `VoicesVM.save('')` 的 JSON.stringify 行为一致）。
                    val raw = c.api.patchJson("/settings", "{\"tts_voice\":null}", 30_000L)
                    c.api.requireOk(raw)
                } else {
                    c.account.patchSettings(SettingsPatchBodyDto(ttsVoice = voiceId))
                }
                _state.update {
                    it.copy(saving = false, currentVoice = voiceId, notice = "已保存音色偏好 ✅")
                }
                // 同步本机语音镜像：示范音/对话朗读下一次调用立即用新音色（ROUND2 §1.2）
                c.voicePrefs.syncFromAccount(voiceId.takeIf { it.isNotEmpty() }, _state.value.rate)
                // 用服务端最新值再校正一次（PATCH 返回的是瘦身 user，不解析它）
                load()
            } catch (e: Throwable) {
                val apiError = e as? ApiError
                val unsupported = apiError != null && (
                    apiError.status == 405 || apiError.status == 501 ||
                        (apiError.status == 0 &&
                            (apiError.detail.contains("patch", ignoreCase = true) ||
                                apiError.detail.contains("method", ignoreCase = true)))
                    )
                val message = if (unsupported) {
                    "该设置暂不可用（当前服务器不支持保存偏好）"
                } else {
                    c.session.toUiErrorAsync(e).message
                }
                _state.update { it.copy(saving = false, saveError = message) }
            }
        }
    }

    /** 音色中文名（列表里存的是 id，展示用这个；未知 id 原样显示）。 */
    fun labelOf(voiceId: String): String {
        if (voiceId.isEmpty()) return "默认音色（provider 决定）"
        return Voices.find(voiceId)?.labelZh ?: voiceId
    }
}

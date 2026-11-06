package top.dreamsearch.englishcoach.ui.page.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.audio.Voices
import top.dreamsearch.englishcoach.core.config.AppConfig
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.dto.HealthCapabilitiesDto
import top.dreamsearch.englishcoach.core.net.dto.HealthFeaturesDto

/**
 * 服务状态页（`ui/page/account/HealthScreen.kt` 专用）。
 *
 * 数据来源（ROUND2 §4-③）：
 * - 基础状态：`PracticeService.health(force)`（`GET /api/health[?force=1]`，无需登录，5s 超时）——
 *   status/service/version/time + db + voice.reachable/mode/capabilities；
 * - web 构建特性：`StatsService.healthFull(force)`（同一端点全字段版）的 **`features` 列表**，
 *   与 capabilities 分成两块展示；两个请求**分别兜底**（一个失败不影响另一块）；
 * - 当前生效音色：`voicePrefs.resolve(isChild)`（账号偏好本机镜像，ROUND2 §1.2）。
 *
 * 判定顺序（照抄 hos HealthPage / account-misc §7.3）：
 * DB 异常 → 红色「服务异常」；voice 不可达 → 琥珀提示；否则绿色「服务正常」。
 *
 * 「强制刷新」= `force=true` → 服务端跳过 15s 缓存并重新探测 voice。
 */
data class HealthUiState(
    val loading: Boolean = false,
    val loaded: Boolean = false,
    /** 本次是否为强制刷新（跳过服务端缓存） */
    val forcing: Boolean = false,
    val error: UiError? = null,
    // /health 基本信息
    val status: String = "",
    val service: String = "",
    val version: String = "",
    val serverTime: String = "",
    // 数据库
    val dbOk: Boolean = false,
    val dbError: String = "",
    // 语音服务
    val voiceReachable: Boolean = false,
    val voiceMode: String = "",
    val voiceHint: String = "",
    val capabilities: HealthCapabilitiesDto? = null,
    // web 构建特性（stats.healthFull 的 features；与 capabilities 分开兜底）
    val features: List<Pair<String, Boolean>> = emptyList(),
    val featuresLoaded: Boolean = false,
    val featuresError: String = "",
    // 当前生效音色（voicePrefs.resolve 的结果）
    val effectiveVoiceLabel: String = "",
    val effectiveRate: String = "",
    // 客户端信息
    val baseUrl: String = "",
    val appVersion: String = AppConfig.APP_VERSION,
    val tokenDegraded: Boolean = false,
) {
    /** ok / warn / bad；未加载完成时按 ok 处理（页面不会在未加载时展示状态卡）。 */
    val level: String
        get() = when {
            !loaded -> "ok"
            !dbOk -> "bad"
            !voiceReachable -> "warn"
            else -> "ok"
        }
}

class HealthViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(HealthUiState())
    val state: StateFlow<HealthUiState> = _state.asStateFlow()

    init {
        _state.update {
            it.copy(
                baseUrl = c.config.baseUrl,
                tokenDegraded = c.tokenStore.degraded,
                effectiveVoiceLabel = effectiveVoiceLabel(),
                effectiveRate = c.voicePrefs.resolve(c.session.state.value.isChild).rate,
            )
        }
        load()
    }

    /**
     * 拉取服务状态。
     *
     * @param force true = 强制刷新（`?force=1`，跳过服务端缓存 + 重新探测 voice）
     */
    fun load(force: Boolean = false) {
        if (_state.value.loading) return
        viewModelScope.launch {
            _state.update { it.copy(loading = true, forcing = force, error = null) }
            // 两块数据并行且各自兜底：基础状态失败不吞掉 features，反之亦然
            val basicDeferred = async { runCatching { c.practice.health(force = force) } }
            val featuresDeferred = async { runCatching { c.stats.healthFull(force = force) } }
            val basic = basicDeferred.await()
            val featuresResult = featuresDeferred.await()

            val basicError = basic.exceptionOrNull()
            if (basicError is CancellationException) throw basicError
            val featuresFailure = featuresResult.exceptionOrNull()
            if (featuresFailure is CancellationException) throw featuresFailure
            basic.getOrNull()?.let { health ->
                val voice = health.voice
                val db = health.db
                _state.update {
                    it.copy(
                        loaded = true,
                        error = null,
                        status = health.status,
                        service = health.service,
                        version = health.version,
                        serverTime = health.time,
                        dbOk = db?.ok == true,
                        dbError = db?.error.orEmpty(),
                        voiceReachable = voice?.reachable == true,
                        voiceMode = voice?.mode.orEmpty(),
                        voiceHint = voice?.hint.orEmpty(),
                        capabilities = voice?.capabilities,
                    )
                }
            }
            val full = featuresResult.getOrNull()
            if (full != null) {
                _state.update {
                    it.copy(
                        features = featureLines(full.features),
                        featuresLoaded = true,
                        featuresError = "",
                    )
                }
            } else {
                _state.update {
                    it.copy(
                        featuresLoaded = true,
                        featuresError = c.session.toUiError(
                            featuresFailure ?: IllegalStateException("features 未返回"),
                        ).message,
                    )
                }
            }

            _state.update {
                it.copy(
                    loading = false,
                    baseUrl = c.config.baseUrl,
                    tokenDegraded = c.tokenStore.degraded,
                    effectiveVoiceLabel = effectiveVoiceLabel(),
                    effectiveRate = c.voicePrefs.resolve(c.session.state.value.isChild).rate,
                    error = basicError?.let { err -> c.session.toUiError(err) },
                )
            }
        }
    }

    /** 「强制刷新」按钮：`force=true` 跳过服务端缓存。 */
    fun forceRefresh() = load(force = true)

    // ------------------------------------------------------------------ 展示文案

    fun levelTitle(): String = when (state.value.level) {
        "bad" -> "服务异常"
        "warn" -> "服务可用，语音未就绪"
        else -> "服务正常"
    }

    fun levelDetail(): String = when (state.value.level) {
        "bad" -> "数据库不可用：评测、历史与统计可能受影响，请检查家庭 NAS 的数据库配置。"
        "warn" -> "语音服务未就绪：录音与文本仍会入库，可稍后「重试评测」；文本/历史功能不受影响。"
        else -> "家庭 NAS 与语音服务均可用，可以正常练习。"
    }

    fun levelIcon(): String = when (state.value.level) {
        "bad" -> "⛔"
        "warn" -> "⚠️"
        else -> "✅"
    }

    fun voiceSummary(): String = buildString {
        append("模式：")
        append(state.value.voiceMode.ifEmpty { "—" })
        append(" · ")
        append(if (state.value.voiceReachable) "可连接" else "不可达")
    }

    /** 语音能力清单（capabilities 为空时返回空列表，页面显示「未返回」）。 */
    fun capabilityLines(): List<Pair<String, Boolean>> {
        val cap = state.value.capabilities ?: return emptyList()
        return listOf(
            "音素级评分" to cap.phonemeLevel,
            "韵律/语调" to cap.prosody,
            "语调曲线" to cap.intonationCurve,
            "N-best 音素" to cap.nbestPhonemes,
            "SSML" to cap.ssml,
            "图片 OCR" to cap.ocr,
            "插画生成" to cap.image,
            "照片生成形象" to cap.imageAvatar,
            "预置形象" to cap.avatarPresets,
            "音频拼接" to cap.audioConcat,
            "单词音标" to cap.wordIpa,
        )
    }

    fun imageProvider(): String = state.value.capabilities?.imageProvider.orEmpty()

    fun asrProviders(): List<String> = state.value.capabilities?.asrProviders.orEmpty()

    fun tokenStorageNote(): String = if (state.value.tokenDegraded) {
        "凭证只保存在内存（本次运行有效）：系统安全存储不可用"
    } else {
        "凭证保存在系统安全存储（EncryptedSharedPreferences）"
    }

    /** 当前生效音色（儿童未设置音色时是内置童声，见 VoicePrefs.resolve）。 */
    private fun effectiveVoiceLabel(): String {
        val choice = c.voicePrefs.resolve(c.session.state.value.isChild)
        val id = choice.voice
        if (id.isNullOrEmpty()) return "默认音色（provider 决定）"
        return Voices.find(id)?.labelZh ?: id
    }

    private fun featureLines(features: HealthFeaturesDto?): List<Pair<String, Boolean>> {
        if (features == null) return emptyList()
        return listOf(
            "对话不限轮数" to features.chatUnlimitedTurns,
            "整段对话回放" to features.chatAudioReplay,
            "场景受众分离" to features.chatScenariosAudience,
            "预置形象库" to features.avatarPresets,
            "故事模式" to features.storyMode,
            "异步评分" to features.asyncScoring,
        )
    }
}

package top.dreamsearch.englishcoach.ui.page.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.audio.Voices
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.ErrorMapper
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.model.UsageDto
import top.dreamsearch.englishcoach.core.model.UserDto
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.dto.SettingsPatchBodyDto

/**
 * 设置页状态（`ui/page/account/SettingsScreen.kt` 专用）。
 *
 * 数据来源：`GET /api/settings`（user/prefs/usage）、`PATCH /api/settings`（保存）、
 * `GET /api/health`（服务器连接 + image 能力）、`POST /family/members/:id/password`（本人改密）。
 *
 * 硬约束（CONTRACT §3.2 / hos AccountSettingsVM）：
 * - **儿童绝不提交** `daily_limit_minutes` / `allow_free_chat`（服务端 403）；
 * - PATCH 返回的 user 是瘦身版，**不用它覆盖**本地 gender/autoIllustrate/storySentences；
 * - PATCH 被当前环境不支持（405/501 或 http 层 method 错误）→ 提示「该设置暂不可用」；
 * - 权威错误文案统一走 `SessionStore.toUiError`，不直接展示 code。
 *
 * 对应 hos：`viewmodel/AccountVM.ets` 的 `AccountSettingsVM` + `pages/SettingsPage.ets`。
 */
data class SettingsUiState(
    val loading: Boolean = false,
    val loaded: Boolean = false,
    val saving: Boolean = false,
    val error: UiError? = null,
    val notice: String = "",
    // 账号
    val userId: String = "",
    val email: String = "",
    val role: String = "child",
    val ageBand: String = "adult",
    val avatar: String = "",
    val cefrLevel: String = "A1",
    val isChild: Boolean = false,
    // 偏好表单
    val displayName: String = "",
    /** '' = 不设置；girl | boy | woman | man | other */
    val gender: String = "",
    /** -1 = 角色默认；3–12 */
    val storySentences: Int = -1,
    val dailyLimit: Int = 20,
    val allowFreeChat: Boolean = false,
    val autoIllustrate: Boolean = false,
    /** gentle | standard | none */
    val correctionLevel: String = "gentle",
    /** '' = provider 默认音色 */
    val ttsVoice: String = "",
    /** slow | normal */
    val ttsRate: String = "normal",
    val showWordIpa: Boolean = true,
    // 用量
    val usageMinutes: Int = 0,
    val usageLimit: Int = 20,
    // 服务器 / 健康
    val baseUrl: String = "",
    val savedBaseUrl: String = "",
    val checkingServer: Boolean = false,
    val serverStatus: String = "",
    val serverOk: Boolean = false,
    /** null = 未探测；false = 服务端未启用图像能力（自动插画开关要提示） */
    val imageCapable: Boolean? = null,
    /** false = 服务端未开启预置形象库（`capability.avatarPresets`，形象入口置灰） */
    val avatarPresetsAvailable: Boolean = true,
    // 退出 / 改密
    val loggingOut: Boolean = false,
    val passwordDialogOpen: Boolean = false,
    val newPassword: String = "",
    val confirmPassword: String = "",
    val passwordSaving: Boolean = false,
    val passwordError: String = "",
    val passwordNotice: String = "",
)

class SettingsViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        val baseUrl = c.config.baseUrl
        _state.update { it.copy(baseUrl = baseUrl, savedBaseUrl = baseUrl) }
        load()
        checkServer()
    }

    /** 表单编辑统一入口：`vm.edit { it.copy(displayName = value) }`。 */
    fun edit(transform: (SettingsUiState) -> SettingsUiState) {
        _state.update(transform)
    }

    // ------------------------------------------------------------------ 加载

    fun load() {
        if (_state.value.loading) return
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            try {
                val dto = c.account.settings()
                val user = dto.user
                val usage = dto.usage
                _state.update { s ->
                    var next = s.copy(loading = false, loaded = true, error = null)
                    if (user != null) {
                        next = next.copy(
                            userId = user.id,
                            email = user.email,
                            role = user.role,
                            ageBand = user.ageBand,
                            avatar = user.avatar.orEmpty(),
                            cefrLevel = user.cefrLevel,
                            isChild = user.role == "child" || user.isChild == true,
                            displayName = user.displayName,
                            autoIllustrate = user.autoIllustrate == true,
                            gender = user.gender.orEmpty(),
                            storySentences = user.storySentences ?: -1,
                            dailyLimit = user.dailyLimitMinutes,
                            allowFreeChat = user.allowFreeChat,
                        )
                    }
                    val prefs = dto.prefs
                    if (prefs != null) {
                        val child = next.isChild
                        next = next.copy(
                            correctionLevel = prefs.correctionLevel.takeIf { it.isNotEmpty() } ?: "gentle",
                            ttsVoice = prefs.ttsVoice.orEmpty(),
                            ttsRate = prefs.ttsRate.takeIf { it.isNotEmpty() }
                                ?: if (child) "slow" else "normal",
                            showWordIpa = prefs.showWordIpa ?: true,
                        )
                    }
                    if (usage != null) {
                        next = next.copy(usageMinutes = usage.minutes, usageLimit = usage.limitMinutes)
                    }
                    next
                }
                if (user != null) c.session.applyUser(user, usage)
                // 账号偏好 → 本机语音镜像（示范音/对话朗读统一走 voicePrefs.resolve）
                val loaded = _state.value
                c.voicePrefs.syncFromAccount(
                    loaded.ttsVoice.takeIf { it.isNotEmpty() },
                    loaded.ttsRate,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(loading = false, error = c.session.toUiErrorAsync(e)) }
            }
        }
    }

    // ------------------------------------------------------------------ 保存偏好

    fun save() {
        val snapshot = _state.value
        if (snapshot.saving) return
        val problem = validate(snapshot)
        if (problem != null) {
            _state.update { it.copy(error = UiError(message = problem, code = ApiErrorCode.BAD_REQUEST), notice = "") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(saving = true, error = null, notice = "") }
            try {
                val dto = c.account.patchSettings(buildPatch(snapshot))
                val prefs = dto.prefs
                val usage = dto.usage
                _state.update { s ->
                    var next = s.copy(
                        saving = false,
                        loaded = true,
                        error = null,
                        notice = "已保存 ✅",
                    )
                    if (prefs != null) {
                        next = next.copy(
                            correctionLevel = prefs.correctionLevel.takeIf { it.isNotEmpty() }
                                ?: next.correctionLevel,
                            ttsVoice = prefs.ttsVoice.orEmpty(),
                            ttsRate = prefs.ttsRate.takeIf { it.isNotEmpty() } ?: next.ttsRate,
                            showWordIpa = prefs.showWordIpa ?: true,
                        )
                    }
                    if (usage != null) {
                        next = next.copy(
                            usageMinutes = usage.minutes,
                            usageLimit = usage.limitMinutes,
                        )
                    }
                    next
                }
                if (usage != null) c.session.updateUsage(usage)
                pushSession()
                // 保存成功 → 同步本机语音镜像：下一次示范音/对话朗读立即用新音色/语速
                val saved = _state.value
                c.voicePrefs.syncFromAccount(
                    saved.ttsVoice.takeIf { it.isNotEmpty() },
                    saved.ttsRate,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update {
                    it.copy(saving = false, notice = "", error = mapSaveError(e))
                }
                // 服务端可能「先落库再校验失败」：400 后重新拉一次同步真实状态
                if (e is ApiError && e.status == 400) load()
            }
        }
    }

    fun clearNotice() {
        _state.update { it.copy(notice = "") }
    }

    // ------------------------------------------------------------------ 服务器地址

    /** `GET /api/health`：连接状态（+ 能力开关走 `CapabilityCache`，ROUND2 §1.1 / §4-④）。 */
    fun checkServer() {
        if (_state.value.checkingServer) return
        viewModelScope.launch {
            _state.update { it.copy(checkingServer = true, serverStatus = "") }
            // 能力开关：统一来源（与 Me/Avatar 一致，不再单独解析 stats.healthFull）
            val caps = runCatching { c.capability.refresh() }.getOrNull()
            try {
                val health = c.practice.health()
                val voice = health.voice
                val db = health.db
                val status = when {
                    voice != null && !voice.reachable ->
                        "已连接；语音服务未就绪（录音会先保存，可稍后重试评测）"
                    db != null && !db.ok -> "已连接；数据库异常"
                    else -> "已连接"
                }
                _state.update {
                    it.copy(
                        checkingServer = false,
                        serverStatus = status,
                        serverOk = true,
                        imageCapable = caps?.image ?: voice?.capabilities?.image,
                        avatarPresetsAvailable = caps?.avatarPresets
                            ?: voice?.capabilities?.avatarPresets ?: true,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update {
                    it.copy(
                        checkingServer = false,
                        serverStatus = c.session.toUiError(e).message,
                        serverOk = false,
                        imageCapable = caps?.image,
                        avatarPresetsAvailable = caps?.avatarPresets ?: true,
                    )
                }
            }
        }
    }

    fun saveBaseUrl() {
        if (_state.value.saving) return
        val normalized = c.config.normalizeUrl(_state.value.baseUrl)
        if (!c.config.isValidUrl(normalized)) {
            _state.update {
                it.copy(
                    error = UiError(message = ErrorMapper.messageFor(ApiErrorCode.BAD_BASE_URL, false)),
                    notice = "",
                )
            }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(saving = true, error = null, notice = "") }
            try {
                c.config.baseUrl = normalized
                val cleartext = c.config.isCleartext(normalized)
                _state.update {
                    it.copy(
                        saving = false,
                        baseUrl = normalized,
                        savedBaseUrl = normalized,
                        notice = if (cleartext) {
                            "已保存。注意：http 明文在部分网络下会被系统拦截，建议使用 https"
                        } else {
                            "服务器地址已保存"
                        },
                    )
                }
                checkServer()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update {
                    it.copy(saving = false, error = c.session.toUiError(e))
                }
            }
        }
    }

    fun clearAudioCache() {
        c.cache.clearAudioCache()
        _state.update { it.copy(notice = "已清除示范音与回放缓存", error = null) }
    }

    // ------------------------------------------------------------------ 退出登录

    /** 退出：先 `session.logout()`（revoke 失败也继续），再回调页面 `onLogout()`。 */
    fun logout(onLoggedOut: () -> Unit) {
        if (_state.value.loggingOut) return
        viewModelScope.launch {
            _state.update { it.copy(loggingOut = true, error = null) }
            try {
                c.session.logout()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                // 退出流程内部已尽力 revoke；本地状态已清理，仍继续回到登录页
                _state.update { it.copy(error = c.session.toUiError(e)) }
            } finally {
                _state.update { it.copy(loggingOut = false) }
                onLoggedOut()
            }
        }
    }

    // ------------------------------------------------------------------ 修改密码（本人）

    fun openPasswordDialog() {
        _state.update {
            it.copy(
                passwordDialogOpen = true,
                newPassword = "",
                confirmPassword = "",
                passwordError = "",
                passwordNotice = "",
            )
        }
    }

    fun closePasswordDialog() {
        _state.update {
            it.copy(passwordDialogOpen = false, passwordSaving = false, passwordError = "")
        }
    }

    fun editNewPassword(value: String) {
        _state.update { it.copy(newPassword = value, passwordError = "") }
    }

    fun editConfirmPassword(value: String) {
        _state.update { it.copy(confirmPassword = value, passwordError = "") }
    }

    /**
     * 修改本人密码：`POST /family/members/:id/password {new_password}`（无旧密码校验，
     * 服务端不会吊销已有 refresh token，因此提示用户旧设备需自行退出）。
     */
    fun savePassword() {
        val snapshot = _state.value
        if (snapshot.passwordSaving) return
        if (snapshot.isChild) {
            _state.update { it.copy(passwordError = "请让爸爸妈妈在家长面板帮你改密码") }
            return
        }
        val password = snapshot.newPassword
        when {
            password.length < 8 || password.length > 128 ->
                _state.update { it.copy(passwordError = "新密码需为 8–128 位") }

            password != snapshot.confirmPassword ->
                _state.update { it.copy(passwordError = "两次输入的密码不一致") }

            snapshot.userId.isEmpty() ->
                _state.update { it.copy(passwordError = "账号信息还没加载好，稍后再试") }

            else -> viewModelScope.launch {
                _state.update { it.copy(passwordSaving = true, passwordError = "") }
                try {
                    c.account.resetMemberPassword(snapshot.userId, password)
                    _state.update {
                        it.copy(
                            passwordSaving = false,
                            passwordDialogOpen = false,
                            newPassword = "",
                            confirmPassword = "",
                            passwordNotice = "新密码已保存；其他设备可能仍保持登录，建议在旧设备退出",
                        )
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    _state.update {
                        it.copy(passwordSaving = false, passwordError = c.session.toUiError(e).message)
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ 展示文案

    fun voiceLabel(): String {
        val id = _state.value.ttsVoice
        if (id.isEmpty()) return "默认音色（provider 决定）"
        return Voices.find(id)?.labelZh ?: id
    }

    /** 当前**生效**音色（儿童未设置音色时是内置童声；语速儿童强制 slow——ROUND2 §1.2）。 */
    fun effectiveVoiceLabel(): String {
        val choice = c.voicePrefs.resolve(_state.value.isChild)
        val id = choice.voice
        if (id.isNullOrEmpty()) return "默认音色（provider 决定）"
        return Voices.find(id)?.labelZh ?: id
    }

    fun effectiveVoiceRate(): String = c.voicePrefs.resolve(_state.value.isChild).rate

    fun roleText(): String {
        val s = _state.value
        if (s.isChild) return "小朋友"
        return if (s.role == "parent") "家长" else "学习者"
    }

    fun usageText(): String = "今日已练 ${_state.value.usageMinutes} / ${_state.value.usageLimit} 分钟"

    fun storyDefault(): Int = if (_state.value.isChild) 5 else 8

    fun tokenStorageNote(): String = if (c.tokenStore.degraded) {
        "凭证保存在内存（本次运行有效）：系统安全存储当前不可用"
    } else {
        "凭证保存在系统安全存储（EncryptedSharedPreferences）"
    }

    // ------------------------------------------------------------------ 内部

    /** 前端前置校验（服务端「先写 users 再校验 prefs」有缺陷，必须客户端兜住）。null = 通过。 */
    private fun validate(s: SettingsUiState): String? {
        val name = s.displayName.trim()
        if (name.length !in 1..30) return "昵称需为 1–30 个字符"
        if (!s.isChild && s.dailyLimit !in 5..180) return "每日时长上限需在 5–180 分钟之间"
        if (s.gender.isNotEmpty() && s.gender !in GENDERS) return "性别取值不合法"
        if (s.storySentences != -1 && s.storySentences !in 3..12) return "故事句子数需在 3–12 之间"
        if (s.correctionLevel !in CORRECTION_LEVELS) return "纠正强度取值不合法"
        if (s.ttsRate !in TTS_RATES) return "语速取值不合法"
        if (s.ttsVoice.isNotEmpty() && Voices.find(s.ttsVoice) == null) return "音色不在可选范围内"
        return null
    }

    private fun buildPatch(s: SettingsUiState): SettingsPatchBodyDto = SettingsPatchBodyDto(
        displayName = s.displayName.trim(),
        dailyLimitMinutes = if (s.isChild) null else s.dailyLimit,
        allowFreeChat = if (s.isChild) null else s.allowFreeChat,
        autoIllustrate = s.autoIllustrate,
        gender = s.gender.takeIf { it.isNotEmpty() },
        storySentences = s.storySentences.takeIf { it >= 3 },
        correctionLevel = s.correctionLevel,
        ttsRate = s.ttsRate,
        ttsVoice = s.ttsVoice.takeIf { it.isNotEmpty() },
        showWordIpa = s.showWordIpa,
    )

    /** 保存成功后把表单值同步到全局会话（「我的」页昵称/用量即时更新）。 */
    private fun pushSession() {
        val s = _state.value
        c.session.applyUser(
            UserDto(
                id = s.userId,
                email = s.email,
                displayName = s.displayName.trim(),
                role = s.role,
                ageBand = s.ageBand,
                cefrLevel = s.cefrLevel,
                avatar = s.avatar,
                gender = s.gender.takeIf { it.isNotEmpty() },
                autoIllustrate = s.autoIllustrate,
                storySentences = s.storySentences.takeIf { it >= 3 },
                dailyLimitMinutes = s.dailyLimit,
                allowFreeChat = s.allowFreeChat,
                isChild = s.isChild,
            ),
            null,
        )
        c.session.updateUsage(
            UsageDto(
                minutes = s.usageMinutes,
                limitMinutes = s.usageLimit,
                remainingMinutes = (s.usageLimit - s.usageMinutes).coerceAtLeast(0),
                exceeded = s.usageMinutes >= s.usageLimit,
            )
        )
    }

    private fun mapSaveError(e: Throwable): UiError {
        if (e is ApiError) {
            if (e.status == 405 || e.status == 501) {
                return UiError(message = "该设置暂不可用（当前服务器不支持保存偏好）", code = e.code)
            }
            if (e.status == 0) {
                val detail = e.detail.lowercase()
                if (detail.contains("patch") || detail.contains("method")) {
                    return UiError(message = "该设置暂不可用（当前服务器不支持保存偏好）", code = e.code)
                }
            }
            if (e.status == 403) {
                return UiError(
                    message = e.detail.ifEmpty { "每日时长与自由话题由家长设置" },
                    code = e.code,
                )
            }
        }
        return c.session.toUiError(e)
    }

    companion object {
        private val GENDERS = setOf("girl", "boy", "woman", "man", "other")
        private val CORRECTION_LEVELS = setOf("gentle", "standard", "none")
        private val TTS_RATES = setOf("slow", "normal")
    }
}

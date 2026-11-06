package top.dreamsearch.englishcoach.ui.page.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.config.DemoAccount
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.ErrorMapper
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.dto.HealthDto

/**
 * 登录页状态（`ui/page/auth/LoginScreen.kt` 专用）。
 *
 * 数据来源：`core/config/AppConfig.kt`（baseUrl / demoAccounts / rememberPassword / lastEmail）、
 * `core/session/CredentialStore.kt`（记住的账号密码）、`PracticeService.health()`（底部连接状态）、
 * `SessionStore.login()`（真正登录 + 保存/清除记住密码）。
 *
 * 对应 hos：`viewmodel/LoginVM.ets` + `pages/LoginPage.ets`。
 *
 * 与 hos 的差异：**不在 VM 里做自动登录**。Android 的 `AppRoot` 在 `restore()` 失败后已调用
 * `session.loginWithSaved()`，这里只负责把记住的邮箱/密码预填到表单，避免同一次启动登录两次。
 */
data class LoginUiState(
    val email: String = "",
    val password: String = "",
    val baseUrl: String = "",
    /** 密码是否明文可见（眼睛切换）。 */
    val passwordVisible: Boolean = false,
    val rememberPassword: Boolean = true,
    /** 本机 EncryptedSharedPreferences 不可用：密码无法安全保存（只影响持久化，不阻塞登录）。 */
    val rememberUnsupported: Boolean = false,
    val loading: Boolean = false,
    val checkingServer: Boolean = false,
    /** 底部连接状态文案。 */
    val serverStatus: String = "",
    /** ok / warn / bad；空串 = 未检查。 */
    val serverLevel: String = "",
    /** 当前地址是 http 明文（会被部分网络拦截，展示风险提示）。 */
    val cleartext: Boolean = false,
    val error: UiError? = null,
    val demos: List<DemoAccount> = emptyList(),
) {
    /** 连接状态点/文字的颜色语义：checking/未检查 → 中性，连接成功 → good。 */
    val serverStatusText: String
        get() = when {
            checkingServer -> "正在检查服务器…"
            serverStatus.isNotEmpty() -> serverStatus
            else -> "未检查"
        }
}

class LoginViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(LoginUiState())
    val state: StateFlow<LoginUiState> = _state.asStateFlow()

    init {
        applyPrefill()
    }

    /**
     * 页面每次进入组合时调用（`LaunchedEffect(Unit)`）：
     * 清理上一次登录留下的敏感字段/错误；重新读取「记住的账号」与最新 baseUrl；再检查一次服务器。
     *
     * 为什么需要：`LoginScreen` 的 ViewModel 挂在 Activity 上，退出登录回到登录页时会复用同一个
     * 实例 —— 必须清掉旧密码/旧错误，否则会残留上一次输入。
     */
    fun onScreenShown() {
        applyPrefill()
        checkServer()
    }

    /** 用本地存的安全偏好 / baseUrl 回填表单；不会覆盖用户正在输入的内容以外的东西。 */
    private fun applyPrefill() {
        val storageReady = c.credentials.isAvailable()
        val saved = if (storageReady) runCatching { c.credentials.load() }.getOrNull() else null
        val remember = c.config.rememberPassword
        val baseUrl = c.config.baseUrl
        _state.update {
            it.copy(
                baseUrl = baseUrl,
                email = saved?.email?.takeIf { value -> value.isNotEmpty() } ?: c.config.lastEmail,
                password = if (remember) saved?.password.orEmpty() else "",
                rememberPassword = remember,
                rememberUnsupported = !storageReady,
                demos = c.config.demoAccounts,
                cleartext = c.config.isCleartext(baseUrl),
                loading = false,
                passwordVisible = false,
                error = null,
            )
        }
    }

    // ------------------------------------------------------------------ 表单编辑

    fun setEmail(value: String) {
        _state.update { it.copy(email = value, error = null) }
    }

    fun setPassword(value: String) {
        _state.update { it.copy(password = value, error = null) }
    }

    fun setBaseUrl(value: String) {
        _state.update { it.copy(baseUrl = value, cleartext = c.config.isCleartext(value), error = null) }
    }

    fun togglePasswordVisible() {
        _state.update { it.copy(passwordVisible = !it.passwordVisible) }
    }

    /** 演示账号「一键填入」：邮箱 + 密码都填（种子账号与 AppConfig 一致，可直接登录）。 */
    fun fillDemo(account: DemoAccount) {
        _state.update { it.copy(email = account.email, password = account.password, error = null) }
    }

    fun setRememberPassword(enabled: Boolean) {
        c.config.rememberPassword = enabled
        if (!enabled) c.credentials.clear()
        _state.update {
            it.copy(
                rememberPassword = enabled,
                rememberUnsupported = enabled && !c.credentials.isAvailable(),
            )
        }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }

    // ------------------------------------------------------------------ 连接状态

    /**
     * `GET /api/health`（无需登录）：判断「家庭 NAS 是否已连接」。
     * 与 hos 一致：先按输入框里的地址更新 baseUrl，让检查结果反映用户正在编辑的服务器。
     */
    fun checkServer() {
        if (_state.value.checkingServer) return
        viewModelScope.launch {
            _state.update { it.copy(checkingServer = true, serverStatus = "", serverLevel = "") }
            try {
                val normalized = c.config.normalizeUrl(_state.value.baseUrl)
                if (c.config.isValidUrl(normalized)) {
                    if (normalized != c.config.baseUrl) c.config.baseUrl = normalized
                    _state.update {
                        it.copy(baseUrl = normalized, cleartext = c.config.isCleartext(normalized))
                    }
                }
                val health = c.practice.health()
                val described = describeHealth(health)
                _state.update {
                    it.copy(
                        checkingServer = false,
                        serverStatus = described.second,
                        serverLevel = described.first,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update {
                    it.copy(
                        checkingServer = false,
                        serverStatus = c.session.toUiError(e).message,
                        serverLevel = "bad",
                    )
                }
            }
        }
    }

    // ------------------------------------------------------------------ 登录

    /**
     * 校验顺序（照抄 hos LoginVM）：必填 → baseUrl 合法 → 保存 baseUrl → `POST /auth/token`。
     * 成功后只写全局会话（`SessionStore.state.loggedIn`），导航由 `AppRoot` 自动切首页。
     */
    fun login() {
        val snapshot = _state.value
        if (snapshot.loading) return
        val email = snapshot.email.trim()
        if (email.isEmpty() || snapshot.password.isEmpty()) {
            showFormError("请输入邮箱和密码")
            return
        }
        val normalized = c.config.normalizeUrl(snapshot.baseUrl)
        if (!c.config.isValidUrl(normalized)) {
            showFormError(ErrorMapper.messageFor(ApiErrorCode.BAD_BASE_URL, false))
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            try {
                c.config.baseUrl = normalized
                _state.update { it.copy(baseUrl = normalized, cleartext = c.config.isCleartext(normalized)) }
                c.session.login(email, snapshot.password, snapshot.rememberPassword)
                _state.update {
                    it.copy(loading = false, error = null, rememberUnsupported = !c.credentials.isAvailable())
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(loading = false, error = c.session.toUiErrorAsync(e)) }
            }
        }
    }

    private fun showFormError(message: String) {
        _state.update {
            it.copy(error = UiError(message = message, code = ApiErrorCode.BAD_REQUEST), loading = false)
        }
    }

    private fun describeHealth(health: HealthDto): Pair<String, String> {
        val voice = health.voice
        if (voice != null && !voice.reachable) {
            return "warn" to "家庭 NAS 已连接 · 语音服务未就绪（录音会先保存，可稍后重试评测）"
        }
        val db = health.db
        if (db != null && !db.ok) {
            return "warn" to "家庭 NAS 已连接 · 数据库异常"
        }
        return "ok" to "家庭 NAS 已连接"
    }
}

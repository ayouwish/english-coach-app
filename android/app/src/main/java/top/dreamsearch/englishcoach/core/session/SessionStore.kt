package top.dreamsearch.englishcoach.core.session

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import top.dreamsearch.englishcoach.core.config.AppConfig
import top.dreamsearch.englishcoach.core.error.ErrorMapper
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.model.UsageDto
import top.dreamsearch.englishcoach.core.model.UserDto
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.service.AuthService
import top.dreamsearch.englishcoach.core.storage.CacheStore
import top.dreamsearch.englishcoach.core.util.Logx

/** 全局会话状态（登录用户 / 角色 / 今日用量），在 VM 与页面之间只读共享。 */
data class SessionState(
    val loggedIn: Boolean = false,
    val userId: String = "",
    val displayName: String = "",
    val email: String = "",
    /** 'parent' | 'child' */
    val role: String = "child",
    val cefrLevel: String = "A1",
    /** 'child' | 'teen' | 'adult' */
    val ageBand: String = "adult",
    val isChild: Boolean = false,
    val avatar: String = "",
    val dailyLimitMinutes: Int = 20,
    val minutesToday: Int = 0,
    val remainingMinutes: Int = 0,
    val exceeded: Boolean = false,
)

/**
 * 会话编排（对应 hos `SessionStore`）：启动恢复 / 登录 / 登出 / 用量同步 / 统一错误映射。
 *
 * 页面不直接读 TokenStore：未登录 → [state].loggedIn == false，导航层据此显示登录页。
 */
class SessionStore(
    private val config: AppConfig,
    private val tokenStore: TokenStore,
    private val cache: CacheStore,
    private val credentials: CredentialStore,
    private val auth: AuthService,
) {
    private val _state = MutableStateFlow(SessionState())
    val state: StateFlow<SessionState> = _state.asStateFlow()

    val isChild: Boolean get() = _state.value.isChild

    /**
     * 冷启动恢复：读 token → `/auth/me`。
     * 返回 false = 需要登录；抛错 = 网络/服务器问题（由启动页展示重试）。
     */
    suspend fun restore(): Boolean {
        tokenStore.load()
        if (!tokenStore.hasRefresh()) {
            _state.value = SessionState()
            return false
        }
        return try {
            val me = auth.me()
            val user = me.user
            if (user == null) {
                tokenStore.clear()
                _state.value = SessionState()
                false
            } else {
                applyUser(user, me.usage)
                true
            }
        } catch (e: ApiError) {
            if (e.code == ApiErrorCode.UNAUTHORIZED) {
                tokenStore.clear()
                _state.value = SessionState()
                false
            } else {
                throw e
            }
        }
    }

    /** 登录：POST /auth/token → GET /auth/me 补 usage → 保存"记住密码"（可选）。 */
    suspend fun login(email: String, password: String, rememberPassword: Boolean): SessionState {
        val result = auth.login(email, password)
        val user = result.user
            ?: throw ApiError(ApiErrorCode.BAD_RESPONSE, 401, "登录返回缺少用户信息")
        // 切换账号：旧账号缓存必须失效（docs/architecture.md §7.4）
        cache.clearAll()
        config.lastEmail = email
        config.rememberPassword = rememberPassword
        if (rememberPassword) {
            val saved = credentials.save(email, password)
            if (!saved) {
                Logx.w("Session", "remember password unsupported on this device")
            }
        } else {
            credentials.clear()
        }
        applyUser(user, result.usage)
        return _state.value
    }

    /** 自动登录：有记住的账号且用户没有主动退出时使用。 */
    suspend fun loginWithSaved(): Boolean {
        if (credentials.consumeAutoLoginSuppressed()) return false
        val saved = credentials.load() ?: return false
        return try {
            login(saved.email, saved.password, rememberPassword = true)
            true
        } catch (e: Throwable) {
            // 自动登录失败不弹错，回落到登录页（用户可看到上次记住的邮箱）
            Logx.w("Session", "auto login failed", e)
            false
        }
    }

    /** 退出：先 revoke（失败也继续），再清 token + 缓存 + 全局状态。 */
    suspend fun logout() {
        // 主动退出后不在本次进程内自动登录（记住的密码仍保留，下次启动可自动登录）
        credentials.markLoggedOut()
        runCatching { auth.revoke() }
        tokenStore.clear()
        cache.clearAll()
        _state.value = SessionState()
    }

    /** 会话失效（401/刷新被拒）：清 token + 全局会话。 */
    suspend fun expire() {
        runCatching { tokenStore.clear() }
        _state.value = SessionState()
    }

    /** 每次提交评测后同步用量（422/429 依赖它展示剩余时长）。 */
    fun updateUsage(usage: UsageDto) {
        _state.value = _state.value.copy(
            dailyLimitMinutes = usage.limitMinutes,
            minutesToday = usage.minutes,
            remainingMinutes = usage.remainingMinutes,
            exceeded = usage.exceeded,
        )
    }

    fun applyUser(user: UserDto, usage: UsageDto?) {
        var next = SessionState(
            loggedIn = true,
            userId = user.id,
            displayName = user.displayName,
            email = user.email,
            role = user.role,
            cefrLevel = user.cefrLevel,
            ageBand = user.ageBand,
            isChild = user.role == "child" || user.isChild == true,
            avatar = user.avatar.orEmpty(),
            dailyLimitMinutes = user.dailyLimitMinutes,
        )
        if (usage != null) {
            next = next.copy(
                dailyLimitMinutes = usage.limitMinutes,
                minutesToday = usage.minutes,
                remainingMinutes = usage.remainingMinutes,
                exceeded = usage.exceeded,
            )
        }
        _state.value = next
    }

    /**
     * 统一错误映射：命中 unauthorized 时顺带 [expire]。
     * 页面只需要展示返回的 UiError，不需要自己判断 401。
     */
    suspend fun toUiErrorAsync(err: Throwable): UiError {
        val ui = ErrorMapper.from(err, isChild)
        if (ui.code == ApiErrorCode.UNAUTHORIZED) {
            expire()
        }
        return ui
    }

    /** 同步版：不触发 expire（启动期/非协程场景用）。 */
    fun toUiError(err: Throwable): UiError = ErrorMapper.from(err, isChild)
}

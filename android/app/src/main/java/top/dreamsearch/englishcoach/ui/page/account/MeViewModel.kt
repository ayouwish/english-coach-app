package top.dreamsearch.englishcoach.ui.page.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError

/**
 * 「我的」Tab 状态（`ui/page/account/MeScreen.kt` 专用）。
 *
 * 数据来源：
 * - 账号/角色/用量：全局 `SessionStore.state`（页面直接 collect，VM 不复制一份登录态）；
 * - 用量刷新：`GET /auth/me`（`AuthService.me()` → `session.applyUser`，与 hos 的「刷新用量」一致）；
 * - 服务状态副标题：`GET /api/health`（`PracticeService.health()`）；
 * - 退出登录：`SessionStore.logout()`（成功后 AppRoot 自动切登录页）。
 *
 * 对应 hos：`pages/MePage.ets`（无独立 VM，逻辑内联；Android 按 CONTRACT §2.6 建 VM）。
 */
data class MeUiState(
    val refreshing: Boolean = false,
    val error: UiError? = null,
    val loggingOut: Boolean = false,
    /** 服务状态入口的副标题；空串 = 未检查。 */
    val serverStatus: String = "",
    /** ok / warn / bad；空串 = 未检查。 */
    val serverLevel: String = "",
    /** 待补评分录音条数（ROUND2 §1.3 离线队列；>0 才显示入口）。 */
    val pendingCount: Int = 0,
    /** 服务端是否开启预置形象库（`capability.avatarPresets`；false → 入口置灰）。 */
    val avatarPresetsAvailable: Boolean = true,
)

class MeViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(MeUiState())
    val state: StateFlow<MeUiState> = _state.asStateFlow()

    init {
        refresh()
        checkServer()
        refreshPending()
        refreshCapabilities()
    }

    /**
     * 刷新「待补评分录音」条数（本地离线队列，同步读 index，不联网）。
     * 页面在每个 ON_RESUME 调用一次（排队/补评分会发生在别的页面）。
     */
    fun refreshPending() {
        val count = runCatching { c.pendingUploads.count() }.getOrDefault(0)
        _state.update { it.copy(pendingCount = count) }
    }

    /** 刷新能力开关（`/health` 的 avatar_presets；5 分钟内复用缓存，入口置灰用）。 */
    fun refreshCapabilities() {
        viewModelScope.launch {
            val caps = runCatching { c.capability.refresh() }.getOrNull()
            _state.update { it.copy(avatarPresetsAvailable = caps?.avatarPresets ?: true) }
        }
    }

    /** `GET /auth/me`：同步最新昵称/等级/今日用量（失败可见可重试，不阻塞页面）。 */
    fun refresh() {
        if (_state.value.refreshing) return
        viewModelScope.launch {
            _state.update { it.copy(refreshing = true, error = null) }
            try {
                val me = c.auth.me()
                val user = me.user
                if (user != null) c.session.applyUser(user, me.usage)
                _state.update { it.copy(refreshing = false, error = null) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(refreshing = false, error = c.session.toUiErrorAsync(e)) }
            }
        }
    }

    /** `GET /api/health`：服务状态入口的副标题（失败也算一种状态，不弹整页错误）。 */
    fun checkServer() {
        viewModelScope.launch {
            try {
                val health = c.practice.health()
                val voice = health.voice
                val db = health.db
                when {
                    voice != null && !voice.reachable -> _state.update {
                        it.copy(serverStatus = "语音服务未就绪（录音会先保存）", serverLevel = "warn")
                    }
                    db != null && !db.ok -> _state.update {
                        it.copy(serverStatus = "家庭 NAS 已连接 · 数据库异常", serverLevel = "warn")
                    }
                    else -> _state.update {
                        it.copy(serverStatus = "家庭 NAS 已连接", serverLevel = "ok")
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update {
                    it.copy(serverStatus = c.session.toUiError(e).message, serverLevel = "bad")
                }
            }
        }
    }

    /** 退出登录；成功后 AppRoot 自动切登录页（Tab 根页无需手动导航）。 */
    fun logout() {
        if (_state.value.loggingOut) return
        viewModelScope.launch {
            _state.update { it.copy(loggingOut = true, error = null) }
            try {
                c.session.logout()
                _state.update { it.copy(loggingOut = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(loggingOut = false, error = c.session.toUiError(e)) }
            }
        }
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }
}

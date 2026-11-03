package top.dreamsearch.englishcoach.core.service

import kotlinx.serialization.encodeToString
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.model.LoginBodyDto
import top.dreamsearch.englishcoach.core.model.LoginResult
import top.dreamsearch.englishcoach.core.model.MeResponseDto
import top.dreamsearch.englishcoach.core.model.TokenResponseDto
import top.dreamsearch.englishcoach.core.model.UsageDto
import top.dreamsearch.englishcoach.core.model.UserDto
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.ApiRequest
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.net.decodeBody
import top.dreamsearch.englishcoach.core.net.dto.RefreshBodyDto
import top.dreamsearch.englishcoach.core.net.dto.RevokeBodyDto
import top.dreamsearch.englishcoach.core.session.TokenStore

/**
 * 认证服务：登录 / 取当前用户 / 退出。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/service/AuthService.ets`。
 * 数据来源：docs/architecture.md §9.1；DTO 用 `core/model/UserModels.kt`（Lead 已提供，不重复定义）。
 *
 * 流程：`POST /auth/token`（auth=false）→ 保存两个 token → `GET /auth/me` 补 usage。
 * `/auth/token`、`/auth/refresh`（内部）、`/auth/revoke`、`/health` 都不参与 401 自动刷新。
 *
 * 注意（与 hos 的差异，已与 Lead 约定）：
 * - Android 的 `ApiClient` 构造签名是 `AuthService(api)`，拿不到 TokenStore，
 *   而登录必须落 token（否则后续请求全 401），因此这里通过已初始化的
 *   `AppGraph.container.tokenStore` 取；运行期 `EnglishCoachApp.onCreate()` 已保证容器就绪。
 * - `ApiClient.refreshAccessToken()` 是 private，所以 `me()` 里「刷新一次再取」由本服务
 *   直接用 `POST /auth/refresh` 完成，错误语义与 ApiClient 内部刷新保持一致：
 *   400/401 → 清 token 抛 unauthorized；网络/5xx → 不清 token。
 */
class AuthService(private val api: ApiClient) {

    private val tokenStore: TokenStore get() = AppGraph.container.tokenStore

    /**
     * 登录。
     *
     * @return user 来自 `/auth/token`（尽量用 `/auth/me` 校正），usage 可能为 null。
     */
    suspend fun login(email: String, password: String): LoginResult {
        val body = EcJson.encodeToString(LoginBodyDto(email = email.trim(), password = password))
        val raw = api.postJson("/auth/token", body, auth = false, timeoutMs = LOGIN_TIMEOUT_MS)
        if (raw.status != 200) {
            throw api.errorOf(raw)
        }
        val dto = decodeBody<TokenResponseDto>(raw.text, "登录")
        val accessToken = dto.accessToken
        val refreshToken = dto.refreshToken
        if (accessToken.isEmpty() || refreshToken.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "登录返回缺少 token")
        }
        tokenStore.save(
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresInSec = dto.expiresIn,
            refreshExpiresInSec = dto.refreshExpiresIn,
        )

        var user: UserDto? = dto.user
        var usage: UsageDto? = dto.usage
        try {
            val me = me()
            me.user?.let { user = it }
            me.usage?.let { usage = it }
        } catch (e: ApiError) {
            // token 已保存，usage 拉取失败不影响进入首页；但会话已失效时必须让登录失败
            if (e.code == ApiErrorCode.UNAUTHORIZED) throw e
        }
        val resolvedUser = user
            ?: throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "登录返回缺少用户信息")
        return LoginResult(resolvedUser, usage)
    }

    /**
     * `GET /auth/me`。
     *
     * 兼容「无效 Bearer 返回 200 + {user:null}」的旧行为：先刷新一次再取，
     * 仍为空则清 token 抛 `unauthorized`。
     */
    suspend fun me(): MeResponseDto {
        val first = fetchMe()
        if (first.user != null) return first

        if (!tokenStore.hasRefresh()) {
            tokenStore.clear()
            throw ApiError(ApiErrorCode.UNAUTHORIZED, 200, "登录已失效，请重新登录")
        }
        refreshAccessTokenOnce()
        val second = fetchMe()
        if (second.user == null) {
            tokenStore.clear()
            throw ApiError(ApiErrorCode.UNAUTHORIZED, 200, "登录已失效，请重新登录")
        }
        return second
    }

    /** `POST /auth/revoke`（204）；失败由调用方决定是否忽略。 */
    suspend fun revoke() {
        val refreshToken = tokenStore.refreshToken()
        if (refreshToken.isEmpty()) return
        val body = EcJson.encodeToString(RevokeBodyDto(refreshToken = refreshToken))
        val raw = api.request(
            ApiRequest(
                method = "POST",
                path = "/auth/revoke",
                jsonBody = body,
                auth = false,
                retryOn401 = false,
                timeoutMs = REVOKE_TIMEOUT_MS,
            )
        )
        if (raw.status != 204 && raw.status != 200) {
            throw api.errorOf(raw)
        }
    }

    // ------------------------------------------------------------------ 内部

    private suspend fun fetchMe(): MeResponseDto {
        val raw = api.getJson("/auth/me", null, ME_TIMEOUT_MS)
        if (raw.status == 401) {
            throw api.errorOf(raw)
        }
        api.requireOk(raw)
        return decodeBody<MeResponseDto>(raw.text, "用户信息")
    }

    /**
     * 主动刷新一次 access token（语义与 `ApiClient` 内部刷新一致）：
     * 400/401 → 清 token + unauthorized；网络/5xx → 保留 token 直接抛错。
     */
    private suspend fun refreshAccessTokenOnce() {
        val refreshToken = tokenStore.refreshToken()
        if (refreshToken.isEmpty()) {
            tokenStore.clear()
            throw ApiError(ApiErrorCode.UNAUTHORIZED, 401, "登录已失效，请重新登录")
        }
        val body = EcJson.encodeToString(RefreshBodyDto(refreshToken = refreshToken))
        val raw = api.request(
            ApiRequest(
                method = "POST",
                path = "/auth/refresh",
                jsonBody = body,
                auth = false,
                retryOn401 = false,
                timeoutMs = REFRESH_TIMEOUT_MS,
            )
        )
        if (raw.status == 400 || raw.status == 401) {
            tokenStore.clear()
            throw ApiError(ApiErrorCode.UNAUTHORIZED, raw.status, "登录已过期，请重新登录")
        }
        if (raw.status != 200) {
            // 网络/5xx：不清 token，让用户重试（避免一次断网就登出）
            throw api.errorOf(raw)
        }
        val dto = decodeBody<TokenResponseDto>(raw.text, "登录续期")
        if (dto.accessToken.isEmpty() || dto.refreshToken.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "服务器返回的登录信息不完整")
        }
        tokenStore.save(
            accessToken = dto.accessToken,
            refreshToken = dto.refreshToken,
            expiresInSec = dto.expiresIn,
            refreshExpiresInSec = dto.refreshExpiresIn,
        )
    }

    companion object {
        private const val LOGIN_TIMEOUT_MS = 15_000L
        private const val ME_TIMEOUT_MS = 15_000L
        private const val REVOKE_TIMEOUT_MS = 10_000L
        private const val REFRESH_TIMEOUT_MS = 15_000L
    }
}

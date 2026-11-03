package top.dreamsearch.englishcoach.core.net

/**
 * 统一错误类型（docs/architecture.md §6）。
 *
 * - 网络层、鉴权层、媒体层都抛 ApiError，VM 只处理这一种错误；
 * - `code` 仅用于日志/测试，UI 文案统一由 `core/error/ErrorMapper` 映射；
 * - `status == 0` 表示「客户端本地错误」（mic_denied、timeout 等），不是 HTTP 响应。
 */
class ApiError(
    val code: String,
    val status: Int,
    val detail: String,
) : Exception(if (detail.isNotEmpty()) detail else code) {

    val retryable: Boolean = isRetryable(code, status)

    companion object {
        fun local(code: String, detail: String): ApiError = ApiError(code, 0, detail)

        fun isRetryable(code: String, status: Int): Boolean {
            if (code == ApiErrorCode.NETWORK_UNREACHABLE) return true
            if (code == ApiErrorCode.TIMEOUT) return true
            if (code == ApiErrorCode.INTERNAL_ERROR && status >= 500) return true
            if (code == ApiErrorCode.PROVIDER_ERROR) return true
            if (code == ApiErrorCode.PROVIDER_TIMEOUT) return true
            return status == 502 || status == 503 || status == 504
        }
    }
}

/** 服务端错误码 + 客户端本地错误码。字符串常量集中一处，避免拼写漂移。 */
object ApiErrorCode {
    // ---- 服务端 ----
    const val BAD_REQUEST = "bad_request"
    const val UNAUTHORIZED = "unauthorized"
    const val FORBIDDEN = "forbidden"
    const val NOT_FOUND = "not_found"
    const val AUDIO_NOT_FOUND = "audio_not_found"
    const val AUDIO_GONE = "audio_gone"
    const val PAYLOAD_TOO_LARGE = "payload_too_large"
    const val DAILY_LIMIT_REACHED = "daily_limit_reached"
    const val TOO_MANY_REQUESTS = "too_many_requests"
    const val CONTENT_UNSAFE = "content_unsafe"
    const val INTERNAL_ERROR = "internal_error"
    const val PROVIDER_ERROR = "provider_error"
    const val PROVIDER_UNAVAILABLE = "provider_unavailable"
    const val PROVIDER_TIMEOUT = "provider_timeout"

    // ---- 客户端本地 ----
    const val NETWORK_UNREACHABLE = "network_unreachable"
    const val TIMEOUT = "timeout"
    const val CLEARTEXT_BLOCKED = "cleartext_blocked"
    const val MIC_DENIED = "mic_denied"
    const val MIC_UNAVAILABLE = "mic_unavailable"
    const val RECORD_FAILED = "record_failed"
    const val RECORD_TOO_SHORT = "record_too_short"
    const val RECORD_TOO_LARGE = "record_too_large"
    const val PLAYBACK_FAILED = "playback_failed"
    const val CACHE_CORRUPT = "cache_corrupt"
    const val BAD_RESPONSE = "bad_response"
    const val BAD_BASE_URL = "bad_base_url"

    /** HTTP 状态 → 默认 code（响应体没有标准错误信封时兜底）。 */
    fun forStatus(status: Int): String = when (status) {
        400 -> BAD_REQUEST
        401 -> UNAUTHORIZED
        403 -> FORBIDDEN
        404 -> NOT_FOUND
        413 -> PAYLOAD_TOO_LARGE
        429 -> DAILY_LIMIT_REACHED
        502 -> PROVIDER_ERROR
        503 -> PROVIDER_UNAVAILABLE
        504 -> PROVIDER_TIMEOUT
        else -> INTERNAL_ERROR
    }
}

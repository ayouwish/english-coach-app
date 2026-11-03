package top.dreamsearch.englishcoach.core.config

import top.dreamsearch.englishcoach.core.storage.AppPrefs

/** 登录页「演示账号一键填入」用的账号（与后端种子账号一致）。 */
data class DemoAccount(
    val label: String,
    val email: String,
    val password: String,
)

/**
 * 非敏感配置（baseUrl、语速偏好、token 过期时间戳）。
 *
 * 敏感数据（access/refresh token、记住的密码）**只**放加密存储（TokenStore），不得进这里。
 */
class AppConfig(private val prefs: AppPrefs) {

    /** 去掉尾部 `/` 与误填的 `/api`，补全 scheme。空串回落到默认值。 */
    fun normalizeUrl(raw: String): String {
        var url = raw.trim()
        if (url.isEmpty()) return DEFAULT_BASE_URL
        val lower = url.lowercase()
        if (!lower.startsWith("http://") && !lower.startsWith("https://")) {
            url = "https://$url"
        }
        while (url.endsWith("/")) url = url.dropLast(1)
        if (url.lowercase().endsWith("/api")) url = url.dropLast(4)
        return url
    }

    /** 轻量校验：只要求 scheme + 非空 host；不做 DNS/可达性判断。 */
    fun isValidUrl(url: String): Boolean {
        val lower = url.lowercase()
        val rest = when {
            lower.startsWith("https://") -> url.substring(8)
            lower.startsWith("http://") -> url.substring(7)
            else -> return false
        }
        if (rest.isEmpty() || rest.contains(' ')) return false
        val host = rest.split('/')[0].split(':')[0]
        return host.isNotEmpty()
    }

    fun isCleartext(url: String): Boolean = url.lowercase().startsWith("http://")

    /** 当前账号 cefrLevel → 可用的语料等级（服务端没有 C1 语料，回退 B2）。 */
    fun levelForCefr(cefr: String): String {
        val upper = cefr.trim().uppercase()
        return if (upper in LEVELS) upper else "B2"
    }

    /** 服务器根地址（不含 `/api`，请求时由 ApiClient 拼接）。 */
    var baseUrl: String
        get() = normalizeUrl(prefs.getString(KEY_BASE_URL, DEFAULT_BASE_URL))
        set(value) {
            prefs.putString(KEY_BASE_URL, normalizeUrl(value))
        }

    var rememberPassword: Boolean
        get() = prefs.getBoolean(KEY_REMEMBER_PASSWORD, false)
        set(value) {
            prefs.putBoolean(KEY_REMEMBER_PASSWORD, value)
        }

    /** 最近一次登录成功的邮箱（登录页预填，不涉及密码）。 */
    var lastEmail: String
        get() = prefs.getString(KEY_LAST_EMAIL, "")
        set(value) {
            prefs.putString(KEY_LAST_EMAIL, value)
        }

    val demoAccounts: List<DemoAccount> = listOf(
        DemoAccount("爸爸 · 家长 · B1", "dad@example.com", "Dad12345!"),
        DemoAccount("女儿 · 儿童 · A1", "girl@example.com", "Girl12345!"),
    )

    companion object {
        const val DEFAULT_BASE_URL: String = "https://english.dreamsearch.top"
        const val APP_VERSION: String = "0.1.0"
        /** 仅用于博文的展示：服务端时间戳用 Long，这里仅供 token 过期判断。 */
        const val KEY_BASE_URL: String = "baseUrl"
        const val KEY_REMEMBER_PASSWORD: String = "rememberPassword"
        const val KEY_LAST_EMAIL: String = "lastEmail"
        const val KEY_ACCESS_EXPIRES_AT: String = "accessExpiresAt"
        const val KEY_REFRESH_EXPIRES_AT: String = "refreshExpiresAt"
        val LEVELS: List<String> = listOf("A1", "A2", "B1", "B2")
    }
}

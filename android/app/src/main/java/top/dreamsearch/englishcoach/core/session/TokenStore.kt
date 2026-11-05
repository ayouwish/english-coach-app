package top.dreamsearch.englishcoach.core.session

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import top.dreamsearch.englishcoach.core.util.Logx

/**
 * access / refresh token 的唯一存放处（对应 hos `TokenSession`，ADR-0002）。
 *
 * Android 方案：**EncryptedSharedPreferences**（Android Keystore + AES256-GCM，API 23+）。
 * 失败时降级为进程内存（不落明文），代价是杀进程后需重新登录，收益是绝不把凭证降级成明文。
 */
class TokenStore(context: Context) {

    private val prefs: SharedPreferences? = createEncrypted(context)

    @Volatile
    private var accessTokenCache: String = ""
    @Volatile
    private var refreshTokenCache: String = ""
    @Volatile
    private var accessExpiresAt: Long = 0L
    @Volatile
    private var refreshExpiresAt: Long = 0L

    /** true = 无法落盘、仅内存（设置页可提示「本机不能安全记住登录」）。 */
    @Volatile
    var degraded: Boolean = false
        private set

    init {
        load()
    }

    /** 冷启动从加密存储读一次（SessionStore.restore 会显式调用；构造时也会执行）。 */
    internal fun load() {
        val p = prefs ?: return
        accessTokenCache = p.getString(KEY_ACCESS, "") ?: ""
        refreshTokenCache = p.getString(KEY_REFRESH, "") ?: ""
        accessExpiresAt = p.getLong(KEY_ACCESS_EXP, 0L)
        refreshExpiresAt = p.getLong(KEY_REFRESH_EXP, 0L)
    }

    fun accessToken(): String = accessTokenCache

    fun refreshToken(): String = refreshTokenCache

    fun hasAccess(): Boolean = accessTokenCache.isNotEmpty()

    fun hasRefresh(): Boolean = refreshTokenCache.isNotEmpty()

    fun accessExpiresAt(): Long = accessExpiresAt

    fun refreshExpiresAt(): Long = refreshExpiresAt

    /** 过期或在 skew 窗口内。M1 以服务端 401 为准，此方法用于后续主动刷新优化。 */
    fun needsRefresh(now: Long = System.currentTimeMillis(), skewMs: Long = 60_000): Boolean {
        if (!hasAccess()) return true
        if (accessExpiresAt <= 0) return false
        return accessExpiresAt - skewMs <= now
    }

    /**
     * 原子替换一对 token（先 refresh 后 access；refresh 不可再生）。
     * expiresInSec / refreshExpiresInSec 来自 `/auth/token`、`/auth/refresh`。
     */
    fun save(
        accessToken: String,
        refreshToken: String,
        expiresInSec: Int,
        refreshExpiresInSec: Int,
    ) {
        val now = System.currentTimeMillis()
        accessTokenCache = accessToken
        refreshTokenCache = refreshToken
        accessExpiresAt = if (expiresInSec > 0) now + expiresInSec * 1000L else 0L
        refreshExpiresAt = if (refreshExpiresInSec > 0) now + refreshExpiresInSec * 1000L else 0L
        val p = prefs
        if (p == null) {
            degraded = true
            return
        }
        runCatching {
            p.edit()
                .putString(KEY_REFRESH, refreshToken)
                .putString(KEY_ACCESS, accessToken)
                .putLong(KEY_ACCESS_EXP, accessExpiresAt)
                .putLong(KEY_REFRESH_EXP, refreshExpiresAt)
                .apply()
        }.onFailure {
            degraded = true
            Logx.w("Token", "save failed, memory only", it)
        }
    }

    fun clear() {
        accessTokenCache = ""
        refreshTokenCache = ""
        accessExpiresAt = 0L
        refreshExpiresAt = 0L
        runCatching { prefs?.edit()?.clear()?.apply() }
    }

    private fun createEncrypted(context: Context): SharedPreferences? = runCatching {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            PREF_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }.onFailure {
        degraded = true
        Logx.e("Token", "EncryptedSharedPreferences unavailable, memory only", it)
    }.getOrNull()

    companion object {
        const val PREF_NAME = "ec_tokens"
        private const val KEY_ACCESS = "access_token"
        private const val KEY_REFRESH = "refresh_token"
        private const val KEY_ACCESS_EXP = "access_expires_at"
        private const val KEY_REFRESH_EXP = "refresh_expires_at"
    }
}

package top.dreamsearch.englishcoach.core.session

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.serialization.Serializable
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.util.Logx

@Serializable
data class SavedLogin(
    val email: String = "",
    val password: String = "",
)

/**
 * 「记住密码 / 自动登录」（用户要求的基础能力，对应 hos `CredentialStore`）。
 *
 * 安全约束：
 * - 只存 EncryptedSharedPreferences（Keystore 加密），不写普通偏好、不落日志；
 * - 加密不可用时**不降级为明文**：save() 返回 false，页面提示「本机无法安全保存密码」；
 * - 退出登录**不清除**记住的密码（下次仍可一键登录）；用户手动关闭开关才清除。
 */
class CredentialStore(context: Context) {

    private val prefs: SharedPreferences? = runCatching {
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
    }.onFailure { Logx.e("Cred", "encrypted prefs unavailable, remember-password disabled", it) }
        .getOrNull()

    /** 主动退出登录后，本次进程内不再自动登录（否则退出→登录页→立刻又登回去）。 */
    private var suppressAutoLogin: Boolean = false

    fun isAvailable(): Boolean = prefs != null

    fun markLoggedOut() {
        suppressAutoLogin = true
    }

    /** 读取并复位「刚退出登录」标记。 */
    fun consumeAutoLoginSuppressed(): Boolean {
        val value = suppressAutoLogin
        suppressAutoLogin = false
        return value
    }

    /** 保存账号密码；返回 false 表示本机无法安全保存。 */
    fun save(email: String, password: String): Boolean {
        if (email.isEmpty() || password.isEmpty()) {
            clear()
            return true
        }
        val p = prefs ?: return false
        val value = EcJson.encodeToString(SavedLogin.serializer(), SavedLogin(email, password))
        return runCatching {
            p.edit().putString(KEY_LOGIN, value).apply()
            true
        }.getOrElse {
            Logx.e("Cred", "save failed", it)
            false
        }
    }

    /** 读取记住的账号；不存在/解析失败返回 null。 */
    fun load(): SavedLogin? {
        val p = prefs ?: return null
        val text = p.getString(KEY_LOGIN, "") ?: ""
        if (text.isEmpty()) return null
        val saved = runCatching { EcJson.decodeFromString(SavedLogin.serializer(), text) }.getOrNull()
            ?: return null
        if (saved.email.isEmpty() || saved.password.isEmpty()) return null
        return saved
    }

    fun clear() {
        runCatching { prefs?.edit()?.remove(KEY_LOGIN)?.apply() }
    }

    companion object {
        const val PREF_NAME = "ec_credentials"
        private const val KEY_LOGIN = "saved_login"
    }
}

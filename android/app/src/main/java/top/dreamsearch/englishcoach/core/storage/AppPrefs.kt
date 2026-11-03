package top.dreamsearch.englishcoach.core.storage

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

/**
 * 非敏感偏好的唯一入口（对应 hos `AppConfig` 的 Preferences 部分）。
 *
 * - token / 记住的密码**不放这里**（见 [top.dreamsearch.englishcoach.core.session.TokenStore]）；
 * - 只有 [baseUrl]、语速偏好、过期时间戳等非敏感数据落盘。
 */
class AppPrefs(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

    fun getString(key: String, default: String): String = prefs.getString(key, default) ?: default

    fun putString(key: String, value: String) {
        prefs.edit { putString(key, value) }
    }

    fun getInt(key: String, default: Int): Int = prefs.getInt(key, default)

    fun putInt(key: String, value: Int) {
        prefs.edit { putInt(key, value) }
    }

    fun getLong(key: String, default: Long): Long = prefs.getLong(key, default)

    fun putLong(key: String, value: Long) {
        prefs.edit { putLong(key, value) }
    }

    fun getBoolean(key: String, default: Boolean): Boolean = prefs.getBoolean(key, default)

    fun putBoolean(key: String, value: Boolean) {
        prefs.edit { putBoolean(key, value) }
    }

    fun remove(key: String) {
        prefs.edit { remove(key) }
    }

    companion object {
        const val PREF_NAME = "ec_prefs"
    }
}

package top.dreamsearch.englishcoach.core.util

import android.util.Log

/**
 * 日志门面（对应 hos 的 hilog）。
 *
 * 约定：**绝不打印 token / 密码 / 音频内容**；release 构建只保留 warn 及以上。
 */
object Logx {
    private const val TAG_PREFIX = "EC"

    fun d(tag: String, message: String) {
        Log.d("$TAG_PREFIX/$tag", message)
    }

    fun i(tag: String, message: String) {
        Log.i("$TAG_PREFIX/$tag", message)
    }

    fun w(tag: String, message: String, throwable: Throwable? = null) {
        Log.w("$TAG_PREFIX/$tag", message, throwable)
    }

    fun e(tag: String, message: String, throwable: Throwable? = null) {
        Log.e("$TAG_PREFIX/$tag", message, throwable)
    }
}

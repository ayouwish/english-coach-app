package top.dreamsearch.englishcoach.core.error

import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode

/**
 * 用户可见的错误（页面只渲染这个，不直接看 HTTP code）。
 * `message` 是中文、可执行；`actionLabel` 为空表示无动作。
 */
data class UiError(
    val title: String = "",
    val message: String = "",
    val actionLabel: String = "",
    val retryable: Boolean = false,
    val code: String = "",
) {
    companion object {
        fun of(code: String, message: String, retryable: Boolean): UiError =
            UiError(title = "", message = message, actionLabel = if (retryable) "重试" else "", retryable = retryable, code = code)
    }
}

/**
 * 错误 → 中文文案（成人 / 儿童两套，对应 hos `ErrorMapper`）。
 *
 * 规则（docs/architecture.md §6）：
 * - 服务端 `error.message` 已经是中文，优先直接用；
 * - 没有 message 时用本表兜底；
 * - 儿童版更短、更口语，不出现「错误/失败/权限/token」等词。
 */
object ErrorMapper {

    fun from(err: Throwable, isChild: Boolean): UiError {
        if (err is ApiError) return fromApiError(err, isChild)
        return UiError(
            message = if (isChild) "刚才没成功，再试一次吧" else "操作没有完成，请重试",
            actionLabel = if (isChild) "再试一次" else "重试",
            retryable = true,
            code = "unknown",
        )
    }

    private fun fromApiError(err: ApiError, isChild: Boolean): UiError {
        val code = err.code
        val serverMessage = err.detail
        val fallback = messageFor(code, isChild)
        val message = if (err.status > 0 && serverMessage.isNotEmpty() && !isNetworkCode(code)) {
            serverMessage
        } else {
            fallback
        }
        return UiError(
            title = titleFor(code, isChild),
            message = message,
            actionLabel = if (err.retryable) (if (isChild) "再试一次" else "重试") else "",
            retryable = err.retryable,
            code = code,
        )
    }

    private fun isNetworkCode(code: String): Boolean = code in setOf(
        ApiErrorCode.NETWORK_UNREACHABLE,
        ApiErrorCode.TIMEOUT,
        ApiErrorCode.CLEARTEXT_BLOCKED,
        ApiErrorCode.BAD_RESPONSE,
        ApiErrorCode.INTERNAL_ERROR,
    )

    private fun titleFor(code: String, isChild: Boolean): String = when (code) {
        ApiErrorCode.NETWORK_UNREACHABLE -> if (isChild) "连不上家里的网" else "连不上家庭 NAS"
        ApiErrorCode.TIMEOUT -> if (isChild) "等太久啦" else "请求超时"
        ApiErrorCode.UNAUTHORIZED -> if (isChild) "要重新登录了" else "登录已过期"
        ApiErrorCode.MIC_DENIED -> if (isChild) "还听不到你说话" else "需要麦克风权限"
        ApiErrorCode.PROVIDER_ERROR, ApiErrorCode.PROVIDER_UNAVAILABLE ->
            if (isChild) "评分老师休息一下" else "评测服务暂不可用"
        else -> ""
    }

    /** code → 中文兜底文案（服务端 message 缺失时使用）。 */
    fun messageFor(code: String, isChild: Boolean): String = when (code) {
        ApiErrorCode.BAD_REQUEST -> if (isChild) "好像有点不对，再试一次吧" else "请求参数不对，请检查后重试"
        ApiErrorCode.UNAUTHORIZED -> if (isChild) "请重新登录一下" else "登录已过期，请重新登录"
        ApiErrorCode.FORBIDDEN -> if (isChild) "这个要爸爸妈妈才能用哦" else "你没有权限访问这个功能"
        ApiErrorCode.NOT_FOUND -> if (isChild) "这个内容不见了" else "内容不在了，刷新看看"
        ApiErrorCode.AUDIO_NOT_FOUND -> if (isChild) "这段录音找不到了" else "这条录音找不到了，可能已过期"
        ApiErrorCode.AUDIO_GONE -> if (isChild) "录音不见了，再录一次吧" else "录音文件已不存在，请重新录制"
        ApiErrorCode.PAYLOAD_TOO_LARGE -> if (isChild) "这句话太长啦，说短一点" else "文件太大了（录音上限 12MB），请缩短后重试"
        ApiErrorCode.DAILY_LIMIT_REACHED -> if (isChild) "今天已经练得很棒啦，明天再来 🌙" else "今天的练习时长已达上限，明天再来"
        ApiErrorCode.TOO_MANY_REQUESTS -> if (isChild) "试得有点快，等一下再试吧" else "尝试次数过多，请稍后再试"
        ApiErrorCode.CONTENT_UNSAFE -> if (isChild) "这个我们换个说法吧" else "内容未通过审核，请换一种表达"
        ApiErrorCode.INTERNAL_ERROR -> if (isChild) "服务器打了个盹，再试一次吧" else "服务器开小差了，稍后再试"
        ApiErrorCode.PROVIDER_ERROR -> if (isChild) "评分老师有点忙，录音先存好啦" else "语音服务暂时不可用；录音已保存，稍后可重试"
        ApiErrorCode.PROVIDER_UNAVAILABLE -> if (isChild) "这个功能还没开，换一种方式吧" else "该能力当前未启用，请稍后再试"
        ApiErrorCode.PROVIDER_TIMEOUT -> if (isChild) "等太久啦，再试一次吧" else "上游服务超时，请重试"
        ApiErrorCode.NETWORK_UNREACHABLE ->
            if (isChild) "检查一下是不是连着家里的 Wi-Fi"
            else "连不上家里的服务器，请确认连着家庭 Wi-Fi（该域名只在家庭网络可达）"
        ApiErrorCode.TIMEOUT -> if (isChild) "网络有点慢，再试一次吧" else "请求超时了，网络有点慢，请重试"
        ApiErrorCode.CLEARTEXT_BLOCKED -> "当前网络不允许明文 HTTP，请改用 https 地址"
        ApiErrorCode.MIC_DENIED -> if (isChild) "要听到你的声音，需要打开麦克风" else "需要麦克风才能练习，请在设置里允许"
        ApiErrorCode.MIC_UNAVAILABLE -> if (isChild) "麦克风被别人占用了，等一下再试" else "麦克风被占用了，请关闭其他录音应用后重试"
        ApiErrorCode.RECORD_FAILED -> if (isChild) "录音没有成功，再试一次吧" else "录音失败，请重试（或重启 App）"
        ApiErrorCode.RECORD_TOO_SHORT -> if (isChild) "这次录得太短啦，把句子读完再点完成" else "录音太短（少于 0.6 秒），请读完整句后重试"
        ApiErrorCode.RECORD_TOO_LARGE -> if (isChild) "这句话太长啦，短一点好吗" else "录音超过 12MB，请缩短录音"
        ApiErrorCode.PLAYBACK_FAILED -> if (isChild) "声音没有播出来，再点一次吧" else "声音播放失败，请再试一次"
        ApiErrorCode.CACHE_CORRUPT -> if (isChild) "声音文件有点问题，重新下载一次" else "缓存文件损坏，已重新下载"
        ApiErrorCode.BAD_RESPONSE -> if (isChild) "没听懂服务器说什么，再试一次吧" else "服务器返回格式异常，请重试"
        ApiErrorCode.BAD_BASE_URL -> "服务器地址格式不对，示例：https://english.dreamsearch.top"
        else -> if (isChild) "刚才没成功，再试一次吧" else "操作没有完成，请重试"
    }
}

package top.dreamsearch.englishcoach.core.audio

import top.dreamsearch.englishcoach.core.storage.AppPrefs

/**
 * 账号语音偏好的**本机镜像**（对应 ROUND2_CONTRACT §1.2）。
 *
 * 数据来源：`GET /settings` 的 `prefs`（`ttsVoice` / `ttsRate`，camelCase）。
 * 设置页 PATCH 成功后调 [syncFromAccount] 写回；示范音/对话朗读/鼓励语统一用
 * [resolve] 取「音色 + 语速」，不再各页写死 `normal` / `slow`。
 *
 * 规则：
 * - 儿童**强制 `slow`**；儿童没有显式音色时用内置童声 [CHILD_DEFAULT_VOICE]；
 * - 成人默认 `normal`；音色为 null 表示交给服务端默认；
 * - 偏好只存非敏感的 `AppPrefs`（token/密码仍只走 `TokenStore`/`CredentialStore`）。
 */
class VoicePrefs(private val prefs: AppPrefs) {

    /** 一次朗读要用的音色 + 语速（`rate`: `"slow"` | `"normal"`）。 */
    data class VoiceChoice(
        val voice: String?,
        val rate: String,
    )

    /** 账号偏好音色；null = 服务端默认（存储里用空串表示）。 */
    var ttsVoice: String?
        get() = prefs.getString(KEY_VOICE, "").trim().ifEmpty { null }
        set(value) {
            prefs.putString(KEY_VOICE, value?.trim().orEmpty())
        }

    /** 账号偏好语速；只接受 `slow` / `normal`，其它值归一为 `normal`。 */
    var ttsRate: String
        get() = normalizeRate(prefs.getString(KEY_RATE, RATE_NORMAL))
        set(value) {
            prefs.putString(KEY_RATE, normalizeRate(value))
        }

    /**
     * 取本次朗读的音色/语速。
     *
     * - 儿童：语速强制 `slow`；音色 = 已设置音色 ?: [CHILD_DEFAULT_VOICE]；
     * - 成人：语速 = [ttsRate]；音色 = [ttsVoice]（null 交给服务端默认）。
     */
    fun resolve(isChild: Boolean): VoiceChoice {
        val voice = ttsVoice ?: if (isChild) CHILD_DEFAULT_VOICE else null
        val rate = if (isChild) RATE_SLOW else ttsRate
        return VoiceChoice(voice = voice, rate = rate)
    }

    /** `GET /settings`（或 PATCH 响应）里的账号偏好写回本机镜像。 */
    fun syncFromAccount(ttsVoice: String?, ttsRate: String?) {
        this.ttsVoice = ttsVoice?.takeIf { it.isNotBlank() }
        this.ttsRate = normalizeRate(ttsRate.orEmpty())
    }

    /** 直接写入（设置页即时预览用；与 [syncFromAccount] 等价但参数必填语义更明确）。 */
    fun put(voice: String?, rate: String) {
        ttsVoice = voice
        ttsRate = rate
    }

    companion object {
        /** 本机偏好存储 key（ROUND2_CONTRACT §1.2 指定）。 */
        const val KEY_VOICE = "voice_tts_voice"
        const val KEY_RATE = "voice_tts_rate"

        const val RATE_SLOW = "slow"
        const val RATE_NORMAL = "normal"

        /** 儿童默认音色（与 `core/audio/Voices.kt` 的 9 个内置音色一致）。 */
        const val CHILD_DEFAULT_VOICE = "en-US-AnaNeural"

        /** 非法/空语速归一为 `normal`。 */
        fun normalizeRate(raw: String?): String =
            if (raw?.trim()?.lowercase() == RATE_SLOW) RATE_SLOW else RATE_NORMAL
    }
}

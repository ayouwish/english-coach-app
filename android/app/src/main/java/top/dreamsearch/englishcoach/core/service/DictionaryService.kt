package top.dreamsearch.englishcoach.core.service

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.net.EcJson

/**
 * 单词音标查询（`GET /api/words/:word`，v0.19）。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/service/DictionaryService.ets`。
 *
 * 语义（契约 §3.2）：
 * - 404（词典未收录）/ `ipa` 为 null / 音标开关关闭 → 返回 **null**（浮层显示「暂无音标」）；
 * - 网络失败 / 503 也返回 null（点单词查音标是辅助能力，**不能**把正文页面打挂）；
 * - **不做缓存**：契约规定调用方（`ui/component/WordText`）自己维护 LRU 缓存。
 */
class DictionaryService(private val api: ApiClient) {

    /** @return 音标（不含两侧斜杠）；null = 暂无音标 / 音标已关闭 / 查询失败。 */
    suspend fun wordIpa(word: String): String? {
        val trimmed = word.trim()
        if (trimmed.isEmpty()) return null
        val raw = try {
            api.getJson(
                "/words/${java.net.URLEncoder.encode(trimmed, "UTF-8")}",
                null,
                TIMEOUT_MS,
            )
        } catch (ignored: Throwable) {
            return null
        }
        if (raw.status == 404) return null
        if (raw.status !in 200..299) return null
        val dto = try {
            EcJson.decodeFromString<WordIpaDto>(raw.text)
        } catch (ignored: Throwable) {
            null
        } ?: return null
        if (dto.ipaDisabled) return null
        val ipa = dto.ipa?.trim().orEmpty()
        return ipa.ifEmpty { null }
    }

    /** `GET /api/words/:word` 响应（hos 在 service 内联定义，这里同样放私有位置）。 */
    @Serializable
    private data class WordIpaDto(
        val word: String = "",
        val ipa: String? = null,
        val variants: List<String> = emptyList(),
        val syllables: Int? = null,
        @SerialName("ipa_disabled") val ipaDisabled: Boolean = false,
    )

    companion object {
        private const val TIMEOUT_MS = 8_000L
    }
}

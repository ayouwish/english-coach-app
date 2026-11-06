package top.dreamsearch.englishcoach.core.content

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.net.ApiRequest
import top.dreamsearch.englishcoach.core.net.EcJson

/**
 * 能力开关的**统一来源**（对应 ROUND2_CONTRACT §1.1）。
 *
 * 数据源：`GET /api/health` 的 `features` + `voice.capabilities`：
 * - `voice.capabilities.image`         → 插画 / 自动插图
 * - `voice.capabilities.ocr`           → 拍照识别书页
 * - `voice.capabilities.avatar_presets` → 预置形象库（缺失时回退 `features.avatar_presets`）
 * - `voice.capabilities.audio_concat`  → 整段回放
 * - `voice.capabilities.word_ipa`      → 点词音标
 * - `voice.capabilities.asr_providers` → ASR provider 清单
 *
 * 语义（重要）：
 * - **缺省一律按「可用」**：服务端没下发 → 不误隐藏入口；
 * - `cached()` 只在 5 分钟内有效，过期返回 null；页面可先读缓存再后台 [refresh]；
 * - [refresh] 失败（网络/5xx/解析失败）**不抛异常**，返回最近一次快照或全默认值——
 *   能力开关只做入口显隐，不应把页面打成错误态（健康页的严格错误展示走
 *   `PracticeService.health(force=true)` / `StatsService.healthFull`）。
 */
class CapabilityCache(private val api: ApiClient) {

    /** 能力开关（默认全 true = 「假定可用」，避免服务端漏字段时隐藏功能）。 */
    data class Capabilities(
        val image: Boolean = true,
        val ocr: Boolean = true,
        val avatarPresets: Boolean = true,
        val audioConcat: Boolean = true,
        val wordIpa: Boolean = true,
        val asrProviders: List<String> = emptyList(),
    )

    private val mutex = Mutex()

    @Volatile
    private var snapshot: Capabilities? = null

    @Volatile
    private var fetchedAtMs: Long = 0L

    /** 5 分钟内的快照；过期/从未刷新返回 null。 */
    fun cached(): Capabilities? {
        val snap = snapshot ?: return null
        if (System.currentTimeMillis() - fetchedAtMs > TTL_MS) return null
        return snap
    }

    /**
     * 刷新能力开关（并发调用单飞，只发一次 `/health`）。
     *
     * @param force true 时忽略缓存强制请求；false 时命中 5 分钟缓存直接返回。
     * @return 最新快照；失败时返回上一次快照（可能过期）或全默认值，不抛异常。
     */
    suspend fun refresh(force: Boolean = false): Capabilities {
        if (!force) cached()?.let { return it }
        return mutex.withLock {
            // 等锁期间别的协程可能已经刷新过（非 force 时直接复用）
            if (!force) cached()?.let { return@withLock it }
            val fresh = try {
                fetch()
            } catch (e: CancellationException) {
                throw e
            } catch (ignored: Throwable) {
                null
            }
            if (fresh != null) {
                snapshot = fresh
                fetchedAtMs = System.currentTimeMillis()
                fresh
            } else {
                snapshot ?: Capabilities()
            }
        }
    }

    // ------------------------------------------------------------------ 内部

    /** `GET /health`（公开接口：不带 Bearer、不参与 401 刷新），失败返回 null。 */
    private suspend fun fetch(): Capabilities? {
        val raw = api.request(
            ApiRequest(
                method = "GET",
                path = "/health",
                auth = false,
                retryOn401 = false,
                timeoutMs = HEALTH_TIMEOUT_MS,
            )
        )
        if (raw.status !in 200..299) return null
        val dto = runCatching { EcJson.decodeFromString<HealthSnapshotDto>(raw.text) }.getOrNull() ?: return null
        return dto.toCapabilities()
    }

    private fun HealthSnapshotDto.toCapabilities(): Capabilities {
        val caps = voice?.capabilities
        return Capabilities(
            image = caps?.image ?: true,
            ocr = caps?.ocr ?: true,
            avatarPresets = caps?.avatarPresets ?: features?.avatarPresets ?: true,
            audioConcat = caps?.audioConcat ?: true,
            wordIpa = caps?.wordIpa ?: true,
            asrProviders = caps?.asrProviders.orEmpty(),
        )
    }

    companion object {
        /** 缓存有效期：5 分钟（ROUND2_CONTRACT §1.1）。 */
        const val TTL_MS: Long = 5 * 60 * 1000L

        /** 健康检查超时（与 `PracticeService.health` 一致）。 */
        private const val HEALTH_TIMEOUT_MS = 5_000L
    }
}

// ---------------------------------------------------------------------------
// 只取能力开关所需字段的轻量响应（不依赖全量 HealthFullDto，字段全部可空）
// ---------------------------------------------------------------------------

@Serializable
private data class HealthSnapshotDto(
    val features: HealthFeaturesSnapshotDto? = null,
    val voice: HealthVoiceSnapshotDto? = null,
)

@Serializable
private data class HealthFeaturesSnapshotDto(
    @SerialName("avatar_presets") val avatarPresets: Boolean? = null,
)

@Serializable
private data class HealthVoiceSnapshotDto(
    val capabilities: HealthCapsSnapshotDto? = null,
)

@Serializable
private data class HealthCapsSnapshotDto(
    val image: Boolean? = null,
    val ocr: Boolean? = null,
    @SerialName("avatar_presets") val avatarPresets: Boolean? = null,
    @SerialName("audio_concat") val audioConcat: Boolean? = null,
    @SerialName("word_ipa") val wordIpa: Boolean? = null,
    @SerialName("asr_providers") val asrProviders: List<String>? = null,
)

package top.dreamsearch.englishcoach.core.service

import kotlinx.serialization.encodeToString
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.ApiRequest
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.net.FormPart
import top.dreamsearch.englishcoach.core.net.decodeBody
import top.dreamsearch.englishcoach.core.net.dto.AttemptItemDto
import top.dreamsearch.englishcoach.core.net.dto.AttemptListDto
import top.dreamsearch.englishcoach.core.net.dto.AttemptResponseDto
import top.dreamsearch.englishcoach.core.net.dto.HealthDto
import top.dreamsearch.englishcoach.core.net.dto.SentenceDto
import top.dreamsearch.englishcoach.core.net.dto.SentenceListDto
import top.dreamsearch.englishcoach.core.net.dto.TtsBodyDto
import top.dreamsearch.englishcoach.core.net.dto.WarmupBodyDto

/**
 * 跟读相关 API：语料、TTS、同步评测、录音回放、健康检查。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/service/PracticeService.ets`。
 * 数据来源：`docs/architecture.md` §2／docs/api-contract.md（`/sentences`、`/tts`、`/attempts`）。
 *
 * 职责边界：只拼 URL / 转 DTO / 返回字节；**不落盘、不播放、不碰 Context**
 * （音频字节由 VM 交给 `CacheStore` 落盘，再交 `AudioController` 播放）。
 * 线上不存在的接口不实现：`GET /practice/cursor`、`GET /sentences/:id/attempts`、`GET /tts/voices`。
 */
class PracticeService(private val api: ApiClient) {

    /** `GET /api/sentences?level=A1[&focus=<音素>]` */
    suspend fun sentences(level: String, focus: String = ""): List<SentenceDto> {
        val query = LinkedHashMap<String, String>()
        if (level.isNotEmpty()) query["level"] = level
        if (focus.isNotEmpty()) query["focus"] = focus
        val raw = api.getJson("/sentences", query, SENTENCES_TIMEOUT_MS)
        api.requireOk(raw)
        return decodeBody<SentenceListDto>(raw.text, "语料").sentences
    }

    /**
     * `POST /api/tts` → 音频字节。
     *
     * 注意：失败时服务端返回的是 JSON 错误体而不是音频，所以必须「先看 HTTP 状态」，
     * 不能无条件把字节当音频。
     */
    suspend fun tts(
        text: String,
        rate: String,
        voice: String? = null,
        format: String = "wav",
    ): ByteArray {
        val body = EcJson.encodeToString(
            TtsBodyDto(
                text = text,
                rate = rate,
                format = format,
                voice = voice?.takeIf { it.isNotEmpty() },
            )
        )
        val raw = api.postJsonForBytes("/tts", body, TTS_TIMEOUT_MS)
        if (raw.status != 200) {
            throw api.errorOf(raw)
        }
        val bytes = raw.bytes
        if (bytes == null || bytes.size < 64) {
            throw ApiError(ApiErrorCode.CACHE_CORRUPT, 0, "示范音内容为空")
        }
        return bytes
    }

    /** `GET /api/attempts?limit=N` —— 我的评测记录（单句历史/进步曲线的替代数据源）。 */
    suspend fun attempts(limit: Int = 20): List<AttemptItemDto> {
        val query = mapOf("limit" to limit.toString())
        val raw = api.getJson("/attempts", query, SENTENCES_TIMEOUT_MS)
        api.requireOk(raw)
        return decodeBody<AttemptListDto>(raw.text, "评测记录").attempts
    }

    /** `GET /api/audio/:id` → 录音回放字节（交给 VM 落盘后播放；带 Bearer 鉴权）。 */
    suspend fun audio(audioId: String): ByteArray {
        val raw = api.getBytes("/audio/${encodePath(audioId)}", null, TTS_TIMEOUT_MS)
        api.requireOk(raw)
        val bytes = raw.bytes
        if (bytes == null || bytes.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "录音内容为空")
        }
        return bytes
    }

    /**
     * 按 `AttemptItemDto.audio_url` 取录音回放字节（ROUND2_CONTRACT §1.5）。
     *
     * 兼容多种来源形状：
     * - `/api/audio/cm_x`（服务端 `audio_url` 的常规形状）
     * - `/audio/cm_x`、完整 URL（`https://host/api/audio/cm_x?t=...`）
     * - 纯 audio id（`cm_x`）
     *
     * 单句历史逐条回放 / 对话消息回放都走这里，页面不再自己拼 URL。
     */
    suspend fun audioByUrl(audioUrl: String): ByteArray {
        val path = audioPathOf(audioUrl)
        if (path.isEmpty()) {
            throw ApiError.local(ApiErrorCode.AUDIO_NOT_FOUND, "这条记录没有录音")
        }
        val raw = api.getBytes(path, null, TTS_TIMEOUT_MS)
        api.requireOk(raw)
        val bytes = raw.bytes
        if (bytes == null || bytes.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "录音内容为空")
        }
        return bytes
    }

    /**
     * `POST /api/attempts`（multipart，同步评测）。
     * 字段名严格按契约：audio / sentence_id / reference_text / mode / duration_ms [ / blind_test_id ]。
     */
    suspend fun evaluate(
        audio: ByteArray,
        sentenceId: String,
        referenceText: String,
        durationMs: Int = 0,
        blindTestId: String? = null,
        mode: String = "scripted",
    ): AttemptResponseDto {
        if (audio.isEmpty()) {
            throw ApiError.local(ApiErrorCode.RECORD_FAILED, "录音文件为空")
        }
        if (audio.size > MAX_AUDIO_BYTES) {
            throw ApiError.local(ApiErrorCode.RECORD_TOO_LARGE, "录音超过 12MB")
        }
        val parts = mutableListOf(
            FormPart.file("audio", "recording.m4a", audio, "audio/mp4"),
            FormPart.text("sentence_id", sentenceId),
            FormPart.text("reference_text", referenceText),
            FormPart.text("mode", mode),
            FormPart.text("duration_ms", durationMs.toString()),
        )
        blindTestId?.takeIf { it.isNotEmpty() }?.let { parts.add(FormPart.text("blind_test_id", it)) }
        val raw = api.postMultipart("/attempts", null, parts, ATTEMPT_TIMEOUT_MS)
        api.requireOk(raw)
        val dto = decodeBody<AttemptResponseDto>(raw.text, "评测结果")
        if (dto.attemptId.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "评测结果格式异常")
        }
        return dto
    }

    /** `POST /api/attempts/:id/retry` —— 用已存录音重评（degraded 时用，不重新上传）。 */
    suspend fun retryAttempt(attemptId: String): AttemptResponseDto {
        val raw = api.request(
            ApiRequest(
                method = "POST",
                path = "/attempts/${encodePath(attemptId)}/retry",
                timeoutMs = ATTEMPT_TIMEOUT_MS,
            )
        )
        api.requireOk(raw)
        val dto = decodeBody<AttemptResponseDto>(raw.text, "评测结果")
        if (dto.attemptId.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "评测结果格式异常")
        }
        return dto
    }

    /**
     * `GET /api/health`（无需登录，5s 超时）。
     *
     * @param force true 时加 `?force=1` 跳过服务端 15s 缓存（健康页「强制刷新」用）；
     *   默认 false，既有 `health()` 调用点保持编译。
     */
    suspend fun health(force: Boolean = false): HealthDto {
        val raw = api.request(
            ApiRequest(
                method = "GET",
                path = "/health",
                query = if (force) mapOf("force" to "1") else null,
                auth = false,
                retryOn401 = false,
                timeoutMs = HEALTH_TIMEOUT_MS,
            )
        )
        api.requireOk(raw)
        return decodeBody<HealthDto>(raw.text, "健康检查")
    }

    /**
     * `POST /api/warmup` —— TTS 预热，fire-and-forget（失败静默，不展示）。
     *
     * Kotlin 版是 suspend：调用方应在 `viewModelScope.launch { ... }` 里单独跑，
     * 不要 await（否则会把 30s 预热等成主流程阻塞）。
     */
    suspend fun warmup(texts: List<String>, rate: String = "normal") {
        if (texts.isEmpty()) return
        val limited = texts.take(MAX_WARMUP_TEXTS)
        val body = EcJson.encodeToString(WarmupBodyDto(texts = limited, rate = rate))
        try {
            api.request(
                ApiRequest(
                    method = "POST",
                    path = "/warmup",
                    jsonBody = body,
                    timeoutMs = WARMUP_TIMEOUT_MS,
                )
            )
        } catch (ignored: Throwable) {
            // 预热失败静默
        }
    }

    // ------------------------------------------------------------------ 内部

    /**
     * 把各种形状的 `audio_url` 归一为 `ApiClient` 需要的「不含 `/api` 前缀」路径。
     *
     * `/api/audio/cm_1` → `/audio/cm_1`；`/audio/cm_1` 原样；完整 URL 取 path；
     * 纯 id → `/audio/<id>`；带 query/fragment 的先剥掉。
     */
    private fun audioPathOf(rawUrl: String): String {
        var url = rawUrl.trim()
        if (url.isEmpty()) return ""
        val cut = url.indexOfFirst { it == '?' || it == '#' }
        if (cut >= 0) url = url.substring(0, cut)
        if (url.isEmpty()) return ""
        val apiIndex = url.indexOf("/api/")
        if (apiIndex >= 0) return url.substring(apiIndex + 4)
        if (url.startsWith("/")) return url
        if (url.startsWith("http://", ignoreCase = true) || url.startsWith("https://", ignoreCase = true)) {
            val path = url.substringAfter("://").substringAfter('/', "")
            return if (path.isEmpty()) "" else "/$path"
        }
        return "/audio/${encodePath(url)}"
    }

    /** 路径段编码（id 只含安全字符，仍做一次编码避免拼出怪 URL）。 */
    private fun encodePath(segment: String): String =
        java.net.URLEncoder.encode(segment, "UTF-8")

    companion object {
        private const val SENTENCES_TIMEOUT_MS = 15_000L
        private const val TTS_TIMEOUT_MS = 30_000L
        /** 同步评测最长约 100s（pronounce 60s + feedback 40s），客户端给 120s */
        private const val ATTEMPT_TIMEOUT_MS = 120_000L
        private const val HEALTH_TIMEOUT_MS = 5_000L
        private const val WARMUP_TIMEOUT_MS = 30_000L
        private const val MAX_AUDIO_BYTES = 12 * 1024 * 1024
        private const val MAX_WARMUP_TEXTS = 12
    }
}

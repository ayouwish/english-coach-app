package top.dreamsearch.englishcoach.core.service

import kotlinx.serialization.encodeToString
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.ApiRequest
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.net.FormPart
import top.dreamsearch.englishcoach.core.net.decodeBody
import top.dreamsearch.englishcoach.core.net.dto.MaterialPatchBodyDto
import top.dreamsearch.englishcoach.core.net.dto.StoryAsrDto
import top.dreamsearch.englishcoach.core.net.dto.StoryAudioStatusDto
import top.dreamsearch.englishcoach.core.net.dto.StoryIllustrateBodyDto
import top.dreamsearch.englishcoach.core.net.dto.StoryIllustrationDto
import top.dreamsearch.englishcoach.core.net.dto.StoryMaterialCreateDto
import top.dreamsearch.englishcoach.core.net.dto.StoryMaterialDto
import top.dreamsearch.englishcoach.core.net.dto.StoryMaterialListDto
import top.dreamsearch.englishcoach.core.net.dto.StoryRetellBodyDto
import top.dreamsearch.englishcoach.core.net.dto.StoryRetellDto
import top.dreamsearch.englishcoach.core.net.dto.StoryRewriteBodyDto
import top.dreamsearch.englishcoach.core.net.dto.StoryRewriteDto

/**
 * 故事模式 API（材料 / 转录 / 改写 / 复述 / 插画 / 整段朗读回放 / 图片）。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/service/StoryService.ets`。
 * 数据来源：`.specs/chat-story.md` §3。
 *
 * 线上降级（2026-11-03 实测，与 hos 一致）：
 * - `POST /api/story/recordings` 是 404 → 录音转写一律走 `asr()`（`POST /api/asr?language=`）；
 * - 复述 = 两步：先 `asr(language="en-US")` 拿 transcript，再 `retell()`。
 *
 * 职责边界：只拼 URL / 传字节 / 转 DTO；不落盘、不播放、不碰 Context
 * （图片 / 整段朗读字节由 VM 交给 `CacheStore`）。
 */
class StoryService(private val api: ApiClient) {

    // ------------------------------------------------------------------ 故事集

    /**
     * `GET /api/materials?kind=story&limit=N&offset=M`（家庭共享，服务端已排序）。
     * `kind` 默认 story，书页场景可传 page。
     */
    suspend fun materials(
        kind: String = "story",
        limit: Int = 50,
        offset: Int = 0,
    ): List<StoryMaterialDto> {
        val query = mapOf(
            "kind" to kind,
            "limit" to limit.toString(),
            "offset" to offset.toString(),
        )
        val raw = api.getJson("/materials", query, LIST_TIMEOUT_MS)
        api.requireOk(raw)
        return decodeBody<StoryMaterialListDto>(raw.text, "故事列表").items
    }

    /** `GET /api/materials/:id` */
    suspend fun materialDetail(id: String): StoryMaterialDto {
        val raw = api.getJson("/materials/${encodePath(id)}", null, DETAIL_TIMEOUT_MS)
        api.requireOk(raw)
        val dto = decodeBody<StoryMaterialDto>(raw.text, "故事详情")
        if (dto.id.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "故事详情返回格式异常")
        }
        return dto
    }

    /** `POST /api/materials`（kind=story，201）→ 新建故事摘要。 */
    suspend fun createMaterial(
        title: String,
        text: String,
        sourceZh: String,
        level: String,
        kind: String = "story",
    ): StoryMaterialDto {
        val body = EcJson.encodeToString(
            StoryMaterialCreateDto(
                title = title,
                text = text,
                kind = kind,
                sourceZh = sourceZh,
                level = level,
                source = "text",
            )
        )
        val raw = api.postJson("/materials", body, auth = true, timeoutMs = SAVE_TIMEOUT_MS)
        api.requireOk(raw)
        val dto = decodeBody<StoryMaterialDto>(raw.text, "故事保存")
        if (dto.id.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "故事保存返回格式异常")
        }
        return dto
    }

    /** `PATCH /materials/:id` —— 只改标题（服务端校验只能改自己录入的）。 */
    suspend fun renameMaterial(id: String, title: String) {
        val body = EcJson.encodeToString(MaterialPatchBodyDto(title = title))
        val raw = api.patchJson("/materials/${encodePath(id)}", body, SAVE_TIMEOUT_MS)
        api.requireOk(raw)
    }

    /** `DELETE /materials/:id` —— 删除故事（服务端校验只能删自己录入的）。 */
    suspend fun deleteMaterial(id: String) {
        val raw = api.deleteJson("/materials/${encodePath(id)}", SAVE_TIMEOUT_MS)
        api.requireOk(raw)
    }

    // ------------------------------------------------------------------ 转录 / 改写 / 复述

    /**
     * `POST /api/asr?language=xx[&provider=]`（multipart，字段名 `audio`）。
     *
     * @param language 讲故事录音用 `zh-CN`（默认），复述用 `en-US`。
     * @return 识别文本；空文本转成 `bad_response`（带服务端 error 文案或「没有听清，再说一次吧」）。
     */
    suspend fun asr(audio: ByteArray, language: String = "zh-CN", provider: String? = null): String {
        if (audio.isEmpty()) {
            throw ApiError.local(ApiErrorCode.RECORD_FAILED, "录音文件为空")
        }
        if (audio.size > MAX_AUDIO_BYTES) {
            throw ApiError.local(ApiErrorCode.RECORD_TOO_LARGE, "录音超过 25MB")
        }
        val query = LinkedHashMap<String, String>()
        query["language"] = language
        provider?.takeIf { it.isNotEmpty() }?.let { query["provider"] = it }
        val parts = listOf(FormPart.file("audio", "story.m4a", audio, "audio/mp4"))
        val raw = api.postMultipart("/asr", query, parts, ASR_TIMEOUT_MS)
        api.requireOk(raw)
        val dto = decodeBody<StoryAsrDto>(raw.text, "语音识别")
        val text = dto.text.trim()
        if (text.isEmpty()) {
            val providerError = dto.error
            throw ApiError(
                ApiErrorCode.BAD_RESPONSE,
                raw.status,
                if (providerError != null && providerError.isNotEmpty()) providerError else "没有听清，再说一次吧",
            )
        }
        return text
    }

    /** `POST /api/story/rewrite`（中文 → 分级英文）。 */
    suspend fun rewrite(
        textZh: String,
        level: String,
        maxSentences: Int,
        tense: String? = null,
        useWeakPhonemes: Boolean = false,
    ): StoryRewriteDto {
        val body = EcJson.encodeToString(
            StoryRewriteBodyDto(
                textZh = textZh,
                level = level,
                maxSentences = maxSentences,
                useWeakPhonemes = useWeakPhonemes,
                tense = tense?.takeIf { it.isNotEmpty() } ?: "auto",
            )
        )
        val raw = api.postJson("/story/rewrite", body, auth = true, timeoutMs = REWRITE_TIMEOUT_MS)
        api.requireOk(raw)
        val dto = decodeBody<StoryRewriteDto>(raw.text, "故事改写")
        if (dto.sentences.isEmpty() && dto.textEn.isBlank()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "故事改写结果为空，请重试")
        }
        return dto
    }

    /** `POST /api/story/retell`（不评发音分）。`materialId` 为空串时不传。 */
    suspend fun retell(
        materialId: String,
        storySentences: List<String>,
        transcript: String,
        level: String,
    ): StoryRetellDto {
        val body = EcJson.encodeToString(
            StoryRetellBodyDto(
                materialId = materialId.ifEmpty { null },
                storySentences = storySentences,
                transcript = transcript,
                level = level,
            )
        )
        val raw = api.postJson("/story/retell", body, auth = true, timeoutMs = RETELL_TIMEOUT_MS)
        api.requireOk(raw)
        return decodeBody<StoryRetellDto>(raw.text, "复述结果")
    }

    // ------------------------------------------------------------------ 插画

    /**
     * `POST /api/story/:id/illustrate[?force=1]`（返回 prompt_used）。
     * Android `ApiClient` 没有「POST + query + JSON」快捷入口，这里用裸 [ApiRequest]。
     */
    suspend fun illustrate(materialId: String, force: Boolean = false): StoryIllustrationDto {
        val body = EcJson.encodeToString(StoryIllustrateBodyDto(force = force, style = "watercolor"))
        val raw = api.request(
            ApiRequest(
                method = "POST",
                path = "/story/${encodePath(materialId)}/illustrate",
                query = if (force) mapOf("force" to "1") else null,
                jsonBody = body,
                timeoutMs = ILLUSTRATE_TIMEOUT_MS,
            )
        )
        api.requireOk(raw)
        return decodeBody<StoryIllustrationDto>(raw.text, "插画")
    }

    // ------------------------------------------------------------------ 整段朗读回放

    /**
     * `GET /api/story/:id/audio/status`（只读，绝不触发构建）。
     * 404（no_audio）不抛错，转成 `status:"no_audio"` 交给 UI 隐藏播放器。
     */
    suspend fun audioStatus(materialId: String): StoryAudioStatusDto {
        val raw = api.getJson(
            "/story/${encodePath(materialId)}/audio/status",
            null,
            AUDIO_STATUS_TIMEOUT_MS,
        )
        if (raw.status == 200) {
            val dto = decodeBody<StoryAudioStatusDto>(raw.text, "整段回放状态")
            return if (dto.status.isEmpty()) dto.copy(status = "building") else dto
        }
        if (raw.status == 404) {
            val error = api.errorOf(raw)
            return StoryAudioStatusDto(
                status = "no_audio",
                error = error.detail.ifEmpty { "这个故事还没有可回放的朗读录音" },
            )
        }
        throw api.errorOf(raw)
    }

    /**
     * `GET /api/story/:id/audio[?force=1]`。
     *
     * @return 200 → 音频字节；202（还在构建）→ null（页面继续轮询 status）。
     */
    suspend fun storyAudio(materialId: String, force: Boolean = false): ByteArray? {
        val query = if (force) mapOf("force" to "1") else null
        val raw = api.getBytes(
            "/story/${encodePath(materialId)}/audio",
            query,
            AUDIO_TIMEOUT_MS,
        )
        if (raw.status == 202) return null
        api.requireOk(raw)
        val bytes = raw.bytes
        if (bytes == null || bytes.size < MIN_AUDIO_BYTES) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "整段朗读音频为空")
        }
        return bytes
    }

    // ------------------------------------------------------------------ 图片

    /** `GET /api/materials/:id/image` → 图片字节（带 Bearer，必须由客户端下载后落盘再显示）。 */
    suspend fun materialImage(materialId: String): ByteArray {
        val raw = api.getBytes(
            "/materials/${encodePath(materialId)}/image",
            null,
            DETAIL_TIMEOUT_MS,
        )
        api.requireOk(raw)
        val bytes = raw.bytes
        if (bytes == null || bytes.size < MIN_IMAGE_BYTES) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "图片内容为空")
        }
        return bytes
    }

    // ------------------------------------------------------------------ 内部

    private fun encodePath(segment: String): String =
        java.net.URLEncoder.encode(segment, "UTF-8")

    companion object {
        private const val LIST_TIMEOUT_MS = 20_000L
        private const val DETAIL_TIMEOUT_MS = 20_000L
        /** ASR 可能 60s+；给 120s */
        private const val ASR_TIMEOUT_MS = 120_000L
        private const val REWRITE_TIMEOUT_MS = 120_000L
        private const val RETELL_TIMEOUT_MS = 120_000L
        /** 生图很慢（10–30s），留足余量 */
        private const val ILLUSTRATE_TIMEOUT_MS = 180_000L
        private const val SAVE_TIMEOUT_MS = 30_000L
        private const val AUDIO_STATUS_TIMEOUT_MS = 15_000L
        private const val AUDIO_TIMEOUT_MS = 120_000L
        private const val MAX_AUDIO_BYTES = 25 * 1024 * 1024
        private const val MIN_AUDIO_BYTES = 64
        private const val MIN_IMAGE_BYTES = 32
    }
}

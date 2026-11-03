package top.dreamsearch.englishcoach.core.service

import kotlinx.serialization.encodeToString
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.net.FormPart
import top.dreamsearch.englishcoach.core.net.decodeBody
import top.dreamsearch.englishcoach.core.net.dto.AsyncStatusDto
import top.dreamsearch.englishcoach.core.net.dto.AsyncStatusItemDto
import top.dreamsearch.englishcoach.core.net.dto.AsyncSubmitDto
import top.dreamsearch.englishcoach.core.net.dto.FlowDiagnosisDto
import top.dreamsearch.englishcoach.core.net.dto.MaterialCreateBodyDto
import top.dreamsearch.englishcoach.core.net.dto.MaterialDetailDto
import top.dreamsearch.englishcoach.core.net.dto.MaterialDto
import top.dreamsearch.englishcoach.core.net.dto.MaterialListDto
import top.dreamsearch.englishcoach.core.net.dto.MaterialPatchBodyDto
import top.dreamsearch.englishcoach.core.net.dto.OcrResultDto

/**
 * 连读模式（/flow）：书页材料、拍照识别、异步评分、轮询、批次诊断。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/service/FlowService.ets`。
 * 数据来源：`.specs/practice-flow.md` §2.12–§2.14；`docs/api-contract.md`。
 *
 * 后端实况（2026-11-03 线上，与 hos 一致）：
 * - 存在：`/materials`、`/ocr`、`/attempts/async`、`/attempts/status`、`/diagnosis?scope=batch`；
 * - **不存在**：`/practice/cursor`、`/sentences/:id/attempts` → 本服务不调用；
 *   游标用本地偏好（`AppPrefs`），单句历史用 `PracticeService.attempts(limit)` 过滤。
 *
 * 职责边界：只拼 URL / 转 DTO / 返回字节；不落盘、不弹 Toast、不碰 Context。
 */
class FlowService(private val api: ApiClient) {

    // ------------------------------------------------------------------ 书页

    /** `GET /materials?kind=page&limit=N` —— 家庭共享的「我的书页」。 */
    suspend fun materialsPage(limit: Int = 50): List<MaterialDto> {
        val query = mapOf("kind" to "page", "limit" to limit.toString())
        val raw = api.getJson("/materials", query, SHORT)
        api.requireOk(raw)
        return decodeBody<MaterialListDto>(raw.text, "书页列表").items
    }

    /** `GET /materials/:id` —— 书页详情（含 text）。 */
    suspend fun materialDetail(id: String): MaterialDetailDto {
        val raw = api.getJson("/materials/${encodePath(id)}", null, SHORT)
        api.requireOk(raw)
        return decodeBody<MaterialDetailDto>(raw.text, "书页详情")
    }

    /**
     * `POST /materials {title,text,kind:page,source}` → 201 新建书页摘要。
     * 连读只存文字（OCR 的图片不落库；识别结果已在客户端转成文字）。
     */
    suspend fun createPage(title: String, text: String, source: String = "text"): MaterialDto {
        val body = EcJson.encodeToString(
            MaterialCreateBodyDto(title = title, text = text, kind = "page", source = source)
        )
        val raw = api.postJson("/materials", body, auth = true, timeoutMs = SHORT)
        api.requireOk(raw)
        return decodeBody<MaterialDto>(raw.text, "保存书页")
    }

    /** `POST /materials` 的兼容入口（旧调用方不关心返回的书页 id）。 */
    suspend fun savePage(title: String, text: String): MaterialDto =
        createPage(title = title, text = text, source = "text")

    /** `PATCH /materials/:id` —— 重命名 / 改文本；null 字段不传（PATCH = 未传取原值）。 */
    suspend fun updatePage(id: String, title: String? = null, text: String? = null) {
        val body = EcJson.encodeToString(MaterialPatchBodyDto(title = title, text = text))
        val raw = api.patchJson("/materials/${encodePath(id)}", body, SHORT)
        api.requireOk(raw)
    }

    /** `DELETE /materials/:id` —— 删除书页（服务端校验只能删自己录入的）。 */
    suspend fun deletePage(id: String) {
        val raw = api.deleteJson("/materials/${encodePath(id)}", SHORT)
        api.requireOk(raw)
    }

    // ------------------------------------------------------------------ OCR

    /** `POST /ocr`（multipart `image`）→ 识别书页文字。 */
    suspend fun ocr(imageBytes: ByteArray, fileName: String): OcrResultDto {
        if (imageBytes.isEmpty()) {
            throw ApiError.local(ApiErrorCode.BAD_REQUEST, "图片文件为空")
        }
        val contentType = imageContentType(fileName)
        val remoteName = imageFileName(fileName)
        val parts = listOf(FormPart.file("image", remoteName, imageBytes, contentType))
        val raw = api.postMultipart("/ocr", null, parts, OCR_TIMEOUT)
        api.requireOk(raw)
        return decodeBody<OcrResultDto>(raw.text, "识别结果")
    }

    // ------------------------------------------------------------------ 异步评分

    /**
     * `POST /attempts/async` —— 录完即走（multipart）。
     * 字段：audio / reference_text / mode=scripted / duration_ms / source
     *      [ / sentence_id / material_id / blind_test_id ]。
     *
     * 盲测提交时响应只有 `attempt_id` / `blind` / `progress`，不含分数。
     */
    suspend fun submitAsync(
        audio: ByteArray,
        sentenceId: String?,
        referenceText: String,
        blindTestId: String? = null,
        source: String = "custom",
        materialId: String? = null,
        durationMs: Int = 0,
    ): AsyncSubmitDto {
        if (audio.isEmpty()) {
            throw ApiError.local(ApiErrorCode.RECORD_FAILED, "录音文件为空")
        }
        if (audio.size > MAX_AUDIO_BYTES) {
            throw ApiError.local(ApiErrorCode.RECORD_TOO_LARGE, "录音超过 12MB")
        }
        val parts = mutableListOf(
            FormPart.file("audio", "recording.m4a", audio, "audio/mp4"),
            FormPart.text("reference_text", referenceText),
            FormPart.text("mode", "scripted"),
            FormPart.text("duration_ms", durationMs.toString()),
            FormPart.text("source", source),
        )
        sentenceId?.takeIf { it.isNotEmpty() }?.let { parts.add(FormPart.text("sentence_id", it)) }
        materialId?.takeIf { it.isNotEmpty() }?.let { parts.add(FormPart.text("material_id", it)) }
        blindTestId?.takeIf { it.isNotEmpty() }?.let { parts.add(FormPart.text("blind_test_id", it)) }
        val raw = api.postMultipart("/attempts/async", null, parts, UPLOAD)
        api.requireOk(raw)
        return decodeBody<AsyncSubmitDto>(raw.text, "提交评分")
    }

    /** `GET /attempts/status?ids=a,b,c` —— 最多 50 个 id；空入参直接返回空。 */
    suspend fun status(ids: List<String>): List<AsyncStatusItemDto> {
        if (ids.isEmpty()) return emptyList()
        val limited = ids.take(MAX_STATUS_IDS)
        val raw = api.getJson(
            "/attempts/status",
            mapOf("ids" to limited.joinToString(",")),
            SHORT,
        )
        api.requireOk(raw)
        return decodeBody<AsyncStatusDto>(raw.text, "评分状态").items
    }

    /** `GET /diagnosis?scope=batch&attempt_ids=...` —— 连读汇总页「这一批的问题」（≤20）。 */
    suspend fun diagnosisBatch(attemptIds: List<String>): FlowDiagnosisDto {
        val limited = attemptIds.take(BATCH_MAX)
        val raw = api.getJson(
            "/diagnosis",
            mapOf("scope" to "batch", "attempt_ids" to limited.joinToString(",")),
            SHORT,
        )
        api.requireOk(raw)
        return decodeBody<FlowDiagnosisDto>(raw.text, "诊断")
    }

    // ------------------------------------------------------------------ 内部

    /** 服务端按文件头二次校验，但仍显式给正确的 Content-Type。 */
    private fun imageContentType(fileName: String): String = when {
        fileName.endsWith(".png", ignoreCase = true) -> "image/png"
        fileName.endsWith(".heic", ignoreCase = true) -> "image/heic"
        fileName.endsWith(".heif", ignoreCase = true) -> "image/heif"
        fileName.endsWith(".webp", ignoreCase = true) -> "image/webp"
        else -> "image/jpeg"
    }

    private fun imageFileName(fileName: String): String = when {
        fileName.endsWith(".png", ignoreCase = true) -> "page.png"
        fileName.endsWith(".heic", ignoreCase = true) -> "page.heic"
        fileName.endsWith(".heif", ignoreCase = true) -> "page.heif"
        fileName.endsWith(".webp", ignoreCase = true) -> "page.webp"
        else -> "page.jpg"
    }

    private fun encodePath(segment: String): String =
        java.net.URLEncoder.encode(segment, "UTF-8")

    companion object {
        /** 普通 JSON 请求（列表/详情/状态/诊断） */
        private const val SHORT = 15_000L
        /** 上传录音（12MB）与提交异步评分 */
        private const val UPLOAD = 60_000L
        /** OCR 首次识别可能 1–2s，给足 60s */
        private const val OCR_TIMEOUT = 60_000L
        /** 诊断 batch 最多 20 个 id（服务端硬限制） */
        private const val BATCH_MAX = 20
        /** /attempts/status 最多 50 个 id */
        private const val MAX_STATUS_IDS = 50
        private const val MAX_AUDIO_BYTES = 12 * 1024 * 1024
    }
}

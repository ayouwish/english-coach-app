package top.dreamsearch.englishcoach.core.service

import kotlinx.serialization.encodeToString
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.ApiRequest
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.net.decodeBody
import top.dreamsearch.englishcoach.core.net.dto.BlindFinishDto
import top.dreamsearch.englishcoach.core.net.dto.BlindTestListDto
import top.dreamsearch.englishcoach.core.net.dto.BlindTestStartDto
import top.dreamsearch.englishcoach.core.net.dto.DiagnosisResponseDto
import top.dreamsearch.englishcoach.core.net.dto.HealthFullDto
import top.dreamsearch.englishcoach.core.net.dto.ReviewGradeBodyDto
import top.dreamsearch.englishcoach.core.net.dto.ReviewGradeResultDto
import top.dreamsearch.englishcoach.core.net.dto.ReviewResponseDto

/**
 * 统计类 API：发音诊断（4 个 scope）、错音本 SRS、盲测、健康检查全字段。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/service/StatsService.ets`。
 * 数据来源：`.specs/practice-flow.md` §2.14–§2.16、`.specs/account-misc.md` §7。
 *
 * 职责边界：只拼 URL / 转 DTO；不持有页面状态、不弹 Toast。
 *
 * 注意（契约与 hos 的差异）：
 * - `gradeReview` 的 grade 是**字符串**（`again|hard|good|easy`），不是数字——
 *   服务端 `POST /review` 入参为 `{card_id, grade}`，`ReviewGradeDto.grade` 也是字符串；
 * - `diagnosis` 的 scope：`all` / `recent&days=7` / `attempt&attempt_id=` / `batch&attempt_ids=`。
 */
class StatsService(private val api: ApiClient) {

    /**
     * `GET /diagnosis`。
     *
     * - `scope=recent` 需要 days（默认 7，上限 365）；
     * - `scope=attempt` 需要 attemptId；
     * - `scope=batch` 需要 attemptIds（≤20，服务端超限会 400 invalid_scope）。
     */
    suspend fun diagnosis(
        scope: String = "all",
        days: Int? = null,
        attemptId: String? = null,
        attemptIds: List<String>? = null,
    ): DiagnosisResponseDto {
        val query = LinkedHashMap<String, String>()
        query["scope"] = scope
        when (scope) {
            "recent" -> {
                var window = days ?: 7
                if (window < 1) window = 7
                if (window > 365) window = 365
                query["days"] = window.toString()
            }

            "attempt" -> {
                val id = attemptId?.trim().orEmpty()
                if (id.isEmpty()) {
                    throw ApiError.local(ApiErrorCode.BAD_REQUEST, "缺少评测记录，无法完成这次诊断")
                }
                query["attempt_id"] = id
            }

            "batch" -> {
                val limited = (attemptIds ?: emptyList()).take(BATCH_MAX)
                if (limited.isEmpty()) {
                    throw ApiError.local(ApiErrorCode.BAD_REQUEST, "缺少评测记录，无法做本批诊断")
                }
                query["attempt_ids"] = limited.joinToString(",")
            }
        }
        val raw = api.getJson("/diagnosis", query, SHORT)
        api.requireOk(raw)
        return decodeBody<DiagnosisResponseDto>(raw.text, "诊断报告")
    }

    /** `GET /review?limit=N`（N 上限 50，默认 20）。 */
    suspend fun review(limit: Int = 20): ReviewResponseDto {
        var count = limit
        if (count < 1) count = 20
        if (count > 50) count = 50
        val raw = api.getJson("/review", mapOf("limit" to count.toString()), SHORT)
        api.requireOk(raw)
        return decodeBody<ReviewResponseDto>(raw.text, "错音本")
    }

    /** `POST /review {card_id, grade}` —— grade ∈ again | hard | good | easy。 */
    suspend fun gradeReview(cardId: String, grade: String): ReviewGradeResultDto {
        val body = EcJson.encodeToString(ReviewGradeBodyDto(cardId = cardId, grade = grade))
        val raw = api.postJson("/review", body, auth = true, timeoutMs = POST_TIMEOUT)
        api.requireOk(raw)
        return decodeBody<ReviewGradeResultDto>(raw.text, "评分结果")
    }

    /** `GET /blind-tests[?user_id=]` —— 家长可看孩子；儿童带别人 id 会 403。 */
    suspend fun blindTests(userId: String = ""): BlindTestListDto {
        val query = if (userId.isNotEmpty()) mapOf("user_id" to userId) else null
        val raw = api.getJson("/blind-tests", query, SHORT)
        api.requireOk(raw)
        return decodeBody<BlindTestListDto>(raw.text, "盲测列表")
    }

    /** `POST /blind-tests`（空 body；已有进行中的批次会直接返回它，`resumed=true`）。 */
    suspend fun startBlindTest(): BlindTestStartDto {
        val raw = api.postJson("/blind-tests", "{}", auth = true, timeoutMs = POST_TIMEOUT)
        api.requireOk(raw)
        return decodeBody<BlindTestStartDto>(raw.text, "盲测创建")
    }

    /** `POST /blind-tests/:id/finish`（幂等）。 */
    suspend fun finishBlindTest(blindTestId: String): BlindFinishDto {
        val raw = api.postJson(
            "/blind-tests/${encodePath(blindTestId)}/finish",
            "{}",
            auth = true,
            timeoutMs = POST_TIMEOUT,
        )
        api.requireOk(raw)
        return decodeBody<BlindFinishDto>(raw.text, "盲测报告")
    }

    /**
     * `GET /health[?force=1]`（无需登录，5s 超时）—— 全字段版。
     * `force=true` 跳过服务端 15s 缓存；健康页与降级判断都用它。
     * 与 [PracticeService.health] 一致：不注入 Bearer、不参与 401 刷新。
     */
    suspend fun healthFull(force: Boolean = false): HealthFullDto {
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
        return decodeBody<HealthFullDto>(raw.text, "健康检查")
    }

    // ------------------------------------------------------------------ 内部

    private fun encodePath(segment: String): String =
        java.net.URLEncoder.encode(segment, "UTF-8")

    companion object {
        private const val SHORT = 15_000L
        private const val POST_TIMEOUT = 30_000L
        private const val HEALTH_TIMEOUT_MS = 5_000L
        /** 诊断 batch 最多 20 个 id（服务端硬限制） */
        private const val BATCH_MAX = 20
    }
}

package top.dreamsearch.englishcoach.core.service

import kotlinx.serialization.encodeToString
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.net.decodeBody
import top.dreamsearch.englishcoach.core.net.dto.AvatarDescBodyDto
import top.dreamsearch.englishcoach.core.net.dto.AvatarPresetsDto
import top.dreamsearch.englishcoach.core.net.dto.AvatarSelectBodyDto
import top.dreamsearch.englishcoach.core.net.dto.AvatarStateDto
import top.dreamsearch.englishcoach.core.net.dto.FamilyCreateBodyDto
import top.dreamsearch.englishcoach.core.net.dto.FamilyMemberDto
import top.dreamsearch.englishcoach.core.net.dto.FamilyMemberListDto
import top.dreamsearch.englishcoach.core.net.dto.FamilyMemberResponseDto
import top.dreamsearch.englishcoach.core.net.dto.FamilyPatchBodyDto
import top.dreamsearch.englishcoach.core.net.dto.ParentSummaryDto
import top.dreamsearch.englishcoach.core.net.dto.ResetPasswordBodyDto
import top.dreamsearch.englishcoach.core.net.dto.SettingsPatchBodyDto
import top.dreamsearch.englishcoach.core.net.dto.SettingsResponseDto
import top.dreamsearch.englishcoach.core.net.dto.SuggestionContextDto
import top.dreamsearch.englishcoach.core.net.dto.SuggestionCreateBodyDto
import top.dreamsearch.englishcoach.core.net.dto.SuggestionCreateResultDto
import top.dreamsearch.englishcoach.core.net.dto.SuggestionListDto
import top.dreamsearch.englishcoach.core.net.dto.SuggestionPatchBodyDto

/**
 * 账号类 API：设置偏好、家庭成员、家长面板、建议箱、虚拟形象。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/service/AccountService.ets`。
 * 数据来源：`.specs/account-misc.md` §3–§9、`.specs/chat-story.md` §4。
 *
 * 关键约束（§10.2，必须照抄）：
 * - 儿童 `PATCH /settings` **绝不能**带 `daily_limit_minutes` / `allow_free_chat`（服务端 403），
 *   由 VM 构造 [SettingsPatchBodyDto] 时控制（本服务不偷偷补字段）；
 * - `PATCH /settings` 返回的 user 是瘦身版，调用方不要用它覆盖 gender/autoIllustrate/storySentences；
 * - 判断权限只看 HTTP 状态码（儿童 403 不跳登录）；
 * - 照片生成形象已按隐私策略关闭（multipart 会 403 policy_disabled），本服务不提供照片上传；
 * - hos 没有 `DELETE /family/members/:id`（没有移除成员接口），因此**不实现** deleteMember。
 */
class AccountService(private val api: ApiClient) {

    // ------------------------------------------------------------------ 设置

    /** `GET /settings` —— user（全量）+ prefs（camelCase）+ usage。 */
    suspend fun settings(): SettingsResponseDto {
        val raw = api.getJson("/settings", null, SHORT)
        api.requireOk(raw)
        return decodeBody<SettingsResponseDto>(raw.text, "设置")
    }

    /** `PATCH /settings` —— 入参 snake_case；返回瘦身 user + 完整 prefs + 最新 usage。 */
    suspend fun patchSettings(body: SettingsPatchBodyDto): SettingsResponseDto {
        val json = EcJson.encodeToString(body)
        val raw = api.patchJson("/settings", json, WRITE_TIMEOUT)
        api.requireOk(raw)
        return decodeBody<SettingsResponseDto>(raw.text, "保存设置")
    }

    // ------------------------------------------------------------------ 家庭成员

    /** `GET /family/members` —— 仅家长；items 是 snake_case。 */
    suspend fun familyMembers(): List<FamilyMemberDto> {
        val raw = api.getJson("/family/members", null, SHORT)
        api.requireOk(raw)
        return decodeBody<FamilyMemberListDto>(raw.text, "成员列表").items
    }

    /** `POST /family/members` → 201（返回体是 `{ok, member}`，这里解包出 member）。 */
    suspend fun createMember(body: FamilyCreateBodyDto): FamilyMemberDto {
        val json = EcJson.encodeToString(body)
        val raw = api.postJson("/family/members", json, auth = true, timeoutMs = WRITE_TIMEOUT)
        if (raw.status != 200 && raw.status != 201) {
            throw api.errorOf(raw)
        }
        val dto = decodeBody<FamilyMemberResponseDto>(raw.text, "创建成员")
        return dto.member
            ?: throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "创建成员返回格式异常")
    }

    /** `PATCH /family/members/:id` —— 可写昵称/水平/时长/自由聊/头像（传 role 会 400）。 */
    suspend fun updateMember(memberId: String, body: FamilyPatchBodyDto): FamilyMemberDto {
        val json = EcJson.encodeToString(body)
        val raw = api.patchJson("/family/members/${encodePath(memberId)}", json, WRITE_TIMEOUT)
        api.requireOk(raw)
        val dto = decodeBody<FamilyMemberResponseDto>(raw.text, "保存成员")
        return dto.member
            ?: throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "保存成员返回格式异常")
    }

    /** `POST /family/members/:id/password` —— 不需要旧密码，可重置自己。 */
    suspend fun resetMemberPassword(memberId: String, newPassword: String) {
        val body = EcJson.encodeToString(ResetPasswordBodyDto(newPassword = newPassword))
        val raw = api.postJson(
            "/family/members/${encodePath(memberId)}/password",
            body,
            auth = true,
            timeoutMs = WRITE_TIMEOUT,
        )
        api.requireOk(raw)
    }

    // ------------------------------------------------------------------ 家长面板

    /** `GET /parent/summary` —— 仅家长；儿童 403（提示「家长专用」，不跳登录）。 */
    suspend fun parentSummary(): ParentSummaryDto {
        val raw = api.getJson("/parent/summary", null, SHORT)
        api.requireOk(raw)
        return decodeBody<ParentSummaryDto>(raw.text, "家长面板")
    }

    // ------------------------------------------------------------------ 建议箱

    /** `POST /suggestions` —— 所有人（含儿童）都能提；服务端从会话取 user_id。 */
    suspend fun submitSuggestion(
        category: String,
        content: String,
        page: String? = null,
        context: SuggestionContextDto? = null,
    ): SuggestionCreateResultDto {
        val body = EcJson.encodeToString(
            SuggestionCreateBodyDto(
                category = category,
                content = content,
                page = page?.takeIf { it.isNotEmpty() },
                context = context,
            )
        )
        val raw = api.postJson("/suggestions", body, auth = true, timeoutMs = WRITE_TIMEOUT)
        api.requireOk(raw)
        return decodeBody<SuggestionCreateResultDto>(raw.text, "建议提交")
    }

    /** `GET /suggestions?[status=]&limit=&offset=` —— 仅家长。 */
    suspend fun listSuggestions(
        status: String = "",
        limit: Int = 50,
        offset: Int = 0,
    ): SuggestionListDto {
        val query = LinkedHashMap<String, String>()
        if (status.isNotEmpty()) query["status"] = status
        query["limit"] = limit.toString()
        query["offset"] = offset.toString()
        val raw = api.getJson("/suggestions", query, SHORT)
        api.requireOk(raw)
        return decodeBody<SuggestionListDto>(raw.text, "建议列表")
    }

    /** `PATCH /suggestions/:id {status}` —— open | read | resolved。 */
    suspend fun patchSuggestionStatus(suggestionId: String, status: String) {
        val body = EcJson.encodeToString(SuggestionPatchBodyDto(status = status))
        val raw = api.patchJson("/suggestions/${encodePath(suggestionId)}", body, WRITE_TIMEOUT)
        api.requireOk(raw)
    }

    /**
     * `GET /suggestions/export?format=md[&status=]` —— 响应体是 **Markdown 文本**（不是 JSON）。
     * 错误分支的 code 恒为 forbidden（看 HTTP 状态，不看 code）。
     */
    suspend fun exportSuggestionsMarkdown(status: String = ""): String {
        val query = LinkedHashMap<String, String>()
        query["format"] = "md"
        if (status.isNotEmpty()) query["status"] = status
        val raw = api.getJson("/suggestions/export", query, SHORT)
        api.requireOk(raw)
        return raw.text
    }

    // ------------------------------------------------------------------ 虚拟形象

    /** `GET /avatar/presets` —— 12 角色 × 5 风格；images 是站内绝对路径。 */
    suspend fun avatarPresets(): AvatarPresetsDto {
        val raw = api.getJson("/avatar/presets", null, SHORT)
        api.requireOk(raw)
        return decodeBody<AvatarPresetsDto>(raw.text, "预置形象库")
    }

    /** `GET /avatar` —— 未设置时字段为 null（styles 仍在）。 */
    suspend fun avatar(): AvatarStateDto {
        val raw = api.getJson("/avatar", null, SHORT)
        api.requireOk(raw)
        return decodeBody<AvatarStateDto>(raw.text, "形象信息")
    }

    /** `POST /avatar {preset_id, style}` —— 立即生效，不生成图片。 */
    suspend fun selectAvatar(presetId: String, style: String): AvatarStateDto {
        val body = EcJson.encodeToString(AvatarSelectBodyDto(presetId = presetId, style = style))
        val raw = api.postJson("/avatar", body, auth = true, timeoutMs = WRITE_TIMEOUT)
        api.requireOk(raw)
        return decodeBody<AvatarStateDto>(raw.text, "保存形象")
    }

    /** `PATCH /avatar {character_desc}` —— 只允许改角色卡。 */
    suspend fun updateAvatarDescription(desc: String): AvatarStateDto {
        val body = EcJson.encodeToString(AvatarDescBodyDto(characterDesc = desc))
        val raw = api.patchJson("/avatar", body, WRITE_TIMEOUT)
        api.requireOk(raw)
        return decodeBody<AvatarStateDto>(raw.text, "保存形象描述")
    }

    /** `DELETE /avatar` —— 清空字段（预置静态图不删）。 */
    suspend fun clearAvatar() {
        val raw = api.deleteJson("/avatar", WRITE_TIMEOUT)
        api.requireOk(raw)
    }

    // ------------------------------------------------------------------ 内部

    private fun encodePath(segment: String): String =
        java.net.URLEncoder.encode(segment, "UTF-8")

    companion object {
        private const val SHORT = 15_000L
        private const val WRITE_TIMEOUT = 30_000L
    }
}

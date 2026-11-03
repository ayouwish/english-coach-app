package top.dreamsearch.englishcoach.core.service

import kotlinx.serialization.encodeToString
import top.dreamsearch.englishcoach.core.net.ApiClient
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.ApiRequest
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.net.FormPart
import top.dreamsearch.englishcoach.core.net.decodeBody
import top.dreamsearch.englishcoach.core.net.dto.ChatAsrDto
import top.dreamsearch.englishcoach.core.net.dto.ChatAudioStatusDto
import top.dreamsearch.englishcoach.core.net.dto.ChatMessageDto
import top.dreamsearch.englishcoach.core.net.dto.ChatMessageListDto
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioBodyDto
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioDto
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioListDto
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioMutationDto
import top.dreamsearch.englishcoach.core.net.dto.ChatSessionCreateBodyDto
import top.dreamsearch.englishcoach.core.net.dto.ChatSessionDetailDto
import top.dreamsearch.englishcoach.core.net.dto.ChatSessionDto
import top.dreamsearch.englishcoach.core.net.dto.ChatSessionListDto
import top.dreamsearch.englishcoach.core.net.dto.ChatSessionSummaryDto
import top.dreamsearch.englishcoach.core.net.dto.ChatTurnBodyDto
import top.dreamsearch.englishcoach.core.net.dto.ChatTurnDto

/**
 * 对话训练 API（场景 / 会话 / 消息 / 一轮）。参考 `.specs/chat-story.md` §2。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/core/service/ChatService.ets`。
 *
 * 三步一轮（§2.5/§7.3）——**由 VM 编排**，本服务不写文件、不播音频：
 *   ① `asr()` → 文本
 *   ② `turn()` → 助手文本（服务端不返回 TTS 音频）
 *   ③ `PracticeService.tts()` → 字节 → VM 落盘交给 `AudioController`
 *
 * `pron` 分数**只能**从 `messages()` 轮询拿到，`turn()` 的响应不含分数。
 * `GET /:id/audio` 的 202（构建中）必须返回 null，不能抛错。
 */
class ChatService(private val api: ApiClient) {

    // ------------------------------------------------------------------ 场景

    /** `GET /api/chat/scenarios[?include_child=1]` */
    suspend fun scenarios(includeChild: Boolean = false): List<ChatScenarioDto> {
        val query = if (includeChild) mapOf("include_child" to "1") else null
        val raw = api.getJson("/chat/scenarios", query, LIST_TIMEOUT_MS)
        api.requireOk(raw)
        return decodeBody<ChatScenarioListDto>(raw.text, "场景列表").scenarios
    }

    /**
     * 创建自定义场景（§2.3）。`audience` 传空串表示交给服务端按账号定（儿童强制 child）。
     *
     * @return 新场景 id（响应缺 id 时抛 `bad_response`，不返回空壳）。
     */
    suspend fun createScenario(
        title: String,
        titleZh: String,
        settingZh: String,
        rolePrompt: String,
        openingLine: String,
        level: String,
        audience: String,
    ): String {
        val body = scenarioBody(title, titleZh, settingZh, rolePrompt, openingLine, level, audience)
        val raw = api.postJson("/chat/scenarios", body, auth = true, timeoutMs = MUTATE_TIMEOUT_MS)
        api.requireOk(raw)
        val dto = decodeBody<ChatScenarioMutationDto>(raw.text, "保存结果")
        if (dto.id.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "场景已提交，但没有拿到场景 ID")
        }
        return dto.id
    }

    /** 编辑自定义场景：rolePrompt 传空串表示「不修改」（未传字段服务端取原值）。 */
    suspend fun updateScenario(
        id: String,
        title: String,
        titleZh: String,
        settingZh: String,
        rolePrompt: String,
        openingLine: String,
        level: String,
    ) {
        // audience 传空串 = 不传（与 hos 的 updateScenario 一致）
        val body = scenarioBody(title, titleZh, settingZh, rolePrompt, openingLine, level, "")
        val raw = api.patchJson(
            "/chat/scenarios/${encodePath(id)}",
            body,
            MUTATE_TIMEOUT_MS,
        )
        api.requireOk(raw)
    }

    /** 删除自定义场景（仅 owner，他人 id 返回 404）。 */
    suspend fun deleteScenario(id: String) {
        val raw = api.deleteJson("/chat/scenarios/${encodePath(id)}", MUTATE_TIMEOUT_MS)
        api.requireOk(raw)
    }

    // ------------------------------------------------------------------ 会话

    /** `POST /api/chat/sessions {scenario_id}` */
    suspend fun createSession(scenarioId: String): ChatSessionDto {
        val body = EcJson.encodeToString(ChatSessionCreateBodyDto(scenarioId = scenarioId))
        val raw = api.postJson("/chat/sessions", body, auth = true, timeoutMs = MUTATE_TIMEOUT_MS)
        api.requireOk(raw)
        val dto = decodeBody<ChatSessionDto>(raw.text, "会话创建结果")
        if (dto.sessionId.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "会话创建结果格式异常")
        }
        return dto
    }

    /**
     * `POST /api/chat/sessions/:id/turn`（multipart：`text` 必填 + `audio` 可选）。
     *
     * @param audio 录音字节；null / 空数组表示纯文字输入（走 JSON 分支）。
     */
    suspend fun turn(sessionId: String, audio: ByteArray?, text: String): ChatTurnDto {
        val path = "/chat/sessions/${encodePath(sessionId)}/turn"
        val raw = if (audio != null && audio.isNotEmpty()) {
            val parts = mutableListOf(FormPart.text("text", text))
            parts.add(FormPart.file("audio", "recording.m4a", audio, "audio/mp4"))
            api.postMultipart(path, null, parts, TURN_TIMEOUT_MS)
        } else {
            val body = EcJson.encodeToString(ChatTurnBodyDto(text = text))
            api.postJson(path, body, auth = true, timeoutMs = TURN_TIMEOUT_MS)
        }
        api.requireOk(raw)
        return decodeBody<ChatTurnDto>(raw.text, "对话回复")
    }

    /** `GET /api/chat/sessions/:id/messages`（唯一的 pron 来源）。 */
    suspend fun messages(sessionId: String): List<ChatMessageDto> {
        val raw = api.getJson(
            "/chat/sessions/${encodePath(sessionId)}/messages",
            null,
            LIST_TIMEOUT_MS,
        )
        api.requireOk(raw)
        return decodeBody<ChatMessageListDto>(raw.text, "消息列表").messages
    }

    /** `POST /api/chat/sessions/:id/end`（幂等；空 body，所以用裸 request）。 */
    suspend fun end(sessionId: String) {
        val raw = api.request(
            ApiRequest(
                method = "POST",
                path = "/chat/sessions/${encodePath(sessionId)}/end",
                timeoutMs = MUTATE_TIMEOUT_MS,
            )
        )
        api.requireOk(raw)
    }

    /** `GET /api/chat/sessions/:id/audio/status`（只读，绝不触发构建）。 */
    suspend fun audioStatus(sessionId: String): ChatAudioStatusDto {
        val raw = api.getJson(
            "/chat/sessions/${encodePath(sessionId)}/audio/status",
            null,
            LIST_TIMEOUT_MS,
        )
        api.requireOk(raw)
        return decodeBody<ChatAudioStatusDto>(raw.text, "回放状态")
    }

    /**
     * `GET /api/chat/sessions/:id/audio[?force=1]`：
     * - 200 = 二进制 wav → 返回字节；
     * - **202 = 后台开始拼 → 返回 null（不是错误，页面继续轮询 status）**；
     * - 其他 → 抛 `ApiError`（500 时带可读 message）。
     */
    suspend fun audio(sessionId: String, force: Boolean = false): ByteArray? {
        val query = if (force) mapOf("force" to "1") else null
        val raw = api.getBytes(
            "/chat/sessions/${encodePath(sessionId)}/audio",
            query,
            AUDIO_TIMEOUT_MS,
        )
        if (raw.status == 202) return null
        api.requireOk(raw)
        val bytes = raw.bytes
        if (bytes == null || bytes.size < MIN_AUDIO_BYTES) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "整段回放内容为空")
        }
        return bytes
    }

    // ------------------------------------------------------------------ 历史

    /** `GET /api/chat/sessions?limit=N`（最近 N 条，倒序）。 */
    suspend fun sessions(limit: Int = 20): List<ChatSessionSummaryDto> {
        val safeLimit = limit.coerceAtLeast(1)
        val raw = api.getJson("/chat/sessions", mapOf("limit" to safeLimit.toString()), LIST_TIMEOUT_MS)
        api.requireOk(raw)
        return decodeBody<ChatSessionListDto>(raw.text, "历史列表").sessions.take(safeLimit)
    }

    /** `GET /api/chat/sessions/:id`（详情，**无 pron**；pron 走 [messages]）。 */
    suspend fun sessionDetail(sessionId: String): ChatSessionDetailDto {
        val raw = api.getJson("/chat/sessions/${encodePath(sessionId)}", null, LIST_TIMEOUT_MS)
        api.requireOk(raw)
        return decodeBody<ChatSessionDetailDto>(raw.text, "会话详情")
    }

    /**
     * 下载单条消息的录音（`audio_url` 形如 `/api/audio/cm_xxx`）→ 字节。
     * 这是 [PracticeService.audio] 之外的补充入口：VM 拿到字节后自行落盘播放。
     */
    suspend fun messageAudio(audioUrl: String): ByteArray {
        val path = stripApiPrefix(audioUrl)
        if (path.isEmpty()) {
            throw ApiError.local(ApiErrorCode.AUDIO_NOT_FOUND, "这条消息没有录音")
        }
        val raw = api.getBytes(path, null, AUDIO_DOWNLOAD_TIMEOUT_MS)
        api.requireOk(raw)
        val bytes = raw.bytes
        if (bytes == null || bytes.isEmpty()) {
            throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "录音内容为空")
        }
        return bytes
    }

    // ------------------------------------------------------------------ ASR

    /**
     * `POST /api/asr?language=xx[&provider=]`（multipart audio）。
     *
     * @param language 默认 `en`（英文自由说）；讲中文时传 `zh-CN`。
     * @return 识别文本（可能为空 = 没听清）。
     */
    suspend fun asr(audio: ByteArray, language: String = "en", provider: String? = null): String {
        if (audio.isEmpty()) {
            throw ApiError.local(ApiErrorCode.RECORD_FAILED, "录音文件为空，请重试")
        }
        val query = LinkedHashMap<String, String>()
        if (language.isNotEmpty()) query["language"] = language
        provider?.takeIf { it.isNotEmpty() }?.let { query["provider"] = it }
        val parts = listOf(FormPart.file("audio", "recording.m4a", audio, "audio/mp4"))
        val raw = api.postMultipart(
            "/asr",
            if (query.isEmpty()) null else query,
            parts,
            ASR_TIMEOUT_MS,
        )
        api.requireOk(raw)
        val dto = decodeBody<ChatAsrDto>(raw.text, "语音识别结果")
        return dto.text ?: dto.transcript ?: ""
    }

    // ------------------------------------------------------------------ 内部

    /** 创建/编辑场景的 JSON body：空字符串不出现在 body 里（PATCH = 未传取原值）。 */
    private fun scenarioBody(
        title: String,
        titleZh: String,
        settingZh: String,
        rolePrompt: String,
        openingLine: String,
        level: String,
        audience: String,
    ): String = EcJson.encodeToString(
        ChatScenarioBodyDto(
            title = title.ifEmpty { null },
            titleZh = titleZh.ifEmpty { null },
            settingZh = settingZh.ifEmpty { null },
            rolePrompt = rolePrompt.ifEmpty { null },
            openingLine = openingLine.ifEmpty { null },
            level = level.ifEmpty { null },
            audience = audience.ifEmpty { null },
        )
    )

    /** 站内绝对路径（可能带 `/api` 前缀）→ ApiClient 需要的「不含 /api」路径。 */
    private fun stripApiPrefix(url: String): String {
        if (url.isEmpty()) return ""
        if (url.startsWith("/api/")) return url.substring(4)
        if (url.startsWith("http://") || url.startsWith("https://")) {
            val index = url.indexOf("/api/")
            return if (index >= 0) url.substring(index + 4) else ""
        }
        return url
    }

    private fun encodePath(segment: String): String =
        java.net.URLEncoder.encode(segment, "UTF-8")

    companion object {
        private const val LIST_TIMEOUT_MS = 15_000L
        private const val MUTATE_TIMEOUT_MS = 20_000L
        private const val ASR_TIMEOUT_MS = 60_000L
        /** LLM 单轮最长约 40s，给 90s */
        private const val TURN_TIMEOUT_MS = 90_000L
        /** 整段回放可能几分钟（上限 900s），下载给 120s */
        private const val AUDIO_TIMEOUT_MS = 120_000L
        private const val AUDIO_DOWNLOAD_TIMEOUT_MS = 60_000L
        /** 小于该字节数视为「不是音频」（错误 JSON 体等） */
        private const val MIN_AUDIO_BYTES = 128
    }
}

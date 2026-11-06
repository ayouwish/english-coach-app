package top.dreamsearch.englishcoach.ui.page.chat

import kotlinx.coroutines.flow.MutableStateFlow
import top.dreamsearch.englishcoach.core.net.dto.ChatCorrectionDto
import top.dreamsearch.englishcoach.core.net.dto.ChatMessageDto
import top.dreamsearch.englishcoach.core.net.dto.ChatPronDto
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioDto
import top.dreamsearch.englishcoach.core.net.dto.ChatSessionDto
import top.dreamsearch.englishcoach.core.storage.AppPrefs
import java.io.File
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId

/**
 * 对话训练 · 页面共享模型与工具。
 *
 * 对应 hos：
 * - `viewmodel/ChatVM.ets` 的 `ChatMsg` / `ChatMsgFactory` / `ChatFormat`；
 * - `core/net/ChatDtos.ets` 的 `ChatNav`（会话页与场景页之间的内存交接）；
 * - `pages/ChatScenariosPage.ets` 的「自定义场景保存后刷新」用 AppStorage rev，
 *   Android 侧用 [ChatRefreshBus] 替代。
 *
 * 数据来源：`GET /api/chat/sessions/:id/messages`（pron / correction 只在这里）、
 * `POST /api/chat/scenarios`（列表项）。
 */

// ---------------------------------------------------------------------------
// 枚举
// ---------------------------------------------------------------------------

/** 一条气泡的播放状态（对应 hos `ChatMsg.playState`）。 */
enum class ChatPlayState { NONE, LOADING, PLAYING, FAILED }

/** 整段回放状态（对应 hos `ChatVM.replayStatus`）。 */
enum class ChatReplayStatus { IDLE, LOADING, BUILDING, READY, FAILED }

/** 错误条「重试」真正要重做的动作（对应 hos `ChatVM.lastAction`）。 */
enum class ChatRetryAction { NONE, RECORD, ASR, TURN, PLAY_TTS, REPLAY, END, RESTART }

// ---------------------------------------------------------------------------
// 气泡模型
// ---------------------------------------------------------------------------

/**
 * 一条消息气泡（页面只渲染这个，不直接碰 DTO）。
 *
 * 与 hos `ChatMsg` 的差异：Android 用不可变 data class + StateFlow 整体替换列表，
 * 不再需要 `rev`/`renderKey()`（Compose 用 `key = id` 做差量）。
 *
 * @property localAudio 刚录完、还没上传/还没下载时的本地文件（用户气泡回放用）
 * @property audioUrl 服务端录音地址（历史详情回放用，形如 `/api/audio/cm_xxx`）
 */
data class ChatMessageUi(
    val id: String,
    val role: String,
    val text: String,
    val textZh: String = "",
    val hasCorrection: Boolean = false,
    val better: String = "",
    val explainZh: String = "",
    val correctionType: String = "",
    val unsafeFiltered: Boolean = false,
    val hasPron: Boolean = false,
    val pronScore: Double? = null,
    val weakLabels: List<String> = emptyList(),
    val wordTexts: List<String> = emptyList(),
    val wordScores: List<Double?> = emptyList(),
    val localAudio: File? = null,
    val audioUrl: String = "",
    val playState: ChatPlayState = ChatPlayState.NONE,
) {
    val isUser: Boolean get() = role == "user"
}

/** DTO → 气泡。`isChild` 只影响 pron 的弱音/逐词（儿童永不显示 IPA 与数字）。 */
object ChatMsgFactory {

    fun fromDto(dto: ChatMessageDto, isChild: Boolean): ChatMessageUi {
        val base = ChatMessageUi(
            id = dto.id.ifEmpty { "m_${System.nanoTime()}" },
            role = dto.role.ifEmpty { "assistant" },
            text = dto.text,
            textZh = dto.textZh.orEmpty(),
            unsafeFiltered = dto.flag == "unsafe_filtered",
            audioUrl = dto.audioUrl.orEmpty(),
        )
        return applyCorrection(applyPron(base, dto.pron, isChild), dto.correction)
    }

    /** 更正（「更自然」）：`has_error != true` 视为没有更正。 */
    fun applyCorrection(msg: ChatMessageUi, correction: ChatCorrectionDto?): ChatMessageUi {
        if (correction == null || !correction.hasError) {
            return msg.copy(hasCorrection = false, better = "", explainZh = "", correctionType = "")
        }
        return msg.copy(
            hasCorrection = true,
            better = correction.better,
            explainZh = correction.explainZh,
            correctionType = correction.type,
        )
    }

    /** 发音分：儿童只记「有没有分」，不落数字、不落弱音与逐词（渲染层规则）。 */
    fun applyPron(msg: ChatMessageUi, pron: ChatPronDto?, isChild: Boolean): ChatMessageUi {
        if (pron == null) return msg.copy(hasPron = false)
        var next = msg.copy(hasPron = true, pronScore = pron.pron)
        if (!isChild) {
            val weak = pron.weakPhonemes.take(3)
                .map { item -> item.label.ifEmpty { item.ipa.orEmpty() } }
                .filter { it.isNotEmpty() }
            val words = pron.words.take(24)
            next = next.copy(
                weakLabels = weak,
                wordTexts = words.map { it.word },
                wordScores = words.map { it.score },
            )
        }
        return next
    }
}

// ---------------------------------------------------------------------------
// 展示格式化（成人/儿童共用，不含分数口径）
// ---------------------------------------------------------------------------

object ChatFormat {

    /** 分数文本：保留 1 位小数；null → 「—」。 */
    fun scoreText(value: Double?): String {
        if (value == null) return "—"
        val rounded = Math.round(value * 10.0) / 10.0
        return if (rounded % 1.0 == 0.0) rounded.toInt().toString() else rounded.toString()
    }

    /** 毫秒 → 「48 秒」/「2 分 10 秒」。 */
    fun durationText(ms: Long): String {
        if (ms <= 0L) return ""
        val totalSec = Math.round(ms / 1000.0).toLong()
        if (totalSec < 60) return "$totalSec 秒"
        return "${totalSec / 60} 分 ${totalSec % 60} 秒"
    }

    /** ISO 时间 → 「11-02 17:00」；解析失败原样返回（对应 hos `ChatFormat.timeText`）。 */
    fun timeText(iso: String): String {
        if (iso.isEmpty()) return ""
        try {
            val local = OffsetDateTime.parse(iso).atZoneSameInstant(ZoneId.systemDefault())
            return "${pad2(local.monthValue)}-${pad2(local.dayOfMonth)} ${pad2(local.hour)}:${pad2(local.minute)}"
        } catch (ignored: Throwable) {
            // 没有时区后缀的服务端时间戳走下面
        }
        try {
            val local = LocalDateTime.parse(iso)
            return "${pad2(local.monthValue)}-${pad2(local.dayOfMonth)} ${pad2(local.hour)}:${pad2(local.minute)}"
        } catch (ignored: Throwable) {
            return iso
        }
    }

    private fun pad2(value: Int): String = if (value < 10) "0$value" else value.toString()
}

// ---------------------------------------------------------------------------
// 跨页交接（替代 hos 的 ChatNav / AppStorage）
// ---------------------------------------------------------------------------

/** 场景页 → 会话页的一次性交接数据：开会话响应 + 被点的场景（响应缺 scenario 时兜底）。 */
data class ChatSessionHandoffData(
    val session: ChatSessionDto,
    val scenario: ChatScenarioDto?,
)

/**
 * 会话页启动数据（对应 hos `ChatNav.session`）。
 *
 * 契约里跨页参数只有 `NavParams.chatSessionId`（导航层写），但「开场白」来自
 * `POST /chat/sessions` 响应里的随机变体（`scenario.opening_line`），没有接口能重新取到，
 * 所以同进程内用它交接；取不到时（进程重建/热重载）会话页退化为只读重看（与 hos 一致）。
 */
object ChatSessionHandoff {

    @Volatile
    private var pending: ChatSessionHandoffData? = null

    fun put(session: ChatSessionDto, scenario: ChatScenarioDto?) {
        pending = ChatSessionHandoffData(session, scenario)
    }

    fun take(sessionId: String): ChatSessionHandoffData? {
        val current = pending ?: return null
        if (current.session.sessionId != sessionId) return null
        pending = null
        return current
    }
}

/**
 * 自定义场景页入口意图（对应 hos `ChatNav.editScenario`）。
 * 场景 Tab 点「＋ 自定义场景」= 直接开表单；点卡片的「编辑」= 带场景进入。
 */
object ChatCustomHandoff {

    @Volatile
    var editScenario: ChatScenarioDto? = null

    @Volatile
    var createOnOpen: Boolean = false

    fun consumeEdit(): ChatScenarioDto? {
        val current = editScenario
        editScenario = null
        return current
    }

    fun consumeCreate(): Boolean {
        val current = createOnOpen
        createOnOpen = false
        return current
    }
}

/**
 * 场景列表刷新信号（替代 hos 的 `AppStorage 'chat_scenarios_rev'`）：
 * 自定义场景新建/删除后 → Tab 页重新拉列表。
 */
object ChatRefreshBus {
    val revision = MutableStateFlow(0)

    fun bump() {
        revision.value = revision.value + 1
    }
}

// ---------------------------------------------------------------------------
// 语音偏好
// ---------------------------------------------------------------------------

/**
 * 对话页 TTS 偏好。
 *
 * 说明：共享层目前没有 `VoicePrefs` 类型（`core/` 不归本页维护），这里按任务要求
 * 直接从 `AppGraph.container.prefs` 读同一组 key（行为与 hos `ChatVM.loadPrefs` 一致）：
 * - 语速：`chat_tts_rate`（本页偏好）→ `tts_rate`（设置页全局）→ 默认（儿童 slow / 成人 normal）；
 * - 音色：`tts_voice`（空 = 服务端默认）；
 * - 自动朗读：`chat_auto_read`（默认开）。
 */
data class ChatVoicePrefs(
    val rate: String,
    val voice: String,
    val autoRead: Boolean,
) {
    companion object {
        const val KEY_TTS_VOICE = "tts_voice"
        const val KEY_TTS_RATE = "tts_rate"
        const val KEY_CHAT_TTS_RATE = "chat_tts_rate"
        const val KEY_CHAT_AUTO_READ = "chat_auto_read"
        const val KEY_CHAT_INCLUDE_CHILD = "chat_include_child"

        fun load(prefs: AppPrefs, isChild: Boolean): ChatVoicePrefs {
            val rate = prefs.getString(KEY_CHAT_TTS_RATE, "")
                .ifEmpty { prefs.getString(KEY_TTS_RATE, "") }
                .ifEmpty { if (isChild) "slow" else "normal" }
            // 儿童默认用内置童声（Voices.ALL 的 en-US-AnaNeural），成人留空 = 服务端默认音色
            val voice = prefs.getString(KEY_TTS_VOICE, "")
                .ifEmpty { if (isChild) DEFAULT_CHILD_VOICE else "" }
            val autoRead = prefs.getString(KEY_CHAT_AUTO_READ, "1") != "0"
            return ChatVoicePrefs(rate = rate, voice = voice, autoRead = autoRead)
        }

        /** 内置英语童声（`Voices.ALL` 的 en-US-AnaNeural）；儿童默认慢速 + 童声。 */
        const val DEFAULT_CHILD_VOICE = "en-US-AnaNeural"
    }
}

// ---------------------------------------------------------------------------
// 气泡文案（成人/儿童两套口径）
// ---------------------------------------------------------------------------

/** 用户气泡下方的发音行：成人给数字 + 最弱音，儿童只鼓励（对应 hos `pronLine`）。 */
fun pronLineFor(msg: ChatMessageUi, isChild: Boolean): String {
    if (!msg.hasPron && msg.role != "user") return ""
    if (isChild) {
        return if (msg.hasPron) "这次说得很清楚，继续说！🌟" else "这次的声音我听到啦"
    }
    if (!msg.hasPron) return "发音 —（本轮评分未完成）"
    val base = "发音 " + ChatFormat.scoreText(msg.pronScore)
    return if (msg.weakLabels.isEmpty()) base else base + " · 最弱 " + msg.weakLabels.joinToString("/")
}

/** 场景卡 emoji：接口没有 emoji 字段，按 id 关键词给一个稳定映射（照抄 hos `emojiFor`）。 */
fun emojiForScenario(item: ChatScenarioDto): String {
    if (item.isCustom) return "✨"
    val id = item.id
    return when {
        id.contains("coffee") -> "☕"
        id.contains("restaurant") || id.contains("food") || id.contains("cooking") -> "🍽️"
        id.contains("zoo") || id.contains("animal") -> "🦁"
        id.contains("school") -> "🏫"
        id.contains("birthday") -> "🎂"
        id.contains("clothes") || id.contains("supermarket") -> "🛍️"
        id.contains("weather") -> "🌤️"
        id.contains("doctor") -> "🩺"
        id.contains("hobbies") -> "🎨"
        id.contains("airport") || id.contains("travel") || id.contains("hotel") -> "✈️"
        id.contains("work") || id.contains("report") -> "💼"
        id.contains("weekend") || id.contains("chat") -> "🗣️"
        id.contains("directions") -> "🧭"
        id.contains("intro") || id.contains("friend") -> "👋"
        else -> "💬"
    }
}

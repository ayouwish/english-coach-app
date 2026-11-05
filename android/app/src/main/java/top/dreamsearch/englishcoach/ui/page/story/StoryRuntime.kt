package top.dreamsearch.englishcoach.ui.page.story

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.storage.CacheStore
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId

/**
 * 故事模式的「本机记录」+ 文本/日期工具（第二轮：由纯进程内改为落盘）。
 *
 * 对应 hos：`hos/entry/src/main/ets/viewmodel/StoryVM.ets` 里的 `StoryRuntime` / `StoryDates` /
 * `StoryRecordVM.splitSentences`。
 *
 * 线上限制与落盘方案：
 * - `POST /api/story/recordings` 线上 404，服务端不保存中文原声 → 客户端把**原声文件路径 +
 *   `source_zh`** 存进 `CacheStore` 的 JSON（`story_record_<materialId>`），并尽量把录音复制到
 *   `cache/audio/story_orig_<id>.m4a`；文件被清（换机/清缓存/系统回收）时打开详情仍能看到中文原文，
 *   只是隐藏回放（[OriginalRecording.playable]）。
 * - 服务端没有「复述历史」接口 → 只持久化**最近一次**复述（coverage/points/feedback），体积很小。
 * - Tab 根页（故事集）与新建/详情页不在同一条生命周期上 → 用 [refreshTick] 通知列表刷新。
 */
object StoryRuntime {

    /** 一次复述结果（对应 hos `StoryRetellRecord`；只存最近一次）。 */
    data class RetellRecord(
        /** 展示用时间 HH:mm */
        val createdAt: String,
        /** 覆盖率百分比；-1 = 服务端没给 */
        val coveragePercent: Int,
        val coveredPoints: List<String>,
        val missingPoints: List<String>,
        val feedbackZh: String,
        val feedbackEn: String,
        val transcript: String,
    )

    /** 本机保存的原声信息；[playable] = 录音文件当前还在，可回放。 */
    data class OriginalRecording(
        val path: String,
        val textZh: String,
        val playable: Boolean,
    )

    /** 一次读取出来的本机记录（原声 + 最近一次复述）。 */
    data class StorySnapshot(
        val sourceZh: String = "",
        val originalPath: String = "",
        val retell: RetellRecord? = null,
    )

    /** 落盘形状（内部契约，改字段必须兼容默认值）。 */
    @Serializable
    private data class PersistedRecord(
        val sourceZh: String = "",
        val originalPath: String = "",
        val retell: PersistedRetell? = null,
    )

    @Serializable
    private data class PersistedRetell(
        val createdAt: String = "",
        val coveragePercent: Int = -1,
        val coveredPoints: List<String> = emptyList(),
        val missingPoints: List<String> = emptyList(),
        val feedbackZh: String = "",
        val feedbackEn: String = "",
        val transcript: String = "",
    )

    private const val KEY_PREFIX = "story_record_"

    private val _refreshTick = MutableStateFlow(0)

    /** 故事集刷新信号：新建/改名/删除后 +1，故事集 VM 收到后重新拉列表。 */
    val refreshTick: StateFlow<Int> = _refreshTick.asStateFlow()

    private val _retellTick = MutableStateFlow(0)

    /** 复述结果刷新信号：复述完成后 +1，详情页 VM 收到后重新读本机记录。 */
    val retellTick: StateFlow<Int> = _retellTick.asStateFlow()

    /** 新建/改名/删除成功后通知故事集刷新。 */
    fun notifySaved() {
        _refreshTick.value = _refreshTick.value + 1
    }

    // ------------------------------------------------------------------ 读写

    /** 读本机记录；没有记录或 JSON 损坏都返回空快照（不抛错）。 */
    fun load(cache: CacheStore, materialId: String): StorySnapshot {
        if (materialId.isEmpty()) return StorySnapshot()
        val raw = cache.readJson(keyOf(materialId)) ?: return StorySnapshot()
        val dto = runCatching {
            EcJson.decodeFromString(PersistedRecord.serializer(), raw)
        }.getOrNull() ?: return StorySnapshot()
        return StorySnapshot(
            sourceZh = dto.sourceZh,
            originalPath = dto.originalPath,
            retell = dto.retell?.toUi(),
        )
    }

    /** 原声信息；文件不存在时 [OriginalRecording.playable] = false（页面隐藏回放但保留文字）。 */
    fun original(cache: CacheStore, materialId: String): OriginalRecording? {
        val snapshot = load(cache, materialId)
        if (snapshot.originalPath.isEmpty()) return null
        val exists = runCatching { File(snapshot.originalPath).let { it.exists() && it.length() > 0 } }
            .getOrDefault(false)
        return OriginalRecording(
            path = snapshot.originalPath,
            textZh = snapshot.sourceZh,
            playable = exists,
        )
    }

    /** 保存原声（路径应由调用方复制到稳定目录后再传进来）。 */
    fun saveOriginal(cache: CacheStore, materialId: String, sourceZh: String, originalPath: String) {
        if (materialId.isEmpty()) return
        val current = load(cache, materialId)
        write(
            cache,
            materialId,
            PersistedRecord(
                sourceZh = sourceZh,
                originalPath = originalPath,
                retell = current.retell?.toPersisted(),
            ),
        )
    }

    /** 追加/覆盖「最近一次复述」（服务端没有历史接口，只留最新一条，控制体积）。 */
    fun addRetell(cache: CacheStore, materialId: String, record: RetellRecord) {
        if (materialId.isEmpty()) return
        val current = load(cache, materialId)
        write(
            cache,
            materialId,
            PersistedRecord(
                sourceZh = current.sourceZh,
                originalPath = current.originalPath,
                retell = record.toPersisted(),
            ),
        )
        _retellTick.value = _retellTick.value + 1
    }

    /** 「清除本机记录」：清空 JSON + 尽量删除已复制的原声文件；服务端故事本身不受影响。 */
    fun clear(cache: CacheStore, materialId: String) {
        if (materialId.isEmpty()) return
        val snapshot = load(cache, materialId)
        // CacheStore 没有 removeJson：写一个可解析的空对象，load() 会得到空快照
        runCatching { cache.writeJson(keyOf(materialId), "{}") }
        if (snapshot.originalPath.isNotEmpty()) {
            runCatching { File(snapshot.originalPath).delete() }
        }
        _retellTick.value = _retellTick.value + 1
    }

    /** 一条 JSON 记录是否还在（页面按钮显隐用；不读文件系统）。 */
    fun hasRecords(cache: CacheStore, materialId: String): Boolean {
        val snapshot = load(cache, materialId)
        return snapshot.originalPath.isNotEmpty() || snapshot.retell != null
    }

    private fun write(cache: CacheStore, materialId: String, record: PersistedRecord) {
        runCatching {
            cache.writeJson(keyOf(materialId), EcJson.encodeToString(PersistedRecord.serializer(), record))
        }
    }

    private fun keyOf(materialId: String): String = KEY_PREFIX + materialId

    private fun PersistedRetell.toUi(): RetellRecord = RetellRecord(
        createdAt = createdAt,
        coveragePercent = coveragePercent,
        coveredPoints = coveredPoints,
        missingPoints = missingPoints,
        feedbackZh = feedbackZh,
        feedbackEn = feedbackEn,
        transcript = transcript,
    )

    private fun RetellRecord.toPersisted(): PersistedRetell = PersistedRetell(
        createdAt = createdAt,
        coveragePercent = coveragePercent,
        coveredPoints = coveredPoints,
        missingPoints = missingPoints,
        feedbackZh = feedbackZh,
        feedbackEn = feedbackEn,
        transcript = transcript,
    )
}

/**
 * 故事集分组 / 连续天数用的本地日期工具（对应 hos `StoryDates`）。
 *
 * 日期一律按**设备本地时区**算；ISO 解析失败返回 null，页面把该条归到「更早」。
 */
object StoryDates {

    /** ISO 时间 → `yyyy-MM-dd`（本地时区）；解析失败返回空串。 */
    fun keyFromIso(iso: String): String {
        if (iso.isBlank()) return ""
        val date = parseDate(iso) ?: return ""
        return keyOf(date)
    }

    fun keyOf(date: LocalDate): String =
        "%04d-%02d-%02d".format(date.year, date.monthValue, date.dayOfMonth)

    /** 「昨天」的 key（用于分组标签）。 */
    fun yesterdayKey(today: LocalDate = LocalDate.now()): String = keyOf(today.minusDays(1))

    /** 分组标签：今天 / 昨天 / 更早。 */
    fun labelOf(key: String, todayKey: String, yesterdayKey: String): String = when (key) {
        todayKey -> "今天"
        yesterdayKey -> "昨天"
        else -> "更早"
    }

    /**
     * 连续天数：从**今天**（今天没有故事则从昨天）往前数，连续有故事的天数。
     * 数据源是本地 AppPrefs 里「看过的故事日期集合」；没有今天/昨天则返回 0。
     */
    fun streakDays(keys: Set<String>, today: LocalDate = LocalDate.now()): Int {
        if (keys.isEmpty()) return 0
        val todayKey = keyOf(today)
        val yesterdayKey = keyOf(today.minusDays(1))
        val start = when {
            keys.contains(todayKey) -> today
            keys.contains(yesterdayKey) -> today.minusDays(1)
            else -> return 0
        }
        var cursor = start
        var count = 0
        while (keys.contains(keyOf(cursor))) {
            count++
            cursor = cursor.minusDays(1)
        }
        return count
    }

    /** 解析服务端时间（ISO offset / UTC `Z` / 纯日期三种都兼容）。 */
    fun parseDate(iso: String): LocalDate? {
        if (iso.isBlank()) return null
        return runCatching { OffsetDateTime.parse(iso).toLocalDate() }.getOrNull()
            ?: runCatching { Instant.parse(iso).atZone(ZoneId.systemDefault()).toLocalDate() }.getOrNull()
            ?: runCatching { LocalDate.parse(iso.take(10)) }.getOrNull()
    }
}

/** 故事相关的纯文本 / 等级 / 日期工具（不放 VM 里，详情、复述、新建三处共用）。 */
object StoryText {

    private val STORY_LEVELS = listOf("A1", "A2", "B1", "B2", "C1")

    /** 英文正文 → 句子数组（先按换行；只有一行时按 ". " 再拆，照抄 hos）。 */
    fun splitSentences(text: String): List<String> {
        val lines = text.split('\n').map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.size > 1) return lines
        val single = lines.firstOrNull() ?: text.trim()
        if (single.isEmpty()) return emptyList()
        val pieces = single.split(". ")
        if (pieces.size <= 1) return lines
        val out = ArrayList<String>(pieces.size)
        pieces.forEachIndexed { index, raw ->
            var piece = raw.trim()
            if (piece.isEmpty()) return@forEachIndexed
            if (index < pieces.size - 1 && !piece.endsWith(".")) piece += "."
            out.add(piece)
        }
        return out
    }

    /** 账号 cefrLevel → 故事改写等级（A1–C1；无法识别时回落到 A2，与 hos `normalizeLevel` 一致）。 */
    fun storyLevelForCefr(cefr: String): String {
        val upper = cefr.trim().uppercase()
        return if (upper in STORY_LEVELS) upper else "A2"
    }

    /** 复述等级（A1–C1；服务端对非法值静默回落 A2）。 */
    fun normalizeRetellLevel(level: String): String {
        val upper = level.trim().uppercase()
        return if (upper in STORY_LEVELS) upper else "A2"
    }

    /** 服务端 ISO 时间 → 「9月28日」（解析失败返回空串，页面自行隐藏）。 */
    fun dateTextOf(iso: String): String {
        val date = StoryDates.parseDate(iso) ?: return ""
        return "${date.monthValue}月${date.dayOfMonth}日"
    }

    /** 复述记录的时间戳（HH:mm）。 */
    fun clockTextNow(): String {
        val now = java.time.LocalTime.now()
        return String.format(java.util.Locale.US, "%02d:%02d", now.hour, now.minute)
    }

    /** 1.0–100 的百分比取整；null → -1（页面显示「—」）。 */
    fun coveragePercentOf(coverage: Double?): Int {
        if (coverage == null) return -1
        return Math.round(coverage * 100).toInt()
    }
}

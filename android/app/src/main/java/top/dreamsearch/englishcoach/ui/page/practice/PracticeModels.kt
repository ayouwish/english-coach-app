package top.dreamsearch.englishcoach.ui.page.practice

import kotlinx.serialization.encodeToString
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.net.dto.AttemptItemDto
import top.dreamsearch.englishcoach.core.net.dto.AttemptResponseDto
import top.dreamsearch.englishcoach.core.net.dto.FeedbackDto
import top.dreamsearch.englishcoach.core.net.dto.IntonationDto
import top.dreamsearch.englishcoach.core.net.dto.PronounceResultDto
import top.dreamsearch.englishcoach.core.net.dto.ScoresDto
import top.dreamsearch.englishcoach.core.net.dto.SentenceDto
import top.dreamsearch.englishcoach.core.net.dto.SentenceListDto
import top.dreamsearch.englishcoach.core.net.dto.WordScoreDto
import top.dreamsearch.englishcoach.core.storage.CacheStore
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 跟读页的 **UI 侧模型 / 纯函数辅助**（不碰 Android UI、不碰网络）。
 *
 * 事实来源：hos `viewmodel/PracticeVM.ets`、`pages/PracticePage.ets`、
 * `pages/SentenceListPage.ets`。数据来源约定见 `android/CONTRACT.md` §3.2 / §6：
 * - 语料：`PracticeService.sentences(level, focus)`；
 * - 单句历史：线上没有 `/sentences/:id/attempts`，用 `PracticeService.attempts(limit)` 按
 *   `sentence_id` 过滤（见 [buildHistoryUi]）；
 * - 练习游标：线上没有 `/practice/cursor`，用 `AppPrefs` 记「每等级上次读到哪句」。
 *
 * 设计：页面只依赖这里的 `Ui` 模型，不直接渲染 DTO（DTO 字段可能为 null/空串）。
 */

/** 语料等级（服务端没有 C1，账号 C1 → B2，见 AppConfig.levelForCefr）。 */
object PracticeLevels {
    val ALL: List<String> = listOf("A1", "A2", "B1", "B2")
}

/** 本地练习游标 key：每个等级记「上次读到哪句」的 sentence id。 */
fun practiceCursorKey(level: String): String = "practice_cursor_$level"

/** 语料列表 JSON 缓存 key（先显示后刷新用）。 */
fun sentencesCacheKey(level: String, focus: String): String =
    if (focus.isEmpty()) "sentences_$level" else "sentences_${level}_$focus"

// ---------------------------------------------------------------------------
// 句子（UI 侧）
// ---------------------------------------------------------------------------

/** 当前一句的可渲染视图模型（儿童不暴露 focus/tags）。 */
data class PracticeSentenceUi(
    val id: String = "",
    val index: Int = 0,
    val total: Int = 0,
    val text: String = "",
    val translation: String = "",
    val level: String = "",
    val focusPhonemes: List<String> = emptyList(),
    val tags: List<String> = emptyList(),
) {
    val hasPrev: Boolean get() = index > 0
    val hasNext: Boolean get() = index < total - 1
}

fun SentenceDto.toPracticeUi(index: Int, total: Int, isChild: Boolean): PracticeSentenceUi =
    PracticeSentenceUi(
        id = id,
        index = index,
        total = total,
        text = text,
        translation = translationZh,
        level = level,
        // 服务端已对儿童剥离，这里再兜一层保险（screens.md §0）
        focusPhonemes = if (isChild) emptyList() else focusPhonemes,
        tags = if (isChild) emptyList() else tags,
    )

// ---------------------------------------------------------------------------
// 语料 JSON 缓存（CacheStore.readJson / writeJson；先显示后刷新）
// ---------------------------------------------------------------------------

/** 读语料缓存；无缓存/解析失败返回空列表（不抛）。 */
fun readSentencesCache(cache: CacheStore, level: String, focus: String): List<SentenceDto> =
    runCatching {
        val raw = cache.readJson(sentencesCacheKey(level, focus)) ?: return@runCatching emptyList()
        EcJson.decodeFromString(SentenceListDto.serializer(), raw).sentences
    }.getOrDefault(emptyList())

/** 写语料缓存（失败静默：缓存只是加速，不是主流程）。 */
fun writeSentencesCache(
    cache: CacheStore,
    level: String,
    focus: String,
    sentences: List<SentenceDto>,
) {
    runCatching {
        val dto = SentenceListDto(level = level, count = sentences.size, sentences = sentences)
        cache.writeJson(sentencesCacheKey(level, focus), EcJson.encodeToString(dto))
    }
}

// ---------------------------------------------------------------------------
// 评测结果（UI 侧）
// ---------------------------------------------------------------------------

/** 逐词得分（成人；儿童不渲染）。 */
data class WordScoreUi(
    val word: String = "",
    val score: Double? = null,
    val errorType: String = "",
)

/**
 * 「需要纠正的地方」卡片。
 *
 * 成人：来自 `IssueDto` + 本地音素提示（最多 2 条，见 [buildCorrectionCards]）；
 * 儿童：只用 1 条温和版（标题 + 怎么做），不出现 IPA。
 */
data class CorrectionCardUi(
    val title: String = "",
    val word: String = "",
    val expected: String = "",
    val actual: String = "",
    val score: Double? = null,
    val why: String = "",
    val how: String = "",
    /** 推荐练习词（沉到 `practice_words`，用「·」拼好；空串不显示） */
    val practiceWords: String = "",
)

/** 语调曲线（成人；已把 F0 点转成图表可直接吃的 `List<Float?>`）。 */
data class IntonationUi(
    val userF0: List<Float?> = emptyList(),
    val refF0: List<Float?> = emptyList(),
    /** DTW 距离，保留 2 位小数；空串 = 服务端未给 */
    val distanceText: String = "",
    /** 最差区间的人话（最多 2 条） */
    val regionTexts: List<String> = emptyList(),
    /** 图表 Y 轴（按真实 Hz 范围留 15% 余量，不伪造 0–100） */
    val minY: Float = 0f,
    val maxY: Float = 100f,
)

/** 单句历史 / 进步曲线（成人显示趋势；儿童只保留逐条回放，不显示分数）。 */
data class HistoryUi(
    val scores: List<Float> = emptyList(),
    val labels: List<String> = emptyList(),
    val attemptIds: List<String> = emptyList(),
    val first: Float? = null,
    val last: Float? = null,
    /** 逐条记录（旧→新，UI 倒序展示）：id / 时间 / 分数 / 录音 URL，用于「▶ 回放」 */
    val items: List<HistoryItemUi> = emptyList(),
) {
    /** 首末分差（正数=进步）；无记录为 null。 */
    val delta: Float? get() = if (first != null && last != null) last - first else null
}

/** 单句历史里的一条：儿童 `score = null`（隐藏分数、只保留回放），成人带分数。 */
data class HistoryItemUi(
    val attemptId: String = "",
    val score: Double? = null,
    /** 展示用时间（`M/d HH:mm`） */
    val label: String = "",
    /** `AttemptItemDto.audioUrl`（形如 `/api/audio/xxx`）；空 = 无录音，不显示回放按钮 */
    val audioUrl: String = "",
)

/**
 * 能力雷达（成人结果区 / 全屏结果页）：
 * labels 固定「准确 / 流利 / 完整 / 语调 / 总分」，values 为 `ScoresDto` 的
 * accuracy / fluency / completeness / prosody / pron（缺失为 null，不伪造 0 分）。
 */
data class RadarUi(
    val labels: List<String> = emptyList(),
    val values: List<Double?> = emptyList(),
)

/** 一次评测的可渲染结果（页面不再碰 DTO）。 */
data class PracticeResultUi(
    val attemptId: String = "",
    val pron: Double? = null,
    val accuracy: Double? = null,
    val fluency: Double? = null,
    val completeness: Double? = null,
    val prosody: Double? = null,
    val recognizedText: String = "",
    /** 空识别：显示「没听到你的声音」，且**不显示 0 分**（screens.md §3 状态表） */
    val noSpeech: Boolean = false,
    val lowSnr: Boolean = false,
    val durationText: String = "",
    val feedbackSummary: String = "",
    val feedbackPraise: String = "",
    val feedbackClosing: String = "",
    /** 纠错/建议卡片：成人最多 2 条、儿童 1 条温和版 */
    val cards: List<CorrectionCardUi> = emptyList(),
    /** 逐词（句子顺序，最多 12 个；儿童为空） */
    val words: List<WordScoreUi> = emptyList(),
    /** 需要练的词（分数升序，最多 9 个；儿童为空） */
    val worstWords: List<WordScoreUi> = emptyList(),
    /** 语调曲线（儿童为空） */
    val intonation: IntonationUi? = null,
    /** 能力雷达（成人；儿童为空 → 只显示星级/鼓励） */
    val radar: RadarUi? = null,
    /** 结果元信息（provider / 粒度 / 时长 / attempt id），成人详情底部一行 */
    val metaText: String = "",
)

/** 结果页子项分数条（key 与 `EcScore.subScoreLabel` 对齐）。 */
fun subScoreItems(result: PracticeResultUi): List<Pair<String, Double?>> = listOf(
    "accuracy" to result.accuracy,
    "fluency" to result.fluency,
    "completeness" to result.completeness,
    "prosody" to result.prosody,
)

/**
 * 把 `AttemptResponseDto` 转成页面模型；`result == null`（degraded / 无结果）返回 null。
 *
 * 规则与 hos `PracticeVM.applyAttempt` 一致：
 * - 总分取 `scores.pron`，缺失为 null（**不是 0**）；
 * - `recognized_text` 去空白后长度 < 2 → 空识别；
 * - 逐词/音素/语调只给成人（儿童走简化版，不显示 IPA/低分曲线）。
 */
fun buildResultUi(resp: AttemptResponseDto, isChild: Boolean): PracticeResultUi? {
    val result: PronounceResultDto = resp.result ?: return null
    val feedback: FeedbackDto? = resp.feedback
    val scores = result.scores
    val recognized = result.recognizedText
    val durationMs = result.durationMs
    val words = if (isChild) emptyList<WordScoreUi>() else buildWordScores(result.words)
    val worst = if (isChild) emptyList<WordScoreUi>() else words.sortedWith(
        compareBy<WordScoreUi> { it.score ?: 101.0 }.thenBy { it.word }
    ).take(9)
    val metaParts = mutableListOf<String>()
    result.provider.takeIf { it.isNotEmpty() }?.let { metaParts += "provider: $it" }
    result.granularity.takeIf { it.isNotEmpty() }?.let { metaParts += "粒度: $it" }
    if (durationMs > 0) metaParts += "时长: ${formatDuration(durationMs)}"
    resp.attemptId.takeIf { it.isNotEmpty() }?.let { metaParts += "记录: $it" }
    return PracticeResultUi(
        attemptId = resp.attemptId,
        pron = scores?.pron,
        accuracy = scores?.accuracy,
        fluency = scores?.fluency,
        completeness = scores?.completeness,
        prosody = scores?.prosody,
        recognizedText = recognized,
        noSpeech = recognized.trim().length < 2,
        lowSnr = result.warnings.contains("low_snr"),
        durationText = if (durationMs > 0) formatDuration(durationMs) else "",
        feedbackSummary = feedback?.summary.orEmpty(),
        feedbackPraise = feedback?.praise.orEmpty(),
        feedbackClosing = feedback?.closing.orEmpty(),
        cards = buildCorrectionCards(result, feedback, isChild),
        words = words,
        worstWords = worst,
        intonation = if (isChild) null else buildIntonationUi(result.intonation),
        // 儿童只显示星级/鼓励，不显示能力雷达（screens.md §0「图表简化」）
        radar = buildRadarUi(scores, isChild),
        metaText = metaParts.joinToString(" · "),
    )
}

/**
 * 能力雷达（成人）：准确 / 流利 / 完整 / 语调 / 总分。
 * values 直接取 `ScoresDto` 的五项，缺失为 null（雷达组件按空值处理，不伪造 0）。
 */
private fun buildRadarUi(scores: ScoresDto?, isChild: Boolean): RadarUi? {
    if (isChild) return null
    return RadarUi(
        labels = listOf("准确", "流利", "完整", "语调", "总分"),
        values = listOf(
            scores?.accuracy,
            scores?.fluency,
            scores?.completeness,
            scores?.prosody,
            scores?.pron,
        ),
    )
}

/** 逐词（句子顺序，最多 12 个；null 分保留为 null = 显示「—」）。 */
private fun buildWordScores(words: List<WordScoreDto>): List<WordScoreUi> =
    words.take(12).map { WordScoreUi(word = it.word, score = it.score, errorType = it.errorType.orEmpty()) }

/**
 * 纠错/建议卡片：
 * - 成人：优先用 `issues`（音素提示本地化）最多 2 条；没有 issues 时回落到 `feedback.points`；
 * - 儿童：不出现音素符号，取 `feedback.points` 第 1 条（标题 + 怎么做）；都没有则空（页面给鼓励语）。
 */
private fun buildCorrectionCards(
    result: PronounceResultDto,
    feedback: FeedbackDto?,
    isChild: Boolean,
): List<CorrectionCardUi> {
    val cards = mutableListOf<CorrectionCardUi>()
    if (!isChild) {
        for (issue in result.issues) {
            if (cards.size >= MAX_CORRECTION_CARDS) break
            val lookup = issue.expected?.takeIf { it.isNotEmpty() } ?: issue.phoneme.orEmpty()
            val hint = PhonemeHints.byPhoneme(lookup)
            cards += CorrectionCardUi(
                title = PhonemeHints.title(hint, false),
                word = issue.word,
                expected = issue.expected.orEmpty(),
                actual = issue.actual.orEmpty(),
                score = issue.score,
                why = PhonemeHints.why(hint, false),
                how = PhonemeHints.how(hint, false),
                practiceWords = hint.words.joinToString(" · "),
            )
        }
    }
    if (cards.isEmpty()) {
        val points = feedback?.points.orEmpty()
        val limit = if (isChild) 1 else MAX_CORRECTION_CARDS
        points.take(limit).forEach { point ->
            cards += CorrectionCardUi(
                title = point.title.ifEmpty { if (isChild) "再读一次会更好" else "可以再练一下" },
                why = if (isChild) "" else point.why,
                how = point.how,
                practiceWords = point.practiceWords.joinToString(" · "),
            )
        }
    }
    return cards.take(if (isChild) 1 else MAX_CORRECTION_CARDS)
}

private const val MAX_CORRECTION_CARDS = 2

/** `IntonationDto` → 图表模型；不可用 / 无有效 F0 返回 null（不画空图）。 */
fun buildIntonationUi(dto: IntonationDto?): IntonationUi? {
    if (dto == null || !dto.available) return null
    // F0Point = [time_ms, f0_hz|null]；图表只要纵坐标，null 保留为断点
    val user = dto.userF0.map { it.getOrNull(1)?.toFloat() }
    val ref = dto.referenceF0.map { it.getOrNull(1)?.toFloat() }
    val values = (user + ref).filterNotNull()
    if (values.isEmpty()) return null
    val rawMin = values.min()
    val rawMax = values.max()
    val padding = max(10f, abs(rawMax - rawMin) * 0.15f)
    val regionTexts = dto.worstRegions.take(2).map { region ->
        val label = regionLabel(region.issue)
        val text = region.text
        if (text.isEmpty()) label else "$label（$text）"
    }
    return IntonationUi(
        userF0 = user,
        refF0 = ref,
        distanceText = dto.dtwDistance?.let { formatTwoDecimals(it) }.orEmpty(),
        regionTexts = regionTexts,
        minY = rawMin - padding,
        maxY = rawMax + padding,
    )
}

/** 语调最差区间 → 人话（照抄 hos PracticeVM.regionLabel）。 */
private fun regionLabel(issue: String): String = when (issue) {
    "expected_rise_but_flat" -> "这里该升调却没升"
    "expected_fall_but_flat" -> "这里该降调却没降"
    "wrong_direction" -> "升降方向反了"
    "stress_misplaced" -> "重音位置偏了"
    "monotone_overall" -> "整体偏平"
    "unexpected_pause" -> "不该停的地方停了"
    else -> "语调可以更自然"
}

/**
 * 单句历史：`GET /attempts?limit=100` 按 `sentence_id` 过滤，取最近 10 次。
 *
 * - 成人：分数序列（旧→新）给趋势图 + 逐条记录（含 audioUrl 可回放；降级无分的条目只有回放）；
 * - 儿童：**不显示分数/趋势**，但保留逐条记录用于回放（score 置 null）。
 * 没有记录返回 null。
 */
fun buildHistoryUi(items: List<AttemptItemDto>, sentenceId: String, isChild: Boolean): HistoryUi? {
    if (sentenceId.isEmpty()) return null
    val recent = items
        .asSequence()
        .filter { it.sentenceId == sentenceId && !it.pending && !it.blind }
        .take(10)
        .toList()
    if (recent.isEmpty()) return null
    val ordered = recent.reversed() // 服务端倒序 → 旧→新
    val itemsUi = ordered.map { item ->
        HistoryItemUi(
            attemptId = item.id,
            score = if (isChild) null else item.scores?.pron,
            label = formatHistoryTime(item.createdAt),
            audioUrl = item.audioUrl.orEmpty(),
        )
    }
    // 趋势只用有 pron 分的条目（降级/无分条目只保留回放）
    val scored = if (isChild) {
        emptyList()
    } else {
        ordered.mapNotNull { item -> item.scores?.pron?.let { pron -> item to pron } }
    }
    val scores = scored.map { it.second.toFloat() }
    return HistoryUi(
        scores = scores,
        labels = scored.map { formatHistoryTime(it.first.createdAt) },
        attemptIds = ordered.map { it.id },
        first = scores.firstOrNull(),
        last = scores.lastOrNull(),
        items = itemsUi,
    )
}

/** ISO 时间 → `M/d HH:mm`（历史横轴，与 hos formatHistoryTime 规则一致；解析不了就原样返回）。 */
fun formatHistoryTime(iso: String): String {
    if (iso.length < 16) return iso
    return runCatching {
        val month = iso.substring(5, 7).trimStart('0').ifEmpty { "0" }
        val day = iso.substring(8, 10).trimStart('0').ifEmpty { "0" }
        val hour = iso.substring(11, 13)
        val minute = iso.substring(14, 16)
        "$month/$day $hour:$minute"
    }.getOrDefault(iso)
}

/** 毫秒 → `3.2s`（结果详情用）。 */
fun formatDuration(durationMs: Int): String = (durationMs / 100.0).roundToInt().let { tenths ->
    val whole = tenths / 10
    val frac = tenths % 10
    if (frac == 0) "${whole}s" else "$whole.${frac}s"
}

private fun formatTwoDecimals(value: Double): String {
    val rounded = (value * 100).roundToInt()
    return (rounded / 100.0).toString()
}

/** 分数取整显示（null → 「—」，不伪装 0 分）。 */
fun scoreText(score: Double?): String = if (score == null) "—" else score.roundToInt().toString()

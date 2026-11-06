package top.dreamsearch.englishcoach.ui.page.flow

/**
 * 连读模式（/flow）页面共享模型：阶段 / 单句状态机 / 句子批次 / 汇总快照 / 鼓励语文案 / 文本切句 /
 * 进程内运行态共享（FlowRunStore）。
 *
 * 对应 hos：`hos/entry/src/main/ets/viewmodel/FlowVM.ets` 里的
 * FlowPhase / FlowStatus / FlowItem / FlowRunSentence / FlowWorstItem / FlowSummaryData /
 * FlowText / FlowEncouragement 与 FlowRunStore。
 * 业务来源：`.specs/practice-flow.md` §5、`hos/docs/screens.md` §4（连读模式）与 §0（儿童/成人）。
 *
 * Android 侧差异：hos 用 @Observed 类 + notifyItems() 手动替换数组触发刷新；
 * 这里改用不可变 data class，所有更新由 FlowViewModel 走 `MutableStateFlow.update { copy(...) }`。
 */

/** 连读阶段：setup → running →（全部 settled）summary；summary 里「再读一遍」回 running、「再读一段」回 setup。 */
enum class FlowPhase { SETUP, RUNNING, SUMMARY }

/**
 * 单句状态机（PENDING/SCORING/DONE/FAILED 与服务端 `/attempts/status` 字符串对应；
 * [PENDING_OFFLINE] 是第二轮新增的本地态：提交时网络/5xx 失败，录音已入待补评分队列，
 * 不算失败、也不再轮询，汇总页可去「待补评分」页补提交）。
 */
enum class FlowStatus {
    UNSENT,
    PENDING,
    SCORING,
    DONE,
    FAILED,

    /** 提交失败但录音已入本机待补评分队列（`PendingUploadQueue`，mode="flow"）。 */
    PENDING_OFFLINE,
    ;

    companion object {
        /** 服务端字符串 → 本地状态；未知值返回 null（调用方忽略，保持原状态）。 */
        fun fromWire(value: String): FlowStatus? = when (value) {
            "unsent" -> UNSENT
            "pending" -> PENDING
            "scoring" -> SCORING
            "done" -> DONE
            "failed" -> FAILED
            else -> null
        }
    }
}

/** 逐词分数（连读详情：只有 word/score，没有音素明细）。 */
data class FlowWordScore(
    val word: String = "",
    val score: Double? = null,
)

/**
 * 连读中一句话的本地模型（服务端 attempt 的可视化镜像）。
 *
 * @property translationZh 语料句的中文翻译（自定义/故事文本没有，空串不展示）
 * @property scorePron 综合分 0–100；`null` 表示本次没拿到分数（不是 0）
 * @property noSpeech 识别文本里几乎没有英文字母（服务端没听到声音）
 */
data class FlowItem(
    val index: Int = 0,
    val text: String = "",
    val sentenceId: String = "",
    /** corpus | custom —— 直接作为 /attempts/async 的 source 字段 */
    val source: String = "custom",
    val materialId: String = "",
    val translationZh: String = "",
    val attemptId: String = "",
    val status: FlowStatus = FlowStatus.UNSENT,
    val error: String = "",
    val hasResult: Boolean = false,
    val scorePron: Double? = null,
    val scoreAccuracy: Double? = null,
    val scoreFluency: Double? = null,
    val scoreCompleteness: Double? = null,
    val scoreProsody: Double? = null,
    val recognizedText: String = "",
    val noSpeech: Boolean = false,
    val feedbackSummary: String = "",
    val feedbackPraise: String = "",
    val feedbackClosing: String = "",
    val pointTitles: List<String> = emptyList(),
    val pointHows: List<String> = emptyList(),
    val words: List<FlowWordScore> = emptyList(),
    val issueTexts: List<String> = emptyList(),
) {
    /** 「重录这句」：清掉上一轮 attempt 的全部展示数据，回到未读。 */
    fun resetForRedo(): FlowItem = FlowItem(
        index = index,
        text = text,
        sentenceId = sentenceId,
        source = source,
        materialId = materialId,
        translationZh = translationZh,
    )
}

/** 一批句子（「再读一遍」复用，不重新抽句/切句）。 */
data class FlowRunSentence(
    val text: String = "",
    val sentenceId: String = "",
    val source: String = "custom",
    val materialId: String = "",
    val translationZh: String = "",
)

/** 汇总页「最需要再练的几句」一行。 */
data class FlowWorstItem(
    val score: Double? = null,
    val text: String = "",
    val index: Int = 0,
)

/** 本地鼓励语文案（中英双语、6 档、按本批 attempt id 确定性挑选）。 */
data class FlowEncouragement(
    val tier: String = "",
    val zh: String = "",
    val en: String = "",
    /** 具体化补充（挑本次读得最好的词；可能为空） */
    val praise: String = "",
)

/** 汇总页渲染快照（一次构建，页面不反复计算）。 */
data class FlowSummaryData(
    val round: Int = 1,
    val total: Int = 0,
    /** 已评分句数（status=done 且拿到 pron） */
    val doneCount: Int = 0,
    val failedCount: Int = 0,
    /** null = 没有可算的平均分 */
    val avgScore: Double? = null,
    val worst: List<FlowWorstItem> = emptyList(),
    val encouragement: FlowEncouragement = FlowEncouragement(),
    /** 参与 `GET /diagnosis?scope=batch` 的 attempt id（≤20） */
    val attemptIds: List<String> = emptyList(),
    val items: List<FlowItem> = emptyList(),
    /** 本轮句子来自的故事材料 id（空 = 非故事来源；用于汇总页「复述这个故事」入口） */
    val materialId: String = "",
    /** 本轮是否由「故事 → 去连读」（`NavParams.flowMaterialId`）启动 */
    val fromStoryMaterial: Boolean = false,
    /**
     * 本轮已入待补评分队列的句数（status=PENDING_OFFLINE）。
     * 汇总页另有「队列总数」（`PendingUploadQueue.count()`，含以前批次）用于去处理入口。
     */
    val offlineCount: Int = 0,
)

/** 汇总页诊断标签色调（页面再映射成 UI Kit 的 PillTone，避免模型层依赖组件层）。 */
enum class DiagTone { NEUTRAL, GOOD, WARN, BAD }

/** 汇总页「这一批的问题」一行标签。 */
data class DiagChip(
    val label: String = "",
    val tone: DiagTone = DiagTone.NEUTRAL,
)

// ---------------------------------------------------------------------------
// 统计扩展：运行页与汇总页共用（避免两处各写一遍计数）
// ---------------------------------------------------------------------------

/** 已提交（状态不再是 unsent）句数。 */
fun List<FlowItem>.submittedCount(): Int = count { it.status != FlowStatus.UNSENT }

/** 排队/评分中的句数。 */
fun List<FlowItem>.pendingCount(): Int =
    count { it.status == FlowStatus.PENDING || it.status == FlowStatus.SCORING }

/** 已评分（done）句数。 */
fun List<FlowItem>.doneCount(): Int = count { it.status == FlowStatus.DONE }

/** 评分失败句数。 */
fun List<FlowItem>.failedCount(): Int = count { it.status == FlowStatus.FAILED }

/** 已入待补评分队列的句数（status=pending-offline，不算失败）。 */
fun List<FlowItem>.offlineQueuedCount(): Int = count { it.status == FlowStatus.PENDING_OFFLINE }

/** 进度百分比 0–100（按已提交句数算，与 hos 一致）。 */
fun List<FlowItem>.progressPercent(): Int {
    if (isEmpty()) return 0
    return (submittedCount() * 100 + size / 2) / size
}

// ---------------------------------------------------------------------------
// 纯文本工具（照抄 hos FlowText，规格 §5.2）
// ---------------------------------------------------------------------------

object FlowText {

    /** 按 `. ! ? 。！？` 切句（保留句末标点，丢弃没有英文字母的碎片）。 */
    fun splitSentences(input: String): List<String> {
        val raw = ArrayList<String>()
        val current = StringBuilder()
        for (ch in input) {
            current.append(ch)
            if (ch == '.' || ch == '!' || ch == '?' || ch == '。' || ch == '！' || ch == '？') {
                val trimmed = current.toString().trim()
                if (trimmed.isNotEmpty()) raw.add(trimmed)
                current.setLength(0)
            }
        }
        val tail = current.toString().trim()
        if (tail.isNotEmpty()) raw.add(tail)
        return raw.filter { letterCount(it) > 0 }
    }

    /**
     * 材料/故事正文切句：多行文本按行优先（故事材料就是「一行一句」），
     * 单行时退回句末标点切句；任一行里有多句也会再切一次。
     */
    fun splitMaterial(text: String): List<String> {
        val lines = text.split('\n').map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.size <= 1) return splitSentences(text)
        val out = ArrayList<String>()
        for (line in lines) out.addAll(splitSentences(line))
        return out
    }

    /** 英文字母个数（判断「有没有听到内容」用，数字/标点不算）。 */
    fun letterCount(text: String): Int {
        var count = 0
        for (ch in text) {
            if ((ch in 'a'..'z') || (ch in 'A'..'Z')) count++
        }
        return count
    }

    /** 取首行并截断（保存书页的默认标题）；空文本回落到「未命名书页」。 */
    fun firstLine(text: String, max: Int): String {
        val idx = text.indexOf('\n')
        val line = if (idx >= 0) text.substring(0, idx) else text
        val trimmed = line.trim()
        val value = if (trimmed.length > max) trimmed.substring(0, max) else trimmed
        return value.ifEmpty { "未命名书页" }
    }
}

// ---------------------------------------------------------------------------
// 鼓励语池（6 档 × 5 条中英双语；成长型措辞，儿童视角不出现否定词）
// ---------------------------------------------------------------------------

/** 一条中英双语鼓励语。 */
data class FlowEnc(val zh: String, val en: String)

/** 鼓励语池（照抄 hos FlowVM 的 POOL_S/A/B/C/NO_SPEECH/INCOMPLETE）。 */
object FlowEncPools {

    val S: List<FlowEnc> = listOf(
        FlowEnc("太棒了！这次特别清楚！", "Great job! That was so clear!"),
        FlowEnc("哇，这次读得特别棒！", "Wow, you did great!"),
        FlowEnc("进步好大，继续保持！", "Big progress! Keep going!"),
        FlowEnc("这次的声音又清楚又好听！", "That sounded clear and lovely!"),
        FlowEnc("太厉害了，一口气读下来了！", "Amazing! You read the whole thing!"),
    )

    val A: List<FlowEnc> = listOf(
        FlowEnc("读得很好！继续这样就好。", "Nice reading! Keep it up."),
        FlowEnc("很稳！保持这个节奏。", "Very steady! Keep this rhythm."),
        FlowEnc("这次比上次更顺了。", "Smoother than last time!"),
        FlowEnc("很好，句子都读完整了。", "Good job finishing every sentence."),
        FlowEnc("听起来很棒，再来一次会更好。", "Sounds great! One more time will be even better."),
    )

    val B: List<FlowEnc> = listOf(
        FlowEnc("很认真！再读一遍会更顺。", "Good try! Reading again will be smoother."),
        FlowEnc("看到你在努力，继续保持。", "I can see your effort. Keep going!"),
        FlowEnc("大部分都读到了，真棒！", "You got most of it. Nice work!"),
        FlowEnc("慢一点会更清楚，我们再试试。", "Slow down a little and try again."),
        FlowEnc("你的声音很响亮，很好！", "Your voice was nice and loud!"),
    )

    val C: List<FlowEnc> = listOf(
        FlowEnc("谢谢你勇敢地读出来。我们慢慢来。", "Thank you for reading! Let us take our time."),
        FlowEnc("敢开口就很了不起，我们一起再试试。", "Speaking up is brave. Let us try together."),
        FlowEnc("今天已经在进步的路上了。", "You are on the way. Keep going!"),
        FlowEnc("我听到你的声音了，我们再练一次。", "I heard your voice! Let us practice again."),
        FlowEnc("一点点来，你已经在变好了。", "Little by little, you are getting better."),
    )

    val NO_SPEECH: List<FlowEnc> = listOf(
        FlowEnc("这次好像没听到你的声音，我们再来一次好吗？", "Let us try again! I will listen."),
        FlowEnc("麦克风可能没收到，靠近一点再说一次吧。", "Come a little closer and say it again."),
        FlowEnc("没关系，我们深呼吸一下再来一次。", "No worries. Take a breath and try again."),
        FlowEnc("准备好了吗？我在这儿听着呢。", "Ready? I am listening."),
        FlowEnc("我们慢慢来，先大声说一句试试。", "Take your time. Say one sentence loudly."),
    )

    val INCOMPLETE: List<FlowEnc> = listOf(
        FlowEnc("有几句话没读完，没关系，我们试试一口气读完。", "You can do it! Let us finish the whole page."),
        FlowEnc("读到一半也很好，下次把它读完吧。", "Halfway is good too. Let us finish next time."),
        FlowEnc("慢慢来，把每一句都读完就更棒了。", "Take your time and finish each sentence."),
        FlowEnc("我们已经读了一大半了，再读一点点就好。", "We are almost done. Just a little more."),
        FlowEnc("一句一句来，读完最后一句我们就成功啦。", "One sentence at a time. Let us finish the last one!"),
    )

    fun forTier(tier: String): List<FlowEnc> = when (tier) {
        "S" -> S
        "A" -> A
        "B" -> B
        "C" -> C
        "incomplete" -> INCOMPLETE
        else -> NO_SPEECH
    }

    /** FNV 风格确定性哈希：同一批结果永远选到同一条文案（照抄 hos）。 */
    fun stableHash(input: String): Int {
        var h = 0L
        for (ch in input) {
            h = (h * 31 + ch.code) % 1_000_000_007L
        }
        return h.toInt()
    }
}

// ---------------------------------------------------------------------------
// 进程内运行态共享（Tab 根页 ↔ 汇总页）
// ---------------------------------------------------------------------------

/**
 * 连读运行态的进程内单例（对应 hos `FlowRunStore`）。
 *
 * 为什么需要：`FlowTab()` 是 Tab 根页、汇总页是 push 出来的二级页，两者各有自己的 ViewModel；
 * 汇总页展示的是「同一轮连读」的同一份状态（逐条列表、「重录这句」、「再读一遍」都要改它）。
 *
 * 生命周期：FlowViewModel 创建时 [attach]、`onCleared()` 时 [detach]；
 * 汇总页读不到（进程被杀 / 直接打开）时展示空态并返回。
 */
object FlowRunStore {

    @Volatile
    private var run: FlowViewModel? = null

    fun attach(vm: FlowViewModel) {
        run = vm
    }

    fun detach(vm: FlowViewModel) {
        if (run === vm) run = null
    }

    fun current(): FlowViewModel? = run
}

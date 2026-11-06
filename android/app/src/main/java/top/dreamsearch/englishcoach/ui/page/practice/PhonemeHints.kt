package top.dreamsearch.englishcoach.ui.page.practice

/**
 * 音素教学提示（音素/hint_key → 中文 why / how / 练习词）。
 *
 * 移植自鸿蒙实现 `hos/entry/src/main/ets/core/content/PhonemeHints.ets`
 * （与 Web 端 `web/src/lib/hints.ts` 的 canonical-v1 对齐：18 个合法键 + GENERIC 兜底）。
 *
 * 用途：跟读结果页「需要纠正的地方」卡片，把服务端 `IssueDto` 的
 * `hint_key`（优先）/`expected` 音素翻译成家长和孩子都能看懂的中文。
 *
 * 儿童规则（docs/screens.md §0）：儿童版**不出现 IPA 符号**，文案更短更口语；
 * 没有单独儿童版的键沿用成人版文字（与 hos 行为一致）。
 */
data class PhonemeHint(
    val key: String = "",
    val titleZh: String = "",
    val titleChild: String = "",
    val whyZh: String = "",
    val whyChild: String = "",
    val howZh: String = "",
    val howChild: String = "",
    val words: List<String> = emptyList(),
    val demoText: String = "",
)

object PhonemeHints {

    /** 音素符号 → hint_key（与 hos PHONEME_TO_KEY 逐条一致）。 */
    private val phonemeToKey: Map<String, String> = mapOf(
        "θ" to "th_voiceless",
        "ð" to "th_voiced",
        "r" to "r_l_v",
        "l" to "r_l_v",
        "v" to "v_w",
        "w" to "v_w",
        "s" to "s_sh",
        "ʃ" to "s_sh",
        "n" to "n_ng",
        "ŋ" to "n_ng",
        "i" to "short_i_long_i",
        "ɪ" to "short_i_long_i",
        "e" to "ae_e",
        "æ" to "ae_e",
        "ə" to "schwa",
        "ɜ" to "schwa",
        "tʃ" to "consonant_cluster",
        "dʒ" to "consonant_cluster",
    )

    private val generic: PhonemeHint = PhonemeHint(
        key = "generic",
        titleZh = "这个词可以再清楚一点",
        titleChild = "这个词再说清楚一点点",
        whyZh = "发音清晰度还可以提高。",
        whyChild = "发音清晰度还可以提高。",
        howZh = "放慢速度，把每个音都说完整，再录一遍试试。",
        howChild = "放慢速度，把每个音都说完整，再录一遍试试。",
        words = emptyList(),
        demoText = "",
    )

    private val table: Map<String, PhonemeHint> by lazy {
        listOf(
            PhonemeHint(
                key = "th_voiceless",
                titleZh = "th 的 /θ/ 音（如 think）",
                titleChild = "think 里开头的那个「咬舌音」",
                whyZh = "舌尖没有伸出来，气流从牙龈缝隙出去了，听起来像 /s/。",
                whyChild = "舌尖没有伸出来，气从牙缝里跑掉了，听起来有点像 s。",
                howZh = "舌尖轻轻伸到上下齿之间，让气流从缝里摩擦出来，声带不要振动。",
                howChild = "舌尖轻轻伸到上下牙齿之间，让气从缝里出来，嗓子不要振动。",
                words = listOf("think", "thank", "three", "thick"),
                demoText = "think, thank, three",
            ),
            PhonemeHint(
                key = "th_voiced",
                titleZh = "th 的 /ð/ 音（如 this）",
                titleChild = "this 里那个「带声音的咬舌音」",
                whyZh = "舌尖位置不对，/ð/ 被读成了 /d/ 或 /z/。",
                whyChild = "舌尖的位置不太对，这个音听起来像 d 或者 z。",
                howZh = "舌尖放在上下齿之间，这次要让声带振动，喉咙有嗡嗡的震感。",
                howChild = "舌尖放在上下牙齿中间，这次要让嗓子嗡嗡地振动起来。",
                words = listOf("this", "that", "mother", "weather"),
                demoText = "this, that, mother",
            ),
            PhonemeHint(
                key = "r_l_v",
                titleZh = "/r/ 与 /l/ 混淆",
                titleChild = "r 和 l 两个音要分开",
                whyZh = "舌尖卷起与顶住上齿龈的动作没有区分开。",
                whyChild = "r 和 l 的舌头动作没有分开，听起来会混。",
                howZh = "/r/ 舌尖悬空向后卷，不碰上颚；/l/ 舌尖要顶住上齿龈。",
                howChild = "r 的舌尖要悬空向后卷、不碰上颚；l 的舌尖要顶住上齿龈。",
                words = listOf("right", "light", "really", "little"),
                demoText = "right, light, really",
            ),
            PhonemeHint(
                key = "v_w",
                titleZh = "/v/ 与 /w/ 混淆",
                titleChild = "v 要咬嘴唇，w 要圆嘴巴",
                whyZh = "/v/ 缺少上齿咬下唇的摩擦，听起来像 /w/。",
                whyChild = "上齿没有咬住下唇，这个音听起来像 w。",
                howZh = "上齿轻咬下唇送气＝/v/；双唇收圆不碰牙齿＝/w/。",
                howChild = "上齿轻轻咬住下唇送气就是 v；双唇收圆、不碰牙齿就是 w。",
                words = listOf("very", "west", "voice", "water"),
                demoText = "very, west, voice",
            ),
            PhonemeHint(
                key = "short_i_long_i",
                titleZh = "短 /ɪ/ 与长 /i/（canonical-v1）",
                titleChild = "短音和长音要拉长一点",
                whyZh = "长短元音没有区分，ship 听成了 sheep。",
                whyChild = "长音和短音没有分开，ship 听起来像 sheep。",
                howZh = "/i/ 嘴角往两边拉开并保持久一点；/ɪ/ 短促、嘴角放松。",
                howChild = "长音要把嘴角往两边拉开、保持久一点；短音要短促、嘴角放松。",
                words = listOf("ship", "sheep", "sit", "seat"),
                demoText = "ship, sheep, sit, seat",
            ),
            PhonemeHint(
                key = "ae_e",
                titleZh = "/æ/ 与 /e/",
                titleChild = "嘴巴要张大一点",
                whyZh = "/æ/ 开口不够大，听起来像 /e/。",
                whyChild = "嘴巴张得不够大，这个音听起来像 e。",
                howZh = "下巴放低，嘴角略向两边，像说「啊」又像「哎」。",
                howChild = "下巴放低，嘴角往两边一点，像说「啊」又像「哎」。",
                words = listOf("cat", "bed", "apple", "pen"),
                demoText = "cat, bed, apple",
            ),
            PhonemeHint(
                key = "s_sh",
                titleZh = "/s/ 与 /ʃ/",
                titleChild = "sh 要把嘴唇收圆",
                whyZh = "舌位太靠前，/ʃ/ 被读成 /s/。",
                whyChild = "舌头太靠前了，sh 这个音听起来像 s。",
                howZh = "舌面抬高靠近硬腭，双唇稍微收圆前突。",
                howChild = "舌头抬高靠近上颚，嘴唇稍微收圆往前。",
                words = listOf("she", "sea", "shoe", "sure"),
                demoText = "she, sea, shoe",
            ),
            PhonemeHint(
                key = "n_ng",
                titleZh = "词尾 /n/ 与 /ŋ/",
                titleChild = "结尾的 ng 要从鼻子里出来",
                whyZh = "词尾鼻音区分不清，sin 与 sing 一样。",
                whyChild = "结尾的鼻音区分不清，sin 和 sing 听起来一样。",
                howZh = "/ŋ/ 舌根抬起顶住软腭，气流从鼻腔出来，舌尖不要碰齿龈。",
                howChild = "发结尾的 ng 时，舌根抬起来顶住软腭，气从鼻子出来，舌尖不要碰上齿龈。",
                words = listOf("sing", "sin", "thing", "thin"),
                demoText = "sing, thing, long",
            ),
            PhonemeHint(
                key = "l_dark",
                titleZh = "词尾暗 /l/",
                titleChild = "结尾的 l 舌头要抬起来",
                whyZh = "词尾 /l/ 被吞掉或读成元音。",
                whyChild = "结尾的 l 被吞掉了。",
                howZh = "舌尖顶住上齿龈并保持住，再收尾。",
                howChild = "结尾的 l 要把舌尖顶住上齿龈，保持一下再收。",
                words = listOf("milk", "school", "little", "apple"),
                demoText = "milk, school, little",
            ),
            PhonemeHint(
                key = "schwa",
                titleZh = "非重读弱元音 /ə/",
                titleChild = "不重要的音节要读得又轻又短",
                whyZh = "每个音节都读得太重，节奏听起来很硬。",
                whyChild = "每个音节都读得太重，听起来有点硬。",
                howZh = "非重读音节放松成轻轻的「呃」，重音只放在一个音节上。",
                howChild = "不重要的音节轻轻带过，只有重音的音节读得响一点。",
                words = listOf("banana", "about", "teacher", "today"),
                demoText = "banana, about, teacher",
            ),
            PhonemeHint(
                key = "final_consonant",
                titleZh = "词尾辅音丢失",
                titleChild = "最后一个音也要说完整",
                whyZh = "词尾辅音没有发出来，look 听成了 loo。",
                whyChild = "最后一个音没有说出来，look 听起来像 loo。",
                howZh = "句子结束时也要把最后的辅音轻轻收住，不要吞掉。",
                howChild = "最后一个音也要轻轻收住，不要说一半。",
                words = listOf("book", "good", "cat", "stop"),
                demoText = "book, good, cat",
            ),
            PhonemeHint(
                key = "consonant_cluster",
                titleZh = "辅音连缀",
                titleChild = "两个辅音要连在一起说",
                whyZh = "连缀中间被插入了元音，strike 读成 sutrike。",
                whyChild = "两个辅音中间多了一个音。",
                howZh = "把两个辅音紧挨着快速说出，中间不要加「呃」。",
                howChild = "两个辅音紧挨着快速说出来，中间不要加别的音。",
                words = listOf("street", "spring", "desk", "asked"),
                demoText = "street, spring, desk",
            ),
            PhonemeHint(
                key = "stress_wrong",
                titleZh = "单词重音位置",
                titleChild = "有一个音节要读得更响",
                whyZh = "重音位置不对，单词听起来不自然。",
                whyChild = "重音的位置不太对。",
                howZh = "重读音节读得更长、更响、更高，其余音节弱化。",
                howChild = "有一个音节读得更长、更响、更高，其它音节轻轻带过。",
                words = listOf("record", "present", "banana", "photograph"),
                demoText = "banana, present, photograph",
            ),
            PhonemeHint(
                key = "monotone",
                titleZh = "语调太平",
                titleChild = "声音要有高有低才像在说话",
                whyZh = "整句音高几乎没有起伏。",
                whyChild = "整句的高低变化太少了。",
                howZh = "陈述句结尾轻轻下降，疑问句结尾明显上扬。",
                howChild = "说句子的时候声音要有高有低，结尾可以降一点或升一点。",
                words = listOf("Really?", "Is it?", "Nice to meet you."),
                demoText = "Is it? Yes, it is.",
            ),
            PhonemeHint(
                key = "pause_wrong",
                titleZh = "停顿位置不当",
                titleChild = "在词组之间换气，不要在词中间停",
                whyZh = "在意群中间断开，影响理解。",
                whyChild = "在词中间停下来了，听起来会断。",
                howZh = "按意群（短语）停顿，一次说完一个词组。",
                howChild = "把词组连着说完，在词组之间再换气。",
                words = listOf("in the morning", "at school", "with my friend"),
                demoText = "in the morning, at school",
            ),
            PhonemeHint(
                key = "omission",
                titleZh = "漏词",
                titleChild = "有个词忘记说了",
                whyZh = "参考句里的单词没有读出来。",
                whyChild = "有一个词没有读出来。",
                howZh = "放慢速度，一个词一个词看清楚再连起来读。",
                howChild = "慢一点，一个词一个词看清楚再连起来读。",
                words = emptyList(),
                demoText = "",
            ),
            PhonemeHint(
                key = "insertion",
                titleZh = "多词",
                titleChild = "多说了词",
                whyZh = "读出了参考句以外的内容。",
                whyChild = "多读了一些内容。",
                howZh = "先默读一遍参考句，再开口录音。",
                howChild = "先在心里读一遍句子，再开口录音。",
                words = emptyList(),
                demoText = "",
            ),
        ).associateBy { it.key }
    }

    fun byKey(key: String): PhonemeHint = table[key] ?: generic

    /** 音素符号 → hint_key → 提示；没有映射时返回 GENERIC。 */
    fun byPhoneme(phoneme: String): PhonemeHint {
        val key = phonemeToKey[phoneme.trim()] ?: return generic
        return byKey(key)
    }

    fun title(hint: PhonemeHint, isChild: Boolean): String =
        if (isChild) hint.titleChild.ifEmpty { hint.titleZh } else hint.titleZh

    fun why(hint: PhonemeHint, isChild: Boolean): String =
        if (isChild) hint.whyChild.ifEmpty { hint.whyZh } else hint.whyZh

    fun how(hint: PhonemeHint, isChild: Boolean): String =
        if (isChild) hint.howChild.ifEmpty { hint.howZh } else hint.howZh
}

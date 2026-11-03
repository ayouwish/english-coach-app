package top.dreamsearch.englishcoach.core.audio

/**
 * 内置音色常量（移植 hos `core/service/MediaService.ets` 的 9 个音色）。
 *
 * 为什么内置：`GET /api/tts/voices` 线上 404（CONTRACT §3.2），音色清单按规格固化在客户端；
 * 字段与服务端一致：id / label_zh / lang / sample（没有 gender 字段）。
 *
 * @property id 传给 `POST /tts` 的 voice 参数
 * @property labelZh 设置页显示的中文名
 * @property lang 'en' / 'zh'
 * @property sample 试听示例文本
 * @property isEnglish 是否英语音色（= lang == "en"，页面筛选用）
 */
data class TtsVoice(
    val id: String,
    val labelZh: String,
    val lang: String,
    val sample: String,
    val isEnglish: Boolean,
)

/** 9 个内置音色：英语 5 + 中文 4。 */
object Voices {

    val ALL: List<TtsVoice> = listOf(
        TtsVoice(
            id = "en-US-JennyNeural",
            labelZh = "Jenny · 英语女声（默认）",
            lang = "en",
            sample = "Hello! Let's practice English together.",
            isEnglish = true,
        ),
        TtsVoice(
            id = "en-US-AriaNeural",
            labelZh = "Aria · 英语女声（活泼）",
            lang = "en",
            sample = "Hi there! Ready for a story?",
            isEnglish = true,
        ),
        TtsVoice(
            id = "en-US-AnaNeural",
            labelZh = "Ana · 英语童声",
            lang = "en",
            sample = "I like playing with my friends!",
            isEnglish = true,
        ),
        TtsVoice(
            id = "en-US-GuyNeural",
            labelZh = "Guy · 英语男声",
            lang = "en",
            sample = "Good job! Let's try the next sentence.",
            isEnglish = true,
        ),
        TtsVoice(
            id = "en-US-MichelleNeural",
            labelZh = "Michelle · 英语女声（温柔）",
            lang = "en",
            sample = "Take your time. You are doing great.",
            isEnglish = true,
        ),
        TtsVoice(
            id = "zh-CN-XiaoxiaoNeural",
            labelZh = "晓晓 · 中文女声（默认）",
            lang = "zh",
            sample = "你好呀，我们一起来练习吧。",
            isEnglish = false,
        ),
        TtsVoice(
            id = "zh-CN-XiaoyiNeural",
            labelZh = "晓伊 · 中文女声（温柔）",
            lang = "zh",
            sample = "慢慢来，不着急。",
            isEnglish = false,
        ),
        TtsVoice(
            id = "zh-CN-YunxiNeural",
            labelZh = "云希 · 中文男声",
            lang = "zh",
            sample = "太棒了，继续加油！",
            isEnglish = false,
        ),
        TtsVoice(
            id = "zh-CN-YunjianNeural",
            labelZh = "云健 · 中文男声（沉稳）",
            lang = "zh",
            sample = "今天我们一起读一个小故事。",
            isEnglish = false,
        ),
    )

    /** 按 id 找音色；找不到（空/线上旧 id）返回 null，页面显示「默认音色」。 */
    fun find(id: String?): TtsVoice? {
        if (id.isNullOrEmpty()) return null
        return ALL.firstOrNull { it.id == id }
    }
}

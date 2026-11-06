package top.dreamsearch.englishcoach.ui.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Design tokens · 唯一来源（对应 hos `design/DesignTokens.ets` 与仓库根 `docs/design-tokens.md`）。
 *
 * 真实值（与 Web / 鸿蒙端对齐）：背景 #F5F7FF、主色 #5B5BD6、卡片 20dp、弹层 28dp、按钮 14dp。
 * 页面里不要再写魔法值；按语义取 token。
 */
object EcColor {
    val bg = Color(0xFFF5F7FF)
    val surface = Color(0xFFFFFFFF)
    val surfaceAlt = Color(0xFFF1F3FF)
    val ink = Color(0xFF1B1F3B)
    val muted = Color(0xFF6B7290)
    val border = Color(0xFFE3E6F3)
    val primary = Color(0xFF5B5BD6)
    val primaryPressed = Color(0xFF4A4AC4)
    val primarySoft = Color(0xFFECEBFF)
    val focus = Color(0xFFA5B4FC)
    val good = Color(0xFF16A34A)
    val goodText = Color(0xFF15803D)
    val goodBg = Color(0xFFF0FDF4)
    val warn = Color(0xFFF59E0B)
    val warnText = Color(0xFFB45309)
    val warnBg = Color(0xFFFFF3D6)
    val bad = Color(0xFFEF4444)
    val badText = Color(0xFFB91C1C)
    val badBg = Color(0xFFFEF2F2)
    val info = Color(0xFF0EA5E9)
    val overlay = Color(0x5C1B1F3B)
}

object EcSpace {
    val x1 = 4.dp
    val x2 = 8.dp
    val x3 = 12.dp
    val x4 = 16.dp
    val x5 = 20.dp
    val x6 = 24.dp
    val x8 = 32.dp
    val x10 = 40.dp
    val x12 = 48.dp
}

object EcRadius {
    val sm = 8.dp

    /** 按钮 / 输入框（Web 0.9rem） */
    val md = 14.dp

    /** 卡片（Web 1.25rem） */
    val lg = 20.dp

    /** 大容器 / 弹层（Web 1.75rem） */
    val xl = 28.dp
    val pill = 999.dp
}

object EcFont {
    val display = 32.sp
    val h1 = 28.sp
    val h2 = 24.sp
    val h3 = 20.sp
    val body = 16.sp
    val caption = 13.sp
    val micro = 11.sp
    val childBody = 19.sp
    val childH1 = 30.sp
    val childButton = 19.sp

    /** 句子卡英文正文 */
    val sentence = 22.sp
}

object EcButtonSize {
    val sm = 36.dp
    val md = 48.dp
    val lg = 56.dp

    /** 儿童所有可点按钮 */
    val child = 60.dp

    /** 录音主按钮 */
    val record = 72.dp
    val recordChild = 88.dp
}

/**
 * 分数展示规则（docs/screens.md §0、docs/design-system.md §1.2）。
 *
 * 成人：0–100 数字 + 语义色（≥85 good / 70–84 info / 60–69 warn / <60 bad）。
 * 儿童：<60 **不显示数字、不用红色**，只给鼓励语 + 星星。
 */
object EcScore {

    fun color(score: Double?, isChild: Boolean): Color {
        if (score == null) return EcColor.muted
        return if (isChild) colorForChild(score) else color(score)
    }

    fun color(score: Double?): Color {
        if (score == null) return EcColor.muted
        return when {
            score >= 85 -> EcColor.good
            score >= 70 -> EcColor.info
            score >= 60 -> EcColor.warn
            else -> EcColor.bad
        }
    }

    /** 儿童的分数颜色：低分用 warn（不刺眼），不出现红色。 */
    fun colorForChild(score: Double?): Color {
        if (score == null) return EcColor.muted
        return when {
            score >= 85 -> EcColor.good
            score >= 60 -> EcColor.info
            else -> EcColor.warn
        }
    }

    /** 儿童 <60 不展示数字；null（不可得）一律不展示。 */
    fun showNumber(score: Double?, isChild: Boolean): Boolean {
        if (score == null) return false
        if (!isChild) return true
        return score >= 60
    }

    fun numberText(score: Double?): String {
        if (score == null) return "—"
        return score.toInt().toString()
    }

    /** 总分一句话（成人/儿童两套语气，儿童不出现否定词）。 */
    fun encouragement(score: Double?, isChild: Boolean): String {
        if (score == null) {
            return if (isChild) "录好啦，等下再看分数" else "本次没有拿到分数，可稍后重试评测"
        }
        return when {
            score >= 90 -> if (isChild) "太棒啦，读得非常清楚 🌟" else "很稳，几乎和示范一样清楚"
            score >= 80 -> if (isChild) "读得真好，继续加油 ⭐" else "整体很好，个别词再注意一下"
            score >= 70 -> if (isChild) "不错哦，再读一遍会更顺 💪" else "不错，节奏和重音还能更自然"
            score >= 60 -> if (isChild) "有进步，再试一次吧 🌱" else "基本能听懂，慢一点会更清楚"
            else -> if (isChild) "再来一次会更好 💪" else "这句话有点难，放慢速度再读一遍，注意加粗的词"
        }
    }

    fun stars(score: Double?): String = when {
        score == null -> "⭐"
        score >= 85 -> "⭐⭐⭐"
        score >= 70 -> "⭐⭐"
        else -> "⭐"
    }

    /** 子项中文名（儿童版在文案层换成「说得准不准」等口语说法）。 */
    fun subScoreLabel(key: String): String = when (key) {
        "accuracy" -> "准确度"
        "fluency" -> "流利度"
        "completeness" -> "完整度"
        "prosody" -> "语调"
        else -> key
    }
}

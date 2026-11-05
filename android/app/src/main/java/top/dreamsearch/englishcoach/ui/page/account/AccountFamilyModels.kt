package top.dreamsearch.englishcoach.ui.page.account

import androidx.compose.ui.graphics.Color
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.net.dto.AvatarImagesDto
import top.dreamsearch.englishcoach.core.net.dto.ParentTrendPointDto
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor

/**
 * 家庭/形象/音色五页共享的常量与格式化函数。
 *
 * 对应 hos：`hos/entry/src/main/ets/viewmodel/AccountVM.ets` 里散落在各 VM 的 helper
 * （`ParentVM.minutes/scoreText`、`SuggestionsVM.categoryLabel/statusLabel`、`MediaService.publicUrl`），
 * 以及 `hos/entry/src/main/ets/pages/{Parent,Family,Suggestions,Avatar,Voices}Page.ets` 的静态文案。
 *
 * 规则（docs/screens.md §10/§11/§13、docs/screens-matrix.md §6/§7）：
 * - 数值一律「—」兜底，不显示 null/NaN；
 * - 日期只保留 `MM-dd`（家长面板/盲测柱状图标签够用，避免长文本挤爆一行）；
 * - 形象只允许加载**预置静态图**（`/avatars/...`，无需鉴权）；照片路径按隐私策略不展示。
 */

/** 建议分类（家长 5 类 / 儿童 3 类，文案两套；对应 hos `SuggestionCategory`）。 */
data class SuggestionCategory(
    val key: String,
    val adultLabel: String,
    val childLabel: String,
)

object AccountFormat {

    /** 家庭成员可选 CEFR（含 C1；与 hos FamilyPage.cefrOptions 一致）。 */
    val LEVELS: List<String> = listOf("A1", "A2", "B1", "B2", "C1")

    /** 建议分类全集（儿童只取 experience / content / other）。 */
    val CATEGORIES: List<SuggestionCategory> = listOf(
        SuggestionCategory("experience", "体验问题", "用起来哪里不顺手"),
        SuggestionCategory("content", "内容建议", "想读·想聊的内容"),
        SuggestionCategory("feature", "新功能想法", "想要的新功能"),
        SuggestionCategory("bug", "程序出错", "哪里出错了"),
        SuggestionCategory("other", "其他", "其他想法"),
    )

    /** 当前角色可选的分类（儿童 3 类）。 */
    fun categoriesFor(isChild: Boolean): List<SuggestionCategory> =
        if (isChild) {
            CATEGORIES.filter { it.key == "experience" || it.key == "content" || it.key == "other" }
        } else {
            CATEGORIES
        }

    /** 分类 key → 中文（儿童用儿童版文案，未知 key 原样显示）。 */
    fun categoryLabel(key: String, isChild: Boolean): String {
        val item = CATEGORIES.firstOrNull { it.key == key } ?: return key
        return if (isChild) item.childLabel else item.adultLabel
    }

    /** 建议状态 key → 中文。 */
    fun statusLabel(status: String): String = when (status) {
        "open" -> "未读"
        "read" -> "已读"
        "resolved" -> "已解决"
        else -> status
    }

    /** 建议状态 → 标签色调。 */
    fun statusTone(status: String): PillTone = when (status) {
        "open" -> PillTone.WARN
        "read" -> PillTone.INFO
        "resolved" -> PillTone.GOOD
        else -> PillTone.NEUTRAL
    }

    /** 角色 key → 中文。 */
    fun roleLabel(role: String): String = when (role) {
        "child" -> "孩子"
        "parent" -> "家长"
        else -> "成员"
    }

    /** 成员徽标：`孩子 · A2`。 */
    fun roleBadge(role: String, cefrLevel: String): String {
        val roleText = roleLabel(role)
        return if (cefrLevel.isEmpty()) roleText else "$roleText · $cefrLevel"
    }

    /** 成员头像：服务端给 emoji，缺省按角色兜底。 */
    fun memberAvatar(avatar: String?, role: String): String =
        avatar?.takeIf { it.isNotEmpty() } ?: if (role == "child") "🧒" else "👤"

    /** 整数分钟（家长面板汇总用）。 */
    fun minutes(value: Int): String = value.toString()

    /** 一位小数的分钟（用餐时长可能带小数）。 */
    fun minutes1(value: Double?): String {
        if (value == null) return "—"
        return (Math.round(value * 10.0) / 10.0).toString()
    }

    /** 分数文本：一位小数；null → 「—」（不把缺分画成 0）。 */
    fun scoreText(score: Double?): String {
        if (score == null) return "—"
        return (Math.round(score * 10.0) / 10.0).toString()
    }

    /** ISO 时间 → `MM-dd`（解析失败返回空串，页面不显示）。 */
    fun dateText(iso: String): String {
        if (iso.length < 10) return ""
        val month = iso.substring(5, 7)
        val day = iso.substring(8, 10)
        if (month.toIntOrNull() == null || day.toIntOrNull() == null) return ""
        return "$month-$day"
    }

    /** 趋势点 → 折线值（null 保留断点）。 */
    fun trendValues(points: List<ParentTrendPointDto>): List<Float?> =
        points.map { point -> point.avgPron?.toFloat() }

    /** 趋势点 → X 轴标签（`MM-dd`）。 */
    fun trendLabels(points: List<ParentTrendPointDto>): List<String> =
        points.map { point -> dateText(point.date) }

    /** 盲测环比文案（对应 hos `ParentVM.blindDeltaText`）。 */
    fun blindDeltaText(delta: Double?): String {
        if (delta == null) return "首次（无对比）"
        val rounded = Math.round(delta * 10.0) / 10.0
        return when {
            delta > 0.0 -> "▲ +$rounded"
            delta < 0.0 -> "▼ $rounded"
            else -> "＝ 0"
        }
    }

    /** 盲测环比颜色：涨绿 / 跌红 / 平灰（家长面板是成人视角）。 */
    fun blindDeltaColor(delta: Double?): Color = when {
        delta == null -> EcColor.muted
        delta > 0.0 -> EcColor.goodText
        delta < 0.0 -> EcColor.badText
        else -> EcColor.muted
    }

    /** 掌握度条宽度：null 给小底色（2%），不把「无数据」画成 0 分（对应 hos `weakBarWidth`）。 */
    fun barFraction(score: Double?): Float {
        if (score == null) return 0.02f
        return (score.coerceIn(0.0, 100.0) / 100.0).toFloat().coerceAtLeast(0.02f)
    }

    /**
     * 站内静态资源 → 绝对 URL（对应 hos `MediaService.publicUrl`）。
     * 已是 http(s) 的原样返回；空串返回空串（调用方显示占位）。
     */
    fun publicUrl(path: String): String {
        val trimmed = path.trim()
        if (trimmed.isEmpty()) return ""
        val lower = trimmed.lowercase()
        if (lower.startsWith("http://") || lower.startsWith("https://")) return trimmed
        val base = AppGraph.container.config.baseUrl
        return if (trimmed.startsWith("/")) base + trimmed else "$base/$trimmed"
    }

    /** 形象图是否可公开展示：只有预置静态图 `/avatars/...` 可以（照片路径按隐私策略关闭）。 */
    fun isPublicAvatarPath(path: String): Boolean = path.startsWith("/avatars/")

    /** 按风格 id 取角色图片的站内路径（5 个风格键固定）。 */
    fun avatarPath(images: AvatarImagesDto?, style: String): String {
        if (images == null) return ""
        val value = when (style) {
            "watercolor" -> images.watercolor
            "cartoon" -> images.cartoon
            "pixel" -> images.pixel
            "papercut" -> images.papercut
            "clay" -> images.clay
            else -> ""
        }
        return publicUrl(value)
    }
}

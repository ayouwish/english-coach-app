package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcScore
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 分数展示组件（移植 hos `components/ScoreViews.ets` 的 ScoreRing / SubScoreBar）。
 *
 * 儿童规则（docs/screens.md §0）：
 * - <60 不显示数字、不用红色，只显示 🌱 + 鼓励语；
 * - 颜色统一走 [EcScore.color] 的儿童分支（低分用 warn）。
 */

/**
 * 总分环：Progress Ring + 中间数字（儿童 <60 显示 🌱）。
 *
 * @param score 0–100；null 表示无分数（环空转、中间显示 —）
 * @param isChild 默认取 [LocalIsChild]（主题注入），页面一般不用传
 * @param label 环内小标签（如「总分」「继续加油」），null 时不显示
 * @param caption 环下方一行小字（如「综合分」），null 时不占位
 */
@Composable
fun ScoreBadge(
    score: Double?,
    isChild: Boolean = LocalIsChild.current,
    label: String? = null,
    caption: String? = null,
) {
    val ringColor = EcScore.color(score, isChild)
    val showNumber = EcScore.showNumber(score, isChild)
    val centerText = when {
        showNumber -> EcScore.numberText(score)
        score == null -> "—"
        isChild -> "🌱"
        else -> "—"
    }
    val description = buildString {
        if (showNumber) {
            append(label ?: "总分")
            append(EcScore.numberText(score))
            append("分")
        } else {
            append(EcScore.encouragement(score, isChild))
        }
        if (!caption.isNullOrEmpty()) {
            append("，")
            append(caption)
        }
    }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Box(
            modifier = Modifier
                .size(96.dp)
                .semantics { contentDescription = description },
            contentAlignment = Alignment.Center,
        ) {
            Canvas(modifier = Modifier.size(96.dp)) {
                val stroke = 9.dp.toPx()
                val inset = stroke / 2f
                val arcSize = Size(size.width - stroke, size.height - stroke)
                drawArc(
                    color = EcColor.surfaceAlt,
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    topLeft = Offset(inset, inset),
                    size = arcSize,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                )
                val safeScore = (score ?: 0.0).coerceIn(0.0, 100.0)
                if (safeScore > 0.0) {
                    drawArc(
                        color = ringColor,
                        startAngle = -90f,
                        sweepAngle = (safeScore / 100.0 * 360.0).toFloat(),
                        useCenter = false,
                        topLeft = Offset(inset, inset),
                        size = arcSize,
                        style = Stroke(width = stroke, cap = StrokeCap.Round),
                    )
                }
            }
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(0.dp),
            ) {
                Text(
                    text = centerText,
                    fontSize = if (isChild) EcFont.h2 else EcFont.h1,
                    fontWeight = FontWeight.Bold,
                    color = ringColor,
                )
                if (!label.isNullOrEmpty()) {
                    Text(text = label, fontSize = EcFont.micro, color = EcColor.muted)
                }
            }
        }
        if (!caption.isNullOrEmpty()) {
            Text(
                text = caption,
                fontSize = EcFont.micro,
                color = EcColor.muted,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/**
 * 分数小胶囊（逐词评分、小节得分等）：底色取分数语义色的浅色，文字取深色变体。
 * `text` 由页面拼好（如「准确 82」）；儿童低分由 [EcScore.color] 自动变 warn。
 */
@Composable
fun ScoreChip(
    score: Double?,
    isChild: Boolean = LocalIsChild.current,
    text: String,
) {
    val color = EcScore.color(score, isChild)
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(EcRadius.sm))
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 8.dp, vertical = 3.dp),
    ) {
        Text(
            text = text,
            fontSize = EcFont.caption,
            fontWeight = FontWeight.Medium,
            color = color,
        )
    }
}

/**
 * 子项分数条（准确/流利/完整/语调）：label + 进度条 + 数值；null 显示 — 且不画 0 分。
 * 儿童 <60 不显示数字（显示 🌱），与总分规则一致。
 */
@Composable
fun SubScoreRow(
    items: List<Pair<String, Double?>>,
    isChild: Boolean = LocalIsChild.current,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        items.forEach { (key, score) ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(24.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = EcScore.subScoreLabel(key),
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                    modifier = Modifier.width(56.dp),
                )
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(8.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(EcColor.surfaceAlt),
                ) {
                    if (score != null) {
                        Box(
                            modifier = Modifier
                                .fillMaxHeight()
                                .fillMaxWidth((score.coerceIn(0.0, 100.0) / 100.0).toFloat())
                                .clip(RoundedCornerShape(4.dp))
                                .background(EcScore.color(score, isChild)),
                        )
                    }
                }
                val showNumber = EcScore.showNumber(score, isChild)
                val valueText = when {
                    score == null -> "—"
                    showNumber -> EcScore.numberText(score)
                    else -> "🌱"
                }
                Text(
                    text = valueText,
                    fontSize = EcFont.caption,
                    color = if (score != null) EcScore.color(score, isChild) else EcColor.muted,
                    textAlign = TextAlign.End,
                    modifier = Modifier.width(36.dp),
                )
            }
        }
    }
}

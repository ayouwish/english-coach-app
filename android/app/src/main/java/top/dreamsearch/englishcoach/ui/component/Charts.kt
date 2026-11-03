package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import kotlin.math.ceil

/**
 * 纯 Canvas 图表（不引第三方库；移植 hos `components/Charts.ets` 的
 * PitchChart / SparkLine / 柱状图能力，签名按 android/CONTRACT.md §4）。
 *
 * 约定：
 * - 语调曲线用 `List<Float?>`，`null` = 该点无 F0 → 断线不画（不伪造 0）；
 * - 不画网格，只画 0 / 50 / 100 三条淡参考线（docs/design-system.md §5.1）；
 * - 分数颜色由调用方传（通常 `EcColor.primary` / `EcScore.color`）。
 */

/**
 * 折线图（多系列）。X 轴按数据点下标均分；每个系列 `null` 处断线。
 *
 * @param series 每个系列一条曲线（如 [用户 F0, 示范 F0]）
 * @param colors 与 series 一一对应的颜色；不足时回退主色
 * @param minY/maxY Y 轴范围（分数 0–100；F0 传实际 Hz 范围）
 */
@Composable
fun EcLineChart(
    series: List<List<Float?>>,
    colors: List<Color>,
    height: Dp = 120.dp,
    minY: Float = 0f,
    maxY: Float = 100f,
) {
    val maxLength = series.maxOfOrNull { it.size } ?: 0
    if (maxLength == 0) return
    val range = (maxY - minY).takeIf { it > 0f } ?: 1f

    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(height),
    ) {
        val width = size.width
        val chartHeight = size.height
        drawGridLines(width = width, height = chartHeight)

        series.forEachIndexed { seriesIndex, points ->
            if (points.isEmpty()) return@forEachIndexed
            val color = colors.getOrNull(seriesIndex) ?: EcColor.primary
            val path = Path()
            var started = false
            points.forEachIndexed { index, value ->
                if (value == null) {
                    started = false
                    return@forEachIndexed
                }
                val x = if (maxLength <= 1) width / 2f else width * index / (maxLength - 1)
                val ratio = ((value.coerceIn(minY, maxY) - minY) / range).coerceIn(0f, 1f)
                val y = chartHeight - chartHeight * ratio
                if (started) {
                    path.lineTo(x, y)
                } else {
                    path.moveTo(x, y)
                    started = true
                }
            }
            drawPath(
                path = path,
                color = color,
                style = Stroke(
                    width = 2.dp.toPx(),
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                ),
            )
        }
    }
}

/**
 * 柱状图（盲测逐次柱 / 诊断分布）。
 * 标签在柱子下方一行显示；`values` 与 `labels` 长度不等时以较短为准。
 */
@Composable
fun EcBarChart(
    values: List<Float>,
    labels: List<String>,
    height: Dp = 120.dp,
    maxValue: Float = 100f,
    color: Color = EcColor.primary,
) {
    val safeMax = maxValue.takeIf { it > 0f } ?: 100f
    Column(modifier = Modifier.fillMaxWidth()) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(height),
        ) {
            drawGridLines(width = size.width, height = size.height)
            if (values.isEmpty()) return@Canvas
            val gap = 4.dp.toPx()
            val barWidth = ((size.width - gap * (values.size - 1)) / values.size)
                .coerceAtLeast(1.dp.toPx())
            values.forEachIndexed { index, value ->
                val ratio = (value / safeMax).coerceIn(0f, 1f)
                val barHeight = size.height * ratio
                val left = index * (barWidth + gap)
                drawRoundRect(
                    color = color,
                    topLeft = Offset(left, size.height - barHeight),
                    size = Size(barWidth, barHeight),
                    cornerRadius = CornerRadius(4.dp.toPx(), 4.dp.toPx()),
                )
            }
        }
        if (labels.isNotEmpty()) {
            ChartLabels(labels = labels, maxLabelCount = 8)
        }
    }
}

/**
 * 趋势折线（历次总分走势；`null` = 本次无分，断线）。
 * 与 [EcLineChart] 的区别：固定 0–100 归一化、带数据点圆点、标签最多显示 7 个。
 */
@Composable
fun EcTrendChart(
    points: List<Float?>,
    labels: List<String>,
    height: Dp = 120.dp,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(height),
        ) {
            drawGridLines(width = size.width, height = size.height)
            val count = points.size
            if (count == 0) return@Canvas
            val path = Path()
            var started = false
            points.forEachIndexed { index, value ->
                if (value == null) {
                    started = false
                    return@forEachIndexed
                }
                val x = xOf(index = index, count = count, width = size.width)
                val ratio = (value.coerceIn(0f, 100f) / 100f)
                val y = size.height - size.height * ratio
                if (started) {
                    path.lineTo(x, y)
                } else {
                    path.moveTo(x, y)
                    started = true
                }
            }
            drawPath(
                path = path,
                color = EcColor.primary,
                style = Stroke(
                    width = 2.dp.toPx(),
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                ),
            )
            points.forEachIndexed { index, value ->
                if (value == null) return@forEachIndexed
                val x = xOf(index = index, count = count, width = size.width)
                val ratio = (value.coerceIn(0f, 100f) / 100f)
                val y = size.height - size.height * ratio
                drawCircle(
                    color = EcColor.primary,
                    radius = 3.dp.toPx(),
                    center = Offset(x, y),
                )
            }
        }
        if (labels.isNotEmpty()) {
            ChartLabels(labels = labels, maxLabelCount = 7)
        }
    }
}

/** 0 / 50 / 100 三条淡参考线（不画网格）。 */
private fun DrawScope.drawGridLines(
    width: Float,
    height: Float,
) {
    val color = EcColor.border.copy(alpha = 0.6f)
    val stroke = 1.dp.toPx()
    listOf(0f, 0.5f, 1f).forEach { ratio ->
        val y = height - height * ratio
        drawLine(
            color = color,
            start = Offset(0f, y),
            end = Offset(width, y),
            strokeWidth = stroke,
        )
    }
}

private fun xOf(index: Int, count: Int, width: Float): Float =
    if (count <= 1) width / 2f else width * index / (count - 1)

/** X 轴标签行：等宽槽位居中；标签过密时按步长抽稀（最多 maxLabelCount 个）。 */
@Composable
private fun ChartLabels(labels: List<String>, maxLabelCount: Int) {
    if (labels.isEmpty()) return
    val step = if (maxLabelCount <= 0) 1 else ceil(labels.size.toFloat() / maxLabelCount).toInt().coerceAtLeast(1)
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        labels.forEachIndexed { index, label ->
            if (index % step == 0) {
                Text(
                    text = label,
                    modifier = Modifier.weight(1f),
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

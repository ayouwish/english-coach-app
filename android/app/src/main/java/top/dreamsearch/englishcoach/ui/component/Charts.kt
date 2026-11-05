package top.dreamsearch.englishcoach.ui.component

import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
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
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.sin

/**
 * 纯 Canvas 图表（不引第三方库；移植 hos `components/Charts.ets` 的
 * PitchChart / SparkLine / 柱状图能力，签名按 android/CONTRACT.md §4）。
 *
 * 约定：
 * - 语调曲线用 `List<Float?>`，`null` = 该点无 F0 → 断线不画（不伪造 0）；
 * - 不画网格，只画 0 / 50 / 100 三条淡参考线（docs/design-system.md §5.1）；
 * - 线条颜色由调用方传（通常 `EcColor.primary` / `EcScore.color`）。
 *
 * 能力雷达图（[EcRadarChart]）的数据来源是跟读评测结果 `ScoresDto`：
 * accuracy（准确）/ fluency（流利）/ completeness（完整）/ prosody（语调）/ pron（总分）。
 * 组件只接收 `labels + values`（primitives），**不 import 任何数据层 DTO**；null = 该项无分
 * （按 0 画但标签仍显示），儿童模式是否展示由调用方决定。
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

        for (seriesIndex in series.indices) {
            val points = series[seriesIndex]
            if (points.isEmpty()) continue
            val color = colors.getOrNull(seriesIndex) ?: EcColor.primary
            val path = Path()
            var started = false
            for (index in points.indices) {
                val value = points[index]
                if (value == null) {
                    started = false
                    continue
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
            for (index in values.indices) {
                val ratio = (values[index] / safeMax).coerceIn(0f, 1f)
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
            for (index in points.indices) {
                val value = points[index]
                if (value == null) {
                    started = false
                    continue
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
            for (index in points.indices) {
                val value = points[index] ?: continue
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
    val ratios = listOf(0f, 0.5f, 1f)
    for (ratio in ratios) {
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
    val step = if (maxLabelCount <= 0) {
        1
    } else {
        ceil(labels.size.toFloat() / maxLabelCount).toInt().coerceAtLeast(1)
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        for (index in labels.indices) {
            if (index % step == 0) {
                Text(
                    text = labels[index],
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

// ---------------------------------------------------------------------------
// 能力雷达图（跟读结果：准确 / 流利 / 完整 / 语调 / 总分）
// ---------------------------------------------------------------------------

/** 所有数值相同（含全 0 / 全 null）时的最小半径比例：避免多边形退化成一个点。 */
private const val RADAR_MIN_RADIUS_RATIO = 0.08f

/** 雷达图四周留给轴标签的边距。 */
private val RadarLabelPadding = 30.dp

/** 标签与最外圈网格之间的距离。 */
private val RadarLabelGap = 10.dp

/**
 * 能力雷达图（纯 Canvas，无第三方库）：跟读结果的能力多边形。
 *
 * 数据来源：评测结果 `ScoresDto` 的 accuracy / fluency / completeness / prosody / pron
 * （由调用方映射成 `labels + values`，本组件**不 import 任何数据层 DTO**）。
 *
 * 规则：
 * - 轴数按 `labels.size` 自适应 3–6 个（多于 6 只画前 6 个）；
 * - `values[i] == null` 视为 0（顶点落在圆心），但该轴标签仍然绘制；
 * - 所有值相同（含全部为 0 / 全为 null）时，最小半径取 8%，避免画成一个点；
 * - 网格 4 圈 + 轴线 + 环外标签（`EcFont.micro` / `EcColor.muted`）；
 *   多边形填充 `color.copy(alpha = 0.16f)` 并描边，便于和网格区分；
 * - 儿童模式不做特殊处理，是否展示由调用方决定。
 *
 * @param labels 轴标签（如 准确/流利/完整/语调/总分）
 * @param values 与 labels 一一对应的分值；null = 该项无分
 * @param size 正方形图表边长（标签已预留环外空间）
 * @param color 多边形主色（填充用 16% 透明度）
 * @param maxValue 归一化上限（默认 100 分制）
 */
@Composable
fun EcRadarChart(
    labels: List<String>,
    values: List<Double?>,
    modifier: Modifier = Modifier,
    size: Dp = 160.dp,
    color: Color = EcColor.primary,
    maxValue: Double = 100.0,
) {
    if (labels.isEmpty()) return
    val axisCount = labels.size.coerceIn(3, 6)
    val safeMax = maxValue.takeIf { it > 0.0 } ?: 100.0

    val ratios = ArrayList<Float>(axisCount)
    for (index in 0 until axisCount) {
        val raw = values.getOrNull(index)
        ratios.add(if (raw == null) 0f else (raw / safeMax).coerceIn(0.0, 1.0).toFloat())
    }
    val uniform = ratios.all { it == ratios[0] }
    val displayRatios = if (uniform) {
        ratios.map { it.coerceAtLeast(RADAR_MIN_RADIUS_RATIO) }
    } else {
        ratios
    }

    val density = LocalDensity.current
    val labelSizePx = with(density) { EcFont.micro.toPx() }
    val diameterPx = with(density) { size.toPx() }
    val labelPaddingPx = with(density) { RadarLabelPadding.toPx() }
    val labelGapPx = with(density) { RadarLabelGap.toPx() }
    val labelPaint = remember(labelSizePx) {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            textSize = labelSizePx
            color = EcColor.muted.toArgb()
        }
    }

    val description = buildString {
        append("能力雷达图")
        for (index in 0 until axisCount) {
            append(if (index == 0) "：" else "，")
            append(labels.getOrNull(index).orEmpty())
            append(" ")
            append(values.getOrNull(index)?.toInt()?.toString() ?: "—")
        }
    }

    Canvas(
        modifier = modifier
            .size(size)
            .semantics { contentDescription = description },
    ) {
        val canvasWidth = this.size.width
        val canvasHeight = this.size.height
        if (canvasWidth <= 0f || canvasHeight <= 0f) return@Canvas
        val center = Offset(canvasWidth / 2f, canvasHeight / 2f)
        val radius = (minOf(canvasWidth, canvasHeight) / 2f - labelPaddingPx)
            .coerceAtLeast(diameterPx * 0.15f)
        if (radius <= 0f) return@Canvas

        fun vertex(index: Int, vertexRadius: Float): Offset {
            val angle = (-90.0 + index * 360.0 / axisCount) * PI / 180.0
            return Offset(
                x = center.x + (cos(angle) * vertexRadius).toFloat(),
                y = center.y + (sin(angle) * vertexRadius).toFloat(),
            )
        }

        val gridColor = EcColor.border.copy(alpha = 0.8f)
        val gridStroke = 1.dp.toPx()

        // 4 圈网格（每圈都是与轴数相同的正多边形）
        for (ring in 1..4) {
            val ringRadius = radius * ring / 4f
            val ringPath = Path()
            for (index in 0 until axisCount) {
                val point = vertex(index, ringRadius)
                if (index == 0) {
                    ringPath.moveTo(point.x, point.y)
                } else {
                    ringPath.lineTo(point.x, point.y)
                }
            }
            ringPath.close()
            drawPath(path = ringPath, color = gridColor, style = Stroke(width = gridStroke))
        }

        // 轴线：圆心 → 最外圈顶点
        for (index in 0 until axisCount) {
            drawLine(
                color = gridColor,
                start = center,
                end = vertex(index, radius),
                strokeWidth = gridStroke,
            )
        }

        // 数值多边形：填充 16% 主色 + 2dp 描边 + 顶点圆点
        val valuePath = Path()
        for (index in 0 until axisCount) {
            val point = vertex(index, radius * displayRatios[index])
            if (index == 0) {
                valuePath.moveTo(point.x, point.y)
            } else {
                valuePath.lineTo(point.x, point.y)
            }
        }
        valuePath.close()
        drawPath(path = valuePath, color = color.copy(alpha = 0.16f))
        drawPath(
            path = valuePath,
            color = color,
            style = Stroke(width = 2.dp.toPx(), join = StrokeJoin.Round),
        )
        for (index in 0 until axisCount) {
            drawCircle(
                color = color,
                radius = 2.5.dp.toPx(),
                center = vertex(index, radius * displayRatios[index]),
            )
        }

        // 轴标签（环外；左右/上下做边界收拢，避免被图表边界裁掉）
        val nativeCanvas = drawContext.canvas.nativeCanvas
        for (index in 0 until axisCount) {
            val label = labels.getOrNull(index).orEmpty()
            if (label.isEmpty()) continue
            val anchor = vertex(index, radius + labelGapPx)
            val textWidth = labelPaint.measureText(label)
            val textX = anchor.x.coerceIn(textWidth / 2f, canvasWidth - textWidth / 2f)
            val baselineY = (anchor.y + labelSizePx * 0.35f)
                .coerceIn(labelSizePx, canvasHeight - 2.dp.toPx())
            nativeCanvas.drawText(label, textX, baselineY, labelPaint)
        }
    }
}

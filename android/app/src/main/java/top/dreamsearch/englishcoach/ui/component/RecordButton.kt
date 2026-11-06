package top.dreamsearch.englishcoach.ui.component

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.dreamsearch.englishcoach.ui.design.EcButtonSize
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 录音主按钮（移植 hos 的「🎤 开始说 / ⏹ 说完啦」大圆钮 + 录音脉冲动效；
 * 签名按 android/CONTRACT.md §4）。
 *
 * - 成人 72dp、儿童 88dp；点击开始/停止全局统一（不做长按）；
 * - 录音中：红色圆钮 + 「⏹」+ 1.4s 循环脉冲环（尊重 DesignSystem §7 的 1.4s 节奏）；
 * - `label` 非空时显示在圆钮下方（如「说完啦 0:03」由页面自己计时拼好）。
 */
@Composable
fun RecordButton(
    recording: Boolean,
    enabled: Boolean = true,
    isChild: Boolean = LocalIsChild.current,
    onClick: () -> Unit,
    label: String? = null,
) {
    val diameter = if (isChild) EcButtonSize.recordChild else EcButtonSize.record
    val baseColor = if (recording) EcColor.bad else EcColor.primary
    val transition = rememberInfiniteTransition(label = "record_pulse")
    val pulse by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "record_pulse_alpha",
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(contentAlignment = Alignment.Center) {
            if (recording) {
                Canvas(modifier = Modifier.size(diameter * 1.5f)) {
                    val baseRadius = diameter.toPx() / 2f
                    val alpha = ((1f - pulse) * 0.24f).coerceIn(0f, 1f)
                    drawCircle(
                        color = EcColor.bad.copy(alpha = alpha),
                        radius = baseRadius * (1f + pulse * 0.45f),
                    )
                }
            }
            Box(
                modifier = Modifier
                    .size(diameter)
                    .alpha(if (enabled) 1f else 0.45f)
                    .clip(CircleShape)
                    .background(baseColor)
                    .clickable(enabled = enabled, onClick = onClick),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = if (recording) "⏹" else "🎤",
                    fontSize = if (isChild) 32.sp else 28.sp,
                )
            }
        }
        if (!label.isNullOrEmpty()) {
            Text(
                text = label,
                fontSize = if (isChild) EcFont.childBody else EcFont.caption,
                color = EcColor.muted,
            )
        }
    }
}

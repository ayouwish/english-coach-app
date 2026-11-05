package top.dreamsearch.englishcoach.ui.page.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace

/**
 * 统计页（诊断 / 错音本 / 盲测）共用的小 UI 块。
 *
 * 为什么单独一个文件：三页都需要「白底卡片 + 轻阴影」与「纯 Compose 进度条」，
 * 组件库的 `EcCard` 没有边框参数，而诊断的 weak 卡需要 2dp 琥珀边框（hos 视觉一致）。
 * 只放无业务逻辑的布局原语，颜色/圆角/间距全部取 token。
 */

/** 统计页卡片：白底 + 20dp 圆角 + 2dp 阴影；`borderColor != null` 时加 2dp 边框。 */
@Composable
internal fun StatCard(
    borderColor: Color? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(EcRadius.lg)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(elevation = 2.dp, shape = shape, clip = false)
            .clip(shape)
            .background(EcColor.surface)
            .then(
                if (borderColor != null) Modifier.border(2.dp, borderColor, shape) else Modifier
            )
            .padding(EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        content = content,
    )
}

/** 纯 Compose 进度条（不用 Material 的实验性 progress lambda API）。 */
@Composable
internal fun StatsProgressBar(fraction: Float, height: Dp = 8.dp) {
    val shape = RoundedCornerShape(height / 2f)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(height)
            .clip(shape)
            .background(EcColor.surfaceAlt),
    ) {
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth(fraction.coerceIn(0f, 1f))
                .clip(shape)
                .background(EcColor.primary),
        )
    }
}

package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius

/**
 * 通用卡片（对应 hos `SectionCard` / `EcCard`，签名按 android/CONTRACT.md §4）。
 *
 * 白底 + 20dp 圆角 + 轻阴影 + 16dp 内边距；`onClick != null` 时整卡可点（列表项/快捷卡）。
 */
@Composable
fun EcCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(EcRadius.lg)
    var box = modifier
        .shadow(elevation = 2.dp, shape = shape, clip = false)
        .clip(shape)
        .background(EcColor.surface)
    if (onClick != null) {
        box = box.clickable(onClick = onClick)
    }
    Column(
        modifier = box
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

/**
 * 分区标题（对应 hos `SectionTitle`/页面里的「标题 + 查看全部」行）。
 *
 * `actionLabel` 非空时右侧出现文字动作（主色），点击区 ≥48dp。
 */
@Composable
fun EcSectionTitle(
    text: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 32.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = text,
            color = EcColor.ink,
            fontSize = EcFont.h3,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f),
        )
        if (actionLabel != null && actionLabel.isNotEmpty() && onAction != null) {
            Text(
                text = actionLabel,
                color = EcColor.primary,
                fontSize = EcFont.caption,
                fontWeight = FontWeight.Medium,
                modifier = Modifier
                    .clickable(onClick = onAction)
                    .padding(horizontal = 8.dp, vertical = 12.dp),
            )
        }
    }
}

package top.dreamsearch.englishcoach.ui.page.story

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace

/**
 * 故事模式四个页面共用的小块（只做展示，不含业务请求）。
 *
 * 说明：这些块在鸿蒙实现里是每页内联的 `Row + LoadingProgress` / 提示文字；
 * 抽到一处避免 4 个页面各写一遍，样式与 hos 一致（主色小 spinner + 一句话，不伪造进度）。
 */

/** 「进行中」行：小 spinner + 主色文案（识别中 / 生成中 / 保存中）。 */
@Composable
internal fun StoryBusyRow(text: String) {
    if (text.isEmpty()) return
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(16.dp),
            color = EcColor.primary,
            strokeWidth = 2.dp,
        )
        Text(text = text, fontSize = EcFont.caption, color = EcColor.primary)
    }
}

/** 绿色/灰色的一句轻提示（识别成功、保存成功、说明等）。 */
@Composable
internal fun StoryNotice(text: String, good: Boolean = true) {
    if (text.isEmpty()) return
    Text(
        text = text,
        modifier = Modifier.fillMaxWidth(),
        fontSize = EcFont.caption,
        color = if (good) EcColor.goodText else EcColor.muted,
    )
}

/** 页尾说明文字（灰色小字，居中）。 */
@Composable
internal fun StoryFooterNote(text: String) {
    Text(
        text = text,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = EcSpace.x2, bottom = EcSpace.x8),
        fontSize = EcFont.micro,
        color = EcColor.muted,
        textAlign = TextAlign.Center,
    )
}

/** 带标题的白卡片（故事各页的分区容器；内部仍是 EcCard 的白底/圆角/阴影）。 */
@Composable
internal fun StoryCard(title: String? = null, content: @Composable ColumnScope.() -> Unit) {
    EcCard {
        if (!title.isNullOrEmpty()) {
            Text(
                text = title,
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
        }
        content()
    }
}

/** 封面/插画的圆角占位块（无图或加载失败时用，避免破图）。 */
@Composable
internal fun StoryPlaceholderBox(
    modifier: Modifier,
    emoji: String,
    size: Dp? = null,
    circle: Boolean = false,
) {
    val bounded = if (size != null) modifier.size(size) else modifier
    val shape = if (circle) CircleShape else RoundedCornerShape(EcRadius.md)
    Box(
        modifier = bounded.clip(shape).background(EcColor.surfaceAlt),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = emoji, fontSize = EcFont.h3)
    }
}

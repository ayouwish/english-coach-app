package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import top.dreamsearch.englishcoach.ui.design.EcButtonSize
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius

/**
 * 统一按钮（移植 hos `components/EcButton.ets`，签名按 android/CONTRACT.md §4）。
 *
 * - 层级：PRIMARY / SECONDARY / GHOST / DANGER（对应 hos 的 Primary/Tonal/Ghost/Danger；
 *   CONTRACT 用 SECONDARY 命名，视觉照抄 hos 的 Tonal：primarySoft 底 + primary 字）。
 * - 状态：loading 时左侧 18dp spinner、禁用重复点击；disabled/loading 统一透明度 0.45。
 * - 尺寸：SM 36dp / MD 48dp / LG 56dp / CHILD 60dp（儿童可点区域 ≥60dp）。
 * - 一屏最多一个 PRIMARY 实心按钮（docs/design-system.md §4）。
 */
enum class EcButtonKind { PRIMARY, SECONDARY, GHOST, DANGER }

/** 按钮尺寸档位；CHILD = 儿童按钮（60dp / 19sp / 20dp 圆角）。 */
enum class EcButtonSizeKind { SM, MD, LG, CHILD }

@Composable
fun EcButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: EcButtonKind = EcButtonKind.PRIMARY,
    size: EcButtonSizeKind = EcButtonSizeKind.MD,
    enabled: Boolean = true,
    loading: Boolean = false,
    fullWidth: Boolean = false,
) {
    val interactive = enabled && !loading
    val height = when (size) {
        EcButtonSizeKind.SM -> EcButtonSize.sm
        EcButtonSizeKind.MD -> EcButtonSize.md
        EcButtonSizeKind.LG -> EcButtonSize.lg
        EcButtonSizeKind.CHILD -> EcButtonSize.child
    }
    val radius = if (size == EcButtonSizeKind.CHILD) EcRadius.lg else EcRadius.md
    val shape = RoundedCornerShape(radius)
    val textSize = when (size) {
        EcButtonSizeKind.SM -> EcFont.caption
        EcButtonSizeKind.MD, EcButtonSizeKind.LG -> EcFont.body
        EcButtonSizeKind.CHILD -> EcFont.childButton
    }

    val background: Color = when (kind) {
        EcButtonKind.PRIMARY -> EcColor.primary
        EcButtonKind.SECONDARY -> EcColor.primarySoft
        EcButtonKind.GHOST -> EcColor.surface
        EcButtonKind.DANGER -> EcColor.badBg
    }
    val foreground: Color = when (kind) {
        EcButtonKind.PRIMARY -> Color.White
        EcButtonKind.SECONDARY -> EcColor.primary
        EcButtonKind.GHOST -> EcColor.ink
        EcButtonKind.DANGER -> EcColor.badText
    }

    val widthModifier = if (fullWidth) Modifier.fillMaxWidth() else Modifier

    Box(
        modifier = modifier
            .then(widthModifier)
            .height(height)
            .clip(shape)
            .alpha(if (interactive) 1f else 0.45f)
            .background(background)
            .then(
                if (kind == EcButtonKind.GHOST) {
                    Modifier.border(1.dp, EcColor.border, shape)
                } else {
                    Modifier
                }
            )
            .clickable(enabled = interactive, onClick = onClick)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = foreground,
                    strokeWidth = 2.dp,
                )
            }
            Text(
                text = label,
                color = foreground,
                fontSize = textSize,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

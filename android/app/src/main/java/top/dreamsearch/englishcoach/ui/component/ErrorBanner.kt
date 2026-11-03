package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius

/**
 * 页内错误条（移植 hos `components/ErrorBanner.ets`）。
 *
 * 浅红底 + 标题 + 可执行动作，**不用全屏 Dialog**：错误要「可见 + 可操作」。
 * `error == null` 时什么都不渲染，页面可以直接常驻在布局里。
 * - 主动作文案取 `error.actionLabel`（空时若传了 `onRetry` 用「重试」）；
 * - `onDismiss != null` 时右上角出现「✕」。
 */
@Composable
fun ErrorBanner(
    error: UiError?,
    onRetry: (() -> Unit)? = null,
    onDismiss: (() -> Unit)? = null,
) {
    val e = error ?: return
    val actionLabel = e.actionLabel.ifEmpty { if (onRetry != null) "重试" else "" }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.badBg)
            .padding(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = "!",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Bold,
            color = EcColor.badText,
            modifier = Modifier.padding(end = 8.dp),
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (e.title.isNotEmpty()) {
                Text(
                    text = e.title,
                    fontSize = EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.badText,
                )
            }
            if (e.message.isNotEmpty()) {
                Text(
                    text = e.message,
                    fontSize = EcFont.caption,
                    color = EcColor.badText,
                )
            }
        }
        if (actionLabel.isNotEmpty() && onRetry != null) {
            Text(
                text = actionLabel,
                fontSize = EcFont.caption,
                fontWeight = FontWeight.Medium,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(onClick = onRetry)
                    .padding(start = 8.dp, top = 4.dp, bottom = 4.dp),
            )
        }
        if (onDismiss != null) {
            Text(
                text = "✕",
                fontSize = EcFont.caption,
                color = EcColor.muted,
                modifier = Modifier
                    .clickable(onClick = onDismiss)
                    .padding(start = 8.dp, top = 4.dp, bottom = 4.dp),
            )
        }
    }
}

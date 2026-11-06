package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont

/**
 * 空态（移植 hos `components/EmptyState.ets`）：图标 + 一句人话 + 一个可执行动作。
 *
 * 文案由页面传入（儿童版更口语）；`actionLabel` 为空时只显示文案。
 */
@Composable
fun EmptyState(
    icon: String = "🌱",
    message: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(text = icon, fontSize = 40.sp)
        Text(
            text = message,
            fontSize = EcFont.body,
            color = EcColor.muted,
            textAlign = TextAlign.Center,
        )
        if (!actionLabel.isNullOrEmpty() && onAction != null) {
            EcButton(
                label = actionLabel,
                onClick = onAction,
                kind = EcButtonKind.SECONDARY,
                modifier = Modifier.width(168.dp),
            )
        }
    }
}

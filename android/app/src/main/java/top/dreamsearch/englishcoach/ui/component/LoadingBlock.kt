package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
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
 * 加载态（移植 hos `components/LoadingBlock.ets`）：
 * 小 spinner + 一句进度文案；不用整屏白屏、不伪造百分比。
 */
@Composable
fun LoadingBlock(text: String = "加载中…", subText: String? = null) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CircularProgressIndicator(
            modifier = Modifier.size(28.dp),
            color = EcColor.primary,
            strokeWidth = 3.dp,
        )
        Text(
            text = text,
            fontSize = EcFont.body,
            color = EcColor.muted,
            textAlign = TextAlign.Center,
        )
        if (!subText.isNullOrEmpty()) {
            Text(
                text = subText,
                fontSize = EcFont.caption,
                color = EcColor.muted,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}

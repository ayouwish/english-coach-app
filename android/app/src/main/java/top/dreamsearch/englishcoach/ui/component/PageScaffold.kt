package top.dreamsearch.englishcoach.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont

/**
 * 二级页通用骨架（对应 hos `TopBar` + 页面滚动容器，签名按 android/CONTRACT.md §4）。
 *
 * - 自带「‹ 返回 + 标题 + 右侧动作」页头，处理状态栏 inset；
 * - 底部 `bottomBar`（可为空）自动加导航栏 inset；
 * - 内容最大宽度 960dp 居中（平板可拉伸，docs/design-system.md §8）；
 * - **内容区不会自动加内边距**：`content` 收到的 [PaddingValues] 由页面自己
 *   `Modifier.padding(paddingValues)` 使用（这样列表页可以在内边距里放 LazyColumn）。
 * - `scrollable = true` 时内容区自动纵向滚动；内容里有 LazyColumn 的页面请保持默认 `false`。
 */
@Composable
fun PageScaffold(
    title: String,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    scrollable: Boolean = false,
    content: @Composable ColumnScope.(PaddingValues) -> Unit,
) {
    Scaffold(
        containerColor = EcColor.bg,
        topBar = { EcTopBar(title = title, onBack = onBack, actions = actions) },
        bottomBar = {
            Column(modifier = Modifier.fillMaxWidth().navigationBarsPadding()) {
                bottomBar()
            }
        },
    ) { innerPadding ->
        Box(modifier = Modifier.fillMaxSize()) {
            val layout = Modifier
                .align(Alignment.TopCenter)
                .widthIn(max = 960.dp)
                .fillMaxSize()
            if (scrollable) {
                Column(
                    modifier = layout.verticalScroll(rememberScrollState()),
                ) { content(innerPadding) }
            } else {
                Column(modifier = layout) { content(innerPadding) }
            }
        }
    }
}

/** 页头：‹ 返回 + 标题 + 动作；返回热区 48dp。 */
@Composable
private fun EcTopBar(
    title: String,
    onBack: (() -> Unit)?,
    actions: @Composable RowScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(EcColor.bg)
            .statusBarsPadding(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .clickable(onClick = onBack),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "‹",
                        fontSize = 30.sp,
                        fontWeight = FontWeight.Medium,
                        color = EcColor.ink,
                    )
                }
            } else {
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text(
                text = title,
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 8.dp),
                fontSize = EcFont.h3,
                fontWeight = FontWeight.Bold,
                color = EcColor.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            actions()
        }
    }
}

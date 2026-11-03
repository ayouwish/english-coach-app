package top.dreamsearch.englishcoach.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.nav.TabNav
import top.dreamsearch.englishcoach.ui.nav.Tabs
import top.dreamsearch.englishcoach.ui.page.account.MeTab
import top.dreamsearch.englishcoach.ui.page.chat.ChatScenariosTab
import top.dreamsearch.englishcoach.ui.page.flow.FlowTab
import top.dreamsearch.englishcoach.ui.page.practice.PracticeTab
import top.dreamsearch.englishcoach.ui.page.story.StoryHomeTab

/**
 * 已登录首页：5 个 Tab（跟读 / 连读 / 对话 / 故事 / 我的，对应 hos `HomeTabs.ets`）。
 *
 * - 顶部 `voice.reachable == false` 时显示琥珀降级提示条（README §2.4 / screens-matrix §8）；
 * - [TabNav] 负责跨页切 Tab（如故事详情「去连读」）；
 * - 二级页面由 [AppNavHost] push，不在本组件内。
 */
@Composable
fun HomeScreen(onNavigate: (String) -> Unit) {
    var currentTab by remember { mutableIntStateOf(Tabs.PRACTICE) }
    var voiceDegraded by remember { mutableStateOf(false) }

    // 启动时探一次 /health：voice 不可用 → 顶部提示"录音先保存，稍后可重试评测"
    LaunchedEffect(Unit) {
        runCatching { AppGraph.container.practice.health() }
            .onSuccess { health -> voiceDegraded = health.voice?.reachable == false }
    }

    // 跨页切 Tab
    val pendingTab by TabNav.pending.collectAsStateWithLifecycle()
    LaunchedEffect(pendingTab) {
        val target = pendingTab
        if (target != null && target in 0..4) {
            currentTab = target
            TabNav.consume()
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(EcColor.bg).safeDrawingPadding()) {
        if (voiceDegraded) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(EcColor.warnBg)
                    .padding(horizontal = EcSpace.x4, vertical = EcSpace.x2),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text("⚠️", fontSize = EcFont.caption)
                Text(
                    text = "语音服务暂时不可用：录音会先保存，稍后可在结果页重试评测",
                    fontSize = EcFont.micro,
                    color = EcColor.warnText,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            when (currentTab) {
                Tabs.PRACTICE -> PracticeTab()
                Tabs.FLOW -> FlowTab()
                Tabs.CHAT -> ChatScenariosTab()
                Tabs.STORY -> StoryHomeTab()
                else -> MeTab(onNavigate = onNavigate)
            }
        }

        HomeTabBar(current = currentTab, onSelect = { currentTab = it })
    }
}

private val tabLabels = listOf("跟读", "连读", "对话", "故事", "我的")
private val tabIcons = listOf("🎤", "🔗", "💬", "📖", "🙂")

@Composable
private fun HomeTabBar(current: Int, onSelect: (Int) -> Unit) {
    Surface(color = EcColor.surface, shadowElevation = 8.dp) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .height(56.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            tabLabels.forEachIndexed { index, label ->
                val selected = index == current
                val interactionSource = remember { MutableInteractionSource() }
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxSize()
                        .clickable(
                            interactionSource = interactionSource,
                            indication = null,
                        ) { onSelect(index) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        text = tabIcons[index],
                        fontSize = if (selected) 22.sp else 20.sp,
                    )
                    Text(
                        text = label,
                        fontSize = EcFont.micro,
                        fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal,
                        color = if (selected) EcColor.primary else EcColor.muted,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

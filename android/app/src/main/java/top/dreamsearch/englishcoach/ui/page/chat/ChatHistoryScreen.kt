package top.dreamsearch.englishcoach.ui.page.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.dto.ChatSessionSummaryDto
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 对话历史列表（`Routes.CHAT_HISTORY`，对应 hos `pages/ChatHistoryPage.ets`）。
 *
 * 数据来源：`GET /api/chat/sessions?limit=20`（[ChatHistoryViewModel]）。
 * 点击某条 → `onOpenDetail(id)`（父级 AppNavHost 写 `NavParams.chatDetailId` 再导航）。
 *
 * 说明：列表接口没有 summary / 平均发音字段，所以只显示
 * 「时间 · 场景中文名 · N 轮 · 状态」，不编造分数。
 */
@Composable
fun ChatHistoryScreen(
    onBack: () -> Unit,
    onOpenDetail: (String) -> Unit,
) {
    val vm: ChatHistoryViewModel = viewModel(
        factory = remember { vmFactory { ChatHistoryViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current

    PageScaffold(title = "对话历史", onBack = onBack) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(
                start = EcSpace.x4,
                end = EcSpace.x4,
                top = EcSpace.x2,
                bottom = EcSpace.x4,
            ),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            val error = state.error
            when {
                state.loading -> item(key = "loading") { LoadingBlock(text = "正在取历史记录…") }
                error != null -> item(key = "error") {
                    ErrorBanner(error = error, onRetry = { vm.load() })
                }
                state.items.isEmpty() -> item(key = "empty") {
                    EmptyState(
                        icon = "🕘",
                        message = "还没有对话记录，去「对话」选个场景开始吧",
                        actionLabel = "去对话",
                        onAction = onBack,
                    )
                }
                else -> {
                    item(key = "count") {
                        Text(
                            text = "最近 ${state.items.size} 次对话",
                            fontSize = EcFont.caption,
                            color = EcColor.muted,
                            modifier = Modifier.padding(top = EcSpace.x2, bottom = EcSpace.x1),
                        )
                    }
                    items(state.items, key = { it.id }) { item ->
                        HistoryRow(
                            item = item,
                            isChild = isChild,
                            onClick = { onOpenDetail(item.id) },
                        )
                    }
                    item(key = "footer") {
                        Text(
                            text = "历史记录按时间顺序保存，家长可回看每次对话的校正与评价。",
                            fontSize = EcFont.micro,
                            color = EcColor.muted,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = EcSpace.x3, bottom = EcSpace.x6),
                        )
                    }
                }
            }
        }
    }
}

/** 一条历史记录：💬 + 场景名 + 时间 / 轮数 / 状态 + ›。 */
@Composable
private fun HistoryRow(
    item: ChatSessionSummaryDto,
    isChild: Boolean,
    onClick: () -> Unit,
) {
    EcCard(onClick = onClick) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(EcRadius.md))
                    .background(EcColor.surfaceAlt),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = "💬", fontSize = 22.sp)
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = item.scenarioTitleZh.ifEmpty { item.scenarioTitle }.ifEmpty { "对话" },
                    fontSize = if (isChild) EcFont.childBody else EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                ) {
                    Text(
                        text = ChatFormat.timeText(item.startedAt),
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                    Text(
                        text = "${item.turnCount} 轮",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                    EcPill(text = statusText(item, isChild), tone = PillTone.NEUTRAL)
                }
                val last = item.lastMessage
                if (!last.isNullOrEmpty()) {
                    Text(
                        text = last,
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Text(text = "›", fontSize = 24.sp, color = EcColor.muted)
        }
    }
}

/** 状态文案：儿童更口语（对应 hos `statusText`）。 */
private fun statusText(item: ChatSessionSummaryDto, isChild: Boolean): String {
    val ended = !item.endedAt.isNullOrEmpty()
    if (isChild) return if (ended) "聊完了" else "还在聊"
    return if (ended) "已结束" else "还在进行"
}

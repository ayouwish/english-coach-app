package top.dreamsearch.englishcoach.ui.page.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 对话详情（历史，`Routes.CHAT_DETAIL`，对应 hos `pages/ChatDetailPage.ets`）。
 *
 * 数据来源（[ChatSessionViewModel] 的 HISTORY 模式）：
 * `GET /chat/sessions/:id`（meta，**无 pron**）+ `GET /chat/sessions/:id/messages`（含 pron/correction）；
 * 整段回放走与会话页相同的 `audio/status → audio` 流程（202 = 构建中，轮询）。
 *
 * 会话 id 由导航层写 `NavParams.chatDetailId`，VM init 读取并清空。
 */
@Composable
fun ChatDetailScreen(onBack: () -> Unit) {
    val vm: ChatSessionViewModel = viewModel(
        factory = remember {
            vmFactory { ChatSessionViewModel(AppGraph.container, ChatSessionViewModel.Mode.HISTORY) }
        },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    var expandedMsgId by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    DisposableEffect(Unit) {
        onDispose { vm.onLeave() }
    }

    PageScaffold(title = "对话详情", onBack = onBack) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            state = listState,
            contentPadding = PaddingValues(
                start = EcSpace.x4,
                end = EcSpace.x4,
                top = EcSpace.x2,
                bottom = EcSpace.x4,
            ),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            item(key = "header") { DetailHeaderCard(state = state, isChild = isChild) }

            if (state.loading) {
                item(key = "loading") { LoadingBlock(text = "正在取对话记录…") }
            }
            val loadError = state.loadError
            if (loadError != null) {
                item(key = "error") {
                    ErrorBanner(
                        error = loadError,
                        onRetry = {
                            if (state.sessionId.isEmpty()) onBack() else vm.reloadThread()
                        },
                    )
                }
            }
            if (state.replayStatus != ChatReplayStatus.IDLE) {
                item(key = "replay") {
                    ChatReplayCard(
                        status = state.replayStatus,
                        errorText = state.replayError,
                        isChild = isChild,
                        playing = state.replayPlaying,
                        durationText = ChatFormat.durationText(state.replayDurationMs),
                        onPlayTap = { vm.playReplay() },
                        onRegenerateTap = { vm.regenerateReplay() },
                    )
                }
            }

            items(state.messages, key = { it.id }) { msg ->
                ChatBubble(
                    msg = msg,
                    isChild = isChild,
                    wordsExpanded = expandedMsgId == msg.id,
                    onPlayTap = { vm.playMessage(msg.id) },
                    onWordsTap = { expandedMsgId = if (expandedMsgId == msg.id) "" else msg.id },
                )
            }

            if (!state.loading && state.messages.isEmpty() && state.loadError == null) {
                item(key = "empty") {
                    EmptyState(icon = "💬", message = "这次对话没有留下消息记录")
                }
            }

            item(key = "footer") {
                Text(
                    text = "历史记录按时间顺序保存，家长可回看每次对话的校正与评价。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(top = EcSpace.x2, bottom = EcSpace.x6),
                )
            }
        }
    }
}

/** 详情头部：标题 / 英文标题 / 时间 · 轮数 · 状态 / 口径说明。 */
@Composable
private fun DetailHeaderCard(state: ChatSessionUiState, isChild: Boolean) {
    EcCard {
        Row(
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = state.titleZh.ifEmpty { state.titleEn }.ifEmpty { "这次对话" },
                    fontSize = EcFont.h3,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                if (state.titleEn.isNotEmpty() && state.titleZh.isNotEmpty()) {
                    Text(text = state.titleEn, fontSize = EcFont.caption, color = EcColor.muted)
                }
                Text(
                    text = metaText(state),
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            EcPill(
                text = if (isChild) "儿童的对话" else "完整记录",
                tone = PillTone.INFO,
            )
        }
        // 历史接口不返回 summary（后端缺口）：成人明确说明，不编造分数
        if (isChild) {
            Text(
                text = "这次聊得很棒，慢慢看都可以 🌟",
                fontSize = EcFont.caption,
                color = EcColor.goodText,
            )
        } else {
            Text(
                text = "发音评价只在「结束对话」当时展示；历史记录保留完整对话、每条校正与录音。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
    }
}

private fun metaText(state: ChatSessionUiState): String {
    val parts = ArrayList<String>(3)
    val started = ChatFormat.timeText(state.startedAt)
    if (started.isNotEmpty()) parts.add(started)
    parts.add("${state.turnCount} 轮")
    parts.add(if (state.endedAt.isNotEmpty() || state.ended) "已结束" else "还在进行")
    return parts.joinToString(" · ")
}

package top.dreamsearch.englishcoach.ui.page.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.audio.rememberMicPermission
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RecordButton
import top.dreamsearch.englishcoach.ui.component.WordText
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 对话会话页（`Routes.CHAT_SESSION`，对应 hos `pages/ChatSessionPage.ets`）。
 *
 * 语音唯一输入，一轮严格按序：
 * 录音（0.6–60s）→ ASR → **显示识别文本，用户点「重说 / 发送」** → turn →
 * 文本先渲染 → TTS 播放回复（失败不影响文字）→ 后台轮询补 pron 小分。
 *
 * 附加：
 * - 开场白立即显示、可「再听」；用户气泡可回放；建议回复 chips **只朗读不发送**；
 * - 一轮未完成禁用录音、不允许并发 turn；
 * - 结束时 `POST /:id/end` → 结束卡（换个场景 / 再聊一次）+ 整段回放；
 * - `degraded_llm` / `degraded` / `unsafe_filtered` / 限额（429、全局 exceeded）都有明确提示。
 *
 * 页面不直接发请求：全部经 [ChatSessionViewModel]；录音/播放全部走 `AudioController`。
 */
@Composable
fun ChatSessionScreen(onBack: () -> Unit) {
    val vm: ChatSessionViewModel = viewModel(
        factory = remember {
            vmFactory { ChatSessionViewModel(AppGraph.container, ChatSessionViewModel.Mode.LIVE) }
        },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    val mic = rememberMicPermission()
    var micHint by remember { mutableStateOf(false) }
    var confirmEnd by remember { mutableStateOf(false) }
    var expandedMsgId by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    DisposableEffect(Unit) {
        onDispose { vm.onLeave() }
    }
    LaunchedEffect(mic.granted) {
        if (mic.granted) micHint = false
    }

    // 新消息 / 结束态出现整段回放时滚到底
    val replayVisible = state.ended && state.replayStatus != ChatReplayStatus.IDLE
    LaunchedEffect(state.messages.size, replayVisible) {
        val offset = if (replayVisible) 1 else 0
        val target = offset + state.messages.lastIndex
        if (target >= 0) listState.animateScrollToItem(target)
    }

    val error = state.error
    val onErrorRetry: () -> Unit = {
        if (error?.code == ApiErrorCode.MIC_DENIED) {
            micHint = true
            mic.request()
        } else {
            vm.retryError()
        }
    }
    val onRecord: () -> Unit = {
        when {
            state.recording -> vm.stopAndRecognize()
            !mic.granted -> {
                micHint = true
                mic.request()
            }
            else -> vm.startRecording()
        }
    }

    val title = state.titleZh.ifEmpty { state.titleEn }.ifEmpty { "对话中" }

    PageScaffold(
        title = title,
        onBack = onBack,
        actions = {
            if (!state.ended && !state.readOnly) {
                Text(
                    text = if (state.ending) "结束中…" else "结束",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(enabled = !state.ending) { confirmEnd = true }
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x2),
                )
            }
        },
        bottomBar = {
            when {
                state.readOnly -> Unit
                state.ended -> EndPanel(
                    isChild = isChild,
                    error = state.error,
                    onRetry = { vm.retryError() },
                    onBack = onBack,
                    onRestart = { vm.restartSession() },
                )
                else -> RecordPanel(
                    state = state,
                    isChild = isChild,
                    micGranted = mic.granted,
                    micHint = micHint,
                    confirmEnd = confirmEnd,
                    onRecordTap = onRecord,
                    onCancelRecording = { vm.cancelRecording() },
                    onReRecord = { vm.reRecord() },
                    onSend = { vm.confirmSend() },
                    onSuggestionTap = { vm.speakSuggestion(it) },
                    onRequestMic = {
                        micHint = true
                        mic.request()
                    },
                    onRetryError = onErrorRetry,
                    onEndClick = { confirmEnd = true },
                    onConfirmEnd = {
                        confirmEnd = false
                        vm.endSession()
                    },
                    onCancelEnd = { confirmEnd = false },
                )
            }
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            // 头部：英文标题 / 场景说明 / 轮次
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = EcSpace.x4),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
            ) {
                if (state.titleEn.isNotEmpty() && state.titleEn != title) {
                    Text(text = state.titleEn, fontSize = EcFont.micro, color = EcColor.muted)
                }
                if (state.settingZh.isNotEmpty()) {
                    Text(text = state.settingZh, fontSize = EcFont.caption, color = EcColor.muted, maxLines = 2)
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                ) {
                    EcPill(text = "第 ${state.turnCount + 1} 轮", tone = PillTone.INFO)
                    if (state.level.isNotEmpty()) {
                        EcPill(text = state.level, tone = PillTone.NEUTRAL)
                    }
                    Text(
                        text = if (state.readOnly) "历史记录" else "不限轮数，想聊多久都可以",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
            }

            // 业务提示：限额 / 降级 / 语音失败
            val noticeModifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = EcSpace.x4, vertical = EcSpace.x1)
            if (state.quotaExceeded) {
                Column(noticeModifier) {
                    ChatWarnLine(
                        text = state.quotaText.ifEmpty {
                            if (isChild) "今天已经练得很棒啦，明天再来 🌙" else "今天的练习时间到了，明天再来"
                        },
                        icon = "🌙",
                    )
                }
            }
            if (state.degradedLlm) {
                Column(noticeModifier) {
                    ChatWarnLine(text = "当前回复来自内置话术（还没接入大模型），先练着，不影响记录。")
                }
            }
            if (state.degraded) {
                Column(noticeModifier) {
                    ChatWarnLine(text = "对话服务暂时不可用，已切换到本地固定话术（数据仍然完整保存）。")
                }
            }
            if (state.sessionExceeded && !state.quotaExceeded) {
                Column(noticeModifier) {
                    ChatWarnLine(
                        text = "今天的练习时长已达上限，还剩 ${state.remainingMinutes} 分钟，明天再来",
                        icon = "🌙",
                    )
                }
            }
            if (state.voiceNotice.isNotEmpty()) {
                Column(noticeModifier) {
                    ChatInfoLine(text = state.voiceNotice)
                }
            }
            val loadError = state.loadError
            if (loadError != null) {
                Column(noticeModifier) {
                    ErrorBanner(
                        error = loadError,
                        onRetry = {
                            if (state.sessionId.isEmpty()) onBack() else vm.reloadThread()
                        },
                    )
                }
            }
            if (state.loading) {
                LoadingBlock(text = "正在打开对话…")
            }

            LazyColumn(
                modifier = Modifier.fillMaxWidth().weight(1f),
                state = listState,
                contentPadding = PaddingValues(
                    start = EcSpace.x4,
                    end = EcSpace.x4,
                    top = EcSpace.x2,
                    bottom = EcSpace.x4,
                ),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
            ) {
                if (replayVisible) {
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
                        EmptyState(
                            icon = "💬",
                            message = if (isChild) "还没开始聊天，点下面的大按钮说第一句话吧" else "对话还没开始，点下面的录音按钮开始说吧",
                        )
                    }
                }
                item(key = "footer") {
                    Text(
                        text = if (state.ended) {
                            "这段对话已经结束啦，回放和文字记录都会保存下来。"
                        } else {
                            "点场景卡只是开始；对话里只有语音输入，没有文字输入框。"
                        },
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(vertical = EcSpace.x2),
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 录音 / 一轮底部面板
// ---------------------------------------------------------------------------

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RecordPanel(
    state: ChatSessionUiState,
    isChild: Boolean,
    micGranted: Boolean,
    micHint: Boolean,
    confirmEnd: Boolean,
    onRecordTap: () -> Unit,
    onCancelRecording: () -> Unit,
    onReRecord: () -> Unit,
    onSend: () -> Unit,
    onSuggestionTap: (String) -> Unit,
    onRequestMic: () -> Unit,
    onRetryError: () -> Unit,
    onEndClick: () -> Unit,
    onConfirmEnd: () -> Unit,
    onCancelEnd: () -> Unit,
) {
    val error = state.error
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 400.dp)
            .verticalScroll(rememberScrollState())
            .background(EcColor.surface)
            .padding(horizontal = EcSpace.x4, vertical = EcSpace.x2),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        if (error != null) {
            ErrorBanner(error = error, onRetry = onRetryError)
        }

        // 建议回复：点击只朗读提示句，不发送（产品硬约束）
        if (state.suggestedReplies.isNotEmpty() && !state.busy && !state.recording && !state.quotaExceeded) {
            Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
                Text(
                    text = "可以这样回（点一下只朗读，不会发送）：",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                    verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
                ) {
                    state.suggestedReplies.forEach { reply ->
                        Text(
                            text = reply,
                            fontSize = if (isChild) EcFont.childBody else EcFont.caption,
                            color = EcColor.primary,
                            maxLines = 2,
                            modifier = Modifier
                                .clip(RoundedCornerShape(EcRadius.pill))
                                .background(EcColor.primarySoft)
                                .clickable { onSuggestionTap(reply) }
                                .padding(horizontal = EcSpace.x3, vertical = EcSpace.x1),
                        )
                    }
                }
            }
        }

        if (state.hintText.isNotEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(EcRadius.md))
                    .background(EcColor.primarySoft)
                    .padding(EcSpace.x3),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(text = "照着这句说：", fontSize = EcFont.micro, color = EcColor.muted)
                Text(
                    text = state.hintText,
                    fontSize = if (isChild) EcFont.childBody else EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                )
                Text(
                    text = "提示句只给你参考，发出去的是你说的录音。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }

        if (confirmEnd) {
            EndConfirmCard(
                isChild = isChild,
                ending = state.ending,
                onConfirm = onConfirmEnd,
                onCancel = onCancelEnd,
            )
        }
        // ASR 识别结果：不自动发送，用户点「重说 / 发送」
        if (state.pendingText.isNotEmpty()) {
            AsrConfirmCard(
                text = state.pendingText,
                isChild = isChild,
                busy = state.busy,
                onReRecord = onReRecord,
                onSend = onSend,
            )
        } else {
            if (state.busy) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = EcColor.primary,
                        strokeWidth = 2.dp,
                    )
                    Text(
                        text = state.progressText.ifEmpty { "识别 / 回复中…请稍候 ⏳" },
                        fontSize = EcFont.caption,
                        color = EcColor.primary,
                    )
                }
            }
            RecordButton(
                recording = state.recording,
                enabled = state.canRecord,
                isChild = isChild,
                onClick = onRecordTap,
                label = when {
                    state.recording -> "说完啦 ${state.elapsedMs / 1000}s"
                    state.preparing -> "正在打开麦克风…"
                    isChild -> "点一下，开始说（慢慢来）"
                    else -> "点一下开始说"
                },
            )
            if (state.recording) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                ) {
                    Text(
                        text = "正在听你说…说完点上面按钮",
                        fontSize = EcFont.micro,
                        color = EcColor.warnText,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = "✖️ 不要了",
                        fontSize = EcFont.caption,
                        color = EcColor.badText,
                        modifier = Modifier
                            .clickable { onCancelRecording() }
                            .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
                    )
                }
            }
        }

        if (!confirmEnd && !state.ended) {
            Text(
                text = if (state.ending) "结束中…" else "🏁 结束对话",
                fontSize = EcFont.caption,
                color = EcColor.badText,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = !state.ending) { onEndClick() }
                    .padding(vertical = EcSpace.x1),
            )
        }

        if (!micGranted || micHint) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text(
                    text = "🎤 要听到你的声音，需要先打开麦克风",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "去开启",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable { onRequestMic() }
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
                )
            }
        }

        Text(
            text = "本页需要麦克风才能对话（没有输入框）",
            fontSize = EcFont.micro,
            color = EcColor.muted,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** 识别结果确认卡：显示 ASR 文本 + 「重说 / 发送」（不自动发送）。 */
@Composable
private fun AsrConfirmCard(
    text: String,
    isChild: Boolean,
    busy: Boolean,
    onReRecord: () -> Unit,
    onSend: () -> Unit,
) {
    val buttonSize = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.surfaceAlt)
            .padding(EcSpace.x3),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = if (isChild) "我听到你说：" else "识别结果（确认后再发送）：",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
        WordText(text = text, isChild = isChild, showIpa = false)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = "🔁 重说",
                onClick = onReRecord,
                kind = EcButtonKind.SECONDARY,
                size = buttonSize,
                enabled = !busy,
                modifier = Modifier.weight(1f),
            )
            EcButton(
                label = "✅ 发送",
                onClick = onSend,
                kind = EcButtonKind.PRIMARY,
                size = buttonSize,
                enabled = !busy,
                loading = busy,
                modifier = Modifier.weight(1f),
            )
        }
        Text(
            text = "识别错了就点「重说」，确认没问题再发送。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

/** 结束确认卡。 */
@Composable
private fun EndConfirmCard(
    isChild: Boolean,
    ending: Boolean,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.surfaceAlt)
            .padding(EcSpace.x3),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = "结束这次对话？",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        Text(
            text = "结束后会生成整段回放，想聊多久都可以，随时可以结束。",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = "🏁 结束对话",
                onClick = onConfirm,
                kind = EcButtonKind.DANGER,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                enabled = !ending,
                loading = ending,
                modifier = Modifier.weight(1f),
            )
            EcButton(
                label = "再聊会儿",
                onClick = onCancel,
                kind = EcButtonKind.SECONDARY,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                enabled = !ending,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

/** 结束卡：「今天聊得很棒」+ 换个场景 / 再聊一次；「再聊一次」失败时同卡展示错误 + 重试。 */
@Composable
private fun EndPanel(
    isChild: Boolean,
    error: UiError?,
    onRetry: () -> Unit,
    onBack: () -> Unit,
    onRestart: () -> Unit,
) {
    val size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(EcColor.surface)
            .padding(horizontal = EcSpace.x4, vertical = EcSpace.x2),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        if (error != null) {
            ErrorBanner(error = error, onRetry = onRetry)
        }
        Text(text = "🌟", fontSize = 32.sp)
        Text(
            text = "今天聊得很棒！",
            fontSize = if (isChild) EcFont.childH1 else EcFont.h3,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Text(
            text = if (isChild) "我们刚才的对话都保存下来啦，随时可以再听一遍。" else "整段回放和文字记录都已经保存下来。",
            fontSize = EcFont.caption,
            color = EcColor.muted,
            textAlign = TextAlign.Center,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = "换个场景",
                onClick = onBack,
                kind = EcButtonKind.SECONDARY,
                size = size,
                modifier = Modifier.weight(1f),
            )
            EcButton(
                label = "再聊一次",
                onClick = onRestart,
                kind = EcButtonKind.PRIMARY,
                size = size,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

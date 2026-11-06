package top.dreamsearch.englishcoach.ui.page.story

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.audio.rememberMicPermission
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RecordButton
import top.dreamsearch.englishcoach.ui.component.WordText
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 故事复述（二级页，`Routes.STORY_REVIEW`，签名见 CONTRACT §5）。
 *
 * 对应 hos：`hos/entry/src/main/ets/pages/StoryReviewPage.ets`（布局/文案照抄）。
 * id 来自 `NavParams.storyMaterialId`（VM init 里读取并清空）。
 *
 * 录音（0.6–60s）→ ASR(en-US) → `POST /story/retell`；展示覆盖度/关键点/中文反馈，
 * **绝不显示发音分**。儿童只显示「讲到了 / 还可以讲」，不显示百分比；失败保留录音可重试。
 */
@Composable
fun StoryReviewScreen(onBack: () -> Unit) {
    val vm: StoryReviewViewModel = viewModel(
        factory = remember { vmFactory { StoryReviewViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    val mic = rememberMicPermission()

    val onStartRecording: () -> Unit = {
        if (!mic.granted) mic.request() else vm.startRecording()
    }

    PageScaffold(title = "讲给我听", onBack = onBack, scrollable = true) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxWidth()
                .padding(horizontal = EcSpace.x4, vertical = EcSpace.x3),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            when {
                state.loading -> {
                    LoadingBlock(text = "正在打开故事…")
                }

                state.loadError != null -> {
                    ErrorBanner(error = state.loadError, onRetry = { vm.retryLoad() })
                }

                else -> {
                    ReviewHeaderCard(state, isChild)
                    ReviewInputCard(
                        state = state,
                        isChild = isChild,
                        vm = vm,
                        onStartRecording = onStartRecording,
                        onRequestMic = { mic.request() },
                    )
                    if (state.hasResult) {
                        ReviewResultCard(
                            state = state,
                            isChild = isChild,
                            onAgain = {
                                vm.setTextMode(false)
                                onStartRecording()
                            },
                            onBack = onBack,
                        )
                    }
                    ReviewSentenceCard(state)
                    StoryFooterNote("复述只看「讲清楚没有」，不计发音分。")
                }
            }
        }
    }
}

// ------------------------------------------------------------------ 页头

@Composable
private fun ReviewHeaderCard(state: StoryReviewUiState, isChild: Boolean) {
    StoryCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = "🎤 讲给我听",
                modifier = Modifier.weight(1f),
                fontSize = if (isChild) EcFont.childH1 else EcFont.h2,
                fontWeight = FontWeight.Bold,
                color = EcColor.ink,
            )
            EcPill(text = state.level, tone = PillTone.INFO)
        }
        Text(
            text = state.storyTitle,
            modifier = Modifier.fillMaxWidth(),
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        )
        Text(
            text = "不看屏幕，用 2–3 句话把故事讲一遍 🙂",
            modifier = Modifier.fillMaxWidth(),
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
    }
}

// ------------------------------------------------------------------ 输入

@Composable
private fun ReviewInputCard(
    state: StoryReviewUiState,
    isChild: Boolean,
    vm: StoryReviewViewModel,
    onStartRecording: () -> Unit,
    onRequestMic: () -> Unit,
) {
    StoryCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcChip(
                label = "🎤 说英文",
                selected = !state.textMode,
                onClick = { vm.setTextMode(false) },
            )
            EcChip(
                label = "✍️ 打字复述",
                selected = state.textMode,
                onClick = { vm.setTextMode(true) },
            )
        }

        if (state.exceeded) {
            EcInlineNotice(text = "今天的练习时长已达上限，明天再来 🌙", tone = PillTone.WARN)
        }

        if (!state.textMode) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                RecordButton(
                    recording = state.recording,
                    enabled = !state.busy && !state.exceeded,
                    isChild = isChild,
                    onClick = {
                        if (state.recording) vm.stopRecordingAndSubmit() else onStartRecording()
                    },
                    label = recordButtonLabel(state, isChild),
                )
                if (state.recording) {
                    EcButton(
                        label = "✖️ 不要了",
                        onClick = { vm.cancelRecording() },
                        kind = EcButtonKind.GHOST,
                        size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                    )
                }
            }
            if (state.transcript.isNotEmpty()) {
                Text(
                    text = "我听到的是：${state.transcript}",
                    modifier = Modifier.fillMaxWidth(),
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
            }
            if (state.canPlayRecording) {
                EcButton(
                    label = if (state.recordingPlaying) "播放中…" else "🔁 回放我刚才说的",
                    onClick = { vm.playRecording() },
                    kind = EcButtonKind.GHOST,
                    fullWidth = true,
                )
            }
        } else {
            EcTextField(
                value = state.typedText,
                onValueChange = vm::setTypedText,
                label = "用英文写 2–3 句复述",
                placeholder = "I built a tower with Ming. Hua knocked it down. I was angry.",
                singleLine = false,
                modifier = Modifier.height(120.dp),
            )
            EcButton(
                label = if (state.busy) "提交中…" else "提交复述",
                onClick = { vm.submitTyped() },
                loading = state.busy,
                enabled = state.typedText.trim().isNotEmpty() && !state.exceeded,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                fullWidth = true,
            )
        }

        StoryBusyRow(state.busyText)
        ErrorBanner(
            error = state.error,
            onRetry = {
                if (state.error?.code == ApiErrorCode.MIC_DENIED) onRequestMic() else vm.retry()
            },
            onDismiss = vm::clearError,
        )
    }
}

// ------------------------------------------------------------------ 结果

@Composable
private fun ReviewResultCard(
    state: StoryReviewUiState,
    isChild: Boolean,
    onAgain: () -> Unit,
    onBack: () -> Unit,
) {
    StoryCard {
        if (isChild) {
            Text(
                text = "🌟 你真棒！讲到了 ${state.coveredPoints.size} 个关键点",
                modifier = Modifier.fillMaxWidth(),
                fontSize = EcFont.h3,
                fontWeight = FontWeight.Bold,
                color = EcColor.goodText,
            )
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text(
                    text = if (state.coveragePercent < 0) "覆盖度 —" else "覆盖度 ${state.coveragePercent}%",
                    fontSize = EcFont.h3,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.primary,
                )
                Text(
                    text = "讲到了 ${state.coveredPoints.size} 个关键点",
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
            }
        }

        if (state.coveredPoints.isNotEmpty()) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
            ) {
                Text(text = "讲到了：", fontSize = EcFont.caption, color = EcColor.muted)
                state.coveredPoints.forEach { point ->
                    Text(text = "· $point", fontSize = EcFont.caption, color = EcColor.ink)
                }
            }
        }
        if (state.missingPoints.isNotEmpty()) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
            ) {
                Text(text = "下一次可以试试：", fontSize = EcFont.caption, color = EcColor.muted)
                state.missingPoints.forEach { point ->
                    Text(text = "· 把「$point」也讲进去", fontSize = EcFont.caption, color = EcColor.ink)
                }
            }
        }
        if (state.feedbackZh.isNotEmpty()) {
            Text(
                text = state.feedbackZh,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(EcColor.goodBg)
                    .padding(EcSpace.x3),
                fontSize = if (isChild) EcFont.childBody else EcFont.body,
                color = EcColor.ink,
            )
        }
        if (!isChild && state.feedbackEn.isNotEmpty()) {
            Text(text = state.feedbackEn, fontSize = EcFont.caption, color = EcColor.muted)
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = "🎤 再讲一次",
                onClick = onAgain,
                kind = EcButtonKind.SECONDARY,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                modifier = Modifier.weight(1f),
            )
            EcButton(
                label = "回到故事",
                onClick = onBack,
                kind = EcButtonKind.GHOST,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

// ------------------------------------------------------------------ 故事原文（可偷看）

@Composable
private fun ReviewSentenceCard(state: StoryReviewUiState) {
    if (state.storySentences.isEmpty()) return
    StoryCard(title = "故事原文（想不起来可以偷看）") {
        state.storySentences.forEachIndexed { index, sentence ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text(
                    text = "${index + 1}.",
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
                WordText(text = sentence, modifier = Modifier.weight(1f))
            }
        }
    }
}

// ------------------------------------------------------------------ 小工具

private fun recordButtonLabel(state: StoryReviewUiState, isChild: Boolean): String = when {
    state.recording -> "⏹ 说完啦 ${state.elapsedMs / 1000}s"
    state.preparing -> "准备麦克风…"
    isChild -> "🎤 开始讲（我听着）"
    else -> "🎤 开始复述"
}

package top.dreamsearch.englishcoach.ui.page.story

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcDialog
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RemoteImage
import top.dreamsearch.englishcoach.ui.component.WordText
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild
import top.dreamsearch.englishcoach.ui.nav.NavParams

/**
 * 故事详情（二级页，`Routes.STORY_DETAIL`，签名见 CONTRACT §5）。
 *
 * 对应 hos：`hos/entry/src/main/ets/pages/StoryDetailPage.ets`（布局/文案照抄）。
 * id 来自 `NavParams.storyMaterialId`（VM init 里读取并清空）。
 *
 * 内容：英文全文（逐句 TTS，可预取）+ **复制全文** + 中文原声回顾（本机落盘，文件失效只隐藏回放）
 * + 插画（鉴权接口图，可换一张，有费用提示）+ 整段朗读回放（building 轮询，**超时给重试**）
 * + 复述入口 / **上次复述（本机保存，可清除）** + 改名/删除（creator/parent）。
 * 不显示任何发音分；儿童隐藏提示词等技术细节。
 */
@Composable
fun StoryDetailScreen(onBack: () -> Unit, onOpenFlow: () -> Unit, onOpenReview: () -> Unit) {
    val vm: StoryDetailViewModel = viewModel(
        factory = remember { vmFactory { StoryDetailViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current

    LaunchedEffect(state.deleted) {
        if (state.deleted) onBack()
    }

    PageScaffold(
        title = "故事详情",
        onBack = onBack,
        scrollable = true,
        bottomBar = {
            if (!state.loading && state.error == null && state.storyId.isNotEmpty()) {
                DetailBottomBar(
                    storyId = state.storyId,
                    onOpenFlow = onOpenFlow,
                    onOpenReview = onOpenReview,
                )
            }
        },
    ) { padding ->
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

                state.error != null -> {
                    ErrorBanner(error = state.error, onRetry = { vm.retryLoad() })
                }

                else -> {
                    DetailHeaderCard(state, isChild, vm)
                    DetailEnglishCard(state, vm)
                    DetailSourceCard(state, vm)
                    DetailImageCard(state, isChild, vm)
                    DetailAudioCard(state, isChild, vm)
                    DetailRetellCard(state, isChild, onOpenReview)
                    StoryFooterNote("复述只看「讲清楚没有」，不计发音分。")
                }
            }
        }
    }

    if (state.confirmDelete) {
        EcDialog(title = "删除这个故事？", onDismiss = { vm.cancelDelete() }) {
            Text(
                text = "删除后全家都看不到这个故事了，无法恢复。",
                modifier = Modifier.fillMaxWidth(),
                fontSize = EcFont.body,
                color = EcColor.ink,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "取消",
                    onClick = { vm.cancelDelete() },
                    kind = EcButtonKind.GHOST,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = if (state.deleting) "删除中…" else "删除",
                    onClick = { vm.delete() },
                    kind = EcButtonKind.DANGER,
                    loading = state.deleting,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    if (state.confirmClearRecords) {
        EcDialog(title = "清除本机记录？", onDismiss = { vm.cancelClearRecords() }) {
            Text(
                text = "会删除本机保存的中文原声和上次复述记录；服务端的故事、英文正文与中文原文都不受影响。",
                modifier = Modifier.fillMaxWidth(),
                fontSize = EcFont.body,
                color = EcColor.ink,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "取消",
                    onClick = { vm.cancelClearRecords() },
                    kind = EcButtonKind.GHOST,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = "清除",
                    onClick = { vm.clearRecords() },
                    kind = EcButtonKind.DANGER,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

// ------------------------------------------------------------------ 页头

@Composable
private fun DetailHeaderCard(state: StoryDetailUiState, isChild: Boolean, vm: StoryDetailViewModel) {
    StoryCard {
        Text(
            text = state.title,
            modifier = Modifier.fillMaxWidth(),
            fontSize = if (isChild) EcFont.childH1 else EcFont.h2,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
        ) {
            if (state.level.isNotEmpty()) {
                EcPill(text = state.level, tone = PillTone.INFO)
            }
            if (state.sentenceCount > 0) {
                EcPill(text = "${state.sentenceCount} 句", tone = PillTone.NEUTRAL)
            }
            if (state.dateText.isNotEmpty()) {
                Text(text = state.dateText, fontSize = EcFont.micro, color = EcColor.muted)
            }
            if (state.authorName.isNotEmpty()) {
                Text(
                    text = "· ${state.authorName} 的故事",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }
        if (state.canEdit && !isChild) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "✏️ 改名",
                    onClick = { vm.startRename() },
                    kind = EcButtonKind.GHOST,
                    size = EcButtonSizeKind.SM,
                )
                EcButton(
                    label = "🗑 删除",
                    onClick = { vm.askDelete() },
                    kind = EcButtonKind.DANGER,
                    size = EcButtonSizeKind.SM,
                )
            }
        }
        if (state.renaming) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcTextField(
                    value = state.renameText,
                    onValueChange = vm::setRenameText,
                    label = "故事标题",
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = "保存",
                    onClick = { vm.saveRename() },
                    kind = EcButtonKind.SECONDARY,
                    size = EcButtonSizeKind.SM,
                    loading = state.renameSaving,
                )
                EcButton(
                    label = "取消",
                    onClick = { vm.cancelRename() },
                    kind = EcButtonKind.GHOST,
                    size = EcButtonSizeKind.SM,
                )
            }
        }
        if (state.actionError.isNotEmpty()) {
            Text(text = state.actionError, fontSize = EcFont.micro, color = EcColor.badText)
        }
    }
}

// ------------------------------------------------------------------ 英文全文（逐句朗读）

@Composable
private fun DetailEnglishCard(state: StoryDetailUiState, vm: StoryDetailViewModel) {
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    StoryCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = if (state.isChild) "📖 故事正文" else "英文全文",
                modifier = Modifier.weight(1f),
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
            if (!state.isChild) {
                EcButton(
                    label = "📋 复制全文",
                    onClick = {
                        val text = vm.copyText()
                        if (text.isNotEmpty()) {
                            clipboard.setText(AnnotatedString(text))
                            Toast.makeText(context, "已复制全文", Toast.LENGTH_SHORT).show()
                        }
                    },
                    kind = EcButtonKind.GHOST,
                    size = EcButtonSizeKind.SM,
                )
            }
            Text(text = "点 🔊 听这一句", fontSize = EcFont.micro, color = EcColor.muted)
        }
        if (!state.isChild) {
            Text(
                text = if (state.showSource && state.hasSourceZh) {
                    "复制内容：标题 + 英文全文 + 中文对照"
                } else {
                    "复制内容：标题 + 英文全文"
                },
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
        if (state.sentences.isEmpty()) {
            Text(
                text = "这个故事还没有正文。",
                modifier = Modifier.fillMaxWidth(),
                fontSize = EcFont.body,
                color = EcColor.muted,
            )
        }
        state.sentences.forEachIndexed { index, sentence ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text(
                    text = "${sentence.index}.",
                    modifier = Modifier.padding(top = EcSpace.x1),
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                )
                WordText(
                    text = sentence.en,
                    modifier = Modifier.weight(1f),
                )
                val loading = state.ttsLoadingIndex == index
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .clickable(enabled = !loading) { vm.playSentence(index) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = when {
                            loading -> "⏳"
                            state.playingSentenceIndex == index -> "🔊"
                            else -> "🔊"
                        },
                        fontSize = EcFont.h3,
                    )
                }
            }
        }
    }
}

// ------------------------------------------------------------------ 原声回顾

@Composable
private fun DetailSourceCard(state: StoryDetailUiState, vm: StoryDetailViewModel) {
    if (!state.hasSourceZh && state.originalPath.isEmpty()) return
    StoryCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = "🎙️ 原声回顾",
                modifier = Modifier.weight(1f),
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
            if (state.originalPath.isNotEmpty()) {
                EcPill(text = "本机保存 · 可回放", tone = PillTone.WARN)
            }
        }
        if (state.hasSourceZh) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { vm.toggleSource() },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "🗒️ 看看你当时怎么讲的（中文）",
                    modifier = Modifier.weight(1f),
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                )
                Text(
                    text = if (state.showSource) "收起" else "展开",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            if (state.showSource) {
                Text(
                    text = state.sourceZh,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(EcColor.surfaceAlt)
                        .padding(EcSpace.x3),
                    fontSize = EcFont.body,
                    color = EcColor.ink,
                )
            }
        }
        if (state.originalPath.isNotEmpty()) {
            EcButton(
                label = if (state.originalPlaying) "播放中…" else "▶ 听我讲的中文原声",
                onClick = { vm.playOriginal() },
                kind = EcButtonKind.SECONDARY,
                fullWidth = true,
            )
            Text(
                text = "原声保存在本机（录故事时的那段）；换设备、清缓存或文件被清理后可能听不到，但中文原文仍保留。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        } else if (state.originalText.isNotBlank()) {
            Text(
                text = "本机原声文件已不在了，中文原文仍然保留。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
    }
}

// ------------------------------------------------------------------ 插画

@Composable
private fun DetailImageCard(state: StoryDetailUiState, isChild: Boolean, vm: StoryDetailViewModel) {
    StoryCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = if (isChild) "🎨 给我的故事画张画" else "🖼️ 故事插画",
                modifier = Modifier.weight(1f),
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
            if (state.hasImage && !state.imageLoading) {
                Text(text = "✅ 已生成", fontSize = EcFont.micro, color = EcColor.goodText)
            }
        }

        when {
            state.imageLoading -> {
                LoadingBlock(text = "🎨 正在画插画… 大约 10–30 秒", subText = "可以先看文字或听朗读")
            }

            state.hasImage -> {
                RemoteImage(
                    path = "/materials/${state.storyId}/image?v=${state.imageVersion}",
                    contentDescription = state.title,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(320.dp),
                    withAuth = true,
                    fallback = {
                        StoryPlaceholderBox(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(320.dp),
                            emoji = "🖼️",
                        )
                    },
                )
                if (!isChild && state.imagePrompt.isNotEmpty()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { vm.togglePrompt() },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "🖼️ 生成用的提示词",
                            modifier = Modifier.weight(1f),
                            fontSize = EcFont.micro,
                            color = EcColor.primary,
                        )
                        Text(
                            text = if (state.showPrompt) "收起" else "展开",
                            fontSize = EcFont.micro,
                            color = EcColor.muted,
                        )
                    }
                    if (state.showPrompt) {
                        Text(
                            text = state.imagePrompt,
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(EcColor.surfaceAlt)
                                .padding(EcSpace.x2),
                            fontSize = EcFont.micro,
                            color = EcColor.muted,
                        )
                    }
                }
                if (state.imageCapable) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                    ) {
                        EcButton(
                            label = if (state.imageLoading) "画中…" else "🖼️ 换一张",
                            onClick = { vm.illustrate(true) },
                            kind = EcButtonKind.SECONDARY,
                            loading = state.imageLoading,
                            modifier = Modifier.weight(1f),
                        )
                        EcButton(
                            label = "重新加载",
                            onClick = { vm.reloadImage() },
                            kind = EcButtonKind.GHOST,
                            size = EcButtonSizeKind.SM,
                        )
                        Text(text = "每张约 ¥0.1", fontSize = EcFont.micro, color = EcColor.muted)
                    }
                }
            }

            state.imageCapable -> {
                EcButton(
                    label = "🖼️ 给我画一张",
                    onClick = { vm.illustrate(false) },
                    kind = EcButtonKind.SECONDARY,
                    fullWidth = true,
                )
            }

            else -> {
                Text(
                    text = "插画服务暂未启用（服务端 capabilities.image=false），先读故事、听朗读吧。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }

        if (state.imageError.isNotEmpty()) {
            Text(text = state.imageError, fontSize = EcFont.caption, color = EcColor.badText)
        }
    }
}

// ------------------------------------------------------------------ 整段朗读回放

@Composable
private fun DetailAudioCard(state: StoryDetailUiState, isChild: Boolean, vm: StoryDetailViewModel) {
    StoryCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "🎧 " + if (isChild) "听一听我读的故事" else "整段朗读回放",
                modifier = Modifier.weight(1f),
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
            if (state.audioDurationText.isNotEmpty() && state.audioState == STORY_AUDIO_READY) {
                Text(text = state.audioDurationText, fontSize = EcFont.micro, color = EcColor.muted)
            }
        }

        when (state.audioState) {
            STORY_AUDIO_CHECKING -> {
                LoadingBlock(text = "正在检查朗读录音…")
            }

            STORY_AUDIO_BUILDING -> {
                StoryBusyRow(state.audioStatusText)
                if (state.audioSlow) {
                    Text(
                        text = "生成超过 30 秒了：可以继续等，也可以重新生成一段。",
                        fontSize = EcFont.caption,
                        color = EcColor.warnText,
                    )
                    EcButton(
                        label = "🔄 重新生成",
                        onClick = { vm.retryAudio() },
                        kind = EcButtonKind.SECONDARY,
                        fullWidth = true,
                    )
                }
            }

            STORY_AUDIO_READY -> {
                Text(text = state.audioStatusText, fontSize = EcFont.caption, color = EcColor.muted)
                EcButton(
                    label = if (state.audioPlaying) "⏹ 停止播放" else "▶ 播放整段朗读",
                    onClick = {
                        if (state.audioPlaying) vm.stopPlayback() else vm.playAudio()
                    },
                    loading = state.audioLoading,
                    fullWidth = true,
                )
            }

            STORY_AUDIO_FAILED -> {
                Text(text = state.audioStatusText, fontSize = EcFont.caption, color = EcColor.warnText)
                EcButton(
                    label = "🔄 重新生成整段朗读",
                    onClick = { vm.retryAudio() },
                    kind = EcButtonKind.SECONDARY,
                    fullWidth = true,
                )
            }

            else -> {
                Text(text = state.audioStatusText, fontSize = EcFont.caption, color = EcColor.warnText)
            }
        }

        if (state.audioError.isNotEmpty()) {
            Text(text = state.audioError, fontSize = EcFont.micro, color = EcColor.badText)
        }
        Text(
            text = "说明：整段朗读来自你的连读/跟读录音；没读过就是空的。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

// ------------------------------------------------------------------ 复述入口 / 记录

@Composable
private fun DetailRetellCard(
    state: StoryDetailUiState,
    isChild: Boolean,
    onOpenReview: () -> Unit,
) {
    StoryCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "🎤 讲给我听",
                    modifier = Modifier.fillMaxWidth(),
                    fontSize = EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                )
                Text(
                    text = "不看屏幕，用 2–3 句话把故事讲一遍 🙂",
                    modifier = Modifier.fillMaxWidth(),
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
            }
            EcButton(
                label = if (state.lastRetell != null) "再复述一次" else "去复述",
                onClick = {
                    NavParams.storyMaterialId = state.storyId
                    onOpenReview()
                },
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            )
        }

        state.lastRetell?.let { record ->
            Text(
                text = "上次复述（本机保存）",
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(EcColor.surfaceAlt)
                    .padding(EcSpace.x3),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = if (isChild) {
                            "你真棒！讲到了 ${record.coveredPoints.size} 个关键点"
                        } else {
                            "覆盖度 ${if (record.coveragePercent < 0) "—" else "${record.coveragePercent}%"} · " +
                                "讲到了 ${record.coveredPoints.size} 个关键点"
                        },
                        modifier = Modifier.weight(1f),
                        fontSize = EcFont.caption,
                        fontWeight = FontWeight.Medium,
                        color = if (isChild) EcColor.goodText else EcColor.ink,
                    )
                    Text(text = record.createdAt, fontSize = EcFont.micro, color = EcColor.muted)
                }
                if (record.feedbackZh.isNotEmpty()) {
                    Text(text = record.feedbackZh, fontSize = EcFont.caption, color = EcColor.muted)
                }
                if (record.missingPoints.isNotEmpty()) {
                    Text(
                        text = "下一次可以试试：" + record.missingPoints.joinToString("、"),
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
            }
        }

        if (state.hasLocalRecords) {
            EcButton(
                label = "🗑 清除本机记录",
                onClick = { vm.askClearRecords() },
                kind = EcButtonKind.GHOST,
                size = EcButtonSizeKind.SM,
            )
            Text(
                text = "只清除本机保存的原声/复述记录，服务端的故事和文字不受影响。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
        if (state.recordsNotice.isNotEmpty()) {
            Text(text = state.recordsNotice, fontSize = EcFont.micro, color = EcColor.goodText)
        }
    }
}

// ------------------------------------------------------------------ 底部操作

@Composable
private fun DetailBottomBar(storyId: String, onOpenFlow: () -> Unit, onOpenReview: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(EcColor.surface)
            .padding(horizontal = EcSpace.x4, vertical = EcSpace.x2),
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        EcButton(
            label = "🔗 去连读",
            onClick = {
                NavParams.flowMaterialId = storyId
                onOpenFlow()
            },
            kind = EcButtonKind.SECONDARY,
            modifier = Modifier.weight(1f),
        )
        EcButton(
            label = "🎤 复述故事",
            onClick = {
                NavParams.storyMaterialId = storyId
                onOpenReview()
            },
            modifier = Modifier.weight(1f),
        )
    }
}

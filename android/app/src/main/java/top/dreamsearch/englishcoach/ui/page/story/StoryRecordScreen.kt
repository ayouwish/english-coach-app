package top.dreamsearch.englishcoach.ui.page.story

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import top.dreamsearch.englishcoach.ui.component.EcSwitchRow
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RemoteImage
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild
import top.dreamsearch.englishcoach.ui.nav.NavParams
import top.dreamsearch.englishcoach.ui.nav.Navigator
import top.dreamsearch.englishcoach.ui.nav.Routes

/**
 * 新建故事（二级页，`Routes.STORY_RECORD`，签名见 CONTRACT §5）。
 *
 * 对应 hos：`hos/entry/src/main/ets/pages/StoryRecordPage.ets`（布局/文案照抄），
 * ViewModel：[StoryRecordViewModel]（中文输入/录音识别 → 改写 → 可编辑预览 → 保存）。
 *
 * 导航契约（本页只有 onBack / onOpenFlow 两个回调）：
 * - 保存成功后「去连读」：写 `NavParams.flowMaterialId` 再调 [onOpenFlow]（父级切 FLOW Tab 回首页）；
 * - 保存成功后「查看故事」：写 `NavParams.storyMaterialId` 后 `Navigator.navigate(Routes.STORY_DETAIL)`；
 * - 「画一张插画」：留在本页，`illustrate(id, force=false)`，成功后直接显示插画；
 * - 账号开启 `auto_illustrate` 时，保存成功会自动画一张（失败不影响已保存的故事）。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StoryRecordScreen(onBack: () -> Unit, onOpenFlow: () -> Unit) {
    val vm: StoryRecordViewModel = viewModel(
        factory = remember { vmFactory { StoryRecordViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    val mic = rememberMicPermission()

    val onRecordClick: () -> Unit = {
        when {
            state.recording -> vm.stopRecordingAndRecognize()
            !mic.granted -> mic.request()
            else -> vm.startRecording()
        }
    }

    PageScaffold(title = "新故事", onBack = onBack, scrollable = true) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxWidth()
                .padding(horizontal = EcSpace.x4, vertical = EcSpace.x3),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            // ---------------- 中文输入 + 语音输入 ----------------
            StoryCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = if (isChild) "先用中文讲讲吧" else "故事内容（中文）",
                        modifier = Modifier.weight(1f),
                        fontSize = EcFont.body,
                        fontWeight = FontWeight.Medium,
                        color = EcColor.ink,
                    )
                    val overLimit = state.textZh.length >= StoryRecordViewModel.MAX_ZH_CHARS
                    Text(
                        text = "${state.textZh.length} / ${StoryRecordViewModel.MAX_ZH_CHARS}",
                        fontSize = EcFont.micro,
                        color = if (overLimit) EcColor.badText else EcColor.muted,
                    )
                }
                EcTextField(
                    value = state.textZh,
                    onValueChange = vm::setTextZh,
                    label = "中文故事",
                    placeholder = "例如：今天我和小明搭积木塔，被小华碰倒了，我很生气。",
                    singleLine = false,
                    enabled = !state.busy,
                    modifier = Modifier.height(150.dp),
                )
                if (state.exceeded) {
                    EcInlineNotice(text = "今天的练习时长已达上限，明天再来 🌙", tone = PillTone.WARN)
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                ) {
                    EcButton(
                        label = recordButtonLabel(state, isChild),
                        onClick = onRecordClick,
                        kind = if (state.recording) EcButtonKind.DANGER else EcButtonKind.SECONDARY,
                        size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                        enabled = !state.busy && !state.saving && !state.exceeded,
                        loading = state.preparing,
                        modifier = Modifier.weight(1f),
                    )
                    if (state.recording) {
                        EcButton(
                            label = "✖️ 不要了",
                            onClick = vm::cancelRecording,
                            kind = EcButtonKind.GHOST,
                            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                StoryBusyRow(state.busyText)
                StoryNotice(state.notice)
                ErrorBanner(
                    error = state.error,
                    onRetry = {
                        if (state.error?.code == ApiErrorCode.MIC_DENIED) mic.request() else vm.retry()
                    },
                    onDismiss = vm::clearError,
                )
                Text(
                    text = "说中文会被转成文字写进上面的框里；录音本身只在本次会话里可用。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }

            // ---------------- 难度 / 句数 / 时态 ----------------
            StoryCard(title = null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(text = "难度", fontSize = EcFont.caption, color = EcColor.muted, modifier = Modifier.weight(1f))
                    Text(
                        text = "⬇️ 再简单一点",
                        fontSize = EcFont.micro,
                        color = EcColor.primary,
                        modifier = Modifier
                            .clickable { vm.adjustLevel(-1) }
                            .padding(horizontal = EcSpace.x1),
                    )
                    Text(
                        text = "⬆️ 再难一点",
                        fontSize = EcFont.micro,
                        color = EcColor.primary,
                        modifier = Modifier
                            .clickable { vm.adjustLevel(1) }
                            .padding(horizontal = EcSpace.x1),
                    )
                }
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                    verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
                ) {
                    StoryRecordViewModel.LEVELS.forEach { level ->
                        EcChip(
                            label = level,
                            selected = state.level == level,
                            onClick = { vm.selectLevel(level) },
                        )
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(text = "句子数", fontSize = EcFont.caption, color = EcColor.muted, modifier = Modifier.weight(1f))
                    Text(
                        text = "儿童默认 5 句 / 成人默认 8 句",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                    verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
                ) {
                    (3..12).forEach { count ->
                        EcChip(
                            label = count.toString(),
                            selected = state.maxSentences == count,
                            onClick = { vm.setMaxSentences(count) },
                        )
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(text = "时态", fontSize = EcFont.caption, color = EcColor.muted, modifier = Modifier.weight(1f))
                    Text(
                        text = "讲故事默认用过去时",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                    verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
                ) {
                    StoryRecordViewModel.TENSES.forEach { tense ->
                        EcChip(
                            label = tenseLabel(tense),
                            selected = state.tense == tense,
                            onClick = { vm.setTense(tense) },
                        )
                    }
                }
                if (!isChild) {
                    EcSwitchRow(
                        title = "把 weakest 音练进故事",
                        subtitle = "按你最近最弱的音挑词，故事读起来更有针对性（成人）",
                        checked = state.useWeakPhonemes,
                        onCheckedChange = vm::setUseWeakPhonemes,
                        enabled = !state.busy,
                    )
                }
            }

            // ---------------- 生成入口 / 手动英文 ----------------
            if (!state.hasResult && !state.manualMode) {
                EcButton(
                    label = if (state.busy) "生成中…" else "✨ 变成英文故事",
                    onClick = vm::rewrite,
                    size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.LG,
                    loading = state.busy,
                    enabled = state.textZh.trim().isNotEmpty(),
                    fullWidth = true,
                )
                EcButton(
                    label = "✍️ 我自己写英文",
                    onClick = vm::enterManualMode,
                    kind = EcButtonKind.GHOST,
                    fullWidth = true,
                    enabled = !state.busy,
                )
            }

            if (state.manualMode && !state.hasResult) {
                StoryCard(title = "自己写英文（保存后一样能连读、复述）") {
                    EcTextField(
                        value = state.manualTitle,
                        onValueChange = vm::setManualTitle,
                        label = "标题（英文）",
                        placeholder = "The Lost Kitten",
                    )
                    EcTextField(
                        value = state.manualText,
                        onValueChange = vm::setManualText,
                        label = "英文故事（一行一句）",
                        placeholder = "Once upon a time, I built a tower with Ming.",
                        singleLine = false,
                        modifier = Modifier.height(150.dp),
                    )
                    EcButton(
                        label = if (state.saving) "保存中…" else "💾 保存故事",
                        onClick = vm::save,
                        kind = EcButtonKind.PRIMARY,
                        loading = state.saving,
                        enabled = !state.busy,
                        fullWidth = true,
                    )
                    EcButton(
                        label = "🔄 还是让 AI 写",
                        onClick = vm::rewrite,
                        kind = EcButtonKind.GHOST,
                        enabled = !state.busy && state.textZh.trim().isNotEmpty(),
                        fullWidth = true,
                    )
                }
            }

            // ---------------- 英文预览（可编辑） ----------------
            if (state.hasResult) {
                StoryCard {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                    ) {
                        Text(
                            text = "英文故事预览",
                            fontSize = EcFont.body,
                            fontWeight = FontWeight.Medium,
                            color = EcColor.ink,
                        )
                        EcPill(text = state.level, tone = PillTone.INFO)
                        Text(
                            text = "可逐句修改",
                            modifier = Modifier.weight(1f),
                            fontSize = EcFont.micro,
                            color = EcColor.muted,
                        )
                    }
                    EcTextField(
                        value = state.title,
                        onValueChange = vm::setTitle,
                        label = "标题（英文）",
                        placeholder = "给故事起个标题",
                    )
                    if (!isChild && state.readabilityText.isNotEmpty()) {
                        Text(text = state.readabilityText, fontSize = EcFont.caption, color = EcColor.muted)
                    }
                    if (!isChild && state.unknownWordsText.isNotEmpty()) {
                        Text(text = state.unknownWordsText, fontSize = EcFont.micro, color = EcColor.muted)
                    }
                    if (state.warningText.isNotEmpty()) {
                        EcInlineNotice(text = state.warningText, tone = PillTone.WARN)
                    }
                    if (!isChild && state.weakPhonemes.isNotEmpty()) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
                        ) {
                            Text(text = "练到这些音：", fontSize = EcFont.micro, color = EcColor.muted)
                            state.weakPhonemes.forEach { phoneme ->
                                EcPill(text = phoneme, tone = PillTone.NEUTRAL)
                            }
                        }
                    }
                    state.sentences.forEachIndexed { index, sentence ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.Top,
                            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                        ) {
                            Text(
                                text = "${sentence.index}.",
                                modifier = Modifier.padding(top = EcSpace.x3),
                                fontSize = EcFont.caption,
                                color = EcColor.muted,
                            )
                            EcTextField(
                                value = sentence.en,
                                onValueChange = { vm.setSentenceEn(index, it) },
                                label = "第 ${sentence.index} 句",
                                singleLine = false,
                                enabled = !state.busy,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                    if (state.savedId.isEmpty()) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                        ) {
                            EcButton(
                                label = if (state.saving) "保存中…" else "💾 保存故事",
                                onClick = vm::save,
                                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                                loading = state.saving,
                                enabled = !state.busy,
                                modifier = Modifier.weight(1f),
                            )
                            EcButton(
                                label = "🔄 重新生成",
                                onClick = vm::rewrite,
                                kind = EcButtonKind.GHOST,
                                enabled = !state.busy,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
            }

            // ---------------- 保存成功：去连读 / 查看故事 / 插画 ----------------
            if (state.savedId.isNotEmpty()) {
                StoryCard(title = "✅ 已保存到家庭书架") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                    ) {
                        EcButton(
                            label = "🔗 去连读",
                            onClick = {
                                NavParams.flowMaterialId = state.savedId
                                onOpenFlow()
                            },
                            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                            modifier = Modifier.weight(1f),
                        )
                        EcButton(
                            label = "📖 查看故事",
                            onClick = {
                                NavParams.storyMaterialId = state.savedId
                                Navigator.navigate(Routes.STORY_DETAIL)
                            },
                            kind = EcButtonKind.SECONDARY,
                            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                            modifier = Modifier.weight(1f),
                        )
                    }

                    if (state.illustrating) {
                        // 不显示假进度：只告知耗时与价格（自动插图/手动插图共用）
                        StoryBusyRow("正在生成插画… 约 10–30 秒（约 ¥0.1/张）")
                    } else if (state.autoIllustrate && state.imageCapable) {
                        EcInlineNotice(
                            text = "已开启自动插图：保存后会自动生成一张（约 ¥0.1/张，约 10–30 秒）。",
                            tone = PillTone.INFO,
                        )
                    }

                    if (!state.imageCapable) {
                        Text(
                            text = "插画服务暂未启用，可以先去连读或查看故事。",
                            fontSize = EcFont.micro,
                            color = EcColor.muted,
                        )
                    } else if (!state.illustrationDone && !state.illustrating) {
                        EcButton(
                            label = if (state.illustrationError.isNotEmpty()) {
                                "🖼️ 重试画插画"
                            } else {
                                "🖼️ 画一张插画"
                            },
                            onClick = vm::illustrate,
                            kind = EcButtonKind.SECONDARY,
                            fullWidth = true,
                        )
                        Text(
                            text = "生成插画约需 10–30 秒、约 ¥0.1/张；失败不会影响已保存的故事。",
                            fontSize = EcFont.micro,
                            color = EcColor.muted,
                        )
                    }
                    if (state.illustrationError.isNotEmpty()) {
                        Text(text = state.illustrationError, fontSize = EcFont.caption, color = EcColor.badText)
                    }
                    if (state.illustrationDone) {
                        RemoteImage(
                            path = "/materials/${state.savedId}/image?v=${state.imageVersion}",
                            contentDescription = state.title,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(220.dp),
                            withAuth = true,
                            fallback = {
                                StoryPlaceholderBox(
                                    modifier = Modifier.fillMaxWidth().height(220.dp),
                                    emoji = "🎨",
                                )
                            },
                        )
                        EcButton(
                            label = "重新加载插画",
                            onClick = { vm.reloadIllustration() },
                            kind = EcButtonKind.GHOST,
                            size = EcButtonSizeKind.SM,
                            fullWidth = true,
                        )
                    }
                    EcButton(
                        label = "返回故事集",
                        onClick = onBack,
                        kind = EcButtonKind.GHOST,
                        fullWidth = true,
                    )
                }
            }

            StoryFooterNote("改写会按你的难度和句数生成；保存后可以插画、听整段朗读、做复述。")
        }
    }
}

// ------------------------------------------------------------------ 小工具

private fun recordButtonLabel(state: StoryRecordUiState, isChild: Boolean): String = when {
    state.recording -> "⏹ 说完啦 ${state.elapsedMs / 1000}s"
    state.preparing -> "准备麦克风…"
    isChild -> "🎤 说中文（我听着）"
    else -> "🎤 说中文"
}

private fun tenseLabel(tense: String): String = when (tense) {
    "auto" -> "自动"
    "past" -> "过去时"
    "present" -> "现在时"
    else -> tense
}

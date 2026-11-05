package top.dreamsearch.englishcoach.ui.page.flow

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcScore
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.nav.Navigator
import top.dreamsearch.englishcoach.ui.nav.Routes

/**
 * 连读汇总（push 出来的二级页）。
 *
 * 对应 hos：`hos/entry/src/main/ets/pages/FlowSummaryPage.ets`；签名按 `ROUND2_CONTRACT.md` §2：
 * `@Composable fun FlowSummaryScreen(onBack: () -> Unit, onOpenFlowTab: () -> Unit, onOpenReview: (materialId: String) -> Unit)`。
 *
 * 内容（与 hos 一致）：
 * - 头部：完成句数 / 平均分（成人数字、儿童按 EcScore 规则隐藏低分）/ 第几遍；
 * - 鼓励语（本地 6 档中英双语，可 🔊 听鼓励，音色/语速走 `VoicePrefs`）；
 * - 这一批的问题（`FlowService.diagnosisBatch`，儿童不出现 IPA、低分不显示数字）；
 * - 最需要再练的几句 + 失败句重读入口；
 * - 待补评分提示：本轮有「网络/5xx 失败已入队」的句子时显示「待补评分 N 条 → 去处理」；
 * - 保存本次自定义文本为书页（`FlowService.createPage`）；
 * - 再读一遍 / 再读一段（改共享运行态后由 `onOpenFlowTab` 切回连读 Tab）；
 * - 本轮来自故事材料时「📝 复述这个故事」→ `onOpenReview(materialId)`；
 * - 逐条列表（点一行展开详情，失败行可「重录这句」）。
 *
 * 「重录这句」必须先调用运行态（FlowSummaryViewModel.redo）再切 Tab，否则直接切走会读到旧状态。
 */
@Composable
fun FlowSummaryScreen(
    onBack: () -> Unit,
    onOpenFlowTab: () -> Unit,
    onOpenReview: (materialId: String) -> Unit,
) {
    val vm: FlowSummaryViewModel = viewModel(factory = remember { vmFactory { FlowSummaryViewModel(AppGraph.container) } })
    val state by vm.state.collectAsStateWithLifecycle()
    val child = state.isChild

    // 从「待补评分」页返回时刷新队列条数（该页 pop 后本页会重新进入组合）
    LaunchedEffect(Unit) { vm.refreshPendingUploads() }

    PageScaffold(
        title = if (child) "读完啦" else "连读汇总",
        onBack = onBack,
        scrollable = true,
    ) { innerPadding ->
        if (!state.ready || state.summary == null) {
            Column(modifier = Modifier.padding(innerPadding)) {
                EmptyState(
                    icon = "🎉",
                    message = if (child) "还没有读完一轮哦" else "还没有读完一轮连读",
                    actionLabel = "返回连读",
                    onAction = onOpenFlowTab,
                )
            }
            return@PageScaffold
        }
        val data = state.summary ?: return@PageScaffold

        Column(
            modifier = Modifier
                .padding(innerPadding)
                .padding(horizontal = EcSpace.x4, vertical = EcSpace.x3),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            HeaderCard(data = data, isChild = child)
            EncouragementCard(state = state, onPlay = vm::playEncouragement)
            DiagnosisCard(state = state, doneCount = data.doneCount, onRetry = vm::loadDiagnosis)
            WorstCard(data = data, isChild = child)
            if (data.failedCount > 0) {
                FailedListCard(
                    items = state.items.filter { it.status == FlowStatus.FAILED },
                    isChild = child,
                    onRedo = { index ->
                        if (vm.redo(index)) onOpenFlowTab()
                    },
                )
            }
            if (state.customText.isNotBlank()) {
                SavedPageCard(vm = vm, state = state)
            }
            if (state.pendingUploads > 0) {
                PendingUploadsCard(count = state.pendingUploads, isChild = child)
            }
            ActionRow(
                isChild = child,
                onReread = { if (vm.reread()) onOpenFlowTab() },
                onBackToSetup = { if (vm.backToSetup()) onOpenFlowTab() },
            )
            // 仅当本轮句子来自故事材料（故事详情/故事保存 → 去连读）时提供复述入口
            if (data.fromStoryMaterial && data.materialId.isNotEmpty()) {
                EcButton(
                    label = if (child) "📝 讲讲这个故事" else "📝 复述这个故事",
                    onClick = { onOpenReview(data.materialId) },
                    kind = EcButtonKind.SECONDARY,
                    size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                    fullWidth = true,
                )
            }

            Text(
                text = if (child) "一句一句看（点一下看看）" else "逐条列表（点一行展开详情）",
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
            state.items.forEach { item ->
                FlowItemRow(
                    item = item,
                    isChild = child,
                    expanded = state.expandedIndex == item.index,
                    onToggle = { vm.toggleExpanded(item.index) },
                    onRedo = {
                        if (vm.redo(item.index)) onOpenFlowTab()
                    },
                )
            }
            Spacer(modifier = Modifier.height(EcSpace.x6))
        }
    }
}

// ===========================================================================
// 区块
// ===========================================================================

@Composable
private fun HeaderCard(data: FlowSummaryData, isChild: Boolean) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(EcColor.surface)
            .padding(EcSpace.x5),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = "🎉 " + if (isChild) "读完啦！" else "连读完成",
                fontSize = if (isChild) EcFont.childH1 else EcFont.h2,
                fontWeight = FontWeight.Bold,
                color = EcColor.ink,
                modifier = Modifier.weight(1f),
            )
            if (data.round > 1) {
                EcPill(text = "第 ${data.round} 遍", tone = PillTone.INFO)
            }
        }
        Text(
            text = summaryLineText(data, isChild),
            fontSize = EcFont.body,
            color = EcColor.ink,
        )
    }
}

@Composable
private fun EncouragementCard(state: FlowSummaryUiState, onPlay: () -> Unit) {
    val data = state.summary ?: return
    val isChild = state.isChild
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(EcColor.primarySoft)
            .padding(EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = "🎙", fontSize = EcFont.h3)
            Text(
                text = if (isChild) "听听夸奖" else "鼓励语",
                fontSize = EcFont.caption,
                color = EcColor.muted,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = if (state.encPlaying) "🔊 播放中…" else "🔊 听鼓励",
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(enabled = !state.encPlaying, onClick = onPlay)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
            )
        }
        Text(
            text = encouragementZhText(data),
            fontSize = if (isChild) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        Text(text = data.encouragement.en, fontSize = EcFont.caption, color = EcColor.muted)
        if (state.encError.isNotEmpty()) {
            Text(text = state.encError, fontSize = EcFont.micro, color = EcColor.warnText)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DiagnosisCard(state: FlowSummaryUiState, doneCount: Int, onRetry: () -> Unit) {
    val isChild = state.isChild
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(EcColor.surface)
            .padding(EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = "这一批（$doneCount 句）的问题",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        when {
            state.diagLoading -> LoadingBlock(text = "正在统计…")
            state.diagError.isNotEmpty() -> {
                Text(text = state.diagError, fontSize = EcFont.caption, color = EcColor.warnText)
                Text(
                    text = "重试",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(onClick = onRetry)
                        .padding(vertical = EcSpace.x1),
                )
            }
            else -> {
                if (state.diagSummary.isNotEmpty()) {
                    Text(text = state.diagSummary, fontSize = EcFont.caption, color = EcColor.ink)
                }
                if (state.diagChips.isNotEmpty()) {
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
                        verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
                    ) {
                        state.diagChips.forEach { chip ->
                            EcPill(text = chip.label, tone = chip.tone.toPillTone())
                        }
                    }
                }
                if (doneCount == 0) {
                    Text(
                        text = "这一批还没有评完的句子，暂时没有诊断",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
            }
        }
    }
}

@Composable
private fun WorstCard(data: FlowSummaryData, isChild: Boolean) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(EcColor.surface)
            .padding(EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
    ) {
        Text(
            text = if (isChild) "这几句可以再读一遍" else "最需要再练的几句",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        if (data.worst.isEmpty()) {
            Text(
                text = if (isChild) {
                    "读得开心最重要 🙂"
                } else {
                    "这一批没有拿到分数，先不用纠结分数，读得开心最重要 🙂"
                },
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
        } else {
            data.worst.forEach { row ->
                Text(
                    text = worstLine(row, isChild),
                    fontSize = EcFont.caption,
                    color = EcColor.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** 失败句列表 + 重录入口（儿童不出现「失败」字样）。 */
@Composable
private fun FailedListCard(
    items: List<FlowItem>,
    isChild: Boolean,
    onRedo: (Int) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(EcColor.surface)
            .padding(EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = if (isChild) "这几句要不要再读一遍" else "需要重读的句子",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        items.forEach { item ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = "${item.index + 1}. ${item.text}",
                        fontSize = if (isChild) EcFont.childBody else EcFont.caption,
                        color = EcColor.ink,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = item.error.ifEmpty { "评分没有成功" },
                        fontSize = EcFont.micro,
                        color = if (isChild) EcColor.warnText else EcColor.badText,
                        maxLines = 2,
                    )
                }
                Text(
                    text = if (isChild) "再读一次" else "重录这句",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable { onRedo(item.index) }
                        .padding(horizontal = EcSpace.x1, vertical = EcSpace.x1),
                )
            }
        }
    }
}

/**
 * 待补评分提示（本轮或历史批次的录音因网络/5xx 已入 `PendingUploadQueue`）。
 * 点击「去处理」进入 `Routes.PENDING_UPLOADS` 页（screens-chat 负责实现）。
 */
@Composable
private fun PendingUploadsCard(count: Int, isChild: Boolean) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(EcColor.warnBg)
            .padding(EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = "📤 待补评分 $count 条",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        Text(
            text = if (isChild) {
                "这些录音先存在本机啦，等网络好一点再补评分"
            } else {
                "提交时网络/服务端暂时不可用，录音已保存在本机；网络恢复后可以逐条补提交评分"
            },
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        EcButton(
            label = if (isChild) "去补评分" else "去处理 →",
            onClick = { Navigator.navigate(Routes.PENDING_UPLOADS) },
            kind = EcButtonKind.SECONDARY,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            fullWidth = true,
        )
    }
}

/** 保存本次自定义文本为书页（只在有自定义文本时展示）。 */
@Composable
private fun SavedPageCard(vm: FlowSummaryViewModel, state: FlowSummaryUiState) {
    val isChild = state.isChild
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(EcColor.surface)
            .padding(EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = "💾 把这次读的文字存成书页",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        EcTextField(
            value = state.saveTitle,
            onValueChange = vm::setSaveTitle,
            label = "书页标题",
            placeholder = "默认取第一行",
            enabled = state.savedPageId.isEmpty(),
        )
        if (state.savedPageId.isNotEmpty()) {
            Text(
                text = "已保存为「${state.savedPageTitle.ifEmpty { "未命名书页" }}」",
                fontSize = EcFont.micro,
                color = EcColor.goodText,
            )
        } else {
            EcButton(
                label = if (state.saveBusy) "保存中…" else "保存为书页",
                onClick = vm::saveCustomPage,
                kind = EcButtonKind.SECONDARY,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                loading = state.saveBusy,
                enabled = state.customText.isNotBlank(),
            )
        }
        state.saveError?.let { error ->
            ErrorBanner(error = error, onRetry = vm::saveCustomPage, onDismiss = vm::clearSaveError)
        }
    }
}

@Composable
private fun ActionRow(isChild: Boolean, onReread: () -> Unit, onBackToSetup: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
        EcButton(
            label = if (isChild) "🔁 再读一遍～" else "🔁 再读一遍",
            onClick = onReread,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.LG,
            fullWidth = true,
        )
        EcButton(
            label = "再读一段",
            onClick = onBackToSetup,
            kind = EcButtonKind.GHOST,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            fullWidth = true,
        )
    }
}

// ===========================================================================
// 纯文本辅助
// ===========================================================================

private fun worstLine(row: FlowWorstItem, isChild: Boolean): String {
    if (isChild) return "· ${row.text}"
    val score = row.score
    val scoreText = if (score == null) "—" else "${EcScore.numberText(score)} 分"
    return "· $scoreText · ${row.text}"
}

/** 诊断色调（模型层）→ 组件层 PillTone。 */
private fun DiagTone.toPillTone(): PillTone = when (this) {
    DiagTone.NEUTRAL -> PillTone.NEUTRAL
    DiagTone.GOOD -> PillTone.GOOD
    DiagTone.WARN -> PillTone.WARN
    DiagTone.BAD -> PillTone.BAD
}

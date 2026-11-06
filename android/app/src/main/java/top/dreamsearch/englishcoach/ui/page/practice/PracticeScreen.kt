package top.dreamsearch.englishcoach.ui.page.practice

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.collect
import top.dreamsearch.englishcoach.core.audio.rememberMicPermission
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
import top.dreamsearch.englishcoach.ui.component.EcLineChart
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcRadarChart
import top.dreamsearch.englishcoach.ui.component.EcTrendChart
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RecordButton
import top.dreamsearch.englishcoach.ui.component.ScoreBadge
import top.dreamsearch.englishcoach.ui.component.ScoreChip
import top.dreamsearch.englishcoach.ui.component.SubScoreRow
import top.dreamsearch.englishcoach.ui.component.WordText
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcScore
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild
import top.dreamsearch.englishcoach.ui.nav.NavParams
import top.dreamsearch.englishcoach.ui.nav.Navigator
import top.dreamsearch.englishcoach.ui.nav.Routes

/**
 * 跟读练习页（Tab 根页：`@Composable fun PracticeTab()`）。
 *
 * 移植自 hos `pages/PracticePage.ets`；ROUND2 补齐（`android/ROUND2_CONTRACT.md` §4）：
 * ①结果区能力雷达（成人，`EcRadarChart`）；
 * ②全屏结果页（页内 overlay，不新增路由；顶部关闭 / 底部重试评测 / 下一句 / BackHandler）；
 * ③单句历史逐条回放（`audioUrl` → `AudioController.playBytes`；儿童保留回放、隐藏分数）；
 * ④左右滑动切句（`HorizontalPager`，保留上下句按钮；录音/提交中禁滑）；
 * ⑤示范音/跟我读走 `VoicePrefs.resolve(isChild)`（VM 内）；
 * ⑥提交网络/5xx 失败自动入队待补评分（VM 内）+ 顶部「去补评分」入口。
 *
 * 三态：loading 骨架、error（ErrorBanner + 重试）、empty（EmptyState + 换等级）。
 * 儿童规则（docs/screens.md §0）：不显示 IPA/雷达/F0/低分数字，统一走 `LocalIsChild`。
 */
@Composable
fun PracticeTab() {
    val vm: PracticeViewModel = viewModel(
        factory = remember { vmFactory { PracticeViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    val mic = rememberMicPermission()

    // 每次进入组合（从句子列表返回 / 从诊断页切进来）读取跨页参数
    LaunchedEffect(Unit) { vm.syncFromNavParams() }

    // 离开 Tab / push 二级页：停录音与播放（照抄 hos aboutToDisappear）
    DisposableEffect(Unit) {
        onDispose { vm.onLeaveUi() }
    }

    // 首次点录音 / 「跟我读」自动开录：VM 标记 → 页面申请权限 → 授权后自动开始
    LaunchedEffect(state.micPermissionRequest) {
        if (state.micPermissionRequest) {
            vm.onMicRequestLaunched()
            mic.request()
        }
    }
    LaunchedEffect(mic.granted) {
        if (mic.granted) vm.onMicPermissionGranted()
    }

    // 全屏结果页打开时，系统返回键先关 overlay（不直接退出页面）
    BackHandler(enabled = state.overlayVisible) { vm.closeOverlay() }

    Box(modifier = Modifier.fillMaxSize().background(EcColor.bg)) {
        Column(modifier = Modifier.fillMaxSize()) {
            PracticeHeader(
                state = state,
                isChild = isChild,
                onSelectLevel = vm::selectLevel,
                onClearFocus = vm::clearFocus,
                onReload = vm::reload,
            )

            PracticeStatusBanners(state = state, isChild = isChild, vm = vm)

            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                when {
                    state.loading && state.sentences.isEmpty() -> LoadingBlock(text = "正在取句子…")

                    state.sentences.isEmpty() && state.error != null -> Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = EcSpace.x4, vertical = EcSpace.x3),
                    ) {
                        ErrorBanner(error = state.error, onRetry = vm::reload)
                    }

                    state.sentences.isEmpty() -> EmptyState(
                        icon = "📚",
                        message = if (isChild) "这个等级还没有句子，换一个等级看看吧" else "这个等级还没有句子，换一个等级试试",
                        actionLabel = "换个等级",
                        onAction = { vm.selectLevel(if (state.level == "A1") "A2" else "A1") },
                    )

                    else -> PracticePager(state = state, isChild = isChild, vm = vm)
                }
            }

            PracticeSentenceBar(state = state, isChild = isChild, vm = vm)
        }

        // 全屏结果页（页内 overlay，不新增路由）：覆盖整个 Tab 内容
        val result = state.result
        if (state.overlayVisible && result != null) {
            ResultOverlay(state = state, result = result, isChild = isChild, vm = vm)
        }
    }
}

// ---------------------------------------------------------------------------
// 页头：问候 / 用量 / 专项 / 等级
// ---------------------------------------------------------------------------

@Composable
private fun PracticeHeader(
    state: PracticeUiState,
    isChild: Boolean,
    onSelectLevel: (String) -> Unit,
    onClearFocus: () -> Unit,
    onReload: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                start = EcSpace.x4,
                end = EcSpace.x4,
                top = EcSpace.x4,
                bottom = EcSpace.x2,
            ),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
            ) {
                Text(
                    text = if (state.displayName.isNotEmpty()) "你好，${state.displayName}" else "你好",
                    fontSize = if (isChild) EcFont.childH1 else EcFont.h2,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                Text(
                    text = usageText(state),
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
            }
            Text(
                text = if (state.total > 0) "${state.index + 1} / ${state.total}" else "",
                fontSize = EcFont.caption,
                color = EcColor.muted,
                textAlign = TextAlign.End,
            )
        }

        // 诊断页「专项练习」：按 focus 音素过滤
        if (state.focusToken.isNotEmpty()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcPill(
                    text = if (isChild) "专项练习" else "专项练习 · ${state.focusToken}",
                    tone = PillTone.INFO,
                )
                Text(
                    text = "练这个音素的句子",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "退出专项",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(onClick = onClearFocus)
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x2),
                )
            }
        }

        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                state.levels.forEach { level ->
                    EcChip(
                        label = level,
                        selected = state.level == level,
                        onClick = { onSelectLevel(level) },
                    )
                }
            }
            Text(
                text = "↻ 换一批",
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(onClick = onReload)
                    .padding(start = EcSpace.x2, top = EcSpace.x2, bottom = EcSpace.x2, end = EcSpace.x1),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// 顶部状态条：刷新中 / 额度 / 继续上次 / 读完提示 / 待补评分
// ---------------------------------------------------------------------------

@Composable
private fun PracticeStatusBanners(
    state: PracticeUiState,
    isChild: Boolean,
    vm: PracticeViewModel,
) {
    val hasAny = state.refreshing ||
        state.limitReached ||
        state.resumeIndex > 0 ||
        state.notice != null ||
        state.pendingSaved
    if (!hasAny) return
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = EcSpace.x4, end = EcSpace.x4, bottom = EcSpace.x2),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        if (state.refreshing) {
            Text(text = "正在更新句子…", fontSize = EcFont.micro, color = EcColor.muted)
        }

        // 今日额度用完（429 / daily_limit_reached）：提示剩余时长并禁用录音
        if (state.limitReached) {
            EcInlineNotice(
                text = state.quotaText ?: if (isChild) {
                    "今天已经练得很棒啦，明天再来 🌙"
                } else {
                    "今天的练习时长用完了（今日 ${state.minutesToday} / ${state.dailyLimitMinutes} 分钟，剩余 ${state.remainingMinutes} 分钟），明天再来吧"
                },
                tone = PillTone.WARN,
            )
        }

        // 上次练到第 N 句（练习游标，线上没有 /practice/cursor）
        if (state.resumeIndex > 0) {
            ResumeBanner(state = state, vm = vm)
        }

        state.notice?.let { notice ->
            NoticeBanner(text = notice, onDismiss = vm::dismissNotice, onRestart = vm::startFromBeginning)
        }

        // 离线能力：提交失败已入队 → 提示 + 「去补评分」入口（ROUND2 §1.3）
        val pendingNotice = state.pendingNotice
        if (state.pendingSaved && pendingNotice != null) {
            PendingBanner(text = pendingNotice)
        }
    }
}

@Composable
private fun PendingBanner(text: String) {
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
        EcInlineNotice(text = text, tone = PillTone.INFO)
        EcButton(
            label = "去补评分",
            onClick = { Navigator.navigate(Routes.PENDING_UPLOADS) },
            kind = EcButtonKind.SECONDARY,
            size = EcButtonSizeKind.MD,
            fullWidth = true,
        )
    }
}

@Composable
private fun ResumeBanner(state: PracticeUiState, vm: PracticeViewModel) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.primarySoft)
            .padding(horizontal = EcSpace.x3, vertical = EcSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = "上次练到第 ${state.resumeIndex + 1} 句（共 ${state.total} 句）",
            fontSize = EcFont.caption,
            color = EcColor.ink,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = "▶ 继续上次",
            fontSize = EcFont.caption,
            color = EcColor.primary,
            modifier = Modifier
                .clickable(onClick = vm::resumeFromBanner)
                .padding(horizontal = EcSpace.x1, vertical = EcSpace.x1),
        )
        Text(
            text = "从头开始",
            fontSize = EcFont.micro,
            color = EcColor.muted,
            modifier = Modifier
                .clickable(onClick = vm::startFromBeginning)
                .padding(horizontal = EcSpace.x1, vertical = EcSpace.x1),
        )
    }
}

@Composable
private fun NoticeBanner(text: String, onDismiss: () -> Unit, onRestart: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.surfaceAlt)
            .padding(horizontal = EcSpace.x3, vertical = EcSpace.x2),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
            Text(
                text = "🌱 $text",
                fontSize = EcFont.caption,
                color = EcColor.ink,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "✕",
                fontSize = EcFont.caption,
                color = EcColor.muted,
                modifier = Modifier.clickable(onClick = onDismiss).padding(EcSpace.x1),
            )
        }
        EcButton(
            label = "从第一句再读一遍",
            onClick = onRestart,
            kind = EcButtonKind.SECONDARY,
            size = EcButtonSizeKind.MD,
        )
    }
}

// ---------------------------------------------------------------------------
// 句子卡片流：HorizontalPager 左右滑动切句
// ---------------------------------------------------------------------------

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PracticePager(
    state: PracticeUiState,
    isChild: Boolean,
    vm: PracticeViewModel,
) {
    val initialPage = state.index.coerceIn(0, (state.sentences.size - 1).coerceAtLeast(0))
    val pagerState = rememberPagerState(initialPage = initialPage, pageCount = { state.sentences.size })

    // VM 索引变化（上一句/下一句按钮、句子列表选句、游标）→ 同步 Pager
    LaunchedEffect(state.index, state.sentences.size) {
        if (state.sentences.isEmpty()) return@LaunchedEffect
        val target = state.index.coerceIn(0, state.sentences.size - 1)
        if (pagerState.currentPage != target) pagerState.animateScrollToPage(target)
    }

    // 手势翻页落定 → 同步当前句/游标（并清空上一句的结果，见 onPageSettled 注释）
    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.currentPage to pagerState.isScrollInProgress }
            .collect { (page, scrolling) ->
                if (!scrolling) vm.onPageSettled(page)
            }
    }

    HorizontalPager(
        state = pagerState,
        modifier = Modifier.fillMaxSize(),
        // 录音/提交中禁止滑动（避免误翻页打断录音）；显示结果时允许滑动，落定即关结果并换句
        userScrollEnabled = !state.busy && !state.ttsLoading,
        key = { page -> state.sentences.getOrNull(page)?.id ?: page },
    ) { page ->
        PracticeSentencePage(state = state, page = page, isChild = isChild, vm = vm)
    }
}

@Composable
private fun PracticeSentencePage(
    state: PracticeUiState,
    page: Int,
    isChild: Boolean,
    vm: PracticeViewModel,
) {
    val sentence = state.sentences.getOrNull(page) ?: return
    val isCurrentPage = page == state.index
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(start = EcSpace.x4, end = EcSpace.x4, bottom = EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
    ) {
        SentenceCard(
            state = state,
            sentence = sentence,
            isChild = isChild,
            vm = vm,
            isCurrentPage = isCurrentPage,
        )
        if (isCurrentPage) {
            ResultSection(state = state, isChild = isChild, vm = vm)
        }
    }
}

@Composable
private fun SentenceCard(
    state: PracticeUiState,
    sentence: PracticeSentenceUi,
    isChild: Boolean,
    vm: PracticeViewModel,
    isCurrentPage: Boolean,
) {
    EcCard(modifier = Modifier.fillMaxWidth()) {
        // 等级 / focus / 状态标签（儿童不显示音素；非当前页不显示状态）
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcPill(text = sentence.level.ifEmpty { state.level }, tone = PillTone.INFO)
            if (!isChild) {
                sentence.focusPhonemes.take(2).forEach { phoneme -> EcPill(text = phoneme, tone = PillTone.NEUTRAL) }
                sentence.tags.take(2).forEach { tag -> EcPill(text = tag, tone = PillTone.NEUTRAL) }
            }
            Spacer(modifier = Modifier.weight(1f))
            if (isCurrentPage) {
                when {
                    state.recording -> EcPill(text = "录音中", tone = PillTone.WARN)
                    state.result?.noSpeech == false -> EcPill(text = "已评分", tone = PillTone.GOOD)
                }
            }
        }

        // 英文大字（成人 22sp / 儿童 24sp；儿童不显示可点 IPA 下划线）
        Text(
            text = sentence.text,
            fontSize = if (isChild) EcFont.h2 else EcFont.sentence,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        if (sentence.translation.isNotEmpty()) {
            Text(
                text = sentence.translation,
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
        }

        // 播放 / 跟我读 / 说完啦
        if (state.recording && isCurrentPage) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "⏹ 说完啦 ${(state.elapsedMs / 1000).toInt()}s",
                    onClick = vm::stopRecordingAndSubmit,
                    kind = EcButtonKind.DANGER,
                    size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                    enabled = !state.submitting,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = "✖️ 不要了",
                    onClick = vm::cancelRecording,
                    kind = EcButtonKind.GHOST,
                    size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                    enabled = !state.submitting,
                    modifier = Modifier.weight(1f),
                )
            }
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = when {
                        isCurrentPage && state.ttsLoading -> "准备中…"
                        isCurrentPage && state.playing -> "播放中…"
                        else -> "🔊 听示范"
                    },
                    onClick = { vm.playDemo(autoRecord = false) },
                    kind = EcButtonKind.SECONDARY,
                    size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                    loading = state.ttsLoading,
                    // 播放中也允许点：重复点先停再播（screens.md §3 交互 4）
                    enabled = isCurrentPage && !state.busy && !state.ttsLoading,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = "🎧 跟我读",
                    onClick = { vm.playDemo(autoRecord = true) },
                    kind = EcButtonKind.SECONDARY,
                    size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                    enabled = isCurrentPage && !state.busy && !state.limitReached && !state.ttsLoading,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        // 录音主按钮（点一下开始/结束；首次点才申请麦克风权限）
        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            RecordButton(
                recording = state.recording,
                enabled = isCurrentPage && !state.submitting && !state.preparing && !state.limitReached,
                isChild = isChild,
                onClick = {
                    if (state.recording) vm.stopRecordingAndSubmit() else vm.startRecording()
                },
                label = when {
                    state.recording -> "正在听你说…读完点一下停止"
                    state.playing -> "示范播放中，听完会自动开始录音"
                    isCurrentPage -> "点一下开始说，也可以左右滑动换一句"
                    else -> "左右滑动切换句子"
                },
            )
        }

        // 提交进度：按耗时切换文案，不显示假百分比（只在当前页显示，避免相邻页重复）
        if (isCurrentPage && state.submitting) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    color = EcColor.primary,
                    strokeWidth = 2.dp,
                )
                Text(
                    text = state.progressText.ifEmpty { "提交中…" },
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                )
            }
        }

        // 麦克风被拒 / 播放失败 / 评测失败：可见 + 可重试（只在当前页）
        if (isCurrentPage) {
            ErrorBanner(
                error = state.error,
                onRetry = if (state.error?.retryable == true || state.error?.code == ApiErrorCode.MIC_DENIED) {
                    vm::onErrorAction
                } else if (state.canRetryEvaluate) {
                    vm::retryEvaluate
                } else {
                    null
                },
                onDismiss = vm::dismissError,
            )

            // degraded：录音已保存，评测服务暂时不可用 → 重试评测（不重录）
            state.degradedNotice?.let { notice ->
                Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
                    EcInlineNotice(text = notice, tone = PillTone.WARN)
                    if (state.canRetryEvaluate) {
                        EcButton(
                            label = "重试评测",
                            onClick = vm::retryEvaluate,
                            kind = EcButtonKind.SECONDARY,
                            loading = state.submitting,
                            enabled = !state.recording,
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 结果区（页内）
// ---------------------------------------------------------------------------

@Composable
private fun ResultSection(
    state: PracticeUiState,
    isChild: Boolean,
    vm: PracticeViewModel,
) {
    val result = state.result ?: return
    EcCard(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "本次结果",
            fontSize = EcFont.h3,
            fontWeight = FontWeight.SemiBold,
            color = EcColor.ink,
        )

        if (result.noSpeech) {
            // 空识别：显示「没听到你的声音」，不显示 0 分（screens.md §3）
            EcInlineNotice(
                text = if (isChild) "没听到你的声音，靠近一点再读一遍吧" else "没听到你的声音，可能是麦克风没收到，靠近一点再读一遍",
                tone = PillTone.WARN,
            )
        } else {
            ScoreSummaryBlock(result = result, isChild = isChild)
        }

        // 能力雷达（成人；儿童只显示星级/鼓励，不显示雷达）
        result.radar?.let { radar -> RadarBlock(radar = radar, isChild = isChild) }

        RecognizedBlock(result = result, isChild = isChild)
        WordBlocks(result = result, isChild = isChild)
        FeedbackTextBlock(result = result)
        CorrectionCardsBlock(result = result, isChild = isChild)
        result.intonation?.let { intonation -> IntonationBlock(intonation = intonation) }
        HistoryBlock(state = state, isChild = isChild, vm = vm)

        // 回放 + 历史 + 完整结果
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = if (state.playingRecording) "播放中…" else "🔁 回放",
                onClick = vm::playRecording,
                kind = EcButtonKind.GHOST,
                enabled = !state.recording && !state.submitting,
                modifier = Modifier.weight(1f),
            )
            EcButton(
                label = if (state.historyLoading) "读取中…" else "📈 历史",
                onClick = vm::refreshHistory,
                kind = EcButtonKind.GHOST,
                enabled = !state.historyLoading && !state.recording,
                modifier = Modifier.weight(1f),
            )
        }
        EcButton(
            label = "查看完整结果",
            onClick = vm::openOverlay,
            kind = EcButtonKind.SECONDARY,
            fullWidth = true,
        )
        if (state.canRetryEvaluate) {
            EcButton(
                label = "重试评测",
                onClick = vm::retryEvaluate,
                kind = EcButtonKind.PRIMARY,
                loading = state.submitting,
                fullWidth = true,
            )
        } else {
            EcButton(
                label = "下一句 →",
                onClick = vm::nextSentence,
                kind = EcButtonKind.PRIMARY,
                fullWidth = true,
                enabled = !state.busy,
            )
        }
        if (!isChild && result.metaText.isNotEmpty()) {
            Text(text = result.metaText, fontSize = EcFont.micro, color = EcColor.muted)
        }
    }
}

// ---------------------------------------------------------------------------
// 全屏结果页（页内 overlay，覆盖整个 Tab；返回键关闭）
// ---------------------------------------------------------------------------

@Composable
private fun ResultOverlay(
    state: PracticeUiState,
    result: PracticeResultUi,
    isChild: Boolean,
    vm: PracticeViewModel,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(EcColor.bg)
            // Tab 内容本身已在安全区内；再显式声明一次，单独预览/嵌入时不顶到状态栏
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = EcSpace.x4, vertical = EcSpace.x3),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "完整结果",
                    fontSize = EcFont.h3,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "✕ 关闭",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(onClick = vm::closeOverlay)
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
                )
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = EcSpace.x4),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
            ) {
                if (result.noSpeech) {
                    EcInlineNotice(
                        text = if (isChild) "没听到你的声音，靠近一点再读一遍吧" else "没听到你的声音，可能是麦克风没收到，靠近一点再读一遍",
                        tone = PillTone.WARN,
                    )
                } else {
                    ScoreSummaryBlock(result = result, isChild = isChild)
                }
                result.radar?.let { radar -> RadarBlock(radar = radar, isChild = isChild) }
                RecognizedBlock(result = result, isChild = isChild)
                WordBlocks(result = result, isChild = isChild)
                FeedbackTextBlock(result = result)
                CorrectionCardsBlock(result = result, isChild = isChild)
                result.intonation?.let { intonation -> IntonationBlock(intonation = intonation) }
                HistoryBlock(state = state, isChild = isChild, vm = vm)
                if (!isChild && result.metaText.isNotEmpty()) {
                    Text(text = result.metaText, fontSize = EcFont.micro, color = EcColor.muted)
                }
                if (!isChild && result.words.isEmpty() && result.cards.isEmpty() &&
                    result.intonation == null && state.history == null
                ) {
                    Text(
                        text = "这次没有更细的问题，整体表现不错。",
                        fontSize = EcFont.caption,
                        color = EcColor.muted,
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = EcSpace.x4, vertical = EcSpace.x3),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                EcButton(
                    label = if (state.playingRecording) "播放中…" else "🔁 回放",
                    onClick = vm::playRecording,
                    kind = EcButtonKind.GHOST,
                    enabled = !state.recording && !state.submitting,
                    modifier = Modifier.weight(1f),
                )
                if (state.canRetryEvaluate) {
                    EcButton(
                        label = "重试评测",
                        onClick = vm::retryEvaluate,
                        kind = EcButtonKind.SECONDARY,
                        loading = state.submitting,
                        modifier = Modifier.weight(1f),
                    )
                }
                EcButton(
                    label = "下一句 →",
                    onClick = {
                        vm.closeOverlay()
                        vm.nextSentence()
                    },
                    kind = EcButtonKind.PRIMARY,
                    enabled = !state.busy,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 结果子块（页内结果 & 全屏结果共用）
// ---------------------------------------------------------------------------

/** 总分环 + 子项条 + 一句鼓励。 */
@Composable
private fun ScoreSummaryBlock(result: PracticeResultUi, isChild: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x4),
        ) {
            ScoreBadge(
                score = result.pron,
                isChild = isChild,
                label = if (EcScore.showNumber(result.pron, isChild)) "总分" else "继续加油",
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
            ) {
                SubScoreRow(items = subScoreItems(result), isChild = isChild)
            }
        }
        Text(
            text = EcScore.encouragement(result.pron, isChild),
            fontSize = if (isChild) EcFont.childBody else EcFont.body,
            color = EcColor.ink,
        )
        // 儿童只看星级/鼓励（不显示雷达与低分数字，screens.md §0）
        if (isChild) {
            Text(text = EcScore.stars(result.pron), fontSize = EcFont.h3)
        }
    }
}

/** 能力雷达图（成人）：准确/流利/完整/语调/总分，缺失项由组件按空值处理。 */
@Composable
private fun RadarBlock(radar: RadarUi, isChild: Boolean) {
    if (isChild) return
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
        Text(text = "能力分布", fontSize = EcFont.caption, color = EcColor.muted)
        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            EcRadarChart(
                labels = radar.labels,
                values = radar.values,
                color = EcColor.primary,
            )
        }
    }
}

/** 识别文本（成人；可点单词看音标）。儿童不显示识别文本。 */
@Composable
private fun RecognizedBlock(result: PracticeResultUi, isChild: Boolean) {
    if (isChild || result.recognizedText.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
        Text(text = "我听到的是：", fontSize = EcFont.caption, color = EcColor.muted)
        WordText(text = result.recognizedText, isChild = false)
    }
}

/** 逐词评分 + 建议多练的词（成人）。 */
@Composable
private fun WordBlocks(result: PracticeResultUi, isChild: Boolean) {
    if (isChild) return
    if (result.words.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            Text(text = "逐词评分", fontSize = EcFont.caption, color = EcColor.muted)
            WordChips(words = result.words, isChild = isChild)
        }
    }
    if (result.worstWords.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            Text(text = "建议多练的词", fontSize = EcFont.caption, color = EcColor.warnText)
            WordChips(words = result.worstWords, isChild = isChild)
        }
    }
}

/** 整体点评文字（summary / praise / closing）。 */
@Composable
private fun FeedbackTextBlock(result: PracticeResultUi) {
    if (result.feedbackSummary.isNotEmpty()) {
        Text(text = result.feedbackSummary, fontSize = EcFont.body, color = EcColor.ink)
    }
    if (result.feedbackPraise.isNotEmpty()) {
        Text(text = "👍 ${result.feedbackPraise}", fontSize = EcFont.caption, color = EcColor.goodText)
    }
    if (result.feedbackClosing.isNotEmpty()) {
        Text(text = result.feedbackClosing, fontSize = EcFont.caption, color = EcColor.muted)
    }
}

/** 纠错 / 建议卡片（成人最多 2 条；儿童 1 条温和版）。 */
@Composable
private fun CorrectionCardsBlock(result: PracticeResultUi, isChild: Boolean) {
    if (result.cards.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
        Text(
            text = if (isChild) "再练一下就更好啦" else "怎么练更好",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        result.cards.forEach { card -> CorrectionCard(card = card, isChild = isChild) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WordChips(words: List<WordScoreUi>, isChild: Boolean) {
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
    ) {
        words.forEach { word ->
            ScoreChip(
                score = word.score,
                isChild = isChild,
                text = "${word.word} ${scoreText(word.score)}",
            )
        }
    }
}

@Composable
private fun CorrectionCard(card: CorrectionCardUi, isChild: Boolean) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(if (isChild) EcColor.primarySoft else EcColor.warnBg)
            .padding(EcSpace.x3),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = card.title,
                fontSize = EcFont.caption,
                fontWeight = FontWeight.Medium,
                color = if (isChild) EcColor.primary else EcColor.warnText,
                modifier = Modifier.weight(1f),
            )
            if (!isChild && card.score != null) {
                Text(
                    text = "${scoreText(card.score)} 分",
                    fontSize = EcFont.caption,
                    fontWeight = FontWeight.Medium,
                    color = EcScore.color(card.score, isChild),
                )
            }
        }
        if (!isChild && card.word.isNotEmpty()) {
            Text(
                text = "单词：${card.word}" +
                    (if (card.expected.isNotEmpty()) " · 音素 ${card.expected}" else "") +
                    (if (card.actual.isNotEmpty()) " → 实际读成 ${card.actual}" else ""),
                fontSize = EcFont.micro,
                color = EcColor.ink,
            )
        }
        if (!isChild && card.why.isNotEmpty()) {
            Text(text = "为什么：${card.why}", fontSize = EcFont.micro, color = EcColor.muted)
        }
        if (card.how.isNotEmpty()) {
            Text(text = "怎么改：${card.how}", fontSize = EcFont.micro, color = EcColor.muted)
        }
        if (card.practiceWords.isNotEmpty()) {
            Text(text = "练习词：${card.practiceWords}", fontSize = EcFont.micro, color = EcColor.primary)
        }
    }
}

@Composable
private fun IntonationBlock(intonation: IntonationUi) {
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = "语调曲线", fontSize = EcFont.caption, color = EcColor.muted)
            if (intonation.distanceText.isNotEmpty()) {
                Text(
                    text = "差距 ${intonation.distanceText}（越小越接近）",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            Text(text = "— 你　— 示范", fontSize = EcFont.micro, color = EcColor.muted)
        }
        EcLineChart(
            series = listOf(intonation.userF0, intonation.refF0),
            colors = listOf(EcColor.primary, EcColor.muted),
            minY = intonation.minY,
            maxY = intonation.maxY,
        )
        intonation.regionTexts.forEach { text ->
            Text(text = "· $text", fontSize = EcFont.micro, color = EcColor.warnText)
        }
    }
}

/**
 * 单句历史：
 * - 成人：进步趋势图 + 首末对比 + 逐条记录（可回放）；
 * - 儿童：只有逐条记录（▶ 回放），**不显示分数/趋势**（ROUND2 §4 ③）。
 */
@Composable
private fun HistoryBlock(state: PracticeUiState, isChild: Boolean, vm: PracticeViewModel) {
    val history = state.history ?: return
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
        Text(
            text = when {
                isChild -> "这一句的朗读记录（${history.items.size} 次）"
                history.scores.isNotEmpty() -> "这一句的进步（最近 ${history.scores.size} 次）"
                else -> "这一句的历史记录（${history.items.size} 次）"
            },
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )

        if (!isChild && history.scores.isNotEmpty()) {
            EcTrendChart(points = history.scores, labels = history.labels)
            val first = history.first
            val last = history.last
            val delta = history.delta
            if (first != null && last != null) {
                Text(
                    text = "首末对比：${first.toInt()} → ${last.toInt()}（${if (delta != null && delta >= 0) "+" else ""}${delta?.let { (it * 10).toInt() / 10.0 } ?: "—"}）",
                    fontSize = EcFont.caption,
                    color = if (delta != null && delta >= 0) EcColor.goodText else EcColor.badText,
                )
            }
        }

        if (history.items.isNotEmpty()) {
            Text(
                text = if (isChild) "点一下可以再听一遍" else "逐次记录（新→旧，可回放）",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
            history.items.asReversed().forEach { item ->
                HistoryRow(
                    item = item,
                    isChild = isChild,
                    playing = state.playingHistoryId == item.attemptId,
                    onPlay = { vm.playHistoryAudio(item) },
                )
            }
        }
    }
}

@Composable
private fun HistoryRow(
    item: HistoryItemUi,
    isChild: Boolean,
    playing: Boolean,
    onPlay: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = EcSpace.x1),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(text = item.label, fontSize = EcFont.micro, color = EcColor.muted)
        if (!isChild && item.score != null) {
            Text(
                text = scoreText(item.score),
                fontSize = EcFont.caption,
                fontWeight = FontWeight.Medium,
                color = EcScore.color(item.score, isChild),
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        if (item.audioUrl.isNotEmpty()) {
            Text(
                text = if (playing) "播放中…" else "▶ 回放",
                fontSize = EcFont.caption,
                color = if (playing) EcColor.muted else EcColor.primary,
                modifier = Modifier
                    .clickable(enabled = !playing, onClick = onPlay)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x2),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// 底部：上一句 / 句子列表 / 下一句
// ---------------------------------------------------------------------------

@Composable
private fun PracticeSentenceBar(
    state: PracticeUiState,
    isChild: Boolean,
    vm: PracticeViewModel,
) {
    // 成人按钮 48dp、儿童 60dp（CONTRACT §4：所有按钮点击区 ≥48dp）
    val buttonSize = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(EcColor.bg)
            .padding(horizontal = EcSpace.x4, vertical = EcSpace.x2),
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        EcButton(
            label = "‹ 上一句",
            onClick = vm::previousSentence,
            kind = EcButtonKind.GHOST,
            size = buttonSize,
            enabled = (state.current?.hasPrev == true) && !state.busy,
            modifier = Modifier.weight(1f),
        )
        EcButton(
            label = "📚 列表",
            onClick = {
                // 句子列表默认展示当前练习等级；选中后由列表写回 practiceSentenceId
                NavParams.practiceLevel = state.level
                Navigator.navigate(Routes.SENTENCES)
            },
            kind = EcButtonKind.GHOST,
            size = buttonSize,
            enabled = !state.busy,
            modifier = Modifier.weight(1f),
        )
        EcButton(
            label = "下一句 ›",
            onClick = vm::nextSentence,
            kind = EcButtonKind.SECONDARY,
            size = buttonSize,
            enabled = state.total > 0 && !state.busy,
            modifier = Modifier.weight(1f),
        )
    }
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

/** 今日用量文案（照抄 hos PracticePage.usageText）。 */
private fun usageText(state: PracticeUiState): String {
    if (state.minutesToday <= 0) return "今天还没有开始练"
    return "今天已练 ${state.minutesToday} / ${state.dailyLimitMinutes} 分钟"
}

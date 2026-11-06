package top.dreamsearch.englishcoach.ui.page.stats

import android.os.SystemClock
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import top.dreamsearch.englishcoach.core.audio.AudioController
import top.dreamsearch.englishcoach.core.audio.rememberMicPermission
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcDialog
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcTrendChart
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RecordButton
import top.dreamsearch.englishcoach.ui.component.WordText
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcScore
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 盲测（`/api/blind-tests`）：Intro → Running（本页直接录音提交）→ Finish 一页闭环。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/pages/BlindTestPage.ets`（hos 只在跟读页录音，
 * 本页只做批次与周报）；本端按任务要求把「录音 → 异步提交 → 进度轮询」并入 Running 阶段。
 *
 * 防作弊硬规则（.specs/practice-flow.md §6.3）：
 * - Running 全程**不显示任何分数**：只展示「第 N/M 句 + 已提交/已评分计数」；
 * - 提交走 `PracticeService.evaluate(...)`（同步 `POST /attempts`，multipart 带 `blind_test_id`），
 *   响应只有 attempt_id/blind/progress，绝不读分数；
 * - 没有「重试评测」入口（服务端对盲测记录返回 409）；
 * - Finish 后才显示 `avg_pron`，`pending>0` 必须提示「还有 N 条在后台评分」。
 *
 * 儿童：Running 零分数；Finish 只显示完成次数 / 星星 / 比上次棒，不显示低分数字。
 */
@Composable
fun BlindTestScreen(onBack: () -> Unit) {
    val vm: BlindTestViewModel = viewModel(
        factory = remember { vmFactory { BlindTestViewModel(AppGraph.container) } }
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val session by AppGraph.session.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    // 限额前置（CONTRACT §6.4）：今日时长用完时禁用录音/开始，并提示剩余时长
    val exceeded = session.exceeded
    val remainingMinutes = session.remainingMinutes.coerceAtLeast(0)

    val audio = AppGraph.container.audio
    val recording by audio.recording.collectAsStateWithLifecycle()
    val mic = rememberMicPermission()

    var recordSeconds by remember { mutableIntStateOf(0) }
    var localError by remember { mutableStateOf<UiError?>(null) }
    var confirmFinish by remember { mutableStateOf(false) }

    // 录音计时：最长 60s 自动停止；停止后直接把文件交给 VM 异步提交。
    LaunchedEffect(recording) {
        if (!recording) {
            recordSeconds = 0
            return@LaunchedEffect
        }
        val startedAt = SystemClock.elapsedRealtime()
        while (isActive) {
            delay(TICK_MS)
            val elapsed = SystemClock.elapsedRealtime() - startedAt
            recordSeconds = (elapsed / 1000L).toInt()
            if (elapsed >= AudioController.MAX_DURATION_MS) {
                runCatching {
                    val result = audio.stopRecording()
                    vm.submitRecording(result.file, result.durationMs)
                }.onFailure { e -> localError = AppGraph.session.toUiError(e) }
                break
            }
        }
    }

    // 页面销毁：丢弃未完成的录音、停播放、取消进度轮询（任务要求：离开取消）。
    DisposableEffect(Unit) {
        onDispose {
            audio.cancelRecording()
            audio.stopPlayback()
            vm.stopPolling()
        }
    }
    LaunchedEffect(state.phase) {
        if (state.phase != BlindPhase.RUNNING) {
            audio.cancelRecording()
            recordSeconds = 0
        }
    }

    val handleBack: () -> Unit = {
        audio.cancelRecording()
        vm.stopPolling()
        onBack()
    }

    // 录音主按钮：未授权时先申请（第一次点才弹系统框），拒绝则展示错误文案。
    val onRecordClick: () -> Unit = {
        when {
            state.submitting || state.allSubmitted -> Unit

            recording -> {
                try {
                    val result = audio.stopRecording()
                    recordSeconds = 0
                    vm.submitRecording(result.file, result.durationMs)
                } catch (e: Throwable) {
                    localError = AppGraph.session.toUiError(e)
                }
            }

            else -> {
                if (!mic.granted) {
                    mic.request()
                    localError = UiError.of(
                        ApiErrorCode.MIC_DENIED,
                        if (isChild) "要听到你的声音，需要打开麦克风，再点一次录音吧" else "需要麦克风才能录音，请允许后再点一次",
                        false,
                    )
                } else {
                    try {
                        audio.startRecording(prefix = "blind")
                        recordSeconds = 0
                        localError = null
                    } catch (e: Throwable) {
                        localError = AppGraph.session.toUiError(e)
                    }
                }
            }
        }
    }

    PageScaffold(
        title = if (isChild) "小测验" else "盲测",
        onBack = handleBack,
        scrollable = true,
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(padding)
                .padding(horizontal = EcSpace.x4, vertical = EcSpace.x4),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            when (state.phase) {
                BlindPhase.INTRO -> BlindIntroContent(
                    state = state,
                    isChild = isChild,
                    exceeded = exceeded,
                    remainingMinutes = remainingMinutes,
                    dateLabel = vm::dateLabel,
                    onRetryLoad = vm::load,
                    onStart = vm::start,
                    onContinue = vm::continueRun,
                    onDismissStartError = vm::dismissStartError,
                )

                BlindPhase.RUNNING -> BlindRunningContent(
                    state = state,
                    isChild = isChild,
                    exceeded = exceeded,
                    remainingMinutes = remainingMinutes,
                    recording = recording,
                    recordSeconds = recordSeconds,
                    localError = localError,
                    onRecordClick = onRecordClick,
                    onDismissLocalError = { localError = null },
                    onDismissSubmitError = vm::dismissSubmitError,
                    onSkip = vm::skipCurrent,
                    onFinish = {
                        if (state.pending > 0) confirmFinish = true else vm.finish()
                    },
                    onRetryFinish = vm::finish,
                    onDismissFinishError = vm::dismissFinishError,
                )

                BlindPhase.FINISH -> BlindFinishContent(
                    state = state,
                    isChild = isChild,
                    dateLabel = vm::dateLabel,
                    scoreText = vm::formatScore,
                    deltaText = vm::deltaText,
                    onRestart = vm::start,
                    onBack = handleBack,
                    onRetryFinish = vm::finish,
                    onDismissFinishError = vm::dismissFinishError,
                )
            }
        }
    }

    if (confirmFinish) {
        EcDialog(title = "现在结束吗？", onDismiss = { confirmFinish = false }) {
            Text(
                text = "还有 ${state.pending} 条在后台评分，报告里会显示为「待评分」，不影响已评完的平均分。",
                fontSize = EcFont.caption,
                color = EcColor.ink,
            )
            EcButton(
                label = "结束并查看周报",
                onClick = {
                    confirmFinish = false
                    vm.finish()
                },
                fullWidth = true,
            )
            EcButton(
                label = "再等等",
                onClick = { confirmFinish = false },
                kind = EcButtonKind.GHOST,
                fullWidth = true,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Intro
// ---------------------------------------------------------------------------

@Composable
private fun BlindIntroContent(
    state: BlindTestUiState,
    isChild: Boolean,
    exceeded: Boolean,
    remainingMinutes: Int,
    dateLabel: (String?) -> String,
    onRetryLoad: () -> Unit,
    onStart: () -> Unit,
    onContinue: () -> Unit,
    onDismissStartError: () -> Unit,
) {
    StatCard {
        Text(
            text = if (isChild) "🎯 小测验（不给分数哦）" else "🎯 盲测（Blind Test）",
            fontSize = if (isChild) EcFont.childH1 else EcFont.h2,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Text(
            text = if (isChild) {
                "同一组句子、全程不给分数，做完才看得到结果 —— 这样才测得准 🙂"
            } else {
                "同一组句子、全程不给任何反馈，和上一次的成绩对比 —— 这是唯一能证明「真的进步了」的指标。"
            },
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        if (state.pendingTotal > 0) {
            EcInlineNotice(
                text = "⏳ 还有 ${state.pendingTotal} 条暂时显示为待评分（后台评分中…），报告里的平均分只基于已评完的记录",
                tone = PillTone.WARN,
            )
        }
    }

    state.error?.let { error ->
        ErrorBanner(error = error, onRetry = onRetryLoad)
    }
    state.startError?.let { error ->
        ErrorBanner(error = error, onRetry = onStart, onDismiss = onDismissStartError)
    }
    if (exceeded) {
        EcInlineNotice(
            text = if (isChild) {
                "今天已经练得很棒啦，还剩 $remainingMinutes 分钟，明天再来 🌙"
            } else {
                "今天的练习时长已达上限（剩余 $remainingMinutes 分钟），明天再来"
            },
            tone = PillTone.WARN,
        )
    }

    when {
        state.loading && !state.loadedOnce -> LoadingBlock(text = "正在取盲测记录…")

        state.error != null && !state.loadedOnce -> Unit

        else -> {
            if (state.tests.isEmpty() && state.inProgress == null) {
                EmptyState(
                    icon = "🎯",
                    message = if (isChild) {
                        "还没有做过小测验。先去读几句，再来试试"
                    } else {
                        "还没有完成过盲测。先做一次，下次再做一次，就能看到「到底有没有变好」了"
                    },
                )
            }

            StatCard {
                val progress = state.inProgress
                if (progress != null) {
                    Text(
                        text = "🎯 盲测进行中",
                        fontSize = EcFont.body,
                        fontWeight = FontWeight.Bold,
                        color = EcColor.ink,
                    )
                    Text(
                        text = "已提交 ${progress.scored + progress.pending} / ${progress.itemCount} 句 · " +
                            "已评分 ${progress.scored} 句",
                        fontSize = EcFont.caption,
                        color = EcColor.muted,
                    )
                    Text(
                        text = "这一轮不会有任何分数和反馈，读完才看得到结果。",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                    EcButton(
                        label = "继续这次盲测",
                        onClick = onContinue,
                        enabled = !exceeded,
                        size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                        fullWidth = true,
                    )
                } else {
                    EcButton(
                        label = "开始盲测",
                        onClick = onStart,
                        enabled = !exceeded,
                        loading = state.starting,
                        size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                        fullWidth = true,
                    )
                    Text(
                        text = "抽题来自你练过的语料；同一用户每次得到同一组句子。" +
                            "没有练过的句子时服务端会提示先练习。",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
            }

            if (state.tests.isNotEmpty()) {
                BlindHistoryCard(state = state, isChild = isChild, dateLabel = dateLabel)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Running
// ---------------------------------------------------------------------------

@Composable
private fun BlindRunningContent(
    state: BlindTestUiState,
    isChild: Boolean,
    exceeded: Boolean,
    remainingMinutes: Int,
    recording: Boolean,
    recordSeconds: Int,
    localError: UiError?,
    onRecordClick: () -> Unit,
    onDismissLocalError: () -> Unit,
    onDismissSubmitError: () -> Unit,
    onSkip: () -> Unit,
    onFinish: () -> Unit,
    onRetryFinish: () -> Unit,
    onDismissFinishError: () -> Unit,
) {
    StatCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = "🎯 盲测进行中",
                modifier = Modifier.weight(1f),
                fontSize = EcFont.body,
                fontWeight = FontWeight.Bold,
                color = EcColor.ink,
            )
            EcPill(
                text = "第 ${(state.submitted + 1).coerceAtMost(state.total.coerceAtLeast(1))} / " +
                    "${state.total} 句",
                tone = PillTone.INFO,
            )
        }
        StatsProgressBar(fraction = state.progress)
        Text(
            text = "已提交 ${state.submitted} 句 · 已评分 ${state.scored} 句" +
                if (state.pending > 0) " · 评分中 ${state.pending} 句" else "",
            fontSize = EcFont.caption,
            color = EcColor.ink,
        )
        if (state.pending > 0) {
            EcInlineNotice(
                text = "还有 ${state.pending} 条在后台评分；这里只显示计数，不显示任何分数。",
                tone = PillTone.WARN,
            )
        }
        Text(
            text = "这一轮不会有任何分数和反馈，读完 ${state.total} 句才看得到结果 —— 这样才测得准 🙂",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }

    state.finishError?.let { error ->
        ErrorBanner(error = error, onRetry = onRetryFinish, onDismiss = onDismissFinishError)
    }
    if (exceeded) {
        EcInlineNotice(
            text = if (isChild) {
                "今天已经练得很棒啦，还剩 $remainingMinutes 分钟，明天再来 🌙"
            } else {
                "今天的练习时长已达上限（剩余 $remainingMinutes 分钟），明天再来"
            },
            tone = PillTone.WARN,
        )
    }

    if (!state.allSubmitted) {
        val sentence = state.currentSentence
        StatCard {
            Text(
                text = "第 ${state.submitted + 1} 句 / 共 ${state.total} 句",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
            if (sentence == null || sentence.text.isBlank()) {
                Text(
                    text = "这一句的原文暂时取不到（可能还没同步到本机）。",
                    fontSize = EcFont.caption,
                    color = EcColor.warnText,
                )
                EcButton(
                    label = "跳过这一句",
                    onClick = onSkip,
                    kind = EcButtonKind.GHOST,
                    size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                    fullWidth = true,
                )
            } else if (isChild) {
                Text(
                    text = sentence.text,
                    fontSize = EcFont.sentence,
                    color = EcColor.ink,
                )
            } else {
                WordText(text = sentence.text)
            }
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            RecordButton(
                recording = recording,
                enabled = !state.submitting && !exceeded,
                isChild = isChild,
                onClick = onRecordClick,
                label = when {
                    exceeded -> "今天的练习时长用完了，明天再来"
                    state.submitting -> "正在提交，马上到下一句…"
                    recording -> "说完啦 · ${recordSeconds}s（最长 60s）"
                    else -> "点一下开始说"
                },
            )
            if (localError != null) {
                ErrorBanner(error = localError, onDismiss = onDismissLocalError)
            }
            if (state.submitError != null) {
                ErrorBanner(error = state.submitError, onDismiss = onDismissSubmitError)
            }
        }

        EcButton(
            label = "提前结束并查看结果",
            onClick = onFinish,
            kind = EcButtonKind.GHOST,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            loading = state.finishing,
            fullWidth = true,
        )
    } else {
        StatCard {
            Text(
                text = "🎉 这一批的句子已经读完了",
                fontSize = EcFont.h3,
                fontWeight = FontWeight.Bold,
                color = EcColor.ink,
            )
            Text(
                text = if (state.pending > 0) {
                    "还有 ${state.pending} 条在后台评分，可以先结束，报告里会标成「待评分」。"
                } else {
                    "评分也完成了，可以结束并查看周报啦 ✅"
                },
                fontSize = EcFont.caption,
                color = if (state.pending > 0) EcColor.warnText else EcColor.goodText,
            )
            EcButton(
                label = "结束并查看周报",
                onClick = onFinish,
                loading = state.finishing,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.LG,
                fullWidth = true,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Finish
// ---------------------------------------------------------------------------

@Composable
private fun BlindFinishContent(
    state: BlindTestUiState,
    isChild: Boolean,
    dateLabel: (String?) -> String,
    scoreText: (Double?) -> String,
    deltaText: (Double?) -> String,
    onRestart: () -> Unit,
    onBack: () -> Unit,
    onRetryFinish: () -> Unit,
    onDismissFinishError: () -> Unit,
) {
    state.finishError?.let { error ->
        ErrorBanner(error = error, onRetry = onRetryFinish, onDismiss = onDismissFinishError)
    }

    val finish = state.finish
    if (finish == null) {
        LoadingBlock(text = "正在生成盲测周报…")
        return
    }

    val weeks = maxOf(state.trend?.weeks ?: 0, state.tests.size)
    val compareText = when {
        finish.deltaPron == null -> "这是第一次盲测，下次就有对比啦"
        finish.deltaPron > 0 -> "比上次更棒啦！"
        finish.deltaPron < 0 -> "这次有点难，下次再来会更棒！"
        else -> "和上次一样棒！"
    }

    StatCard {
        Text(
            text = if (isChild) "🎉 小测验做完啦，你真棒！" else "🎉 盲测完成",
            fontSize = if (isChild) EcFont.childH1 else EcFont.h3,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        // notice 是服务端给黄条的原文（全评完时为 null）
        if (!finish.notice.isNullOrEmpty()) {
            EcInlineNotice(text = finish.notice, tone = PillTone.WARN)
        }

        if (isChild) {
            Text(
                text = EcScore.stars(finish.avgPron),
                fontSize = EcFont.display,
            )
            Text(
                text = "你已经完成 $weeks 次小测验啦 · $compareText",
                fontSize = EcFont.childBody,
                color = EcColor.ink,
            )
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x5),
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = scoreText(finish.avgPron),
                        fontSize = EcFont.display,
                        fontWeight = FontWeight.Bold,
                        color = EcScore.color(finish.avgPron, false),
                    )
                    Text(text = "综合分", fontSize = EcFont.micro, color = EcColor.muted)
                }
                Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
                    Text(text = "与上次相比", fontSize = EcFont.micro, color = EcColor.muted)
                    Text(
                        text = deltaText(finish.deltaPron),
                        fontSize = EcFont.h3,
                        fontWeight = FontWeight.Bold,
                        color = deltaColor(finish.deltaPron),
                    )
                    Text(
                        text = "上次：" + scoreText(finish.previous?.avgPron) + " 分",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
            }
            Text(
                text = "准确度 ${scoreText(finish.avgAccuracy)} · " +
                    "流利度 ${scoreText(finish.avgFluency)} · " +
                    "语调差异 ${scoreText(finish.avgIntonationDistance)}",
                fontSize = EcFont.caption,
                color = EcColor.ink,
            )
        }

        Text(
            text = "本次平均分基于 ${finish.scored} 条已评分记录" +
                if (finish.pending > 0) "（另有 ${finish.pending} 条待评分，未计入）。" else "。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = "再来一次",
                onClick = onRestart,
                modifier = Modifier.weight(1f),
                loading = state.starting,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            )
            EcButton(
                label = "返回",
                onClick = onBack,
                modifier = Modifier.weight(1f),
                kind = EcButtonKind.GHOST,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            )
        }
    }

    // 成人：历次盲测趋势（儿童不展示图表/分数细节）
    if (!isChild && state.series.isNotEmpty()) {
        StatCard {
            Text(
                text = "📈 历次盲测（周报）",
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
            EcTrendChart(
                points = state.series.map { it.avgPron?.toFloat() },
                labels = state.series.map { dateLabel(it.endedAt) },
                height = 140.dp,
            )
            Text(
                text = "已完成 $weeks 次盲测 · 柱/点越高越好",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
    }

    if (state.tests.isNotEmpty()) {
        BlindHistoryCard(
            state = state,
            isChild = isChild,
            dateLabel = dateLabel,
        )
    }
}

// ---------------------------------------------------------------------------
// 历史记录
// ---------------------------------------------------------------------------

@Composable
private fun BlindHistoryCard(
    state: BlindTestUiState,
    isChild: Boolean,
    dateLabel: (String?) -> String,
) {
    StatCard {
        Text(
            text = "历史记录",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        state.tests.take(HISTORY_LIMIT).forEach { test ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = dateLabel(test.endedAt) + " · ${test.itemCount} 句",
                        fontSize = EcFont.caption,
                        color = EcColor.ink,
                    )
                    Text(
                        text = if (isChild) {
                            if (test.pending > 0) "还有待评分" else "完成啦"
                        } else {
                            "综合分 " + formatBlindScore(test.avgPron) +
                                " · 准确 " + formatBlindScore(test.avgAccuracy) +
                                " · 流利 " + formatBlindScore(test.avgFluency) +
                                " · 语调差异 " + formatBlindScore(test.avgIntonationDistance)
                        },
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
                if (test.pending > 0) {
                    EcPill(text = "待评分 ${test.pending}", tone = PillTone.WARN)
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

private val TICK_MS = 200L
private const val HISTORY_LIMIT = 5

private fun deltaColor(delta: Double?): Color = when {
    delta == null -> EcColor.muted
    delta > 0 -> EcColor.goodText
    delta < 0 -> EcColor.badText
    else -> EcColor.muted
}

/** 历史列表里的分数（保留 1 位小数，null → —）。 */
private fun formatBlindScore(score: Double?): String {
    if (score == null) return "—"
    val rounded = kotlin.math.round(score * 10) / 10.0
    return if (rounded % 1.0 == 0.0) rounded.toInt().toString() else rounded.toString()
}

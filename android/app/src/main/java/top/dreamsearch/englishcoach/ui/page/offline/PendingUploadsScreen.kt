package top.dreamsearch.englishcoach.ui.page.offline

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcDialog
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
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
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * 待补评分录音（离线能力，`Routes.PENDING_UPLOADS`，ROUND2_CONTRACT §1.3 / §4）。
 *
 * 「为什么会有这条」：跟读/连读提交评测时网络断开或服务端 5xx，录音不会重复上传也不会丢，
 * 而是先落到本机队列（`PendingUploadQueue`）；等补上网络后在这页点「全部重试」逐条补评分。
 * 补评分成功后服务端才计入用量（不会重复占用今天的练习时长）。
 *
 * 交互：
 * - 列表：句子预览 / 相对时间 / 时长 / 重试次数 / 最近错误（红字）/ ▶ 试听 / 删除（二次确认）；
 * - 底部主按钮「全部重试（N 条）」：loading + 串行进度文案 + 成功/失败汇总；
 * - 顶部动作：全部重试（有网时）/ 清除全部（二次确认）；
 * - 空态「没有待补评分的录音 🌱」+「回首页继续练习」；loading / error 三态齐全。
 *
 * 页面不直接发网络请求：列表/删除/重试全部经 [PendingUploadsViewModel]；试听走 `AudioController`。
 */
@Composable
fun PendingUploadsScreen(onBack: () -> Unit) {
    val vm: PendingUploadsViewModel = viewModel(
        factory = remember { vmFactory { PendingUploadsViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current

    // 回到前台刷新（用户切出去连 Wi-Fi / 从设置返回后，列表和「有网」状态都要更新）
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) vm.refresh()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            vm.onLeave()
        }
    }

    val childButtonSize = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD

    // 单条删除：二次确认
    if (state.deletingId.isNotEmpty()) {
        EcDialog(title = "删除这条录音？", onDismiss = { vm.cancelDelete() }) {
            Text(
                text = if (isChild) "删掉以后这条就不能补评分啦，确定吗？" else "删除后这条录音就无法补评分，确定吗？",
                fontSize = if (isChild) EcFont.childBody else EcFont.body,
                color = EcColor.ink,
            )
            EcButton(
                label = "删除",
                onClick = { vm.confirmDelete() },
                kind = EcButtonKind.DANGER,
                size = childButtonSize,
                fullWidth = true,
            )
            EcButton(
                label = "先不删",
                onClick = { vm.cancelDelete() },
                kind = EcButtonKind.GHOST,
                size = childButtonSize,
                fullWidth = true,
            )
        }
    }

    // 清除全部：二次确认
    if (state.confirmClearAll) {
        EcDialog(title = "清除全部录音？", onDismiss = { vm.cancelClearAll() }) {
            Text(
                text = "将删除本机 ${state.items.size} 条待补评分录音，清除后无法恢复。",
                fontSize = if (isChild) EcFont.childBody else EcFont.body,
                color = EcColor.ink,
            )
            EcButton(
                label = "清除全部",
                onClick = { vm.confirmClearAll() },
                kind = EcButtonKind.DANGER,
                size = childButtonSize,
                fullWidth = true,
            )
            EcButton(
                label = "先不清",
                onClick = { vm.cancelClearAll() },
                kind = EcButtonKind.GHOST,
                size = childButtonSize,
                fullWidth = true,
            )
        }
    }

    PageScaffold(
        title = if (state.items.isEmpty()) "待补评分" else "待补评分（${state.items.size}）",
        onBack = onBack,
        actions = {
            if (state.items.isNotEmpty() && !state.retrying) {
                if (state.online) {
                    Text(
                        text = "全部重试",
                        fontSize = if (isChild) EcFont.body else EcFont.caption,
                        color = EcColor.primary,
                        modifier = Modifier
                            .clickable { vm.retryAll() }
                            .padding(horizontal = EcSpace.x2, vertical = EcSpace.x2),
                    )
                }
                Text(
                    text = "清除全部",
                    fontSize = if (isChild) EcFont.body else EcFont.caption,
                    color = EcColor.badText,
                    modifier = Modifier
                        .clickable { vm.requestClearAll() }
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x2),
                )
            }
        },
        bottomBar = {
            if (state.items.isNotEmpty()) {
                RetryBottomBar(
                    state = state,
                    isChild = isChild,
                    onRetry = { vm.retryAll() },
                )
            }
        },
    ) { padding ->
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
            item(key = "intro") { IntroCard(isChild = isChild, count = state.items.size) }

            val notice = state.notice
            if (notice.isNotEmpty()) {
                item(key = "notice") {
                    EcInlineNotice(
                        text = notice,
                        tone = if (state.noticeWarn) PillTone.WARN else PillTone.GOOD,
                    )
                }
            }

            val error = state.error
            if (error != null) {
                item(key = "error") {
                    ErrorBanner(error = error, onRetry = { vm.load() })
                }
            }

            val result = state.result
            if (result != null) {
                item(key = "result") {
                    RetryResultCard(
                        result = result,
                        isChild = isChild,
                        onDismiss = { vm.dismissResult() },
                    )
                }
            }

            when {
                state.loading -> item(key = "loading") {
                    LoadingBlock(text = "正在读取本机录音…")
                }

                state.items.isEmpty() -> item(key = "empty") {
                    EmptyState(
                        icon = "🌱",
                        message = if (isChild) "没有要补评分的声音啦" else "没有待补评分的录音",
                        actionLabel = "回首页继续练习",
                        onAction = onBack,
                    )
                }

                else -> {
                    items(state.items, key = { it.id }) { item ->
                        PendingUploadRow(
                            item = item,
                            isChild = isChild,
                            playing = state.playingId == item.id,
                            disabled = state.retrying,
                            onPlay = { vm.playItem(item.id) },
                            onDelete = { vm.requestDelete(item.id) },
                        )
                    }
                }
            }

            if (state.items.isNotEmpty()) {
                item(key = "why") { WhyCard(isChild = isChild) }
            }

            item(key = "footer") {
                Text(
                    text = "补评分成功后会从本机删除；失败的会留着，等网络好了再试一次。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = EcSpace.x2, bottom = EcSpace.x4),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 顶部说明 / 原理说明
// ---------------------------------------------------------------------------

/** 顶部说明：录音已在本机、补网后补评分、不重复占时长。 */
@Composable
private fun IntroCard(isChild: Boolean, count: Int) {
    EcCard {
        Text(
            text = "📥 这些录音都存在手机里",
            fontSize = if (isChild) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        Text(
            text = if (isChild) {
                "等连上家里的 Wi-Fi，点下面的按钮就能补上评分，今天的练习时长不会多算一次。"
            } else {
                "这些录音已经保存在本机。补上网络后点重试就能补评分，不会重复占用今天的练习时长。"
            },
            fontSize = if (isChild) EcFont.childBody else EcFont.caption,
            color = EcColor.muted,
        )
        if (count > 0) {
            Text(
                text = "共 $count 条待补评分",
                fontSize = EcFont.micro,
                color = EcColor.primary,
            )
        }
    }
}

/** 「为什么会有这条」说明（ROUND2 §4 screens-chat 要求）。 */
@Composable
private fun WhyCard(isChild: Boolean) {
    EcCard {
        Text(
            text = "为什么会有这条？",
            fontSize = if (isChild) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        Text(
            text = if (isChild) {
                "上次说完句子的时候网络断了一下，声音就先存在手机里啦。等有网络了再来补评分就好。"
            } else {
                "提交录音时网络断开或服务端暂时不可用（5xx）时，录音会先保存在本机，等网络恢复后再补评分；" +
                    "4xx 业务错误不会进这个队列。"
            },
            fontSize = if (isChild) EcFont.caption else EcFont.micro,
            color = EcColor.muted,
        )
    }
}

// ---------------------------------------------------------------------------
// 列表行
// ---------------------------------------------------------------------------

/** 一条待补评分录音：句子预览 / 时间 / 时长 / 重试次数 / 错误 / 试听 / 删除。 */
@Composable
private fun PendingUploadRow(
    item: PendingUploadItemUi,
    isChild: Boolean,
    playing: Boolean,
    disabled: Boolean,
    onPlay: () -> Unit,
    onDelete: () -> Unit,
) {
    EcCard {
        Text(
            text = item.referenceText.ifEmpty { "句子 ${item.sentenceId.take(8)}" },
            fontSize = if (isChild) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = relativeTimeText(item.createdAt),
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
            val duration = durationText(item.durationMs)
            if (duration.isNotEmpty()) {
                Text(text = duration, fontSize = EcFont.micro, color = EcColor.muted)
            }
            if (item.retryCount > 0) {
                Text(
                    text = if (isChild) "试过 ${item.retryCount} 次" else "重试过 ${item.retryCount} 次",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }

        val lastError = item.lastError
        if (!lastError.isNullOrEmpty()) {
            Text(
                text = if (isChild) "上次没成功：$lastError" else "最近一次失败原因：$lastError",
                fontSize = EcFont.micro,
                color = EcColor.badText,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
        }

        if (isChild) {
            // 儿童：大按钮（≥60dp），文案更短
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = if (playing) "⏸ 停下" else "▶ 听听看",
                    onClick = onPlay,
                    kind = EcButtonKind.SECONDARY,
                    size = EcButtonSizeKind.CHILD,
                    enabled = !disabled,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = "删除",
                    onClick = onDelete,
                    kind = EcButtonKind.DANGER,
                    size = EcButtonSizeKind.CHILD,
                    enabled = !disabled,
                    modifier = Modifier.weight(1f),
                )
            }
        } else {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
            ) {
                Text(
                    text = if (playing) "⏸ 停止试听" else "▶ 试听",
                    fontSize = EcFont.caption,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(enabled = !disabled, onClick = onPlay)
                        .padding(vertical = EcSpace.x1),
                )
                Text(
                    text = "删除",
                    fontSize = EcFont.caption,
                    color = EcColor.badText,
                    modifier = Modifier
                        .clickable(enabled = !disabled, onClick = onDelete)
                        .padding(vertical = EcSpace.x1),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 结果汇总卡
// ---------------------------------------------------------------------------

/** 「全部重试」结果：成功 X / 仍失败 Y + 原因 + 用量提示。 */
@Composable
private fun RetryResultCard(
    result: PendingRetryResult,
    isChild: Boolean,
    onDismiss: () -> Unit,
) {
    val allOk = result.failed == 0
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(if (allOk) EcColor.goodBg else EcColor.warnBg)
            .padding(EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
    ) {
        Text(
            text = if (allOk) {
                if (isChild) "🌟 都补好啦" else "✅ 补评分完成"
            } else {
                if (isChild) "有些还没补上" else "⚠️ 部分录音补评分失败"
            },
            fontSize = if (isChild) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Bold,
            color = if (allOk) EcColor.goodText else EcColor.warnText,
        )
        Text(
            text = "成功 ${result.succeeded} 条 · 仍失败 ${result.failed} 条",
            fontSize = EcFont.caption,
            color = if (allOk) EcColor.goodText else EcColor.warnText,
        )
        if (result.succeeded > 0) {
            Text(
                text = "已补评分 ${result.succeeded} 条；今日已练 ${result.minutesToday}/${result.dailyLimitMinutes} 分钟。",
                fontSize = EcFont.micro,
                color = EcColor.goodText,
            )
        }
        val lastError = result.lastError
        if (!lastError.isNullOrEmpty() && result.failed > 0) {
            Text(
                text = "失败原因：$lastError",
                fontSize = EcFont.micro,
                color = EcColor.badText,
            )
        }
        if (result.failed > 0) {
            Text(
                text = "失败的录音还在本机，可以稍后再点「全部重试」。",
                fontSize = EcFont.micro,
                color = EcColor.warnText,
            )
        }
        Spacer(modifier = Modifier.size(EcSpace.x1))
        EcButton(
            label = "知道了",
            onClick = onDismiss,
            kind = EcButtonKind.SECONDARY,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
        )
    }
}

// ---------------------------------------------------------------------------
// 底部重试条
// ---------------------------------------------------------------------------

@Composable
private fun RetryBottomBar(
    state: PendingUploadsUiState,
    isChild: Boolean,
    onRetry: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(EcColor.surface)
            .padding(horizontal = EcSpace.x4, vertical = EcSpace.x2),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        if (!state.online) {
            EcInlineNotice(
                text = if (isChild) {
                    "现在没有网络，连上家里的 Wi-Fi 再试吧"
                } else {
                    "现在没有网络。连上家里的 Wi-Fi 后再点「全部重试」。"
                },
                tone = PillTone.WARN,
            )
        } else if (state.retrying) {
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
                    text = state.retryProgress.ifEmpty { "正在逐条补评分…" },
                    fontSize = if (isChild) EcFont.body else EcFont.caption,
                    color = EcColor.primary,
                )
            }
        }
        EcButton(
            label = when {
                state.retrying -> "正在补评分…"
                isChild -> "全部补评分（${state.items.size} 条）"
                else -> "全部重试（${state.items.size} 条）"
            },
            onClick = onRetry,
            kind = EcButtonKind.PRIMARY,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.LG,
            enabled = !state.retrying && state.online && state.items.isNotEmpty(),
            loading = state.retrying,
            fullWidth = true,
        )
        Text(
            text = if (isChild) "一条一条来，成功的就不用再管啦" else "逐条上传：成功一条删一条，不会重复占用今天的练习时长。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// ---------------------------------------------------------------------------
// 展示格式化
// ---------------------------------------------------------------------------

/** 相对时间：刚刚 / N 分钟前 / 今天 HH:mm / 昨天 HH:mm / MM-dd HH:mm。 */
private fun relativeTimeText(createdAt: Long, now: Long = System.currentTimeMillis()): String {
    if (createdAt <= 0L) return ""
    val diff = now - createdAt
    if (diff in 0L until MINUTE_MS) return "刚刚"
    if (diff in MINUTE_MS until HOUR_MS) return "${diff / MINUTE_MS} 分钟前"
    val zone = ZoneId.systemDefault()
    val created = Instant.ofEpochMilli(createdAt).atZone(zone)
    val today = LocalDate.now(zone)
    val time = created.format(TIME_FORMAT)
    return when (created.toLocalDate()) {
        today -> "今天 $time"
        today.minusDays(1) -> "昨天 $time"
        else -> created.format(DATE_FORMAT)
    }
}

/** 录音时长：「约 3 秒」/「2 分 10 秒」；0 表示不可得（不显示）。 */
private fun durationText(durationMs: Int): String {
    if (durationMs <= 0) return ""
    val totalSec = Math.round(durationMs / 1000.0).toInt()
    if (totalSec < 60) return "约 $totalSec 秒"
    return "${totalSec / 60} 分 ${totalSec % 60} 秒"
}

private const val MINUTE_MS = 60_000L
private const val HOUR_MS = 3_600_000L
private val TIME_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")
private val DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("MM-dd HH:mm")

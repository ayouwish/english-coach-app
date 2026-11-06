package top.dreamsearch.englishcoach.ui.page.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.dto.ParentChildDto
import top.dreamsearch.englishcoach.core.net.dto.ParentMemberDto
import top.dreamsearch.englishcoach.ui.component.EcBarChart
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcSectionTitle
import top.dreamsearch.englishcoach.ui.component.EcTrendChart
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

/**
 * 家长面板（`Routes.PARENT`，仅家长；对应 hos `pages/ParentPage.ets`）。
 *
 * 结构（照抄 hos）：
 * 1. 全家汇总 + 每个孩子的「今日剩余时长」卡；
 * 2. 每个成员一张卡：今日/周/累计、近 14 天趋势、盲测周环比（current / delta / series）、薄弱音素、高频错词；
 * 3. 入口：盲测周报（顶部动作 + 底部按钮）、家庭成员管理、建议箱。
 *
 * 状态：loading（骨架）/ forbidden（只有家长能看）/ error + 重试 / empty（无成员）/ 正常。
 * 数值全部经 `AccountFormat` 兜底为「—」；儿童访问不会落到这里（入口不渲染 + 服务端 403 双保险）。
 */
@Composable
fun ParentScreen(
    onBack: () -> Unit,
    onOpenFamily: () -> Unit,
    onOpenSuggestions: () -> Unit,
    onOpenBlindTest: () -> Unit,
) {
    val vm: ParentViewModel = viewModel(
        factory = remember { vmFactory { ParentViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()

    PageScaffold(
        title = "家长面板",
        onBack = onBack,
        actions = {
            if (!state.forbidden) {
                Text(
                    text = "📊 盲测",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable { onOpenBlindTest() }
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x2),
                )
                Text(
                    text = if (state.refreshing) "刷新中…" else "刷新",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(enabled = !state.refreshing) { vm.refresh() }
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x2),
                )
            }
        },
    ) {
        if (state.forbidden) {
            ForbiddenView(message = state.error?.message, onBack = onBack)
        } else {
            ParentContent(
                state = state,
                vm = vm,
                onOpenFamily = onOpenFamily,
                onOpenSuggestions = onOpenSuggestions,
                onOpenBlindTest = onOpenBlindTest,
            )
        }
    }
}

// ------------------------------------------------------------------ 内容

@Composable
private fun ParentContent(
    state: ParentUiState,
    vm: ParentViewModel,
    onOpenFamily: () -> Unit,
    onOpenSuggestions: () -> Unit,
    onOpenBlindTest: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = EcSpace.x4,
            end = EcSpace.x4,
            top = EcSpace.x3,
            bottom = EcSpace.x8,
        ),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
    ) {
        item(key = "summary") { FamilySummaryCard(state, vm) }

        if (state.error != null) {
            item(key = "error") {
                ErrorBanner(error = state.error, onRetry = { vm.load() })
            }
        }

        when {
            state.loading -> item(key = "loading") {
                LoadingBlock(text = "正在读取全家练习数据…")
            }

            state.members.isEmpty() -> item(key = "empty") {
                EmptyState(
                    icon = "👨‍👩‍👧",
                    message = "还没有家庭成员。先建一个孩子的账号，就能看到练习与盲测数据。",
                    actionLabel = "去添加成员",
                    onAction = onOpenFamily,
                )
            }

            else -> items(state.members, key = { it.id }) { member ->
                MemberCard(member = member, vm = vm)
            }
        }

        item(key = "entries") {
            EntriesCard(
                onOpenFamily = onOpenFamily,
                onOpenSuggestions = onOpenSuggestions,
                onOpenBlindTest = onOpenBlindTest,
            )
        }
    }
}

// ------------------------------------------------------------------ 汇总

@Composable
private fun FamilySummaryCard(state: ParentUiState, vm: ParentViewModel) {
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = "👨‍👩‍👧", fontSize = 24.sp)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "家长面板",
                    fontSize = EcFont.h3,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                Text(
                    text = "看全家练习、剩余时长与盲测周环比（只有家长能看）。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            EcPill(text = "${state.family?.members ?: 0} 人", tone = PillTone.INFO)
        }
        Text(
            text = vm.familyText(state.family),
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        val children: List<ParentChildDto> = state.family?.children ?: emptyList()
        if (children.isNotEmpty()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                children.forEach { child ->
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(EcRadius.md))
                            .background(EcColor.primary)
                            .padding(EcSpace.x3),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(
                            text = "${child.displayName} 今日剩余",
                            fontSize = EcFont.micro,
                            color = EcColor.surface,
                        )
                        Text(
                            text = childRemainingText(child),
                            fontSize = EcFont.h3,
                            fontWeight = FontWeight.Bold,
                            color = EcColor.surface,
                        )
                    }
                }
            }
        }
    }
}

/** 今日剩余时长：`18 / 20 分钟`，缺字段显示「—」。 */
private fun childRemainingText(child: ParentChildDto): String {
    val remaining = child.remainingMinutes?.let { AccountFormat.minutes(it) } ?: "—"
    val limit = child.limitMinutes?.let { it.toString() } ?: "—"
    return "$remaining / $limit 分钟"
}

// ------------------------------------------------------------------ 成员卡

@Composable
private fun MemberCard(member: ParentMemberDto, vm: ParentViewModel) {
    EcCard {
        // 头部：头像 + 昵称 + 角色徽标 + 盲测进行中
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = AccountFormat.memberAvatar(member.avatar, member.role),
                fontSize = 22.sp,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = member.displayName.ifEmpty { "成员" },
                    fontSize = EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                )
                Text(
                    text = AccountFormat.roleBadge(member.role, member.cefrLevel),
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            if (vm.blindInProgress(member)) {
                EcPill(text = "正在做盲测…", tone = PillTone.WARN)
            }
            EcPill(text = "${member.dailyLimitMinutes} 分钟/天", tone = PillTone.NEUTRAL)
        }

        Text(
            text = vm.todayText(member),
            fontSize = EcFont.caption,
            color = EcColor.ink,
        )
        val weekText = vm.weekText(member)
        if (weekText.isNotEmpty()) {
            Text(text = weekText, fontSize = EcFont.micro, color = EcColor.muted)
        }

        // 近 14 天趋势
        val trendPoints = member.trend
        if (trendPoints.isNotEmpty()) {
            Spacer(modifier = Modifier.height(2.dp))
            Text(text = "近 14 天趋势", fontSize = EcFont.micro, color = EcColor.muted)
            EcTrendChart(
                points = AccountFormat.trendValues(trendPoints),
                labels = AccountFormat.trendLabels(trendPoints),
                height = 90.dp,
            )
            Text(
                text = "最近：${vm.trendTail(member)}",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }

        BlindPanel(member = member, vm = vm)
        PhonemeAndWordRows(member = member, vm = vm)
    }
}

/** 盲测周环比：大数字 + 环比 + 子项 + 历次柱状图（无数据给空态文案）。 */
@Composable
private fun BlindPanel(member: ParentMemberDto, vm: ParentViewModel) {
    val current = vm.blindCurrentPron(member)
    val delta = member.blind?.deltaPron
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.surfaceAlt)
            .padding(EcSpace.x3),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = AccountFormat.scoreText(current),
                    fontSize = 34.sp,
                    fontWeight = FontWeight.Bold,
                    color = EcScore.color(current, false),
                )
                Text(
                    text = "最近一次盲测综合分",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                    textAlign = TextAlign.Center,
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(text = "本周 vs 上次", fontSize = EcFont.micro, color = EcColor.muted)
                Text(
                    text = vm.blindDeltaText(member),
                    fontSize = EcFont.h3,
                    fontWeight = FontWeight.Bold,
                    color = AccountFormat.blindDeltaColor(delta),
                )
                Text(
                    text = "已完成盲测 ${vm.blindWeeks(member)} 次",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            Column {
                Text(
                    text = "准确 ${AccountFormat.scoreText(vm.blindAccuracy(member))}",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
                Text(
                    text = "流利 ${AccountFormat.scoreText(vm.blindFluency(member))}",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
                Text(
                    text = "语调差 ${AccountFormat.scoreText(vm.blindIntonation(member))}",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }

        val values = vm.blindBarValues(member)
        if (values.isNotEmpty()) {
            EcBarChart(
                values = values,
                labels = vm.blindBarLabels(member),
                height = 80.dp,
                maxValue = 100f,
            )
        } else {
            Text(
                text = "还没有完成的盲测。让孩子去「🎯 盲测周报」做一次，下周再做一次就能看到环比。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
    }
}

/** 薄弱音素 / 高频错词（各最多 3 条，不占满屏）。 */
@Composable
private fun PhonemeAndWordRows(member: ParentMemberDto, vm: ParentViewModel) {
    if (member.topPhonemes.isNotEmpty()) {
        Text(text = "高频错音", fontSize = EcFont.micro, color = EcColor.muted)
        member.topPhonemes.take(3).forEach { item ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Box(
                    modifier = Modifier
                        .width(64.dp)
                        .height(6.dp)
                        .clip(RoundedCornerShape(3.dp))
                        .background(EcColor.border),
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxHeight()
                            .fillMaxWidth(AccountFormat.barFraction(item.avgScore))
                            .clip(RoundedCornerShape(3.dp))
                            .background(EcScore.color(item.avgScore, false)),
                    )
                }
                Text(
                    text = vm.phonemeText(item),
                    fontSize = EcFont.micro,
                    color = EcColor.ink,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
    if (member.topWords.isNotEmpty()) {
        Text(text = "高频错词（单词级粗评）", fontSize = EcFont.micro, color = EcColor.muted)
        member.topWords.take(3).forEach { item ->
            Text(
                text = vm.wordText(item),
                fontSize = EcFont.micro,
                color = EcColor.ink,
            )
        }
    }
}

// ------------------------------------------------------------------ 入口 / 无权限

@Composable
private fun EntriesCard(
    onOpenFamily: () -> Unit,
    onOpenSuggestions: () -> Unit,
    onOpenBlindTest: () -> Unit,
) {
    EcCard {
        EcSectionTitle(text = "管理")
        EcButton(
            label = "📊 盲测周报一起来看",
            onClick = onOpenBlindTest,
            kind = EcButtonKind.SECONDARY,
            fullWidth = true,
        )
        EcButton(
            label = "👥 家庭成员管理",
            onClick = onOpenFamily,
            kind = EcButtonKind.GHOST,
            fullWidth = true,
        )
        EcButton(
            label = "💡 建议箱（孩子提的建议都在这）",
            onClick = onOpenSuggestions,
            kind = EcButtonKind.GHOST,
            fullWidth = true,
        )
        Text(
            text = "盲测周环比 · 同一组句子、全程不给反馈；日常练习的分数会因为「看完反馈立刻重读」而虚高，只有盲测能证明真的进步了。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

/** 非家长（或服务端 403）：不跳登录，留在本页给一句人话 + 返回。 */
@Composable
private fun ForbiddenView(message: String?, onBack: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(EcSpace.x8),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(text = "👨‍👩‍👧", fontSize = 44.sp)
        Spacer(modifier = Modifier.height(EcSpace.x3))
        Text(
            text = "只有家长能看",
            fontSize = EcFont.h2,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Spacer(modifier = Modifier.height(EcSpace.x2))
        Text(
            text = message?.ifEmpty { null }
                ?: "家长面板仅对家长账号开放。想练习的话回「跟读」就行 🙂",
            fontSize = EcFont.body,
            color = EcColor.muted,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(EcSpace.x5))
        EcButton(label = "返回", onClick = onBack, kind = EcButtonKind.SECONDARY)
    }
}

package top.dreamsearch.englishcoach.ui.page.stats

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.dto.DiagnosisItemDto
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcScore
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild
import top.dreamsearch.englishcoach.ui.nav.TabNav
import top.dreamsearch.englishcoach.ui.nav.Tabs

/**
 * 发音诊断（`GET /api/diagnosis`，4 个 scope：单句 / 连读这一批 / 最近 7 天 / 全部累计）。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/pages/DiagnosisPage.ets`（只做了 recent/all），
 * 单句与批次 scope 按 `.specs/practice-flow.md` §2.14 / §6.1 补齐。
 *
 * 儿童规则（docs/screens.md §0）：
 * - 音素只显示 `child_label`，绝不出现 IPA / 对比音素符号；
 * - 不显示 <60 的数字分（[EcScore.showNumber]），分数行退化为「练过 N 次」；
 * - 文案口语化，按钮至少 60dp。
 *
 * 「强化练习」→ `onPracticeFocus(token)`：父级写 `NavParams.practiceFocus` 并切到跟读 Tab。
 */
@Composable
fun DiagnosisScreen(
    onBack: () -> Unit,
    onPracticeFocus: (String) -> Unit,
) {
    val vm: DiagnosisViewModel = viewModel(
        factory = remember { vmFactory { DiagnosisViewModel(AppGraph.container) } }
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current

    val goPractice: () -> Unit = {
        TabNav.go(Tabs.PRACTICE)
        onBack()
    }

    PageScaffold(
        title = if (isChild) "我的发音报告" else "发音诊断",
        onBack = onBack,
        scrollable = true,
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(padding)
                .padding(horizontal = EcSpace.x4, vertical = EcSpace.x4),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            DiagnosisHeaderCard(
                state = state,
                isChild = isChild,
                metricText = vm.metricText(state),
                itemTitle = { item -> vm.itemTitle(item, isChild) },
                onSwitchScope = vm::switchScope,
                onPrimaryAction = {
                    val token = vm.firstFocusToken(state)
                    if (token.isNotEmpty()) onPracticeFocus(token) else goPractice()
                },
            )

            state.error?.let { error ->
                ErrorBanner(error = error, onRetry = vm::load)
            }

            when {
                state.loading && !state.loadedOnce -> LoadingBlock(text = "正在统计发音…")

                state.error != null && !state.loadedOnce -> Unit // 只显示上面的错误条

                state.isEmptyResult -> EmptyState(
                    icon = "📊",
                    message = state.emptyHint.ifEmpty {
                        if (isChild) "再多读几句，就会有发音小报告啦" else "还没有足够的评测记录，先去跟读几句吧"
                    },
                    actionLabel = if (isChild) "去读几句" else "去跟读练习",
                    onAction = goPractice,
                )

                else -> {
                    state.items.forEach { item ->
                        DiagnosisItemCard(
                            item = item,
                            isChild = isChild,
                            title = vm.itemTitle(item, isChild),
                            scoreLine = vm.scoreLine(item, isChild),
                            trendText = vm.trendText(item, isChild),
                            statusLabel = vm.statusLabel(item.status),
                            focusToken = vm.focusTokenOf(item),
                            onPracticeFocus = onPracticeFocus,
                        )
                    }

                    if (state.okItems.isNotEmpty()) {
                        DiagnosisOkSection(
                            items = state.okItems,
                            expanded = state.showOk,
                            isChild = isChild,
                            itemTitle = { item -> vm.itemTitle(item, isChild) },
                            onToggle = vm::toggleOk,
                        )
                    }
                }
            }

            if (state.loadedOnce) {
                Text(
                    text = "诊断依据：每个音素的历次评测均分与最近 3 次趋势；" +
                        if (state.minSamples < 2) "本口径 1 次的记录也参与。" else "1 次的记录不参与（噪声太大）。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 摘要卡
// ---------------------------------------------------------------------------

@Composable
private fun DiagnosisHeaderCard(
    state: DiagnosisUiState,
    isChild: Boolean,
    metricText: String,
    itemTitle: (DiagnosisItemDto) -> String,
    onSwitchScope: (DiagnosisScope) -> Unit,
    onPrimaryAction: () -> Unit,
) {
    StatCard {
        Text(
            text = if (isChild) "🔍 我的发音报告" else "🔍 发音诊断报告",
            fontSize = if (isChild) EcFont.childH1 else EcFont.h2,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )

        // 4 个统计范围（横向可滚动，避免窄屏挤压）
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            DiagnosisScope.entries.forEach { scope ->
                EcChip(
                    label = scope.label,
                    selected = state.scope == scope,
                    onClick = { onSwitchScope(scope) },
                )
            }
        }

        if (state.summaryZh.isNotEmpty()) {
            Text(
                text = state.summaryZh,
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
        }
        if (state.loadedOnce) {
            Text(text = metricText, fontSize = EcFont.micro, color = EcColor.muted)
        }

        // 最需要练的 1–2 个音（儿童只显示口语名字）
        val focusItems = state.items.take(2)
        if (focusItems.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text(
                    text = if (isChild) "🎯 可以再练一练：" else "🎯 最近最需要练的：",
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
                focusItems.forEach { item ->
                    EcPill(
                        text = itemTitle(item),
                        tone = toneOf(item.status),
                    )
                }
            }
        }

        val focusToken = state.focusPhonemes.firstOrNull { it.isNotBlank() }
            ?: state.items.firstOrNull()?.focusToken.orEmpty()
        EcButton(
            label = when {
                isChild -> "🎯 去练一练"
                focusToken.isNotEmpty() -> "🚀 去跟读页练 /$focusToken/"
                else -> "去跟读练习"
            },
            onClick = onPrimaryAction,
            kind = EcButtonKind.PRIMARY,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            loading = state.loading,
            fullWidth = true,
        )
        Text(
            text = if (isChild) "会跳回「跟读」，专门练这个音。" else "会跳回「跟读」Tab，只练这个音素的句子。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

// ---------------------------------------------------------------------------
// 音素卡
// ---------------------------------------------------------------------------

@Composable
private fun DiagnosisItemCard(
    item: DiagnosisItemDto,
    isChild: Boolean,
    title: String,
    scoreLine: String,
    trendText: String,
    statusLabel: String,
    focusToken: String,
    onPracticeFocus: (String) -> Unit,
) {
    StatCard(borderColor = if (item.status == "weak") EcColor.warn else null) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = title,
                modifier = Modifier.weight(1f),
                fontSize = EcFont.h3,
                fontWeight = FontWeight.Bold,
                color = EcColor.ink,
            )
            EcPill(text = statusLabel, tone = toneOf(item.status))
        }

        Text(
            text = scoreLine,
            fontSize = EcFont.caption,
            color = if (isChild && !EcScore.showNumber(item.avgScore, true)) {
                EcColor.muted
            } else {
                EcScore.color(item.avgScore, isChild)
            },
        )

        if (trendText.isNotEmpty()) {
            Text(text = trendText, fontSize = EcFont.micro, color = EcColor.muted)
        }

        // 口型要点：儿童用服务端儿童版文案（口语），成人加「口型要点：」
        val tip = if (isChild) item.tipChildZh else item.tipZh
        if (tip.isNotEmpty()) {
            Text(
                text = if (isChild) "👄 $tip" else "👄 口型要点：$tip",
                fontSize = EcFont.caption,
                color = EcColor.ink,
            )
        }

        // 常见错误 / 对比音素：仅成人（儿童不显示符号与术语）
        if (!isChild && item.commonErrors.isNotEmpty()) {
            Text(
                text = "⚠️ 常见错误：" + item.commonErrors.joinToString(" · "),
                fontSize = EcFont.caption,
                color = EcColor.warnText,
            )
        }
        if (!isChild && item.contrasts.isNotEmpty()) {
            item.contrasts.take(2).forEach { contrast ->
                val pair = contrast.pair.joinToString(" → ")
                Text(
                    text = "🔀 $pair：${contrast.note}",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }

        if (item.examples.isNotEmpty()) {
            Text(
                text = "相关的词：" + item.examples.joinToString(" · "),
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = when {
                    item.practiceCount > 0 && !isChild -> "🎯 可练 ${item.practiceCount} 句"
                    item.practiceCount > 0 -> "🎯 有 ${item.practiceCount} 句可以练"
                    else -> "暂时没有可练的句子"
                },
                modifier = Modifier.weight(1f),
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
            EcButton(
                label = "强化练习",
                onClick = { if (focusToken.isNotEmpty()) onPracticeFocus(focusToken) },
                kind = EcButtonKind.SECONDARY,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.SM,
                enabled = focusToken.isNotEmpty(),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// 已掌握音素（折叠）
// ---------------------------------------------------------------------------

@Composable
private fun DiagnosisOkSection(
    items: List<DiagnosisItemDto>,
    expanded: Boolean,
    isChild: Boolean,
    itemTitle: (DiagnosisItemDto) -> String,
    onToggle: () -> Unit,
) {
    StatCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "已经掌握的音素（${items.size}）",
                modifier = Modifier.weight(1f),
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
            Text(
                text = if (expanded) "收起" else "点击展开",
                modifier = Modifier
                    .clickable(onClick = onToggle)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x3),
                fontSize = EcFont.caption,
                color = EcColor.primary,
            )
        }

        if (expanded) {
            items.chunked(2).forEach { rowItems ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                ) {
                    rowItems.forEach { item ->
                        EcPill(text = itemTitle(item), tone = PillTone.GOOD)
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

private fun toneOf(status: String): PillTone = when (status) {
    "weak" -> PillTone.BAD
    "watch" -> PillTone.WARN
    else -> PillTone.GOOD
}

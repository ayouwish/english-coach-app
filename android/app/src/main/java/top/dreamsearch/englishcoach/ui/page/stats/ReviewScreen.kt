package top.dreamsearch.englishcoach.ui.page.stats

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import top.dreamsearch.englishcoach.core.net.dto.ReviewCardDto
import top.dreamsearch.englishcoach.core.net.dto.ReviewWeakPhonemeDto
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
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
 * 错音本 / SRS 复习（`GET /api/review` + `POST /api/review`）。
 *
 * 对应 hos：`english-coach-app/hos/entry/src/main/ets/pages/ReviewPage.ets`。
 *
 * 交互（规格 §6.2）：
 * - 卡片流只展示当前一张；四个评分按钮（again/hard/good/easy）成功后本地移除该卡、
 *   due_cards-1，并展示服务端给的「下次复习：N 天后 ✅」；
 * - 底部固定展示薄弱音素（最弱在前）与高频错词（单词级粗评）；
 * - 儿童：不显示 IPA / 低分数字，按钮文案「再练 / 有点难 / 会了 / 太简单」。
 */
@Composable
fun ReviewScreen(onBack: () -> Unit) {
    val vm: ReviewViewModel = viewModel(
        factory = remember { vmFactory { ReviewViewModel(AppGraph.container) } }
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val session by AppGraph.session.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current

    val goPractice: () -> Unit = {
        TabNav.go(Tabs.PRACTICE)
        onBack()
    }

    PageScaffold(
        title = if (isChild) "我的小错音本" else "错音本",
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
            ReviewHeaderCard(
                state = state,
                isChild = isChild,
                minutesToday = vm.minutesText(session),
                minutesLeft = vm.minutesLeft(session),
            )

            state.error?.let { error ->
                ErrorBanner(error = error, onRetry = vm::load)
            }
            state.gradeError?.let { error ->
                ErrorBanner(error = error, onDismiss = vm::dismissGradeError)
            }

            when {
                state.loading && !state.loadedOnce -> LoadingBlock(text = "正在取今天要复习的卡片…")

                state.error != null && !state.loadedOnce -> Unit // 只显示上面的错误条

                state.currentCard == null -> EmptyState(
                    icon = "🎉",
                    message = if (isChild) {
                        "现在没有要做的小练习啦，去读几句就会有新的"
                    } else {
                        "现在没有到期的卡片。去「跟读练习」多读几句，新的错音会自动进来"
                    },
                    actionLabel = if (isChild) "去读几句" else "去跟读练习",
                    onAction = goPractice,
                )

                else -> {
                    Text(
                        text = if (isChild) "今天要复习的小卡片" else "今天要复习的卡片",
                        fontSize = EcFont.caption,
                        color = EcColor.muted,
                    )
                    state.currentCard?.let { card ->
                        ReviewCardView(
                            card = card,
                            isChild = isChild,
                            grading = state.gradingCardId.isNotEmpty(),
                            title = vm.cardTitle(card, isChild),
                            badge = vm.badgeText(card, isChild),
                            meta = vm.metaText(card),
                            gradeLabel = { grade -> vm.gradeLabel(grade, isChild) },
                            onGrade = { grade -> vm.grade(card.id, grade) },
                        )
                    }
                }
            }

            if (state.weakPhonemes.isNotEmpty()) {
                ReviewWeakSection(
                    items = state.weakPhonemes,
                    isChild = isChild,
                    labelOf = { item -> vm.weakPhonemeLabel(item, isChild) },
                    barOf = vm::weakBarFraction,
                )
            }

            if (state.wordErrors.isNotEmpty()) {
                ReviewWordErrorSection(state = state, isChild = isChild)
            }

            if (state.loadedOnce) {
                Text(
                    text = "排期算法：SM-2 简化版（again/hard/good/easy）。" +
                        if (state.phonemeLevel) "" else "当前是单词级粗评（provider 不支持音素级）。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }

            EcButton(
                label = "🎙 返回去跟读练习",
                onClick = goPractice,
                kind = EcButtonKind.SECONDARY,
                size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                fullWidth = true,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// 顶部统计卡
// ---------------------------------------------------------------------------

@Composable
private fun ReviewHeaderCard(
    state: ReviewUiState,
    isChild: Boolean,
    minutesToday: String,
    minutesLeft: String,
) {
    StatCard {
        Text(
            text = if (isChild) "📒 我的小错音本" else "📒 错音本 / SRS 复习",
            fontSize = if (isChild) EcFont.childH1 else EcFont.h2,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Text(
            text = "待复习 ${state.dueCards} 张 · 卡片总数 ${state.totalCards} 张 · " +
                "音素记录 ${state.phonemeRows} 条 · 今日 $minutesToday 分钟" +
                if (isChild) " · 还剩 $minutesLeft 分钟" else "",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        if (state.gradeNotice.isNotEmpty()) {
            Text(
                text = state.gradeNotice,
                fontSize = EcFont.caption,
                fontWeight = FontWeight.Medium,
                color = EcColor.goodText,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// 当前卡片
// ---------------------------------------------------------------------------

@Composable
private fun ReviewCardView(
    card: ReviewCardDto,
    isChild: Boolean,
    grading: Boolean,
    title: String,
    badge: String,
    meta: String,
    gradeLabel: (String) -> String,
    onGrade: (String) -> Unit,
) {
    StatCard(borderColor = EcColor.border) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            if (badge.isNotEmpty()) {
                EcPill(text = badge, tone = PillTone.INFO)
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    fontSize = EcFont.body,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                if (!isChild && meta.isNotEmpty()) {
                    Text(text = meta, fontSize = EcFont.micro, color = EcColor.muted)
                }
            }
        }

        if (card.whyZh.isNotEmpty()) {
            Text(text = card.whyZh, fontSize = EcFont.caption, color = EcColor.ink)
        }
        if (card.howZh.isNotEmpty()) {
            Text(text = "怎么做：${card.howZh}", fontSize = EcFont.caption, color = EcColor.muted)
        }
        if (card.practiceWords.isNotEmpty()) {
            Text(
                text = "练习词：" + card.practiceWords.joinToString(" · "),
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            GRADES.forEach { grade ->
                EcButton(
                    label = gradeLabel(grade),
                    onClick = { onGrade(grade) },
                    modifier = Modifier.weight(1f),
                    kind = if (grade == "good") EcButtonKind.PRIMARY else EcButtonKind.SECONDARY,
                    size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.SM,
                    enabled = !grading,
                )
            }
        }

        if (grading) {
            Text(text = "正在记录…", fontSize = EcFont.micro, color = EcColor.muted)
        }
    }
}

// ---------------------------------------------------------------------------
// 薄弱音素
// ---------------------------------------------------------------------------

@Composable
private fun ReviewWeakSection(
    items: List<ReviewWeakPhonemeDto>,
    isChild: Boolean,
    labelOf: (ReviewWeakPhonemeDto) -> String,
    barOf: (ReviewWeakPhonemeDto) -> Float,
) {
    StatCard {
        Text(
            text = if (isChild) "哪些音我常说不好" else "音素掌握度（最弱在前）",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        items.forEach { item ->
            Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = labelOf(item),
                        modifier = Modifier.weight(1f),
                        fontSize = EcFont.body,
                        fontWeight = FontWeight.Medium,
                        color = EcColor.ink,
                    )
                    if (isChild) {
                        Text(
                            text = "练过 ${item.attempts} 次",
                            fontSize = EcFont.micro,
                            color = EcColor.muted,
                        )
                    } else {
                        Text(
                            text = scoreText(item.avgScore) + " 分",
                            fontSize = EcFont.caption,
                            color = EcScore.color(item.avgScore, false),
                        )
                    }
                }
                if (!isChild) {
                    StatsProgressBar(fraction = barOf(item))
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 高频错词
// ---------------------------------------------------------------------------

@Composable
private fun ReviewWordErrorSection(
    state: ReviewUiState,
    isChild: Boolean,
) {
    StatCard {
        Text(
            text = "高频错词（单词级粗评）",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        state.wordErrors.chunked(2).forEach { rowItems ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                rowItems.forEach { item ->
                    val suffix = if (isChild) {
                        " × ${item.count}"
                    } else {
                        " × ${item.count}（均 ${scoreText(item.avgScore)}）"
                    }
                    EcPill(text = item.word + suffix, tone = PillTone.WARN)
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

private val GRADES = listOf("again", "hard", "good", "easy")

private fun scoreText(score: Double?): String {
    if (score == null) return "—"
    val rounded = kotlin.math.round(score * 10) / 10.0
    return if (rounded % 1.0 == 0.0) rounded.toInt().toString() else rounded.toString()
}

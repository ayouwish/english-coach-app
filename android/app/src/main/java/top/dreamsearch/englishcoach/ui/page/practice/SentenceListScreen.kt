package top.dreamsearch.englishcoach.ui.page.practice

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcPill
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

/**
 * 句子列表（二级页 `@Composable fun SentenceListScreen(onBack: () -> Unit)`）。
 *
 * 移植自 hos `pages/SentenceListPage.ets`：
 * - 当前等级全部句子（等级 chips 可切换；账号 C1 → 默认 B2）；
 * - 高亮「当前句」（本地练习游标，线上无 `/practice/cursor`）；
 * - 点一句 → 写 [top.dreamsearch.englishcoach.ui.nav.NavParams.practiceSentenceId] 后 `onBack()`
 *   回到跟读 Tab（跟读 Tab 在进入组合时读取该参数定位并清空）；
 * - 列表带缓存：先显示缓存、后台刷新（`CacheStore.readJson/writeJson`）；
 * - 三态齐全：loading 骨架 / error（ErrorBanner + 重试）/ empty（EmptyState + 换等级）。
 */
@Composable
fun SentenceListScreen(onBack: () -> Unit) {
    val vm: SentenceListViewModel = viewModel(
        factory = remember { vmFactory { SentenceListViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current

    PageScaffold(title = "句子列表", onBack = onBack) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
            // 等级切换（儿童/成人字号由 EcChip 统一处理）
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = EcSpace.x4, vertical = EcSpace.x2),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                state.levels.forEach { level ->
                    EcChip(
                        label = level,
                        selected = state.level == level,
                        onClick = { vm.selectLevel(level) },
                    )
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = EcSpace.x4, vertical = EcSpace.x1),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text(
                    text = if (state.sentences.isEmpty()) "" else "共 ${state.sentences.size} 句",
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                    modifier = Modifier.weight(1f),
                )
                if (state.refreshing) {
                    Text(text = "更新中…", fontSize = EcFont.micro, color = EcColor.muted)
                }
            }

            when {
                state.loading && state.sentences.isEmpty() -> LoadingBlock(text = "正在取句子…")

                state.sentences.isEmpty() && state.error != null -> Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = EcSpace.x4, vertical = EcSpace.x2),
                ) {
                    ErrorBanner(error = state.error, onRetry = vm::reload)
                }

                state.isEmpty -> EmptyState(
                    icon = "📚",
                    message = if (isChild) "这个等级还没有句子，换一个等级看看吧" else "这个等级还没有句子，换一个等级试试",
                    actionLabel = "换个等级",
                    onAction = { vm.selectLevel(if (state.level == "A1") "A2" else "A1") },
                )

                else -> LazyColumn(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentPadding = PaddingValues(
                        start = EcSpace.x4,
                        end = EcSpace.x4,
                        top = EcSpace.x2,
                        bottom = EcSpace.x6,
                    ),
                    verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
                ) {
                    // 有缓存但刷新失败：列表仍可用 + 顶部错误条可重试
                    if (state.error != null) {
                        item(key = "refresh_error") {
                            ErrorBanner(error = state.error, onRetry = vm::reload)
                        }
                    }
                    items(items = state.sentences, key = { it.id }) { sentence ->
                        SentenceListItem(
                            sentence = sentence,
                            isChild = isChild,
                            isCurrent = sentence.id == state.currentSentenceId,
                            onClick = {
                                vm.pick(sentence.id)
                                onBack()
                            },
                        )
                    }
                }
            }
        }
    }
}

/** 单句卡片：英文 + 翻译 + 等级/focus 标签；当前句加高亮环。 */
@Composable
private fun SentenceListItem(
    sentence: PracticeSentenceUi,
    isChild: Boolean,
    isCurrent: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(EcRadius.lg)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            // 高亮当前句：主色浅底当"2dp 环"（EcCard 自带圆角/阴影，外层补一圈）
            .background(if (isCurrent) EcColor.primarySoft else EcColor.bg)
            .padding(EcSpace.x1),
    ) {
        EcCard(onClick = onClick) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcPill(text = sentence.level, tone = PillTone.INFO)
                if (!isChild) {
                    sentence.focusPhonemes.take(3).forEach { phoneme ->
                        EcPill(text = phoneme, tone = PillTone.NEUTRAL)
                    }
                }
                Spacer(modifier = Modifier.weight(1f))
                if (isCurrent) {
                    EcPill(text = "正在练", tone = PillTone.GOOD)
                }
                Text(text = "›", fontSize = EcFont.h3, color = EcColor.primary)
            }
            Text(
                text = sentence.text,
                fontSize = if (isChild) EcFont.body else EcFont.sentence,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
            if (sentence.translation.isNotEmpty()) {
                Text(text = sentence.translation, fontSize = EcFont.caption, color = EcColor.muted)
            }
        }
    }
}

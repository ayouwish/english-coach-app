package top.dreamsearch.englishcoach.ui.page.story

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.stickyHeader
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RemoteImage
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild
import top.dreamsearch.englishcoach.ui.nav.NavParams
import top.dreamsearch.englishcoach.ui.nav.Navigator
import top.dreamsearch.englishcoach.ui.nav.Routes

/**
 * 故事模式（一级 Tab 页，`Tabs.STORY`）：故事集 + 「讲一个故事」入口。
 *
 * 对应 hos：`hos/entry/src/main/ets/pages/StoryHomePage.ets`（结构/文案照抄）。
 * 数据：`StoryService.materials(kind, 50)`，家庭共享、服务端已排序。
 * 导航：本页没有 navController 参数 → 用全局 [Navigator] push 二级页，
 * 点卡片前先写 `NavParams.storyMaterialId`（契约 §2.7）。
 *
 * 状态：loading（LoadingBlock）/ error（ErrorBanner + 重试）/ empty（EmptyState）/ 正常列表。
 * 第二轮：列表按「今天/昨天/更早」分组（组标题 stickyHeader 吸顶）+ 顶部「🔥 连续讲故事 N 天」。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun StoryHomeTab() {
    val vm: StoryHomeViewModel = viewModel(
        factory = remember { vmFactory { StoryHomeViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(EcColor.bg),
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = EcSpace.x4,
                end = EcSpace.x4,
                top = EcSpace.x4,
                bottom = EcSpace.x2,
            ),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            item(key = "header") { StoryHomeHeader(isChild, state.streakDays) }
            item(key = "hero") { StoryHeroCard(isChild) }
            item(key = "kind") {
                KindRow(
                    kind = state.kind,
                    count = state.items.size,
                    onKind = { vm.setKind(it) },
                )
            }
            if (state.allItems.isNotEmpty() || state.onlyMine) {
                item(key = "owner") {
                    OwnerRow(
                        onlyMine = state.onlyMine,
                        onOnlyMine = { vm.setOnlyMine(it) },
                    )
                }
            }

            when {
                state.loading -> item(key = "loading") {
                    LoadingBlock(text = "正在打开故事书…")
                }

                state.error != null -> item(key = "error") {
                    ErrorBanner(error = state.error, onRetry = { vm.retry() })
                }

                state.items.isEmpty() -> item(key = "empty") {
                    StoryHomeEmpty(state = state, isChild = isChild, vm = vm)
                }

                else -> {
                    state.groups.forEach { group ->
                        stickyHeader(key = "group_${group.label}") {
                            StoryGroupHeader(group)
                        }
                        items(group.items, key = { it.id }) { item ->
                            StoryRow(item)
                        }
                    }
                }
            }

            item(key = "footer") {
                StoryFooterNote("故事保存在家庭共享的书架上，全家都能看到。")
            }
        }
    }
}

// ------------------------------------------------------------------ 页头 / 入口

@Composable
private fun StoryHomeHeader(isChild: Boolean, streakDays: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
        Text(
            text = if (isChild) "📖 我的故事书" else "📖 我的故事",
            modifier = Modifier.fillMaxWidth(),
            fontSize = if (isChild) EcFont.childH1 else EcFont.h1,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Text(
            text = if (isChild) {
                "用中文讲讲今天发生的事，我帮你变英文故事"
            } else {
                "中文讲、中文写都可以；存下来就是家庭共享的英文故事书"
            },
            modifier = Modifier.fillMaxWidth(),
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        // 「🔥 连续讲故事 N 天」：按本机看过的故事日期算；没有数据不显示
        if (streakDays > 0) {
            Row(
                modifier = Modifier.padding(top = EcSpace.x1),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                EcPill(
                    text = if (isChild) {
                        "🔥 连续 $streakDays 天，真棒"
                    } else {
                        "🔥 连续讲故事 $streakDays 天"
                    },
                    tone = PillTone.WARN,
                )
            }
        }
    }
}

/** 日期分组标题（stickyHeader 吸顶；带底色避免与卡片内容重叠看不清）。 */
@Composable
private fun StoryGroupHeader(group: StoryGroup) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(EcColor.bg)
            .padding(vertical = EcSpace.x1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "${group.label} · ${group.items.size} 篇",
            fontSize = EcFont.caption,
            fontWeight = FontWeight.Medium,
            color = EcColor.muted,
        )
    }
}

@Composable
private fun StoryHeroCard(isChild: Boolean) {
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            Text(text = "✨", fontSize = 30.sp)
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = if (isChild) "讲一个今天的故事" else "讲一个故事",
                    modifier = Modifier.fillMaxWidth(),
                    fontSize = EcFont.h3,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                Text(
                    text = "说点子：今天发生了什么？和谁一起？你开心吗？",
                    modifier = Modifier.fillMaxWidth(),
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
            }
        }
        EcButton(
            label = if (isChild) "🎤 我要讲故事" else "✨ 讲一个故事",
            onClick = { Navigator.navigate(Routes.STORY_RECORD) },
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            fullWidth = true,
        )
    }
}

/** 故事 / 书页切换 + 当前条数。 */
@Composable
private fun KindRow(kind: String, count: Int, onKind: (String) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        EcChip(
            label = "故事",
            selected = kind == StoryHomeViewModel.KIND_STORY,
            onClick = { onKind(StoryHomeViewModel.KIND_STORY) },
        )
        EcChip(
            label = "书页",
            selected = kind == StoryHomeViewModel.KIND_PAGE,
            onClick = { onKind(StoryHomeViewModel.KIND_PAGE) },
        )
        Spacer(modifier = Modifier.weight(1f))
        Text(text = "共 $count 篇", fontSize = EcFont.micro, color = EcColor.muted)
    }
}

/** 全家 / 只看我的（客户端过滤，不请求接口）。 */
@Composable
private fun OwnerRow(onlyMine: Boolean, onOnlyMine: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        EcChip(label = "全家", selected = !onlyMine, onClick = { onOnlyMine(false) })
        EcChip(label = "只看我的", selected = onlyMine, onClick = { onOnlyMine(true) })
    }
}

@Composable
private fun StoryHomeEmpty(state: StoryHomeUiState, isChild: Boolean, vm: StoryHomeViewModel) {
    when {
        state.onlyMine && state.allItems.isNotEmpty() -> EmptyState(
            icon = "🔍",
            message = "你还没有讲过故事。先看看全家故事吧。",
            actionLabel = "看全家故事",
            onAction = { vm.setOnlyMine(false) },
        )

        state.kind == StoryHomeViewModel.KIND_PAGE -> EmptyState(
            icon = "📄",
            message = "还没有书页。去「连读」里拍照或导入一段文字，保存后就会出现在这里。",
            actionLabel = "看故事",
            onAction = { vm.setKind(StoryHomeViewModel.KIND_STORY) },
        )

        else -> EmptyState(
            icon = "📖",
            message = if (isChild) {
                "还没有故事。讲讲今天发生的事，存下来就是你的第一本英文故事书。"
            } else {
                "还没有故事。讲讲今天发生的事，存下来就是你的第一本英文故事书。"
            },
            actionLabel = "讲一个故事",
            onAction = { Navigator.navigate(Routes.STORY_RECORD) },
        )
    }
}

// ------------------------------------------------------------------ 卡片

@Composable
private fun StoryRow(item: StoryListItem) {
    EcCard(
        onClick = {
            NavParams.storyMaterialId = item.id
            Navigator.navigate(Routes.STORY_DETAIL)
        },
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            StoryCover(item)
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
            ) {
                Text(
                    text = item.title,
                    modifier = Modifier.fillMaxWidth(),
                    fontSize = EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
                ) {
                    if (item.level.isNotEmpty()) {
                        EcPill(text = item.level, tone = PillTone.INFO)
                    }
                    Text(
                        text = "${item.sentenceCount} 句",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                    if (item.dateText.isNotEmpty()) {
                        Text(text = item.dateText, fontSize = EcFont.micro, color = EcColor.muted)
                    }
                    if (item.authorName.isNotEmpty()) {
                        Text(
                            text = "· ${item.authorName}",
                            fontSize = EcFont.micro,
                            color = EcColor.muted,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
            Text(text = "›", fontSize = 22.sp, color = EcColor.muted)
        }
    }
}

/** 封面：有图走鉴权接口图；无图/失败用渐变占位（不显示破图）。 */
@Composable
private fun StoryCover(item: StoryListItem) {
    val shape = RoundedCornerShape(EcRadius.md)
    Box(modifier = Modifier.size(56.dp).clip(shape)) {
        if (item.hasImage) {
            RemoteImage(
                path = "/materials/${item.id}/image",
                contentDescription = item.title,
                modifier = Modifier.fillMaxSize(),
                withAuth = true,
                fallback = { StoryCoverPlaceholder(item.kind) },
            )
        } else {
            StoryCoverPlaceholder(item.kind)
        }
    }
}

@Composable
private fun StoryCoverPlaceholder(kind: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(EcColor.primarySoft, EcColor.surfaceAlt))),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = if (kind == StoryHomeViewModel.KIND_PAGE) "📄" else "📖",
            fontSize = EcFont.h3,
        )
    }
}

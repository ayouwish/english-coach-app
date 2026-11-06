package top.dreamsearch.englishcoach.ui.page.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioDto
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcSwitchRow
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild
import top.dreamsearch.englishcoach.ui.nav.NavParams
import top.dreamsearch.englishcoach.ui.nav.Navigator
import top.dreamsearch.englishcoach.ui.nav.Routes

/**
 * 对话训练 · 场景列表（Tab 根页，对应 hos `pages/ChatScenariosPage.ets`）。
 *
 * 结构：
 * - 头部：标题 + 「对话历史」入口 + 今日用量 + 自动朗读开关 + 语速（慢速/正常）；
 * - 我的自定义场景（N）+「＋ 自定义场景」；
 * - 成人场景（默认只看成人）→「再看小朋友的场景」开关 → 小朋友的场景；
 * - 儿童账号只看服务端返回的适龄场景（不显示开关，大字号）。
 *
 * 点击场景卡 → `POST /chat/sessions` → 写 `NavParams.chatSessionId` → push 会话页。
 * 数据全部由 [ChatScenariosViewModel] 拉取，本页不发请求。
 */
@Composable
fun ChatScenariosTab() {
    val vm: ChatScenariosViewModel = viewModel(
        factory = remember { vmFactory { ChatScenariosViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current

    // 开会话成功 → 写跨页参数并导航（导航层负责 push）
    LaunchedEffect(state.pendingSessionId) {
        val sessionId = state.pendingSessionId
        if (sessionId.isNotEmpty()) {
            NavParams.chatSessionId = sessionId
            Navigator.navigate(Routes.CHAT_SESSION)
            vm.consumePendingSession()
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(EcColor.bg)) {
        ScenariosHeader(
            state = state,
            onOpenHistory = { Navigator.navigate(Routes.CHAT_HISTORY) },
            onAutoReadChange = vm::setAutoRead,
            onRateChange = vm::setTtsRate,
        )

        LazyColumn(
            modifier = Modifier.fillMaxWidth().weight(1f),
            contentPadding = PaddingValues(
                start = EcSpace.x4,
                end = EcSpace.x4,
                top = EcSpace.x1,
                bottom = EcSpace.x4,
            ),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            if (state.quotaExceeded) {
                item(key = "quota") {
                    ChatWarnLine(
                        text = state.quotaText.ifEmpty {
                            if (isChild) "今天已经练得很棒啦，明天再来 🌙" else "今天的练习时间到了，明天再来"
                        },
                        icon = "🌙",
                    )
                }
            }
            if (state.error != null) {
                item(key = "error") {
                    ErrorBanner(error = state.error, onRetry = { vm.load() })
                }
            }

            when {
                state.loading -> item(key = "loading") { LoadingBlock(text = "正在取场景…") }

                state.customItems.isEmpty() && state.adultItems.isEmpty() && state.childItems.isEmpty() -> {
                    item(key = "empty") {
                        EmptyState(
                            icon = "💬",
                            message = if (isChild) {
                                "现在还没有适合你的场景，等一下再来看看吧"
                            } else {
                                "暂时没有可用场景，点「＋ 自定义场景」写一个你自己的"
                            },
                            actionLabel = "＋ 自定义场景",
                            onAction = { openCreateCustom() },
                        )
                    }
                }

                else -> {
                    item(key = "custom_title") {
                        SectionHeader(
                            title = "我的自定义场景（${state.customItems.size}）",
                            actionLabel = "＋ 自定义场景",
                            onAction = { openCreateCustom() },
                        )
                    }
                    if (state.customItems.isEmpty()) {
                        item(key = "custom_empty") {
                            Text(
                                text = "还没有自定义场景；点「＋ 自定义场景」写一个你自己的。\n可以自定义角色设定和开场白，练你想练的生活场景。",
                                fontSize = EcFont.caption,
                                color = EcColor.muted,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(EcRadius.lg))
                                    .background(EcColor.surface)
                                    .padding(EcSpace.x4),
                            )
                        }
                    } else {
                        items(state.customItems, key = { "custom_${it.id}" }) { item ->
                            CustomScenarioCard(
                                item = item,
                                isChild = isChild,
                                starting = state.startingId == item.id,
                                onClick = { vm.start(item) },
                                onEdit = { openEditCustom(item) },
                            )
                        }
                    }

                    if (isChild) {
                        item(key = "child_title") {
                            SectionHeader(title = "选一个场景开始（${state.childItems.size}）")
                        }
                        items(state.childItems, key = { "child_${it.id}" }) { item ->
                            ScenarioCard(
                                item = item,
                                isChild = true,
                                starting = state.startingId == item.id,
                                onClick = { vm.start(item) },
                            )
                        }
                    } else {
                        item(key = "adult_title") {
                            SectionHeader(title = "成人场景（${state.adultItems.size}）")
                        }
                        items(state.adultItems, key = { "adult_${it.id}" }) { item ->
                            ScenarioCard(
                                item = item,
                                isChild = false,
                                starting = state.startingId == item.id,
                                onClick = { vm.start(item) },
                            )
                        }
                        item(key = "include_child") {
                            EcCard {
                                EcSwitchRow(
                                    title = "再看小朋友的场景",
                                    checked = state.includeChild,
                                    onCheckedChange = { vm.setIncludeChild(it) },
                                    subtitle = "默认只看成人场景；打开后会额外加载儿童场景",
                                )
                            }
                        }
                        if (state.includeChild) {
                            item(key = "child_title") {
                                SectionHeader(title = "小朋友的场景（${state.childItems.size}）")
                            }
                            if (state.childItems.isEmpty()) {
                                item(key = "child_empty") {
                                    Text(
                                        text = "暂时没有可用的儿童场景",
                                        fontSize = EcFont.caption,
                                        color = EcColor.muted,
                                        modifier = Modifier.padding(EcSpace.x3),
                                    )
                                }
                            } else {
                                items(state.childItems, key = { "ch_${it.id}" }) { item ->
                                    ScenarioCard(
                                        item = item,
                                        isChild = false,
                                        starting = state.startingId == item.id,
                                        onClick = { vm.start(item) },
                                    )
                                }
                            }
                        }
                    }

                    item(key = "footer") {
                        Text(
                            text = "点场景卡就开始了；对话里只有语音输入，没有文字输入框。",
                            fontSize = EcFont.micro,
                            color = EcColor.muted,
                            modifier = Modifier.padding(top = EcSpace.x2, bottom = EcSpace.x2),
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 头部
// ---------------------------------------------------------------------------

@Composable
private fun ScenariosHeader(
    state: ChatScenariosUiState,
    onOpenHistory: () -> Unit,
    onAutoReadChange: (Boolean) -> Unit,
    onRateChange: (String) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = EcSpace.x4, vertical = EcSpace.x3),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = if (state.isChild) "💬 和我聊聊天吧！" else "💬 对话训练",
                    fontSize = if (state.isChild) EcFont.childH1 else EcFont.h2,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                Text(
                    text = subtitleText(state),
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
            }
            Text(
                text = "🕘 历史",
                fontSize = EcFont.caption,
                fontWeight = FontWeight.Medium,
                color = EcColor.primary,
                modifier = Modifier
                    .clip(RoundedCornerShape(EcRadius.pill))
                    .background(EcColor.primarySoft)
                    .clickable(onClick = onOpenHistory)
                    .padding(horizontal = EcSpace.x3, vertical = EcSpace.x2),
            )
        }

        Text(
            text = usageText(state),
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )

        EcSwitchRow(
            title = "🔊 自动朗读",
            checked = state.autoRead,
            onCheckedChange = onAutoReadChange,
            subtitle = if (state.autoRead) "开着：回复后自动读一遍" else "关着：点气泡上的 ▶ 才读",
        )

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = "语速", fontSize = EcFont.caption, color = EcColor.muted)
            EcChip(
                label = "🐢 慢速",
                selected = state.ttsRate == "slow",
                onClick = { onRateChange("slow") },
            )
            EcChip(
                label = "🐇 正常",
                selected = state.ttsRate != "slow",
                onClick = { onRateChange("normal") },
            )
        }
    }
}

private fun subtitleText(state: ChatScenariosUiState): String {
    if (state.isChild) return "这里只显示适合你的场景。"
    val adult = state.adultItems.size
    return if (state.includeChild) {
        "成人场景 $adult 个，儿童场景 ${state.childItems.size} 个。"
    } else {
        "成人场景 $adult 个。想练小朋友的场景？打开下面的开关。"
    }
}

private fun usageText(state: ChatScenariosUiState): String {
    val text = "今日已练 ${state.minutesToday}/${state.dailyLimitMinutes} 分钟"
    return if (state.isChild) "$text · 还剩 ${state.remainingMinutes} 分钟" else text
}

// ---------------------------------------------------------------------------
// 卡片
// ---------------------------------------------------------------------------

/** 内置场景卡：emoji + 英文标题 + 中文标题 + level/min_age + setting。 */
@Composable
private fun ScenarioCard(
    item: ChatScenarioDto,
    isChild: Boolean,
    starting: Boolean,
    onClick: () -> Unit,
) {
    EcCard(onClick = onClick) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(EcRadius.md))
                    .background(EcColor.surfaceAlt),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = emojiForScenario(item), fontSize = if (isChild) 28.sp else 24.sp)
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
            ) {
                Text(
                    text = item.title.ifEmpty { item.id },
                    fontSize = if (isChild) EcFont.childBody else EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (item.titleZh.isNotEmpty()) {
                    Text(
                        text = item.titleZh,
                        fontSize = EcFont.caption,
                        color = EcColor.primary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                ) {
                    if (item.level.isNotEmpty()) {
                        EcPill(text = item.level, tone = PillTone.INFO)
                    }
                    if (item.minAge > 0) {
                        EcPill(text = "${item.minAge}+ 岁", tone = PillTone.NEUTRAL)
                    }
                    if (item.isCustom) {
                        EcPill(text = "我的场景", tone = PillTone.GOOD)
                    }
                }
                if (item.settingZh.isNotEmpty()) {
                    Text(
                        text = item.settingZh,
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (starting) {
                CircularProgressIndicator(
                    modifier = Modifier.size(22.dp),
                    color = EcColor.primary,
                    strokeWidth = 2.dp,
                )
            } else {
                Text(text = "›", fontSize = 24.sp, color = EcColor.muted)
            }
        }
    }
}

/** 自定义场景卡：点击开始对话，右侧「编辑」进自定义页。 */
@Composable
private fun CustomScenarioCard(
    item: ChatScenarioDto,
    isChild: Boolean,
    starting: Boolean,
    onClick: () -> Unit,
    onEdit: () -> Unit,
) {
    EcCard(onClick = onClick) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = emojiForScenario(item), fontSize = 24.sp)
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = item.title.ifEmpty { item.id },
                    fontSize = if (isChild) EcFont.childBody else EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (item.titleZh.isNotEmpty()) {
                    Text(
                        text = item.titleZh,
                        fontSize = EcFont.caption,
                        color = EcColor.primary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (starting) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = EcColor.primary,
                    strokeWidth = 2.dp,
                )
            } else {
                Text(text = "开始 ›", fontSize = EcFont.caption, color = EcColor.primary)
            }
        }
        if (item.settingZh.isNotEmpty()) {
            Text(
                text = item.settingZh,
                fontSize = EcFont.micro,
                color = EcColor.muted,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            if (item.level.isNotEmpty()) {
                EcPill(text = item.level, tone = PillTone.INFO)
            }
            if (item.variationCount > 0) {
                EcPill(text = "开场白变体 ${item.variationCount}", tone = PillTone.NEUTRAL)
            }
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = "编辑",
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(onClick = onEdit)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
            )
        }
    }
}

/** 分组小标题（左标题 + 右文字动作）。 */
@Composable
private fun SectionHeader(
    title: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = EcSpace.x3, bottom = EcSpace.x1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            fontSize = EcFont.caption,
            fontWeight = FontWeight.Medium,
            color = EcColor.muted,
            modifier = Modifier.weight(1f),
        )
        if (actionLabel != null && onAction != null) {
            Text(
                text = actionLabel,
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(onClick = onAction)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// 导航入口
// ---------------------------------------------------------------------------

/** 「＋ 自定义场景」：进自定义页并直接打开新建表单。 */
private fun openCreateCustom() {
    ChatCustomHandoff.createOnOpen = true
    Navigator.navigate(Routes.CHAT_CUSTOM)
}

/** 自定义场景卡「编辑」：进自定义页并直接打开编辑表单。 */
private fun openEditCustom(item: ChatScenarioDto) {
    ChatCustomHandoff.editScenario = item
    Navigator.navigate(Routes.CHAT_CUSTOM)
}

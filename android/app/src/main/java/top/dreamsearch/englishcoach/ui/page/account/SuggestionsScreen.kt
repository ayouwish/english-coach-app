package top.dreamsearch.englishcoach.ui.page.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.dto.SuggestionDto
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcDialog
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace

/**
 * 建议箱（`Routes.SUGGESTIONS`；对应 hos `pages/SuggestionsPage.ets`）。
 *
 * 一页两用：
 * - **所有人（含儿童）**：选分类 + 写内容 + 提交（成人 5 类 / 儿童 3 类，正文 ≤ max_length）；
 * - **家长追加**：筛选（全部/未读/已读/已解决）+ 列表 + 标记已读/已解决 + 导出 Markdown
 *   （**弹层展示 + 复制到剪贴板**，不下载文件——移动端不实现 Web 的导出下载）。
 *
 * 儿童只渲染提交区（不请求列表、不显示筛选/导出），与服务端 403 双保险。
 */
@Composable
fun SuggestionsScreen(onBack: () -> Unit) {
    val vm: SuggestionsViewModel = viewModel(
        factory = remember { vmFactory { SuggestionsViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val clipboard = LocalClipboardManager.current

    PageScaffold(
        title = if (state.isChild) "我想说" else "建议箱",
        onBack = onBack,
        actions = {
            if (!state.isChild) {
                Text(
                    text = if (state.listLoading) "刷新中…" else "刷新",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(enabled = !state.listLoading) { vm.loadList() }
                        .padding(horizontal = EcSpace.x3, vertical = EcSpace.x2),
                )
            }
        },
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
            item(key = "header") { SuggestionsHeader(state) }
            item(key = "submit") { SubmitCard(state, vm) }

            if (!state.isChild) {
                item(key = "filters") { FilterRow(state, vm) }

                if (state.listError != null) {
                    item(key = "list-error") {
                        ErrorBanner(error = state.listError, onRetry = { vm.retryList() })
                    }
                }

                if (state.listLoading && !state.listLoadedOnce) {
                    item(key = "list-loading") { LoadingBlock(text = "正在读取建议…") }
                } else if (state.items.isEmpty()) {
                    item(key = "list-empty") {
                        EmptyState(
                            icon = "💡",
                            message = "这里还没有建议。家人用的时候可以在这里随手留言。",
                        )
                    }
                } else {
                    items(state.items, key = { it.id }) { item ->
                        SuggestionRow(item = item, marking = state.markingId == item.id, vm = vm)
                    }
                }

                item(key = "export") { ExportCard(state, vm) }
            } else {
                item(key = "child-note") {
                    Text(
                        text = "写下的建议会记在家庭建议箱里，家长可以统一查看。",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
            }
        }
    }

    // 导出结果弹层：只展示 + 复制（不写文件、不分享）
    if (state.exportVisible) {
        EcDialog(title = "Markdown 导出", onDismiss = { vm.dismissExport() }) {
            if (state.exportNotice.isNotEmpty()) {
                Text(text = state.exportNotice, fontSize = EcFont.micro, color = EcColor.goodText)
            }
            Text(
                text = state.exportText,
                fontSize = EcFont.micro,
                color = EcColor.ink,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 320.dp)
                    .verticalScroll(rememberScrollState()),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "关闭",
                    onClick = { vm.dismissExport() },
                    kind = EcButtonKind.GHOST,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = "一键复制",
                    onClick = {
                        clipboard.setText(AnnotatedString(state.exportText))
                        vm.onCopied()
                    },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

// ------------------------------------------------------------------ 头部 / 提交

@Composable
private fun SuggestionsHeader(state: SuggestionsUiState) {
    EcCard {
        Text(
            text = if (state.isChild) "💡 我想说点什么" else "💡 提建议",
            fontSize = EcFont.h3,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Text(
            text = if (state.isChild) {
                "用起来哪里不顺手、想读什么故事、想加什么功能，都可以告诉我 🙂"
            } else {
                "哪里不好用、想要什么功能、内容有什么问题，都记在这里；家长可以统一查看和导出。"
            },
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        if (!state.isChild) {
            Row(horizontalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
                EcPill(text = "未读 ${state.counts?.open ?: 0}", tone = PillTone.WARN)
                EcPill(text = "已读 ${state.counts?.read ?: 0}", tone = PillTone.INFO)
                EcPill(text = "已解决 ${state.counts?.resolved ?: 0}", tone = PillTone.GOOD)
                EcPill(text = "共 ${state.total} 条", tone = PillTone.NEUTRAL)
            }
        }
    }
}

@Composable
private fun SubmitCard(state: SuggestionsUiState, vm: SuggestionsViewModel) {
    EcCard {
        Text(
            text = if (state.isChild) "想说的话" else "具体内容",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        CategoryChips(state, vm)
        EcTextField(
            value = state.content,
            onValueChange = { vm.setContent(it) },
            label = "内容",
            placeholder = if (state.isChild) {
                "比如：我想读恐龙的故事"
            } else {
                "例如：跟读页的示范音有时要等很久…"
            },
            singleLine = false,
            enabled = !state.submitting,
            modifier = Modifier.heightIn(min = 112.dp),
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "${state.content.length} / ${state.maxLength}",
                fontSize = EcFont.micro,
                color = EcColor.muted,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "页面：/settings（自动带上）",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
        if (state.submitError.isNotEmpty()) {
            Text(text = state.submitError, fontSize = EcFont.caption, color = EcColor.badText)
        }
        if (state.notice.isNotEmpty()) {
            Text(
                text = state.notice,
                fontSize = EcFont.caption,
                color = EcColor.goodText,
                modifier = Modifier.clickable { vm.clearNotice() },
            )
        }
        EcButton(
            label = when {
                state.submitting -> "提交中…"
                state.isChild -> "✉️ 发送给爸爸妈妈"
                else -> "提交建议"
            },
            onClick = { vm.submit() },
            loading = state.submitting,
            size = if (state.isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            fullWidth = true,
        )
    }
}

/** 分类 chips：成人 5 类 / 儿童 3 类，两行折行（不引入实验性 FlowRow）。 */
@Composable
private fun CategoryChips(state: SuggestionsUiState, vm: SuggestionsViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
        state.categories.chunked(2).forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                row.forEach { item ->
                    Column(modifier = Modifier.weight(1f)) {
                        EcChip(
                            label = if (state.isChild) item.childLabel else item.adultLabel,
                            selected = state.category == item.key,
                            onClick = { vm.setCategory(item.key) },
                        )
                    }
                }
                if (row.size == 1) {
                    Column(modifier = Modifier.weight(1f)) {}
                }
            }
        }
    }
}

// ------------------------------------------------------------------ 家长列表

private val filterKeys = listOf("", "open", "read", "resolved")
private val filterLabels = listOf("全部", "未读", "已读", "已解决")

@Composable
private fun FilterRow(state: SuggestionsUiState, vm: SuggestionsViewModel) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
    ) {
        filterKeys.forEachIndexed { index, key ->
            EcChip(
                label = filterLabels[index],
                selected = state.filterStatus == key,
                onClick = { vm.setFilter(key) },
            )
        }
    }
}

@Composable
private fun SuggestionRow(item: SuggestionDto, marking: Boolean, vm: SuggestionsViewModel) {
    EcCard {
        Text(text = item.content, fontSize = EcFont.body, color = EcColor.ink)
        Row(
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            EcPill(text = AccountFormat.roleLabel(item.userRole), tone = PillTone.NEUTRAL)
            EcPill(text = AccountFormat.categoryLabel(item.category, false), tone = PillTone.INFO)
            EcPill(text = AccountFormat.statusLabel(item.status), tone = AccountFormat.statusTone(item.status))
        }
        Text(
            text = "页面 ${item.page} · ${AccountFormat.dateText(item.createdAt)}",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            if (item.status == "open") {
                EcButton(
                    label = if (marking) "处理中…" else "👁 标记已读",
                    onClick = { vm.mark(item.id, "read") },
                    kind = EcButtonKind.SECONDARY,
                    size = EcButtonSizeKind.SM,
                    modifier = Modifier.weight(1f),
                    enabled = !marking,
                )
            }
            if (item.status != "resolved") {
                EcButton(
                    label = "✅ 标记已解决",
                    onClick = { vm.mark(item.id, "resolved") },
                    kind = EcButtonKind.GHOST,
                    size = EcButtonSizeKind.SM,
                    modifier = Modifier.weight(1f),
                    enabled = !marking,
                )
            }
        }
    }
}

@Composable
private fun ExportCard(state: SuggestionsUiState, vm: SuggestionsViewModel) {
    EcCard {
        Text(
            text = "导出给开发者",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        Text(
            text = "把当前筛选下的建议导出成 Markdown，弹层里展示并可一键复制（不下载文件）。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
        EcButton(
            label = if (state.exporting) "生成中…" else "导出 Markdown",
            onClick = { vm.exportMarkdown() },
            kind = EcButtonKind.SECONDARY,
            loading = state.exporting,
            fullWidth = true,
        )
        if (state.exportError.isNotEmpty()) {
            Text(text = state.exportError, fontSize = EcFont.caption, color = EcColor.badText)
        } else if (state.exportNotice.isNotEmpty() && !state.exportVisible) {
            Text(text = state.exportNotice, fontSize = EcFont.micro, color = EcColor.goodText)
        }
        if (state.exportText.isNotEmpty() && !state.exportVisible) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "上次导出 ${state.exportText.length} 字",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "再打开",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable { vm.exportMarkdown() }
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
                )
                Text(
                    text = "清空",
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                    modifier = Modifier
                        .clickable { vm.clearExportText() }
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
                )
            }
        }
    }
}

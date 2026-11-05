package top.dreamsearch.englishcoach.ui.page.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioDto
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcDialog
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 自定义对话场景（`Routes.CHAT_CUSTOM`，对应 hos `pages/ChatCustomPage.ets`）。
 *
 * Android 页签名固定为 `ChatCustomScreen(onBack)`，所以把「我的场景列表 + 新建/编辑表单 +
 * 删除确认」放在同一页：
 * - 列表：`GET /chat/scenarios?include_child=1` 里 `is_custom == true`；
 * - 新建：`POST /chat/scenarios`；编辑：`PATCH /chat/scenarios/:id`；删除：`DELETE /chat/scenarios/:id`；
 * - 前端校验与服务端同口径（标题 1–40、场景说明 1–200、角色设定 20–1500、开场白 5–200）；
 * - 儿童账号创建时 audience 强制 child；
 * - 成功后会刷新列表，并通知场景 Tab（[ChatRefreshBus]）。
 */
@Composable
fun ChatCustomScreen(onBack: () -> Unit) {
    val vm: ChatCustomViewModel = viewModel(
        factory = remember { vmFactory { ChatCustomViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    val form = state.form

    // 删除确认弹层
    if (state.confirmingDeleteId.isNotEmpty()) {
        EcDialog(title = "删除这个场景？", onDismiss = { vm.cancelDelete() }) {
            Text(
                text = "删除后就找不回来了，确定吗？",
                fontSize = EcFont.caption,
                color = EcColor.badText,
            )
            EcButton(
                label = "确认删除",
                onClick = { vm.confirmDelete() },
                kind = EcButtonKind.DANGER,
                loading = state.saving,
                fullWidth = true,
            )
            EcButton(
                label = "先不删",
                onClick = { vm.cancelDelete() },
                kind = EcButtonKind.GHOST,
                enabled = !state.saving,
                fullWidth = true,
            )
        }
    }

    PageScaffold(
        title = when {
            form.open && form.editingId.isNotEmpty() -> "编辑自定义场景"
            form.open -> "新建自定义场景"
            else -> "自定义场景"
        },
        onBack = onBack,
        scrollable = true,
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(padding)
                .padding(horizontal = EcSpace.x4),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            Text(
                text = when {
                    form.open && form.editingId.isNotEmpty() ->
                        "改完点「保存修改」；角色设定留空则保持原来的设定。"
                    form.open ->
                        "写一个你想练的场景：角色设定和开场白都用英文，说出你自己的话。"
                    else ->
                        "自定义场景可以练你想练的生活场景；保存后回「对话」就能看到。"
                },
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )

            val saveError = state.saveError
            if (saveError != null) {
                ErrorBanner(error = saveError)
            }
            val loadError = state.error
            if (loadError != null && !state.loading) {
                ErrorBanner(error = loadError, onRetry = { vm.load() })
            }
            if (state.notice.isNotEmpty()) {
                EcInlineNotice(text = state.notice, tone = PillTone.GOOD)
            }

            if (form.open) {
                CustomFormCard(
                    state = state,
                    isChild = isChild,
                    onTitleChange = vm::updateTitle,
                    onTitleZhChange = vm::updateTitleZh,
                    onSettingChange = vm::updateSettingZh,
                    onRolePromptChange = vm::updateRolePrompt,
                    onOpeningChange = vm::updateOpeningLine,
                    onLevelChange = vm::setLevel,
                    onAudienceChange = vm::setAudience,
                    onSave = { vm.save() },
                    onCancel = { vm.closeForm() },
                )
            } else {
                EcButton(
                    label = "＋ 新建自定义场景",
                    onClick = { vm.openCreate() },
                    kind = EcButtonKind.PRIMARY,
                    size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                    fullWidth = true,
                )
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = EcSpace.x2),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "我的场景（${state.items.size}）",
                    fontSize = EcFont.caption,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.muted,
                )
            }

            if (state.loading) {
                LoadingBlock(text = "正在取自定义场景…")
            } else if (state.items.isEmpty()) {
                Text(
                    text = "还没有自定义场景。点上面的「＋ 新建自定义场景」写一个吧。",
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = EcSpace.x2),
                )
            } else {
                state.items.forEach { item ->
                    CustomItemCard(
                        item = item,
                        isChild = isChild,
                        busy = state.saving,
                        onEdit = { vm.openEdit(item) },
                        onDelete = { vm.requestDelete(item.id) },
                    )
                }
            }

            Spacer(modifier = Modifier.height(EcSpace.x8))
        }
    }
}

// ---------------------------------------------------------------------------
// 表单
// ---------------------------------------------------------------------------

@Composable
private fun CustomFormCard(
    state: ChatCustomUiState,
    isChild: Boolean,
    onTitleChange: (String) -> Unit,
    onTitleZhChange: (String) -> Unit,
    onSettingChange: (String) -> Unit,
    onRolePromptChange: (String) -> Unit,
    onOpeningChange: (String) -> Unit,
    onLevelChange: (String) -> Unit,
    onAudienceChange: (String) -> Unit,
    onSave: () -> Unit,
    onCancel: () -> Unit,
) {
    val form = state.form
    val buttonSize = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD
    EcCard {
        Text(
            text = if (form.editingId.isNotEmpty()) "编辑场景" else "新建场景",
            fontSize = EcFont.h3,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )

        // 英文标题
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            FieldLabel(title = "英文标题", hint = "1–40 个字符")
            EcTextField(
                value = form.title,
                onValueChange = onTitleChange,
                label = "英文标题",
                placeholder = "例如 My weekend plan",
                enabled = !state.saving,
            )
            FieldError(message = form.errors["title"])
        }

        // 中文标题
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            FieldLabel(title = "中文标题", hint = "1–40 个字符")
            EcTextField(
                value = form.titleZh,
                onValueChange = onTitleZhChange,
                label = "中文标题",
                placeholder = "例如 我的周末计划",
                enabled = !state.saving,
            )
            FieldError(message = form.errors["titleZh"])
        }

        // 场景说明
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            FieldLabel(title = "场景说明", hint = "1–200 个字符，中文")
            EcTextField(
                value = form.settingZh,
                onValueChange = onSettingChange,
                label = "场景说明",
                placeholder = "例如 你和朋友在聊周末安排",
                singleLine = false,
                enabled = !state.saving,
            )
            FieldError(message = form.errors["settingZh"])
        }

        // 角色设定
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            FieldLabel(
                title = "角色设定",
                hint = if (form.editingId.isNotEmpty()) "留空 = 不修改（20–1500 个字符）" else "20–1500 个字符，英文",
            )
            EcTextField(
                value = form.rolePrompt,
                onValueChange = onRolePromptChange,
                label = "角色设定",
                placeholder = "You are a friendly friend. Keep each reply under 15 words. Ask one question at a time.",
                singleLine = false,
                enabled = !state.saving,
            )
            FieldError(message = form.errors["rolePrompt"])
        }

        // 开场白
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            FieldLabel(title = "开场白", hint = "5–200 个字符，英文")
            EcTextField(
                value = form.openingLine,
                onValueChange = onOpeningChange,
                label = "开场白",
                placeholder = "Hey! Any plans for the weekend?",
                singleLine = false,
                enabled = !state.saving,
            )
            FieldError(message = form.errors["openingLine"])
        }

        // 难度
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            FieldLabel(title = "难度", hint = "")
            Row(horizontalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
                ChatCustomViewModel.LEVELS.forEach { level ->
                    EcChip(
                        label = level,
                        selected = form.level == level,
                        onClick = { onLevelChange(level) },
                    )
                }
            }
        }

        // 场景类型
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            FieldLabel(title = "场景类型", hint = "")
            if (isChild) {
                Text(
                    text = "小朋友场景（儿童账号只能创建「小朋友」场景）",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                )
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
                    EcChip(
                        label = "成人场景",
                        selected = form.audience != "child",
                        onClick = { onAudienceChange("adult") },
                    )
                    EcChip(
                        label = "小朋友的场景",
                        selected = form.audience == "child",
                        onClick = { onAudienceChange("child") },
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(EcSpace.x1))

        EcButton(
            label = if (form.editingId.isNotEmpty()) "保存修改" else "保存场景",
            onClick = onSave,
            kind = EcButtonKind.PRIMARY,
            size = buttonSize,
            loading = state.saving,
            fullWidth = true,
        )
        EcButton(
            label = "取消",
            onClick = onCancel,
            kind = EcButtonKind.GHOST,
            size = buttonSize,
            enabled = !state.saving,
            fullWidth = true,
        )
    }
}

// ---------------------------------------------------------------------------
// 列表项
// ---------------------------------------------------------------------------

@Composable
private fun CustomItemCard(
    item: ChatScenarioDto,
    isChild: Boolean,
    busy: Boolean,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    EcCard {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = emojiForScenario(item), fontSize = 22.sp)
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
            EcPill(
                text = if (item.audience == "child") "小朋友" else "成人",
                tone = if (item.audience == "child") PillTone.GOOD else PillTone.NEUTRAL,
            )
            Spacer(modifier = Modifier.weight(1f))
            EcButton(
                label = "编辑",
                onClick = onEdit,
                kind = EcButtonKind.SECONDARY,
                size = EcButtonSizeKind.SM,
                enabled = !busy,
            )
            Spacer(modifier = Modifier.width(EcSpace.x2))
            EcButton(
                label = "删除",
                onClick = onDelete,
                kind = EcButtonKind.DANGER,
                size = EcButtonSizeKind.SM,
                enabled = !busy,
            )
        }
    }
}

@Composable
private fun FieldLabel(title: String, hint: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = title,
            fontSize = EcFont.caption,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        if (hint.isNotEmpty()) {
            Text(text = hint, fontSize = EcFont.micro, color = EcColor.muted)
        }
    }
}

@Composable
private fun FieldError(message: String?) {
    if (!message.isNullOrEmpty()) {
        Text(text = message, fontSize = EcFont.micro, color = EcColor.badText)
    }
}

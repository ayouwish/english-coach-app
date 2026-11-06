package top.dreamsearch.englishcoach.ui.page.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.dto.FamilyMemberDto
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcDialog
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcSwitchRow
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace
import kotlin.math.roundToInt

/**
 * 家庭成员（`Routes.FAMILY`，仅家长；对应 hos `pages/FamilyPage.ets`）。
 *
 * 能力：列表 / 新建 / 编辑（昵称·等级·每日时长·自由对话）/ 重置密码。
 * **没有删除成员**：服务端未提供 `DELETE /family/members/:id`（AccountService 注释），页面不出现删除入口。
 * 所有写操作后重新拉列表（服务端为准），失败给出内联错误、保留输入。
 */
@Composable
fun FamilyScreen(onBack: () -> Unit) {
    val vm: FamilyViewModel = viewModel(
        factory = remember { vmFactory { FamilyViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val resettingMember = vm.resettingMember()

    PageScaffold(
        title = "家庭成员",
        onBack = onBack,
        actions = {
            Text(
                text = if (state.formVisible) "收起" else "＋ 添加成员",
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable { vm.toggleForm() }
                    .padding(horizontal = EcSpace.x3, vertical = EcSpace.x2),
            )
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
            item(key = "intro") { FamilyIntro() }

            if (state.formVisible) {
                item(key = "form") { CreateForm(state, vm) }
            }

            if (state.notice.isNotEmpty()) {
                item(key = "notice") {
                    Text(
                        text = state.notice,
                        fontSize = EcFont.caption,
                        color = EcColor.goodText,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { vm.clearNotice() },
                    )
                }
            }

            if (state.error != null) {
                item(key = "error") {
                    ErrorBanner(error = state.error, onRetry = { vm.retry() })
                }
            }

            when {
                state.loading -> item(key = "loading") {
                    LoadingBlock(text = "正在读取家庭成员…")
                }

                state.members.isEmpty() && state.error == null -> item(key = "empty") {
                    EmptyState(
                        icon = "👨‍👩‍👧",
                        message = "还没有其他成员，点右上角「＋ 添加成员」建一个吧。",
                        actionLabel = "添加成员",
                        onAction = { vm.toggleForm() },
                    )
                }

                else -> items(state.members, key = { it.id }) { member ->
                    MemberCard(member = member, state = state, vm = vm)
                }
            }

            item(key = "footer") {
                Text(
                    text = "密码由家长重置（不需要旧密码）。登录名可以只写简称，会自动补 @family.local。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                    modifier = Modifier.padding(bottom = EcSpace.x4),
                )
            }
        }
    }

    // 重置密码弹层（按 id 反查成员，避免页面再传参）
    if (state.resettingId.isNotEmpty() && resettingMember != null) {
        val targetName = resettingMember.displayName.ifEmpty { "成员" }
        EcDialog(title = "重置密码", onDismiss = { vm.cancelReset() }) {
            Text(
                text = "给「$targetName」设置新密码（至少 8 位）。" +
                    "旧密码会立即失效；已登录的设备仍可能在 refresh 到期前保持登录。",
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
            EcTextField(
                value = state.resetPassword,
                onValueChange = { vm.setResetPassword(it) },
                label = "新密码",
                placeholder = "至少 8 位",
                password = true,
            )
            if (state.resetError.isNotEmpty()) {
                Text(text = state.resetError, fontSize = EcFont.caption, color = EcColor.badText)
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "取消",
                    onClick = { vm.cancelReset() },
                    kind = EcButtonKind.GHOST,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = if (state.resetting) "保存中…" else "保存新密码",
                    onClick = { vm.resetPassword() },
                    loading = state.resetting,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

// ------------------------------------------------------------------ 说明 / 新建

@Composable
private fun FamilyIntro() {
    EcCard {
        Text(
            text = "👨‍👩‍👧 家庭成员",
            fontSize = EcFont.h3,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Text(
            text = "给家里人各建一个账号（不同英语水平）。登录名可以只写简称，会自动补 @family.local。",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
    }
}

@Composable
private fun CreateForm(state: FamilyUiState, vm: FamilyViewModel) {
    EcCard {
        Text(
            text = "添加成员",
            fontSize = EcFont.h3,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        EcTextField(
            value = state.formName,
            onValueChange = { vm.setFormName(it) },
            label = "昵称",
            placeholder = "比如：爸爸 / 奶奶",
            enabled = !state.creating,
        )
        EcTextField(
            value = state.formLogin,
            onValueChange = { vm.setFormLogin(it) },
            label = "登录名（可只写简称）",
            placeholder = "比如：dad2",
            enabled = !state.creating,
        )
        EcTextField(
            value = state.formPassword,
            onValueChange = { vm.setFormPassword(it) },
            label = "初始密码（至少 8 位）",
            placeholder = "至少 8 位",
            password = true,
            enabled = !state.creating,
        )

        FieldLabel("角色")
        Row(horizontalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
            EcChip(
                label = "孩子",
                selected = state.formRole == "child",
                onClick = { vm.setFormRole("child") },
            )
            EcChip(
                label = "家长",
                selected = state.formRole == "parent",
                onClick = { vm.setFormRole("parent") },
            )
        }

        FieldLabel("英语等级")
        LevelChips(selected = state.formCefr, enabled = !state.creating, onSelect = { vm.setFormCefr(it) })

        Text(
            text = "每日时长：${state.formLimit} 分钟",
            fontSize = EcFont.caption,
            color = EcColor.ink,
        )
        Slider(
            value = state.formLimit.toFloat(),
            onValueChange = { vm.setFormLimit(it.roundToInt()) },
            valueRange = 5f..180f,
            steps = 34,
            enabled = !state.creating,
        )
        EcSwitchRow(
            title = "允许自由对话（不按剧本）",
            checked = state.formFreeChat,
            onCheckedChange = { vm.setFormFreeChat(it) },
            subtitle = "关闭后对话强制走安全模式",
            enabled = !state.creating,
        )

        if (state.formError.isNotEmpty()) {
            Text(text = state.formError, fontSize = EcFont.caption, color = EcColor.badText)
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = "取消",
                onClick = { vm.toggleForm() },
                kind = EcButtonKind.GHOST,
                modifier = Modifier.weight(1f),
                enabled = !state.creating,
            )
            EcButton(
                label = if (state.creating) "创建中…" else "创建账号",
                onClick = { vm.create() },
                loading = state.creating,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

// ------------------------------------------------------------------ 成员卡

@Composable
private fun MemberCard(member: FamilyMemberDto, state: FamilyUiState, vm: FamilyViewModel) {
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = AccountFormat.memberAvatar(member.avatar, member.role), fontSize = 22.sp)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = member.displayName.ifEmpty { "成员" },
                    fontSize = EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                )
                Text(
                    text = vm.memberBadge(member),
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            if (member.role == "parent") {
                EcPill(text = "家长", tone = PillTone.INFO)
            } else {
                EcPill(text = "孩子", tone = PillTone.GOOD)
            }
        }
        Text(text = vm.memberSubText(member), fontSize = EcFont.micro, color = EcColor.muted)
        Text(
            text = "登录名：${vm.memberEmail(member)}",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = "编辑",
                onClick = { vm.beginEdit(member) },
                kind = EcButtonKind.SECONDARY,
                size = EcButtonSizeKind.SM,
                modifier = Modifier.weight(1f),
            )
            EcButton(
                label = "重置密码",
                onClick = { vm.beginReset(member) },
                kind = EcButtonKind.GHOST,
                size = EcButtonSizeKind.SM,
                modifier = Modifier.weight(1f),
            )
        }

        if (state.editingId == member.id) {
            EditForm(state = state, vm = vm)
        }
    }
}

@Composable
private fun EditForm(state: FamilyUiState, vm: FamilyViewModel) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(EcColor.surfaceAlt)
            .padding(EcSpace.x3),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = "编辑成员",
            fontSize = EcFont.caption,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        EcTextField(
            value = state.editName,
            onValueChange = { vm.setEditName(it) },
            label = "昵称",
            placeholder = "昵称（1–20 字）",
            enabled = !state.savingEdit,
        )
        FieldLabel("英语等级")
        LevelChips(selected = state.editCefr, enabled = !state.savingEdit, onSelect = { vm.setEditCefr(it) })
        Text(
            text = "每日时长：${state.editLimit} 分钟",
            fontSize = EcFont.caption,
            color = EcColor.ink,
        )
        Slider(
            value = state.editLimit.toFloat(),
            onValueChange = { vm.setEditLimit(it.roundToInt()) },
            valueRange = 5f..180f,
            steps = 34,
            enabled = !state.savingEdit,
        )
        EcSwitchRow(
            title = "允许自由对话",
            checked = state.editFreeChat,
            onCheckedChange = { vm.setEditFreeChat(it) },
            enabled = !state.savingEdit,
        )
        if (state.editError.isNotEmpty()) {
            Text(text = state.editError, fontSize = EcFont.caption, color = EcColor.badText)
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = "取消",
                onClick = { vm.cancelEdit() },
                kind = EcButtonKind.GHOST,
                modifier = Modifier.weight(1f),
                enabled = !state.savingEdit,
            )
            EcButton(
                label = if (state.savingEdit) "保存中…" else "保存",
                onClick = { vm.saveEdit() },
                loading = state.savingEdit,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

// ------------------------------------------------------------------ 小组件

@Composable
private fun FieldLabel(text: String) {
    Text(text = text, fontSize = EcFont.micro, color = EcColor.muted)
}

/** CEFR 等级 chips（A1–C1；家庭成员可选 C1，与语料等级回退 B2 不冲突）。 */
@Composable
private fun LevelChips(selected: String, enabled: Boolean, onSelect: (String) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
    ) {
        AccountFormat.LEVELS.forEach { level ->
            EcChip(
                label = level,
                selected = selected == level,
                onClick = { if (enabled) onSelect(level) },
            )
        }
    }
}

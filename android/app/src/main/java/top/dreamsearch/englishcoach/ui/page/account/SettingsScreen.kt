package top.dreamsearch.englishcoach.ui.page.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.config.AppConfig
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcDialog
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
import top.dreamsearch.englishcoach.ui.component.EcSwitchRow
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild
import top.dreamsearch.englishcoach.ui.nav.Navigator
import top.dreamsearch.englishcoach.ui.nav.Routes
import kotlin.math.roundToInt

/**
 * 设置页（签名按 CONTRACT §5，导航层已接线）。
 *
 * 对应 hos `pages/SettingsPage.ets` + `AccountSettingsVM`。内容：
 * - 账号偏好：昵称 / 性别 / 故事句数 3–12 / 纠正强度 / 音色入口 / 语速 / 点词音标 / 自动插画；
 * - 仅家长：每日时长（5–180 分钟滑杆）、允许自由话题 —— 儿童**不渲染**也不提交这两个字段；
 * - 服务器地址：校验 + http 明文风险提示 + 保存到 `AppConfig.baseUrl` + 连接检查；
 * - 入口：形象 / 音色 / 服务状态 / 建议箱 / 家庭成员（家长）/ 修改密码（本人，8–128 位）；
 * - 清理音频缓存、凭证存储说明、版本、隐私说明；退出登录（二次确认，先 `logout()` 再 `onLogout()`）。
 */
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onOpenAvatar: () -> Unit,
    onOpenVoices: () -> Unit,
    onOpenHealth: () -> Unit,
    onOpenSuggestions: () -> Unit,
    onLogout: () -> Unit,
) {
    val vm: SettingsViewModel = viewModel(
        factory = remember { vmFactory { SettingsViewModel(AppGraph.container) } }
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    var confirmLogout by remember { mutableStateOf(false) }

    PageScaffold(title = "设置", onBack = onBack, scrollable = true) { padding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(padding)
                .padding(horizontal = EcSpace.x4, vertical = EcSpace.x3),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            HeaderCard(state = state, roleText = vm.roleText(), usageText = vm.usageText())

            state.error?.let { error ->
                ErrorBanner(
                    error = error,
                    onRetry = vm::load,
                    onDismiss = { vm.edit { it.copy(error = null) } },
                )
            }

            when {
                state.loading && !state.loaded -> LoadingBlock(text = "正在读取账号设置…")
                !state.loaded -> Unit // 加载失败：只保留上面的错误条与重试
                else -> {
                    PrefsCard(state = state, vm = vm, isChild = isChild, onOpenVoices = onOpenVoices)
                    EntriesCard(
                        state = state,
                        isChild = isChild,
                        onOpenAvatar = onOpenAvatar,
                        onOpenVoices = onOpenVoices,
                        onOpenHealth = onOpenHealth,
                        onOpenSuggestions = onOpenSuggestions,
                        onOpenPassword = vm::openPasswordDialog,
                    )
                    ServerCard(state = state, vm = vm, isChild = isChild)
                    MiscCard(state = state, vm = vm)

                    if (state.notice.isNotEmpty()) {
                        EcInlineNotice(text = state.notice, tone = PillTone.GOOD)
                    }
                    if (state.passwordNotice.isNotEmpty()) {
                        EcInlineNotice(text = state.passwordNotice, tone = PillTone.GOOD)
                    }

                    EcButton(
                        label = if (state.loggingOut) "退出中…" else "退出登录",
                        onClick = { confirmLogout = true },
                        kind = EcButtonKind.DANGER,
                        size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                        loading = state.loggingOut,
                        fullWidth = true,
                    )
                    Text(
                        text = "退出后需要重新输入账号密码；本地录音与缓存会被清理。",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(modifier = Modifier.size(EcSpace.x2))
                }
            }
        }
    }

    // ------------------------------------------------------------------ 退出确认
    if (confirmLogout) {
        EcDialog(title = "确认退出登录？", onDismiss = { confirmLogout = false }) {
            Text(
                text = "退出后会回到登录页；本地录音与缓存会被清理，账号数据不受影响。",
                fontSize = EcFont.body,
                color = EcColor.ink,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "取消",
                    onClick = { confirmLogout = false },
                    kind = EcButtonKind.GHOST,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = if (state.loggingOut) "退出中…" else "退出登录",
                    onClick = {
                        confirmLogout = false
                        vm.logout(onLogout)
                    },
                    kind = EcButtonKind.DANGER,
                    loading = state.loggingOut,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    // ------------------------------------------------------------------ 修改密码
    if (state.passwordDialogOpen) {
        PasswordDialog(state = state, vm = vm)
    }
}

// ---------------------------------------------------------------------------
// 卡片
// ---------------------------------------------------------------------------

@Composable
private fun HeaderCard(state: SettingsUiState, roleText: String, usageText: String) {
    EcCard {
        Text(
            text = state.email.ifEmpty { "账号设置" },
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        Text(
            text = "$roleText · 等级 ${state.cefrLevel} · $usageText",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        if (state.loaded) {
            Text(
                text = "数据来自 /api/settings；保存后立即生效",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PrefsCard(
    state: SettingsUiState,
    vm: SettingsViewModel,
    isChild: Boolean,
    onOpenVoices: () -> Unit,
) {
    EcCard {
        Text(
            text = "账号偏好",
            fontSize = if (isChild) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )

        // ---------------------------------------------------------- 昵称
        EcTextField(
            value = state.displayName,
            onValueChange = { value -> vm.edit { it.copy(displayName = value) } },
            label = "昵称",
            placeholder = "1–30 个字符",
            enabled = !state.saving,
        )

        // ---------------------------------------------------------- 每日时长 / 自由话题（仅家长）
        if (state.isChild) {
            EcInlineNotice(
                text = "儿童账号的「每日时长上限」和「自由话题」由家长设置（服务端会拒绝儿童自行修改）",
                tone = PillTone.NEUTRAL,
            )
        } else {
            Text(
                text = "每日练习时长上限：${state.dailyLimit} 分钟",
                fontSize = EcFont.caption,
                color = EcColor.ink,
            )
            Slider(
                value = state.dailyLimit.toFloat(),
                onValueChange = { value -> vm.edit { it.copy(dailyLimit = value.roundToInt()) } },
                valueRange = 5f..180f,
                steps = 34,
                enabled = !state.saving,
            )
            EcSwitchRow(
                title = "允许自由话题",
                checked = state.allowFreeChat,
                onCheckedChange = { value -> vm.edit { it.copy(allowFreeChat = value) } },
                subtitle = "关闭后对话强制 child_safe 安全模式",
                enabled = !state.saving,
            )
        }

        DividerLine()

        // ---------------------------------------------------------- 自动插画
        EcSwitchRow(
            title = if (isChild) "要不要自动画一张画？" else "🎨 卡通插画自动生成",
            checked = state.autoIllustrate,
            onCheckedChange = { value -> vm.edit { it.copy(autoIllustrate = value) } },
            subtitle = when (state.imageCapable) {
                false -> "服务器未启用图像能力：保存故事不会自动画（开关已禁用）"
                true -> "开启后保存故事/书页会自动生成插画；关闭后仍可手动点「生成插画」"
                else -> "开启后保存故事/书页会自动生成插画（约 ¥0.1/张）"
            },
            enabled = !state.saving && state.imageCapable != false,
        )

        DividerLine()

        // ---------------------------------------------------------- 性别
        Text(
            text = if (isChild) "你是男孩还是女孩？" else "性别（影响插画里的形象）",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            genderOptions.forEach { (key, label) ->
                EcChip(
                    label = label,
                    selected = state.gender == key,
                    onClick = { vm.edit { it.copy(gender = key) } },
                )
            }
        }
        Text(
            text = "只用于插画提示词与形象筛选，不会展示给其他人。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )

        DividerLine()

        // ---------------------------------------------------------- 故事句数
        Text(
            text = "📖 故事句子数（默认 ${vm.storyDefault()} 句；可选 3–12）",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            for (count in 3..12) {
                EcChip(
                    label = count.toString(),
                    selected = state.storySentences == count,
                    onClick = { vm.edit { it.copy(storySentences = count) } },
                )
            }
            EcChip(
                label = "恢复默认",
                selected = state.storySentences == -1,
                onClick = { vm.edit { it.copy(storySentences = -1) } },
            )
        }

        DividerLine()

        // ---------------------------------------------------------- 纠正强度
        Text(
            text = "纠正强度（影响对话里的纠错频率）",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            correctionOptions.forEach { (key, label) ->
                EcChip(
                    label = label,
                    selected = state.correctionLevel == key,
                    onClick = { vm.edit { it.copy(correctionLevel = key) } },
                )
            }
        }

        DividerLine()

        // ---------------------------------------------------------- 音色入口
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(text = "🔊 音色", fontSize = EcFont.caption, color = EcColor.ink)
                Text(
                    text = "账号偏好：${vm.voiceLabel()} · 当前生效：${vm.effectiveVoiceLabel()}（语速 ${vm.effectiveVoiceRate()}）",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            Text(
                text = "去试听选择",
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(onClick = onOpenVoices)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
            )
        }

        // ---------------------------------------------------------- 语速
        Text(
            text = if (isChild) "朗读语速（示范音 / 对话朗读都生效）" else "朗读语速",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcChip(
                label = "🐢 慢速",
                selected = state.ttsRate == "slow",
                onClick = { vm.edit { it.copy(ttsRate = "slow") } },
            )
            EcChip(
                label = "🐇 正常",
                selected = state.ttsRate == "normal",
                onClick = { vm.edit { it.copy(ttsRate = "normal") } },
            )
        }
        if (isChild) {
            Text(
                text = "慢速更清楚，但合成耗时约为正常语速的 2.3 倍（等待更久）。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }

        DividerLine()

        // ---------------------------------------------------------- 点词音标
        EcSwitchRow(
            title = if (isChild) "🔤 点单词看音标" else "🔤 单词显示音标",
            checked = state.showWordIpa,
            onCheckedChange = { value -> vm.edit { it.copy(showWordIpa = value) } },
            subtitle = "点正文里的任意英文单词，浮层只显示 /音标/（默认开）",
            enabled = !state.saving,
        )

        // ---------------------------------------------------------- 保存
        EcButton(
            label = if (state.saving) "保存中…" else "保存设置",
            onClick = vm::save,
            kind = EcButtonKind.PRIMARY,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            loading = state.saving,
            fullWidth = true,
        )
    }
}

@Composable
private fun EntriesCard(
    state: SettingsUiState,
    isChild: Boolean,
    onOpenAvatar: () -> Unit,
    onOpenVoices: () -> Unit,
    onOpenHealth: () -> Unit,
    onOpenSuggestions: () -> Unit,
    onOpenPassword: () -> Unit,
) {
    EcCard {
        Text(
            text = "更多",
            fontSize = if (isChild) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        SettingEntry(
            icon = "🎨",
            title = "我的形象",
            subtitle = if (state.avatarPresetsAvailable) {
                "选一个小伙伴当形象"
            } else {
                "当前服务端未开启"
            },
            isChild = isChild,
            enabled = state.avatarPresetsAvailable,
            onClick = onOpenAvatar,
        )
        SettingEntry("🗣️", "音色", "9 种音色，可试听", isChild, onClick = onOpenVoices)
        SettingEntry("🩺", "服务状态", "家庭 NAS / 语音能力自查", isChild, onClick = onOpenHealth)
        SettingEntry("💡", "建议箱", "给产品提建议", isChild, onClick = onOpenSuggestions)
        if (!state.isChild && state.role == "parent") {
            SettingEntry("👥", "家庭成员", "建账号、改水平、重置密码", isChild) {
                Navigator.navigate(Routes.FAMILY)
            }
        }
        SettingEntry("🔑", "修改密码", "给自己设置新密码（8–128 位）", isChild, onClick = onOpenPassword)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ServerCard(state: SettingsUiState, vm: SettingsViewModel, isChild: Boolean) {
    val cleartext = AppGraph.config.isCleartext(state.baseUrl)
    val statusColor = when {
        state.checkingServer -> EcColor.muted
        state.serverStatus.isEmpty() -> EcColor.muted
        state.serverOk -> EcColor.good
        else -> EcColor.bad
    }
    EcCard {
        Text(
            text = "服务器地址",
            fontSize = if (isChild) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        EcTextField(
            value = state.baseUrl,
            onValueChange = { value -> vm.edit { it.copy(baseUrl = value) } },
            label = "服务器地址",
            placeholder = AppConfig.DEFAULT_BASE_URL,
            enabled = !state.savingAddress,
            keyboardType = KeyboardType.Uri,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(statusColor),
            )
            Text(
                text = when {
                    state.checkingServer -> "正在检查…"
                    state.serverStatus.isNotEmpty() -> state.serverStatus
                    else -> "未检查"
                },
                fontSize = EcFont.caption,
                color = statusColor,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "检查",
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(enabled = !state.checkingServer, onClick = vm::checkServer)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
            )
        }
        if (cleartext) {
            EcInlineNotice(
                text = "当前是 http 明文地址：部分网络/系统会拦截，建议改用 https",
                tone = PillTone.WARN,
            )
        }
        EcButton(
            label = if (state.savingAddress) "保存中…" else "保存地址",
            onClick = vm::saveBaseUrl,
            kind = EcButtonKind.SECONDARY,
            loading = state.savingAddress,
            fullWidth = true,
        )
    }
}

@Composable
private fun MiscCard(state: SettingsUiState, vm: SettingsViewModel) {
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = "示范音与回放缓存",
                    fontSize = EcFont.body,
                    color = EcColor.ink,
                )
                Text(
                    text = "只清理本地音频文件，不影响账号数据",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            Text(
                text = "清除",
                fontSize = EcFont.caption,
                color = EcColor.badText,
                modifier = Modifier
                    .clickable(onClick = vm::clearAudioCache)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
            )
        }
        Text(
            text = vm.tokenStorageNote(),
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
        Text(
            text = "版本 ${AppConfig.APP_VERSION}",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
        Text(
            text = "隐私说明：录音会经家庭 NAS 转发到云端做识别与评分，不是纯本地处理。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

// ---------------------------------------------------------------------------
// 小部件
// ---------------------------------------------------------------------------

@Composable
private fun SettingEntry(
    icon: String,
    title: String,
    subtitle: String,
    isChild: Boolean,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .clickable(enabled = enabled, onClick = onClick)
            .heightIn(min = if (isChild) 60.dp else 48.dp)
            .padding(vertical = EcSpace.x2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
    ) {
        Text(
            text = icon,
            fontSize = if (isChild) 26.sp else 22.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .width(36.dp)
                .then(if (enabled) Modifier else Modifier.alpha(0.4f)),
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = title,
                fontSize = if (isChild) EcFont.childBody else EcFont.body,
                fontWeight = FontWeight.Medium,
                color = if (enabled) EcColor.ink else EcColor.muted,
            )
            if (subtitle.isNotEmpty()) {
                Text(text = subtitle, fontSize = EcFont.micro, color = EcColor.muted)
            }
        }
        Text(text = if (enabled) "›" else "—", fontSize = 22.sp, color = EcColor.muted)
    }
}

@Composable
private fun DividerLine() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = EcSpace.x1)
            .height(1.dp)
            .background(EcColor.border),
    )
}

@Composable
private fun PasswordDialog(state: SettingsUiState, vm: SettingsViewModel) {
    EcDialog(title = "修改密码", onDismiss = vm::closePasswordDialog) {
        if (state.isChild) {
            Text(
                text = "请让爸爸妈妈在家长面板帮你改密码。",
                fontSize = EcFont.body,
                color = EcColor.ink,
            )
            EcButton(
                label = "知道了",
                onClick = vm::closePasswordDialog,
                kind = EcButtonKind.SECONDARY,
                fullWidth = true,
            )
        } else {
            Text(
                text = "账号：${state.displayName.ifEmpty { state.email }}",
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
            EcTextField(
                value = state.newPassword,
                onValueChange = vm::editNewPassword,
                label = "新密码",
                placeholder = "至少 8 位",
                password = true,
                enabled = !state.passwordSaving,
            )
            EcTextField(
                value = state.confirmPassword,
                onValueChange = vm::editConfirmPassword,
                label = "再输一次",
                placeholder = "两次输入需一致",
                password = true,
                enabled = !state.passwordSaving,
            )
            if (state.passwordError.isNotEmpty()) {
                Text(
                    text = state.passwordError,
                    fontSize = EcFont.caption,
                    color = EcColor.badText,
                )
            }
            Text(
                text = "修改后其他设备可能仍保持登录，建议在旧设备退出登录。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "取消",
                    onClick = vm::closePasswordDialog,
                    kind = EcButtonKind.GHOST,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = if (state.passwordSaving) "保存中…" else "保存新密码",
                    onClick = vm::savePassword,
                    kind = EcButtonKind.PRIMARY,
                    loading = state.passwordSaving,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 选项
// ---------------------------------------------------------------------------

private val genderOptions: List<Pair<String, String>> = listOf(
    "" to "不设置",
    "girl" to "女孩",
    "boy" to "男孩",
    "woman" to "成年女性",
    "man" to "成年男性",
    "other" to "其它 / 不想说",
)

private val correctionOptions: List<Pair<String, String>> = listOf(
    "gentle" to "轻纠正",
    "standard" to "正常纠正",
    "none" to "纯聊天不纠错",
)

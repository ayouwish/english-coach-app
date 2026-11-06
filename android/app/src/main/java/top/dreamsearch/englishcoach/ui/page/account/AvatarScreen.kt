package top.dreamsearch.englishcoach.ui.page.account

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.dto.AvatarPresetCharacterDto
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcSwitchRow
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RemoteImage
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace

/**
 * 虚拟形象（`Routes.AVATAR`；对应 hos `pages/AvatarPage.ets`）。
 *
 * 流程（只选预置形象，**不生成、不上传照片**）：
 * 1. 第 1 步选风格（5 种：水彩/卡通/像素/剪纸/黏土）；
 * 2. 第 2 步选角色（12 角色，按账号角色 audience 过滤；默认再按性别筛选，可切「显示全部」）；
 * 3. 点一下立即生效（`POST /avatar {preset_id, style}`，不等待生成、不扣费）；
 * 4. 角色卡描述可编辑（`PATCH /avatar {character_desc}`）；也可清空形象（`DELETE /avatar`）。
 *
 * 隐私：照片生成形象已按策略关闭（服务端 403 `policy_disabled`），**页面不提供上传入口**；
 * 形象图只加载站内预置静态图 `/avatars/...`（无需鉴权）。
 */
@Composable
fun AvatarScreen(onBack: () -> Unit) {
    val vm: AvatarViewModel = viewModel(
        factory = remember { vmFactory { AvatarViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()

    PageScaffold(title = "我的形象", onBack = onBack) {
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
            item(key = "header") { AvatarHeader(state) }

            if (state.error != null) {
                item(key = "error") {
                    ErrorBanner(error = state.error, onRetry = { vm.retry() })
                }
            }

            if (state.unavailable) {
                item(key = "unavailable") { AvatarUnavailableCard(state, vm) }
            } else if (state.loading && !state.loadedOnce) {
                item(key = "loading") { LoadingBlock(text = "正在打开形象库…") }
            } else {
                item(key = "current") { CurrentAvatarCard(state, vm) }
                item(key = "style") { StylePicker(state, vm) }
                item(key = "gender") {
                    EcCard {
                        EcSwitchRow(
                            title = "显示全部形象",
                            checked = state.showAllGender,
                            onCheckedChange = { vm.setShowAllGender(it) },
                            subtitle = if (state.myGender.isEmpty()) {
                                "还没有设置性别，默认显示全部角色。"
                            } else {
                                "默认按你的性别筛选；打开后显示全部形象。"
                            },
                        )
                        Text(
                            text = "第 2 步：选角色（共 ${vm.visibleCharacters().size} 个）",
                            fontSize = EcFont.caption,
                            color = EcColor.muted,
                        )
                        if (vm.visibleCharacters().isEmpty()) {
                            Text(
                                text = "这个分类下暂时没有可选形象。",
                                fontSize = EcFont.caption,
                                color = EcColor.muted,
                            )
                        }
                    }
                }
                item(key = "characters") { CharacterGrid(state, vm) }
                item(key = "footer") {
                    Text(
                        text = "点一下立即生效，不需要等待生成。形象只影响故事插画里的角色样子，不会上传任何照片。",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                        modifier = Modifier.padding(bottom = EcSpace.x4),
                    )
                }
            }
        }
    }
}

// ------------------------------------------------------------------ 头部 / 当前形象

/**
 * 形象库不可用（`capability.avatarPresets == false`）：
 * 不渲染风格/角色选择，只给说明 + 重试（重试会对能力开关 force 刷新，服务端开启后即可恢复）。
 */
@Composable
private fun AvatarUnavailableCard(state: AvatarUiState, vm: AvatarViewModel) {
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = "🎨", fontSize = 26.sp)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "形象库暂不可用",
                    fontSize = EcFont.h3,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                Text(
                    text = "当前服务端未开启预置形象库（capabilities.avatar_presets=false）。" +
                        "开启后点「重新检查」即可选择形象；不影响练习与故事插画。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }
        EcButton(
            label = if (state.loading) "检查中…" else "重新检查",
            onClick = { vm.retry() },
            kind = EcButtonKind.SECONDARY,
            loading = state.loading,
            fullWidth = true,
        )
        Text(
            text = "不用上传照片，也不需要生成图片：形象只影响故事插画里的角色样子。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

@Composable
private fun AvatarHeader(state: AvatarUiState) {
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = "🎨", fontSize = 24.sp)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "我的虚拟形象",
                    fontSize = EcFont.h3,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                Text(
                    text = "🛡️ 不用上传照片，选一个就好",
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
            }
            if (state.placeholder) {
                EcPill(text = "占位图", tone = PillTone.WARN)
            }
        }
        if (state.placeholder) {
            Text(
                text = "预览图（未生成真实插画）：当前展示的是占位图，真实插画生成后会替换。",
                fontSize = EcFont.micro,
                color = EcColor.warnText,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
            EcPill(text = "风格：${vmStyleLabel(state)}", tone = PillTone.INFO)
            if (state.audience == "child") {
                EcPill(text = "小朋友形象", tone = PillTone.GOOD)
            } else {
                EcPill(text = "成人形象", tone = PillTone.NEUTRAL)
            }
        }
    }
}

/** 当前选中风格的中文名（state 里没有 styles 映射时回退 id）。 */
private fun vmStyleLabel(state: AvatarUiState): String {
    val style = state.styles.firstOrNull { it.id == state.selectedStyle }
    return style?.labelZh?.ifEmpty { state.selectedStyle } ?: state.selectedStyle
}

@Composable
private fun CurrentAvatarCard(state: AvatarUiState, vm: AvatarViewModel) {
    EcCard {
        Text(
            text = "当前形象",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        val imageUrl = vm.currentImageUrl()
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            Box(
                modifier = Modifier
                    .width(112.dp)
                    .height(112.dp)
                    .clip(RoundedCornerShape(EcRadius.lg))
                    .background(EcColor.surfaceAlt),
                contentAlignment = Alignment.Center,
            ) {
                if (imageUrl.isNotEmpty()) {
                    RemoteImage(
                        path = imageUrl,
                        contentDescription = "当前虚拟形象",
                        modifier = Modifier.fillMaxSize(),
                        withAuth = false,
                        fallback = { Text(text = "🙂", fontSize = 40.sp) },
                    )
                } else {
                    Text(text = "🙂", fontSize = 40.sp)
                }
            }
            Column(modifier = Modifier.weight(1f)) {
                if (vm.hasAvatar()) {
                    val styleLabel = vm.currentStyleLabel()
                    if (styleLabel.isNotEmpty()) {
                        EcPill(text = "风格：$styleLabel", tone = PillTone.INFO)
                    }
                    Text(
                        text = "已设置。想换一个？在下面选风格和角色，点一下就换。",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                } else {
                    Text(
                        text = "还没有设置形象。选一个角色，故事插画里就会用到。",
                        fontSize = EcFont.caption,
                        color = EcColor.muted,
                    )
                }
            }
        }

        val desc = vm.currentDesc()
        if (desc.isNotEmpty()) {
            Text(
                text = "角色卡：$desc",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
        EcTextField(
            value = state.descDraft,
            onValueChange = { vm.setDescDraft(it) },
            label = "把描述改成更像我的",
            placeholder = "例如：a girl with glasses and a red hoodie",
            singleLine = false,
            enabled = !state.savingDesc,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = if (state.savingDesc) "保存中…" else "保存描述",
                onClick = { vm.saveDescription() },
                kind = EcButtonKind.SECONDARY,
                loading = state.savingDesc,
                modifier = Modifier.weight(1f),
            )
            EcButton(
                label = if (state.clearing) "清空中…" else "清空形象",
                onClick = { vm.clearAvatar() },
                kind = EcButtonKind.GHOST,
                loading = state.clearing,
                modifier = Modifier.weight(1f),
                enabled = vm.hasAvatar() || desc.isNotEmpty(),
            )
        }
        if (state.notice.isNotEmpty()) {
            Text(
                text = state.notice,
                fontSize = EcFont.caption,
                color = EcColor.goodText,
                modifier = Modifier.clickable { vm.clearNotice() },
            )
        }
        if (state.actionError.isNotEmpty()) {
            Text(
                text = state.actionError,
                fontSize = EcFont.caption,
                color = EcColor.badText,
                modifier = Modifier.clickable { vm.clearNotice() },
            )
        }
    }
}

// ------------------------------------------------------------------ 风格 / 角色

@Composable
private fun StylePicker(state: AvatarUiState, vm: AvatarViewModel) {
    EcCard {
        Text(
            text = "第 1 步：选风格",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        state.styles.chunked(3).forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                row.forEach { style ->
                    Column(modifier = Modifier.weight(1f)) {
                        EcChip(
                            label = style.labelZh.ifEmpty { style.id },
                            selected = state.selectedStyle == style.id,
                            onClick = { vm.setStyle(style.id) },
                        )
                    }
                }
                repeat(3 - row.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
        Text(
            text = "先选风格，再选角色；换风格会自动展示该风格下的角色图。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

@Composable
private fun CharacterGrid(state: AvatarUiState, vm: AvatarViewModel) {
    val characters = vm.visibleCharacters()
    if (characters.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
        characters.chunked(2).forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                row.forEach { character ->
                    Column(modifier = Modifier.weight(1f)) {
                        CharacterCard(
                            character = character,
                            imageUrl = vm.imageOf(character),
                            title = vm.characterTitle(character),
                            selected = vm.isCurrent(character),
                            saving = state.saving,
                            onClick = { vm.selectPreset(character.id) },
                        )
                    }
                }
                if (row.size == 1) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun CharacterCard(
    character: AvatarPresetCharacterDto,
    imageUrl: String,
    title: String,
    selected: Boolean,
    saving: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(EcRadius.lg)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(EcColor.surface)
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) EcColor.primary else EcColor.border,
                shape = shape,
            )
            .clickable(enabled = !saving, onClick = onClick)
            .padding(EcSpace.x2),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(112.dp)
                .clip(RoundedCornerShape(EcRadius.md))
                .background(EcColor.surfaceAlt),
            contentAlignment = Alignment.Center,
        ) {
            if (imageUrl.isNotEmpty()) {
                RemoteImage(
                    path = imageUrl,
                    contentDescription = title,
                    modifier = Modifier.fillMaxSize(),
                    withAuth = false,
                    fallback = { Text(text = "🙂", fontSize = 30.sp) },
                )
            } else {
                Text(text = "🙂", fontSize = 30.sp)
            }
        }
        Text(
            text = title,
            fontSize = EcFont.caption,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        if (selected) {
            EcPill(text = "使用中", tone = PillTone.GOOD)
        } else {
            Text(
                text = if (saving) "保存中…" else "点一下使用",
                fontSize = EcFont.micro,
                color = EcColor.primary,
            )
        }
    }
}

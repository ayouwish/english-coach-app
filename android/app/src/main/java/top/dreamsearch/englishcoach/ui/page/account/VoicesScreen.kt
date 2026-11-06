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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.audio.TtsVoice
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcSectionTitle
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PageScaffold
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace

/**
 * 音色页（`Routes.VOICES`；对应 hos `pages/VoicesPage.ets`）。
 *
 * 清单**不请求接口**：`GET /api/tts/voices` 线上不存在（CONTRACT §3.2），
 * 9 个音色来自 `core/audio/Voices.ALL`（5 英语 + 4 中文）。
 *
 * 交互：试听（`POST /tts` mp3 → 播放）→ 选择「使用」→ `PATCH /settings {tts_voice}`；
 * 空 = 恢复 provider 默认音色。保存后示范音/对话朗读立即生效（无需重启 App）。
 * 顶部「更多语音设置」→ 设置页（语速/单词音标/账号偏好）。
 */
@Composable
fun VoicesScreen(onBack: () -> Unit, onOpenSettings: () -> Unit) {
    val vm: VoicesViewModel = viewModel(
        factory = remember { vmFactory { VoicesViewModel(AppGraph.container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val english = vm.englishVoices
    val chinese = vm.chineseVoices

    // 离页停播（试听中返回不应该继续响）
    DisposableEffect(Unit) {
        onDispose { vm.stopPreview() }
    }

    PageScaffold(
        title = "音色",
        onBack = onBack,
        actions = {
            Text(
                text = "⚙️ 更多设置",
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(onClick = onOpenSettings)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x2),
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
            item(key = "header") { VoicesHeader(state, vm, onOpenSettings) }

            if (state.error != null) {
                item(key = "error") {
                    ErrorBanner(error = state.error, onRetry = { vm.retry() })
                }
            }

            if (state.loading && !state.loadedOnce) {
                item(key = "loading") { LoadingBlock(text = "正在读取音色偏好…") }
            } else {
                item(key = "default") { DefaultVoiceRow(state, vm) }

                item(key = "en-title") { EcSectionTitle(text = "英语音色") }
                items(english.size, key = { "en-$it" }) { index ->
                    VoiceRow(voice = english[index], state = state, vm = vm)
                }

                item(key = "zh-title") { EcSectionTitle(text = "中文音色") }
                items(chinese.size, key = { "zh-$it" }) { index ->
                    VoiceRow(voice = chinese[index], state = state, vm = vm)
                }

                item(key = "empty") {
                    if (english.isEmpty() && chinese.isEmpty()) {
                        EmptyState(icon = "🔊", message = "没有可用的内置音色。")
                    }
                }

                item(key = "footer") {
                    Text(
                        text = "⚙️ 朗读语速（慢速 / 正常）、单词音标与其它偏好都在「设置」里；" +
                            "试听会调用语音服务，首次可能有 1–2 秒等待。",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                        modifier = Modifier.padding(bottom = EcSpace.x4),
                    )
                }
            }
        }
    }
}

// ------------------------------------------------------------------ 头部 / 默认音色

@Composable
private fun VoicesHeader(state: VoicesUiState, vm: VoicesViewModel, onOpenSettings: () -> Unit) {
    EcCard {
        Text(
            text = "🔊 音色",
            fontSize = EcFont.h3,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Text(
            text = "练习示范音、对话朗读、鼓励音都会用它。默认音色由语音服务决定。",
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
            EcPill(text = "当前：${vm.labelOf(state.currentVoice)}", tone = PillTone.INFO)
            EcPill(text = "语速 ${state.rate}", tone = PillTone.NEUTRAL)
        }
        if (state.notice.isNotEmpty()) {
            Text(
                text = state.notice,
                fontSize = EcFont.caption,
                color = EcColor.goodText,
                modifier = Modifier.clickable { vm.clearNotice() },
            )
        }
        if (state.saveError.isNotEmpty()) {
            Text(
                text = state.saveError,
                fontSize = EcFont.caption,
                color = EcColor.badText,
                modifier = Modifier.clickable { vm.clearNotice() },
            )
        }
        if (state.previewError.isNotEmpty()) {
            Text(
                text = state.previewError,
                fontSize = EcFont.caption,
                color = EcColor.badText,
                modifier = Modifier.clickable { vm.clearNotice() },
            )
        }
        EcButton(
            label = "⚙️ 更多语音设置（语速 / 单词音标）",
            onClick = onOpenSettings,
            kind = EcButtonKind.GHOST,
            fullWidth = true,
        )
    }
}

@Composable
private fun DefaultVoiceRow(state: VoicesUiState, vm: VoicesViewModel) {
    val selected = state.currentVoice.isEmpty()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.surfaceAlt)
            .padding(EcSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "默认音色（provider 决定）",
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
            )
            Text(
                text = "不指定 voice，由语音服务选择最合适的音色。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
        if (selected) {
            EcPill(text = "使用中", tone = PillTone.GOOD)
        } else {
            EcButton(
                label = "使用",
                onClick = { vm.save("") },
                kind = EcButtonKind.SECONDARY,
                size = EcButtonSizeKind.SM,
                loading = state.saving,
            )
        }
    }
}

// ------------------------------------------------------------------ 单个音色

@Composable
private fun VoiceRow(voice: TtsVoice, state: VoicesUiState, vm: VoicesViewModel) {
    val selected = state.currentVoice == voice.id
    val previewing = state.previewingId == voice.id
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = if (voice.isEnglish) "🇬🇧" else "🇨🇳", fontSize = 20.sp)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = voice.labelZh,
                    fontSize = EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                )
                Text(
                    text = voice.sample,
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            if (selected) {
                EcPill(text = "使用中", tone = PillTone.GOOD)
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = when {
                    state.previewLoading && previewing -> "备音频中…"
                    previewing -> "⏹ 停止"
                    else -> "▶ 试听"
                },
                onClick = { vm.togglePreview(voice) },
                kind = EcButtonKind.GHOST,
                size = EcButtonSizeKind.SM,
                modifier = Modifier.weight(1f),
                enabled = !(state.previewLoading && previewing),
            )
            if (!selected) {
                EcButton(
                    label = if (state.saving) "保存中…" else "使用这个音色",
                    onClick = { vm.save(voice.id) },
                    kind = EcButtonKind.SECONDARY,
                    size = EcButtonSizeKind.SM,
                    loading = state.saving,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

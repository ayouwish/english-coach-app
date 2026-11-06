package top.dreamsearch.englishcoach.ui.page.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
import top.dreamsearch.englishcoach.ui.component.EcPill
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
 * 服务状态页（签名按 CONTRACT §5：`HealthScreen(onBack)`）。
 *
 * 对应 hos `pages/HealthPage.ets`。`PracticeService.health()`（GET /api/health，无需登录）：
 * - web status / service / version / 服务端时间；
 * - db.ok（异常 → 红色「服务异常」）；
 * - voice.reachable / mode / hint / capabilities（不可达 → 琥珀提示，录音仍会入库）。
 *
 * 额外展示：服务器地址、App 版本、凭证存储是否降级（`TokenStore.degraded`）、隐私说明。
 * 本页不轮询；「刷新」由用户触发，失败用 `ErrorBanner` + 重试。
 */
@Composable
fun HealthScreen(onBack: () -> Unit) {
    val vm: HealthViewModel = viewModel(
        factory = remember { vmFactory { HealthViewModel(AppGraph.container) } }
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current

    PageScaffold(
        title = "服务状态",
        onBack = onBack,
        actions = {
            Text(
                text = if (state.loading) "检查中…" else "强制刷新",
                fontSize = EcFont.caption,
                color = if (state.loading) EcColor.muted else EcColor.primary,
                modifier = Modifier
                    .clickable(enabled = !state.loading, onClick = vm::forceRefresh)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
            )
        },
        scrollable = true,
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(padding)
                .padding(horizontal = EcSpace.x4, vertical = EcSpace.x3),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            EcCard {
                Text(
                    text = "🩺 服务状态",
                    fontSize = if (isChild) EcFont.childH1 else EcFont.h2,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                Text(
                    text = "家庭 NAS / 语音能力自查。此接口无需登录，可用来判断服务是否在线。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
                Text(
                    text = if (state.forcing) {
                        "本次为强制刷新（?force=1）：已跳过服务端缓存并重新探测 voice。"
                    } else {
                        "「强制刷新会跳过服务端缓存」：普通刷新可能命中服务端 15 秒缓存，强制刷新会重新探测。"
                    },
                    fontSize = EcFont.micro,
                    color = if (state.forcing) EcColor.primary else EcColor.muted,
                )
            }

            state.error?.let { error ->
                ErrorBanner(error = error, onRetry = { vm.load() })
            }

            when {
                state.loading && !state.loaded -> LoadingBlock(text = "正在探测服务状态…")

                !state.loaded -> Unit // 失败时只显示错误条 + 重试

                else -> {
                    StatusCard(state = state, vm = vm, isChild = isChild)
                    FeaturesCard(state = state)
                    VoiceCard(state = state, vm = vm)
                    CapabilitiesCard(state = state, vm = vm)
                    ClientInfoCard(state = state, vm = vm)
                    EcButton(
                        label = "重新检查",
                        onClick = { vm.load() },
                        kind = EcButtonKind.SECONDARY,
                        loading = state.loading,
                        fullWidth = true,
                    )
                    EcButton(
                        label = if (state.forcing) "强制刷新中…" else "强制刷新（跳过服务端缓存）",
                        onClick = vm::forceRefresh,
                        kind = EcButtonKind.GHOST,
                        loading = state.loading && state.forcing,
                        fullWidth = true,
                    )
                    Text(
                        text = "客户端不对 /api/health 做超过每 30 秒一次的轮询；voice 探测有 3 秒超时 + 15 秒缓存，" +
                            "强制刷新（?force=1）会跳过该缓存。",
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 卡片
// ---------------------------------------------------------------------------

@Composable
private fun StatusCard(state: HealthUiState, vm: HealthViewModel, isChild: Boolean) {
    val color = when (state.level) {
        "bad" -> EcColor.badText
        "warn" -> EcColor.warnText
        else -> EcColor.goodText
    }
    val background = when (state.level) {
        "bad" -> EcColor.badBg
        "warn" -> EcColor.warnBg
        else -> EcColor.goodBg
    }
    val pillTone = when (state.level) {
        "bad" -> PillTone.BAD
        "warn" -> PillTone.WARN
        else -> PillTone.GOOD
    }
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "${vm.levelIcon()} ${vm.levelTitle()}",
                fontSize = if (isChild) EcFont.childBody else EcFont.h3,
                fontWeight = FontWeight.Bold,
                color = color,
                modifier = Modifier.weight(1f),
            )
            EcPill(text = state.status.ifEmpty { "—" }, tone = pillTone)
        }
        Text(
            text = vm.levelDetail(),
            fontSize = EcFont.body,
            color = EcColor.ink,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(EcRadius.md))
                .background(background)
                .padding(EcSpace.x3),
        )
        Text(
            text = "service：${state.service.ifEmpty { "—" }} · version：${state.version.ifEmpty { "—" }}",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
        Text(
            text = "服务端时间：${state.serverTime.ifEmpty { "—" }} · status：${state.status.ifEmpty { "—" }}",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
        Text(
            text = "数据库：${if (state.dbOk) "可用" else "异常"}" +
                if (state.dbError.isNotEmpty()) "（${state.dbError}）" else "",
            fontSize = EcFont.micro,
            color = if (state.dbOk) EcColor.goodText else EcColor.badText,
        )
    }
}

@Composable
private fun FeaturesCard(state: HealthUiState) {
    EcCard {
        Text(
            text = "构建特性（web features）",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        when {
            state.featuresError.isNotEmpty() -> {
                EcInlineNotice(text = state.featuresError, tone = PillTone.WARN)
                Text(
                    text = "features 来自 `GET /api/health` 的全字段版（stats.healthFull），与 voice.capabilities 分开兜底。",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }

            !state.featuresLoaded -> {
                Text(
                    text = "正在读取 features…",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }

            state.features.isEmpty() -> {
                Text(
                    text = "未返回 features 字段",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }

            else -> {
                state.features.forEach { (label, supported) ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = label,
                            fontSize = EcFont.caption,
                            color = EcColor.ink,
                            modifier = Modifier.weight(1f),
                        )
                        EcPill(
                            text = if (supported) "支持" else "不支持",
                            tone = if (supported) PillTone.GOOD else PillTone.NEUTRAL,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun VoiceCard(state: HealthUiState, vm: HealthViewModel) {
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "语音服务",
                fontSize = EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
                modifier = Modifier.weight(1f),
            )
            EcPill(
                text = if (state.voiceReachable) "已就绪" else "未就绪",
                tone = if (state.voiceReachable) PillTone.GOOD else PillTone.WARN,
            )
        }
        Text(
            text = vm.voiceSummary(),
            fontSize = EcFont.caption,
            color = EcColor.ink,
        )
        if (state.voiceHint.isNotEmpty()) {
            EcInlineNotice(text = state.voiceHint, tone = PillTone.WARN)
        }
        if (!state.voiceReachable) {
            Text(
                text = "提示：voice 未就绪时录音与文本仍会入库，可稍后「重试评测」；文本/历史功能不受影响。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
        Text(
            text = "voice 地址在服务端容器内，不可从客户端直接访问。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

@Composable
private fun CapabilitiesCard(state: HealthUiState, vm: HealthViewModel) {
    val lines = vm.capabilityLines()
    EcCard {
        Text(
            text = "语音能力（voice.capabilities）",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        if (lines.isEmpty()) {
            Text(
                text = "未返回 capabilities 字段",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        } else {
            lines.forEach { (label, supported) ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = label,
                        fontSize = EcFont.caption,
                        color = EcColor.ink,
                        modifier = Modifier.weight(1f),
                    )
                    EcPill(
                        text = if (supported) "支持" else "不支持",
                        tone = if (supported) PillTone.GOOD else PillTone.NEUTRAL,
                    )
                }
            }
            val provider = vm.imageProvider()
            if (provider.isNotEmpty()) {
                Text(
                    text = "图像 provider：$provider",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            val asr = vm.asrProviders()
            if (asr.isNotEmpty()) {
                Text(
                    text = "ASR providers：${asr.joinToString(" / ")}",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
        }
    }
}

@Composable
private fun ClientInfoCard(state: HealthUiState, vm: HealthViewModel) {
    EcCard {
        Text(
            text = "客户端",
            fontSize = EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        InfoRow(label = "服务器地址", value = state.baseUrl.ifEmpty { "—" })
        InfoRow(label = "App 版本", value = state.appVersion)
        InfoRow(
            label = "生效音色",
            value = (state.effectiveVoiceLabel.ifEmpty { "—" }) +
                if (state.effectiveRate.isNotEmpty()) "（语速 ${state.effectiveRate}）" else "",
        )
        InfoRow(
            label = "凭证存储",
            value = if (state.tokenDegraded) "仅内存（本次运行有效）" else "系统安全存储",
        )
        Text(
            text = vm.tokenStorageNote(),
            fontSize = EcFont.micro,
            color = if (state.tokenDegraded) EcColor.warnText else EcColor.muted,
        )
        Text(
            text = "隐私说明：录音会经家庭 NAS 转发到云端做识别与评分，不是纯本地处理。",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = label,
            fontSize = EcFont.caption,
            color = EcColor.muted,
            modifier = Modifier.width(84.dp),
        )
        Text(
            text = value,
            fontSize = EcFont.caption,
            color = EcColor.ink,
            modifier = Modifier.weight(1f),
        )
    }
}

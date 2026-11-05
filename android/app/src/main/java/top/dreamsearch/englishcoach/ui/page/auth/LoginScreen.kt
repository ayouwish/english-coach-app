package top.dreamsearch.englishcoach.ui.page.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
import top.dreamsearch.englishcoach.ui.component.EcSwitchRow
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild

/**
 * 登录页（对应 hos `pages/LoginPage.ets`；签名按 CONTRACT §5：`LoginScreen()` 无回调）。
 *
 * 未登录时由 `ui/AppRoot.kt` 直接展示；登录成功后 `SessionStore.state.loggedIn` 变 true，
 * AppRoot 自动切到首页，**本页不做导航**。
 *
 * 功能点（Lead 任务 1）：
 * - 邮箱/密码（明文切换）+ loading/禁用 + 内联 `ErrorBanner`；
 * - 「记住密码」开关（`SessionStore.login` 内部写 `CredentialStore`；不可用时明确提示）；
 * - 服务器地址可编辑：校验、http 明文风险提示、登录/检查时保存到 `AppConfig.baseUrl`；
 * - 演示账号一键填入（邮箱 + 密码）；
 * - 底部 `practice.health()` 连接状态（家庭 NAS / 语音未就绪 / 数据库异常）；
 * - 不提供注册与自助找回（文案引导家长重置）。
 */
@Composable
fun LoginScreen() {
    val vm: LoginViewModel = viewModel(
        factory = remember { vmFactory { LoginViewModel(AppGraph.container) } }
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    val tokenDegraded = remember { AppGraph.container.tokenStore.degraded }

    // 退出登录后会复用同一个 ViewModel：清理上一次的敏感输入/错误，并重新检查服务器
    LaunchedEffect(Unit) {
        vm.onScreenShown()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(EcColor.bg)
            .safeDrawingPadding()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = EcSpace.x5),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x4),
    ) {
        Spacer(modifier = Modifier.height(EcSpace.x8))

        // ---------------------------------------------------------- 品牌头
        Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x1)) {
            Text(
                text = "🎤 English Coach",
                fontSize = EcFont.h1,
                fontWeight = FontWeight.Bold,
                color = EcColor.ink,
            )
            Text(
                text = "家庭英语口语教练",
                fontSize = EcFont.body,
                color = EcColor.muted,
            )
            Text(
                text = "只在家庭 Wi-Fi / VPN 下可用，不是公网服务",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }

        // ---------------------------------------------------------- 服务器地址
        EcCard {
            EcTextField(
                value = state.baseUrl,
                onValueChange = vm::setBaseUrl,
                label = "服务器地址",
                placeholder = "https://english.dreamsearch.top",
                enabled = !state.loading,
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
                        .background(serverStatusColor(state)),
                )
                Text(
                    text = state.serverStatusText,
                    fontSize = EcFont.caption,
                    color = serverStatusColor(state),
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "重新检查",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(enabled = !state.checkingServer, onClick = vm::checkServer)
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
                )
            }
            if (state.cleartext) {
                EcInlineNotice(
                    text = "当前是 http 明文地址：部分网络/系统会拦截，建议改用 https",
                    tone = PillTone.WARN,
                )
            }
        }

        // ---------------------------------------------------------- 账号表单
        EcCard {
            EcTextField(
                value = state.email,
                onValueChange = vm::setEmail,
                label = "邮箱",
                placeholder = "dad@example.com",
                enabled = !state.loading,
                keyboardType = KeyboardType.Email,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcTextField(
                    value = state.password,
                    onValueChange = vm::setPassword,
                    label = "密码",
                    placeholder = "输入密码",
                    password = !state.passwordVisible,
                    enabled = !state.loading,
                    keyboardType = KeyboardType.Password,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = if (state.passwordVisible) "隐藏" else "显示",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(onClick = vm::togglePasswordVisible)
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x3),
                )
            }
            EcSwitchRow(
                title = "记住密码",
                checked = state.rememberPassword,
                onCheckedChange = vm::setRememberPassword,
                subtitle = "默认关：开启后下次打开自动登录（密码存系统安全存储）",
                enabled = !state.loading,
            )
            if (state.rememberPassword && state.rememberUnsupported) {
                EcInlineNotice(
                    text = "本机安全存储不可用：密码不会被保存，下次打开需要重新输入",
                    tone = PillTone.WARN,
                )
            }
            if (tokenDegraded) {
                EcInlineNotice(
                    text = "本机不能安全保存登录状态：重启 App 后需要重新登录",
                    tone = PillTone.WARN,
                )
            }
        }

        // ---------------------------------------------------------- 错误 + 登录
        state.error?.let { error ->
            ErrorBanner(error = error, onDismiss = vm::clearError)
        }

        EcButton(
            label = if (state.loading) "登录中…" else "登 录",
            onClick = vm::login,
            kind = EcButtonKind.PRIMARY,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.LG,
            loading = state.loading,
            enabled = !state.loading,
            fullWidth = true,
        )

        // ---------------------------------------------------------- 演示账号
        if (state.demos.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
                Text(
                    text = "演示账号（点一下自动填入邮箱和密码）",
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
                ) {
                    state.demos.forEach { demo ->
                        EcButton(
                            label = demo.label.substringBefore(" ·"),
                            onClick = { vm.fillDemo(demo) },
                            kind = EcButtonKind.GHOST,
                            size = EcButtonSizeKind.SM,
                            enabled = !state.loading,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }

        // ---------------------------------------------------------- 底部说明
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
        ) {
            Text(
                text = "忘记密码？让家长在家长面板重置。账号由家长创建，不提供自助注册。",
                fontSize = EcFont.caption,
                color = EcColor.muted,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = "隐私说明：录音会经家庭 NAS 转发到云端做识别与评分，不是纯本地处理。",
                fontSize = EcFont.micro,
                color = EcColor.muted,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Spacer(modifier = Modifier.height(EcSpace.x8))
    }
}

/** 连接状态点的颜色（与 `LoginUiState.serverLevel` 对应）。 */
private fun serverStatusColor(state: LoginUiState): Color = when {
    state.checkingServer -> EcColor.muted
    state.serverLevel == "ok" -> EcColor.good
    state.serverLevel == "warn" -> EcColor.warn
    state.serverLevel == "bad" -> EcColor.bad
    else -> EcColor.muted
}

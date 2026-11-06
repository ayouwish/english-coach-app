package top.dreamsearch.englishcoach.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.EcTheme
import top.dreamsearch.englishcoach.ui.nav.AppNavHost
import top.dreamsearch.englishcoach.ui.page.auth.LoginScreen

/**
 * 应用根（对应 hos `pages/Index.ets`）。
 *
 * 启动 → 读 token → GET /auth/me
 *   ├─ 成功   → [AppNavHost]（HomeScreen 5 个 Tab + 二级页）
 *   ├─ 无 token 但有记住的账号 → 自动登录 → 失败回落登录页
 *   └─ 网络失败 → 全屏错误 + 重试（**不误清 token**）/ 改服务器地址
 *
 * 未登录时直接显示 [LoginScreen]（不占路由），会话失效自动切回。
 */
@Composable
fun AppRoot() {
    val session by AppGraph.session.state.collectAsStateWithLifecycle()
    var booting by remember { mutableStateOf(true) }
    var bootError by remember { mutableStateOf<UiError?>(null) }
    var bootAttempt by remember { mutableIntStateOf(0) }
    var forceLogin by remember { mutableStateOf(false) }

    LaunchedEffect(bootAttempt) {
        booting = true
        bootError = null
        try {
            val restored = AppGraph.session.restore()
            if (!restored) {
                // 无 token：尝试「记住密码」自动登录（用户主动退出过则跳过）
                AppGraph.session.loginWithSaved()
            }
        } catch (e: Throwable) {
            bootError = AppGraph.session.toUiError(e)
        } finally {
            booting = false
        }
    }

    // 登录成功（含"启动失败→改服务器地址→登录"路径）后必须复位强制登录标记，
    // 否则 `!loggedIn || forceLogin` 会一直停在登录页（ui-kit 审计发现）。
    LaunchedEffect(session.loggedIn) {
        if (session.loggedIn) {
            forceLogin = false
            bootError = null
        }
    }

    EcTheme(isChild = session.isChild) {
        when {
            booting -> BootLoadingView()
            bootError != null && !forceLogin -> BootErrorView(
                error = bootError!!,
                onRetry = { bootAttempt++ },
                onChangeServer = { forceLogin = true },
            )
            !session.loggedIn || forceLogin -> LoginScreen()
            else -> AppNavHost()
        }
    }
}

@Composable
private fun BootLoadingView() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(EcColor.bg)
            .safeDrawingPadding()
            .padding(EcSpace.x8),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("English Coach", fontSize = EcFont.h1, fontWeight = FontWeight.Bold, color = EcColor.ink)
        Spacer(Modifier.height(EcSpace.x2))
        Text("家庭英语口语教练", fontSize = EcFont.body, color = EcColor.muted)
        Spacer(Modifier.height(EcSpace.x8))
        LoadingBlock(text = "正在连接家庭 NAS…", subText = "只在家庭 Wi-Fi / VPN 下可用")
    }
}

@Composable
private fun BootErrorView(error: UiError, onRetry: () -> Unit, onChangeServer: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(EcColor.bg)
            .safeDrawingPadding()
            .padding(EcSpace.x8),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("🏠", fontSize = EcFont.display)
        Spacer(Modifier.height(EcSpace.x4))
        Text(
            text = error.title.ifEmpty { "连不上家庭 NAS" },
            fontSize = EcFont.h2,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(EcSpace.x3))
        Text(
            text = error.message,
            fontSize = EcFont.body,
            color = EcColor.muted,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(EcSpace.x8))
        EcButton(label = "重试", onClick = onRetry, kind = EcButtonKind.PRIMARY, size = EcButtonSizeKind.LG)
        Spacer(Modifier.height(EcSpace.x3))
        EcButton(label = "修改服务器地址", onClick = onChangeServer, kind = EcButtonKind.GHOST)
        Spacer(Modifier.height(EcSpace.x2))
        Text(
            text = "如果一直连不上，可以在登录页修改服务器地址",
            fontSize = EcFont.caption,
            color = EcColor.muted,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

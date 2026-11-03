package top.dreamsearch.englishcoach

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable

/**
 * 单 Activity + Compose（对应 hos 的 EntryAbility + Index 根 Navigation）。
 *
 * 根内容见 `ui/AppRoot.kt`：
 *   启动 → 读 token → GET /auth/me
 *     ├─ 成功   → HomeScreen（5 个 Tab）
 *     ├─ 需登录 → LoginScreen
 *     └─ 网络失败 → 全屏错误 + 重试（不误清 token）
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AppRoot()
        }
    }
}

/** 占位：根组件在 `ui/AppRoot.kt` 中实现（见 android/CONTRACT.md §6）。 */
@Composable
internal fun AppRootPlaceholder() {
    // no-op
}

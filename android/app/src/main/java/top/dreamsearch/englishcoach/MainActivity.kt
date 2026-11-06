package top.dreamsearch.englishcoach

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import top.dreamsearch.englishcoach.ui.AppRoot

/**
 * 单 Activity + Compose（对应 hos 的 EntryAbility + Index 根 Navigation）。
 *
 * 根内容见 `ui/AppRoot.kt`：
 *   启动 → 读 token → GET /auth/me
 *     ├─ 成功   → HomeScreen（5 个 Tab）+ 二级页
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

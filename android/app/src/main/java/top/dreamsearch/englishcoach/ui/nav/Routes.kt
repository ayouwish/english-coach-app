package top.dreamsearch.englishcoach.ui.nav

import androidx.navigation.NavController
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * 路由常量（对应 hos `core/router/Routes.ets`，docs/architecture.md §4.2）。
 * 跨页面跳转只允许用这里的常量，禁止手写字符串。
 *
 * 一级 Tab 不占路由：首页是 [Routes.HOME]，内部 Tab 由 [Tabs] + [TabNav] 控制。
 */
object Routes {
    const val HOME = "home"

    // 跟读 / 语料
    const val SENTENCES = "sentences"

    // 连读
    const val FLOW_SUMMARY = "flow_summary"

    // 对话
    const val CHAT_SESSION = "chat_session"
    const val CHAT_HISTORY = "chat_history"
    const val CHAT_DETAIL = "chat_detail"
    const val CHAT_CUSTOM = "chat_custom"

    // 故事
    const val STORY_RECORD = "story_record"
    const val STORY_DETAIL = "story_detail"
    const val STORY_REVIEW = "story_review"

    // 统计 / 家长 / 其他
    const val DIAGNOSIS = "diagnosis"
    const val REVIEW = "review"
    const val BLIND_TEST = "blind_test"
    const val PARENT = "parent"
    const val FAMILY = "family"
    const val SUGGESTIONS = "suggestions"
    const val AVATAR = "avatar"
    const val VOICES = "voices"
    const val HEALTH = "health"
    const val SETTINGS = "settings"

    /** 离线能力：待重试的评测录音队列（网络恢复后统一重试） */
    const val PENDING_UPLOADS = "pending_uploads"
}

/** 一级 Tab 下标（与 HomeTabs 顺序一致）。 */
object Tabs {
    const val PRACTICE = 0
    const val FLOW = 1
    const val CHAT = 2
    const val STORY = 3
    const val ME = 4
}

/**
 * 页面间跳转的轻量参数袋（替代 hos 的 AppStorage 'tab_index' 与 URL 查询参数）。
 *
 * 用法：跳转前写入 → `nav.navigate(Routes.XXX)` → 目标页在 VM 初始化时读取并立即清空。
 */
object NavParams {
    /** 跟读：指定等级 / 音素 focus / 句子 id */
    @Volatile var practiceLevel: String? = null
    @Volatile var practiceFocus: String? = null
    @Volatile var practiceSentenceId: String? = null

    /** 连读：从故事详情进入时指定材料 id */
    @Volatile var flowMaterialId: String? = null

    /** 对话：会话 id / 历史详情 id */
    @Volatile var chatSessionId: String? = null
    @Volatile var chatDetailId: String? = null

    /** 故事：材料 id */
    @Volatile var storyMaterialId: String? = null

    /** 诊断「连读这一批」：由连读汇总页跳转前写入本批 attempt id（可为空 = 用最近一次批次） */
    @Volatile var diagnosisAttemptIds: List<String>? = null

    fun clearPractice() {
        practiceLevel = null
        practiceFocus = null
        practiceSentenceId = null
    }
}

/**
 * 跨页切 Tab：故事详情「去连读」、首页快捷卡等需要切到某个 Tab 并回到首页。
 *
 * 用法：`TabNav.go(Tabs.FLOW)`；HomeScreen 收集 [pending] 后切 Tab 并清空。
 */
object TabNav {
    val pending = MutableStateFlow<Int?>(null)

    fun go(tab: Int) {
        pending.value = tab
    }

    fun consume(): Int? {
        val value = pending.value
        pending.value = null
        return value
    }
}

/**
 * 全局导航句柄：让 **Tab 根页**（没有 navController 参数）也能 push/pop。
 *
 * 由 [AppNavHost] 在组合时 bind；Tab 内点击卡片/入口时：
 * ```
 * NavParams.storyMaterialId = id
 * Navigator.navigate(Routes.STORY_DETAIL)
 * ```
 * 二级页仍优先用传入的 `onBack` 等回调（可测试、语义清晰）。
 */
object Navigator {
    @Volatile
    private var controller: NavController? = null

    fun bind(nav: NavController) {
        controller = nav
    }

    fun unbind() {
        controller = null
    }

    fun navigate(route: String) {
        controller?.navigate(route) { launchSingleTop = true }
    }

    fun pop(): Boolean = controller?.popBackStack() ?: false

    fun popTo(route: String) {
        controller?.popBackStack(route, inclusive = false)
    }
}

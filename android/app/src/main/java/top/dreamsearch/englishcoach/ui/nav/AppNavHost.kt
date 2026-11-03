package top.dreamsearch.englishcoach.ui.nav

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import top.dreamsearch.englishcoach.ui.HomeScreen
import top.dreamsearch.englishcoach.ui.page.account.AvatarScreen
import top.dreamsearch.englishcoach.ui.page.account.FamilyScreen
import top.dreamsearch.englishcoach.ui.page.account.HealthScreen
import top.dreamsearch.englishcoach.ui.page.account.ParentScreen
import top.dreamsearch.englishcoach.ui.page.account.SettingsScreen
import top.dreamsearch.englishcoach.ui.page.account.SuggestionsScreen
import top.dreamsearch.englishcoach.ui.page.account.VoicesScreen
import top.dreamsearch.englishcoach.ui.page.chat.ChatCustomScreen
import top.dreamsearch.englishcoach.ui.page.chat.ChatDetailScreen
import top.dreamsearch.englishcoach.ui.page.chat.ChatHistoryScreen
import top.dreamsearch.englishcoach.ui.page.chat.ChatSessionScreen
import top.dreamsearch.englishcoach.ui.page.flow.FlowSummaryScreen
import top.dreamsearch.englishcoach.ui.page.practice.SentenceListScreen
import top.dreamsearch.englishcoach.ui.page.stats.BlindTestScreen
import top.dreamsearch.englishcoach.ui.page.stats.DiagnosisScreen
import top.dreamsearch.englishcoach.ui.page.stats.ReviewScreen
import top.dreamsearch.englishcoach.ui.page.story.StoryDetailScreen
import top.dreamsearch.englishcoach.ui.page.story.StoryRecordScreen
import top.dreamsearch.englishcoach.ui.page.story.StoryReviewScreen

/**
 * 已登录后的导航图（对应 hos `Index.ets` 的 Navigation + pageMap）。
 *
 * - `home` = 5 个 Tab 的 [HomeScreen]；
 * - 其余全是 push 出来的二级页，页面自己用 `PageScaffold` 画标题栏；
 * - 跨页参数走 [NavParams]（跳转前写入），页面读后自行清空。
 *
 * 登录/启动态不在这里：由 `ui/AppRoot.kt` 在未登录时直接显示登录页。
 */
@Composable
fun AppNavHost() {
    val nav = rememberNavController()
    // 让 Tab 根页也能导航（见 Navigator 注释）
    androidx.compose.runtime.DisposableEffect(nav) {
        Navigator.bind(nav)
        onDispose { Navigator.unbind() }
    }
    val back: () -> Unit = { nav.popBackStack() }
    val goHome: () -> Unit = { nav.popBackStack(Routes.HOME, inclusive = false) }

    NavHost(navController = nav, startDestination = Routes.HOME) {
        composable(Routes.HOME) {
            HomeScreen(onNavigate = { route -> nav.navigate(route) { launchSingleTop = true } })
        }

        composable(Routes.SENTENCES) {
            SentenceListScreen(onBack = back)
        }

        composable(Routes.FLOW_SUMMARY) {
            FlowSummaryScreen(
                onBack = back,
                onOpenFlowTab = {
                    TabNav.go(Tabs.FLOW)
                    goHome()
                },
            )
        }

        composable(Routes.CHAT_SESSION) {
            ChatSessionScreen(onBack = back)
        }

        composable(Routes.CHAT_HISTORY) {
            ChatHistoryScreen(
                onBack = back,
                onOpenDetail = {
                    NavParams.chatDetailId = it
                    nav.navigate(Routes.CHAT_DETAIL) { launchSingleTop = true }
                },
            )
        }

        composable(Routes.CHAT_DETAIL) {
            ChatDetailScreen(onBack = back)
        }

        composable(Routes.CHAT_CUSTOM) {
            ChatCustomScreen(onBack = back)
        }

        composable(Routes.STORY_RECORD) {
            StoryRecordScreen(
                onBack = back,
                onOpenFlow = {
                    TabNav.go(Tabs.FLOW)
                    goHome()
                },
            )
        }

        composable(Routes.STORY_DETAIL) {
            StoryDetailScreen(
                onBack = back,
                onOpenFlow = {
                    TabNav.go(Tabs.FLOW)
                    goHome()
                },
                onOpenReview = { nav.navigate(Routes.STORY_REVIEW) { launchSingleTop = true } },
            )
        }

        composable(Routes.STORY_REVIEW) {
            StoryReviewScreen(onBack = back)
        }

        composable(Routes.DIAGNOSIS) {
            DiagnosisScreen(
                onBack = back,
                onPracticeFocus = { token ->
                    NavParams.practiceFocus = token
                    TabNav.go(Tabs.PRACTICE)
                    goHome()
                },
            )
        }

        composable(Routes.REVIEW) {
            ReviewScreen(onBack = back)
        }

        composable(Routes.BLIND_TEST) {
            BlindTestScreen(onBack = back)
        }

        composable(Routes.PARENT) {
            ParentScreen(
                onBack = back,
                onOpenFamily = { nav.navigate(Routes.FAMILY) { launchSingleTop = true } },
                onOpenSuggestions = { nav.navigate(Routes.SUGGESTIONS) { launchSingleTop = true } },
            )
        }

        composable(Routes.FAMILY) {
            FamilyScreen(onBack = back)
        }

        composable(Routes.SUGGESTIONS) {
            SuggestionsScreen(onBack = back)
        }

        composable(Routes.AVATAR) {
            AvatarScreen(onBack = back)
        }

        composable(Routes.VOICES) {
            VoicesScreen(onBack = back)
        }

        composable(Routes.HEALTH) {
            HealthScreen(onBack = back)
        }

        composable(Routes.SETTINGS) {
            SettingsScreen(
                onBack = back,
                onOpenAvatar = { nav.navigate(Routes.AVATAR) { launchSingleTop = true } },
                onOpenVoices = { nav.navigate(Routes.VOICES) { launchSingleTop = true } },
                onOpenHealth = { nav.navigate(Routes.HEALTH) { launchSingleTop = true } },
                onOpenSuggestions = { nav.navigate(Routes.SUGGESTIONS) { launchSingleTop = true } },
                onLogout = {
                    // 退出会清 session → AppRoot 自动切回登录页
                    nav.popBackStack(Routes.HOME, inclusive = false)
                },
            )
        }

        // 兜底：不存在的路由 → 回首页
        composable("") { HomeScreen(onNavigate = { nav.navigate(it) { launchSingleTop = true } }) }
    }
}

/** 供调试/深链使用（M1 未启用深链，保留入口）。 */
@Composable
fun rememberAppNavController(): NavHostController = rememberNavController()

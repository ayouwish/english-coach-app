package top.dreamsearch.englishcoach.ui.page.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.config.AppConfig
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.session.SessionState
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RemoteImage
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.design.LocalIsChild
import top.dreamsearch.englishcoach.ui.nav.Routes

/**
 * 「我的」Tab（签名按 CONTRACT §5：`MeTab(onNavigate: (String) -> Unit)`）。
 *
 * 对应 hos `pages/MePage.ets`。内容：
 * - 账号卡：头像（`RemoteImage` 接口图 / emoji / 首字兜底）、昵称、角色 · CEFR、邮箱、今日分钟；
 * - 今日用量卡：已练 / 上限 / 剩余 / 进度条 / 超限提醒（`session.exceeded`）；
 * - 入口按角色分流（儿童精简；家长面板/家庭成员仅 `role == parent`）；
 * - 底部版本 + 服务器地址 + 退出登录（`session.logout()` 后 AppRoot 自动切登录页）。
 *
 * 页面不直接发请求：刷新用量与服务状态都在 [MeViewModel]。
 */
@Composable
fun MeTab(onNavigate: (String) -> Unit) {
    val vm: MeViewModel = viewModel(
        factory = remember { vmFactory { MeViewModel(AppGraph.container) } }
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val session by AppGraph.session.state.collectAsStateWithLifecycle()
    val isChild = LocalIsChild.current
    val isParent = !isChild && session.role == "parent"

    // 回到本页时刷新：待补评分条数（离线队列）+ 能力开关（形象入口置灰）
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        vm.refreshPending()
        vm.refreshCapabilities()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(EcColor.bg)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = EcSpace.x4, vertical = EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
    ) {
        UserCard(session = session, isChild = isChild)
        UsageCard(
            session = session,
            isChild = isChild,
            refreshing = state.refreshing,
            onRefresh = vm::refresh,
        )
        state.error?.let { error ->
            ErrorBanner(error = error, onRetry = vm::refresh, onDismiss = vm::dismissError)
        }

        // 待补评分录音（离线队列）：有才显示，点进去重试/删除
        if (state.pendingCount > 0) {
            PendingUploadsCard(
                count = state.pendingCount,
                isChild = isChild,
                onClick = { onNavigate(Routes.PENDING_UPLOADS) },
            )
        }

        if (isChild) {
            // 儿童精简入口：只留复习、表达与基础偏好
            GroupTitle("学习")
            EcCard {
                Tile("📕", "我的小错音本", "按记忆曲线复习读错的音", isChild) {
                    onNavigate(Routes.REVIEW)
                }
            }
            GroupTitle("偏好")
            EcCard {
                Tile("🗣️", "音色", "选一个喜欢的声音", isChild) {
                    onNavigate(Routes.VOICES)
                }
                Tile(
                    icon = "🎨",
                    title = "我的形象",
                    subtitle = if (state.avatarPresetsAvailable) {
                        "选一个小伙伴当形象"
                    } else {
                        "当前服务端未开启"
                    },
                    isChild = isChild,
                    enabled = state.avatarPresetsAvailable,
                ) {
                    onNavigate(Routes.AVATAR)
                }
                Tile("⚙️", "设置", "语速、故事长度、账号", isChild) {
                    onNavigate(Routes.SETTINGS)
                }
            }
            GroupTitle("家长")
            EcCard {
                Tile("💡", "我想说", "给爸爸妈妈提个建议", isChild) {
                    onNavigate(Routes.SUGGESTIONS)
                }
            }
        } else {
            GroupTitle("学习")
            EcCard {
                Tile("🔍", "发音诊断", "最薄弱的音素与建议", isChild) {
                    onNavigate(Routes.DIAGNOSIS)
                }
                Tile("📕", "错音本", "按记忆曲线复习读错的音", isChild) {
                    onNavigate(Routes.REVIEW)
                }
                Tile("🎭", "盲测周报", "每周一次，只统计已评分", isChild) {
                    onNavigate(Routes.BLIND_TEST)
                }
            }
            GroupTitle("偏好")
            EcCard {
                Tile("⚙️", "设置", "账号偏好、服务器、缓存", isChild) {
                    onNavigate(Routes.SETTINGS)
                }
                Tile("🗣️", "音色", "9 种音色，可试听", isChild) {
                    onNavigate(Routes.VOICES)
                }
                Tile(
                    icon = "🎨",
                    title = "我的形象",
                    subtitle = if (state.avatarPresetsAvailable) {
                        "预置形象选择题"
                    } else {
                        "当前服务端未开启"
                    },
                    isChild = isChild,
                    enabled = state.avatarPresetsAvailable,
                ) {
                    onNavigate(Routes.AVATAR)
                }
            }
            GroupTitle("家长")
            EcCard {
                if (isParent) {
                    Tile("👨‍👩‍👧", "家长面板", "使用时长 / 趋势 / 掌握度", isChild) {
                        onNavigate(Routes.PARENT)
                    }
                    Tile("👥", "家庭成员", "建账号、改水平、重置密码", isChild) {
                        onNavigate(Routes.FAMILY)
                    }
                }
                Tile(
                    icon = "💡",
                    title = if (isParent) "建议箱" else "我想说",
                    subtitle = if (isParent) "孩子提的建议都在这里" else "给爸爸妈妈提个建议",
                    isChild = isChild,
                ) {
                    onNavigate(Routes.SUGGESTIONS)
                }
            }
        }

        GroupTitle("服务")
        EcCard {
            Tile(
                icon = "🩺",
                title = "服务状态",
                subtitle = state.serverStatus.ifEmpty { "家庭 NAS / 语音能力自查" },
                isChild = isChild,
                tone = state.serverLevel,
            ) {
                onNavigate(Routes.HEALTH)
            }
        }

        Text(
            text = "English Coach ${AppConfig.APP_VERSION} · ${AppGraph.config.baseUrl}",
            fontSize = EcFont.micro,
            color = EcColor.muted,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = EcSpace.x2, bottom = EcSpace.x1),
        )

        EcButton(
            label = if (state.loggingOut) "退出中…" else "退出登录",
            onClick = vm::logout,
            kind = EcButtonKind.DANGER,
            size = if (isChild) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            loading = state.loggingOut,
            fullWidth = true,
        )

        Spacer(modifier = Modifier.height(EcSpace.x6))
    }
}

// ---------------------------------------------------------------------------
// 卡片
// ---------------------------------------------------------------------------

@Composable
private fun UserCard(session: SessionState, isChild: Boolean) {
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
        ) {
            AvatarBadge(session = session, isChild = isChild)
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
            ) {
                Text(
                    text = session.displayName.ifEmpty { "我的账号" },
                    fontSize = if (isChild) EcFont.childH1 else EcFont.h3,
                    fontWeight = FontWeight.Bold,
                    color = EcColor.ink,
                )
                Text(
                    text = roleText(session),
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                )
                if (session.email.isNotEmpty()) {
                    Text(
                        text = session.email,
                        fontSize = EcFont.micro,
                        color = EcColor.muted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
                    EcPill(text = "今日 ${session.minutesToday} 分钟", tone = PillTone.INFO)
                    if (isChild) {
                        EcPill(text = "儿童模式", tone = PillTone.GOOD)
                    } else if (session.role == "parent") {
                        EcPill(text = "家长", tone = PillTone.NEUTRAL)
                    }
                }
            }
        }
    }
}

@Composable
private fun UsageCard(
    session: SessionState,
    isChild: Boolean,
    refreshing: Boolean,
    onRefresh: () -> Unit,
) {
    val limit = session.dailyLimitMinutes.coerceAtLeast(1)
    val fraction = (session.minutesToday.toFloat() / limit.toFloat()).coerceIn(0f, 1f)
    val barColor = if (session.exceeded) EcColor.warn else EcColor.primary
    EcCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "今日学习",
                fontSize = if (isChild) EcFont.childBody else EcFont.body,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = if (refreshing) "刷新中…" else "刷新",
                fontSize = EcFont.caption,
                color = if (refreshing) EcColor.muted else EcColor.primary,
                modifier = Modifier
                    .clickable(enabled = !refreshing, onClick = onRefresh)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
            )
        }

        // 进度条（不用环，儿童/成人都能一眼看懂）
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(EcRadius.pill))
                .background(EcColor.surfaceAlt),
        ) {
            if (fraction > 0f) {
                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .fillMaxWidth(fraction)
                        .clip(RoundedCornerShape(EcRadius.pill))
                        .background(barColor),
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "已练 ${session.minutesToday} / ${session.dailyLimitMinutes} 分钟",
                fontSize = EcFont.caption,
                color = EcColor.muted,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = if (session.exceeded) "今日已用完" else "剩余 ${session.remainingMinutes} 分钟",
                fontSize = EcFont.caption,
                color = if (session.exceeded) EcColor.warnText else EcColor.ink,
            )
        }

        if (session.exceeded) {
            EcInlineNotice(
                text = if (isChild) {
                    "今天的练习时间用完啦，明天再来 🌙"
                } else {
                    "今日练习时长已达上限，明天再来；家长可在设置里调整上限"
                },
                tone = PillTone.WARN,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// 小组件
// ---------------------------------------------------------------------------

@Composable
private fun GroupTitle(text: String) {
    Text(
        text = text,
        fontSize = EcFont.caption,
        fontWeight = FontWeight.Medium,
        color = EcColor.muted,
        modifier = Modifier.padding(start = EcSpace.x1, top = EcSpace.x1),
    )
}

@Composable
private fun Tile(
    icon: String,
    title: String,
    subtitle: String,
    isChild: Boolean,
    tone: String = "",
    /** false = 置灰不可点（如服务端未开启预置形象库）；副标题由调用方给「当前服务端未开启」。 */
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
            modifier = Modifier.width(36.dp).then(
                if (enabled) Modifier else Modifier.alpha(0.4f),
            ),
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
                Text(
                    text = subtitle,
                    fontSize = EcFont.micro,
                    color = if (tone == "bad") EcColor.badText else EcColor.muted,
                )
            }
        }
        Text(
            text = if (enabled) "›" else "—",
            fontSize = 22.sp,
            color = EcColor.muted,
        )
    }
}

/**
 * 「待补评分录音」入口卡（ROUND2 §1.3 离线队列）。
 *
 * 只在本机队列 > 0 时显示；点进去可重试/删除（页面由 screens-chat 负责）。
 */
@Composable
private fun PendingUploadsCard(count: Int, isChild: Boolean, onClick: () -> Unit) {
    EcCard(onClick = onClick) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = "📤", fontSize = if (isChild) 26.sp else 22.sp)
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "待补评分录音 $count 条",
                    fontSize = if (isChild) EcFont.childBody else EcFont.body,
                    fontWeight = FontWeight.Medium,
                    color = EcColor.ink,
                )
                Text(
                    text = "录音已保存在本机（网络不好时没提交成功），点这里补评分",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                )
            }
            EcPill(text = "$count", tone = PillTone.WARN)
            Text(text = "›", fontSize = 22.sp, color = EcColor.muted)
        }
    }
}

/** 头像：emoji 优先；站内静态图/接口图走 [RemoteImage]；都没有则首字兜底。 */
@Composable
private fun AvatarBadge(session: SessionState, isChild: Boolean) {
    val size = if (isChild) 72.dp else 64.dp
    val avatar = session.avatar.trim()
    when {
        avatar.startsWith("http://", ignoreCase = true) || avatar.startsWith("https://", ignoreCase = true) -> {
            RemoteImage(
                path = avatar,
                contentDescription = "头像",
                modifier = Modifier.size(size).clip(CircleShape),
                withAuth = false,
                fallback = { InitialAvatar(session.displayName, size) },
            )
        }

        avatar.startsWith("/") -> {
            RemoteImage(
                path = avatar,
                contentDescription = "头像",
                modifier = Modifier.size(size).clip(CircleShape),
                withAuth = false,
                fallback = { InitialAvatar(session.displayName, size) },
            )
        }

        avatar.isNotEmpty() -> {
            Box(
                modifier = Modifier
                    .size(size)
                    .clip(CircleShape)
                    .background(EcColor.primarySoft),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = avatar, fontSize = if (isChild) 32.sp else 28.sp)
            }
        }

        // 没有 emoji/预置图时尝试接口头像（照片策略关闭时 403，自动落到首字兜底）
        else -> {
            RemoteImage(
                path = "/avatar/image",
                contentDescription = "头像",
                modifier = Modifier.size(size).clip(CircleShape),
                withAuth = true,
                fallback = { InitialAvatar(session.displayName, size) },
            )
        }
    }
}

@Composable
private fun InitialAvatar(displayName: String, size: Dp) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(EcColor.primary),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = displayName.trim().take(1).ifEmpty { "👤" },
            fontSize = if (size >= 72.dp) 28.sp else 24.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
        )
    }
}

private fun roleText(session: SessionState): String {
    val role = when {
        session.isChild -> "小朋友"
        session.role == "parent" -> "家长"
        else -> "学习者"
    }
    return "$role · ${session.cefrLevel}"
}

import SwiftUI

/// 应用根（契约 §3.15）：启动三态 + 会话过期弹层。
///
/// 状态机：
/// - `.launching` → 启动画面（`bootstrap()` 正在恢复会话）；
/// - `.signedOut`：
///   - 恢复失败（网络 / 服务端 / 解码，且不是 401/403）→ **全屏错误 + 重试 + 改地址**；
///   - 其余 → 登录页 `LoginView`；
/// - `.signedIn`：`AppServices` 装配完成 → `RootTabView`（装配中的一帧仍显示启动态）。
///
/// 全局环境只注入三种（契约 §3.15 约定 2）：`SessionStore`、`AppRouter`、`\.roleCapabilities`。
struct AppRoot: View {
    @Environment(AppEnvironment.self) private var environment
    /// 启动错误页点“修改服务器地址”后强制进入登录页（不让全屏错误挡住用户）。
    @State private var showsLoginWhileStartupFailed = false
    @State private var sessionExpiredTitle = "登录已过期"
    @State private var sessionExpiredBody = "请重新登录后继续使用。"
    @State private var showsSessionExpiredAlert = false

    var body: some View {
        content
            .environment(environment.session)
            .environment(environment.router)
            // 额外注入 AppConfig：设置页（B5b）需要读写“服务器地址”，而 §3.15.1 冻结的
            // `SettingsView(services:audio:)` 没有 config 参数、Features 又不允许引用
            // AppEnvironment；`AppConfig` 属于 Core，作为环境值注入不引入反向依赖。
            .environment(environment.config)
            .environment(\.roleCapabilities, environment.session.capabilities)
            .task {
                await environment.bootstrap()
            }
            .task(id: environment.session.phase) {
                await environment.syncServicesWithSession()
            }
            .onChange(of: environment.session.startupError) { _, error in
                presentSessionExpiredAlertIfNeeded(error)
            }
            .alert(sessionExpiredTitle, isPresented: $showsSessionExpiredAlert) {
                Button("重新登录", role: .cancel) {}
            } message: {
                Text(sessionExpiredBody)
            }
    }

    // MARK: - 三态内容

    @ViewBuilder
    private var content: some View {
        switch environment.session.phase {
        case .launching:
            AppLaunchingView(message: "正在恢复登录…")
        case .signedOut:
            signedOutContent
        case .signedIn:
            signedInContent
        }
    }

    @ViewBuilder
    private var signedOutContent: some View {
        if let error = environment.session.startupError,
           !error.isUnauthorized,
           !error.isForbidden,
           !showsLoginWhileStartupFailed {
            AppStartupErrorView(
                error: error,
                isChild: environment.session.isChild,
                onRetry: {
                    showsLoginWhileStartupFailed = false
                    Task { await environment.session.retryRestore() }
                },
                onEditServer: {
                    showsLoginWhileStartupFailed = true
                }
            )
        } else {
            LoginView(
                session: environment.session,
                config: environment.config,
                testConnection: { baseURLText in
                    try await environment.testConnection(baseURLText: baseURLText)
                }
            )
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        if let services = environment.services {
            RootTabView(services: services, audio: environment.audio)
        } else {
            // 登录成功到 Service 装配完成之间的一帧：显示启动态，避免闪一下空主界面。
            AppLaunchingView(message: "正在准备…")
        }
    }

    // MARK: - 会话过期

    /// `handleSessionExpired()` / 启动恢复被服务端拒绝时，`startupError == .unauthorized`
    /// 会让 AppRoot 弹一次“登录已过期”（screens.md §0：错误内联，会话过期除外）。
    private func presentSessionExpiredAlertIfNeeded(_ error: APIError?) {
        guard let error,
              error.isUnauthorized,
              environment.session.phase == .signedOut
        else {
            return
        }
        let message = ErrorMapper.message(for: error, isChild: environment.session.isChild)
        guard !message.isSilent else { return }
        sessionExpiredTitle = message.title
        sessionExpiredBody = message.body ?? "请重新登录后继续使用。"
        showsSessionExpiredAlert = true
    }
}

// MARK: - 启动画面

/// 启动/装配等待态：品牌 + 一句进度文案（不显示假百分比）。
private struct AppLaunchingView: View {
    let message: String

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        ZStack {
            Tokens.Colors.canvas.ignoresSafeArea()
            VStack(spacing: Tokens.Spacing.s16) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Tokens.Colors.onPrimary)
                    .frame(width: 88, height: 88)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: [
                                    Tokens.Colors.brandGradientStart,
                                    Tokens.Colors.brandGradientEnd,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .accessibilityHidden(true)
                Text("English Coach")
                    .font(AppFont.titleLarge(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text("家庭英语口语教练")
                    .font(AppFont.footnote(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                LoadingBlock(text: message)
            }
            .padding(Tokens.Spacing.s24)
        }
    }
}

// MARK: - 启动失败

/// 全屏启动失败：标题/说明来自 `ErrorMapper`，提供“重试”与“修改服务器地址”两个出路。
private struct AppStartupErrorView: View {
    let error: APIError
    let isChild: Bool
    let onRetry: () -> Void
    let onEditServer: () -> Void

    @Environment(\.roleCapabilities) private var caps

    private var message: UIMessage {
        ErrorMapper.message(for: error, isChild: isChild)
    }

    var body: some View {
        ZStack {
            Tokens.Colors.canvas.ignoresSafeArea()
            VStack(spacing: Tokens.Spacing.s16) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: caps.isChild ? 56 : 44, weight: .regular))
                    .foregroundStyle(caps.isChild ? Tokens.Colors.childAccent : Tokens.Colors.textSecondary)
                    .accessibilityHidden(true)
                Text(message.title)
                    .font(AppFont.heading(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                if let body = message.body {
                    Text(body)
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AppButton(title: message.actionTitle ?? "重试", icon: "arrow.clockwise", kind: .primary, action: onRetry)
                    .frame(maxWidth: 320)
                AppButton(title: "修改服务器地址", icon: "gearshape", kind: .ghost, action: onEditServer)
                    .frame(maxWidth: 320)
                Text("如果一直连不上，请确认手机连着家里的 Wi-Fi，且 NAS 已开机。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Tokens.Spacing.s24)
        }
    }
}

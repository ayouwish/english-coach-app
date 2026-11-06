import SwiftUI

/// 登录页（契约 §3.15.1 冻结签名：`LoginView(session:config:testConnection:)`）。
///
/// 交互（`ios/docs/screens.md` §1）：
/// - 服务器地址（裸域名自动补 `https://` + `/api`）、测试连通、演示邮箱填充；
/// - 记住登录默认**关**（勾选后密码进 Keychain，下次预填但**不自动提交**）；
/// - 错误一律内联（`ErrorMapper` 文案），登录失败 401 显示“邮箱或密码不正确”；
/// - 隐私提示如实：录音会经家里服务器转发云端语音服务。
struct LoginView: View {
    private let session: SessionStore
    private let config: AppConfig
    private let testConnection: @MainActor (String) async throws -> HealthDTO

    @State private var viewModel: AuthViewModel?

    init(
        session: SessionStore,
        config: AppConfig,
        testConnection: @escaping @MainActor (String) async throws -> HealthDTO
    ) {
        self.session = session
        self.config = config
        self.testConnection = testConnection
    }

    var body: some View {
        Group {
            if let viewModel {
                LoginContent(viewModel: viewModel)
            } else {
                LoadingBlock(text: "正在准备登录…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = AuthViewModel(session: session, config: config, testConnection: testConnection)
            await model.prepare()
            viewModel = model
        }
    }
}

// MARK: - 表单内容

private struct LoginContent: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.roleCapabilities) private var caps

    @FocusState private var focused: Field?
    @State private var showsPassword = false

    private enum Field: Hashable {
        case email
        case password
        case server
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s24) {
                header

                if viewModel.showsStartupBanner {
                    ErrorBanner(
                        message: viewModel.startupBannerMessage,
                        retryTitle: "重试",
                        onRetry: {
                            Task {
                                viewModel.clearError()
                                await viewModel.session.retryRestore()
                            }
                        }
                    )
                }

                credentialsCard
                serverCard
                demoSection
                privacyFooter
            }
            .padding(.horizontal, Tokens.Spacing.s16)
            .padding(.vertical, Tokens.Spacing.s32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .onChange(of: viewModel.error) { _, newValue in
            if newValue != nil {
                focused = .password
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Tokens.Colors.onPrimary)
                .frame(width: 68, height: 68)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Tokens.Colors.primary, Tokens.Colors.primary.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .shadow(color: Tokens.Shadow.floatingTint, radius: 12, x: 0, y: 6)
                .accessibilityHidden(true)

            Text("English Coach")
                .font(AppFont.display(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)

            Text("和家人一起，把英语说出来")
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
    }

    // MARK: 账号 / 密码

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            fieldLabel("邮箱")
            TextField("you@example.com", text: $viewModel.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focused, equals: .email)
                .onSubmit { focused = .password }
                .loginFieldStyle()

            fieldLabel("密码")
            HStack(spacing: Tokens.Spacing.s8) {
                Group {
                    if showsPassword {
                        TextField("密码", text: $viewModel.password)
                    } else {
                        SecureField("密码", text: $viewModel.password)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focused, equals: .password)
                .onSubmit { submit() }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showsPassword.toggle()
                } label: {
                    Image(systemName: showsPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsPassword ? "隐藏密码" : "显示密码")
            }
            .loginFieldStyle()

            rememberToggle

            AppButton(
                title: "登录",
                icon: "arrow.right.circle.fill",
                isLoading: viewModel.isSubmitting,
                isEnabled: viewModel.canSubmit,
                action: { submit() }
            )
            .padding(.top, Tokens.Spacing.s4)

            if let error = viewModel.error {
                if error.isRetryable {
                    InlineErrorView(
                        message: errorText(error),
                        retryTitle: error.actionTitle ?? "重试",
                        onRetry: { submit() }
                    )
                } else {
                    InlineErrorView(message: errorText(error))
                }
            }

            if viewModel.storageDegraded {
                Text("本机安全存储不可用：登录状态可能无法跨重启保存，下次打开需要重新登录。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.prefilledRemembered && !viewModel.password.isEmpty {
                Text("已填入上次记住的账号；如不想保存，请关闭上面的开关。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private var rememberToggle: some View {
        Toggle(
            isOn: Binding(
                get: { viewModel.rememberPassword },
                set: { viewModel.setRememberPassword($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text("记住登录")
                    .font(AppFont.footnote(caps).weight(.semibold))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text("密码只保存在本机系统安全存储（Keychain），不会上传；共用设备建议关闭。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Tokens.Colors.primary)
        .accessibilityLabel(Text("记住登录"))
    }

    // MARK: 服务器地址

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            fieldLabel("服务器地址")
            TextField("https://english.dreamsearch.top/api", text: $viewModel.baseURLText)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused, equals: .server)
                .onSubmit { focused = nil }
                .loginFieldStyle()

            Text("只填主机名也可以（自动补 https:// 与 /api）；手机需要和家里的服务器在同一网络。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.usesInsecureHTTP {
                Text("当前是 HTTP：系统默认会拦截，且凭据会明文传输。请改用 HTTPS 地址。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Tokens.Spacing.s12) {
                Button {
                    Task { await viewModel.testServer() }
                } label: {
                    HStack(spacing: Tokens.Spacing.s4) {
                        if viewModel.isTestingConnection {
                            ProgressView().controlSize(.small)
                        }
                        Text(viewModel.isTestingConnection ? "正在测试…" : "测试连接")
                    }
                    .font(AppFont.footnote(caps).weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(minHeight: caps.minTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isTestingConnection)
                .accessibilityLabel(Text("测试连接"))

                Spacer(minLength: 0)

                connectionText
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var connectionText: some View {
        switch viewModel.connection {
        case .idle:
            EmptyView()
        case .testing:
            Text("正在检查服务器…")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
        case .succeeded(let summary):
            VStack(alignment: .trailing, spacing: Tokens.Spacing.s2) {
                HStack(spacing: Tokens.Spacing.s8) {
                    checkItem(title: "数据库", ok: summary.dbOK)
                    checkItem(title: "语音", ok: summary.voiceReachable)
                }
                Text(summary.text)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(summary.voiceReachable == false ? Tokens.Colors.warningText : Tokens.Colors.successText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let message):
            Text(message)
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.warningText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkItem(title: String, ok: Bool?) -> some View {
        HStack(spacing: Tokens.Spacing.s2) {
            Image(systemName: ok == false ? "xmark.circle.fill" : (ok == true ? "checkmark.circle.fill" : "questionmark.circle"))
                .font(AppFont.micro(caps))
                .foregroundStyle(ok == false ? Tokens.Colors.dangerText : (ok == true ? Tokens.Colors.successText : Tokens.Colors.textTertiary))
            Text(title)
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title)：\(ok == false ? "异常" : (ok == true ? "正常" : "未知"))"))
    }

    // MARK: 演示账号

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("演示账号")
                .font(AppFont.footnote(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
            Text("联调快捷填充：只填邮箱，密码请向家长确认（不把密码编译进 App）。正式使用请改为家里 NAS 上的真实账号。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Tokens.Spacing.s8) {
                ForEach(AppConfig.demoAccounts) { account in
                    AppButton(title: account.label, icon: "person.crop.circle.badge.checkmark", kind: .ghost) {
                        viewModel.fillDemo(account)
                        focused = .password
                    }
                }
            }
        }
    }

    // MARK: 隐私与版本

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("关于录音与隐私")
                .font(AppFont.caption(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
            Text("录音会上传到家里的学习服务器，并可能转发给云端语音服务用于识别与发音评分，会离开家庭网络；照片同样可能上传用于识别。不会上传通讯录或其他无关数据。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("English Coach \(AppConfig.appVersion)")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
        }
        .padding(.top, Tokens.Spacing.s8)
    }

    // MARK: 动作

    private func submit() {
        focused = nil
        Task { await viewModel.login() }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.footnote(caps).weight(.semibold))
            .foregroundStyle(Tokens.Colors.textSecondary)
    }

    private func errorText(_ message: UIMessage) -> String {
        let body = message.body ?? ""
        if message.title.isEmpty {
            return body
        }
        return body.isEmpty ? message.title : "\(message.title)：\(body)"
    }
}

// MARK: - 输入框样式

private struct LoginFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17))
            .foregroundStyle(Tokens.Colors.textPrimary)
            .padding(.horizontal, Tokens.Spacing.s12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.button, style: .continuous)
                    .fill(Tokens.Colors.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.button, style: .continuous)
                    .strokeBorder(Tokens.Colors.borderSubtle, lineWidth: 1)
            )
    }
}

private extension View {
    func loginFieldStyle() -> some View {
        modifier(LoginFieldStyle())
    }
}

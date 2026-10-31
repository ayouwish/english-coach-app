import SwiftUI

/// 登录页。服务器地址、邮箱、密码都必填；演示账号只用于联调。
struct LoginView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var viewModel: AuthViewModel?

    var body: some View {
        Group {
            if let model = viewModel {
                LoginForm(viewModel: model)
            } else {
                ProgressView()
                    .tint(Tokens.Colors.primary)
            }
        }
        .task {
            if viewModel == nil {
                viewModel = AuthViewModel(app: app)
            }
        }
    }
}

private struct LoginForm: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(AppEnvironment.self) private var app
    @Environment(\.capabilities) private var caps
    @FocusState private var focusedField: Field?
    @State private var showsPassword = false

    private enum Field: Hashable {
        case email
        case password
        case baseURL
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s24) {
                header

                if let startupError = app.startupError {
                    ErrorBanner(
                        message: startupError.userMessage(forChild: false),
                        retryTitle: "重试",
                        onRetry: { Task { await app.retryRestore() } }
                    )
                }

                credentialsCard
                serverCard
                demoSection
                footer
            }
            .padding(.horizontal, Tokens.Spacing.s16)
            .padding(.vertical, Tokens.Spacing.s32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if newValue != nil {
                focusedField = .password
            }
        }
    }

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

            Text("English Coach")
                .font(AppFont.display(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)

            Text("和家人一起，把英语说出来")
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            fieldLabel("邮箱")
            TextField("you@example.com", text: $viewModel.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit { focusedField = .password }
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
                .focused($focusedField, equals: .password)
                .onSubmit { submit() }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showsPassword.toggle()
                } label: {
                    Image(systemName: showsPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(showsPassword ? "隐藏密码" : "显示密码")
            }
            .loginFieldStyle()

            AppButton(
                title: "登录",
                icon: "arrow.right.circle.fill",
                isLoading: viewModel.isSubmitting,
                isEnabled: viewModel.isFormValid,
                action: submit
            )
            .padding(.top, Tokens.Spacing.s4)

            if let errorMessage = viewModel.errorMessage {
                InlineErrorView(
                    message: errorMessage,
                    retryTitle: viewModel.errorCanRetry ? "重试" : nil,
                    onRetry: viewModel.errorCanRetry ? { submit() } : nil
                )
            }
        }
        .cardStyle()
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            fieldLabel("服务器地址")
            TextField("https://english.dreamsearch.top/api", text: $viewModel.baseURLText)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focusedField, equals: .baseURL)
                .onSubmit { focusedField = nil }
                .loginFieldStyle()

            Text("只填主机名也可以，会自动补 /api；必须和手机在同一网络。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)

            if viewModel.usesInsecureBaseURL {
                Text("当前是 HTTP：登录凭据会明文传输，仅限局域网排障使用。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.warning)
            }

            HStack {
                Button {
                    Task { await viewModel.testConnection() }
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
                .disabled(viewModel.isTestingConnection)

                Spacer()

                if let message = viewModel.connectionMessage {
                    Text(message)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(viewModel.connectionSucceeded == true ? Tokens.Colors.successText : Tokens.Colors.warning)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .cardStyle()
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("演示账号")
                .font(AppFont.footnote(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
            Text("联调快捷填充（会同时填入种子密码）。正式使用时请改为 NAS 上的真实账号。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)

            Menu {
                ForEach(AuthViewModel.DemoAccount.allCases) { account in
                    Button(account.title) {
                        viewModel.useDemoAccount(account)
                    }
                }
            } label: {
                HStack(spacing: Tokens.Spacing.s8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text("填入演示账号")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .font(AppFont.footnote(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.primary)
                .padding(.horizontal, Tokens.Spacing.s16)
                .frame(maxWidth: .infinity, minHeight: max(44, caps.minTapTarget))
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.button, style: .continuous)
                        .fill(Tokens.Colors.surfaceMuted)
                )
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("关于录音")
                .font(AppFont.caption(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
            Text("录音会上传到家里的学习服务器，并转发给云端语音服务用于识别与发音评分，会离开家庭网络。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.footnote(caps).weight(.semibold))
            .foregroundStyle(Tokens.Colors.textSecondary)
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.login() }
    }
}

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

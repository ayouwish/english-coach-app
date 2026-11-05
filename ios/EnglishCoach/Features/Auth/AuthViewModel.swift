import Foundation
import Observation

/// 登录页状态（契约 §3.15.1：`LoginView(session:config:testConnection:)`）。
///
/// 职责边界：
/// - 只负责表单、内联错误、测试连通、记住登录预填；
/// - 真正的登录/持久化全部交给 `SessionStore.signIn(baseURLText:email:password:remember:)`，
///   成功后 `session.phase` 变 `.signedIn`，由 AppRoot 切主界面（本 VM 不做导航）。
@MainActor
@Observable
final class AuthViewModel {
    /// 测试连通结果。
    enum ConnectionState: Equatable {
        case idle
        case testing
        case succeeded(HealthSummary)
        case failed(String)
    }

    /// `/health` 的精简展示（db / voice 两项勾叉，见 screens.md §1.4）。
    struct HealthSummary: Equatable {
        let dbOK: Bool?
        let voiceReachable: Bool?
        let text: String
    }

    let session: SessionStore
    let config: AppConfig
    let testConnection: @MainActor (String) async throws -> HealthDTO

    /// 首次安装时给一个可用的默认服务器地址（用户只填域名也可以，normalize 会补 `/api`）。
    static let defaultServerText = "https://english.dreamsearch.top/api"

    var email = ""
    var password = ""
    var baseURLText = ""
    /// “记住登录”默认**关**（契约 §3.9：记住密码是显式选择，避免共用设备泄露）。
    var rememberPassword = false

    private(set) var isSubmitting = false
    private(set) var isTestingConnection = false
    private(set) var error: UIMessage?
    private(set) var connection: ConnectionState = .idle
    private(set) var storageDegraded = false
    private(set) var prefilledRemembered = false
    private(set) var didPrepare = false

    init(
        session: SessionStore,
        config: AppConfig,
        testConnection: @escaping @MainActor (String) async throws -> HealthDTO
    ) {
        self.session = session
        self.config = config
        self.testConnection = testConnection
    }

    // MARK: - 派生状态

    var canSubmit: Bool {
        !isSubmitting
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var usesInsecureHTTP: Bool {
        AppConfig.normalize(baseURLText)?.scheme?.lowercased() == "http"
    }

    /// 冷启动/恢复会话失败的错误（只展示网络类，`.unauthorized` 由 AppRoot 弹层处理）。
    var startupError: APIError? {
        session.startupError
    }

    var showsStartupBanner: Bool {
        guard let error = session.startupError else { return false }
        return ErrorMapper.isNetwork(error) || !error.isUnauthorized
    }

    var startupBannerMessage: String {
        guard let error = session.startupError else { return "" }
        return ErrorMapper.message(for: error, isChild: false).body
            ?? ErrorMapper.message(for: error, isChild: false).title
    }

    // MARK: - 生命周期

    /// 一次性预填：服务器地址、记住的邮箱/密码（若曾勾选且未被“主动退出”抑制）。
    func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true

        let savedText = config.baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURLText = savedText.isEmpty ? Self.defaultServerText : savedText
        }

        storageDegraded = await session.credentials.isDegraded()
        let suppressed = await session.consumeAutoLoginSuppressed()
        if let saved = await session.rememberedLogin() {
            email = saved.email
            rememberPassword = true
            prefilledRemembered = true
            // 主动退出登录后不预填密码（避免“退出→立刻又登进去”）。
            if !suppressed {
                password = saved.password
            }
        }
    }

    // MARK: - 表单动作

    func fillDemo(_ account: AppConfig.DemoAccount) {
        email = account.email
        password = ""
        error = nil
    }

    func setRememberPassword(_ value: Bool) {
        rememberPassword = value
        guard !value else { return }
        prefilledRemembered = false
        Task { await session.clearRememberedLogin() }
    }

    func login() async {
        guard !isSubmitting else { return }
        error = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            error = loginError("请输入邮箱和密码")
            return
        }
        guard AppConfig.normalize(baseURLText) != nil else {
            error = ErrorMapper.message(for: APIError.invalidBaseURL, isChild: false)
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await session.signIn(
                baseURLText: baseURLText,
                email: trimmedEmail,
                password: password,
                remember: rememberPassword
            )
            storageDegraded = await session.credentials.isDegraded()
        } catch let apiError as APIError {
            error = loginMessage(for: apiError)
        } catch {
            error = ErrorMapper.message(for: error, isChild: false)
        }
    }

    func testServer() async {
        guard !isTestingConnection else { return }
        isTestingConnection = true
        connection = .testing
        defer { isTestingConnection = false }
        do {
            let health = try await testConnection(baseURLText)
            connection = .succeeded(Self.summarize(health))
        } catch let apiError as APIError {
            connection = .failed(ErrorMapper.message(for: apiError, isChild: false).body
                ?? ErrorMapper.message(for: apiError, isChild: false).title)
        } catch {
            connection = .failed("连不上服务器，请检查地址和网络")
        }
    }

    func clearError() {
        error = nil
    }

    // MARK: - 私有

    private func loginError(_ text: String) -> UIMessage {
        UIMessage(
            title: "登录失败",
            body: text,
            actionTitle: nil,
            action: UIMessage.Action.none,
            isRetryable: false,
            diagnosticID: nil
        )
    }

    /// 登录失败语义：401/401+`bad_request` 是“邮箱或密码不正确”，不能显示成“登录已过期”。
    private func loginMessage(for error: APIError) -> UIMessage {
        switch error {
        case .unauthorized:
            return loginError("邮箱或密码不正确，请再检查一下")
        case .server(let code, let message, let status):
            if status == 401 || code == .badRequest || code == .unauthorized {
                let serverText = message ?? ""
                return loginError(serverText.isEmpty ? "邮箱或密码不正确，请再检查一下" : serverText)
            }
            return ErrorMapper.message(for: error, isChild: false)
        default:
            return ErrorMapper.message(for: error, isChild: false)
        }
    }

    private static func summarize(_ health: HealthDTO) -> HealthSummary {
        let dbOK = health.db?.ok
        let voiceReachable = health.voice?.reachable
        if voiceReachable == false {
            return HealthSummary(
                dbOK: dbOK,
                voiceReachable: voiceReachable,
                text: "服务器已连接，但语音服务未就绪（录音会先保存，可稍后重试评测）"
            )
        }
        if dbOK == false {
            return HealthSummary(
                dbOK: dbOK,
                voiceReachable: voiceReachable,
                text: "服务器已连接，但数据库异常"
            )
        }
        return HealthSummary(dbOK: dbOK, voiceReachable: voiceReachable, text: "家庭 NAS 已连接")
    }
}

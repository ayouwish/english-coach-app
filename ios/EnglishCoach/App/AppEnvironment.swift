import Foundation
import Observation

/// 组合根 + 全局会话状态。
///
/// 依赖方向：App → Features → Core。这里只负责把 Core 的能力装配起来，
/// 并把登录/登出/会话过期收敛成 `phase`，View 不直接碰 token。
@MainActor
@Observable
final class AppEnvironment {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    let config: AppConfig
    private let tokens: TokenStore
    private var transport: APITransport?

    private(set) var phase: Phase = .launching
    private(set) var currentUser: UserProfile?
    /// 冷启动/恢复会话失败时给登录页展示的横幅；网络错误时 token 会保留。
    private(set) var startupError: APIError?
    private var didAttemptRestore = false

    init() {
        self.config = AppConfig()
        self.tokens = TokenStore()
    }

    init(config: AppConfig, tokens: TokenStore) {
        self.config = config
        self.tokens = tokens
    }

    var capabilities: RoleCapabilities {
        RoleCapabilities.make(isChild: currentUser?.isChild ?? false)
    }

    var displayName: String {
        currentUser?.displayName ?? ""
    }

    var demoBaseURL: String {
        "https://english.dreamsearch.top/api"
    }

    // MARK: - 会话恢复

    func restoreIfNeeded() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        await restore()
    }

    /// 登录页“重试”：网络恢复后不需要重新输密码。
    func retryRestore() async {
        phase = .launching
        didAttemptRestore = true
        await restore()
    }

    private func restore() async {
        startupError = nil

        guard let baseURL = config.baseURL else {
            phase = .signedOut
            return
        }
        guard let stored = await tokens.load(),
              !stored.accessToken.isEmpty || !stored.refreshToken.isEmpty
        else {
            phase = .signedOut
            return
        }

        // token 与服务器绑定：地址被改过就不允许拿旧 token 去新服务器。
        if let boundHost = stored.baseURL,
           let boundURL = URL(string: boundHost),
           boundURL.absoluteString != baseURL.absoluteString {
            await tokens.clear()
            phase = .signedOut
            return
        }

        let transport = makeTransport(baseURL: baseURL)
        self.transport = transport
        let auth = AuthAPI(transport: transport)

        do {
            if !stored.refreshToken.isEmpty {
                // 主动刷新而不是等 /auth/me 的 401：后端 `/auth/me` 在 Bearer 失效时
                // 返回 200 `{user:null}`，不会触发网络层的 401 单飞刷新（实测后端行为）。
                let response = try await auth.refresh(refreshToken: stored.refreshToken)
                guard let access = response.accessToken else {
                    throw APIError.unauthorized
                }
                let pair = StoredTokens(
                    accessToken: access,
                    refreshToken: response.refreshToken ?? stored.refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600)),
                    baseURL: baseURL.absoluteString
                )
                try await tokens.save(pair)
            }

            let user = try await auth.me()
            currentUser = user
            startupError = nil
            phase = .signedIn
        } catch let error as APIError {
            if error.isUnauthorized || error == .forbidden {
                await tokens.clear()
            }
            // 网络错误：保留 token，只展示“连不上服务器”，恢复后可重试。
            startupError = error
            phase = .signedOut
        } catch {
            startupError = .transport(.unknown)
            phase = .signedOut
        }
    }

    // MARK: - 登录 / 退出

    func signIn(baseURLText: String, email: String, password: String) async throws {
        guard let baseURL = AppConfig.normalize(baseURLText) else {
            throw APIError.invalidBaseURL
        }

        // 手动登录是明确的账号切换：先清掉旧凭据，避免登录失败后旧 refresh 继续自动登录。
        await tokens.clear()
        config.updateBaseURL(baseURL.absoluteString)

        let transport = makeTransport(baseURL: baseURL)
        let auth = AuthAPI(transport: transport)
        let response = try await auth.token(email: email, password: password)

        guard let access = response.accessToken,
              let refresh = response.refreshToken
        else {
            throw APIError.decoding(path: "auth/token")
        }
        let pair = StoredTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600)),
            baseURL: baseURL.absoluteString
        )
        try await tokens.save(pair)

        self.transport = transport
        if let user = response.user {
            currentUser = user
        } else {
            currentUser = try await auth.me()
        }
        startupError = nil
        phase = .signedIn
    }

    /// 主动退出：先吊销 refresh（204 视为成功），再清本地。
    /// 离线时吊销失败仍然清本地——服务端 refresh 可能继续有效，属已知限制（ADR-0003 §6）。
    func signOut() async {
        if let transport, let stored = await tokens.load(), !stored.refreshToken.isEmpty {
            try? await AuthAPI(transport: transport).revoke(refreshToken: stored.refreshToken)
        }
        await tokens.clear()
        currentUser = nil
        self.transport = nil
        startupError = nil
        phase = .signedOut
    }

    /// 业务接口返回 401 且刷新失败：清本地并回登录页。
    func handleSessionExpired() async {
        await tokens.clear()
        currentUser = nil
        transport = nil
        startupError = .unauthorized
        phase = .signedOut
    }

    // MARK: - API 访问

    func sentenceAPI() throws -> SentenceAPI {
        SentenceAPI(transport: try requireTransport())
    }

    func attemptAPI() throws -> AttemptAPI {
        AttemptAPI(transport: try requireTransport())
    }

    func ttsAPI() throws -> TTSAPI {
        TTSAPI(transport: try requireTransport())
    }

    /// 登录页“测试连接”：用填写的地址发一次 `/health`（不需要鉴权）。
    func testConnection(baseURLText: String) async throws {
        guard let baseURL = AppConfig.normalize(baseURLText) else {
            throw APIError.invalidBaseURL
        }
        let transport = makeTransport(baseURL: baseURL)
        try await HealthAPI(transport: transport).ping()
    }

    private func requireTransport() throws -> APITransport {
        guard let transport = self.transport else {
            throw APIError.unauthorized
        }
        return transport
    }

    private func makeTransport(baseURL: URL) -> APITransport {
        let client = HTTPClient()
        let refresher = TokenRefresher(client: client, store: tokens, baseURL: baseURL)
        return APITransport(baseURL: baseURL, client: client, tokens: tokens, refresher: refresher)
    }
}

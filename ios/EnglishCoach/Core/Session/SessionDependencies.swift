import Foundation

/// `SessionStore` 的依赖边界（由 App 层在组合根装配）。
///
/// 设计约束（契约 §3.9）：
/// - `SessionStore` **不持有 `URLSession`**，也不在内部 new Service，只通过本结构拿能力；
/// - Service 按 baseURL 惰性构造（换服务器是极少数操作，`SessionStore` 会缓存当前 URL 的一套）；
/// - `config` 是 `@MainActor @Observable` 的 `AppConfig`（全局 actor 隔离 ⇒ 隐式 `Sendable`），
///   读 baseURL / 写 baseURL 都只在主线程发生（`SessionStore` 本身是 `@MainActor`）。
struct SessionDependencies: Sendable {
    /// baseURL 的唯一事实来源（UserDefaults + normalize）。
    let config: AppConfig
    /// token 存取（Keychain，actor；契约 §3.9 的 `TokenStore`）。
    let tokens: any TokenStoring
    /// “记住登录”的凭据存取（默认关，Keychain）。
    let credentials: CredentialStore
    /// 按 baseURL 构造 `AuthService`（`token` / `refresh` / `me` / `revoke`）。
    let makeAuthService: @Sendable (URL) -> AuthService
    /// 按 baseURL 构造 `AccountService`（`reloadUser()` 用它拉 `/settings` 同步偏好）。
    /// 为 nil 时 `reloadUser()` 只刷新 `/auth/me`。
    let makeAccountService: (@Sendable (URL) -> AccountService)?
    /// 退出 / 换账号时清用户级缓存（由 Storage 层实现；Core/Session 不直接碰文件）。
    let clearUserScopedCache: @Sendable () async -> Void

    init(
        config: AppConfig,
        tokens: any TokenStoring,
        credentials: CredentialStore,
        makeAuthService: @escaping @Sendable (URL) -> AuthService,
        makeAccountService: (@Sendable (URL) -> AccountService)? = nil,
        clearUserScopedCache: @escaping @Sendable () async -> Void = {}
    ) {
        self.config = config
        self.tokens = tokens
        self.credentials = credentials
        self.makeAuthService = makeAuthService
        self.makeAccountService = makeAccountService
        self.clearUserScopedCache = clearUserScopedCache
    }

    /// 默认装配（供 `AppEnvironment` 一行接入）：
    /// auth / account 共用一个 `HTTPClient`（即一个 `URLSession`），token 走注入的 Keychain store。
    ///
    /// 注意：如果 `AppEnvironment` 已经为业务 Service 建了 `APITransport`，请改用上面的
    /// `init(...)` 把自己的工厂闭包传进来（`makeAuthService: { AuthService(transport: sharedTransport($0)) }`），
    /// 避免出现第二个 `URLSession`（`architecture.md` §4.2 要求只有一个实例）。
    static func live(
        config: AppConfig,
        tokens: any TokenStoring = TokenStore(),
        credentials: CredentialStore = CredentialStore(),
        clearUserScopedCache: @escaping @Sendable () async -> Void = {}
    ) -> SessionDependencies {
        let client = HTTPClient()
        let makeAuth: @Sendable (URL) -> AuthService = { url in
            let transport = Self.makeTransport(baseURL: url, client: client, tokens: tokens)
            return AuthService(transport: transport)
        }
        let makeAccount: @Sendable (URL) -> AccountService = { url in
            let transport = Self.makeTransport(baseURL: url, client: client, tokens: tokens)
            return AccountService(transport: transport)
        }
        return SessionDependencies(
            config: config,
            tokens: tokens,
            credentials: credentials,
            makeAuthService: makeAuth,
            makeAccountService: makeAccount,
            clearUserScopedCache: clearUserScopedCache
        )
    }

    private static func makeTransport(baseURL: URL, client: HTTPClient, tokens: any TokenStoring) -> APITransport {
        let refresher = TokenRefresher(client: client, store: tokens, baseURL: baseURL)
        return APITransport(baseURL: baseURL, client: client, tokens: tokens, refresher: refresher)
    }
}

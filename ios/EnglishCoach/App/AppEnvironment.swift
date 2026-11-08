import Foundation
import Observation
import OSLog

/// 组合根（契约 §3.15）：只负责装配依赖与全局状态，**不承载页面状态**。
///
/// 关键约束：
/// - 全 App 只有**一个 `URLSession`**（本类持有的 `HTTPClient`），
///   `SessionDependencies` 与 `AppServices` 的 8 个 Service 全部复用它（`architecture.md` §4.2）；
/// - `SessionStore` 是唯一会话事实来源；本类只观察 `phase`，在登录后装配 `AppServices`；
/// - `Features/**` 不得引用本类型：页面只通过构造参数拿 `AppServices`/`AudioCoordinator`，
///   通过 Environment 拿 `SessionStore`/`AppRouter`/`RoleCapabilities`。
@MainActor
@Observable
final class AppEnvironment {
    let config: AppConfig
    let session: SessionStore
    let audio: AudioCoordinator
    let router: AppRouter
    /// 登录后才可用（与 baseURL 绑定）；未登录 / 换服务器时为 nil。
    private(set) var services: AppServices?

    @ObservationIgnored private let tokens: TokenStore
    @ObservationIgnored private let httpClient: HTTPClient
    @ObservationIgnored private let logger = Logger(subsystem: "top.dreamsearch.english.coach", category: "app")
    @ObservationIgnored private var servicesBaseURL: URL?
    @ObservationIgnored private var didBootstrap = false

    init(config: AppConfig = AppConfig()) {
        let tokens = TokenStore()
        let client = HTTPClient()
        let credentials = CredentialStore()
        let audio = AudioCoordinator()
        let router = AppRouter()

        self.config = config
        self.tokens = tokens
        self.httpClient = client
        self.audio = audio
        self.router = router

        // 认证/账号 Service 与业务 Service 共用同一个 HTTPClient（即同一个 URLSession）。
        let makeTransport: @Sendable (URL) -> APITransport = { baseURL in
            makeAPITransport(baseURL: baseURL, client: client, tokens: tokens)
        }
        let dependencies = SessionDependencies(
            config: config,
            tokens: tokens,
            credentials: credentials,
            makeAuthService: { baseURL in
                AuthService(transport: makeTransport(baseURL))
            },
            makeAccountService: { baseURL in
                AccountService(transport: makeTransport(baseURL))
            },
            clearUserScopedCache: {
                CacheJanitor.clearUserScoped()
            }
        )
        self.session = SessionStore(dependencies: dependencies)
    }

    // MARK: - 启动

    /// AppRoot `.task` 调用：清缓存 → 恢复会话（幂等，只真正执行一次）。
    ///
    /// 启动阶段**不**并发请求 `/health`：`session.restore()` 内部已有 refresh + `/auth/me`
    /// 两个串行网络往返，健康探活交给 `syncServicesWithSession()` 在会话确定后执行，
    /// 避免冷启动白屏时间叠加。
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        CacheJanitor.cleanupOnBoot()
        await session.restore()
    }

    /// AppRoot 在 `session.phase` 变化时调用：
    /// - 已登录 → 按当前 baseURL 装配（或复用）`AppServices`，并探活 voice 更新降级横幅；
    /// - 未登录 → 释放 Service、清空路由栈（避免退出后仍停在家长页）。
    func syncServicesWithSession() async {
        guard session.isSignedIn, let baseURL = config.baseURL else {
            if services != nil || !router.path.isEmpty {
                services = nil
                servicesBaseURL = nil
                router.reset(to: [])
            }
            return
        }
        let installed = configure(baseURL: baseURL)
        await refreshVoiceHealth(using: installed.practice)
    }

    // MARK: - 服务装配

    /// 登录成功后按 baseURL 装配 Service；同一 baseURL 幂等复用，换服务器则重建。
    @discardableResult
    func configure(baseURL: URL) -> AppServices {
        if let existing = services, servicesBaseURL == baseURL {
            return existing
        }
        let transport = makeAPITransport(baseURL: baseURL, client: httpClient, tokens: tokens)
        let built = AppServices(
            practice: PracticeService(transport: transport),
            flow: FlowService(transport: transport),
            chat: ChatService(transport: transport),
            story: StoryService(transport: transport),
            stats: StatsService(transport: transport),
            account: AccountService(transport: transport),
            dictionary: DictionaryService(transport: transport),
            media: MediaService(transport: transport)
        )
        services = built
        servicesBaseURL = baseURL
        router.reset(to: [])
        logger.notice("services configured")
        return built
    }

    // MARK: - 登录页“测试连接”

    /// 用共享 URLSession 构造一次性 `PracticeService` 调 `/health`（不需要 Bearer）。
    ///
    /// 不写任何状态：未登录不装配业务 Service；非法地址抛 `APIError.invalidBaseURL`，
    /// 网络/服务端失败抛 `APIError`，由登录页用 `ErrorMapper` 出文案。
    func testConnection(baseURLText: String) async throws -> HealthDTO {
        guard let baseURL = AppConfig.normalize(baseURLText) else {
            throw APIError.invalidBaseURL
        }
        let transport = makeAPITransport(baseURL: baseURL, client: httpClient, tokens: tokens)
        return try await PracticeService(transport: transport).health()
    }

    // MARK: - voice 降级

    /// `/health.voice.reachable == false` 时置全局琥珀条；网络失败**不改变**当前判定
    /// （避免把一次抖动误判成语音服务故障）。
    private func refreshVoiceHealth(using practice: PracticeService) async {
        do {
            let health = try await practice.health()
            if let voice = health.voice, voice.reachable == false {
                session.markDegraded(true, reason: nil)
            } else {
                session.markDegraded(false, reason: nil)
            }
        } catch {
            logger.notice("health probe failed")
        }
    }
}

// MARK: - 共享传输层

/// 构造与 baseURL 绑定的 `APITransport`：全 App 复用同一个 `HTTPClient`（URLSession）；
/// 每个 baseURL 一个 `TokenRefresher`（单飞刷新，禁止跨服务器复用 token）。
private func makeAPITransport(
    baseURL: URL,
    client: HTTPClient,
    tokens: any TokenStoring
) -> APITransport {
    let refresher = TokenRefresher(client: client, store: tokens, baseURL: baseURL)
    return APITransport(baseURL: baseURL, client: client, tokens: tokens, refresher: refresher)
}

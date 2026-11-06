import Foundation
import Observation
import OSLog

/// 全局会话状态（契约 §3.9）：启动恢复 / 登录 / 登出 / 用量回填 / voice 降级横幅。
///
/// 约定：
/// - **唯一会话事实来源**：页面只读 `phase` / `user` / `usage` / `capabilities`，不直接碰 token；
/// - 不持有 `URLSession`，所有网络动作经注入的 `SessionDependencies` 调用 `AuthService` / `AccountService`；
/// - 冷启动语义承接 M0 `AppEnvironment.restore()`（见 `ios/docs/architecture.md` §2.1、ADR-0003）：
///   `/auth/me` 失效返回 200 + `user: null` ⇒ 视为未认证并清 token；
///   网络错误 ⇒ **保留 token**，只把错误放进 `startupError` 供登录页横幅展示；
///   换 baseURL ⇒ 先清旧 token（token 与服务器绑定）；refresh 被服务端拒绝才清 token。
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .launching
    private(set) var user: UserProfile?
    private(set) var usage: UsageDTO?
    /// 冷启动 / 恢复会话失败时给登录页展示的横幅来源（网络错误时 token 仍保留）。
    private(set) var startupError: APIError?
    /// 语音服务不可达时的全局横幅（`RootTabView` 顶部琥珀条）。
    private(set) var degradedReason: String?

    /// 账号偏好缓存（tts_voice / tts_rate / show_word_ipa / story_sentences / auto_illustrate）。
    let prefs = AccountPrefs()
    /// “记住登录”凭据（登录页预填 / 自动登录用；默认关，只有勾选才写入）。
    let credentials: CredentialStore

    private let deps: SessionDependencies
    private let logger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "session")

    private var didAttemptRestore = false
    private var restoreTask: Task<Void, Never>?
    private var cachedServices: CachedServices?

    /// 当前 baseURL 的一套 Service（换服务器才会重建）。
    private struct CachedServices {
        let baseURL: URL
        let auth: AuthService
        let account: AccountService?
    }

    init(dependencies: SessionDependencies) {
        self.deps = dependencies
        self.credentials = dependencies.credentials
    }

    // MARK: - 派生状态

    var capabilities: RoleCapabilities {
        RoleCapabilities.make(isChild: isChild)
    }

    var isChild: Bool {
        user?.isChild ?? false
    }

    var isSignedIn: Bool {
        phase == .signedIn
    }

    /// 当前服务器地址（登录页预填 / “检查服务器”入口用）。
    var baseURL: URL? {
        deps.config.baseURL
    }

    // MARK: - 启动恢复

    /// AppRoot `.task` 调用：每个进程只真正执行一次。
    func restore() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        await runRestore()
    }

    /// 登录页“重试”：网络恢复后不需要重新输密码。
    func retryRestore() async {
        didAttemptRestore = true
        phase = .launching
        await runRestore()
    }

    /// 单飞：并发调用（`.task` + 场景回到前台）只发一轮请求。
    private func runRestore() async {
        if let inFlight = restoreTask {
            await inFlight.value
            return
        }
        let task = Task { @MainActor in await self.restoreNow() }
        restoreTask = task
        await task.value
        restoreTask = nil
    }

    private func restoreNow() async {
        startupError = nil

        guard let baseURL = deps.config.baseURL else {
            phase = .signedOut
            return
        }
        await deps.credentials.updateBaseURL(baseURL)

        guard let stored = await deps.tokens.load(),
              !stored.accessToken.isEmpty || !stored.refreshToken.isEmpty
        else {
            phase = .signedOut
            return
        }

        // token 与服务器绑定：地址被改过就不允许拿旧 token 去新服务器。
        if let bound = stored.baseURL,
           let boundURL = URL(string: bound),
           boundURL.absoluteString != baseURL.absoluteString {
            await deps.tokens.clear()
            phase = .signedOut
            return
        }

        let resolved = services(for: baseURL)
        do {
            if !stored.refreshToken.isEmpty {
                // 主动刷新而不是等 `/auth/me` 的 401：后端对失效 Bearer 返回 200 `{user:null}`，
                // 不会触发网络层的 401 单飞刷新（与 M0 `AppEnvironment.restore()` 一致，待运行时复核）。
                let refreshed = try await resolved.auth.refresh(refreshToken: stored.refreshToken)
                guard let access = refreshed.accessToken, !access.isEmpty else {
                    throw APIError.unauthorized
                }
                let pair = StoredTokens(
                    accessToken: access,
                    refreshToken: refreshed.refreshToken ?? stored.refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn ?? 3600)),
                    baseURL: baseURL.absoluteString
                )
                try await deps.tokens.save(pair)
            }

            let me = try await resolved.auth.me()
            guard let dto = me.user else {
                // 兼容“无效 Bearer 返回 200 + user:null”的旧行为：视为未认证。
                await deps.tokens.clear()
                resetSessionState()
                logger.notice("restore: /auth/me returned no user -> signedOut")
                return
            }
            applyUser(dto, usage: me.usage)
            startupError = nil
            phase = .signedIn
            logger.notice("restore ok user=\(dto.id, privacy: .public)")
        } catch let error as APIError {
            switch error {
            case .unauthorized, .forbidden:
                // 服务端明确拒绝 refresh / me（过期、被吊销、已被轮换）：清 token 回登录页。
                await deps.tokens.clear()
                resetSessionState()
            default:
                // 网络 / 服务端 / 解码错误：保留 token，按“启动失败可重试”处理，
                // 避免 NAS 短暂不可达就把全家登出。
                startupError = error
                phase = .signedOut
            }
            logger.notice("restore failed: \(String(describing: error), privacy: .public)")
        } catch {
            startupError = .transport(.unknown)
            phase = .signedOut
            logger.notice("restore failed: unknown error")
        }
    }

    // MARK: - 登录 / 退出

    func signIn(baseURLText: String, email: String, password: String, remember: Bool) async throws {
        guard let baseURL = AppConfig.normalize(baseURLText) else {
            throw APIError.invalidBaseURL
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        startupError = nil

        // 切换服务器先清旧凭据：token 与服务器绑定，旧 token 不能拿去打新服务器。
        if deps.config.baseURL?.absoluteString != baseURL.absoluteString {
            await deps.tokens.clear()
        }
        deps.config.updateBaseURL(baseURL.absoluteString)
        await deps.credentials.updateBaseURL(baseURL)

        let resolved = services(for: baseURL)
        let response = try await resolved.auth.token(email: trimmedEmail, password: password)
        guard let access = response.accessToken, let refresh = response.refreshToken else {
            throw APIError.decoding(path: "auth/token")
        }
        let pair = StoredTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600)),
            baseURL: baseURL.absoluteString
        )
        try await deps.tokens.save(pair)
        // 新会话开始：旧账号的偏好缓存先失效，等 `/settings` 回来再填。
        prefs.reset()

        do {
            let me = try await resolved.auth.me()
            guard let dto = me.user else {
                throw APIError.unauthorized
            }
            applyUser(dto, usage: me.usage)
        } catch let error as APIError {
            if error.isUnauthorized || error == .forbidden {
                await deps.tokens.clear()
                throw error
            }
            // token 已落盘；`/auth/me` 只是校正角色/等级/用量，失败不阻塞进入首页。
            if let dto = response.user {
                applyUser(dto, usage: nil)
            } else {
                throw error
            }
        }

        if remember {
            await deps.credentials.save(email: trimmedEmail, password: password, baseURL: baseURL)
        } else {
            await deps.credentials.clear()
        }

        // 换账号 / 重登先清用户级缓存，避免共用设备串号（architecture.md §7.2）。
        await deps.clearUserScopedCache()
        if let account = resolved.account {
            await loadPreferences(account)
        }

        startupError = nil
        phase = .signedIn
        logger.notice("signIn ok user=\(self.user?.id ?? "", privacy: .public)")
    }

    /// 主动退出：先吊销 refresh（失败也继续），再清 token + 用户级缓存。
    /// 离线时无法吊销，服务端 refresh 仍可能有效，属已知限制（ADR-0003 §6）。
    func signOut() async {
        await deps.credentials.markLoggedOut()
        if let baseURL = deps.config.baseURL {
            let resolved = services(for: baseURL)
            if let stored = await deps.tokens.load(), !stored.refreshToken.isEmpty {
                try? await resolved.auth.revoke(refreshToken: stored.refreshToken)
            }
        }
        await deps.tokens.clear()
        await deps.clearUserScopedCache()
        resetSessionState()
        logger.notice("signOut")
    }

    /// 业务接口返回 401 且刷新失败：清本地并回登录页（页面看到 `startupError == .unauthorized` 弹“重新登录”）。
    func handleSessionExpired() async {
        await deps.tokens.clear()
        await deps.clearUserScopedCache()
        resetSessionState()
        startupError = .unauthorized
        logger.notice("session expired -> signedOut")
    }

    // MARK: - 资料 / 用量 / 降级

    /// 重新 GET `/auth/me`（+ `/settings` 同步偏好）。失败静默降级，不阻塞页面。
    func reloadUser() async {
        guard let baseURL = deps.config.baseURL else { return }
        let resolved = services(for: baseURL)
        do {
            let me = try await resolved.auth.me()
            guard let dto = me.user else {
                await handleSessionExpired()
                return
            }
            applyUser(dto, usage: me.usage)
            if let account = resolved.account {
                await loadPreferences(account)
            }
        } catch let error as APIError {
            if error.isUnauthorized || error == .forbidden {
                await handleSessionExpired()
            } else {
                logger.notice("reloadUser failed: \(String(describing: error), privacy: .public)")
            }
        } catch {
            logger.notice("reloadUser failed: unknown error")
        }
    }

    /// 每次业务响应回填今日用量（422/429 依赖它展示剩余时长）。
    func apply(usage: UsageDTO) {
        self.usage = usage
    }

    func markDegraded(_ on: Bool, reason: String?) {
        if on {
            degradedReason = reason ?? defaultDegradedReason()
        } else {
            degradedReason = nil
        }
    }

    // MARK: - 记住登录（登录页用）

    /// 读取“记住登录”的邮箱 + 密码（与当前 baseURL 绑定；没有则 nil）。
    func rememberedLogin() async -> (email: String, password: String)? {
        await deps.credentials.updateBaseURL(deps.config.baseURL)
        return await deps.credentials.load()
    }

    /// 用户手动关闭“记住登录”。
    func clearRememberedLogin() async {
        await deps.credentials.clear()
    }

    /// 主动退出后抑制本次进程内的自动登录（读一次即复位）。
    func consumeAutoLoginSuppressed() async -> Bool {
        await deps.credentials.consumeAutoLoginSuppressed()
    }

    // MARK: - 私有

    private func services(for baseURL: URL) -> CachedServices {
        if let cached = cachedServices, cached.baseURL == baseURL {
            return cached
        }
        let created = CachedServices(
            baseURL: baseURL,
            auth: deps.makeAuthService(baseURL),
            account: deps.makeAccountService?(baseURL)
        )
        cachedServices = created
        return created
    }

    private func applyUser(_ dto: AccountUserDTO, usage: UsageDTO?) {
        user = UserProfile(dto)
        self.usage = usage
    }

    /// `/settings` 同步账号偏好；失败不阻塞主流程（保留默认值 / 上一次缓存）。
    private func loadPreferences(_ account: AccountService) async {
        do {
            let settings = try await account.settings()
            if let dto = settings.user {
                user = UserProfile(dto)
            }
            if let latest = settings.usage {
                usage = latest
            }
            prefs.apply(
                AccountPrefsSnapshot(
                    ttsVoice: settings.prefs?.ttsVoice ?? "",
                    ttsRate: settings.prefs?.ttsRate ?? "",
                    showWordIpa: settings.prefs?.showWordIpa ?? true,
                    storySentences: settings.user?.storySentences ?? 0,
                    autoIllustrate: settings.user?.autoIllustrate == true
                )
            )
        } catch {
            logger.notice("load preferences failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func resetSessionState() {
        user = nil
        usage = nil
        startupError = nil
        degradedReason = nil
        prefs.reset()
        cachedServices = nil
        phase = .signedOut
    }

    private func defaultDegradedReason() -> String {
        isChild
            ? "现在不能评分，先听一听示范吧"
            : "语音服务暂时不可用；可以先听示范音，或先看文本跟读"
    }
}

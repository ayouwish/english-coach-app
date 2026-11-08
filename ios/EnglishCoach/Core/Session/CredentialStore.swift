import Foundation
import OSLog

/// “记住登录”（邮箱 + 密码）。
///
/// 安全约束（对齐 HOS `core/session/CredentialStore.ets`）：
/// - **默认关**：只有登录页显式勾选“记住登录”才写入；
/// - 只放 Keychain（`KeychainStore`，可访问性 `AfterFirstUnlockThisDeviceOnly`），
///   不写 `UserDefaults`、不落日志、不参与明文降级——写失败就 `isDegraded == true`，页面提示“本机无法安全保存密码”；
/// - 与 baseURL 绑定：换服务器后旧凭据不再可用（token 同样与服务器绑定，见 ADR-0003）；
/// - 退出登录**不清除**已记住的密码（下次仍可一键登录），只标记“本次进程内不再自动登录”；
///   用户手动关闭开关才 `clear()`。
actor CredentialStore {
    /// Keychain account（与 token 共用 service，account 独立）。
    private static let account = "savedLogin"

    private let keychain: KeychainStore
    private let logger = Logger(subsystem: "top.dreamsearch.english.coach", category: "session")

    /// 记录“当前用的是哪台服务器”：save/load 都按它做绑定校验。
    private var boundBaseURL: String?
    /// 主动退出登录后，本次进程内不再自动登录（否则退出 → 登录页 → 立刻又登回去）。
    private var loggedOutThisProcess = false
    private var degraded = false

    init(keychain: KeychainStore = .shared) {
        self.keychain = keychain
    }

    /// 当前服务器地址（由 SessionStore / AppEnvironment 在启动/登录时设置）。
    func updateBaseURL(_ url: URL?) {
        boundBaseURL = url?.absoluteString
    }

    /// 保存“记住登录”。邮箱或密码为空时等价于关闭“记住登录”（清除旧值），与 HOS 一致。
    func save(email: String, password: String) async {
        save(email: email, password: password, baseURLString: boundBaseURL)
    }

    /// 显式指定服务器地址的版本：SessionStore 登录成功后用它保证凭据与服务器绑定。
    func save(email: String, password: String, baseURL: URL?) async {
        save(email: email, password: password, baseURLString: baseURL?.absoluteString)
    }

    /// 读取“记住登录”；不存在 / 解析失败 / 与当前服务器不匹配都返回 nil。
    func load() async -> (email: String, password: String)? {
        load(baseURLString: boundBaseURL)
    }

    func load(baseURL: URL?) async -> (email: String, password: String)? {
        load(baseURLString: baseURL?.absoluteString)
    }

    /// 清除“记住登录”（用户手动关闭开关 / 换账号时调用）。
    func clear() async {
        keychain.delete(Self.account)
        degraded = false
    }

    /// 主动退出登录：保留已记住的密码，但抑制本次进程内的自动登录。
    func markLoggedOut() async {
        loggedOutThisProcess = true
    }

    /// 读取并复位“刚退出登录”标记。
    func consumeAutoLoginSuppressed() async -> Bool {
        let value = loggedOutThisProcess
        loggedOutThisProcess = false
        return value
    }

    /// Keychain 写入是否失败过（true = 本机无法安全保存密码，页面应提示而不是静默丢失）。
    func isDegraded() -> Bool {
        degraded
    }

    // MARK: - actor 内同步实现

    private func save(email: String, password: String, baseURLString: String?) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            keychain.delete(Self.account)
            degraded = false
            return
        }
        let saved = SavedLogin(email: trimmedEmail, password: password, baseURL: baseURLString)
        guard let data = try? JSONEncoder().encode(saved),
              let text = String(data: data, encoding: .utf8)
        else {
            degraded = true
            logger.error("credential encode failed")
            return
        }
        do {
            try keychain.write(text, account: Self.account)
            degraded = false
        } catch {
            // 不降级为明文；页面据此提示“本机无法安全保存密码”。
            degraded = true
            logger.error("credential save failed (keychain)")
        }
    }

    private func load(baseURLString: String?) -> (email: String, password: String)? {
        guard let text = keychain.read(Self.account),
              let data = text.data(using: .utf8),
              let saved = try? JSONDecoder().decode(SavedLogin.self, from: data)
        else {
            return nil
        }
        guard !saved.email.isEmpty, !saved.password.isEmpty else {
            return nil
        }
        // 与服务器绑定：换地址后旧凭据不可用（也不自动填到新服务器上）。
        guard saved.baseURL == baseURLString else {
            return nil
        }
        return (saved.email, saved.password)
    }
}

/// Keychain 里的“记住登录”载荷（不进日志）。
private struct SavedLogin: Codable, Sendable, Equatable {
    let email: String
    let password: String
    let baseURL: String?
}

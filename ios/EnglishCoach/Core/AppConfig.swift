import Foundation
import Observation

/// 应用级配置（当前只有服务器基地址）。
///
/// 基地址由用户在登录页填写，存 `UserDefaults`；**绝不**把 token 放进这里。
/// 后端要求所有接口都在 `…/api` 下，用户通常只需要填到主机名，这里会补 `/api`。
@MainActor
@Observable
final class AppConfig {
    /// 登录页「填入演示账号」用的种子账号。
    ///
    /// 按 `ios/README.md` §0.3：**只填邮箱、不把密码编译进 App**（密码需用户手动输入；
    /// 部署方可能用 `BOOTSTRAP_*` 环境变量覆盖种子账号，因此这里只是演示填充，不保证线上可用）。
    struct DemoAccount: Sendable, Equatable, Identifiable {
        /// 中文标签，例如「爸爸 · 家长 · B1」
        let label: String
        let email: String

        var id: String { email }
    }

    static let baseURLDefaultsKey = "app.baseURL"

    /// 客户端版本号（上报 `app_version` 等用途）。
    ///
    /// 以 Info.plist 的 `CFBundleShortVersionString` 为准（TestFlight / 归档前递增版本号时
    /// 只需改 plist，不会出现「代码里的版本号和实际构建不一致」）；取不到时回退 `0.1.0`。
    static var appVersion: String {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let bundleValue, !bundleValue.isEmpty else { return "0.1.0" }
        return bundleValue
    }

    /// 后端种子账号（`english-coach/web/src/data/accounts.json`）。只用于登录页“填入演示邮箱”。
    static let demoAccounts: [DemoAccount] = [
        DemoAccount(label: "爸爸 · 家长 · B1", email: "dad@example.com"),
        DemoAccount(label: "女儿 · 儿童 · A1", email: "girl@example.com"),
    ]

    private let defaults: UserDefaults
    private(set) var baseURLText: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseURLText = defaults.string(forKey: Self.baseURLDefaultsKey) ?? ""
    }

    var baseURL: URL? {
        Self.normalize(baseURLText)
    }

    var isConfigured: Bool {
        baseURL != nil
    }

    /// 明文 HTTP 只允许 Debug 排障，UI 需要显式提示（token 会明文传输）。
    var usesInsecureHTTP: Bool {
        baseURL?.scheme?.lowercased() == "http"
    }

    func updateBaseURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURLText = trimmed
        defaults.set(trimmed, forKey: Self.baseURLDefaultsKey)
    }

    nonisolated static func normalize(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 用户通常只记得域名（`english.dreamsearch.top`）甚至 IP:端口，不带 scheme。
        // 没写 scheme 时补 `https://`（ATS 默认只允许 https；明文 http 只用于 Debug 排障且会提示）。
        // 注意不能靠 URLComponents 的 scheme 判断——`192.168.1.5:3000` 会被解析成 scheme `192.168.1.5`。
        if !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }

        components.scheme = scheme
        var path = components.path
        // 用户只填 https://host 时补上后端前缀；填写了其它路径则原样尊重。
        if path.isEmpty || path == "/" {
            path = "/api"
        }
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

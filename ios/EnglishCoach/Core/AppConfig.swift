import Foundation
import Observation

/// 应用级配置（当前只有服务器基地址）。
///
/// 基地址由用户在登录页填写，存 `UserDefaults`；**绝不**把 token 放进这里。
/// 后端要求所有接口都在 `…/api` 下，用户通常只需要填到主机名，这里会补 `/api`。
@MainActor
@Observable
final class AppConfig {
    static let baseURLDefaultsKey = "app.baseURL"

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
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
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

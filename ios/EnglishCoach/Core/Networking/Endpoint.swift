import Foundation

// MARK: - 请求原语
//
// 本文件只保留 `Endpoint` 类型与认证/健康检查端点工厂：
// 业务 Service 在各自文件内构造 `Endpoint(...)`（契约 §3），避免多个 agent 并行
// 往同一个工厂文件里塞端点。multipart 构造见 `MultipartBody.swift`。

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// 哪些端点需要 Bearer。登录/刷新/吊销/健康检查不注入 token，
/// 它们的 401 也不能触发单飞刷新（否则递归）。
enum AuthPolicy: Sendable, Equatable {
    case none
    case bearer
}

enum RequestBody: Sendable {
    case none
    case json(Data)
    case multipart(MultipartBody)
}

struct Endpoint: Sendable {
    let method: HTTPMethod
    /// 相对 baseURL 的路径，不带前导 `/`（baseURL 已含 `/api`，见 `AppConfig.normalize`）。
    let path: String
    let query: [URLQueryItem]
    let headers: [String: String]
    let body: RequestBody
    let timeout: TimeInterval
    let authPolicy: AuthPolicy

    init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: RequestBody = .none,
        timeout: TimeInterval = 15,
        authPolicy: AuthPolicy = .bearer
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.authPolicy = authPolicy
    }
}

// MARK: - 认证 / 健康检查端点工厂
//
// `Endpoint.authRefresh` 被 `Core/Session/TokenRefresher` 直接使用（单飞刷新不能走
// `APITransport.send`，否则 401 会递归）。其余认证端点由 `AuthService` 自行构造，
// 这里的工厂保留是为了不破坏 M0 已存在的调用方。

extension Endpoint {
    static func authToken(email: String, password: String) throws -> Endpoint {
        let data = try JSONEncoder().encode(TokenBody(email: email, password: password))
        return Endpoint(
            method: .post,
            path: "auth/token",
            body: .json(data),
            timeout: 15,
            authPolicy: .none
        )
    }

    static func authRefresh(refreshToken: String) throws -> Endpoint {
        let data = try JSONEncoder().encode(RefreshBody(refreshToken: refreshToken))
        return Endpoint(
            method: .post,
            path: "auth/refresh",
            body: .json(data),
            timeout: 10,
            authPolicy: .none
        )
    }

    static func authRevoke(refreshToken: String) throws -> Endpoint {
        let data = try JSONEncoder().encode(RefreshBody(refreshToken: refreshToken))
        return Endpoint(
            method: .post,
            path: "auth/revoke",
            body: .json(data),
            timeout: 10,
            authPolicy: .none
        )
    }

    static func me() -> Endpoint {
        Endpoint(method: .get, path: "auth/me", timeout: 15, authPolicy: .bearer)
    }

    /// 登录页“测试连接”与 `PracticeService.health()` 用；不需要 Bearer。
    static func health() -> Endpoint {
        Endpoint(method: .get, path: "health", timeout: 10, authPolicy: .none)
    }
}

private struct TokenBody: Encodable {
    let email: String
    let password: String
}

private struct RefreshBody: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

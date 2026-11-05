import Foundation

/// 认证域 Service（契约 §3.1）。
///
/// 端点路径相对 baseURL（baseURL 已含 `/api`，见 `AppConfig.normalize`）：
/// `auth/token`、`auth/refresh`、`auth/me`、`auth/revoke`、`auth/password`。
/// 请求体统一走 `ECJSON.encode`（snake_case 编码）；响应解码走 `APITransport` 的 `HTTPClient.decode`。
struct AuthService: Sendable {
    let transport: APITransport

    /// `POST auth/token`（不需要 Bearer）。后端联调注意：失败返回 401，连续 5 次 429。
    func token(email: String, password: String) async throws -> AuthTokenDTO {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = try ECJSON.encode(
            LoginBodyDTO(email: trimmedEmail, password: password),
            path: "auth/token"
        )
        let endpoint = Endpoint(
            method: .post,
            path: "auth/token",
            body: .json(body),
            timeout: AuthTimeout.login,
            authPolicy: .none
        )
        return try await transport.send(endpoint, as: AuthTokenDTO.self)
    }

    /// `POST auth/refresh`（不需要 Bearer）。`/auth/refresh` 是一次性轮换，只允许单飞调用。
    func refresh(refreshToken: String) async throws -> AuthTokenDTO {
        let body = try ECJSON.encode(
            RefreshBodyDTO(refreshToken: refreshToken),
            path: "auth/refresh"
        )
        let endpoint = Endpoint(
            method: .post,
            path: "auth/refresh",
            body: .json(body),
            timeout: AuthTimeout.refresh,
            authPolicy: .none
        )
        return try await transport.send(endpoint, as: AuthTokenDTO.self)
    }

    /// `GET auth/me`（Bearer）。
    ///
    /// 后端在 Bearer 失效时返回 **200 + `{user:null}`**（不是 401），必须在这里显式转成
    /// `APIError.unauthorized`，否则上层会把“未登录”当成已登录的空资料。
    func me() async throws -> MeResponseDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "auth/me",
            timeout: AuthTimeout.read,
            authPolicy: .bearer
        )
        let response = try await transport.send(endpoint, as: MeResponseDTO.self)
        guard response.user != nil else {
            throw APIError.unauthorized
        }
        return response
    }

    /// `POST auth/revoke`（不需要 Bearer）。服务端返回 204/200，响应体不解析。
    func revoke(refreshToken: String) async throws {
        let body = try ECJSON.encode(
            RevokeBodyDTO(refreshToken: refreshToken),
            path: "auth/revoke"
        )
        let endpoint = Endpoint(
            method: .post,
            path: "auth/revoke",
            body: .json(body),
            timeout: AuthTimeout.revoke,
            authPolicy: .none
        )
        _ = try await transport.sendData(endpoint)
    }

    /// `POST auth/password`（Bearer）。
    ///
    /// 后端尚未上线该端点：失败由 UI 走降级分支（不在这里吞错，也不伪造成功）。
    func changePassword(oldPassword: String, newPassword: String) async throws {
        let body = try ECJSON.encode(
            ChangePasswordBodyDTO(oldPassword: oldPassword, newPassword: newPassword),
            path: "auth/password"
        )
        let endpoint = Endpoint(
            method: .post,
            path: "auth/password",
            body: .json(body),
            timeout: AuthTimeout.write,
            authPolicy: .bearer
        )
        _ = try await transport.sendData(endpoint)
    }
}

// MARK: - 超时（与 HOS `AuthService` 常量对齐：登录/me 15s，刷新/吊销 10s）

private enum AuthTimeout {
    static let login: TimeInterval = 15
    static let read: TimeInterval = 15
    static let refresh: TimeInterval = 10
    static let revoke: TimeInterval = 10
    static let write: TimeInterval = 30
}

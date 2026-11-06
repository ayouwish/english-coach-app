import Foundation

// MARK: - 认证请求体 DTO
//
// 只用作 `JSONEncoder` 的入参（响应形状在 `SharedDTO.swift`：`AuthTokenDTO`/`MeResponseDTO`）。
// 编码时 Account/Auth Service 统一使用 `.convertToSnakeCase`，所以这里用 Swift 驼峰字段名；
// 服务端契约：`access_token`、`refresh_token`、`old_password`、`new_password`。

/// `POST /auth/token` 请求体。
struct LoginBodyDTO: Encodable, Sendable {
    let email: String
    let password: String
}

/// `POST /auth/refresh` 请求体。
struct RefreshBodyDTO: Encodable, Sendable {
    let refreshToken: String
}

/// `POST /auth/revoke` 请求体。
struct RevokeBodyDTO: Encodable, Sendable {
    let refreshToken: String
}

/// `POST /auth/password` 请求体。
///
/// 后端尚未上线该端点（见 port-contract §3.1），字段名按后端既有命名惯例推断为
/// `old_password` / `new_password`；上线后若不同，只需改这里。
struct ChangePasswordBodyDTO: Encodable, Sendable {
    let oldPassword: String
    let newPassword: String
}

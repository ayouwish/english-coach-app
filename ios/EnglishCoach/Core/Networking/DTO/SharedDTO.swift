import Foundation

// MARK: - 共享用户 / 用量 / 认证 DTO
//
// 事实来源：`hos/entry/src/main/ets/core/net/AccountDtos.ets`、`Dtos.ets` 与后端源码
// 读出的形状。字段一律按“服务端可能缺失”处理：可能缺省的一律可选，使用处兜底。
// 解码统一走 `HTTPClient.decode`（`convertFromSnakeCase`），因此不需要手写 CodingKeys。

/// 服务端 user 形状（`/auth/me`、`/auth/token`、`/settings` 共用）。
///
/// 注意：`/settings` 返回的是全量 camelCase 用户（含账号偏好字段）；
/// `/auth/token`、`/auth/me` 只返回瘦身版，偏好字段缺省。
struct AccountUserDTO: Decodable, Sendable, Equatable {
    let id: String
    let email: String
    let displayName: String
    /// "parent" | "child"
    let role: String
    /// "child" | "teen" | "adult"
    let ageBand: String
    let cefrLevel: String
    let avatar: String?
    let birthYear: Int?
    let dailyLimitMinutes: Int?
    let allowFreeChat: Bool?
    let isChild: Bool?
    let nativeLanguage: String?

    // MARK: 账号偏好（只有 `/settings` 才有，其它端点缺省）

    /// watercolor | cartoon | pixel | papercut | clay
    let avatarStyle: String?
    /// 站内绝对路径或绝对 URL
    let avatarImageUrl: String?
    /// 本地/服务端形象图片存储路径（HOS `AccountUserDto.avatarImagePath`；形象页用）
    let avatarImagePath: String?
    let autoIllustrate: Bool?
    /// girl | boy | woman | man | other
    let gender: String?
    /// 3–12；nil = 角色默认（儿童 5 / 成人 8）
    let storySentences: Int?

    /// 儿童判定必须同时看三个字段：服务端主要用 `ageBand == "child"`（家长账号下的儿童档案
    /// 也可能是 `role == "parent"` + `ageBand == "child"`），`isChild` 只在部分端点出现。
    var isChildAccount: Bool {
        role.lowercased() == "child"
            || ageBand.lowercased() == "child"
            || isChild == true
    }

    /// 语料请求用的大写等级（A1/A2/B1/B2/C1）；非法/缺失回退 A1。
    var normalizedLevel: String {
        let upper = cefrLevel.uppercased()
        return ["A1", "A2", "B1", "B2", "C1"].contains(upper) ? upper : "A1"
    }
}

/// 当前用量（`/auth/me`、`/settings`、业务响应里的 usage 共用）。
/// 后端 `/auth/me` 可能不带 usage，字段全部可选。
struct UsageDTO: Decodable, Sendable, Equatable {
    let minutes: Double?
    let limitMinutes: Int?
    /// 服务端按 0.1 分钟取整（`16.5` 这类小数会出现），**不能**声明成 Int，否则整包解码失败
    /// （表现就是“版本不匹配”）。
    let remainingMinutes: Double?
    let exceeded: Bool?
    let attemptCount: Int?
    let chatTurnCount: Int?
}

/// `POST /auth/token` 与 `POST /auth/refresh` 的响应（refresh 不返回 user）。
struct AuthTokenDTO: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?
    /// access 有效期（秒），服务端 3600
    let expiresIn: Int?
    /// refresh 有效期（秒），服务端 30 天
    let refreshExpiresIn: Int?
    let user: AccountUserDTO?
}

/// `GET /auth/me` 的真实返回 `{ user, usage }`；未认证时是 **200 + `{user:null}`**。
struct MeResponseDTO: Decodable, Sendable {
    let user: AccountUserDTO?
    let usage: UsageDTO?
}

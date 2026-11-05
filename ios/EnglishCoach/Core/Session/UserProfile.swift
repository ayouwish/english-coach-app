import Foundation

enum UserRole: String, Sendable, Decodable, Equatable {
    case parent
    case child
}

/// 后端 `/auth/token` 与 `/auth/me` 返回的用户资料（只取 M0 用到的字段）。
///
/// 注意：服务端判断“儿童”用的是 `ageBand == "child"`（见 web `toSessionUser`），
/// 不是 `role`。客户端必须同时看两个字段，否则家长账号的儿童档案会看到 IPA/数字分。
struct UserProfile: Sendable, Equatable, Decodable {
    let id: String
    let email: String
    let displayName: String
    let role: UserRole
    let cefrLevel: String
    let ageBand: String
    let avatar: String?

    var isChild: Bool {
        role == .child || ageBand.lowercased() == "child"
    }

    /// 语料请求用的大写等级；非法/缺失回退 A1。
    var normalizedLevel: String {
        let upper = cefrLevel.uppercased()
        return ["A1", "A2", "B1", "B2", "C1"].contains(upper) ? upper : "A1"
    }

    var avatarEmoji: String {
        if let avatar = self.avatar, !avatar.isEmpty {
            return avatar
        }
        return "🙂"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName
        case role
        case cefrLevel
        case ageBand
        case avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = (try? container.decode(String.self, forKey: .email)) ?? ""
        id = (try? container.decode(String.self, forKey: .id)) ?? email
        ageBand = ((try? container.decode(String.self, forKey: .ageBand)) ?? "").lowercased()
        cefrLevel = ((try? container.decode(String.self, forKey: .cefrLevel)) ?? "A1").uppercased()
        avatar = try? container.decodeIfPresent(String.self, forKey: .avatar)

        if let decodedName = try? container.decode(String.self, forKey: .displayName), !decodedName.isEmpty {
            displayName = decodedName
        } else {
            displayName = email
        }

        if let rawRole = try? container.decode(String.self, forKey: .role),
           let parsed = UserRole(rawValue: rawRole.lowercased()) {
            role = parsed
        } else {
            role = ageBand == "child" ? .child : .parent
        }
    }
}

// MARK: - 从契约 DTO 组装

extension UserProfile {
    /// 由 A1 的 `AccountUserDTO`（`/auth/me`、`/auth/token`、`/settings` 的 user 形状）构造。
    ///
    /// 角色判定以服务端字段为准：`role == "child"` 或 `ageBand == "child"` 或 `isChild == true`
    /// 都算儿童（家长账号下的儿童档案也必须走儿童能力集）。
    init(_ dto: AccountUserDTO) {
        let emailValue = dto.email
        let displayValue = dto.displayName
        self.email = emailValue
        self.id = dto.id.isEmpty ? emailValue : dto.id
        self.displayName = displayValue.isEmpty ? emailValue : displayValue
        self.role = UserRole(rawValue: dto.role.lowercased()) ?? (dto.isChildAccount ? .child : .parent)
        self.cefrLevel = dto.normalizedLevel
        self.ageBand = dto.ageBand.lowercased()
        self.avatar = dto.avatar
    }
}

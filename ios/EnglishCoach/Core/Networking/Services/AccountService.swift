import Foundation

/// 账号域 Service（契约 §3.2）：设置偏好、家庭成员、家长面板、建议箱、虚拟形象。
///
/// 端点路径相对 baseURL（baseURL 已含 `/api`）。请求体统一走 `ECJSON.encode`
/// （`.convertToSnakeCase`），响应解码走 `APITransport` → `HTTPClient.decode`。
///
/// 权限约定：只看 HTTP 状态码（儿童 403 不跳登录、由 `ErrorMapper` 出文案）；
/// `/parent/summary`、`/family/*`、`/suggestions*` 的清单接口仅家长可用。
struct AccountService: Sendable {
    let transport: APITransport

    // MARK: - 设置

    /// `GET settings`：全量 user + prefs + usage。
    func settings() async throws -> SettingsResponseDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "settings",
            timeout: AccountTimeout.read,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: SettingsResponseDTO.self)
    }

    /// `PATCH settings`：入参 snake_case；返回瘦身 user + 完整 prefs + 最新 usage。
    /// 儿童绝不能带 `dailyLimitMinutes` / `allowFreeChat`（服务端 403）。
    func patchSettings(_ body: SettingsPatchDTO) async throws -> SettingsResponseDTO {
        let encoded = try ECJSON.encode(body, path: "settings")
        let endpoint = Endpoint(
            method: .patch,
            path: "settings",
            body: .json(encoded),
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: SettingsResponseDTO.self)
    }

    // MARK: - 家庭成员

    /// `GET family/members`（仅家长）。`items` 可能缺省，按空数组处理。
    func familyMembers() async throws -> [FamilyMemberDTO] {
        let endpoint = Endpoint(
            method: .get,
            path: "family/members",
            timeout: AccountTimeout.read,
            authPolicy: .bearer
        )
        let response = try await transport.send(endpoint, as: FamilyMemberListDTO.self)
        return response.items ?? []
    }

    /// `POST family/members` → 201。服务端返回 `{ ok, member }`。
    func createMember(_ body: FamilyCreateDTO) async throws -> FamilyMemberResponseDTO {
        let encoded = try ECJSON.encode(body, path: "family/members")
        let endpoint = Endpoint(
            method: .post,
            path: "family/members",
            body: .json(encoded),
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: FamilyMemberResponseDTO.self)
    }

    /// `PATCH family/members/:id`（可写昵称/水平/时长/自由聊/头像；传 role 会 400）。
    func updateMember(id: String, _ body: FamilyPatchDTO) async throws -> FamilyMemberResponseDTO {
        let encoded = try ECJSON.encode(body, path: "family/members/:id")
        let endpoint = Endpoint(
            method: .patch,
            path: "family/members/\(id)",
            body: .json(encoded),
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: FamilyMemberResponseDTO.self)
    }

    /// `POST family/members/:id/password` —— 不需要旧密码，可重置自己。
    func resetMemberPassword(id: String, newPassword: String) async throws {
        let encoded = try ECJSON.encode(
            ResetPasswordBodyDTO(newPassword: newPassword),
            path: "family/members/:id/password"
        )
        let endpoint = Endpoint(
            method: .post,
            path: "family/members/\(id)/password",
            body: .json(encoded),
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        _ = try await transport.sendData(endpoint)
    }

    // MARK: - 家长面板

    /// `GET parent/summary`（仅家长；儿童 403，由 `ErrorMapper` 提示「家长专用」）。
    func parentSummary() async throws -> ParentSummaryDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "parent/summary",
            timeout: AccountTimeout.read,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: ParentSummaryDTO.self)
    }

    // MARK: - 建议箱

    /// `POST suggestions`（所有人含儿童都能提；user_id 由服务端从会话取）。
    func submitSuggestion(_ body: SuggestionCreateDTO) async throws -> SuggestionCreateResultDTO {
        let encoded = try ECJSON.encode(body, path: "suggestions")
        let endpoint = Endpoint(
            method: .post,
            path: "suggestions",
            body: .json(encoded),
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: SuggestionCreateResultDTO.self)
    }

    /// `GET suggestions`（仅家长）。`status` 为空串表示不过滤；服务端不过滤非法值。
    func listSuggestions(status: String, limit: Int, offset: Int) async throws -> SuggestionListDTO {
        var query: [URLQueryItem] = []
        if !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        query.append(URLQueryItem(name: "limit", value: String(limit)))
        query.append(URLQueryItem(name: "offset", value: String(offset)))
        let endpoint = Endpoint(
            method: .get,
            path: "suggestions",
            query: query,
            timeout: AccountTimeout.read,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: SuggestionListDTO.self)
    }

    /// `PATCH suggestions/:id {status}` —— open | read | resolved。
    func patchSuggestionStatus(id: String, status: String) async throws {
        let encoded = try ECJSON.encode(
            SuggestionPatchDTO(status: status),
            path: "suggestions/:id"
        )
        let endpoint = Endpoint(
            method: .patch,
            path: "suggestions/\(id)",
            body: .json(encoded),
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        _ = try await transport.sendData(endpoint)
    }

    /// `GET suggestions/export?format=md[&status=]` —— 响应体是 **Markdown 文本**（不是 JSON）。
    func exportSuggestionsMarkdown(status: String) async throws -> String {
        var query: [URLQueryItem] = [URLQueryItem(name: "format", value: "md")]
        if !status.isEmpty {
            query.append(URLQueryItem(name: "status", value: status))
        }
        let endpoint = Endpoint(
            method: .get,
            path: "suggestions/export",
            query: query,
            timeout: AccountTimeout.read,
            authPolicy: .bearer
        )
        let data = try await transport.sendData(endpoint)
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIError.decoding(path: "suggestions/export")
        }
        return text
    }

    // MARK: - 虚拟形象

    /// `GET avatar/presets` —— 12 角色 × 5 风格；`images` 是站内绝对路径。
    func avatarPresets() async throws -> AvatarPresetsDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "avatar/presets",
            timeout: AccountTimeout.read,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: AvatarPresetsDTO.self)
    }

    /// `GET avatar` —— 未设置时字段为 nil（`styles` 仍在）。
    func avatar() async throws -> AvatarStateDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "avatar",
            timeout: AccountTimeout.read,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: AvatarStateDTO.self)
    }

    /// `POST avatar {preset_id, style}` —— 立即生效，不生成图片。
    func selectAvatar(presetId: String, style: String) async throws -> AvatarStateDTO {
        let encoded = try ECJSON.encode(
            AvatarSelectBodyDTO(presetId: presetId, style: style),
            path: "avatar"
        )
        let endpoint = Endpoint(
            method: .post,
            path: "avatar",
            body: .json(encoded),
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: AvatarStateDTO.self)
    }

    /// `PATCH avatar {character_desc}` —— 只允许改角色卡描述。
    func updateAvatarDescription(_ description: String) async throws -> AvatarStateDTO {
        let encoded = try ECJSON.encode(
            AvatarDescBodyDTO(characterDesc: description),
            path: "avatar"
        )
        let endpoint = Endpoint(
            method: .patch,
            path: "avatar",
            body: .json(encoded),
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: AvatarStateDTO.self)
    }

    /// `DELETE avatar` —— 清空字段（预置静态图不删）。
    func clearAvatar() async throws {
        let endpoint = Endpoint(
            method: .delete,
            path: "avatar",
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        _ = try await transport.sendData(endpoint)
    }

    /// `GET avatar/image` —— 头像图片二进制（预置图走静态路径时通常不会调用）。
    func avatarImageData() async throws -> Data {
        let endpoint = Endpoint(
            method: .get,
            path: "avatar/image",
            timeout: AccountTimeout.write,
            authPolicy: .bearer
        )
        return try await transport.sendData(endpoint)
    }
}

// MARK: - 超时（与 HOS `AccountService` 常量对齐：读 15s，写 30s）

private enum AccountTimeout {
    static let read: TimeInterval = 15
    static let write: TimeInterval = 30
}

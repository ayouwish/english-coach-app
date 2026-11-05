import Foundation

/// `GET chat/sessions/:id/audio` 的结果（200 / 202 / 500 三种语义都收在这里，页面不解析 HTTP）。
///
/// - `ready(Data)`：200，音频字节（页面自行落盘并交给播放器）
/// - `building`：202，后台正在拼接（页面继续轮询 `audioStatus`）
/// - `failed(String)`：500，携带服务端错误说明；服务端没给说明时是空串，
///   此时页面用 `ErrorMapper` 兜底（本层不写用户可见文案）
struct ChatAudioResult: Sendable {
    enum State: Sendable {
        case ready(Data)
        case building
        case failed(String)
    }

    let state: State
}

/// 对话训练 API（契约 §3.5）。
///
/// 职责边界：只拼 URL / 上传 / 转 DTO；不持有页面状态、不落盘、不弹提示。
/// 一轮三步由页面（B2）编排：`asr` → `turn` → `PracticeService.synthesize`。
/// `pron` 分数只能从 `messages` 拿到，`turn` 的响应不含分数。
struct ChatService: Sendable {
    let transport: APITransport

    private static let listTimeout: TimeInterval = 15
    private static let mutateTimeout: TimeInterval = 20
    private static let asrTimeout: TimeInterval = 60
    /// LLM 单轮最长约 40s，给 90s
    private static let turnTimeout: TimeInterval = 90
    /// 整段回放可能几分钟（上限 900s），下载给 120s
    private static let audioTimeout: TimeInterval = 120
    private static let audioDownloadTimeout: TimeInterval = 60
    /// 小于该字节数视为「不是音频」（错误 JSON 体等）；阈值照 HOS `ChatService`
    private static let minimumAudioBytes = 128

    // MARK: - 场景

    /// `GET chat/scenarios[?include_child=1]`
    func scenarios(includeChild: Bool) async throws -> ChatScenarioListDTO {
        let query: [URLQueryItem] = includeChild
            ? [URLQueryItem(name: "include_child", value: "1")]
            : []
        let endpoint = Endpoint(
            method: .get,
            path: "chat/scenarios",
            query: query,
            timeout: Self.listTimeout
        )
        return try await transport.send(endpoint, as: ChatScenarioListDTO.self)
    }

    /// `POST chat/scenarios`（201）→ 新场景 id。`audience` 为空表示交给服务端按账号定。
    func createScenario(
        title: String,
        titleZh: String,
        settingZh: String,
        rolePrompt: String,
        openingLine: String,
        level: String,
        audience: String
    ) async throws -> String {
        let body = ChatScenarioBody(
            title: Self.optional(title),
            titleZh: Self.optional(titleZh),
            settingZh: Self.optional(settingZh),
            rolePrompt: Self.optional(rolePrompt),
            openingLine: Self.optional(openingLine),
            level: Self.optional(level),
            audience: Self.optional(audience)
        )
        let data = try ECJSON.encode(body, path: "chat/scenarios")
        let endpoint = Endpoint(
            method: .post,
            path: "chat/scenarios",
            body: .json(data),
            timeout: Self.mutateTimeout
        )
        let dto = try await transport.send(endpoint, as: ChatScenarioMutationDTO.self)
        guard let id = dto.id, !id.isEmpty else {
            throw APIError.decoding(path: endpoint.path)
        }
        return id
    }

    /// `PATCH chat/scenarios/:id`。空字符串字段不传（服务端取原值，HOS 同语义）。
    func updateScenario(
        id: String,
        title: String,
        titleZh: String,
        settingZh: String,
        rolePrompt: String,
        openingLine: String,
        level: String
    ) async throws {
        let body = ChatScenarioBody(
            title: Self.optional(title),
            titleZh: Self.optional(titleZh),
            settingZh: Self.optional(settingZh),
            rolePrompt: Self.optional(rolePrompt),
            openingLine: Self.optional(openingLine),
            level: Self.optional(level),
            audience: nil
        )
        let data = try ECJSON.encode(body, path: "chat/scenarios/\(encodedPath(id))")
        let endpoint = Endpoint(
            method: .patch,
            path: "chat/scenarios/\(encodedPath(id))",
            body: .json(data),
            timeout: Self.mutateTimeout
        )
        _ = try await transport.sendData(endpoint)
    }

    /// `DELETE chat/scenarios/:id`（仅 owner；他人 id 返回 404）。
    func deleteScenario(id: String) async throws {
        let endpoint = Endpoint(
            method: .delete,
            path: "chat/scenarios/\(encodedPath(id))",
            timeout: Self.mutateTimeout
        )
        _ = try await transport.sendData(endpoint)
    }

    // MARK: - 会话

    /// `POST chat/sessions {scenario_id}`（201）→ 含 `session_id` 与首条 assistant 消息。
    func createSession(scenarioId: String) async throws -> ChatSessionDTO {
        let body = ChatSessionCreateBody(scenarioId: scenarioId)
        let data = try ECJSON.encode(body, path: "chat/sessions")
        let endpoint = Endpoint(
            method: .post,
            path: "chat/sessions",
            body: .json(data),
            timeout: Self.mutateTimeout
        )
        return try await transport.send(endpoint, as: ChatSessionDTO.self)
    }

    /// `POST chat/sessions/:id/turn`（multipart：`text` 必填 + `audio` 可选）。
    ///
    /// 服务端只返回助手文本（不做 ASR、不返回 TTS 音频）；`audio` 仅供后台发音评估。
    func turn(sessionId: String, text: String, audioData: Data?) async throws -> ChatTurnDTO {
        var builder = MultipartFormDataBuilder()
        builder.addField(name: "text", value: text)
        if let audioData, !audioData.isEmpty {
            builder.addFile(name: "audio", filename: "recording.m4a", mimeType: "audio/mp4", data: audioData)
        }
        let endpoint = Endpoint(
            method: .post,
            path: "chat/sessions/\(encodedPath(sessionId))/turn",
            body: .multipart(builder.finalize()),
            timeout: Self.turnTimeout
        )
        return try await transport.send(endpoint, as: ChatTurnDTO.self)
    }

    /// `GET chat/sessions/:id/messages`（唯一的 `pron` 来源；页面按 1s/2s/3s… 轮询）。
    func messages(sessionId: String) async throws -> ChatMessageListDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "chat/sessions/\(encodedPath(sessionId))/messages",
            timeout: Self.listTimeout
        )
        return try await transport.send(endpoint, as: ChatMessageListDTO.self)
    }

    /// `POST chat/sessions/:id/end`（幂等，空 body）。
    func end(sessionId: String) async throws {
        let endpoint = Endpoint(
            method: .post,
            path: "chat/sessions/\(encodedPath(sessionId))/end",
            timeout: Self.mutateTimeout
        )
        _ = try await transport.sendData(endpoint)
    }

    /// `GET chat/sessions/:id/audio/status`（只读，绝不触发构建）。
    func audioStatus(sessionId: String) async throws -> ChatAudioStatusDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "chat/sessions/\(encodedPath(sessionId))/audio/status",
            timeout: Self.listTimeout
        )
        let dto = try await transport.send(endpoint, as: ChatAudioStatusDTO.self)
        guard let status = dto.status, !status.isEmpty else {
            // 服务端没给状态时按「构建中」处理（HOS 同语义），避免页面误判为 ready。
            return ChatAudioStatusDTO(
                status: "building",
                turnCount: dto.turnCount,
                autoRetry: dto.autoRetry,
                durationMs: dto.durationMs,
                error: dto.error,
                errorCode: dto.errorCode,
                attempts: dto.attempts
            )
        }
        return dto
    }

    /// `GET chat/sessions/:id/audio[?force=1]`：200 / 202 / 500 三态。
    ///
    /// `APITransport` 只暴露字节、不暴露状态码，因此 200（二进制音频）与 202（JSON
    /// `ChatAudioBuildingDTO`）按响应体首字节区分：音频容器开头是 `RIFF`/`ID3`/`ftyp`，不会是 `{`。
    func audio(sessionId: String, force: Bool) async throws -> ChatAudioResult {
        let query: [URLQueryItem] = force
            ? [URLQueryItem(name: "force", value: "1")]
            : []
        let endpoint = Endpoint(
            method: .get,
            path: "chat/sessions/\(encodedPath(sessionId))/audio",
            query: query,
            timeout: Self.audioTimeout
        )
        do {
            let data = try await transport.sendData(endpoint)
            if Self.looksLikeJSON(data) {
                return ChatAudioResult(state: .building)
            }
            guard data.count >= Self.minimumAudioBytes else {
                throw APIError.decoding(path: endpoint.path)
            }
            return ChatAudioResult(state: .ready(data))
        } catch let error as APIError {
            if case .server(_, let message, let status) = error, status == 500 {
                return ChatAudioResult(state: .failed(message ?? ""))
            }
            throw error
        }
    }

    // MARK: - 历史

    /// `GET chat/sessions`（最近 30 条，倒序）。
    func sessions() async throws -> ChatSessionListDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "chat/sessions",
            timeout: Self.listTimeout
        )
        return try await transport.send(endpoint, as: ChatSessionListDTO.self)
    }

    /// `GET chat/sessions/:id`（详情**无 `pron`**；`pron` 只能轮询 `messages`）。
    func sessionDetail(id: String) async throws -> ChatSessionDetailDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "chat/sessions/\(encodedPath(id))",
            timeout: Self.listTimeout
        )
        return try await transport.send(endpoint, as: ChatSessionDetailDTO.self)
    }

    // MARK: - ASR

    /// `POST asr?language=`（multipart `audio`）→ 识别文本。
    ///
    /// 返回空串表示「没听清」（服务端没识别出内容），由页面提示重说，这里不做文案。
    func asr(audioData: Data, language: String) async throws -> String {
        guard !audioData.isEmpty else {
            // 本地预检：空录音不发请求（HOS 抛 RECORD_FAILED）
            throw APIError.server(code: .badRequest, message: nil, status: 0)
        }
        var builder = MultipartFormDataBuilder()
        builder.addFile(name: "audio", filename: "recording.m4a", mimeType: "audio/mp4", data: audioData)
        let query: [URLQueryItem] = language.isEmpty
            ? []
            : [URLQueryItem(name: "language", value: language)]
        if !language.isEmpty {
            // HOS 与契约 §3.5 把 `language` 放在 query 上；这里再冗余一个同名表单字段，
            // 兼容「按 multipart 字段读取 language」的后端实现（两种读法的服务端都能拿到）。
            builder.addField(name: "language", value: language)
        }
        let endpoint = Endpoint(
            method: .post,
            path: "asr",
            query: query,
            body: .multipart(builder.finalize()),
            timeout: Self.asrTimeout
        )
        let dto = try await transport.send(endpoint, as: ChatAsrDTO.self)
        return (dto.text ?? dto.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 音频字节

    /// `GET` 任意站内音频 URL（`audioUrl` 形如 `/api/audio/cm_xxx`，也可能是同源绝对 URL）。
    func downloadAudio(url: String) async throws -> Data {
        guard let location = endpointLocation(for: url) else {
            throw APIError.invalidBaseURL
        }
        let endpoint = Endpoint(
            method: .get,
            path: location.path,
            query: location.query,
            timeout: Self.audioDownloadTimeout
        )
        let data = try await transport.sendData(endpoint)
        guard data.count >= Self.minimumAudioBytes else {
            throw APIError.decoding(path: location.path)
        }
        return data
    }

    // MARK: - 内部工具

    private static func optional(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    /// `APITransport` 不暴露状态码：音频接口 200 = 二进制、202 = JSON，按首字节判别。
    private static func looksLikeJSON(_ data: Data) -> Bool {
        guard let first = data.first else { return false }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }

    /// 路径段编码：id 正常是 `cs_xxx` 这类安全串，这里仍剥掉会改变路径结构的字符。
    private func encodedPath(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// 把服务端给的站内地址（`/api/audio/xx` 或同源绝对 URL）转成「相对 baseURL 的路径 + query」。
    ///
    /// `baseURL` 已含 `/api`（见 `AppConfig.normalize`），所以路径里的 `/api` 前缀要剥掉，
    /// 否则会拼成 `/api/api/audio/xx`。
    private func endpointLocation(for rawURL: String) -> (path: String, query: [URLQueryItem])? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var path: String
        var query: [URLQueryItem] = []

        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            path = components.path
            query = components.queryItems ?? []
            let basePath = transport.baseURL.path
            if !basePath.isEmpty, basePath != "/", path == basePath || path.hasPrefix(basePath + "/") {
                path = String(path.dropFirst(basePath.count))
            } else if let range = path.range(of: "/api/") {
                path = String(path[range.upperBound...])
            } else {
                return nil
            }
        } else {
            path = trimmed
            var rawQuery = ""
            if let questionMark = path.firstIndex(of: "?") {
                rawQuery = String(path[path.index(after: questionMark)...])
                path = String(path[..<questionMark])
            }
            if path.hasPrefix("/api/") {
                path = String(path.dropFirst("/api/".count))
            } else if path.hasPrefix("/") {
                path = String(path.dropFirst())
            }
            if !rawQuery.isEmpty {
                query = rawQuery.split(separator: "&").compactMap { pair in
                    let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard let name = parts.first, !name.isEmpty else { return nil }
                    let decodedName = String(name).removingPercentEncoding ?? String(name)
                    let rawValue = parts.count > 1 ? String(parts[1]) : nil
                    let decodedValue = rawValue?.removingPercentEncoding ?? rawValue
                    return URLQueryItem(name: decodedName, value: decodedValue)
                }
            }
        }

        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }
        return path.isEmpty ? nil : (path: path, query: query)
    }
}

// MARK: - 请求体

/// 创建 / 编辑场景的 body：空串字段按「不传」处理（PATCH 语义 = 未传取原值）。
/// 键名由 `ECJSON` 的 `convertToSnakeCase` 转换（`titleZh` → `title_zh`…）。
private struct ChatScenarioBody: Encodable {
    let title: String?
    let titleZh: String?
    let settingZh: String?
    let rolePrompt: String?
    let openingLine: String?
    let level: String?
    let audience: String?
}

private struct ChatSessionCreateBody: Encodable {
    let scenarioId: String
}

import Foundation

/// 故事模式 API（契约 §3.6）。
///
/// 职责边界：只拼 URL / 上传 / 转 DTO；不落盘、不播放、不持有页面状态。
///
/// 线上降级（2026-11-03 实测，与 HOS 一致）：
/// - `POST story/recordings` 在线上是 404，所以**录音转写一律走** `asr`（`POST asr?language=`）；
///   HOS 也没有该服务方法，故这里不自创「录音留存」接口。
/// - 复述 = 两步：先 `asr(audioData:language:)` 拿 transcript，再 `retell(...)`。
struct StoryService: Sendable {
    let transport: APITransport

    private static let listTimeout: TimeInterval = 20
    private static let detailTimeout: TimeInterval = 20
    /// ASR 可能 60s+；给 120s
    private static let asrTimeout: TimeInterval = 120
    private static let rewriteTimeout: TimeInterval = 120
    private static let retellTimeout: TimeInterval = 120
    /// 生图很慢（10–30s），留足余量
    private static let illustrateTimeout: TimeInterval = 180
    private static let saveTimeout: TimeInterval = 30
    private static let audioStatusTimeout: TimeInterval = 15
    private static let audioTimeout: TimeInterval = 120
    private static let maximumAudioBytes = 25 * 1024 * 1024
    /// 小于该字节数视为「不是音频 / 不是图片」（错误 JSON 体等）；阈值照 HOS `StoryService`
    private static let minimumAudioBytes = 64
    private static let minimumImageBytes = 32

    // MARK: - 故事集（materials）

    /// `GET materials?kind=story&limit=&offset=`（家庭共享，服务端已排序）→ 列表项。
    func materials(limit: Int, offset: Int) async throws -> [StoryMaterialDTO] {
        let query = [
            URLQueryItem(name: "kind", value: "story"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        let endpoint = Endpoint(
            method: .get,
            path: "materials",
            query: query,
            timeout: Self.listTimeout
        )
        let dto = try await transport.send(endpoint, as: StoryMaterialListDTO.self)
        return dto.items ?? []
    }

    /// `GET materials/:id`（详情多 `text` / `sourceZh` / `imageUrl`）。
    func materialDetail(id: String) async throws -> StoryMaterialDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "materials/\(encodedPath(id))",
            timeout: Self.detailTimeout
        )
        return try await transport.send(endpoint, as: StoryMaterialDTO.self)
    }

    /// `POST materials`（kind=story，201）→ 新建故事摘要。
    func createMaterial(title: String, text: String, sourceZh: String, level: String) async throws -> StoryMaterialCreatedDTO {
        let body = StoryMaterialCreateDTO(
            title: title,
            text: text,
            kind: "story",
            sourceZh: Self.optional(sourceZh),
            level: Self.optional(level),
            source: "text"
        )
        let data = try ECJSON.encode(body, path: "materials")
        let endpoint = Endpoint(
            method: .post,
            path: "materials",
            body: .json(data),
            timeout: Self.saveTimeout
        )
        return try await transport.send(endpoint, as: StoryMaterialCreatedDTO.self)
    }

    /// `PATCH materials/:id` —— 只改标题（服务端校验只能改自己录入的）。
    func renameMaterial(id: String, title: String) async throws {
        let data = try ECJSON.encode(StoryMaterialPatchBody(title: title), path: "materials/\(encodedPath(id))")
        let endpoint = Endpoint(
            method: .patch,
            path: "materials/\(encodedPath(id))",
            body: .json(data),
            timeout: Self.saveTimeout
        )
        _ = try await transport.sendData(endpoint)
    }

    /// `DELETE materials/:id` —— 删除故事（服务端校验只能删自己录入的）。
    func deleteMaterial(id: String) async throws {
        let endpoint = Endpoint(
            method: .delete,
            path: "materials/\(encodedPath(id))",
            timeout: Self.saveTimeout
        )
        _ = try await transport.sendData(endpoint)
    }

    // MARK: - ASR（录音转写的唯一降级路径）

    /// `POST asr?language=`（multipart `audio`）→ 识别文本。
    ///
    /// 讲故事录音传 `zh-CN`，复述传 `en-US`。返回空串表示「没听清」（服务端没识别出内容），
    /// 由页面提示重说；本层不写用户可见文案。
    func asr(audioData: Data, language: String) async throws -> String {
        guard !audioData.isEmpty else {
            // 本地预检：空录音不发请求（HOS 抛 RECORD_FAILED）
            throw APIError.server(code: .badRequest, message: nil, status: 0)
        }
        guard audioData.count <= Self.maximumAudioBytes else {
            // HOS 在客户端先拦 25MB，不依赖服务端 413
            throw APIError.payloadTooLarge(localBytes: audioData.count)
        }
        var builder = MultipartFormDataBuilder()
        builder.addFile(name: "audio", filename: "story.m4a", mimeType: "audio/mp4", data: audioData)
        let query: [URLQueryItem] = language.isEmpty
            ? []
            : [URLQueryItem(name: "language", value: language)]
        if !language.isEmpty {
            // HOS 与契约 §3.6 把 `language` 放在 query 上；这里再冗余一个同名表单字段，
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
        let dto = try await transport.send(endpoint, as: StoryAsrDTO.self)
        return (dto.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 改写 / 复述

    /// `POST story/rewrite`（中文 → 分级英文）。`tense` 取 `auto` / `past` / `present`，空串按 `auto`。
    func rewrite(textZh: String, level: String, maxSentences: Int, tense: String) async throws -> StoryRewriteDTO {
        let body = StoryRewriteBody(
            textZh: textZh,
            level: level,
            maxSentences: maxSentences,
            useWeakPhonemes: false,
            tense: Self.optional(tense) ?? "auto"
        )
        let data = try ECJSON.encode(body, path: "story/rewrite")
        let endpoint = Endpoint(
            method: .post,
            path: "story/rewrite",
            body: .json(data),
            timeout: Self.rewriteTimeout
        )
        let dto = try await transport.send(endpoint, as: StoryRewriteDTO.self)
        if dto.sentences.isEmpty, (dto.textEn ?? "").isEmpty {
            throw APIError.decoding(path: endpoint.path)
        }
        return dto
    }

    /// `POST story/retell`（不评发音分）。`materialId` 为空串时不传。
    func retell(materialId: String, storySentences: [String], transcript: String, level: String) async throws -> StoryRetellDTO {
        let body = StoryRetellBody(
            materialId: Self.optional(materialId),
            storySentences: storySentences,
            transcript: transcript,
            level: level
        )
        let data = try ECJSON.encode(body, path: "story/retell")
        let endpoint = Endpoint(
            method: .post,
            path: "story/retell",
            body: .json(data),
            timeout: Self.retellTimeout
        )
        return try await transport.send(endpoint, as: StoryRetellDTO.self)
    }

    /// `GET story/:id/retells` —— 复述历史。
    ///
    /// **契约未定**：HOS 没有这个接口（复述结果只在本会话内存保留），线上可能 404；
    /// 按契约「失败返回 []，页面不阻塞」处理，只把取消继续向上抛。
    func retellRecords(materialId: String) async throws -> [StoryRetellRecordDTO] {
        let endpoint = Endpoint(
            method: .get,
            path: "story/\(encodedPath(materialId))/retells",
            timeout: Self.listTimeout
        )
        do {
            return try await transport.send(endpoint, as: [StoryRetellRecordDTO].self)
        } catch let error as APIError {
            if error.isCancelled {
                throw error
            }
            return []
        } catch {
            return []
        }
    }

    // MARK: - 插画

    /// `POST story/:id/illustrate[?force=1]`（返回 `promptUsed`）。
    func illustrate(id: String, force: Bool) async throws -> StoryIllustrationDTO {
        let data = try ECJSON.encode(
            StoryIllustrateBody(force: force, style: "watercolor"),
            path: "story/\(encodedPath(id))/illustrate"
        )
        let query: [URLQueryItem] = force
            ? [URLQueryItem(name: "force", value: "1")]
            : []
        let endpoint = Endpoint(
            method: .post,
            path: "story/\(encodedPath(id))/illustrate",
            query: query,
            body: .json(data),
            timeout: Self.illustrateTimeout
        )
        return try await transport.send(endpoint, as: StoryIllustrationDTO.self)
    }

    // MARK: - 整段朗读回放

    /// `GET story/:id/audio/status`（只读，绝不触发构建）。
    ///
    /// 404（`no_audio`：这个故事还没录过朗读）不抛错，转成 `status: "no_audio"` 交给页面隐藏播放器。
    func audioStatus(id: String) async throws -> StoryAudioStatusDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "story/\(encodedPath(id))/audio/status",
            timeout: Self.audioStatusTimeout
        )
        do {
            let dto = try await transport.send(endpoint, as: StoryAudioStatusDTO.self)
            guard let status = dto.status, !status.isEmpty else {
                return StoryAudioStatusDTO(
                    status: "building",
                    attemptCount: dto.attemptCount,
                    single: dto.single,
                    durationMs: dto.durationMs,
                    error: dto.error,
                    errorCode: dto.errorCode,
                    retryAfterMs: dto.retryAfterMs
                )
            }
            return dto
        } catch let error as APIError {
            if case .server(_, let message, let status) = error, status == 404 {
                return StoryAudioStatusDTO(
                    status: "no_audio",
                    attemptCount: nil,
                    single: nil,
                    durationMs: nil,
                    error: message ?? "",
                    errorCode: nil,
                    retryAfterMs: nil
                )
            }
            throw error
        }
    }

    /// `GET story/:id/audio[?force=1]` → 整段朗读音频字节。
    ///
    /// 202（后台构建中）的响应体是 JSON，而签名只返回 `Data`：因此这里抛 `.providerUnavailable`
    /// 让页面「稍后再试」（正确流程是先轮询 `audioStatus` 到 ready 再下载）。
    func storyAudio(id: String, force: Bool) async throws -> Data {
        let query: [URLQueryItem] = force
            ? [URLQueryItem(name: "force", value: "1")]
            : []
        let endpoint = Endpoint(
            method: .get,
            path: "story/\(encodedPath(id))/audio",
            query: query,
            timeout: Self.audioTimeout
        )
        let data = try await transport.sendData(endpoint)
        guard !Self.looksLikeJSON(data) else {
            throw APIError.server(code: .providerUnavailable, message: nil, status: 202)
        }
        guard data.count >= Self.minimumAudioBytes else {
            throw APIError.decoding(path: endpoint.path)
        }
        return data
    }

    // MARK: - 图片字节

    /// `GET materials/:id/image` → 图片字节（带 Bearer，必须由客户端落盘再显示）。
    func materialImageData(materialId: String) async throws -> Data {
        let endpoint = Endpoint(
            method: .get,
            path: "materials/\(encodedPath(materialId))/image",
            timeout: Self.detailTimeout
        )
        let data = try await transport.sendData(endpoint)
        guard data.count >= Self.minimumImageBytes else {
            throw APIError.decoding(path: endpoint.path)
        }
        return data
    }

    /// 按服务端返回的 `imageUrl`（形如 `/api/materials/:id/image`，也可能是同源绝对 URL）取图片字节。
    func imageData(url: String) async throws -> Data {
        guard let location = endpointLocation(for: url) else {
            throw APIError.invalidBaseURL
        }
        let endpoint = Endpoint(
            method: .get,
            path: location.path,
            query: location.query,
            timeout: Self.detailTimeout
        )
        let data = try await transport.sendData(endpoint)
        guard data.count >= Self.minimumImageBytes else {
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

    /// 路径段编码：id 正常是 `m_xxx` / `sc_xxx` 这类安全串，这里仍剥掉会改变路径结构的字符。
    private func encodedPath(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// 把服务端给的站内地址（`/api/materials/:id/image` 或同源绝对 URL）转成
    /// 「相对 baseURL 的路径 + query」。`baseURL` 已含 `/api`，所以要剥掉路径里的 `/api` 前缀。
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

/// `POST story/rewrite` 请求体（键名由 `ECJSON` 转 snake_case：`max_sentences` / `use_weak_phonemes`）。
private struct StoryRewriteBody: Encodable {
    let textZh: String
    let level: String
    let maxSentences: Int
    let useWeakPhonemes: Bool
    let tense: String
}

/// `POST story/retell` 请求体（`material_id` 为空时不出现）。
private struct StoryRetellBody: Encodable {
    let materialId: String?
    let storySentences: [String]
    let transcript: String
    let level: String
}

/// `POST story/:id/illustrate` 请求体。
private struct StoryIllustrateBody: Encodable {
    let force: Bool
    let style: String
}

/// `PATCH materials/:id` 请求体（只改标题）。
private struct StoryMaterialPatchBody: Encodable {
    let title: String
}

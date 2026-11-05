import Foundation

/// 跟读域 API：语料、TTS、同步评测、评测历史、健康检查。
/// 职责边界：只拼端点 / 转 DTO / 返回字节；不落盘、不播放、不持有页面状态。
///
/// 超时按 HOS 实现（`core/service/PracticeService.ets`）：
/// 列表 15s、TTS 30s、同步评测 120s、健康检查 5s。
struct PracticeService: Sendable {
    let transport: APITransport

    private static let listTimeout: TimeInterval = 15
    private static let ttsTimeout: TimeInterval = 30
    private static let attemptTimeout: TimeInterval = 120
    private static let healthTimeout: TimeInterval = 5
    /// 服务端硬限制：单段音频 ≤ 12MB；客户端提交前预检，不依赖 413。
    private static let maxAudioBytes = 12 * 1024 * 1024
    /// HOS 判定：小于该长度的 TTS 响应视为损坏（正常音频远大于 64B）。
    private static let minAudioBytes = 64

    // MARK: - 语料

    /// `GET /sentences?level=&focus=`
    func sentences(level: String, focus: String = "") async throws -> SentenceListDTO {
        var query: [URLQueryItem] = []
        if !level.isEmpty {
            query.append(URLQueryItem(name: "level", value: level))
        }
        if !focus.isEmpty {
            query.append(URLQueryItem(name: "focus", value: focus))
        }
        let endpoint = Endpoint(
            method: .get,
            path: "sentences",
            query: query,
            timeout: Self.listTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: SentenceListDTO.self)
    }

    /// `GET /sentences/:id`
    func sentence(id: String) async throws -> SentenceDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "sentences/\(id)",
            timeout: Self.listTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: SentenceDTO.self)
    }

    // MARK: - 评测历史

    /// `GET /attempts?limit=N` —— 我的评测记录（单句历史 / 进步曲线的数据源）。
    func attempts(limit: Int) async throws -> [AttemptItemDTO] {
        let endpoint = Endpoint(
            method: .get,
            path: "attempts",
            query: [URLQueryItem(name: "limit", value: String(limit))],
            timeout: Self.listTimeout,
            authPolicy: .bearer
        )
        let list = try await transport.send(endpoint, as: AttemptListDTO.self)
        return list.attempts ?? []
    }

    /// 单句历史。
    ///
    /// 后端线上**没有** `GET /sentences/:id/attempts`（HOS `FlowService` 头注释与
    /// `docs/android-feature-list.md` §D-02 均实测记录 404），因此按 HOS/Android 的
    /// 既有规避方案实现：拉最近 100 条评测记录，在本地按 `sentence_id` 过滤。
    /// 契约里的方法名/签名不变；调用方拿到的仍是“这一句的评测记录”，顺序为服务端返回顺序。
    func attemptsForSentence(id: String) async throws -> [AttemptItemDTO] {
        let endpoint = Endpoint(
            method: .get,
            path: "attempts",
            query: [URLQueryItem(name: "limit", value: "100")],
            timeout: Self.listTimeout,
            authPolicy: .bearer
        )
        let list = try await transport.send(endpoint, as: AttemptListDTO.self)
        return (list.attempts ?? []).filter { $0.sentenceId == id }
    }

    // MARK: - 同步评测

    /// `POST /attempts`（multipart，同步）。
    /// 字段顺序严格按服务端契约：audio → sentence_id → reference_text → mode → duration_ms，
    /// `blind_test_id` 只在存在时追加。
    func evaluate(
        audioData: Data,
        filename: String,
        mimeType: String,
        sentenceId: String,
        referenceText: String,
        mode: AttemptMode,
        durationMs: Int,
        blindTestId: String? = nil
    ) async throws -> AttemptResponseDTO {
        guard audioData.count <= Self.maxAudioBytes else {
            throw APIError.payloadTooLarge(localBytes: audioData.count)
        }
        var builder = MultipartFormDataBuilder()
        builder.addFile(name: "audio", filename: filename, mimeType: mimeType, data: audioData)
        builder.addField(name: "sentence_id", value: sentenceId)
        builder.addField(name: "reference_text", value: referenceText)
        builder.addField(name: "mode", value: mode.rawValue)
        builder.addField(name: "duration_ms", value: String(durationMs))
        if let blindTestId, !blindTestId.isEmpty {
            builder.addField(name: "blind_test_id", value: blindTestId)
        }
        let endpoint = Endpoint(
            method: .post,
            path: "attempts",
            body: .multipart(builder.finalize()),
            timeout: Self.attemptTimeout,
            authPolicy: .bearer
        )
        return try await decodeAttempt(endpoint)
    }

    /// `POST /attempts/:id/retry` —— 用已存录音重评（degraded 时用，不重新上传）。
    func retryAttempt(id: String) async throws -> AttemptResponseDTO {
        let endpoint = Endpoint(
            method: .post,
            path: "attempts/\(id)/retry",
            timeout: Self.attemptTimeout,
            authPolicy: .bearer
        )
        return try await decodeAttempt(endpoint)
    }

    /// 评测响应必须有 `attempt_id`，缺失视为契约漂移（与 HOS BAD_RESPONSE 判定一致）。
    private func decodeAttempt(_ endpoint: Endpoint) async throws -> AttemptResponseDTO {
        let response = try await transport.send(endpoint, as: AttemptResponseDTO.self)
        guard !response.attemptId.isEmpty else {
            throw APIError.decoding(path: endpoint.path)
        }
        return response
    }

    // MARK: - 音频字节

    /// `GET /audio/:id` → 录音字节（回放由 AudioPlayer 负责）。
    func audioData(audioId: String) async throws -> Data {
        let endpoint = Endpoint(
            method: .get,
            path: "audio/\(audioId)",
            timeout: Self.ttsTimeout,
            authPolicy: .bearer
        )
        let data = try await transport.sendData(endpoint)
        guard !data.isEmpty else {
            throw APIError.decoding(path: "audio")
        }
        return data
    }

    // MARK: - TTS

    /// `POST /tts` → 音频字节。`voice == nil` 时用服务端默认音色；
    /// 失败时服务端返回 JSON 错误体，`sendData` 已按状态码抛错，不会把错误体当音频。
    func synthesize(text: String, rate: TTSRate, voice: String?, format: TTSFormat) async throws -> Data {
        let body = PracticeTTSRequest(
            text: text,
            rate: rate.rawValue,
            format: format.rawValue,
            voice: normalizedVoice(voice)
        )
        let data = try ECJSON.encode(body, path: "tts")
        let endpoint = Endpoint(
            method: .post,
            path: "tts",
            body: .json(data),
            timeout: Self.ttsTimeout,
            authPolicy: .bearer
        )
        let audio = try await transport.sendData(endpoint)
        guard audio.count >= Self.minAudioBytes else {
            throw APIError.decoding(path: "tts")
        }
        return audio
    }

    /// `POST /warmup` —— fire-and-forget 预热示范音，失败静默（不向 UI 抛错、也不阻塞调用方）。
    /// HOS 只预热前 12 句，避免一次请求过大；请求用非结构化 Task 发，方法立即返回。
    func warmup(texts: [String], rate: TTSRate) async {
        let limited = Array(texts.prefix(12))
        guard !limited.isEmpty else {
            return
        }
        let body = PracticeWarmupRequest(texts: limited, rate: rate.rawValue)
        guard let data = try? ECJSON.encode(body, path: "warmup") else {
            return
        }
        let endpoint = Endpoint(
            method: .post,
            path: "warmup",
            body: .json(data),
            timeout: Self.ttsTimeout,
            authPolicy: .bearer
        )
        let transport = self.transport
        Task {
            _ = try? await transport.sendData(endpoint)
        }
    }

    // MARK: - 健康检查

    /// `GET /health`（无需登录，超时 5s，与 HOS 一致）。
    func health() async throws -> HealthDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "health",
            timeout: Self.healthTimeout,
            authPolicy: .none
        )
        return try await transport.send(endpoint, as: HealthDTO.self)
    }

    // MARK: - 内部

    private func normalizedVoice(_ voice: String?) -> String? {
        guard let voice else {
            return nil
        }
        let trimmed = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - 请求体

private struct PracticeTTSRequest: Encodable {
    let text: String
    let rate: String
    let format: String
    let voice: String?
}

private struct PracticeWarmupRequest: Encodable {
    let texts: [String]
    let rate: String
}

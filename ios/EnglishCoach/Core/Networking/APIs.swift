import Foundation

// 领域 API 薄包装：Store 只依赖这些类型，便于以后替换成 fake。

struct AuthAPI: Sendable {
    let transport: APITransport

    func token(email: String, password: String) async throws -> AuthTokenResponse {
        let endpoint = try Endpoint.authToken(email: email, password: password)
        return try await transport.send(endpoint, as: AuthTokenResponse.self)
    }

    func refresh(refreshToken: String) async throws -> AuthTokenResponse {
        let endpoint = try Endpoint.authRefresh(refreshToken: refreshToken)
        return try await transport.send(endpoint, as: AuthTokenResponse.self)
    }

    /// `/auth/me` 在 Bearer 失效时返回 **200 `{user:null}`**，不是 401，必须显式转成 `.unauthorized`。
    func me() async throws -> UserProfile {
        let response = try await transport.send(Endpoint.me(), as: MeResponse.self)
        guard let user = response.user else {
            throw APIError.unauthorized
        }
        return user
    }

    func revoke(refreshToken: String) async throws {
        let endpoint = try Endpoint.authRevoke(refreshToken: refreshToken)
        _ = try await transport.sendData(endpoint)
    }
}

struct SentenceAPI: Sendable {
    let transport: APITransport

    func list(level: String) async throws -> [Sentence] {
        let response = try await transport.send(Endpoint.sentences(level: level), as: SentencesResponse.self)
        return response.sentences
    }
}

struct AttemptAPI: Sendable {
    static let maxAudioBytes = 12 * 1024 * 1024
    let transport: APITransport

    func submit(
        audioData: Data,
        filename: String = "recording.m4a",
        mimeType: String = "audio/mp4",
        sentenceID: String,
        referenceText: String,
        mode: AttemptMode = .scripted,
        durationMs: Int
    ) async throws -> AttemptResponse {
        // 12MB 是服务端契约；客户端预检，不依赖 413。
        guard audioData.count <= Self.maxAudioBytes else {
            throw APIError.payloadTooLarge(localBytes: audioData.count)
        }
        let endpoint = Endpoint.attempt(
            audioData: audioData,
            filename: filename,
            mimeType: mimeType,
            sentenceID: sentenceID,
            referenceText: referenceText,
            mode: mode,
            durationMs: durationMs
        )
        return try await transport.send(endpoint, as: AttemptResponse.self)
    }
}

struct TTSAPI: Sendable {
    let transport: APITransport

    func synthesize(text: String, rate: TTSRate, format: TTSFormat = .wav) async throws -> Data {
        let endpoint = try Endpoint.tts(text: text, rate: rate, format: format)
        let data = try await transport.sendData(endpoint)
        guard !data.isEmpty else {
            throw APIError.decoding(path: "tts")
        }
        return data
    }
}

struct HealthAPI: Sendable {
    let transport: APITransport

    /// 登录页“测试连接”：只要 2xx 即认为后端可达；body 结构不参与判断。
    func ping() async throws {
        _ = try await transport.sendData(Endpoint.health())
    }
}

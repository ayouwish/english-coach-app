import Foundation

/// 连读域 API：异步评测提交、状态轮询、批次诊断。
/// 职责边界：只拼端点 / 转 DTO / 返回 DTO；不落盘、不轮询、不持有页面状态。
///
/// 后端实况（HOS `FlowService` 头注释 + `docs/android-feature-list.md`）：
/// `/attempts/async`、`/attempts/status`、`/diagnosis?scope=batch` 存在；
/// `/sentences/:id/attempts`、`/practice/cursor` 线上不存在，本服务不调用。
struct FlowService: Sendable {
    let transport: APITransport

    /// 列表 / 状态 / 诊断 15s；异步上传 60s（HOS UPLOAD）。
    private static let shortTimeout: TimeInterval = 15
    private static let uploadTimeout: TimeInterval = 60
    /// 状态轮询给足 20s（批量评分期间服务端可能变慢，HOS 用 15s）。
    private static let statusTimeout: TimeInterval = 20
    /// 服务端硬限制：单段音频 ≤ 12MB；客户端预检，不依赖 413。
    private static let maxAudioBytes = 12 * 1024 * 1024
    /// `/attempts/status` 最多 50 个 id。
    private static let statusIdLimit = 50
    /// `/diagnosis?scope=batch` 最多 20 个 id（服务端硬限制）。
    private static let batchIdLimit = 20

    // MARK: - 异步提交

    /// `POST /attempts/async`（multipart）—— 录完即走。
    /// 字段顺序按 HOS：audio → reference_text → mode → duration_ms → source，
    /// `sentence_id` / `material_id` 只在非空时追加。
    func submitAsync(
        audioData: Data,
        referenceText: String,
        sentenceId: String,
        source: String,
        materialId: String?,
        durationMs: Int
    ) async throws -> AsyncSubmitDTO {
        guard audioData.count <= Self.maxAudioBytes else {
            throw APIError.payloadTooLarge(localBytes: audioData.count)
        }
        var builder = MultipartFormDataBuilder()
        builder.addFile(name: "audio", filename: "recording.m4a", mimeType: "audio/mp4", data: audioData)
        builder.addField(name: "reference_text", value: referenceText)
        builder.addField(name: "mode", value: AttemptMode.scripted.rawValue)
        builder.addField(name: "duration_ms", value: String(durationMs))
        builder.addField(name: "source", value: source)
        if !sentenceId.isEmpty {
            builder.addField(name: "sentence_id", value: sentenceId)
        }
        if let materialId, !materialId.isEmpty {
            builder.addField(name: "material_id", value: materialId)
        }
        let endpoint = Endpoint(
            method: .post,
            path: "attempts/async",
            body: .multipart(builder.finalize()),
            timeout: Self.uploadTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: AsyncSubmitDTO.self)
    }

    // MARK: - 状态轮询

    /// `GET /attempts/status?ids=a,b,c` —— 最多 50 个 id；空入参直接返回空列表（不发请求）。
    func status(ids: [String]) async throws -> [AsyncStatusItemDTO] {
        guard !ids.isEmpty else {
            return []
        }
        let limited = Array(ids.prefix(Self.statusIdLimit))
        let endpoint = Endpoint(
            method: .get,
            path: "attempts/status",
            query: [URLQueryItem(name: "ids", value: limited.joined(separator: ","))],
            timeout: Self.statusTimeout,
            authPolicy: .bearer
        )
        let response = try await transport.send(endpoint, as: AsyncStatusDTO.self)
        return response.items ?? []
    }

    // MARK: - 批次诊断

    /// `GET /diagnosis?scope=batch&attempt_ids=a,b,c` —— 连读汇总页「这一批的问题」（≤20）。
    func diagnosisBatch(attemptIds: [String]) async throws -> FlowDiagnosisDTO {
        let limited = Array(attemptIds.prefix(Self.batchIdLimit))
        let endpoint = Endpoint(
            method: .get,
            path: "diagnosis",
            query: [
                URLQueryItem(name: "scope", value: "batch"),
                URLQueryItem(name: "attempt_ids", value: limited.joined(separator: ","))
            ],
            timeout: Self.shortTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: FlowDiagnosisDTO.self)
    }
}

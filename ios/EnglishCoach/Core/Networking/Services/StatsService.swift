import Foundation

/// 统计域 API：发音诊断（4 个 scope）、错音本 SRS、盲测、健康检查全字段。
/// 职责边界：只拼端点 / 转 DTO；不持有页面状态、不弹提示。
///
/// 超时按 HOS `core/service/StatsService.ets`：普通 JSON 15s、写操作 30s、健康检查 5s。
struct StatsService: Sendable {
    let transport: APITransport

    private static let shortTimeout: TimeInterval = 15
    private static let postTimeout: TimeInterval = 30
    private static let healthTimeout: TimeInterval = 5
    /// `/review?limit=` 服务端上限 50，默认 20。
    private static let reviewDefaultLimit = 20
    private static let reviewMaxLimit = 50
    /// `/diagnosis?scope=batch` 最多 20 个 id（服务端超限会 400 invalid_scope）。
    private static let batchIdLimit = 20

    // MARK: - 诊断

    /// `GET /diagnosis?scope=all|recent|attempt|batch`。
    /// - `recent` 需要 `days`（默认 7，上限 365）；
    /// - `batch` 需要 `attempt_ids`（≤20）；
    /// - `attempt` 需要单个 `attempt_id`——契约 §3.7 的签名只给了 `attemptIds`，
    ///   因此这里取第一个元素作为 `attempt_id`（B4 调用方传 `[attemptId]` 即可）。
    func diagnosis(scope: String, days: Int, attemptIds: [String]) async throws -> DiagnosisResponseDTO {
        var query = [URLQueryItem(name: "scope", value: scope)]
        switch scope {
        case "recent":
            var window = days
            if window < 1 {
                window = 7
            }
            if window > 365 {
                window = 365
            }
            query.append(URLQueryItem(name: "days", value: String(window)))
        case "attempt":
            guard let attemptId = attemptIds.first, !attemptId.isEmpty else {
                throw APIError.server(code: .badRequest, message: nil, status: 0)
            }
            query.append(URLQueryItem(name: "attempt_id", value: attemptId))
        case "batch":
            let limited = Array(attemptIds.prefix(Self.batchIdLimit))
            guard !limited.isEmpty else {
                throw APIError.server(code: .badRequest, message: nil, status: 0)
            }
            query.append(URLQueryItem(name: "attempt_ids", value: limited.joined(separator: ",")))
        default:
            break
        }
        let endpoint = Endpoint(
            method: .get,
            path: "diagnosis",
            query: query,
            timeout: Self.shortTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: DiagnosisResponseDTO.self)
    }

    // MARK: - 错音本

    /// `GET /review?limit=N`（N 上限 50，默认 20）。
    func review(limit: Int) async throws -> ReviewResponseDTO {
        var count = limit
        if count < 1 {
            count = Self.reviewDefaultLimit
        }
        if count > Self.reviewMaxLimit {
            count = Self.reviewMaxLimit
        }
        let endpoint = Endpoint(
            method: .get,
            path: "review",
            query: [URLQueryItem(name: "limit", value: String(count))],
            timeout: Self.shortTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: ReviewResponseDTO.self)
    }

    /// SRS 评分：`POST /review {card_id, grade}`，`grade ∈ again | hard | good | easy`。
    ///
    /// 注意：契约 §3.7 注释写的是 `POST review/:id/grade`，但 HOS 实现、Android 移植与
    /// `docs/android-feature-list.md` §2.8 三处一致记录为 **`POST /review` + `{card_id, grade}`**
    /// 请求体，线上以 HOS 为准。
    func gradeReview(cardId: String, grade: String) async throws -> ReviewGradeResultDTO {
        let body = try ECJSON.encode(StatsGradeReviewRequest(cardId: cardId, grade: grade), path: "review")
        let endpoint = Endpoint(
            method: .post,
            path: "review",
            body: .json(body),
            timeout: Self.postTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: ReviewGradeResultDTO.self)
    }

    // MARK: - 盲测

    /// `GET /blind-tests`。契约签名不带 `user_id`（家长看孩子在账号域另行处理）。
    func blindTests() async throws -> BlindTestListDTO {
        let endpoint = Endpoint(
            method: .get,
            path: "blind-tests",
            timeout: Self.shortTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: BlindTestListDTO.self)
    }

    /// `POST /blind-tests`（空 body）。已有进行中的批次时服务端直接返回它（`resumed = true`）。
    func startBlindTest() async throws -> BlindTestStartDTO {
        let body = try ECJSON.encode(StatsEmptyRequest(), path: "blind-tests")
        let endpoint = Endpoint(
            method: .post,
            path: "blind-tests",
            body: .json(body),
            timeout: Self.postTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: BlindTestStartDTO.self)
    }

    /// `POST /blind-tests/:id/finish`（幂等）。
    func finishBlindTest(id: String) async throws -> BlindFinishDTO {
        let body = try ECJSON.encode(StatsEmptyRequest(), path: "blind-tests")
        let endpoint = Endpoint(
            method: .post,
            path: "blind-tests/\(id)/finish",
            body: .json(body),
            timeout: Self.postTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: BlindFinishDTO.self)
    }

    // MARK: - 健康检查（全字段）

    /// `GET /health[?force=1]`（无需登录，5s）。`force` 跳过服务端 15s 缓存；
    /// 健康页与 voice 降级判断都用它。与 `PracticeService.health()` 一样不注入 Bearer。
    func healthFull(force: Bool) async throws -> HealthFullDTO {
        var query: [URLQueryItem] = []
        if force {
            query.append(URLQueryItem(name: "force", value: "1"))
        }
        let endpoint = Endpoint(
            method: .get,
            path: "health",
            query: query,
            timeout: Self.healthTimeout,
            authPolicy: .none
        )
        return try await transport.send(endpoint, as: HealthFullDTO.self)
    }
}

// MARK: - 请求体

private struct StatsGradeReviewRequest: Encodable {
    let cardId: String
    let grade: String
}

private struct StatsEmptyRequest: Encodable {}

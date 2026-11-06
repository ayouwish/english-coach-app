import Foundation

// MARK: - 异步评测提交 / 轮询

/// `POST /attempts/async` → 201。普通提交与盲测提交共用，
/// 盲测响应只有 `attempt_id` / `blind` / `progress`（没有分数）。
struct AsyncSubmitDTO: Decodable, Sendable {
    let id: String?
    let attemptId: String?
    let blind: Bool?
    let status: String?
    let progress: BlindProgressDTO?
}

/// `GET /attempts/status?ids=a,b,c` 的单条状态。
/// `status`：pending | scoring | done | failed。
struct AsyncStatusItemDTO: Decodable, Sendable {
    let id: String
    let status: String
    let error: String?
    let scoredAt: String?
    let result: AsyncResultDTO?
}

/// `/attempts/status` 的 result：words 只有 word/score/start_ms/end_ms/error_type，
/// 没有音素明细（与同步评测不同）。
struct AsyncResultDTO: Decodable, Sendable {
    let scores: ScoresDTO?
    let words: [WordScoreDTO]?
    let issues: [IssueDTO]?
    let intonation: IntonationDTO?
    let feedback: FeedbackDTO?
    let recognizedText: String?
}

/// `GET /attempts/status` 外层。
struct AsyncStatusDTO: Decodable, Sendable {
    let items: [AsyncStatusItemDTO]?
}

// MARK: - 连读批次诊断（GET /diagnosis?scope=batch）

struct FlowDiagnosisCountsDTO: Decodable, Sendable {
    let weak: Int?
    let watch: Int?
    let ok: Int?
}

struct FlowDiagnosisTrendDTO: Decodable, Sendable {
    /// improving | flat | declining
    let direction: String?
    let delta: Double?
    /// 最近 3 次的分数点（可能缺失）
    let points: [Double]?
}

struct FlowDiagnosisErrorWordDTO: Decodable, Sendable {
    let word: String?
    let score: Double?
}

struct FlowDiagnosisContrastDTO: Decodable, Sendable {
    /// 儿童账号服务端会返回空串
    let phoneme: String?
    /// 已排序的对比音素对，例如 ["θ", "s"]
    let pair: [String]?
    let note: String?
}

/// 一个音素的诊断行。`status`：weak | watch | ok。
/// 儿童账号 `phoneme` 为空串（服务端已剥离 IPA），改用 `childLabel`。
struct FlowDiagnosisItemDTO: Decodable, Sendable {
    let phoneme: String?
    let childLabel: String?
    let focusToken: String?
    let status: String?
    let attempts: Int?
    let avgScore: Double?
    let lastScore: Double?
    let bestScore: Double?
    let trend: FlowDiagnosisTrendDTO?
    let errorWords: [FlowDiagnosisErrorWordDTO]?
    let practiceCount: Int?
    let tipZh: String?
    let tipChildZh: String?
    let commonErrors: [String]?
    let examples: [String]?
    let contrasts: [FlowDiagnosisContrastDTO]?
}

struct FlowDiagnosisRangeDTO: Decodable, Sendable {
    let scope: String?
    /// 本次参与统计的 attempt 数
    let attemptCount: Int?
    let attemptIds: [String]?
}

/// `GET /diagnosis?scope=batch&attempt_ids=a,b,c`（≤20）的响应。
struct FlowDiagnosisDTO: Decodable, Sendable {
    let generatedAt: String?
    let minSamples: Int?
    let totalPhonemes: Int?
    let countedPhonemes: Int?
    let counts: FlowDiagnosisCountsDTO?
    let summaryZh: String?
    let focusPhonemes: [String]?
    let items: [FlowDiagnosisItemDTO]?
    let scope: String?
    let range: FlowDiagnosisRangeDTO?
}

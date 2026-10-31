import Foundation

// MARK: - 枚举

enum TTSRate: String, Sendable, CaseIterable {
    case slow
    case normal
}

enum TTSFormat: String, Sendable {
    case wav
    case mp3
}

enum AttemptMode: String, Sendable {
    case scripted
    case unscripted
}

// MARK: - 认证

/// `POST /api/auth/token` 与 `/api/auth/refresh` 的响应。
/// refresh 不返回 user，因此 user 是可选的。
struct AuthTokenResponse: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let refreshExpiresIn: Int?
    let user: UserProfile?
}

/// `GET /api/auth/me` 真实返回 `{ user, usage }`；未认证时是 `{ user: null }`。
struct MeResponse: Decodable, Sendable {
    let user: UserProfile?
}

// MARK: - 语料

struct SentencesResponse: Decodable, Sendable {
    let sentences: [Sentence]
}

struct Sentence: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let text: String
    let translationZh: String?
    let level: String?
    let focusPhonemes: [String]
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case translationZh
        case level
        case focusPhonemes
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        translationZh = try container.decodeIfPresent(String.self, forKey: .translationZh)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        focusPhonemes = container.decodeStringArray(forKey: .focusPhonemes)
        tags = container.decodeStringArray(forKey: .tags)
    }
}

// MARK: - 评测

/// `POST /api/attempts` 的响应（web 自己的形状，不是 voice 契约）：
/// `{ attempt_id, degraded, retryable, message, result, feedback, usage }`。
/// `result == nil` 表示 voice 不可用但录音已入库，页面应显示“稍后重试”。
struct AttemptResponse: Decodable, Sendable {
    let attemptId: String?
    let degraded: Bool?
    let retryable: Bool?
    let message: String?
    let result: AttemptResult?
    let feedback: AttemptFeedback?

    enum CodingKeys: String, CodingKey {
        case attemptId
        case degraded
        case retryable
        case message
        case result
        case feedback
    }
}

struct AttemptResult: Decodable, Sendable {
    let scores: PronounceScores?
    let words: [WordScore]?
    let issues: [PronounceIssue]?
    let recognizedText: String?

    enum CodingKeys: String, CodingKey {
        case scores
        case words
        case issues
        case recognizedText
    }
}

struct PronounceScores: Decodable, Sendable, Equatable {
    let pron: Double?
    let accuracy: Double?
    let fluency: Double?
    let completeness: Double?
    let prosody: Double?
}

struct WordScore: Decodable, Sendable, Identifiable {
    let word: String
    let score: Double?
    let errorType: String?

    var id: String { word }

    enum CodingKeys: String, CodingKey {
        case word
        case score
        case errorType
    }
}

struct PronounceIssue: Decodable, Sendable {
    let type: String?
    let severity: String?
    let word: String?
    let phoneme: String?
    let score: Double?
}

struct AttemptFeedback: Decodable, Sendable {
    let summary: String?
    let praise: String?
    let closing: String?
    let points: [FeedbackPoint]?
}

struct FeedbackPoint: Decodable, Sendable {
    let title: String?
    let why: String?
    let how: String?
}

// MARK: - 解码辅助

private extension KeyedDecodingContainer {
    /// 后端 `focus_phonemes` / `tags` 实际是数组，但也兼容逗号分隔字符串，
    /// 避免一次字段类型调整就让整页解码失败。
    func decodeStringArray(forKey key: Key) -> [String] {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values
        }
        if let raw = try? decodeIfPresent(String.self, forKey: key) {
            return raw
                .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "，" || $0 == "、" })
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}

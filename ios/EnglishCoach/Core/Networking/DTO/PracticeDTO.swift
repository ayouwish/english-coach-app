import Foundation

// MARK: - 枚举（服务端只接受字符串取值）

/// TTS 语速：服务端只接受 `slow` / `normal`。
enum TTSRate: String, Sendable, CaseIterable {
    case slow
    case normal
}

/// TTS 音频容器：服务端按请求合成 `wav` 或 `mp3`。
enum TTSFormat: String, Sendable {
    case wav
    case mp3
}

/// 评测模式：`scripted` = 照着参考文本读；`unscripted` = 自由说。
enum AttemptMode: String, Sendable {
    case scripted
    case unscripted
}

// MARK: - 语料

/// `GET /sentences`、`GET /sentences/:id` 的句子。
/// 儿童账号服务端会剥离 IPA（`focus_phonemes` 返回空数组），客户端不再二次处理。
///
/// `Codable`：除网络解码外还要被 `CorpusRepository` 的 24h 磁盘快照编码落盘（契约 §3.11）。
struct SentenceDTO: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let text: String
    let translationZh: String?
    let level: String?
    let focusPhonemes: [String]
    let tags: [String]
    let source: String?
    let ownerUserId: String?
    let mine: Bool?
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case translationZh
        case level
        case focusPhonemes
        case tags
        case source
        case ownerUserId
        case mine
        case sortOrder
    }

    /// 本地构造（故事详情把「故事句子」当作单句跟读的语料时用）。
    init(
        id: String,
        text: String,
        translationZh: String? = nil,
        level: String? = nil,
        focusPhonemes: [String] = [],
        tags: [String] = [],
        source: String? = nil,
        ownerUserId: String? = nil,
        mine: Bool? = nil,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.translationZh = translationZh
        self.level = level
        self.focusPhonemes = focusPhonemes
        self.tags = tags
        self.source = source
        self.ownerUserId = ownerUserId
        self.mine = mine
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        translationZh = try container.decodeIfPresent(String.self, forKey: .translationZh)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        focusPhonemes = container.decodeStringList(forKey: .focusPhonemes)
        tags = container.decodeStringList(forKey: .tags)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        ownerUserId = try container.decodeIfPresent(String.self, forKey: .ownerUserId)
        mine = try container.decodeIfPresent(Bool.self, forKey: .mine)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    }
}

/// `GET /sentences` 外层。`sentences` 缺失按空列表处理（调用方负责兜底）。
struct SentenceListDTO: Codable, Sendable {
    let level: String?
    let count: Int?
    let sentences: [SentenceDTO]?
    let userLevel: String?
    let officialCount: Int?
    let customCount: Int?
    let mineCount: Int?
}

// MARK: - 评测结果

/// 综合分 0–100；不可得为 `nil`（不是 0，页面必须区分）。
struct ScoresDTO: Decodable, Sendable, Equatable {
    let pron: Double?
    let accuracy: Double?
    let fluency: Double?
    let completeness: Double?
    let prosody: Double?
}

/// 单个词的发音分。同步评测（/attempts）的 `phonemes` 才有音素明细；
/// `/attempts/status` 返回的 words 不带 `phonemes`。
struct WordScoreDTO: Decodable, Sendable {
    let word: String
    let score: Double?
    let errorType: String?
    let startMs: Double?
    let endMs: Double?
    let phonemes: [PhonemeScoreDTO]?
}

/// 音素级得分与候选（nbest 仅部分 provider 提供）。
struct PhonemeScoreDTO: Decodable, Sendable {
    let phoneme: String?
    let score: Double?
    let startMs: Double?
    let endMs: Double?
    let nbest: [NBestDTO]?
}

struct NBestDTO: Decodable, Sendable {
    let phoneme: String?
    let score: Double?
}

/// 评测问题条目（提示文案由 `PhonemeHints` 按 `hintKey` 兜底）。
struct IssueDTO: Decodable, Sendable {
    let type: String?
    let severity: String?
    let word: String?
    let phoneme: String?
    let expected: String?
    let actual: String?
    let score: Double?
    let hintKey: String?
    let startMs: Double?
    let endMs: Double?
}

/// 语调曲线：`[time_ms, f0_hz|null]` 二元数组，20ms 步长、≤600 点，
/// `userF0` 与 `referenceF0` 已 DTW 对齐、同时间轴同长度。
struct F0Point: Decodable, Sendable, Equatable {
    let timeMs: Double
    let hz: Double?
}

extension F0Point {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        timeMs = try container.decode(Double.self)
        hz = try container.decodeIfPresent(Double.self)
    }
}

/// 语调整体信息。`available == false` 时其余字段通常缺失，图表应显示空态。
struct IntonationDTO: Decodable, Sendable {
    let available: Bool?
    let dtwDistance: Double?
    let userF0: [F0Point]?
    let referenceF0: [F0Point]?
    let worstRegions: [IntonationRegionDTO]?
    let referenceAudioUrl: String?
}

struct IntonationRegionDTO: Decodable, Sendable {
    let startMs: Int?
    let endMs: Int?
    let text: String?
    let issue: String?
    let userSlope: Double?
    let refSlope: Double?
}

/// voice 评测的原始结果（`AttemptResponseDTO.result`）。
struct PronounceResultDTO: Decodable, Sendable {
    let provider: String?
    let granularity: String?
    let mode: String?
    let referenceText: String?
    let recognizedText: String?
    let durationMs: Int?
    let scores: ScoresDTO?
    let words: [WordScoreDTO]?
    let issues: [IssueDTO]?
    let intonation: IntonationDTO?
    let warnings: [String]?
}

/// 服务端生成的学习反馈（`AttemptResponseDTO.feedback`）。
struct FeedbackDTO: Decodable, Sendable {
    let provider: String?
    let summary: String?
    let praise: String?
    let points: [FeedbackPointDTO]?
    let closing: String?
}

struct FeedbackPointDTO: Decodable, Sendable {
    let title: String?
    let why: String?
    let how: String?
    let practiceWords: [String]?
    let demoText: String?
    let severity: String?
}

/// 盲测进度（`POST /attempts` 带 `blind_test_id` 时返回）。
struct BlindProgressDTO: Decodable, Sendable, Equatable {
    let done: Int?
    let total: Int?
}

/// `POST /attempts`、`POST /attempts/:id/retry` 的响应。
/// `result == nil` 表示 voice 不可用但录音已入库（`degraded`），页面应提示稍后重试。
struct AttemptResponseDTO: Decodable, Sendable {
    let attemptId: String
    let blind: Bool?
    let degraded: Bool?
    let retryable: Bool?
    let message: String?
    let result: PronounceResultDTO?
    let feedback: FeedbackDTO?
    let usage: UsageDTO?
    let progress: BlindProgressDTO?
}

/// 历史评测记录（`GET /attempts`、`GET /sentences/:id/attempts` 的元素）。
struct AttemptItemDTO: Decodable, Sendable, Identifiable {
    let id: String
    let sentenceId: String?
    let mode: String?
    let referenceText: String?
    let blind: Bool?
    let blindTestId: String?
    let pending: Bool?
    let recognizedText: String?
    let scores: ScoresDTO?
    let issues: [IssueDTO]?
    let intonation: IntonationDTO?
    let feedback: FeedbackDTO?
    let audioUrl: String?
    let refAudioUrl: String?
    let durationMs: Int?
    let warnings: [String]?
    let createdAt: String?
}

/// `GET /attempts` 外层。
struct AttemptListDTO: Decodable, Sendable {
    let attempts: [AttemptItemDTO]?
}

// MARK: - 健康检查（登录页“测试连接”用简化版）

struct HealthDTO: Decodable, Sendable {
    let status: String?
    let service: String?
    let version: String?
    let time: String?
    let db: HealthDbDTO?
    let voice: HealthVoiceDTO?
}

struct HealthVoiceDTO: Decodable, Sendable {
    let reachable: Bool?
    let mode: String?
    let capabilities: HealthCapabilitiesDTO?
    let hint: String?
}

struct HealthCapabilitiesDTO: Decodable, Sendable {
    let phonemeLevel: Bool?
    let prosody: Bool?
    let intonationCurve: Bool?
    let nbestPhonemes: Bool?
    let ssml: Bool?
    let ocr: Bool?
    let image: Bool?
    let imageProvider: String?
    let imageAvatar: Bool?
    let avatarPresets: Bool?
    let audioConcat: Bool?
    let wordIpa: Bool?
    let asrProviders: [String]?
    let chatDoneTurnIndex: Int?
}

struct HealthDbDTO: Decodable, Sendable {
    let ok: Bool?
    let error: String?
}

// MARK: - 音色 / OCR

/// `GET /tts/voices` 线上 404，9 个内置音色以 `MediaService.voicesConst` 为准；
/// 该结构用于未来服务端返回音色清单时的解码兼容。
struct TtsVoiceDTO: Decodable, Sendable, Equatable {
    let id: String
    let labelZh: String?
    let lang: String?
    let sample: String?
}

/// `POST /ocr` 的书页文字识别结果（`MediaService.ocr`）。
struct OCRResultDTO: Decodable, Sendable {
    let provider: String?
    let text: String?
    let lines: [String]?
    let width: Int?
    let height: Int?
    let elapsedMs: Int?
    let warnings: [String]?
    let imageJpegB64: String?
}

// MARK: - 解码辅助

private extension KeyedDecodingContainer {
    /// `focus_phonemes` / `tags` 服务端是数组，也兼容逗号分隔字符串；
    /// 字段缺失或类型漂移时返回空数组，避免一整个列表解不出来。
    func decodeStringList(forKey key: Key) -> [String] {
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

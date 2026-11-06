import Foundation

// MARK: - 发音诊断（GET /diagnosis）

struct DiagnosisCountsDTO: Decodable, Sendable {
    let weak: Int?
    let watch: Int?
    let ok: Int?
}

struct DiagnosisTrendDTO: Decodable, Sendable {
    /// improving | flat | declining
    let direction: String?
    let delta: Double?
    let points: [Double]?
}

struct DiagnosisErrorWordDTO: Decodable, Sendable {
    let word: String?
    let score: Double?
}

struct DiagnosisContrastDTO: Decodable, Sendable {
    /// 儿童为空串
    let phoneme: String?
    /// 已跨音素全局去重并排序
    let pair: [String]?
    let note: String?
}

/// 一个音素的诊断行。`status`：weak（avg<65）/ watch（65–80）/ ok（≥80）。
/// 儿童账号 `phoneme` 为空串，改用 `childLabel`；`commonErrors` 也被服务端剥离。
struct DiagnosisItemDTO: Decodable, Sendable {
    let phoneme: String?
    let childLabel: String?
    let focusToken: String?
    let status: String?
    let attempts: Int?
    let avgScore: Double?
    let lastScore: Double?
    let bestScore: Double?
    let trend: DiagnosisTrendDTO?
    let errorWords: [DiagnosisErrorWordDTO]?
    let practiceCount: Int?
    let tipZh: String?
    let tipChildZh: String?
    let commonErrors: [String]?
    let examples: [String]?
    let contrasts: [DiagnosisContrastDTO]?
}

struct DiagnosisRangeDTO: Decodable, Sendable {
    let scope: String?
    let attemptCount: Int?
    let attemptIds: [String]?
}

/// `GET /diagnosis?scope=all|recent|attempt|batch` 的响应。
struct DiagnosisResponseDTO: Decodable, Sendable {
    let generatedAt: String?
    let minSamples: Int?
    let totalPhonemes: Int?
    let countedPhonemes: Int?
    let counts: DiagnosisCountsDTO?
    let summaryZh: String?
    let focusPhonemes: [String]?
    let items: [DiagnosisItemDTO]?
    let scope: String?
    let range: DiagnosisRangeDTO?
}

// MARK: - 错音本 / SRS（GET /review、POST /review）

struct ReviewStatsDTO: Decodable, Sendable {
    let totalCards: Int?
    let dueCards: Int?
    let phonemeRows: Int?
    let phonemeLevel: Bool?
    let voiceReachable: Bool?
}

struct ReviewDisplayDTO: Decodable, Sendable {
    let text: String?
}

/// 一张 SRS 卡片。儿童：`phoneme == nil`、`ref == ""`，只显示 label/whyZh/howZh。
struct ReviewCardDTO: Decodable, Sendable, Identifiable {
    let id: String
    /// phoneme | word | sentence
    let kind: String?
    let ref: String?
    let dueAt: String?
    let ease: Double?
    let intervalDays: Int?
    let reps: Int?
    let lapses: Int?
    let lastGrade: String?
    let isPhoneme: Bool?
    let phoneme: String?
    let hintKey: String?
    let label: String?
    let whyZh: String?
    let howZh: String?
    let practiceWords: [String]?
    let demoText: String?
    let display: ReviewDisplayDTO?
}

struct ReviewWeakPhonemeTrendDTO: Decodable, Sendable {
    let t: String?
    let s: Double?
}

struct ReviewWeakPhonemeDTO: Decodable, Sendable {
    let phoneme: String?
    let hintKey: String?
    let attempts: Int?
    let avgScore: Double?
    let bestScore: Double?
    let lastScore: Double?
    let trend: [ReviewWeakPhonemeTrendDTO]?
    let label: String?
}

struct ReviewWordErrorDTO: Decodable, Sendable {
    let word: String?
    let count: Int?
    let avgScore: Double?
    let coarse: Bool?
}

struct ReviewGradeDTO: Decodable, Sendable {
    /// again | hard | good | easy
    let grade: String
    let labelZh: String?
}

/// `GET /review?limit=N` 的响应。
struct ReviewResponseDTO: Decodable, Sendable {
    let now: String?
    let stats: ReviewStatsDTO?
    let dueCards: [ReviewCardDTO]?
    let weakPhonemes: [ReviewWeakPhonemeDTO]?
    let wordLevelErrors: [ReviewWordErrorDTO]?
    let grades: [ReviewGradeDTO]?
}

/// `POST /review {card_id, grade}` 的响应。
struct ReviewGradeResultDTO: Decodable, Sendable {
    let cardId: String?
    let grade: String?
    let nextDueAt: String?
    let intervalDays: Int?
    let ease: Double?
    let reps: Int?
    let lapses: Int?
}

// MARK: - 盲测（/blind-tests）

struct BlindTestDTO: Decodable, Sendable, Identifiable {
    let id: String
    let userId: String?
    let startedAt: String?
    let endedAt: String?
    let itemCount: Int?
    let avgPron: Double?
    let avgAccuracy: Double?
    let avgFluency: Double?
    let avgIntonationDistance: Double?
    let sentenceIds: [String]?
    /// 异步评分进度（tests[] / in_progress 都额外带这两个字段）
    let scored: Int?
    let pending: Int?
}

struct BlindTestStartDTO: Decodable, Sendable {
    let blindTestId: String
    let sentenceIds: [String]?
    let total: Int?
    /// true = 复用了进行中的批次（HTTP 200）；false = 新建（201）
    let resumed: Bool?
    let startedAt: String?
}

struct BlindTrendScoreDTO: Decodable, Sendable {
    let blindTestId: String?
    let endedAt: String?
    let avgPron: Double?
    let avgAccuracy: Double?
    let avgFluency: Double?
    let avgIntonationDistance: Double?
    let itemCount: Int?
}

struct BlindTrendDTO: Decodable, Sendable {
    let current: BlindTrendScoreDTO?
    let previous: BlindTrendScoreDTO?
    let deltaPron: Double?
    let deltaAccuracy: Double?
    let deltaFluency: Double?
    let deltaIntonationDistance: Double?
    /// 已完成批次数
    let weeks: Int?
}

/// `GET /blind-tests` 的响应。
struct BlindTestListDTO: Decodable, Sendable {
    let userId: String?
    let tests: [BlindTestDTO]?
    let inProgress: BlindTestDTO?
    let pendingTotal: Int?
    let trend: BlindTrendDTO?
    /// 按时间正序（画柱状图用）
    let series: [BlindTrendScoreDTO]?
}

/// `POST /blind-tests/:id/finish` 的响应。`notice` 只有全评完才是 nil；
/// 有值时必须展示黄条提示。
struct BlindFinishDTO: Decodable, Sendable {
    let blindTestId: String?
    let userId: String?
    let startedAt: String?
    let endedAt: String?
    let itemCount: Int?
    let submitted: Int?
    let scored: Int?
    let pending: Int?
    let notice: String?
    let avgPron: Double?
    let avgAccuracy: Double?
    let avgFluency: Double?
    let avgIntonationDistance: Double?
    let previous: BlindTrendScoreDTO?
    let deltaPron: Double?
    let deltaAccuracy: Double?
    let deltaFluency: Double?
    let deltaIntonationDistance: Double?
}

// MARK: - 健康检查全字段（GET /health，健康页 / 降级判断）

struct HealthFeaturesDTO: Decodable, Sendable {
    let chatUnlimitedTurns: Bool?
    let chatAudioReplay: Bool?
    let chatScenariosAudience: Bool?
    let avatarPresets: Bool?
    let storyMode: Bool?
    let asyncScoring: Bool?
}

struct HealthCapabilitiesFullDTO: Decodable, Sendable {
    let phonemeLevel: Bool?
    let prosody: Bool?
    let intonationCurve: Bool?
    let nbestPhonemes: Bool?
    let ssml: Bool?
    let gpu: Bool?
    let ocr: Bool?
    let ocrProvider: String?
    let heic: Bool?
    let image: Bool?
    let imageProvider: String?
    /// false = 照片生成形象已按隐私策略关闭（客户端隐藏入口）
    let imageAvatar: Bool?
    let avatarPresets: Bool?
    let audioConcat: Bool?
    let chatDoneTurnIndex: Int?
    /// voice 侧已实现的端点清单（排障用）
    let features: [String]?
}

struct HealthVoiceFullDTO: Decodable, Sendable {
    let reachable: Bool?
    /// hybrid | cloud | local | unreachable
    let mode: String?
    /// 服务端容器内地址，不是客户端可用地址
    let url: String?
    let capabilities: HealthCapabilitiesFullDTO?
    let hint: String?
}

/// `GET /health[?force=1]` 全字段。`status`：ok | degraded（只看 DB；voice 挂了仍是 ok）。
struct HealthFullDTO: Decodable, Sendable {
    let status: String?
    let service: String?
    let version: String?
    let time: String?
    let db: HealthDbDTO?
    let features: HealthFeaturesDTO?
    let voice: HealthVoiceFullDTO?
}

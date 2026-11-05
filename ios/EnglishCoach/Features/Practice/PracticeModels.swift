import Foundation

// MARK: - 等级

/// 跟读/连读的等级集合与 CEFR 映射（对齐 HOS `AppConfig.levelForCefr`：
/// 服务端没有 C1 语料，C1 回退 B2；其余非法值回退 A1）。
enum PracticeLevels {
    static let all: [String] = ["A1", "A2", "B1", "B2"]

    static func normalized(_ level: String) -> String {
        let upper = level.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if all.contains(upper) {
            return upper
        }
        if upper == "C1" {
            return "B2"
        }
        return "A1"
    }
}

// MARK: - 结果模型（与 DTO 解耦，页面只渲染这些）

/// 四个维度 + 综合分；nil = 服务端没给（展示「—」，不是 0）。
struct PracticeScores: Hashable, Sendable {
    var pron: Double?
    var accuracy: Double?
    var fluency: Double?
    var completeness: Double?
    var prosody: Double?

    static let empty = PracticeScores(
        pron: nil,
        accuracy: nil,
        fluency: nil,
        completeness: nil,
        prosody: nil
    )

    var hasAny: Bool {
        [pron, accuracy, fluency, completeness, prosody].contains { $0 != nil }
    }
}

/// 逐词得分（同步评测 `/attempts` 才有；`/attempts/status` 与历史记录没有）。
struct PracticeWordScore: Identifiable, Hashable, Sendable {
    let id: Int
    let word: String
    let score: Double?
    let errorType: String?
}

/// 音素明细 chips（仅成人展示；儿童服务端已剥离 IPA）。
struct PracticePhonemeChip: Identifiable, Hashable, Sendable {
    let id: Int
    let phoneme: String
    let score: Double?
}

/// 「需要纠正的地方」卡片（文案取自 `PhonemeHints`，成人版）。
struct PracticeIssueCard: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let word: String
    let expected: String
    let actual: String
    let score: Double?
    let why: String
    let how: String
    let practiceWords: String
}

struct PracticeFeedbackPoint: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let why: String
    let how: String
    let practiceWords: String
}

struct PracticeFeedback: Hashable, Sendable {
    var summary: String
    var praise: String
    var closing: String
    var points: [PracticeFeedbackPoint]

    static let empty = PracticeFeedback(summary: "", praise: "", closing: "", points: [])
}

/// 语调数据（已 DTW 对齐的两条曲线 + 最差区间的人话说明）。
struct PracticeIntonation: Hashable, Sendable {
    var available: Bool
    var dtwDistance: String
    var user: [PitchPoint]
    var reference: [PitchPoint]
    var regionTexts: [String]

    static let unavailable = PracticeIntonation(
        available: false,
        dtwDistance: "",
        user: [],
        reference: [],
        regionTexts: []
    )
}

/// 一次评测的完整页面模型（页内结果 + 详细结果页共用）。
struct PracticeAttemptResult: Identifiable, Hashable, Sendable {
    /// 与 `attemptId` 同值，供 SwiftUI `Identifiable` 使用。
    var id: String { attemptId }

    let attemptId: String
    let sentenceId: String
    let referenceText: String
    let recognizedText: String
    let scores: PracticeScores
    let words: [PracticeWordScore]
    let phonemes: [PracticePhonemeChip]
    let issues: [PracticeIssueCard]
    let feedback: PracticeFeedback
    let intonation: PracticeIntonation
    let provider: String
    let granularity: String
    let durationMs: Int?
    let createdAt: String?
    let degraded: Bool
    let retryable: Bool

    var noSpeech: Bool {
        recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
    }

    var durationText: String {
        guard let durationMs, durationMs > 0 else { return "" }
        return String(format: "%.1fs", Double(durationMs) / 1000)
    }

    /// 低于 60 分的词数（详细结果页提示文案用；列表只展示一遍）。
    var weakWordCount: Int {
        words.reduce(into: 0) { count, word in
            guard let score = word.score, score < 60 else { return }
            count += 1
        }
    }
}

/// 单句历史的一次朗读（进步曲线 + 回放）。
struct PracticeHistoryEntry: Identifiable, Hashable, Sendable {
    var id: String { attemptId }
    let attemptId: String
    let score: Double
    let label: String
}

/// 点词音标浮层的内容（系统 sheet 展示，不在组件里发请求）。
struct PracticeIPASheet: Identifiable, Equatable, Sendable {
    let id = UUID()
    let word: String
    let ipa: String?
    let variants: [String]
    let note: String?

    static func == (lhs: PracticeIPASheet, rhs: PracticeIPASheet) -> Bool {
        lhs.word == rhs.word && lhs.ipa == rhs.ipa && lhs.variants == rhs.variants
    }
}

// MARK: - DTO → 页面模型

/// 服务端评测结果 → 页面模型。文案兜底（`PhonemeHints` / 四舍五入）都在这里，
/// 页面不直接碰 DTO。
enum PracticeResultMapper {

    /// 同步评测响应。`result == nil`（degraded）时返回 nil，由 Store 转成提示。
    static func make(response: AttemptResponseDTO, sentenceId: String) -> PracticeAttemptResult? {
        guard let result = response.result, !response.attemptId.isEmpty else { return nil }
        return PracticeAttemptResult(
            attemptId: response.attemptId,
            sentenceId: sentenceId,
            referenceText: result.referenceText ?? "",
            recognizedText: result.recognizedText ?? "",
            scores: scores(from: result.scores),
            words: words(from: result.words),
            phonemes: phonemes(from: result.words),
            issues: issues(from: result.issues),
            feedback: feedback(from: response.feedback),
            intonation: intonation(from: result.intonation),
            provider: result.provider ?? "",
            granularity: result.granularity ?? "",
            durationMs: result.durationMs,
            createdAt: nil,
            degraded: response.degraded == true,
            retryable: response.retryable != false
        )
    }

    /// 历史记录（`/attempts`）。没有逐词/音素明细，无法拿到录音字节。
    static func make(item: AttemptItemDTO) -> PracticeAttemptResult? {
        guard item.pending != true, let itemScores = item.scores else { return nil }
        return PracticeAttemptResult(
            attemptId: item.id,
            sentenceId: item.sentenceId ?? "",
            referenceText: item.referenceText ?? "",
            recognizedText: item.recognizedText ?? "",
            scores: scores(from: itemScores),
            words: [],
            phonemes: [],
            issues: issues(from: item.issues),
            feedback: feedback(from: item.feedback),
            intonation: intonation(from: item.intonation),
            provider: "",
            granularity: "",
            durationMs: item.durationMs,
            createdAt: item.createdAt,
            degraded: false,
            retryable: false
        )
    }

    // MARK: 字段映射

    private static func scores(from dto: ScoresDTO?) -> PracticeScores {
        guard let dto else { return .empty }
        return PracticeScores(
            pron: dto.pron,
            accuracy: dto.accuracy,
            fluency: dto.fluency,
            completeness: dto.completeness,
            prosody: dto.prosody
        )
    }

    private static func words(from dto: [WordScoreDTO]?) -> [PracticeWordScore] {
        (dto ?? []).enumerated().map { index, word in
            PracticeWordScore(
                id: index,
                word: word.word,
                score: word.score,
                errorType: word.errorType
            )
        }
    }

    private static func phonemes(from dto: [WordScoreDTO]?) -> [PracticePhonemeChip] {
        var chips: [PracticePhonemeChip] = []
        for word in dto ?? [] {
            for phoneme in word.phonemes ?? [] {
                guard let symbol = phoneme.phoneme, !symbol.isEmpty else { continue }
                chips.append(
                    PracticePhonemeChip(
                        id: chips.count,
                        phoneme: symbol,
                        score: phoneme.score
                    )
                )
                if chips.count >= 40 {
                    return chips
                }
            }
        }
        return chips
    }

    private static func issues(from dto: [IssueDTO]?) -> [PracticeIssueCard] {
        var cards: [PracticeIssueCard] = []
        for issue in dto ?? [] {
            guard cards.count < 3 else { break }
            let phoneme = issue.phoneme ?? ""
            let expected = issue.expected ?? ""
            let lookup = expected.isEmpty ? phoneme : expected
            guard !lookup.isEmpty || issue.word != nil else { continue }
            let hint = PhonemeHints.byPhoneme(lookup)
            cards.append(
                PracticeIssueCard(
                    id: cards.count,
                    title: hint.titleZh,
                    word: issue.word ?? "",
                    expected: expected,
                    actual: issue.actual ?? "",
                    score: issue.score,
                    why: hint.whyZh,
                    how: hint.howZh,
                    practiceWords: hint.words.joined(separator: " · ")
                )
            )
        }
        return cards
    }

    private static func feedback(from dto: FeedbackDTO?) -> PracticeFeedback {
        guard let dto else { return .empty }
        let points = (dto.points ?? []).prefix(2).enumerated().map { index, point in
            PracticeFeedbackPoint(
                id: index,
                title: point.title ?? "",
                why: point.why ?? "",
                how: point.how ?? "",
                practiceWords: (point.practiceWords ?? []).joined(separator: " · ")
            )
        }
        return PracticeFeedback(
            summary: dto.summary ?? "",
            praise: dto.praise ?? "",
            closing: dto.closing ?? "",
            points: Array(points)
        )
    }

    private static func intonation(from dto: IntonationDTO?) -> PracticeIntonation {
        guard let dto, dto.available == true else { return .unavailable }
        let user = ChartsData.pitchPoints(
            (dto.userF0 ?? []).map { (timeMs: $0.timeMs, hz: $0.hz) },
            limit: ChartsData.maxIntonationPoints
        )
        let reference = ChartsData.pitchPoints(
            (dto.referenceF0 ?? []).map { (timeMs: $0.timeMs, hz: $0.hz) },
            limit: ChartsData.maxIntonationPoints
        )
        let regions = (dto.worstRegions ?? []).prefix(2).map { region in
            let label = regionLabel(region.issue)
            let text = region.text ?? ""
            return text.isEmpty ? label : "\(label)（\(text)）"
        }
        return PracticeIntonation(
            available: !(user.isEmpty && reference.isEmpty),
            dtwDistance: dto.dtwDistance.map { String(format: "%.2f", $0) } ?? "",
            user: user,
            reference: reference,
            regionTexts: Array(regions)
        )
    }

    private static func regionLabel(_ issue: String?) -> String {
        switch issue ?? "" {
        case "expected_rise_but_flat": return "这里该升调却没升"
        case "expected_fall_but_flat": return "这里该降调却没降"
        case "wrong_direction": return "升降方向反了"
        case "stress_misplaced": return "重音位置偏了"
        case "monotone_overall": return "整体偏平"
        case "unexpected_pause": return "不该停的地方停了"
        default: return "语调可以更自然"
        }
    }
}

// MARK: - 练习游标（「继续上次」）

/// 本地记忆「上次练到哪一句」（HOS 用 Preferences；`/practice/cursor` 线上未部署）。
/// 键带 userId，避免共用设备串号；只存句子 id，不存任何音频/分数。
enum PracticeCursorStore {
    private static func key(level: String, userId: String) -> String {
        "practice_cursor|\(userId)|\(level)"
    }

    static func load(level: String, userId: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key(level: level, userId: userId))
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func save(sentenceId: String, level: String, userId: String) {
        guard !sentenceId.isEmpty else { return }
        UserDefaults.standard.set(sentenceId, forKey: key(level: level, userId: userId))
    }

    static func clear(level: String, userId: String) {
        UserDefaults.standard.removeObject(forKey: key(level: level, userId: userId))
    }
}

// MARK: - 跨页结果交接

/// 详细结果页的数据交接（HOS `PracticeResultStore` 的同语义实现）。
///
/// `AppRoute.practiceResult(attemptId:)` 只携带 id，而逐词/音素明细只有同步评测响应里才有
/// （`/attempts` 历史记录不含 words）。因此本次评测结果先在内存里交接给结果页；
/// 直达/冷启动时结果页再按 attemptId 从 `/attempts` 兜底拉取。
@MainActor
enum PracticeResultHandoff {
    private(set) static var latest: PracticeAttemptResult?
    private static var recordRequested = false

    static func store(_ result: PracticeAttemptResult) {
        latest = result
    }

    /// 取出与 `attemptId` 匹配的本次结果；`attemptId == nil` 时返回最近一次。
    static func result(matching attemptId: String?) -> PracticeAttemptResult? {
        guard let latest else { return nil }
        guard let attemptId, !attemptId.isEmpty else { return latest }
        return latest.attemptId == attemptId ? latest : nil
    }

    /// 结果页点「再读一遍」→ 回到跟读页后自动开录（HOS `requestRecord` 同语义）。
    static func requestRecord() {
        recordRequested = true
    }

    static func consumeRecordRequest() -> Bool {
        let value = recordRequested
        recordRequested = false
        return value
    }

    static func clear() {
        latest = nil
        recordRequested = false
    }
}

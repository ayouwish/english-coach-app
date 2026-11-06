import Foundation
import Observation

/// 错音本（SRS）状态：`GET /review` 拉卡片 + `POST /review {card_id, grade}` 提交评分。
///
/// 提交成功后按 HOS `ReviewVM` 的规则**本地移除该卡并把 due 数减一**（不重新拉列表），
/// 并提示下次复习时间；失败只做内联错误，不打断整页。
@MainActor
@Observable
final class ReviewStore {
    static let gradeKinds = ["again", "hard", "good", "easy"]

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore

    private(set) var response: ReviewResponseDTO?
    private(set) var cards: [ReviewCardDTO] = []
    private(set) var weakPhonemes: [ReviewWeakPhonemeDTO] = []
    private(set) var wordErrors: [ReviewWordErrorDTO] = []

    private(set) var totalCards = 0
    private(set) var dueCards = 0
    private(set) var phonemeRows = 0
    private(set) var phonemeLevel = true
    private(set) var voiceReachable = true

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var loadError: UIMessage?

    private(set) var gradingCardID: String?
    private(set) var gradeNotice: String?
    private(set) var gradeError: UIMessage?
    private(set) var isPreparingDemo = false

    let limit = 20

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
    }

    // MARK: - 派生

    var isChild: Bool {
        session.isChild
    }

    var capabilities: RoleCapabilities {
        session.capabilities
    }

    var hasAnyData: Bool {
        !cards.isEmpty || !weakPhonemes.isEmpty || !wordErrors.isEmpty || totalCards > 0
    }

    var minutesTodayText: String {
        guard let minutes = session.usage?.minutes, minutes.isFinite else {
            return "—"
        }
        return String(format: "%.1f", max(minutes, 0))
    }

    var algorithmText: String {
        var text = "排期算法：SM-2 简化版（again / hard / good / easy）。"
        if !phonemeLevel {
            text += "当前是单词级粗评（评测 provider 不支持音素级）。"
        }
        return text
    }

    // MARK: - 加载

    func load() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        loadError = nil
        do {
            let dto = try await services.stats.review(limit: limit)
            apply(dto)
            hasLoaded = true
        } catch {
            loadError = ErrorMapper.message(for: error, isChild: isChild)
            hasLoaded = true
        }
        isLoading = false
    }

    private func apply(_ dto: ReviewResponseDTO) {
        response = dto
        cards = dto.dueCards ?? []
        weakPhonemes = dto.weakPhonemes ?? []
        wordErrors = dto.wordLevelErrors ?? []
        totalCards = dto.stats?.totalCards ?? 0
        dueCards = dto.stats?.dueCards ?? cards.count
        phonemeRows = dto.stats?.phonemeRows ?? 0
        phonemeLevel = dto.stats?.phonemeLevel != false
        voiceReachable = dto.stats?.voiceReachable != false
    }

    // MARK: - 评分

    func grade(cardID: String, grade: String) async {
        guard gradingCardID == nil else {
            return
        }
        gradingCardID = cardID
        gradeNotice = nil
        gradeError = nil
        do {
            let result = try await services.stats.gradeReview(cardId: cardID, grade: grade)
            cards.removeAll { $0.id == cardID }
            dueCards = max(dueCards - 1, 0)
            gradeNotice = Self.nextDueText(
                intervalDays: result.intervalDays,
                nextDueAt: result.nextDueAt
            )
        } catch {
            gradeError = ErrorMapper.message(for: error, isChild: isChild)
        }
        gradingCardID = nil
    }

    static func nextDueText(intervalDays: Int?, nextDueAt: String?) -> String {
        if let days = intervalDays, days > 0 {
            return "下次复习：\(days) 天后 ✅"
        }
        if let next = nextDueAt, !next.isEmpty {
            return "10 分钟后再来一次 🔁"
        }
        return "已记录 ✅"
    }

    // MARK: - 卡片文案

    func cardTitle(_ card: ReviewCardDTO) -> String {
        let label = card.label ?? ""
        if isChild {
            return label.isEmpty ? "这一张" : label
        }
        let phoneme = card.phoneme ?? ""
        if !phoneme.isEmpty {
            return label.isEmpty ? "/\(phoneme)/" : label
        }
        return label
    }

    /// 音素徽标（仅成人且是音素卡）。
    func badgeText(_ card: ReviewCardDTO) -> String {
        guard !isChild, card.isPhoneme == true else {
            return ""
        }
        let phoneme = card.phoneme ?? ""
        return phoneme.isEmpty ? "" : "/\(phoneme)/"
    }

    func metaText(_ card: ReviewCardDTO) -> String {
        guard !isChild else {
            return ""
        }
        let kind = card.kind ?? "phoneme"
        let reps = card.reps ?? 0
        let lapses = card.lapses ?? 0
        let ease = card.ease ?? 0
        let last = card.lastGrade ?? "未复习"
        return "\(kind) · 已复习 \(reps) 次 · 遗忘 \(lapses) 次 · ease \(String(format: "%.2f", ease)) · 上次：\(last)"
    }

    func whyText(_ card: ReviewCardDTO) -> String {
        let why = card.whyZh ?? ""
        if why.isEmpty {
            return ""
        }
        return isChild ? why : "为什么：\(why)"
    }

    func howText(_ card: ReviewCardDTO) -> String {
        let how = card.howZh ?? ""
        if how.isEmpty {
            return ""
        }
        return isChild ? how : "怎么做：\(how)"
    }

    func practiceWordsText(_ card: ReviewCardDTO) -> String {
        let words = card.practiceWords ?? []
        guard !words.isEmpty else {
            return ""
        }
        return "练习词：" + words.joined(separator: " · ")
    }

    func gradeLabel(_ grade: String) -> String {
        if isChild {
            switch grade {
            case "again": return "😵 还没会"
            case "hard": return "🤔 有点难"
            case "good": return "😀 会了"
            default: return "🤩 太简单"
            }
        }
        switch grade {
        case "again": return "再来一次"
        case "hard": return "有点难"
        case "good": return "记住了"
        default: return "太简单"
        }
    }

    // MARK: - 弱音素

    func weakPhonemeLabel(_ item: ReviewWeakPhonemeDTO) -> String {
        let label = item.label ?? ""
        if !label.isEmpty {
            return label
        }
        if isChild {
            return "这个音"
        }
        let phoneme = item.phoneme ?? ""
        return phoneme.isEmpty ? "—" : "/\(phoneme)/"
    }

    /// 单个弱音素的近几次趋势（少于 2 点返回空，页面不画图）。
    func trendPoints(for item: ReviewWeakPhonemeDTO) -> [TrendPoint] {
        let raw = item.trend ?? []
        guard raw.count >= 2 else {
            return []
        }
        let labels = raw.enumerated().map { index, point in
            if let t = point.t, let date = ECJSON.date(from: t) {
                return EcFormat.monthDayText(date)
            }
            return "第 \(index + 1) 次"
        }
        let values = raw.map { $0.s ?? 0 }
        return ChartsData.trendPoints(labels: labels, values: values)
    }

    func weakestThree() -> [ReviewWeakPhonemeDTO] {
        weakPhonemes
            .sorted { ($0.avgScore ?? 0) < ($1.avgScore ?? 0) }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - 示范音

    /// 播示范：优先卡片 `demoText`，否则用练习词里的第一个词。
    func playDemo(_ card: ReviewCardDTO) async {
        guard !audio.isPlaying, !isPreparingDemo else {
            return
        }
        let demo = (card.demoText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = card.practiceWords?.first ?? ""
        let text = demo.isEmpty ? fallback : demo
        guard !text.isEmpty else {
            return
        }
        isPreparingDemo = true
        let rate = TTSRate(
            rawValue: session.prefs.rateOr(capabilities.prefersSlowDemo ? "slow" : "normal")
        ) ?? .normal
        let voiceRaw = session.prefs.voice()
        do {
            let data = try await services.practice.synthesize(
                text: text,
                rate: rate,
                voice: voiceRaw.isEmpty ? nil : voiceRaw,
                format: .wav
            )
            isPreparingDemo = false
            try await audio.play(data: data, formatHint: "wav")
        } catch {
            isPreparingDemo = false
            gradeError = ErrorMapper.message(for: error, isChild: isChild)
        }
    }
}

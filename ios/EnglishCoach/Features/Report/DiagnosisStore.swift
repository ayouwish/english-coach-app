import Foundation
import Observation

/// 诊断统计口径（screens.md §8 / HOS DiagnosisVM 的四个 scope）。
enum DiagnosisScope: String, CaseIterable, Sendable {
    case recent
    case all
    case attempt
    case batch

    var title: String {
        switch self {
        case .recent: return "最近 7 天"
        case .all: return "全部累计"
        case .attempt: return "单次评测"
        case .batch: return "本批诊断"
        }
    }

    /// 需要 `attempt_id` / `attempt_ids` 才能请求的 scope。
    var needsAttemptIDs: Bool {
        self == .attempt || self == .batch
    }
}

/// 「成长」页（诊断概览 + 最近 7 天本地趋势）的状态。
///
/// 数据来源：`GET /diagnosis`（音素行/计数/建议）+ `GET /attempts?limit=`（本地近 7 天趋势）
/// + `GET /review`（错音本待复习数）。`attempt` / `batch` 两个 scope 需要上游入口带评测 id；
/// 本页没有路由参数，缺参时给出提示并回退到最近 7 天（HOS `DiagnosisPage` 同样只开放 recent/all）。
@MainActor
@Observable
final class DiagnosisStore {
    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore

    // MARK: - 查询

    private(set) var scope: DiagnosisScope = .recent
    private(set) var response: DiagnosisResponseDTO?
    private(set) var items: [DiagnosisItemDTO] = []
    private(set) var okItems: [DiagnosisItemDTO] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var loadError: UIMessage?
    private(set) var scopeNotice: String?
    /// `attempt` / `batch` 使用的评测 id（由外部入口注入；默认空 = 缺参）。
    private(set) var pendingAttemptIds: [String] = []
    var showOk = false

    let days = 7

    // MARK: - 本地成长（最近 7 天）

    private(set) var weekTrend: [TrendPoint] = []
    private(set) var weekAttemptCount = 0
    private(set) var weekAverage: Double?
    private(set) var dueCards = 0
    private(set) var hasLoadedGrowth = false

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

    var summaryZh: String {
        response?.summaryZh ?? ""
    }

    var minSamples: Int {
        response?.minSamples ?? 2
    }

    var countedPhonemes: Int {
        response?.countedPhonemes ?? 0
    }

    var totalPhonemes: Int {
        response?.totalPhonemes ?? 0
    }

    var weakCount: Int {
        response?.counts?.weak ?? 0
    }

    var watchCount: Int {
        response?.counts?.watch ?? 0
    }

    var okCount: Int {
        response?.counts?.ok ?? 0
    }

    var focusPhonemes: [String] {
        response?.focusPhonemes ?? []
    }

    /// 最需要练的前 3 个音素（status != ok 的行）。
    var topItems: [DiagnosisItemDTO] {
        Array(items.prefix(3))
    }

    /// 掌握度 0...100：weak≈50 / watch≈75 / ok≈100 的加权（无数据 = nil）。
    var masteryScore: Double? {
        let total = weakCount + watchCount + okCount
        guard total > 0 else {
            return nil
        }
        let weighted = Double(weakCount) * 50 + Double(watchCount) * 75 + Double(okCount) * 100
        return weighted / Double(total)
    }

    var hasAnyData: Bool {
        !items.isEmpty || !okItems.isEmpty || countedPhonemes > 0
    }

    /// 统计口径说明（成人小字）。
    var metricText: String {
        let window = scope == .all
            ? "全部累计"
            : "最近 \(days) 天"
        return "统计口径：\(window) · \(countedPhonemes) 个音素计入（薄弱 \(weakCount) / 待巩固 \(watchCount) / 已掌握 \(okCount)）。"
    }

    // MARK: - 加载诊断

    func load() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        loadError = nil
        do {
            let dto = try await services.stats.diagnosis(
                scope: scope.rawValue,
                days: days,
                attemptIds: pendingAttemptIds
            )
            apply(dto)
            hasLoaded = true
        } catch {
            loadError = ErrorMapper.message(for: error, isChild: isChild)
            hasLoaded = true
        }
        isLoading = false
    }

    /// 切换 scope；`attempt` / `batch` 缺参时提示并留在最近 7 天。
    func switchScope(_ next: DiagnosisScope) async {
        guard next != scope else {
            return
        }
        if next.needsAttemptIDs, pendingAttemptIds.isEmpty {
            scopeNotice = next == .batch
                ? "还没有可用的评测批次：从连读汇总页「查看本批诊断」进入才能看本批数据，这里先显示最近 7 天。"
                : "还没有指定单次评测：从跟读结果页进入才能看单次诊断，这里先显示最近 7 天。"
            return
        }
        scopeNotice = nil
        scope = next
        items = []
        okItems = []
        showOk = false
        await load()
    }

    /// 上游入口（若以后有路由 payload）注入 attempt id 后再切 scope。
    func setAttemptContext(ids: [String], scope next: DiagnosisScope) async {
        pendingAttemptIds = ids
        guard !ids.isEmpty else {
            scopeNotice = "缺少评测记录，无法做这次诊断。"
            return
        }
        scope = next
        await load()
    }

    private func apply(_ dto: DiagnosisResponseDTO) {
        response = dto
        var weakOrWatch: [DiagnosisItemDTO] = []
        var ok: [DiagnosisItemDTO] = []
        for item in dto.items ?? [] {
            if item.status == "ok" {
                ok.append(item)
            } else {
                weakOrWatch.append(item)
            }
        }
        items = weakOrWatch
        okItems = ok
        hasLoaded = true
    }

    // MARK: - 加载成长（最近 7 天本地趋势 + 错音本计数）

    func loadGrowth() async {
        let attempts = (try? await services.practice.attempts(limit: 100)) ?? []
        let review = try? await services.stats.review(limit: 20)
        dueCards = review?.stats?.dueCards ?? 0
        applyGrowth(attempts: attempts)
        hasLoadedGrowth = true
    }

    private func applyGrowth(attempts: [AttemptItemDTO]) {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(byAdding: .day, value: -7, to: Date()) else {
            weekTrend = []
            weekAttemptCount = 0
            weekAverage = nil
            return
        }
        let week = attempts
            .compactMap { item -> (date: Date, score: Double)? in
                guard let date = ECJSON.date(from: item.createdAt),
                      date >= weekStart,
                      let score = item.scores?.pron,
                      score.isFinite
                else {
                    return nil
                }
                return (date, score)
            }
            .sorted { $0.date < $1.date }

        weekAttemptCount = week.count
        let values = week.map { $0.score }
        weekAverage = ChartsData.average(values.map { Optional($0) })
        let labels = week.map { EcFormat.monthDayText($0.date) }
        weekTrend = ChartsData.trendPoints(labels: labels, values: values)
    }

    // MARK: - 行文案

    func itemTitle(_ item: DiagnosisItemDTO) -> String {
        let childLabel = item.childLabel ?? ""
        if isChild {
            return childLabel.isEmpty ? "这个音" : childLabel
        }
        let phoneme = item.phoneme ?? ""
        if phoneme.isEmpty {
            return childLabel
        }
        return childLabel.isEmpty ? "/\(phoneme)/" : "/\(phoneme)/ · \(childLabel)"
    }

    func statusTone(_ status: String?) -> PillTag.Tone {
        switch status {
        case "weak":
            return .danger
        case "watch":
            return .warning
        default:
            return .success
        }
    }

    func statusTitle(_ status: String?) -> String {
        switch status {
        case "weak":
            return "需要练"
        case "watch":
            return "待巩固"
        default:
            return "已掌握"
        }
    }

    func scoreLine(_ item: DiagnosisItemDTO) -> String {
        let attempts = item.attempts ?? 0
        if isChild {
            return "练过 \(attempts) 次"
        }
        let avgText = EcFormat.scoreText(item.avgScore)
        return "\(avgText) 分 · \(attempts) 次记录"
    }

    func trendText(_ item: DiagnosisItemDTO) -> String {
        guard let trend = item.trend, let direction = trend.direction else {
            return ""
        }
        let abs = Int((abs(trend.delta ?? 0)).rounded())
        if isChild {
            switch direction {
            case "improving": return "最近在进步 ↗"
            case "declining": return "最近有点下滑 ↘"
            default: return "最近比较稳定 →"
            }
        }
        switch direction {
        case "improving": return "近 3 次 ↗ 在进步（+\(abs)）"
        case "declining": return "近 3 次 ↘ 略有下滑（-\(abs)）"
        default: return "近 3 次 → 基本持平"
        }
    }

    func tipText(_ item: DiagnosisItemDTO) -> String {
        if isChild {
            return item.tipChildZh ?? ""
        }
        return item.tipZh ?? ""
    }

    /// 最小对立对：按 `pair` 去重（服务端已全局去重，这里再兜底一次），最多 3 组。
    func contrasts(_ item: DiagnosisItemDTO) -> [DiagnosisContrastDTO] {
        guard !isChild else {
            return []
        }
        var seen = Set<String>()
        var result: [DiagnosisContrastDTO] = []
        for contrast in item.contrasts ?? [] {
            let pair = contrast.pair ?? []
            guard !pair.isEmpty else {
                continue
            }
            let key = pair.sorted().joined(separator: "|")
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(contrast)
            if result.count >= 3 {
                break
            }
        }
        return result
    }

    func practiceCountText(_ item: DiagnosisItemDTO) -> String {
        let count = item.practiceCount ?? 0
        if count <= 0 {
            return ""
        }
        return isChild ? "去练一练" : "练这 \(count) 句"
    }

    /// 播示范音：优先用服务端给的示例词，其次用 `PhonemeHints` 的示范句。
    func playDemo(_ item: DiagnosisItemDTO) async {
        guard !audio.isPlaying else {
            return
        }
        let hint = PhonemeHints.byPhoneme(item.phoneme ?? "")
        let raw = item.examples?.first ?? hint.demoText
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
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
            try await audio.play(data: data, formatHint: "wav")
        } catch {
            loadError = ErrorMapper.message(for: error, isChild: isChild)
        }
    }
}

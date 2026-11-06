import Foundation
import Observation

/// 家长面板状态（`ParentView(services:audio:)`）。
///
/// `GET /parent/summary` 字段结构在 screens.md §9.1 标注【待确认】：渲染必须容错——
/// 未知字段忽略、缺失字段隐藏整行，绝不因字段缺失崩溃。
@MainActor
@Observable
final class ParentViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(UIMessage)
    }

    enum DeltaTone {
        case up
        case down
        case flat
        case unknown
    }

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore

    private(set) var loadState: LoadState = .idle
    private(set) var forbidden = false
    private(set) var didLoad = false

    private(set) var familyMembers = 0
    private(set) var minutesToday: Double = 0
    private(set) var minutes7d: Double = 0
    private(set) var sentenceCount = 0
    private(set) var scenarioCount = 0
    private(set) var children: [ParentSummaryDTO.ParentChildDTO] = []
    private(set) var members: [ParentMemberDTO] = []

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
    }

    // MARK: - 加载

    func load(force: Bool = false) async {
        if didLoad && !force { return }
        if case .loading = loadState { return }
        loadState = .loading
        forbidden = false
        do {
            let dto = try await services.account.parentSummary()
            familyMembers = dto.family?.members ?? 0
            minutesToday = dto.family?.minutesToday ?? 0
            minutes7d = dto.family?.minutes7d ?? 0
            sentenceCount = dto.family?.sentenceCount ?? 0
            scenarioCount = dto.family?.scenarioCount ?? 0
            children = dto.family?.children ?? []
            members = dto.members ?? []
            didLoad = true
            loadState = .loaded
        } catch let error as APIError {
            if case .forbidden = error {
                forbidden = true
                loadState = .failed(
                    UIMessage(
                        title: "家长面板仅对家长账号开放",
                        body: "请用家长账号登录；孩子账号看不到这里的数据。",
                        actionTitle: "返回",
                        action: UIMessage.Action.back,
                        isRetryable: false,
                        diagnosticID: nil
                    )
                )
            } else {
                loadState = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
            }
        } catch {
            loadState = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
        }
    }

    // MARK: - 汇总文案

    var familyText: String {
        let today = Self.minutesText(minutesToday)
        let week = Self.minutesText(minutes7d)
        return "全家今天共练习 \(today) 分钟，近 7 天 \(week) 分钟 · 语料 \(sentenceCount) 句 · 对话场景 \(scenarioCount) 个"
    }

    var memberCountText: String {
        "家庭共 \(familyMembers) 个账号"
    }

    // MARK: - 成员卡片

    func memberTitle(_ member: ParentMemberDTO) -> String {
        let name = member.displayName ?? "成员"
        let avatar = (member.avatar?.isEmpty == false) ? (member.avatar ?? "") : "🙂"
        return "\(avatar) \(name)"
    }

    func memberBadge(_ member: ParentMemberDTO) -> String {
        let role = member.role == "child" ? "孩子" : "家长"
        let level = member.cefrLevel ?? ""
        return level.isEmpty ? role : "\(role) · \(level)"
    }

    func todayText(_ member: ParentMemberDTO) -> String {
        guard let today = member.today else { return "今日暂无练习" }
        var text = "今日练习 \(Self.minutesText(today.minutes ?? 0)) 分钟"
        if let blind = today.blindMinutes, blind > 0 {
            text += " + 盲测 \(Self.minutesText(blind)) 分钟"
        }
        text += " · 跟读 \(today.attemptCount ?? 0) 次 · 对话 \(today.chatTurns ?? 0) 轮"
        if let remaining = today.remainingMinutes {
            text += " · 剩余 \(Self.minutesText(remaining)) 分钟"
        }
        return text
    }

    func weekText(_ member: ParentMemberDTO) -> String? {
        guard member.week != nil || member.totals != nil else { return nil }
        let minutes = Self.minutesText(member.week?.minutes ?? 0)
        let attempts = member.week?.attempts ?? 0
        let avg = Self.scoreText(member.week?.avgPron)
        let totalAttempts = member.totals?.attempts ?? 0
        let sessions = member.totals?.chatSessions ?? 0
        return "近 7 天 \(minutes) 分钟 · 练习 \(attempts) 次 · 平均分 \(avg) · 累计 \(totalAttempts) 次跟读 / \(sessions) 场对话"
    }

    // MARK: - 盲测

    func blindScoreText(_ member: ParentMemberDTO) -> String {
        guard let current = member.blind?.current else { return "—" }
        return Self.scoreText(current.avgPron)
    }

    func blindDelta(member: ParentMemberDTO) -> (text: String, tone: DeltaTone)? {
        guard member.blind?.current != nil else { return nil }
        guard let delta = member.blind?.deltaPron else {
            return ("首次（无对比）", .unknown)
        }
        let rounded = (delta * 10).rounded() / 10
        if rounded > 0 { return ("▲ +\(Self.number(rounded))", .up) }
        if rounded < 0 { return ("▼ \(Self.number(rounded))", .down) }
        return ("＝ 0", .flat)
    }

    func blindWeeksText(_ member: ParentMemberDTO) -> String? {
        guard let weeks = member.blind?.weeks, weeks > 0 else { return nil }
        return "近 \(weeks) 周趋势"
    }

    func blindSeriesText(_ member: ParentMemberDTO) -> String? {
        guard let series = member.blind?.series, !series.isEmpty else { return nil }
        let values = series.map { Self.scoreText($0.avgPron) }
        return "历史：" + values.joined(separator: " · ")
    }

    // MARK: - 音素 / 单词 / 趋势

    func topPhonemes(_ member: ParentMemberDTO) -> [ParentPhonemeDTO] {
        member.topPhonemes ?? []
    }

    func phonemeText(_ item: ParentPhonemeDTO) -> String {
        let phoneme = item.phoneme ?? ""
        let title = item.titleZh ?? ""
        let line = "\(phoneme) \(title)".trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? "音素" : line
    }

    func phonemeMeta(_ item: ParentPhonemeDTO) -> String {
        "均 \(Self.scoreText(item.avgScore)) · \(item.count ?? 0) 次 · 低于 60 \(item.hardHits ?? 0) 次"
    }

    func topWords(_ member: ParentMemberDTO) -> [ParentWordDTO] {
        member.topWords ?? []
    }

    func wordText(_ item: ParentWordDTO) -> String {
        "\(item.word ?? "") × \(item.count ?? 0)（均 \(Self.scoreText(item.avgScore))）"
    }

    func trendTail(_ member: ParentMemberDTO) -> String? {
        let points = member.trend ?? []
        guard !points.isEmpty else { return nil }
        let tail = points.suffix(3)
        let parts = tail.map { "\($0.date ?? "")：\(Self.scoreText($0.avgPron))" }
        return "近 3 天：" + parts.joined(separator: " · ")
    }

    // MARK: - 孩子剩余时长

    func childRemainingText(_ child: ParentSummaryDTO.ParentChildDTO) -> String {
        let remaining = child.remainingMinutes.map(Self.minutesText) ?? "—"
        let limit = child.limitMinutes.map { Self.number($0) } ?? "—"
        return "\(remaining) / \(limit) 分钟"
    }

    // MARK: - 工具

    static func minutesText(_ value: Double) -> String {
        number((value * 10).rounded() / 10)
    }

    static func scoreText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return number((value * 10).rounded() / 10)
    }

    private static func number(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

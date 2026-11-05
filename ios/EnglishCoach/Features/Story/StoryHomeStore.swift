import Foundation
import Observation

/// 故事集（Tab 3 根页）状态。
///
/// 职责：拉 `GET materials?kind=story`、按「今天/昨天/更早」分组、全家/只看我的筛选、
/// 连续天数统计；只做展示态，不做网络以外的副作用。
@MainActor
@Observable
final class StoryHomeStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(UIMessage)
    }

    private(set) var phase: Phase = .loading
    private(set) var groups: [StoryGroup] = []
    private(set) var onlyMine = false
    private(set) var streakDays = 0
    private(set) var total = 0
    private(set) var isRefreshing = false

    private let services: AppServices
    private let session: SessionStore
    private let runtime: StoryRuntime
    private var allCards: [StoryCardItem] = []
    private var hasLoaded = false

    init(services: AppServices, session: SessionStore) {
        self.services = services
        self.session = session
        self.runtime = StoryRuntime.shared
    }

    var isChild: Bool { session.isChild }

    var filteredCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    /// 监听它即可在「新建故事」后刷新列表（`StoryRuntime.savedTick`）。
    var savedTick: Int { runtime.savedTick }

    // MARK: - 加载

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        if allCards.isEmpty {
            phase = .loading
        }
        do {
            let list = try await services.story.materials(limit: 50, offset: 0)
            allCards = list.map { StoryCardItem(material: $0) }
            total = allCards.count
            streakDays = StoryDates.streakDays(from: allCards)
            rebuildGroups()
            phase = .ready
            hasLoaded = true
        } catch {
            if allCards.isEmpty {
                phase = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
            }
        }
    }

    func reload() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await load()
    }

    func setOnlyMine(_ value: Bool) {
        guard onlyMine != value else { return }
        onlyMine = value
        rebuildGroups()
    }

    // MARK: - 分组

    private func rebuildGroups() {
        let userId = session.user?.id ?? ""
        let filtered = onlyMine ? allCards.filter { $0.authorId == userId } : allCards

        var labels: [String] = []
        var buckets: [String: [StoryCardItem]] = [:]
        for card in filtered {
            let label = card.dateLabel
            if buckets[label] == nil {
                labels.append(label)
                buckets[label] = []
            }
            buckets[label]?.append(card)
        }
        groups = labels.map { StoryGroup(label: $0, items: buckets[$0] ?? []) }
    }
}

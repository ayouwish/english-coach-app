import Foundation
import Observation

/// 对话历史列表 Store（`.chatHistory`）。
@MainActor
@Observable
final class ChatHistoryStore {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(UIMessage)
    }

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let session: SessionStore

    private(set) var loadState: LoadState = .loading
    private(set) var items: [ChatSessionListItemDTO] = []
    private(set) var failure: UIMessage?
    private(set) var isChild: Bool

    @ObservationIgnored private var lastLoadedAt: Date?
    @ObservationIgnored private var isLoading = false

    init(services: AppServices, session: SessionStore) {
        self.services = services
        self.session = session
        self.isChild = session.isChild
    }

    func appear() async {
        guard !isLoading else { return }
        if loadState == .ready, let last = lastLoadedAt, Date().timeIntervalSince(last) < 1.5 {
            return
        }
        await load()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        if loadState != .ready {
            loadState = .loading
        }
        failure = nil
        do {
            let list = try await services.chat.sessions()
            items = list.sessions ?? []
            loadState = .ready
            lastLoadedAt = Date()
        } catch {
            let message = ErrorMapper.message(for: error, isChild: isChild)
            if message.isSilent {
                failure = nil
            } else if loadState == .ready, !items.isEmpty {
                failure = message
            } else {
                loadState = .failed(message)
            }
        }
        isLoading = false
    }

    func dismissFailure() {
        failure = nil
    }

    // MARK: - 行展示

    func title(for item: ChatSessionListItemDTO) -> String {
        let zh = (item.scenarioTitleZh ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !zh.isEmpty { return zh }
        let en = (item.scenarioTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return en.isEmpty ? "对话" : en
    }

    func statusText(for item: ChatSessionListItemDTO) -> String {
        isEnded(item) ? "已结束" : "还在进行"
    }

    func isEnded(_ item: ChatSessionListItemDTO) -> Bool {
        !(item.endedAt ?? "").isEmpty
    }

    func timeText(for item: ChatSessionListItemDTO) -> String {
        guard let date = ECJSON.date(from: item.startedAt) else { return "" }
        return EcFormat.relative(date)
    }
}

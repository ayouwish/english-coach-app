import Foundation
import Observation

/// 对话场景页 Store（Tab 2 / `.chatScenarios`）。
///
/// 数据来源 `GET chat/scenarios[?include_child=1]`：
/// - 自定义场景（`isCustom`）单独一组；
/// - 官方场景按 `audience` 分成人 / 儿童两组；
/// - 儿童账号只看儿童场景，成人默认只看成人，可手动加载儿童场景。
@MainActor
@Observable
final class ChatScenariosStore {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(UIMessage)
    }

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let audio: AudioCoordinator
    @ObservationIgnored private let session: SessionStore

    private(set) var loadState: LoadState = .loading
    private(set) var customScenarios: [ChatScenarioDTO] = []
    private(set) var adultScenarios: [ChatScenarioDTO] = []
    private(set) var childScenarios: [ChatScenarioDTO] = []
    private(set) var hiddenCount = 0
    private(set) var age = 0
    private(set) var includeChild = false
    private(set) var startingScenarioID: String?
    private(set) var failure: UIMessage?
    private(set) var isQuotaExceeded = false
    private(set) var quotaText = ""
    private(set) var isChild: Bool
    private(set) var autoRead: Bool
    private(set) var rateText: String

    @ObservationIgnored private var lastLoadedAt: Date?
    @ObservationIgnored private var isLoading = false

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
        self.isChild = session.isChild
        self.autoRead = ChatSettings.autoRead()
        if ChatSettings.hasRateOverride() {
            self.rateText = ChatSettings.rateText()
        } else {
            self.rateText = session.prefs.ttsRate == TTSRate.slow.rawValue ? TTSRate.slow.rawValue : TTSRate.normal.rawValue
        }
    }

    // MARK: - 派生展示

    var isAllEmpty: Bool {
        customScenarios.isEmpty && adultScenarios.isEmpty && childScenarios.isEmpty
    }

    var usageText: String? {
        guard !isChild, let usage = session.usage else { return nil }
        let minutes = Int((usage.minutes ?? 0).rounded())
        if let limit = usage.limitMinutes, limit > 0 {
            var text = "今日已练 \(minutes)/\(limit) 分钟"
            if let remaining = usage.remainingMinutes {
                text += " · 还剩 \(max(0, remaining)) 分钟"
            }
            return text
        }
        return minutes > 0 ? "今日已练 \(minutes) 分钟" : nil
    }

    var audienceHint: String {
        if isChild {
            if age > 0 {
                return "你 \(age) 岁，这里只显示适合你的场景。"
            }
            return "这里只显示适合你的场景。"
        }
        if includeChild {
            return "成人场景 \(adultScenarios.count) 个，儿童场景 \(childScenarios.count) 个。"
        }
        return "成人场景 \(adultScenarios.count) 个。想练小朋友的场景？打开下面的「再看小朋友的场景」开关。"
    }

    var childToggleSubtitle: String {
        if includeChild {
            return "默认只看成人场景；打开后会多请求 \(hiddenCount) 个儿童场景"
        }
        return "默认只看成人场景；打开后额外加载儿童场景"
    }

    // MARK: - 加载

    /// 页面出现时调用：首次加载；从自定义场景页返回时（距上次加载 > 1.5s）刷新。
    func appear() async {
        guard !isLoading else { return }
        if loadState == .ready, let last = lastLoadedAt, Date().timeIntervalSince(last) < 1.5 {
            return
        }
        await load()
    }

    func reload() async {
        await load()
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        if loadState != .ready {
            loadState = .loading
        }
        failure = nil
        do {
            let dto = try await services.chat.scenarios(includeChild: includeChild)
            apply(dto)
            loadState = .ready
            lastLoadedAt = Date()
        } catch {
            let message = ErrorMapper.message(for: error, isChild: isChild)
            if message.isSilent {
                failure = nil
            } else if loadState == .ready, !isAllEmpty {
                // 已有内容时用顶部横幅提示，不整页报错。
                failure = message
            } else {
                loadState = .failed(message)
            }
            registerQuota(error)
        }
        isLoading = false
    }

    private func apply(_ dto: ChatScenarioListDTO) {
        age = dto.age ?? 0
        hiddenCount = dto.hiddenCount ?? 0
        if let serverInclude = dto.includeChild {
            includeChild = serverInclude
        }
        let items = dto.scenarios ?? []
        let custom = items.filter { $0.isCustom == true }
        let official = items.filter { $0.isCustom != true }
        let childItems = official.filter { ($0.audience ?? "").lowercased() == "child" }
        let adultItems = official.filter { ($0.audience ?? "").lowercased() != "child" }
        customScenarios = custom
        if isChild {
            childScenarios = childItems.isEmpty ? official : childItems
            adultScenarios = []
        } else {
            childScenarios = childItems
            adultScenarios = adultItems
        }
    }

    // MARK: - 操作

    func setIncludeChild(_ on: Bool) async {
        guard includeChild != on else { return }
        includeChild = on
        await load()
    }

    func setAutoRead(_ on: Bool) {
        autoRead = on
        ChatSettings.setAutoRead(on)
    }

    func setRateText(_ raw: String) {
        let normalized = raw == TTSRate.slow.rawValue ? TTSRate.slow.rawValue : TTSRate.normal.rawValue
        rateText = normalized
        ChatSettings.setRateText(normalized)
    }

    /// 开始对话：`POST chat/sessions` → sessionId。失败返回 nil 并展示 ErrorMapper 文案。
    func start(_ scenario: ChatScenarioDTO) async -> String? {
        guard startingScenarioID == nil else { return nil }
        startingScenarioID = scenario.id
        failure = nil
        var sessionID: String?
        do {
            let created = try await services.chat.createSession(scenarioId: scenario.id)
            sessionID = created.sessionId
        } catch {
            let message = ErrorMapper.message(for: error, isChild: isChild)
            failure = message.isSilent ? nil : message
            registerQuota(error)
        }
        startingScenarioID = nil
        return sessionID
    }

    /// 自定义场景保存/删除后由子页面调用（子页面 push 返回时本页会再次 `appear()`）。
    func markNeedsReload() {
        lastLoadedAt = nil
    }

    func dismissFailure() {
        failure = nil
    }

    private func registerQuota(_ error: any Error) {
        guard let api = error as? APIError else { return }
        guard case .server(let code, _, _) = api else { return }
        switch code {
        case .dailyLimitReached, .tooManyRequests:
            isQuotaExceeded = true
            let message = ErrorMapper.message(for: error, isChild: isChild)
            quotaText = message.body ?? message.title
        default:
            break
        }
    }
}

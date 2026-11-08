import Foundation
import Observation

/// 对话会话 Store（实时会话与历史详情共用）。
///
/// 职责：
/// - 加载会话详情（标题/轮数/消息），实时会话补齐 `pron`；
/// - 一轮三步：`asr` → 乐观用户气泡 → `turn` → 助手文本 → 自动 TTS 播放；
/// - 每轮后台轮询 `messages` 补 `pron`（1/2/3/4/5s，累计约 15s，超时静默）；
/// - 整段回放交给 `ChatReplayController`（先轮询 `audioStatus` 到 ready 再取音频）；
/// - 退出页面/切后台时取消轮询与播放。
///
/// 纯语音约束：本 Store 不接收文本输入（唯一入口是录音）。
@MainActor
@Observable
final class ChatSessionStore {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(UIMessage)
    }

    enum MicState: Equatable {
        case idle
        case preparing
        case recording
        case busy
        case ending
    }

    let sessionID: String
    let readOnly: Bool
    /// 整段回放状态机（只读历史页同样使用）。
    let replay: ChatReplayController

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let audio: AudioCoordinator
    @ObservationIgnored private let session: SessionStore

    private(set) var loadState: LoadState = .loading
    private(set) var bubbles: [ChatBubble] = []
    private(set) var titleEn = ""
    private(set) var titleZh = ""
    private(set) var settingZh = ""
    private(set) var level = ""
    private(set) var startedAt = ""
    private(set) var endedAt = ""
    private(set) var turnCount = 0
    private(set) var isEnded = false
    private(set) var isDone = false
    private(set) var isEnding = false
    private(set) var isAwaitingReply = false
    private(set) var micState: MicState = .idle
    private(set) var elapsedMs = 0
    private(set) var progressText = ""
    private(set) var showsSlowHint = false
    private(set) var suggestedReplies: [String] = []
    private(set) var hintText = ""
    private(set) var failure: UIMessage?
    private(set) var isQuotaExceeded = false
    private(set) var quotaText = ""
    private(set) var isDegraded = false
    private(set) var isDegradedLlm = false

    private(set) var isChild: Bool
    private(set) var autoRead: Bool
    private(set) var rateText: String

    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private var recordingTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var pronPollTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTurnText = ""
    @ObservationIgnored private var pendingTurnAudio: Data?
    @ObservationIgnored private var pendingTurnBubbleID = ""
    @ObservationIgnored private var pendingKind: PendingKind = .none

    private enum PendingKind {
        case none
        case load
        case turn
        case replay
    }

    /// 对话录音上限：比跟读短（`screens.md` §5.6 成人 30s；Core 硬上限 60s）。
    private static let maxRecordingMs = 30_000
    /// pron 轮询：1/2/3/4/5s（累计 15s 上限，与 screens.md §5.3 一致）。
    private static let pronDelays: [Double] = [1, 2, 3, 4, 5]

    init(
        sessionID: String,
        readOnly: Bool,
        scenario: ChatScenarioDTO?,
        services: AppServices,
        audio: AudioCoordinator,
        session: SessionStore
    ) {
        self.sessionID = sessionID
        self.readOnly = readOnly
        self.services = services
        self.audio = audio
        self.session = session
        self.isChild = session.isChild
        self.autoRead = ChatSettings.autoRead()
        let localRate = ChatSettings.rateText()
        let prefRate = session.prefs.ttsRate
        self.rateText = ChatSettings.hasRateOverride()
            ? localRate
            : (prefRate == TTSRate.slow.rawValue ? prefRate : localRate)
        self.replay = ChatReplayController(
            sessionID: sessionID,
            services: services,
            audio: audio,
            isChild: session.isChild
        )
        if let scenario {
            titleEn = scenario.title ?? ""
            titleZh = scenario.titleZh ?? ""
            settingZh = scenario.settingZh ?? ""
            level = scenario.level ?? ""
        }
    }

    // MARK: - 派生状态

    var isRecording: Bool { micState == .recording }
    var isPreparing: Bool { micState == .preparing }
    var isBusy: Bool { micState == .busy || isAwaitingReply }
    var canRecord: Bool {
        !readOnly && !isEnded && !isDone && loadState == .ready && micState == .idle && !isAwaitingReply && !isQuotaExceeded
    }
    var canEnd: Bool { !readOnly && !isEnded && loadState == .ready }
    var title: String {
        if !titleZh.isEmpty { return titleZh }
        if !titleEn.isEmpty { return titleEn }
        return readOnly ? "对话详情" : "对话中"
    }
    var subtitle: String {
        var parts: [String] = []
        if !settingZh.isEmpty { parts.append(settingZh) }
        if !titleEn.isEmpty, !titleZh.isEmpty { parts.append(titleEn) }
        if !level.isEmpty { parts.append(level.uppercased()) }
        return parts.joined(separator: " · ")
    }
    var progressLabel: String {
        if !progressText.isEmpty { return progressText }
        return isBusy ? "识别 / 回复中…请稍候 ⏳" : ""
    }

    // MARK: - 加载

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await reload()
    }

    func reload() async {
        loadState = .loading
        failure = nil
        pendingKind = .none
        do {
            let detail = try await services.chat.sessionDetail(id: sessionID)
            apply(detail: detail)
            if !readOnly, !isEnded {
                await refreshMessages()
            }
            loadState = .ready
            if !readOnly, !isEnded, autoRead, let opening = bubbles.first(where: { $0.speaker == .assistant && !$0.text.isEmpty }) {
                await play(opening.id)
            }
        } catch {
            registerFailure(error, kind: .load)
            loadState = .failed(failure ?? ErrorMapper.message(for: error, isChild: isChild))
        }
    }

    private func apply(detail: ChatSessionDetailDTO) {
        if !(detail.scenarioTitleZh ?? "").isEmpty { titleZh = detail.scenarioTitleZh ?? "" }
        if !(detail.scenarioTitle ?? "").isEmpty { titleEn = detail.scenarioTitle ?? "" }
        startedAt = detail.startedAt ?? ""
        endedAt = detail.endedAt ?? ""
        isEnded = !endedAt.isEmpty
        if let count = detail.turnCount, count > 0 {
            turnCount = count
        } else {
            turnCount = (detail.messages ?? []).filter { $0.role == ChatSpeaker.user.rawValue }.count
        }
        bubbles = (detail.messages ?? []).map { ChatBubbleFactory.from(dto: $0, isChild: isChild) }
    }

    /// 用 `/messages` 补 `pron` 与 `correction`（历史详情不展示 pron，可跳过）。
    private func refreshMessages() async {
        guard !readOnly else { return }
        do {
            let list = try await services.chat.messages(sessionId: sessionID)
            for dto in list.messages ?? [] {
                guard let index = bubbleIndex(for: dto) else { continue }
                if let pron = dto.pron {
                    ChatBubbleFactory.applyPron(pron, to: &bubbles[index], isChild: isChild)
                }
                if let correction = dto.correction, !bubbles[index].hasCorrection {
                    ChatBubbleFactory.applyCorrection(correction, to: &bubbles[index])
                }
            }
        } catch {
            // 静默：这是补数据，失败不影响已有内容。
        }
    }

    private func bubbleIndex(for dto: ChatMessageDTO) -> Int? {
        if let dtoID = dto.id, !dtoID.isEmpty,
           let index = bubbles.firstIndex(where: { $0.serverID == dtoID }) {
            return index
        }
        let role = dto.role == ChatSpeaker.user.rawValue ? ChatSpeaker.user : .assistant
        let text = dto.text ?? ""
        return bubbles.lastIndex(where: { $0.speaker == role && $0.text == text })
    }

    // MARK: - 录音（唯一输入）

    func toggleMic() async {
        guard !readOnly, !isEnded, !isQuotaExceeded else { return }
        if micState == .recording {
            await stopAndSend()
            return
        }
        guard micState == .idle, !isAwaitingReply else { return }
        failure = nil
        pendingKind = .none
        if audio.permission != .granted {
            let granted = await audio.requestPermission()
            guard granted else {
                registerFailure(AudioError.permissionDenied, kind: .none)
                return
            }
        }
        micState = .preparing
        progressText = "正在打开麦克风…"
        do {
            try await audio.startRecording()
            micState = .recording
            elapsedMs = 0
            progressText = ""
            startRecordingTimer()
        } catch {
            micState = .idle
            progressText = ""
            registerFailure(error, kind: .none)
        }
    }

    func cancelRecording() async {
        guard micState == .recording else { return }
        recordingTask?.cancel()
        await audio.cancelRecording()
        micState = .idle
        elapsedMs = 0
        progressText = ""
    }

    private func startRecordingTimer() {
        recordingTask?.cancel()
        recordingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard let self, self.micState == .recording else { return }
                self.elapsedMs += 200
                if self.audio.mode != .recording {
                    self.micState = .idle
                    self.elapsedMs = 0
                    return
                }
                if self.elapsedMs >= Self.maxRecordingMs {
                    await self.stopAndSend()
                    return
                }
            }
        }
    }

    private func stopAndSend() async {
        guard micState == .recording else { return }
        recordingTask?.cancel()
        micState = .preparing
        progressText = ""
        let recorded: RecordedAudio
        do {
            recorded = try await audio.stopRecording()
        } catch {
            micState = .idle
            elapsedMs = 0
            registerFailure(error, kind: .none)
            return
        }
        elapsedMs = 0
        await sendRecorded(recorded)
    }

    private func sendRecorded(_ recorded: RecordedAudio) async {
        micState = .busy
        isAwaitingReply = true
        progressText = "识别中…"
        showsSlowHint = false
        startProgressTimer()

        var recognized = ""
        do {
            recognized = try await services.chat.asr(audioData: recorded.data, language: "en")
        } catch {
            finishBusy()
            registerFailure(error, kind: .none)
            return
        }
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finishBusy()
            failure = UIMessage(
                title: "我没听清，再说一次",
                body: "这次没识别到英文；说得慢一点、清楚一点就好。",
                actionTitle: nil,
                action: UIMessage.Action.none,
                isRetryable: false,
                diagnosticID: nil
            )
            return
        }
        progressText = "回复中…"
        let bubble = ChatBubbleFactory.makeLocalUser(text: trimmed, audio: recorded.data)
        bubbles.append(bubble)
        await sendTurn(text: trimmed, audio: recorded.data, bubbleID: bubble.id)
    }

    private func sendTurn(text: String, audio data: Data?, bubbleID: String) async {
        isAwaitingReply = true
        micState = .busy
        progressText = "回复中…"
        showsSlowHint = false
        startProgressTimer()
        pendingTurnText = text
        pendingTurnAudio = data
        pendingTurnBubbleID = bubbleID
        do {
            let turn = try await services.chat.turn(sessionId: sessionID, text: text, audioData: data)
            apply(turn: turn, bubbleID: bubbleID)
            pendingTurnText = ""
            pendingTurnAudio = nil
            pendingTurnBubbleID = ""
            pendingKind = .none
            finishBusy()
            if let replyID = bubbles.last?.id, bubbles.last?.speaker == .assistant, autoRead, !isEnded {
                await play(replyID)
            }
            if let index = bubbles.firstIndex(where: { $0.id == bubbleID }) {
                startPronPoll(
                    bubbleID: bubbles[index].id,
                    serverID: bubbles[index].serverID,
                    text: bubbles[index].text
                )
            }
        } catch {
            finishBusy()
            registerFailure(error, kind: .turn)
        }
    }

    private func apply(turn: ChatTurnDTO, bubbleID: String) {
        if let index = bubbles.firstIndex(where: { $0.id == bubbleID }) {
            bubbles[index].serverID = turn.userMessageId ?? ""
            ChatBubbleFactory.applyCorrection(turn.correction, to: &bubbles[index])
            bubbles[index].pronPending = true
        }
        let reply = (turn.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !reply.isEmpty {
            bubbles.append(
                ChatBubbleFactory.makeAssistant(
                    text: reply,
                    textZh: turn.replyZh ?? "",
                    serverID: turn.messageId ?? "",
                    unsafeFiltered: turn.flag == "unsafe_filtered"
                )
            )
        }
        turnCount = turn.turnIndex ?? (turnCount + 1)
        suggestedReplies = Array((turn.suggestedReplies ?? []).prefix(4))
        hintText = ""
        isDegraded = turn.degraded == true
        isDegradedLlm = turn.degradedLlm == true
        if turn.done == true {
            isDone = true
            suggestedReplies = []
        }
    }

    // MARK: - pron 轮询

    private func startPronPoll(bubbleID: String, serverID: String, text: String) {
        pronPollTask?.cancel()
        pronPollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in Self.pronDelays {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled, !self.isEnded else { return }
                if await self.pollPronOnce(bubbleID: bubbleID, serverID: serverID, text: text) {
                    return
                }
            }
            self.markPronTimedOut(bubbleID: bubbleID)
        }
    }

    private func pollPronOnce(bubbleID: String, serverID: String, text: String) async -> Bool {
        do {
            let list = try await services.chat.messages(sessionId: sessionID)
            guard let target = (list.messages ?? []).last(where: {
                $0.role == ChatSpeaker.user.rawValue && (!serverID.isEmpty ? ($0.id ?? "") == serverID : ($0.text ?? "") == text)
            }), let pron = target.pron else {
                return false
            }
            guard let index = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return true }
            ChatBubbleFactory.applyPron(pron, to: &bubbles[index], isChild: isChild)
            return true
        } catch {
            return false
        }
    }

    private func markPronTimedOut(bubbleID: String) {
        guard let index = bubbles.firstIndex(where: { $0.id == bubbleID }), bubbles[index].pronPending else { return }
        bubbles[index].pronPending = false
        bubbles[index].pronTimedOut = true
    }

    private func stopPronPoll() {
        pronPollTask?.cancel()
        pronPollTask = nil
    }

    // MARK: - 播放单条气泡

    func play(_ bubbleID: String) async {
        guard let index = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        if bubbles[index].playback == .playing {
            await stopPlayback()
            return
        }
        guard micState != .recording, !isPreparing else { return }
        let bubble = bubbles[index]
        if bubble.speaker == .assistant {
            guard !bubble.text.isEmpty else { return }
        } else {
            guard bubble.hasAudio else { return }
        }
        bubbles[index].playback = .loading
        do {
            let data: Data
            if bubble.speaker == .assistant {
                data = try await services.practice.synthesize(
                    text: bubble.text,
                    rate: TTSRate(rawValue: rateText) ?? .normal,
                    voice: currentVoice,
                    format: .mp3
                )
            } else if let local = bubble.localAudio {
                data = local
            } else {
                data = try await services.chat.downloadAudio(url: bubble.audioURL)
            }
            try await audio.play(data: data, formatHint: bubble.speaker == .assistant ? "mp3" : "m4a")
            setPlayback(bubbleID, .playing)
            watchPlayback(bubbleID)
        } catch {
            setPlayback(bubbleID, .failed)
            registerFailure(error, kind: .none)
        }
    }

    private func setPlayback(_ bubbleID: String, _ state: ChatPlaybackState) {
        guard let index = bubbles.firstIndex(where: { $0.id == bubbleID }) else { return }
        bubbles[index].playback = state
    }

    private func watchPlayback(_ bubbleID: String) {
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                if !self.audio.isPlaying || self.audio.mode != .playing {
                    self.setPlayback(bubbleID, .idle)
                    return
                }
            }
        }
    }

    func stopPlayback() async {
        playbackTask?.cancel()
        await audio.stopPlayback()
        await replay.stop()
        for index in bubbles.indices where bubbles[index].playback != .idle {
            bubbles[index].playback = .idle
        }
    }

    // MARK: - 建议 / 提示

    func useSuggestion(_ text: String) {
        hintText = text
    }

    func clearHint() {
        hintText = ""
    }

    func setAutoRead(_ on: Bool) {
        autoRead = on
        ChatSettings.setAutoRead(on)
        if !on {
            Task { await stopPlayback() }
        }
    }

    func setRateText(_ raw: String) {
        rateText = raw == TTSRate.slow.rawValue ? TTSRate.slow.rawValue : TTSRate.normal.rawValue
        ChatSettings.setRateText(rateText)
    }

    private var currentVoice: String? {
        let raw = session.prefs.voice().trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    // MARK: - 结束会话

    /// 返回 true = 已结束，可回场景页。
    func endSession() async -> Bool {
        guard !readOnly, !isEnded else { return true }
        isEnding = true
        micState = .ending
        do {
            try await services.chat.end(sessionId: sessionID)
            isEnded = true
            isEnding = false
            micState = .idle
            stopPronPoll()
            await stopPlayback()
            await replay.begin()
            return true
        } catch {
            isEnding = false
            micState = .idle
            registerFailure(error, kind: .none)
            return false
        }
    }

    // MARK: - 失败与重试

    private func registerFailure(_ error: any Error, kind: PendingKind) {
        let message = ErrorMapper.message(for: error, isChild: isChild)
        guard !message.isSilent else { return }
        failure = message
        pendingKind = kind
        if let api = error as? APIError {
            if case .server(let code, _, _) = api {
                switch code {
                case .dailyLimitReached, .tooManyRequests:
                    isQuotaExceeded = true
                    quotaText = message.body ?? message.title
                case .sessionClosed:
                    isEnded = true
                default:
                    break
                }
            }
        }
    }

    func dismissFailure() {
        failure = nil
        pendingKind = .none
    }

    func retry() async {
        let kind = pendingKind
        failure = nil
        pendingKind = .none
        switch kind {
        case .load:
            await reload()
        case .turn:
            guard pendingTurnAudio != nil || !pendingTurnBubbleID.isEmpty else { return }
            await sendTurn(text: pendingTurnText, audio: pendingTurnAudio, bubbleID: pendingTurnBubbleID)
        case .replay:
            await replay.regenerate()
        case .none:
            break
        }
    }

    // MARK: - 生命周期

    /// 切后台：停止播放、放弃当前录音、取消所有轮询（页面内容保留）。
    func pauseForBackground() async {
        recordingTask?.cancel()
        stopPronPoll()
        replay.pauseForBackground()
        playbackTask?.cancel()
        await audio.stopAll()
        if micState == .recording || micState == .preparing {
            micState = .idle
            elapsedMs = 0
            progressText = ""
        }
        for index in bubbles.indices where bubbles[index].playback != .idle {
            bubbles[index].playback = .idle
        }
    }

    /// 退出页面：取消全部后台任务并归还音频焦点（再进入页面会重新加载）。
    func dispose() {
        recordingTask?.cancel()
        progressTask?.cancel()
        pronPollTask?.cancel()
        playbackTask?.cancel()
        replay.dispose()
        recordingTask = nil
        progressTask = nil
        pronPollTask = nil
        playbackTask = nil
        let coordinator = audio
        Task { @MainActor in
            await coordinator.stopAll()
        }
    }

    // MARK: - 内部小工具

    private func startProgressTimer() {
        progressTask?.cancel()
        showsSlowHint = false
        progressTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.isAwaitingReply else { return }
            self.showsSlowHint = true
        }
    }

    private func finishBusy() {
        progressTask?.cancel()
        progressTask = nil
        isAwaitingReply = false
        micState = .idle
        progressText = ""
        showsSlowHint = false
    }
}

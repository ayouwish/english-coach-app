import Foundation
import Observation
import OSLog
import SwiftUI

private let flowLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "flow")

/// 上传并发闸门：`/attempts/async` 同时最多 2 个在途（契约要求「提交并发 ≤2」）。
private actor FlowSubmitGate {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
        active += 1
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            // 直接把名额交给等待者，避免 release 后名额短暂空出导致并发超限。
            next.resume()
            return
        }
        active = max(0, active - 1)
    }
}

/// 连读状态机（setup → running → summary）。
///
/// 关键约束（对齐 HOS `FlowVM` + screens.md §4）：
/// - 录完立刻 `submitAsync`（异步 Task，最多 2 个在途），然后进入下一句，不阻塞；
/// - 轮询 `/attempts/status` 只传 pending/scoring 的 id，全部 settled 后停表并进汇总；
/// - 页面不可见 / 切后台必须 `pause()`：停轮询、停录音、停播放（提交中的请求允许完成）；
/// - 失败项保留 attempt id / 本地录音状态，支持「重录这句」；不允许在 View 里直接发网络请求。
@MainActor
@Observable
final class FlowStore {
    enum SetupPhase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    enum DiagnosisPhase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    enum FailedAction: Equatable {
        case none
        case load
        case record
        case submit
        case diagnosis
    }

    // MARK: - 依赖

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore
    @ObservationIgnored private let corpus: CorpusRepository
    @ObservationIgnored private let submitGate = FlowSubmitGate(limit: 2)

    // MARK: - 阶段

    private(set) var phase: FlowPhase = .setup
    private(set) var round = 1

    // MARK: - setup

    var source: FlowSource = .corpus
    let levels: [String] = ["A1", "A2", "B1", "B2", "ALL"]
    let counts: [Int] = [5, 10, 15]
    private(set) var level: String
    private(set) var count = 5
    private(set) var startIndex = 0
    private(set) var randomMode = false
    private(set) var randomPick: [SentenceDTO] = []
    private(set) var corpusSentences: [SentenceDTO] = []
    private(set) var corpusPhase: SetupPhase = .idle
    private(set) var corpusError: UIMessage?
    private(set) var preview: [SentenceDTO] = []
    private(set) var customInput = ""
    private(set) var customSentences: [String] = []
    private(set) var setupError: String?

    // MARK: - running

    private(set) var items: [FlowItem] = []
    private(set) var runSentences: [FlowRunSentence] = []
    private(set) var currentIndex = 0
    var autoNext = true
    private(set) var expandedIndex = -1
    private(set) var recording = false
    private(set) var preparing = false
    private(set) var isPreparingDemo = false
    private(set) var isPlayingDemo = false
    private(set) var uploadingCount = 0
    private(set) var elapsedMs = 0
    private(set) var allSubmitted = false
    private(set) var limitReached = false
    private(set) var limitMessage: UIMessage?
    private(set) var errorMessage: UIMessage?
    private(set) var lastFailedAction: FailedAction = .none

    // MARK: - summary

    private(set) var summary = FlowSummaryData()
    private(set) var diagnosisPhase: DiagnosisPhase = .idle
    private(set) var diagnosisError: UIMessage?
    private(set) var diagnosisSummary = ""
    private(set) var diagnosisTags: [FlowDiagnosisTag] = []

    /// 全部 settled 时由页面注入（push `.flowSummary`）；页面不可见时由 FlowView 自行处理。
    var onFinished: (() -> Void)?
    /// FlowView 的可见性（Tab 切换 / 被二级页覆盖时为 false）。
    var isVisible = false

    // MARK: - 内部

    private var started = false
    private var finished = false
    /// 每轮运行的代号：`backToSetup` / `reread` 后丢弃上一轮迟到的上传结果。
    private var runToken = 0
    private var recordStartedAt = Date()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var recordTimer: Task<Void, Never>?
    @ObservationIgnored private var advanceTask: Task<Void, Never>?
    /// 示范音（与跟读一致：听示范 / 跟我读）
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private let audioCache = AudioCache()
    @ObservationIgnored private var submissionTasks: [Task<Void, Never>] = []

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
        self.level = PracticeLevels.normalized(session.user?.normalizedLevel ?? "A1")
        self.corpus = CorpusRepository(service: services.practice)
    }

    // MARK: - 派生状态

    var isChild: Bool { session.isChild }
    var caps: RoleCapabilities { session.capabilities }
    var sourceOptions: [FlowSource] { FlowSource.allCases }

    var currentItem: FlowItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var submittedCount: Int {
        items.filter { $0.status != .unsent }.count
    }

    var pendingCount: Int {
        items.filter { $0.status == .pending || $0.status == .scoring || $0.status == .uploading }.count
    }

    var doneCount: Int {
        items.filter { $0.status == .done }.count
    }

    var failedCount: Int {
        items.filter { $0.status == .failed }.count
    }

    var progressPercent: Int {
        guard !items.isEmpty else { return 0 }
        return Int((Double(submittedCount) / Double(items.count) * 100).rounded())
    }

    var canStartRun: Bool {
        source == .corpus ? !preview.isEmpty : !customSentences.isEmpty
    }

    var levelPoolSize: Int { corpusSentences.count }

    // MARK: - 生命周期

    func startIfNeeded() async {
        guard !started else { return }
        started = true
        await loadCorpus()
    }

    /// 页面不可见 / 切后台：停轮询、停录音、停播放（在途上传允许完成，避免丢记录）。
    func pause() {
        cancelDemo()
        stopPolling()
        recordTimer?.cancel()
        recordTimer = nil
        advanceTask?.cancel()
        advanceTask = nil
        recording = false
        preparing = false
        elapsedMs = 0
        Task { @MainActor [weak self] in
            await self?.audio.stopAll()
        }
    }

    func resumePolling() {
        guard phase == .running else { return }
        if !pendingIDs.isEmpty {
            startPolling()
        } else {
            checkAllSettled()
        }
    }

    func handleScenePhase(_ scenePhase: ScenePhase) async {
        switch scenePhase {
        case .active:
            isVisible = true
            resumePolling()
        case .background:
            pause()
        default:
            break
        }
    }

    // MARK: - setup：语料

    func loadCorpus(force: Bool = false) async {
        corpusPhase = .loading
        corpusError = nil
        lastFailedAction = .load
        do {
            let userId = session.user?.id ?? ""
            var merged: [SentenceDTO] = []
            if level == "ALL" {
                for each in PracticeLevels.all {
                    if let part = try? await corpus.sentences(level: each, focus: "", userId: userId, force: force) {
                        merged.append(contentsOf: part)
                    }
                }
                if merged.isEmpty {
                    throw APIError.server(code: .notFound, message: nil, status: 404)
                }
            } else {
                merged = try await corpus.sentences(level: level, focus: "", userId: userId, force: force)
            }
            guard !Task.isCancelled else { return }
            corpusSentences = merged
            if startIndex >= merged.count {
                startIndex = 0
            }
            if randomMode {
                drawRandomSentences()
            } else {
                refreshPreview()
            }
            corpusPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            if let apiError = error as? APIError, apiError.isCancelled {
                return
            }
            corpusSentences = []
            preview = []
            corpusPhase = .failed
            corpusError = ErrorMapper.message(for: error, isChild: isChild)
            await handleAuthIfNeeded(corpusError)
        }
    }

    func setLevel(_ newLevel: String) {
        guard newLevel != level else { return }
        level = newLevel
        startIndex = 0
        randomPick = []
        setupError = nil
        Task { await loadCorpus() }
    }

    func setSource(_ newSource: FlowSource) {
        source = newSource
        setupError = nil
        if newSource == .corpus, corpusPhase == .idle {
            Task { await loadCorpus() }
        }
    }

    func setCount(_ newCount: Int) {
        guard counts.contains(newCount), newCount != count else { return }
        count = newCount
        if randomMode {
            drawRandomSentences()
        } else {
            refreshPreview()
        }
    }

    func setStartIndex(_ value: Int) {
        let maxValue = max(corpusSentences.count - 1, 0)
        startIndex = min(max(value, 0), maxValue)
        refreshPreview()
    }

    func setRandomMode(_ enabled: Bool) {
        randomMode = enabled
        if enabled {
            drawRandomSentences()
        } else {
            randomPick = []
            refreshPreview()
        }
    }

    func drawRandomSentences() {
        guard !corpusSentences.isEmpty else {
            randomPick = []
            refreshPreview()
            return
        }
        var indices = Array(corpusSentences.indices)
        indices.shuffle()
        let wanted = min(count, corpusSentences.count)
        randomPick = indices.prefix(wanted).map { corpusSentences[$0] }
        refreshPreview()
    }

    private func refreshPreview() {
        if randomMode, !randomPick.isEmpty {
            preview = randomPick
            return
        }
        guard !corpusSentences.isEmpty else {
            preview = []
            return
        }
        preview = Array(corpusSentences.dropFirst(startIndex).prefix(count))
    }

    // MARK: - setup：自己输入

    func setCustomInput(_ text: String) {
        customInput = text
        setupError = nil
    }

    func updateCustomSentence(index: Int, text: String) {
        guard customSentences.indices.contains(index) else { return }
        customSentences[index] = text
    }

    func splitCustom() {
        customSentences = FlowText.splitSentences(customInput)
        if customSentences.isEmpty {
            setupError = isChild ? "先写几句英文吧" : "没有切出句子：先输入一段英文，再点「切句」"
        } else {
            setupError = nil
        }
    }

    // MARK: - 开始连读

    func startCorpus() {
        guard !preview.isEmpty else {
            setupError = isChild ? "这里还没有句子，换一个起点吧" : "这个位置没有句子，换个起点或级别试试"
            return
        }
        let sentences = preview.map { FlowRunSentence(text: $0.text, sentenceId: $0.id, source: "corpus") }
        beginRun(sentences)
    }

    func startCustom() {
        if customSentences.isEmpty {
            customSentences = FlowText.splitSentences(customInput)
        }
        let texts = customSentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !texts.isEmpty else {
            setupError = isChild ? "先写几句话吧" : "先输入一段文本，再点「切句」"
            return
        }
        beginRun(texts.map { FlowRunSentence(text: $0, sentenceId: "", source: "custom") })
    }

    private func beginRun(_ sentences: [FlowRunSentence]) {
        runToken += 1
        runSentences = sentences
        items = buildItems(sentences)
        currentIndex = 0
        round = 1
        expandedIndex = -1
        phase = .running
        allSubmitted = false
        finished = false
        limitReached = false
        limitMessage = nil
        recording = false
        preparing = false
        uploadingCount = 0
        elapsedMs = 0
        errorMessage = nil
        setupError = nil
        lastFailedAction = .none
        diagnosisPhase = .idle
        diagnosisSummary = ""
        diagnosisTags = []
        diagnosisError = nil
        stopPolling()
        recordTimer?.cancel()
        recordTimer = nil
        advanceTask?.cancel()
        advanceTask = nil
    }

    private func buildItems(_ sentences: [FlowRunSentence]) -> [FlowItem] {
        sentences.enumerated().map { index, sentence in
            FlowItem(
                index: index,
                text: sentence.text,
                sentenceId: sentence.sentenceId,
                source: sentence.source
            )
        }
    }

    // MARK: - running：录音

    func startRecording() async {
        guard phase == .running, !recording, !preparing, let item = currentItem else { return }
        guard item.status == .unsent else { return }
        guard !limitReached else {
            refreshLimitMessage()
            return
        }
        errorMessage = nil
        isPreparingDemo = false
        isPlayingDemo = false
        lastFailedAction = .record
        preparing = true
        if audio.permission != .granted {
            let granted = await audio.requestPermission()
            guard granted, !Task.isCancelled else {
                preparing = false
                return
            }
        }
        do {
            try await audio.startRecording()
            recording = true
            recordStartedAt = Date()
            elapsedMs = 0
            startRecordTimer()
        } catch {
            await handle(error)
        }
        preparing = false
    }

    // MARK: - running：示范音（听示范 / 跟我读）

    /// 播当前句的示范音；`autoRecord == true` 时播完自动开始录音（「跟我读」）。
    func playDemo(autoRecord: Bool) {
        guard phase == .running, let item = currentItem, item.status == .unsent,
              !recording, !preparing else { return }
        demoTask?.cancel()
        errorMessage = nil
        isPreparingDemo = true
        isPlayingDemo = false
        demoTask = Task { @MainActor [weak self] in
            await self?.runDemo(autoRecord: autoRecord)
        }
    }

    private func runDemo(autoRecord: Bool) async {
        guard let item = currentItem else {
            isPreparingDemo = false
            return
        }
        do {
            let data = try await demoAudio(for: item.text)
            try Task.checkCancellation()
            // 取音频期间用户可能已经点了「开始说」：不要在录音开始后再起播。
            guard !recording, !preparing else {
                isPreparingDemo = false
                return
            }
            isPreparingDemo = false
            isPlayingDemo = true
            try await audio.play(data: data, formatHint: TTSFormat.wav.rawValue)
            await waitForDemoPlaybackEnd()
            isPlayingDemo = false
            guard autoRecord, !recording, !preparing, !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await startRecording()
        } catch is CancellationError {
            isPreparingDemo = false
            isPlayingDemo = false
        } catch {
            isPreparingDemo = false
            isPlayingDemo = false
            await handle(error)
        }
    }

    /// 先落 `AudioCache` 再播：命中缓存时不发 `/tts`（与跟读页同一套键）。
    private func demoAudio(for text: String) async throws -> Data {
        let voice = session.prefs.voice()
        let voiceArg = voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : voice
        let rate = demoRate
        let key = AudioCache.ttsKey(
            text: text,
            rate: rate.rawValue,
            voice: voiceArg,
            format: TTSFormat.wav.rawValue
        )
        if let cached = await audioCache.data(for: key) {
            return cached
        }
        let data = try await services.practice.synthesize(
            text: text,
            rate: rate,
            voice: voiceArg,
            format: .wav
        )
        await audioCache.store(data, for: key)
        return data
    }

    private var demoRate: TTSRate {
        guard !isChild else { return .slow }
        return session.prefs.ttsRate == TTSRate.slow.rawValue ? .slow : .normal
    }

    private func waitForDemoPlaybackEnd(timeoutMs: Int = 30_000) async {
        var waited = 0
        while audio.isPlaying && waited < timeoutMs {
            if Task.isCancelled {
                await audio.stopPlayback()
                return
            }
            try? await Task.sleep(for: .milliseconds(80))
            waited += 80
        }
    }

    /// 停掉示范音任务与标志（页面暂停 / 退出运行态 / 切句时调用）。
    private func cancelDemo() {
        demoTask?.cancel()
        demoTask = nil
        isPreparingDemo = false
        isPlayingDemo = false
    }

    func stopAndSubmit() async {
        guard recording else { return }
        recording = false
        recordTimer?.cancel()
        recordTimer = nil
        elapsedMs = 0
        let index = currentIndex
        do {
            let recorded = try await audio.stopRecording()
            beginSubmission(index: index, recorded: recorded)
        } catch {
            await handle(error)
        }
    }

    func cancelRecording() async {
        recording = false
        recordTimer?.cancel()
        recordTimer = nil
        elapsedMs = 0
        await audio.cancelRecording()
    }

    private func startRecordTimer() {
        recordTimer?.cancel()
        recordStartedAt = Date()
        recordTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.recording else { return }
                let elapsed = Int(Date().timeIntervalSince(self.recordStartedAt) * 1000)
                self.elapsedMs = min(elapsed, 60_000)
                if self.elapsedMs >= 60_000 {
                    await self.stopAndSubmit()
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    // MARK: - running：异步提交（并发 ≤2）

    private func beginSubmission(index: Int, recorded: RecordedAudio) {
        guard items.indices.contains(index) else { return }
        items[index].status = .uploading
        items[index].attemptId = ""
        items[index].errorText = ""
        items[index].result = nil
        uploadingCount += 1
        let token = runToken
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.submitGate.acquire()
            await self.performSubmit(index: index, recorded: recorded, token: token)
            await self.submitGate.release()
            self.uploadingCount = max(0, self.uploadingCount - 1)
            self.checkAllSettled()
        }
        submissionTasks.append(task)
    }

    private func performSubmit(index: Int, recorded: RecordedAudio, token: Int) async {
        guard items.indices.contains(index), token == runToken else { return }
        let item = items[index]
        lastFailedAction = .submit
        do {
            let response = try await services.flow.submitAsync(
                audioData: recorded.data,
                referenceText: item.text,
                sentenceId: item.sentenceId,
                source: item.source,
                materialId: nil,
                durationMs: recorded.durationMs
            )
            guard token == runToken else { return }
            let attemptId = (response.attemptId?.isEmpty == false ? response.attemptId : nil)
                ?? (response.id?.isEmpty == false ? response.id : nil)
                ?? ""
            guard !attemptId.isEmpty else {
                throw APIError.decoding(path: "attempts/async")
            }
            guard items.indices.contains(index) else { return }
            items[index].attemptId = attemptId
            items[index].status = .pending
            items[index].errorText = ""
            checkAllSubmitted()
            startPolling()
            scheduleAdvance(from: index)
        } catch is CancellationError {
            guard token == runToken, items.indices.contains(index) else { return }
            items[index].status = .failed
            items[index].errorText = "已取消"
        } catch {
            guard token == runToken else { return }
            if items.indices.contains(index) {
                items[index].status = .failed
                items[index].errorText = errorText(for: error)
            }
            if let apiError = error as? APIError,
               case .server(let code, _, _) = apiError,
               code == .dailyLimitReached {
                limitReached = true
                refreshLimitMessage()
            } else {
                await handle(error)
            }
            checkAllSubmitted()
        }
    }

    private func scheduleAdvance(from index: Int) {
        advanceTask?.cancel()
        guard autoNext else {
            checkAllSettled()
            return
        }
        advanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            if let next = self.nextUnsentIndex(after: index) {
                self.currentIndex = next
                self.errorMessage = nil
            }
            self.checkAllSettled()
        }
    }

    // MARK: - running：轮询

    func startPolling() {
        guard pollTask == nil, phase == .running, !pendingIDs.isEmpty else { return }
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if self.phase != .running || self.pendingIDs.isEmpty {
                    break
                }
                await self.pollOnce()
                try? await Task.sleep(for: .milliseconds(1500))
            }
            self.pollTask = nil
            self.checkAllSettled()
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private var pendingIDs: [String] {
        items.compactMap { item in
            guard !item.attemptId.isEmpty else { return nil }
            guard item.status == .pending || item.status == .scoring else { return nil }
            return item.attemptId
        }
    }

    private func pollOnce() async {
        guard phase == .running else { return }
        let ids = Array(pendingIDs.prefix(50))
        guard !ids.isEmpty else {
            stopPolling()
            checkAllSettled()
            return
        }
        do {
            let updates = try await services.flow.status(ids: ids)
            guard !Task.isCancelled else { return }
            for update in updates {
                guard let index = items.firstIndex(where: { $0.attemptId == update.id }) else { continue }
                apply(update: update, at: index)
            }
        } catch is CancellationError {
            return
        } catch {
            // 轮询失败静默：下一拍重试（screens.md §4.5）。
            flowLogger.debug("flow status poll failed")
        }
        if pendingIDs.isEmpty {
            stopPolling()
        }
        checkAllSettled()
    }

    private func apply(update: AsyncStatusItemDTO, at index: Int) {
        let status = FlowResultMapper.status(from: update.status)
        items[index].status = status
        switch status {
        case .failed:
            items[index].errorText = "评分没有成功，可以重录这句"
            items[index].result = nil
        case .done:
            if let result = update.result {
                items[index].result = FlowResultMapper.make(from: result, isChild: isChild)
                items[index].errorText = ""
            } else {
                items[index].status = .failed
                items[index].errorText = "评分结果格式异常，可以重录这句"
                items[index].result = nil
            }
        default:
            break
        }
    }

    // MARK: - running：状态 / 交互

    func nextSentence() {
        cancelDemo()
        guard let next = nextUnsentIndex(after: currentIndex) else {
            checkAllSettled()
            return
        }
        currentIndex = next
        errorMessage = nil
        checkAllSettled()
    }

    func toggleExpanded(index: Int) {
        expandedIndex = expandedIndex == index ? -1 : index
    }

    private func nextUnsentIndex(after from: Int) -> Int? {
        guard !items.isEmpty else { return nil }
        for index in (from + 1)..<items.count where items[index].status == .unsent {
            return index
        }
        for index in 0..<items.count where items[index].status == .unsent {
            return index
        }
        return nil
    }

    private func checkAllSubmitted() {
        allSubmitted = !items.contains { $0.status == .unsent }
    }

    private func checkAllSettled() {
        guard phase == .running, !finished else { return }
        guard allSubmitted, uploadingCount == 0 else { return }
        guard pendingCount == 0 else { return }
        finishRun()
    }

    /// 全部 done/failed → 停表 → 计算汇总快照 → 通知页面 push 汇总页。
    func finishRun() {
        finished = true
        stopPolling()
        recordTimer?.cancel()
        recordTimer = nil
        advanceTask?.cancel()
        advanceTask = nil
        recording = false
        summary = buildSummary()
        phase = .summary
        let callback = onFinished
        callback?()
    }

    func retryItem(index: Int) {
        cancelDemo()
        guard items.indices.contains(index) else { return }
        items[index].resetForRedo()
        currentIndex = index
        expandedIndex = -1
        phase = .running
        finished = false
        allSubmitted = false
        limitReached = false
        limitMessage = nil
        errorMessage = nil
        stopPolling()
        advanceTask?.cancel()
        advanceTask = nil
        checkAllSettled()
    }

    func reread() {
        guard !runSentences.isEmpty else { return }
        runToken += 1
        items = buildItems(runSentences)
        currentIndex = 0
        expandedIndex = -1
        round += 1
        phase = .running
        allSubmitted = false
        finished = false
        limitReached = false
        limitMessage = nil
        recording = false
        preparing = false
        uploadingCount = 0
        elapsedMs = 0
        errorMessage = nil
        diagnosisPhase = .idle
        diagnosisSummary = ""
        diagnosisTags = []
        diagnosisError = nil
        stopPolling()
        recordTimer?.cancel()
        recordTimer = nil
        advanceTask?.cancel()
        advanceTask = nil
    }

    func backToSetup() {
        cancelDemo()
        runToken += 1
        phase = .setup
        items = []
        runSentences = []
        currentIndex = 0
        round = 1
        expandedIndex = -1
        allSubmitted = false
        finished = false
        limitReached = false
        limitMessage = nil
        recording = false
        preparing = false
        uploadingCount = 0
        elapsedMs = 0
        errorMessage = nil
        setupError = nil
        summary = FlowSummaryData()
        diagnosisPhase = .idle
        diagnosisSummary = ""
        diagnosisTags = []
        diagnosisError = nil
        stopPolling()
        recordTimer?.cancel()
        recordTimer = nil
        advanceTask?.cancel()
        advanceTask = nil
    }

    // MARK: - running / summary：文案

    func statusBadge(_ item: FlowItem) -> String {
        switch item.status {
        case .unsent: return "未读"
        case .uploading: return "上传中…"
        case .pending: return "待评分…"
        case .scoring: return "评分中…"
        case .done:
            guard let score = item.scorePron else { return "已评分" }
            return caps.showsNumericScore ? "\(Int(score.rounded())) 分" : "已评分"
        case .failed: return "评分失败"
        }
    }

    func statusTone(_ item: FlowItem) -> PillTag.Tone {
        switch item.status {
        case .unsent: return .neutral
        case .uploading, .pending, .scoring: return .primary
        case .done: return .success
        case .failed: return caps.isChild ? .warning : .danger
        }
    }

    func currentStatusLine() -> String {
        guard let item = currentItem else { return "" }
        switch item.status {
        case .uploading: return "这一句正在上传…（可以继续读下一句）"
        case .pending: return "这一句已提交，正在排队评分…（可以继续读下一句）"
        case .scoring: return "这一句正在评分…（可以继续读下一句）"
        case .done: return "这一句已评分 ✅（可以继续读下一句）"
        case .failed: return "这一句提交或评分没有成功，可以重录这句"
        case .unsent: return ""
        }
    }

    // MARK: - summary

    func buildSummary() -> FlowSummaryData {
        var data = FlowSummaryData()
        data.round = round
        data.total = items.count
        data.items = items

        var scored = 0
        var sum = 0.0
        for item in items {
            if item.status == .failed {
                data.failedCount += 1
            }
            guard item.status == .done, let score = item.scorePron else { continue }
            scored += 1
            sum += score
            if !item.attemptId.isEmpty, data.attemptIds.count < 20 {
                data.attemptIds.append(item.attemptId)
            }
        }
        data.doneCount = scored
        data.avgScore = scored > 0 ? (sum / Double(scored) * 10).rounded() / 10 : nil
        data.worst = items.compactMap { item -> FlowWorstItem? in
            guard item.status == .done, let score = item.scorePron else { return nil }
            return FlowWorstItem(index: item.index, score: score, text: item.text)
        }
        .sorted { lhs, rhs in
            (lhs.score ?? 0) < (rhs.score ?? 0)
        }
        .prefix(3)
        .map { $0 }

        data.encouragement = FlowEncouragementBuilder.make(
            items: items,
            total: items.count,
            doneCount: scored,
            avgScore: data.avgScore,
            attemptIds: data.attemptIds
        )
        return data
    }

    /// 汇总页：批次诊断 `GET /diagnosis?scope=batch`（≤20 个 attempt id）。
    func loadDiagnosisIfNeeded() async {
        guard diagnosisPhase == .idle else { return }
        await loadDiagnosis()
    }

    func loadDiagnosis() async {
        let ids = summary.attemptIds
        guard !ids.isEmpty else {
            diagnosisPhase = .loaded
            return
        }
        diagnosisPhase = .loading
        diagnosisError = nil
        lastFailedAction = .diagnosis
        do {
            let dto = try await services.flow.diagnosisBatch(attemptIds: ids)
            culpritLabel(dto: dto)
            diagnosisPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            if let apiError = error as? APIError, apiError.isCancelled {
                return
            }
            diagnosisError = ErrorMapper.message(for: error, isChild: isChild)
            diagnosisPhase = .failed
            await handleAuthIfNeeded(diagnosisError)
        }
    }

    private func culpritLabel(dto: FlowDiagnosisDTO) {
        diagnosisSummary = dto.summaryZh ?? ""
        var tags: [FlowDiagnosisTag] = []
        for (index, item) in (dto.items ?? []).prefix(5).enumerated() {
            let label = diagnosisLabel(for: item, index: index)
            guard !label.isEmpty else { continue }
            tags.append(FlowDiagnosisTag(index: index, label: label, status: item.status ?? "watch"))
        }
        if tags.isEmpty, diagnosisSummary.isEmpty {
            diagnosisSummary = isChild
                ? "这一批读得不错，继续保持"
                : "这一批没有明显的薄弱音素，保持就好 👍"
        }
        diagnosisTags = tags
    }

    private func diagnosisLabel(for item: FlowDiagnosisItemDTO, index: Int) -> String {
        let phoneme = item.phoneme ?? ""
        let childLabel = item.childLabel ?? ""
        var label: String
        if isChild {
            // 儿童绝不出现 IPA：只认服务端给的口语化名字，没有就整条不展示。
            label = childLabel
        } else if !phoneme.isEmpty {
            label = "/\(phoneme)/"
            if !childLabel.isEmpty {
                label = label + " " + childLabel
            }
        } else {
            label = childLabel
        }
        guard !label.isEmpty else { return "" }
        if caps.showsNumericScore, let avg = item.avgScore {
            label += " · \(Int(avg.rounded())) 分"
        }
        return label
    }

    // MARK: - 错误

    func clearError() {
        errorMessage = nil
    }

    func clearSetupError() {
        setupError = nil
    }

    private func errorText(for error: Error) -> String {
        let message = ErrorMapper.message(for: error, isChild: isChild)
        return message.title.isEmpty ? "提交没有成功" : message.title
    }

    private func handle(_ error: Error) async {
        if let apiError = error as? APIError, apiError.isCancelled {
            return
        }
        if error is CancellationError {
            return
        }
        let message = ErrorMapper.message(for: error, isChild: isChild)
        guard !message.isSilent else { return }
        errorMessage = message
        flowLogger.debug("flow action failed")
        await handleAuthIfNeeded(message)
    }

    private func handleAuthIfNeeded(_ message: UIMessage?) async {
        guard let message, message.action == .relogin else { return }
        await session.handleSessionExpired()
    }

    private func refreshLimitMessage() {
        guard limitReached else {
            limitMessage = nil
            return
        }
        limitMessage = ErrorMapper.message(
            for: APIError.server(code: .dailyLimitReached, message: nil, status: 429),
            isChild: isChild
        )
    }
}

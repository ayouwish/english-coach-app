import Foundation
import Observation
import OSLog
import SwiftUI

private let practiceLogger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "practice")

/// 跟读页状态（卡片流 + 页内结果）。
///
/// 职责边界：
/// - 网络只走 `PracticeService` / `DictionaryService`（经 `AppServices` 注入）；
/// - 录音、播放只走 `AudioCoordinator`（页面/Store 都不碰 AVAudio*）；
/// - 错误文案只由 `ErrorMapper` 生产，页面渲染 `UIMessage`；
/// - 儿童/成人差异只读 `SessionStore.capabilities`。
@MainActor
@Observable
final class PracticeStore {
    enum LoadPhase: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    enum RecordingPhase: Equatable {
        case idle
        case recording
        case evaluating
    }

    /// 最近一次失败的操作：错误条上的「重试」据此重放对应动作。
    enum FailedAction: Equatable {
        case none
        case demo
        case follow
        case record
        case evaluate
        case playback
        case load
        case ipa
    }

    // MARK: - 依赖

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore
    @ObservationIgnored private let corpus: CorpusRepository
    @ObservationIgnored private let audioCache = AudioCache()

    // MARK: - 数据

    private(set) var level: String
    private(set) var sentences: [SentenceDTO] = []
    private(set) var index = 0
    private(set) var loadPhase: LoadPhase = .idle
    private(set) var loadError: UIMessage?
    /// 练习游标：上次练到第几句（-1 = 无提示）。
    private(set) var resumeIndex = -1
    private(set) var isSingleSentence = false

    // MARK: - 音频 / 提交状态

    private(set) var recordingPhase: RecordingPhase = .idle
    private(set) var elapsedMs = 0
    private(set) var permission: MicPermission
    private(set) var isPreparingDemo = false
    private(set) var isPlayingDemo = false
    private(set) var isPlayingRecording = false
    private(set) var isEvaluating = false

    // MARK: - 结果 / 错误

    private(set) var result: PracticeAttemptResult?
    private(set) var errorMessage: UIMessage?
    private(set) var infoMessage: UIMessage?
    private(set) var limitMessage: UIMessage?
    private(set) var canRetryEvaluate = false
    private(set) var lastFailedAction: FailedAction = .none

    // MARK: - 内部

    private var started = false
    private var recordStartedAt = Date()
    private var lastAttemptId = ""
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private var recordingTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore, level: String) {
        self.services = services
        self.audio = audio
        self.session = session
        self.level = PracticeLevels.normalized(level)
        self.corpus = CorpusRepository(service: services.practice)
        self.permission = audio.permission
    }

    // MARK: - 派生状态

    var caps: RoleCapabilities { session.capabilities }
    var isRecording: Bool { recordingPhase == .recording }
    var total: Int { sentences.count }
    var canGoPrevious: Bool { index > 0 }
    var canGoNext: Bool { index + 1 < sentences.count }
    var progressText: String { total > 0 ? "\(index + 1) / \(total)" : "" }

    var currentSentence: SentenceDTO? {
        guard sentences.indices.contains(index) else { return nil }
        return sentences[index]
    }

    var currentText: String { currentSentence?.text ?? "" }
    var currentTranslation: String { currentSentence?.translationZh ?? "" }

    /// 重点音素：儿童不展示（服务端也会剥离，客户端双保险）。
    var focusPhonemes: [String] {
        guard !caps.isChild, let sentence = currentSentence else { return [] }
        return sentence.focusPhonemes
    }

    /// 示范音语速：儿童固定慢速；成人优先账号偏好。
    var defaultDemoRate: TTSRate {
        guard !caps.isChild else { return .slow }
        return session.prefs.ttsRate == TTSRate.slow.rawValue ? .slow : .normal
    }

    /// 今日是否已到练习时长上限（前置禁用录音/评测）。
    var isLimitReached: Bool {
        guard let usage = session.usage else { return false }
        if usage.exceeded == true {
            return true
        }
        if let remaining = usage.remainingMinutes, remaining <= 0 {
            return true
        }
        return false
    }

    /// 今日用量文案（对方括号里的限制值来自服务端；缺失时不显示）。
    var usageText: String {
        guard let usage = session.usage else { return "" }
        let minutes = usage.minutes ?? 0
        if minutes <= 0 {
            return "今天还没有开始练"
        }
        let value = String(format: "%.1f", minutes)
        if let limit = usage.limitMinutes, limit > 0 {
            return "今天已练 \(value) / \(limit) 分钟"
        }
        return "今天已练 \(value) 分钟"
    }

    var showsResumeBanner: Bool { !isSingleSentence && resumeIndex > 0 }

    // MARK: - 生命周期

    /// 页面出现时调用：准备音频、刷新权限/限额；首次自动拉语料。
    func startIfNeeded() async {
        permission = audio.permission
        await audio.prepare()
        permission = audio.permission
        refreshLimitMessage()
        guard !started else { return }
        started = true
        if loadPhase == .idle {
            await load()
        }
    }

    /// 单句跟读页：只练这一句（不写练习游标）。
    func configureSingle(sentence: SentenceDTO, level: String) {
        self.level = PracticeLevels.normalized(level)
        sentences = [sentence]
        index = 0
        loadPhase = .loaded
        loadError = nil
        resumeIndex = -1
        isSingleSentence = true
        started = true
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            await audio.prepare()
            permission = audio.permission
            refreshLimitMessage()
        case .background:
            await stopAll()
        default:
            break
        }
    }

    // MARK: - 语料

    func load(force: Bool = false) async {
        loadPhase = .loading
        loadError = nil
        lastFailedAction = .load
        do {
            let list = try await corpus.sentences(
                level: level,
                focus: "",
                userId: session.user?.id ?? "",
                force: force
            )
            guard !Task.isCancelled else { return }
            sentences = list
            index = min(index, max(list.count - 1, 0))
            loadPhase = .loaded
            prepareResumeCursor()
            warmupNeighbors()
            if !list.isEmpty {
                PracticeCursorStore.save(
                    sentenceId: list[index].id,
                    level: level,
                    userId: session.user?.id ?? ""
                )
            }
        } catch is CancellationError {
            return
        } catch {
            if let apiError = error as? APIError, apiError.isCancelled {
                return
            }
            let message = ErrorMapper.message(for: error, isChild: caps.isChild)
            loadError = message
            loadPhase = .failed
            await handleAuthIfNeeded(message)
        }
    }

    func reload(force: Bool = true) async {
        await load(force: force)
    }

    func selectLevel(_ newLevel: String) async {
        let mapped = PracticeLevels.normalized(newLevel)
        guard mapped != level else { return }
        await stopAll()
        level = mapped
        index = 0
        sentences = []
        result = nil
        lastAttemptId = ""
        await load()
    }

    func select(index newIndex: Int) {
        guard sentences.indices.contains(newIndex), newIndex != index else { return }
        demoTask?.cancel()
        demoTask = nil
        stopPlayback()
        index = newIndex
        resetAttempt()
        saveCursor()
        permission = audio.permission
    }

    func next() {
        guard canGoNext else { return }
        select(index: index + 1)
    }

    func previous() {
        guard canGoPrevious else { return }
        select(index: index - 1)
    }

    func continueFromResume() {
        guard resumeIndex > 0, sentences.indices.contains(resumeIndex) else {
            resumeIndex = -1
            return
        }
        index = resumeIndex
        resumeIndex = -1
        resetAttempt()
        saveCursor()
    }

    func startFromBeginning() {
        PracticeCursorStore.clear(level: level, userId: session.user?.id ?? "")
        resumeIndex = -1
        index = 0
        resetAttempt()
    }

    // MARK: - 示范音

    /// 播示范音；`autoRecord == true` 时播完自动开始录音（「跟我读」）。
    func playDemo(autoRecord: Bool) {
        guard currentSentence != nil, !isEvaluating else { return }
        if isRecording {
            errorMessage = ErrorMapper.message(
                for: AudioError.engine("busy"),
                isChild: caps.isChild
            )
            return
        }
        demoTask?.cancel()
        demoTask = Task { @MainActor [weak self] in
            await self?.runDemo(autoRecord: autoRecord)
        }
    }

    private func runDemo(autoRecord: Bool) async {
        guard let sentence = currentSentence else { return }
        lastFailedAction = autoRecord ? .follow : .demo
        errorMessage = nil
        isPreparingDemo = true
        isPlayingDemo = false
        do {
            let data = try await demoAudio(for: sentence)
            try Task.checkCancellation()
            isPreparingDemo = false
            isPlayingDemo = true
            try await audio.play(data: data, formatHint: TTSFormat.wav.rawValue)
            await waitForPlaybackEnd()
            isPlayingDemo = false
            guard autoRecord, !Task.isCancelled else { return }
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

    /// 先落 `AudioCache` 再播：命中缓存时不发 `/tts`（正常 < 300ms 起播）。
    private func demoAudio(for sentence: SentenceDTO) async throws -> Data {
        let rate = defaultDemoRate
        let voice = session.prefs.voice()
        let voiceArg = voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : voice
        let key = AudioCache.ttsKey(
            text: sentence.text,
            rate: rate.rawValue,
            voice: voiceArg,
            format: TTSFormat.wav.rawValue
        )
        if let cached = await audioCache.data(for: key) {
            return cached
        }
        let data = try await services.practice.synthesize(
            text: sentence.text,
            rate: rate,
            voice: voiceArg,
            format: .wav
        )
        await audioCache.store(data, for: key)
        return data
    }

    // MARK: - 录音

    func startRecording() async {
        guard currentSentence != nil, !isEvaluating, !isRecording else { return }
        guard !isLimitReached else {
            refreshLimitMessage()
            return
        }
        demoTask?.cancel()
        errorMessage = nil
        infoMessage = nil
        lastFailedAction = .record

        if audio.permission != .granted {
            let granted = await audio.requestPermission()
            permission = audio.permission
            guard granted, !Task.isCancelled else { return }
        }

        do {
            try await audio.startRecording()
            recordingPhase = .recording
            recordStartedAt = Date()
            elapsedMs = 0
            result = nil
            lastAttemptId = ""
            canRetryEvaluate = false
            startRecordingTimer()
        } catch {
            recordingPhase = .idle
            await handle(error)
        }
    }

    func stopRecordingAndEvaluate() async {
        guard recordingPhase == .recording else { return }
        recordingTask?.cancel()
        recordingTask = nil
        recordingPhase = .evaluating
        elapsedMs = 0

        let recorded: RecordedAudio
        do {
            recorded = try await audio.stopRecording()
        } catch {
            recordingPhase = .idle
            await handle(error)
            return
        }
        guard let sentence = currentSentence else {
            recordingPhase = .idle
            return
        }
        guard recorded.data.count <= 12 * 1024 * 1024 else {
            recordingPhase = .idle
            errorMessage = ErrorMapper.message(
                for: APIError.payloadTooLarge(localBytes: recorded.data.count),
                isChild: caps.isChild
            )
            return
        }

        isEvaluating = true
        errorMessage = nil
        lastFailedAction = .evaluate
        do {
            let response = try await services.practice.evaluate(
                audioData: recorded.data,
                filename: recorded.filename,
                mimeType: recorded.mimeType,
                sentenceId: sentence.id,
                referenceText: sentence.text,
                mode: .scripted,
                durationMs: recorded.durationMs
            )
            try Task.checkCancellation()
            apply(response: response, sentence: sentence)
        } catch is CancellationError {
            // 页面已离开：结果不再落地。
        } catch {
            await handle(error)
        }
        isEvaluating = false
        recordingPhase = .idle
    }

    func cancelRecording() async {
        recordingTask?.cancel()
        recordingTask = nil
        recordingPhase = .idle
        elapsedMs = 0
        await audio.cancelRecording()
    }

    private func startRecordingTimer() {
        recordingTask?.cancel()
        recordStartedAt = Date()
        recordingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.recordingPhase == .recording else { return }
                let elapsed = Int(Date().timeIntervalSince(self.recordStartedAt) * 1000)
                self.elapsedMs = min(elapsed, 60_000)
                if self.elapsedMs >= 60_000 {
                    await self.stopRecordingAndEvaluate()
                    return
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    // MARK: - 评测结果

    private func apply(response: AttemptResponseDTO, sentence: SentenceDTO) {
        if !response.attemptId.isEmpty {
            lastAttemptId = response.attemptId
        }
        if let usage = response.usage {
            session.apply(usage: usage)
            refreshLimitMessage()
        }
        canRetryEvaluate = response.degraded == true && response.retryable != false

        if let mapped = PracticeResultMapper.make(response: response, sentenceId: sentence.id) {
            result = mapped
            PracticeResultHandoff.store(mapped)
            if response.degraded == true {
                infoMessage = ErrorMapper.message(
                    for: APIError.server(code: .providerUnavailable, message: nil, status: 503),
                    isChild: caps.isChild
                )
            } else {
                infoMessage = nil
            }
        } else {
            result = nil
            infoMessage = ErrorMapper.message(
                for: APIError.server(code: .providerUnavailable, message: nil, status: 503),
                isChild: caps.isChild
            )
        }
    }

    /// degraded 时用服务端已存录音重评（不重录、不重复上传音频）。
    func retryEvaluate() async {
        guard !isEvaluating else { return }
        let attemptId = result?.attemptId ?? lastAttemptId
        guard !attemptId.isEmpty else { return }
        isEvaluating = true
        errorMessage = nil
        infoMessage = nil
        lastFailedAction = .evaluate
        let sentenceId = result?.sentenceId ?? currentSentence?.id ?? ""
        do {
            let response = try await services.practice.retryAttempt(id: attemptId)
            try Task.checkCancellation()
            if let usage = response.usage {
                session.apply(usage: usage)
                refreshLimitMessage()
            }
            canRetryEvaluate = response.degraded == true && response.retryable != false
            if let mapped = PracticeResultMapper.make(response: response, sentenceId: sentenceId) {
                result = mapped
                PracticeResultHandoff.store(mapped)
                infoMessage = nil
            } else {
                infoMessage = ErrorMapper.message(
                    for: APIError.server(code: .providerUnavailable, message: nil, status: 503),
                    isChild: caps.isChild
                )
            }
        } catch is CancellationError {
            // 页面已离开。
        } catch {
            await handle(error)
        }
        isEvaluating = false
    }

    // MARK: - 回放

    func playRecording() {
        let attemptId = result?.attemptId ?? lastAttemptId
        guard !attemptId.isEmpty else { return }
        lastFailedAction = .playback
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await self.services.practice.audioData(audioId: attemptId)
                try Task.checkCancellation()
                self.isPlayingRecording = true
                try await self.audio.play(data: data, formatHint: "m4a")
                await self.waitForPlaybackEnd()
            } catch is CancellationError {
                // 主动停止。
            } catch {
                await self.handle(error)
            }
            self.isPlayingRecording = false
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlayingRecording = false
        isPlayingDemo = false
        isPreparingDemo = false
        Task { @MainActor [weak self] in
            await self?.audio.stopPlayback()
        }
    }

    // MARK: - 点词音标

    /// 查单词音标（仅成人；儿童 `canSeeIPA == false` 直接返回 nil）。
    func lookupIPA(for word: String) async -> PracticeIPASheet? {
        guard caps.canSeeIPA else { return nil }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        errorMessage = nil
        lastFailedAction = .ipa
        do {
            let dto = try await services.dictionary.wordIpa(word: trimmed)
            var note: String?
            if let error = dto.error, !error.isEmpty {
                note = error
            }
            if dto.ipa == nil, note == nil {
                note = "暂无音标"
            }
            return PracticeIPASheet(
                word: dto.word.isEmpty ? trimmed : dto.word,
                ipa: dto.ipa,
                variants: dto.variants ?? [],
                note: note
            )
        } catch {
            await handle(error)
            return nil
        }
    }

    // MARK: - 错误

    /// 错误条上的「重试」：按最近一次失败的动作重放，而不是一律重新录音。
    func retryLastFailedAction() async {
        switch lastFailedAction {
        case .demo:
            playDemo(autoRecord: false)
        case .follow:
            playDemo(autoRecord: true)
        case .record:
            await startRecording()
        case .evaluate:
            if canRetryEvaluate {
                await retryEvaluate()
            } else {
                await startRecording()
            }
        case .playback:
            playRecording()
        case .load:
            await load(force: true)
        case .ipa, .none:
            break
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearInfo() {
        infoMessage = nil
    }

    private func handle(_ error: Error) async {
        if let apiError = error as? APIError, apiError.isCancelled {
            return
        }
        if error is CancellationError {
            return
        }
        let message = ErrorMapper.message(for: error, isChild: caps.isChild)
        guard !message.isSilent else { return }
        errorMessage = message
        practiceLogger.debug("practice action failed")
        await handleAuthIfNeeded(message)
    }

    private func handleAuthIfNeeded(_ message: UIMessage) async {
        guard message.action == .relogin else { return }
        await session.handleSessionExpired()
    }

    // MARK: - 生命周期收尾

    /// 页面消失 / 切后台：停播放、丢录音、停计时（不支持后台录音）。
    func stopAll() async {
        demoTask?.cancel()
        demoTask = nil
        playbackTask?.cancel()
        playbackTask = nil
        recordingTask?.cancel()
        recordingTask = nil
        if recordingPhase == .recording {
            recordingPhase = .idle
            await audio.cancelRecording()
        } else {
            await audio.stopPlayback()
        }
        isPreparingDemo = false
        isPlayingDemo = false
        isPlayingRecording = false
        elapsedMs = 0
    }

    // MARK: - 内部工具

    private func resetAttempt() {
        result = nil
        errorMessage = nil
        infoMessage = nil
        canRetryEvaluate = false
        lastAttemptId = ""
        recordingPhase = .idle
        elapsedMs = 0
    }

    private func saveCursor() {
        guard !isSingleSentence, let sentence = currentSentence else { return }
        PracticeCursorStore.save(
            sentenceId: sentence.id,
            level: level,
            userId: session.user?.id ?? ""
        )
    }

    private func prepareResumeCursor() {
        resumeIndex = -1
        let userId = session.user?.id ?? ""
        guard let saved = PracticeCursorStore.load(level: level, userId: userId),
              let found = sentences.firstIndex(where: { $0.id == saved }),
              found > 0
        else {
            return
        }
        resumeIndex = found
    }

    private func warmupNeighbors() {
        guard !sentences.isEmpty else { return }
        let texts = sentences.dropFirst(index).prefix(6).map(\.text)
        guard !texts.isEmpty else { return }
        let service = services.practice
        let rate = defaultDemoRate
        Task { @MainActor in
            await service.warmup(texts: Array(texts), rate: rate)
        }
    }

    private func refreshLimitMessage() {
        guard isLimitReached else {
            limitMessage = nil
            return
        }
        limitMessage = ErrorMapper.message(
            for: APIError.server(code: .dailyLimitReached, message: nil, status: 429),
            isChild: caps.isChild
        )
    }

    /// 等播放结束（协调器没有完成回调，以 `isPlaying` 轮询；超时自动放弃等待）。
    private func waitForPlaybackEnd(timeoutMs: Int = 30_000) async {
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
}

// MARK: - 句子列表页状态

/// `.sentences` 句子列表：按等级取语料（走 `CorpusRepository` 24h 快照），点一句进入单句跟读。
@MainActor
@Observable
final class SentenceListStore {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    let session: SessionStore
    private let corpus: CorpusRepository
    private(set) var level: String
    private(set) var sentences: [SentenceDTO] = []
    private(set) var phase: Phase = .loading
    private(set) var errorMessage: UIMessage?
    private var loadedOnce = false

    let levels = PracticeLevels.all

    init(services: AppServices, session: SessionStore) {
        self.session = session
        self.corpus = CorpusRepository(service: services.practice)
        self.level = PracticeLevels.normalized(session.user?.normalizedLevel ?? "A1")
    }

    func loadIfNeeded() async {
        guard !loadedOnce else { return }
        loadedOnce = true
        await load()
    }

    func selectLevel(_ newLevel: String) async {
        let mapped = PracticeLevels.normalized(newLevel)
        guard mapped != level else { return }
        level = mapped
        sentences = []
        phase = .loading
        await load()
    }

    func load() async {
        phase = .loading
        errorMessage = nil
        do {
            let list = try await corpus.sentences(
                level: level,
                focus: "",
                userId: session.user?.id ?? "",
                force: false
            )
            guard !Task.isCancelled else { return }
            sentences = list
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            if let apiError = error as? APIError, apiError.isCancelled {
                return
            }
            let message = ErrorMapper.message(for: error, isChild: session.isChild)
            errorMessage = message
            phase = .failed
            if message.action == .relogin {
                await session.handleSessionExpired()
            }
        }
    }
}

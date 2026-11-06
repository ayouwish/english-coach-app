import Foundation
import Observation

/// 盲测模式（screens.md §7.1）：A 盲听选择 / B 盲跟读。
enum BlindQuestionMode: String, Sendable {
    case listen
    case read
}

/// 设置页的三种模式选项：只盲听 / 只盲跟读 / 交替出题。
enum BlindModeOption: String, CaseIterable, Sendable {
    case listen
    case read
    case alternating
}

/// 一道盲测题。`options` 只在盲听模式有值（4 个中文释义，含正确项）。
struct BlindQuestion: Identifiable, Sendable {
    let id: String
    let sentence: SentenceDTO
    let mode: BlindQuestionMode
    let options: [String]
    let correctIndex: Int
}

/// 盲测是「一页闭环」：开始 → 逐题（听/跟读，全程不给分数）→ 结束 → 周报/趋势。
/// 进行中**绝不展示任何分数**（screens.md §7.3：盲测硬规则）；揭晓前不显示原文。
@MainActor
@Observable
final class BlindTestStore {
    enum Phase: Equatable {
        case setup
        case running
        case summary
    }

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore

    private let ttsCache = AudioCache()
    private var prefetchTask: Task<Void, Never>?

    // MARK: - 列表 / 周报

    private(set) var phase: Phase = .setup
    private(set) var overview: BlindTestListDTO?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var loadError: UIMessage?

    // MARK: - 设置

    /// 出题模式（题量由服务端 `/blind-tests` 决定，客户端不改批次大小，
    /// 否则 `finish` 时会出现大量「待评分」条目）。
    var modeOption: BlindModeOption = .listen
    private(set) var isPreparing = false
    private(set) var startError: UIMessage?
    private(set) var setupNotice: String?

    // MARK: - 进行中

    private(set) var blindTestId: String?
    private(set) var questions: [BlindQuestion] = []
    private(set) var index = 0

    private(set) var currentAudio: Data?
    private(set) var isAudioLoading = false
    private(set) var audioErrorText: String?
    private(set) var replayCount = 0
    private(set) var selectedOption: Int?
    private(set) var isRevealed = false
    private(set) var isScoring = false
    private(set) var isFinishing = false
    /// 当前题的提示（降级 / 待评分 / 语料不足切换模式等），不是错误。
    private(set) var inlineNotice: String?
    private(set) var recordError: UIMessage?
    private(set) var wrongSentences: [SentenceDTO] = []

    // MARK: - 结束

    private(set) var finishResult: BlindFinishDTO?
    private(set) var finishError: UIMessage?

    /// 最多重听次数（screens.md §7.3）。
    static let maxReplay = 3

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

    var level: String {
        session.user?.normalizedLevel ?? "A1"
    }

    var currentQuestion: BlindQuestion? {
        guard questions.indices.contains(index) else {
            return nil
        }
        return questions[index]
    }

    var questionNumberText: String {
        "第 \(min(index + 1, max(questions.count, 1))) / \(questions.count) 题"
    }

    var canReplay: Bool {
        currentAudio != nil && replayCount < Self.maxReplay && !isAudioLoading
    }

    var replayRemaining: Int {
        max(Self.maxReplay - replayCount, 0)
    }

    /// 盲听模式：音频没准备好之前禁止作答（screens.md §7.5）。
    var canAnswerListen: Bool {
        currentAudio != nil && !isAudioLoading && !isRevealed
    }

    var inProgress: BlindTestDTO? {
        overview?.inProgress
    }

    var history: [BlindTestDTO] {
        overview?.tests ?? []
    }

    var trend: BlindTrendDTO? {
        overview?.trend
    }

    var weeks: Int {
        overview?.trend?.weeks ?? 0
    }

    var currentPron: Double? {
        overview?.trend?.current?.avgPron
    }

    var previousPron: Double? {
        overview?.trend?.previous?.avgPron
    }

    var deltaPron: Double? {
        overview?.trend?.deltaPron
    }

    var series: [BlindTrendScoreDTO] {
        overview?.series ?? []
    }

    /// 周报柱状图（历次盲测综合分，已降采样 ≤200 点）。
    var seriesBars: [BarValue] {
        let recent = ChartsData.recent(series, limit: 30)
        let labels = recent.map { item -> String in
            guard let date = ECJSON.date(from: item.endedAt) else {
                return "—"
            }
            return EcFormat.monthDayText(date)
        }
        let values = recent.map { $0.avgPron ?? 0 }
        return ChartsData.barValues(labels: labels, values: values)
    }

    var hasReport: Bool {
        !history.isEmpty || trend != nil
    }

    // MARK: - 结束结果（扁平化，页面不做深层可选链）

    var finishPron: Double? {
        finishResult?.avgPron
    }

    var finishAccuracy: Double? {
        finishResult?.avgAccuracy
    }

    var finishFluency: Double? {
        finishResult?.avgFluency
    }

    var finishIntonation: Double? {
        finishResult?.avgIntonationDistance
    }

    var finishNotice: String? {
        finishResult?.notice
    }

    var finishScoredCount: Int {
        finishResult?.scored ?? 0
    }

    var finishPendingCount: Int {
        finishResult?.pending ?? 0
    }

    var finishItemCount: Int {
        finishResult?.itemCount ?? questions.count
    }

    var finishSubmittedCount: Int {
        finishResult?.submitted ?? 0
    }

    // MARK: - 列表

    func loadOverview() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        loadError = nil
        do {
            overview = try await services.stats.blindTests()
            hasLoaded = true
        } catch {
            loadError = ErrorMapper.message(for: error, isChild: isChild)
            hasLoaded = true
        }
        isLoading = false
    }

    // MARK: - 开始

    func start() async {
        guard !isPreparing else {
            return
        }
        isPreparing = true
        startError = nil
        setupNotice = nil
        wrongSentences = []
        finishResult = nil
        finishError = nil
        do {
            let corpus = (try await services.practice.sentences(level: level)).sentences ?? []
            let start = try await services.stats.startBlindTest()
            blindTestId = start.blindTestId

            var ids = start.sentenceIds ?? []

            // 续做上一次未完成的批次：按已有的盲测 attempt 过滤掉做过的句子。
            if start.resumed == true, let attempts = try? await services.practice.attempts(limit: 100) {
                let done = Set(
                    attempts
                        .filter { $0.blindTestId == start.blindTestId }
                        .compactMap { $0.sentenceId }
                )
                ids = ids.filter { !done.contains($0) }
                if ids.isEmpty {
                    isPreparing = false
                    await finish()
                    return
                }
            }

            let resolved = await resolveSentences(ids: ids, corpus: corpus)
            guard !resolved.isEmpty else {
                throw APIError.server(
                    code: .noAttempts,
                    message: "还没有练习记录，先跟读几句再来做小测验吧。",
                    status: 0
                )
            }
            let built = buildQuestions(sentences: resolved, corpus: corpus)
            questions = built.questions
            if built.fellBackToRead {
                setupNotice = "听得懂的干扰项不足 4 个，本次改用盲跟读（不显示分数）。"
            } else {
                setupNotice = nil
            }
            index = 0
            isRevealed = false
            wrongSentences = []
            phase = .running
            resetQuestionState()
            await prepareCurrentAudio()
        } catch {
            startError = ErrorMapper.message(for: error, isChild: isChild)
            blindTestId = nil
        }
        isPreparing = false
    }

    private func resolveSentences(ids: [String], corpus: [SentenceDTO]) async -> [SentenceDTO] {
        var byID: [String: SentenceDTO] = [:]
        for sentence in corpus {
            byID[sentence.id] = sentence
        }
        var resolved: [SentenceDTO] = []
        for id in ids {
            if let cached = byID[id] {
                resolved.append(cached)
                continue
            }
            if let fetched = try? await services.practice.sentence(id: id) {
                resolved.append(fetched)
            }
        }
        return resolved
    }

    private func buildQuestions(
        sentences: [SentenceDTO],
        corpus: [SentenceDTO]
    ) -> (questions: [BlindQuestion], fellBackToRead: Bool) {
        let allTranslations = Array(
            Set(corpus.compactMap { $0.translationZh }.filter { !$0.isEmpty })
        )
        var result: [BlindQuestion] = []
        var fellBack = false

        for (offset, sentence) in sentences.enumerated() {
            let desired = desiredMode(at: offset)
            var mode = desired
            var options: [String] = []
            var correctIndex = 0

            if desired == .listen {
                let correctText = sentence.translationZh ?? ""
                let distractors = allTranslations
                    .filter { $0 != correctText }
                    .shuffled()
                    .prefix(3)
                if correctText.isEmpty || distractors.count < 3 {
                    mode = .read
                    fellBack = true
                } else {
                    var shuffled = Array(distractors) + [correctText]
                    shuffled.shuffle()
                    options = shuffled
                    correctIndex = shuffled.firstIndex(of: correctText) ?? 0
                }
            }

            result.append(
                BlindQuestion(
                    id: sentence.id,
                    sentence: sentence,
                    mode: mode,
                    options: options,
                    correctIndex: correctIndex
                )
            )
        }
        return (result, fellBack)
    }

    private func desiredMode(at offset: Int) -> BlindQuestionMode {
        switch modeOption {
        case .listen:
            return .listen
        case .read:
            return .read
        case .alternating:
            return offset.isMultiple(of: 2) ? .listen : .read
        }
    }

    // MARK: - 题目交互

    func play() async {
        guard let data = currentAudio else {
            return
        }
        do {
            try await audio.play(data: data, formatHint: "wav")
        } catch {
            audioErrorText = "播放失败，可以再点一次"
        }
    }

    func replay() async {
        guard canReplay else {
            return
        }
        replayCount += 1
        await play()
    }

    /// 音频加载失败后的重试（不改变当前题）。
    func retryAudio() async {
        await prepareCurrentAudio()
    }

    /// 盲听：选择中文释义后立即揭晓（答错用中性提示，不出现大红叉）。
    func selectOption(_ option: Int) {
        guard let question = currentQuestion,
              question.mode == .listen,
              canAnswerListen,
              question.options.indices.contains(option)
        else {
            return
        }
        selectedOption = option
        isRevealed = true
        if option != question.correctIndex, !wrongSentences.contains(where: { $0.id == question.id }) {
            wrongSentences.append(question.sentence)
        }
    }

    /// 盲跟读：开始录音（未授权时先请求权限）。
    func startRecording() async {
        guard !isScoring, !isRevealed else {
            return
        }
        do {
            if audio.permission != .granted {
                let granted = await audio.requestPermission()
                guard granted else {
                    recordError = ErrorMapper.message(for: AudioError.permissionDenied, isChild: isChild)
                    return
                }
            }
            recordError = nil
            try await audio.startRecording()
        } catch {
            recordError = ErrorMapper.message(for: error, isChild: isChild)
        }
    }

    /// 盲跟读：结束录音并提交（带 `blind_test_id`，服务端不返回分数）。
    func stopRecordingAndSubmit() async {
        guard audio.mode == .recording else {
            return
        }
        do {
            let recorded = try await audio.stopRecording()
            await submit(recorded)
        } catch {
            recordError = ErrorMapper.message(for: error, isChild: isChild)
        }
    }

    func cancelRecording() async {
        await audio.cancelRecording()
    }

    private func submit(_ recorded: RecordedAudio) async {
        guard let question = currentQuestion, let testID = blindTestId else {
            return
        }
        isScoring = true
        recordError = nil
        inlineNotice = nil
        do {
            let response = try await services.practice.evaluate(
                audioData: recorded.data,
                filename: recorded.filename,
                mimeType: recorded.mimeType,
                sentenceId: question.id,
                referenceText: question.sentence.text,
                mode: .unscripted,
                durationMs: recorded.durationMs,
                blindTestId: testID
            )
            if let usage = response.usage {
                session.apply(usage: usage)
            }
            if response.degraded == true {
                inlineNotice = "评分服务暂时不可用，本题已记为待评分，不会影响已评完的分数。"
            } else {
                inlineNotice = "已提交，这一轮不显示分数；结束后统一出报告。"
            }
            isRevealed = true
        } catch {
            recordError = ErrorMapper.message(for: error, isChild: isChild)
        }
        isScoring = false
    }

    func skipQuestion() async {
        let hadRecording = audio.mode == .recording
        if hadRecording {
            await audio.cancelRecording()
        }
        await advance()
    }

    func advance() async {
        guard index + 1 < questions.count else {
            await finish()
            return
        }
        index += 1
        resetQuestionState()
        await prepareCurrentAudio()
    }

    // MARK: - 结束 / 重新开始

    func finish() async {
        guard let testID = blindTestId, !isFinishing else {
            return
        }
        isFinishing = true
        finishError = nil
        do {
            let result = try await services.stats.finishBlindTest(id: testID)
            finishResult = result
            blindTestId = nil
            phase = .summary
            await loadOverview()
        } catch {
            finishError = ErrorMapper.message(for: error, isChild: isChild)
        }
        isFinishing = false
    }

    /// 结束「服务端已存在但本机没在跑」的批次（页面 setup 里的「结束并查看报告」）。
    func finishInProgress() async {
        guard blindTestId == nil, let testID = inProgress?.id else {
            return
        }
        blindTestId = testID
        await finish()
    }

    func restart() {
        prefetchTask?.cancel()
        prefetchTask = nil
        phase = .setup
        questions = []
        index = 0
        blindTestId = nil
        finishResult = nil
        finishError = nil
        startError = nil
        setupNotice = nil
        wrongSentences = []
        resetQuestionState()
    }

    /// 页面退出：停播放/录音、取消预取。
    func teardown() async {
        prefetchTask?.cancel()
        prefetchTask = nil
        await audio.stopAll()
    }

    // MARK: - 音频

    private func resetQuestionState() {
        currentAudio = nil
        isAudioLoading = false
        audioErrorText = nil
        replayCount = 0
        selectedOption = nil
        isRevealed = false
        isScoring = false
        inlineNotice = nil
        recordError = nil
    }

    private func prepareCurrentAudio() async {
        guard let question = currentQuestion else {
            return
        }
        isAudioLoading = true
        audioErrorText = nil
        do {
            let data = try await ttsData(for: question.sentence.text)
            currentAudio = data
            isAudioLoading = false
            prefetchNextAudio()
            await play()
        } catch {
            isAudioLoading = false
            if let apiError = error as? APIError, apiError.isCancelled {
                return
            }
            audioErrorText = "这道题听不了，可以跳过"
        }
    }

    private func prefetchNextAudio() {
        prefetchTask?.cancel()
        guard questions.indices.contains(index + 1) else {
            return
        }
        let nextText = questions[index + 1].sentence.text
        prefetchTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            _ = try? await self.ttsData(for: nextText)
        }
    }

    /// TTS 字节：先走 `AudioCache`（离线可复用），未命中再请求 `/tts`。
    private func ttsData(for text: String) async throws -> Data {
        let rate = session.prefs.rateOr(capabilities.prefersSlowDemo ? "slow" : "normal")
        let voiceRaw = session.prefs.voice()
        let voice: String? = voiceRaw.isEmpty ? nil : voiceRaw
        let key = AudioCache.ttsKey(
            text: text,
            rate: rate,
            voice: voice,
            format: TTSFormat.wav.rawValue
        )
        if let cached = await ttsCache.data(for: key) {
            return cached
        }
        let data = try await services.practice.synthesize(
            text: text,
            rate: TTSRate(rawValue: rate) ?? .normal,
            voice: voice,
            format: .wav
        )
        await ttsCache.store(data, for: key)
        return data
    }
}

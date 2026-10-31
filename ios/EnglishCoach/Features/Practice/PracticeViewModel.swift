import Foundation
import Observation

/// 练习页状态机：语料列表 + 当前句子 + 录音/评分 + 示范音。
///
/// 注意：录音与播放互斥由 `AudioRecorder` 在开始录音前 `playback.stop()` 保证；
/// 页面只调用 `AudioRecorder` / `AudioPlayer`，不直接碰 AVAudioRecorder。
@MainActor
@Observable
final class PracticeViewModel {
    enum ListState: Equatable {
        case idle
        case loading
        case loaded
        case failed(APIError)
    }

    enum RecordingPhase: Equatable {
        case idle
        case recording
        case scoring
    }

    let app: AppEnvironment
    private let player: AudioPlayer
    private let recorder: AudioRecorder

    var level: String
    private(set) var state: ListState = .idle
    private(set) var sentences: [Sentence] = []
    private(set) var currentIndex = 0

    private(set) var permission: MicPermission
    private(set) var recordingPhase: RecordingPhase = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var levelValue: Double = 0
    private(set) var audioError: AudioError?
    private(set) var submissionError: APIError?
    private(set) var attemptMessage: String?
    private(set) var lastRecording: RecordedAudio?
    private(set) var score: ScorePresentation?

    private(set) var isPreparingDemo = false
    private(set) var demoErrorMessage: String?
    private var demoCache: [String: URL] = [:]

    private var ticker: Task<Void, Never>?
    private var loadToken = 0
    private var isFinishing = false

    init(app: AppEnvironment) {
        self.app = app
        self.level = app.currentUser?.normalizedLevel ?? "A1"
        let player = AudioPlayer()
        let recorder = AudioRecorder(playback: player)
        self.player = player
        self.recorder = recorder
        self.permission = recorder.currentPermission()
    }

    var currentSentence: Sentence? {
        guard sentences.indices.contains(currentIndex) else { return nil }
        return sentences[currentIndex]
    }

    var isRecording: Bool { recordingPhase == .recording }
    var isScoring: Bool { recordingPhase == .scoring }
    var isPlayingAudio: Bool { player.isPlaying }
    var canGoNext: Bool { currentIndex + 1 < sentences.count }
    var defaultDemoRate: TTSRate { app.capabilities.prefersSlowDemo ? .slow : .normal }

    // MARK: - 语料

    func load() async {
        loadToken += 1
        let token = loadToken
        state = .loading

        do {
            let list = try await app.sentenceAPI().list(level: level)
            guard token == loadToken, !Task.isCancelled else { return }
            sentences = list
            currentIndex = min(currentIndex, max(list.count - 1, 0))
            state = .loaded
        } catch let error as APIError {
            guard token == loadToken else { return }
            if error.isCancelled { return }
            state = .failed(error)
            if error.isUnauthorized {
                await app.handleSessionExpired()
            }
        } catch is CancellationError {
            return
        } catch {
            guard token == loadToken else { return }
            state = .failed(.transport(.unknown))
        }
    }

    func select(index: Int) {
        guard sentences.indices.contains(index) else { return }
        if index != currentIndex {
            stopAllAudio()
            currentIndex = index
            resetAttempt()
            demoErrorMessage = nil
        }
        permission = recorder.currentPermission()
    }

    /// 返回 false 表示已经是最后一句，由 View 决定是否 pop。
    func advance() -> Bool {
        guard canGoNext else { return false }
        stopAllAudio()
        currentIndex += 1
        resetAttempt()
        demoErrorMessage = nil
        permission = recorder.currentPermission()
        return true
    }

    private func resetAttempt() {
        score = nil
        attemptMessage = nil
        submissionError = nil
        audioError = nil
        lastRecording = nil
        recordingPhase = .idle
        elapsed = 0
        levelValue = 0
    }

    // MARK: - 示范音

    func prepareDemo(rate: TTSRate? = nil) async {
        guard let sentence = currentSentence else { return }
        let rate = rate ?? defaultDemoRate
        let key = ttsKey(text: sentence.text, rate: rate)
        if demoCache[key] != nil {
            demoErrorMessage = nil
            return
        }

        isPreparingDemo = true
        demoErrorMessage = nil
        defer { isPreparingDemo = false }

        do {
            let data = try await app.ttsAPI().synthesize(text: sentence.text, rate: rate, format: .wav)
            try Task.checkCancellation()
            let url = try writeTTSFile(data: data, key: key)
            demoCache[key] = url
        } catch let error as APIError {
            if !error.isCancelled {
                demoErrorMessage = error.userMessage(forChild: app.capabilities.isChild)
            }
            if error.isUnauthorized {
                await app.handleSessionExpired()
            }
        } catch is CancellationError {
            return
        } catch {
            demoErrorMessage = "示范音暂时不可用，可以直接跟读"
        }
    }

    /// “播放示范”：点击后立即开始（若已预取则零等待）。
    func playDemo() async {
        guard !isRecording, !isScoring, let sentence = currentSentence else { return }
        let rate = defaultDemoRate
        guard let url = await ensureDemoURL(text: sentence.text, rate: rate) else { return }
        try? player.play(url: url)
    }

    /// “跟我读”：先播完示范音，再自动开始录音（播放失败也允许直接录）。
    func followAndRecord() async {
        guard !isRecording, !isScoring else { return }
        if let sentence = currentSentence,
           let url = await ensureDemoURL(text: sentence.text, rate: defaultDemoRate) {
            try? await player.playAndWait(url: url)
        }
        // 离开页面会取消等待；不要把“播完自动开录”延续到已离开的页面。
        guard !Task.isCancelled else { return }
        await beginRecording()
    }

    func stopPlayback() {
        player.stop()
    }

    private func ensureDemoURL(text: String, rate: TTSRate) async -> URL? {
        let key = ttsKey(text: text, rate: rate)
        if let cached = demoCache[key] {
            return cached
        }
        await prepareDemo(rate: rate)
        return demoCache[key]
    }

    private func ttsKey(text: String, rate: TTSRate) -> String {
        Hashing.sha256Hex("tts|\(text)|\(rate.rawValue)|wav")
    }

    private func writeTTSFile(data: Data, key: String) throws -> URL {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw AudioError.fileUnavailable
        }
        let directory = base.appendingPathComponent("TTS", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(key).wav")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 录音

    func refreshPermission() {
        permission = recorder.currentPermission()
    }

    func toggleRecording() async {
        if isRecording {
            await finishRecording()
        } else {
            await beginRecording()
        }
    }

    func beginRecording() async {
        guard recordingPhase != .scoring, !isRecording else { return }

        permission = recorder.currentPermission()
        if permission == .undetermined {
            permission = await recorder.requestPermission()
        }
        // 页面在系统权限弹窗期间被取消（返回/切后台）时不要再开录。
        guard !Task.isCancelled, permission == .granted else { return }

        do {
            try await recorder.start()
            recordingPhase = .recording
            elapsed = 0
            levelValue = 0
            audioError = nil
            submissionError = nil
            attemptMessage = nil
            score = nil
            lastRecording = nil
            startTicker()
        } catch let error as AudioError {
            audioError = error
            recordingPhase = .idle
            permission = recorder.currentPermission()
        } catch {
            audioError = .recorderFailed
            recordingPhase = .idle
        }
    }

    func finishRecording() async {
        guard recordingPhase == .recording, !isFinishing else { return }
        isFinishing = true
        ticker?.cancel()
        ticker = nil

        do {
            let audio = try recorder.stop()
            lastRecording = audio
            elapsed = audio.durationSeconds
            levelValue = 0
            recordingPhase = .scoring
            await submit(audio: audio)
        } catch let error as AudioError {
            audioError = error
            recordingPhase = .idle
            permission = recorder.currentPermission()
        } catch {
            audioError = .recorderFailed
            recordingPhase = .idle
        }
        isFinishing = false
    }

    /// 失败后重试：复用同一个文件，不要求用户重录（除非服务端明确说格式/超限）。
    func retrySubmission() async {
        guard let audio = lastRecording, recordingPhase == .idle else { return }
        recordingPhase = .scoring
        await submit(audio: audio)
    }

    func recordAgain() async {
        resetAttempt()
        await beginRecording()
    }

    func playMyRecording() {
        guard !isRecording, !isScoring, let recording = lastRecording else { return }
        try? player.play(url: recording.url)
    }

    private func submit(audio: RecordedAudio) async {
        guard let sentence = currentSentence else {
            recordingPhase = .idle
            return
        }
        submissionError = nil
        attemptMessage = nil
        score = nil
        let submittedSentenceID = sentence.id

        guard let data = try? Data(contentsOf: audio.url) else {
            audioError = .fileUnavailable
            recordingPhase = .idle
            return
        }

        do {
            let response = try await app.attemptAPI().submit(
                audioData: data,
                filename: audio.filename,
                mimeType: audio.mimeType,
                sentenceID: sentence.id,
                referenceText: sentence.text,
                mode: .scripted,
                durationMs: audio.durationMs
            )
            guard !Task.isCancelled else {
                recordingPhase = .idle
                return
            }
            // 用户可能在上传期间返回列表并选了别的句子：结果只能落到提交时的那一句。
            if currentSentence?.id == submittedSentenceID {
                apply(response)
            }
            recordingPhase = .idle
        } catch let error as APIError {
            if error.isCancelled {
                recordingPhase = .idle
                return
            }
            if currentSentence?.id == submittedSentenceID {
                submissionError = error
            }
            recordingPhase = .idle
            if error.isUnauthorized {
                await app.handleSessionExpired()
            }
        } catch {
            if currentSentence?.id == submittedSentenceID {
                submissionError = .transport(.unknown)
            }
            recordingPhase = .idle
        }
    }

    private func apply(_ response: AttemptResponse) {
        if response.degraded == true {
            attemptMessage = response.message ?? "评测服务暂时不可用，录音已经保存，可以稍后重试。"
        } else {
            attemptMessage = nil
        }

        if let result = response.result {
            score = ScorePresentation.make(
                result: result,
                feedback: response.feedback,
                capabilities: app.capabilities
            )
        } else {
            score = nil
            if attemptMessage == nil {
                attemptMessage = response.message ?? "这次没有拿到评分，请重试。"
            }
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.recordingPhase == .recording else { return }
                self.elapsed = self.recorder.elapsed
                self.levelValue = self.recorder.level

                if self.recorder.needsAutoStop {
                    // 60s 到点：recorder 已经停了，这里负责读文件并自动提交。
                    Task { await self.finishRecording() }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// 离开页面 / 进入后台：录音直接丢弃（不支持后台录音），播放停止。
    func stopAllAudio() {
        ticker?.cancel()
        ticker = nil
        recorder.cancelPendingStart()
        if recorder.isRecording {
            recorder.cancel()
        }
        player.stop()
        if recordingPhase == .recording {
            recordingPhase = .idle
        }
        levelValue = 0
        elapsed = 0
    }
}

// MARK: - 评分展示模型

/// 把服务端结果转换成“页面能直接渲染”的模型。
/// 孩子模式在**数据层**就没有数字分数与 IPA，UI 不可能误显示。
struct ScorePresentation: Equatable {
    enum Tier: Equatable {
        case celebrate
        case encourage
        case retry
    }

    struct Metric: Identifiable, Equatable {
        let id: String
        let title: String
        /// 0...1；nil 显示“—”
        let value: Double?
    }

    struct WordItem: Identifiable, Equatable {
        let id: String
        let word: String
        let score: Double?
        let isGood: Bool
    }

    let tier: Tier
    let numericScore: Int?
    let stars: Int
    let headline: String
    let encouragement: String
    let metrics: [Metric]
    let words: [WordItem]
    let issues: [String]
    let feedbackSummary: String?
    let feedbackPraise: String?
    let feedbackPoints: [String]
    let feedbackClosing: String?

    static func make(
        result: AttemptResult,
        feedback: AttemptFeedback?,
        capabilities: RoleCapabilities
    ) -> ScorePresentation {
        let scores = result.scores
        let pron = rawScore(scores?.pron)
        let accuracy = rawScore(scores?.accuracy)
        let fluency = rawScore(scores?.fluency)
        let completeness = rawScore(scores?.completeness)
        let average = [accuracy, fluency, completeness].compactMap { $0 }.average
        let overall = pron ?? average
        let tier = tier(for: overall)

        let metrics: [Metric] = capabilities.showsNumericScore
            ? [
                Metric(id: "accuracy", title: "准确度", value: normalized(accuracy)),
                Metric(id: "fluency", title: "流利度", value: normalized(fluency)),
                Metric(id: "completeness", title: "完整度", value: normalized(completeness)),
            ]
            : []

        let words = (result.words ?? []).enumerated().map { index, word in
            let wordScore = rawScore(word.score)
            let isGood = (wordScore ?? 0) >= 70
            return WordItem(
                id: "\(index)-\(word.word)",
                word: word.word,
                score: capabilities.showsNumericScore ? wordScore : nil,
                isGood: isGood
            )
        }

        let issues = capabilities.showsIPA
            ? (result.issues ?? []).compactMap { issueText($0) }
            : []

        let headline: String
        let encouragement: String
        switch (capabilities.isChild, tier) {
        case (true, .celebrate):
            headline = "说得真清楚！"
            encouragement = "你把这句读出来了，真棒 🌟"
        case (true, .encourage):
            headline = "有进步！"
            encouragement = "再来一次会更棒，慢慢读就好。"
        case (true, .retry):
            headline = "我听到你的努力了"
            encouragement = "这一句有点长，我们再来一次。"
        case (false, .celebrate):
            headline = "很不错"
            encouragement = "发音清晰，继续保持。"
        case (false, .encourage):
            headline = "还可以更清楚"
            encouragement = "注意标出的词，再读一遍会更稳。"
        case (false, .retry):
            headline = "这一句有点难"
            encouragement = "先听示范，再慢慢跟读一次。"
        }

        return ScorePresentation(
            tier: tier,
            numericScore: capabilities.showsNumericScore ? overall : nil,
            stars: stars(for: tier),
            headline: headline,
            encouragement: encouragement,
            metrics: metrics,
            words: words,
            issues: issues,
            feedbackSummary: feedback?.summary,
            feedbackPraise: feedback?.praise,
            feedbackPoints: capabilities.showsIPA
                ? (feedback?.points ?? []).compactMap { point in
                    guard let title = point.title, !title.isEmpty else { return nil }
                    if let why = point.why, !why.isEmpty {
                        return "\(title)：\(why)"
                    }
                    return title
                }
                : [],
            feedbackClosing: feedback?.closing
        )
    }

    private static func rawScore(_ value: Double?) -> Int? {
        guard let value else { return nil }
        let scaled = value <= 1 ? value * 100 : value
        return min(max(Int(scaled.rounded()), 0), 100)
    }

    private static func normalized(_ value: Int?) -> Double? {
        guard let value else { return nil }
        return min(max(Double(value) / 100, 0), 1)
    }

    private static func tier(for score: Int?) -> Tier {
        guard let score else { return .encourage }
        if score >= 85 { return .celebrate }
        if score >= 70 { return .encourage }
        return .retry
    }

    private static func stars(for tier: Tier) -> Int {
        switch tier {
        case .celebrate: return 3
        case .encourage: return 2
        case .retry: return 1
        }
    }

    private static func issueText(_ issue: PronounceIssue) -> String? {
        guard let type = issue.type, type != "None" else { return nil }
        let word = issue.word.map { "「\($0)」" } ?? "这里"
        let phoneme = issue.phoneme.map { "（\($0)）" } ?? ""
        switch type {
        case "Mispronunciation":
            return "\(word)\(phoneme) 的发音可以更清楚"
        case "Omission":
            return "\(word) 好像漏读了"
        case "Insertion":
            return "\(word) 附近多读了一个音"
        case "UnexpectedBreak":
            return "\(word) 这里的停顿有点久"
        case "MissingBreak":
            return "\(word) 这里可以连起来读"
        case "Monotone":
            return "语调可以更有起伏"
        default:
            return nil
        }
    }
}

private extension Array where Element == Int {
    var average: Int? {
        guard !isEmpty else { return nil }
        return Int((Double(reduce(0, +)) / Double(count)).rounded())
    }
}

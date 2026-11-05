import Foundation
import Observation

/// 故事复述状态：录音 → ASR（en-US）→ `story/retell`；也支持打字复述。
///
/// 复述只看「讲清楚没有」，不计发音分（screens.md §6.3）：
/// 成人显示覆盖率百分比，儿童只用星星 + 中文反馈。
@MainActor
@Observable
final class StoryReviewStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(UIMessage)
    }

    enum Mode: String, Hashable {
        case voice
        case typing
    }

    private(set) var phase: Phase = .loading
    private(set) var storyTitle = ""
    private(set) var level = "A2"
    private(set) var storySentences: [String] = []
    private(set) var storyPairs: [StoryTextPair] = []
    private(set) var mode: Mode = .voice
    var typedText = ""

    private(set) var isRecording = false
    private(set) var isPreparing = false
    private(set) var elapsedMs = 0
    private(set) var busyText = ""
    private(set) var hasResult = false
    private(set) var coverage: Double = -1
    private(set) var coveredPoints: [String] = []
    private(set) var missingPoints: [String] = []
    private(set) var feedbackZh = ""
    private(set) var feedbackEn = ""
    private(set) var transcript = ""
    private(set) var isSubmitting = false
    private(set) var inlineError = ""
    private(set) var uiError: UIMessage?
    private(set) var showsStoryText = false
    private(set) var recordedData: Data?
    private(set) var isPlayingRecording = false

    private let materialId: String
    private let services: AppServices
    private let audio: AudioCoordinator
    private let session: SessionStore
    private let runtime: StoryRuntime

    private var hasLoaded = false
    private var timerTask: Task<Void, Never>?
    private var playbackWatcher: Task<Void, Never>?

    init(
        materialId: String,
        sentences: [String],
        services: AppServices,
        audio: AudioCoordinator,
        session: SessionStore
    ) {
        let cleaned = sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.storySentences = cleaned
        self.materialId = materialId
        self.services = services
        self.audio = audio
        self.session = session
        self.runtime = StoryRuntime.shared
        self.storyPairs = cleaned.enumerated().map { index, sentence in
            StoryTextPair(index: index + 1, en: sentence)
        }
    }

    var isChild: Bool { session.isChild }

    var isBusy: Bool {
        isSubmitting || !busyText.isEmpty
    }

    var coverageStars: Int {
        guard coverage >= 0 else { return 1 }
        if coverage >= 0.85 { return 3 }
        if coverage >= 0.6 { return 2 }
        return 1
    }

    var coveredCountText: String {
        "说到了 \(coveredPoints.count) 个要点"
    }

    // MARK: - 加载

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        phase = .loading
        do {
            let detail = try await services.story.materialDetail(id: materialId)
            let rawTitle = (detail.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            storyTitle = rawTitle.isEmpty ? "这个故事" : rawTitle
            let upper = (detail.level ?? "").uppercased()
            level = upper.isEmpty ? "A2" : upper
            if storySentences.isEmpty {
                let pieces = StorySplit.sentences(from: detail.text ?? "")
                storySentences = pieces
            }
            storyPairs = storySentences.enumerated().map { index, sentence in
                StoryTextPair(index: index + 1, en: sentence)
            }
            phase = storySentences.isEmpty ? .failed(localMessage("这个故事还没有内容，先回详情看看吧")) : .ready
        } catch {
            if storySentences.isEmpty {
                phase = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
            } else {
                phase = .ready
            }
        }
    }

    // MARK: - 模式与文字

    func setMode(_ value: Mode) {
        guard mode != value else { return }
        mode = value
        clearMessages()
    }

    func toggleStoryText() {
        showsStoryText.toggle()
    }

    /// 「再复述一次」：清空上一次结果，保留故事与模式。
    func resetResult() {
        hasResult = false
        coverage = -1
        coveredPoints = []
        missingPoints = []
        feedbackZh = ""
        feedbackEn = ""
        transcript = ""
        typedText = ""
        inlineError = ""
        uiError = nil
    }

    func submitTyped() async {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            inlineError = "先写几句英文再提交吧"
            return
        }
        await submit(transcript: text)
    }

    // MARK: - 录音 → ASR → retell

    func startRecording() async {
        guard !isRecording, !isPreparing, !isBusy else { return }
        clearMessages()
        isPreparing = true
        defer { isPreparing = false }
        do {
            if audio.permission != .granted {
                let granted = await audio.requestPermission()
                guard granted else {
                    present(error: AudioError.permissionDenied)
                    return
                }
            }
            try await audio.startRecording()
            isRecording = true
            elapsedMs = 0
            startTimer()
        } catch {
            present(error: error)
        }
    }

    func stopRecordingAndSubmit() async {
        guard isRecording else { return }
        isRecording = false
        stopTimer()
        let recorded: RecordedAudio
        do {
            recorded = try await audio.stopRecording()
        } catch {
            present(error: error)
            return
        }
        recordedData = recorded.data
        await recognize(data: recorded.data)
    }

    func cancelRecording() async {
        isRecording = false
        stopTimer()
        elapsedMs = 0
        await audio.cancelRecording()
    }

    func retryRecognize() async {
        guard let recordedData else { return }
        await recognize(data: recordedData)
    }

    func retryRetell() async {
        guard !transcript.isEmpty else { return }
        await submit(transcript: transcript)
    }

    private func recognize(data: Data) async {
        clearMessages()
        busyText = "正在听懂你的复述…"
        defer { busyText = "" }
        do {
            let text = try await services.story.asr(audioData: data, language: "en-US")
            let recognized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recognized.isEmpty else {
                inlineError = "这次没听清，再讲一次吧 🙂"
                return
            }
            await submit(transcript: recognized)
        } catch {
            present(error: error)
        }
    }

    private func submit(transcript text: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        busyText = "正在看你说清楚了没有…"
        defer {
            isSubmitting = false
            busyText = ""
        }
        do {
            let result = try await services.story.retell(
                materialId: materialId,
                storySentences: storySentences,
                transcript: text,
                level: level
            )
            transcript = text
            coveredPoints = result.coveredPoints ?? []
            missingPoints = result.missingPoints ?? []
            feedbackZh = result.feedbackZh ?? ""
            feedbackEn = result.feedbackEn ?? ""
            coverage = result.coverage ?? -1
            hasResult = true
            inlineError = ""
            runtime.addRetell(
                materialId: materialId,
                record: StoryRetellRecordDTO(
                    createdAt: Self.timestamp(),
                    coverage: result.coverage,
                    coveredCount: coveredPoints.count,
                    coveredPoints: coveredPoints,
                    missingPoints: missingPoints,
                    feedbackZh: feedbackZh,
                    feedbackEn: feedbackEn,
                    transcript: text
                )
            )
        } catch {
            present(error: error)
        }
    }

    // MARK: - 回放我的复述

    func playRecording() async {
        guard let data = recordedData else { return }
        if isPlayingRecording {
            await audio.stopPlayback()
            isPlayingRecording = false
            return
        }
        do {
            try await audio.play(data: data, formatHint: "m4a")
            isPlayingRecording = true
            playbackWatcher?.cancel()
            playbackWatcher = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled, self.audio.isPlaying {
                    try? await Task.sleep(for: .milliseconds(300))
                }
                guard !Task.isCancelled else { return }
                self.isPlayingRecording = false
            }
        } catch {
            present(error: error)
        }
    }

    // MARK: - 清理

    func clearMessages() {
        inlineError = ""
        uiError = nil
    }

    func stopAll() async {
        isRecording = false
        stopTimer()
        playbackWatcher?.cancel()
        playbackWatcher = nil
        await audio.stopAll()
        isPlayingRecording = false
    }

    // MARK: - 私有

    private func startTimer() {
        stopTimer()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.isRecording else { return }
                self.elapsedMs = min(self.elapsedMs + 200, 60_000)
                if self.elapsedMs >= 60_000 {
                    await self.stopRecordingAndSubmit()
                    return
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func present(error: Error) {
        if let apiError = error as? APIError, apiError.isCancelled { return }
        let message = ErrorMapper.message(for: error, isChild: session.isChild)
        if message.isSilent { return }
        uiError = message
    }

    private func localMessage(_ text: String) -> UIMessage {
        UIMessage(
            title: text,
            body: nil,
            actionTitle: nil,
            action: UIMessage.Action.none,
            isRetryable: false,
            diagnosticID: nil
        )
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

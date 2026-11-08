import Foundation
import Observation

/// 故事详情状态：逐句朗读、整段朗读（audio/status 轮询）、插画、原声回放、复述记录、改名/删除。
///
/// 契约 §3.6 已确认：`storyAudio` 遇 202 会抛 `providerUnavailable`，
/// 所以整段朗读必须**先轮询 `audioStatus` 到 `ready` 再下载**；
/// `no_audio` 表示这个故事没录过朗读 → 页面隐藏整段播放。
@MainActor
@Observable
final class StoryDetailStore {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(UIMessage)
    }

    /// 整段朗读四态（ready / building / failed / no_audio）。
    enum AudioPhase: Equatable {
        case unknown
        case noAudio
        case building
        case ready
        case failed(String)
    }

    // MARK: 展示状态

    private(set) var phase: Phase = .loading
    private(set) var title = ""
    private(set) var level = ""
    private(set) var authorName = ""
    private(set) var dateText = ""
    /// 打印用的绝对日期（`yyyy/M/d`）；`dateText` 是“3 分钟前”这类相对文案。
    private(set) var createdAtText = ""
    private(set) var sourceZh = ""
    private(set) var showsSourceZh = false
    private(set) var sentences: [StorySentenceItem] = []

    private(set) var imageData: Data?
    private(set) var imageLoading = false
    private(set) var imageVersion = 0
    private(set) var hasImage = false
    private(set) var imagePrompt = ""
    private(set) var showsImagePrompt = false
    private(set) var isIllustrating = false
    private(set) var imageCapable = true

    private(set) var audioPhase: AudioPhase = .unknown
    private(set) var audioDurationText = ""
    private(set) var isAudioLoading = false
    private(set) var isAudioPlaying = false

    private(set) var playingSentenceId: Int?
    private(set) var isTTSLoading = false

    private(set) var originalRecordingData: Data?
    private(set) var isOriginalPlaying = false

    private(set) var retellRecords: [StoryRetellRecordDTO] = []

    private(set) var busyText = ""
    private(set) var uiError: UIMessage?
    private(set) var notice = ""
    private(set) var isRenaming = false
    private(set) var isDeleting = false

    // MARK: 依赖

    private let materialId: String
    private let services: AppServices
    private let audio: AudioCoordinator
    private let session: SessionStore
    private let runtime: StoryRuntime
    private let audioCache = AudioCache()
    private let recordingCache = RecordingCache()

    private var hasLoaded = false
    private var audioPoller: Task<Void, Never>?
    private var storyAudioData: Data?
    private var playbackWatcher: Task<Void, Never>?

    init(
        materialId: String,
        services: AppServices,
        audio: AudioCoordinator,
        session: SessionStore
    ) {
        self.materialId = materialId
        self.services = services
        self.audio = audio
        self.session = session
        self.runtime = StoryRuntime.shared
    }

    var isChild: Bool { session.isChild }

    var fullText: String {
        sentences.map(\.en).joined(separator: "\n")
    }

    var hasSourceZh: Bool {
        !sourceZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 加载

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        let capabilities = await StoryCapabilities.load(services: services)
        imageCapable = capabilities.image
        await load()
    }

    func load() async {
        phase = .loading
        do {
            let detail = try await services.story.materialDetail(id: materialId)
            apply(detail: detail)
            phase = .ready
            await loadImage()
            await refreshAudioStatus()
            await loadOriginalRecording()
            await loadRetellRecords()
        } catch {
            phase = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
        }
    }

    private func apply(detail: StoryMaterialDTO) {
        let rawTitle = (detail.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        title = rawTitle.isEmpty ? "未命名故事" : rawTitle
        level = (detail.level ?? "").uppercased()
        authorName = detail.createdByName ?? ""
        dateText = ECJSON.relativeText(from: detail.createdAt)
        createdAtText = Self.printDate(detail.createdAt)
        sourceZh = (detail.sourceZh ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        showsSourceZh = false
        imagePrompt = (detail.imagePrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        showsImagePrompt = false
        hasImage = detail.hasImage == true || !(detail.imageUrl ?? "").isEmpty
        imageVersion = StoryDates.versionToken(from: detail.updatedAt ?? detail.createdAt)

        let text = detail.text ?? ""
        let pieces = StorySplit.sentences(from: text)
        sentences = pieces.enumerated().map { index, sentence in
            StorySentenceItem(index: index + 1, en: sentence)
        }
        if !hasImage {
            imageData = nil
        }
    }

    private static func printDate(_ raw: String?) -> String {
        guard let date = ECJSON.date(from: raw) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: date)
    }

    // MARK: - 插画

    private func loadImage() async {
        guard hasImage || imageVersion > 0 else {
            imageData = nil
            return
        }
        imageLoading = true
        defer { imageLoading = false }
        imageData = await StoryImageLoader.load(
            materialId: materialId,
            version: imageVersion,
            services: services
        )
    }

    func illustrate(force: Bool) async {
        guard imageCapable, !isIllustrating else { return }
        isIllustrating = true
        busyText = isChild ? "正在画插画…" : "正在生成插画…"
        uiError = nil
        notice = ""
        defer {
            isIllustrating = false
            busyText = ""
        }
        do {
            _ = try await services.story.illustrate(id: materialId, force: force)
            // 重新拉详情拿到新的 updatedAt（作为图片缓存版本）与提示词。
            if let refreshed = try? await services.story.materialDetail(id: materialId) {
                apply(detail: refreshed)
            }
            imageData = await StoryImageLoader.reload(
                materialId: materialId,
                version: imageVersion,
                services: services
            )
            notice = isChild ? "插画画好啦，快看看 ⭐" : "插画已更新"
        } catch {
            present(error: error)
        }
    }

    // MARK: - 逐句朗读（TTS 先落盘/缓存再播）

    func speak(sentence: StorySentenceItem) async {
        if playingSentenceId == sentence.id {
            await audio.stopPlayback()
            playingSentenceId = nil
            return
        }
        guard !isTTSLoading else { return }
        let text = sentence.en.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isTTSLoading = true
        defer { isTTSLoading = false }
        let rate = resolvedTTSRate()
        let voice = resolvedVoice()
        let format = TTSFormat.mp3
        let key = AudioCache.ttsKey(text: text, rate: rate.rawValue, voice: voice, format: format.rawValue)

        do {
            let data: Data
            if let cached = await audioCache.data(for: key) {
                data = cached
            } else {
                data = try await services.practice.synthesize(text: text, rate: rate, voice: voice, format: format)
                await audioCache.store(data, for: key)
            }
            try await audio.play(data: data, formatHint: "mp3")
            playingSentenceId = sentence.id
            watchPlayback { [weak self] in
                self?.playingSentenceId = nil
            }
        } catch {
            present(error: error)
        }
    }

    // MARK: - 整段朗读

    func refreshAudioStatus() async {
        do {
            let status = try await services.story.audioStatus(id: materialId)
            apply(audioStatus: status)
        } catch {
            if let apiError = error as? APIError, apiError.isCancelled { return }
            audioPhase = .failed(ErrorMapper.message(for: error, isChild: session.isChild).body ?? "朗读暂时不可用")
        }
    }

    private func apply(audioStatus status: StoryAudioStatusDTO) {
        if let duration = status.durationMs, duration > 0 {
            audioDurationText = EcFormat.clock(milliseconds: duration)
        } else {
            audioDurationText = ""
        }
        let raw = (status.status ?? "").lowercased()
        switch raw {
        case "ready":
            audioPhase = .ready
        case "failed":
            audioPhase = .failed((status.error ?? "").isEmpty ? "生成失败" : (status.error ?? ""))
        case "no_audio":
            audioPhase = .noAudio
        default:
            audioPhase = .building
            startAudioPolling()
        }
    }

    private func startAudioPolling() {
        audioPoller?.cancel()
        audioPoller = Task { @MainActor [weak self] in
            for _ in 0..<15 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                guard let status = try? await self.services.story.audioStatus(id: self.materialId) else { continue }
                let raw = (status.status ?? "").lowercased()
                if raw == "ready" {
                    self.apply(audioStatus: status)
                    return
                }
                if raw == "failed" || raw == "no_audio" {
                    self.apply(audioStatus: status)
                    return
                }
            }
            guard let self else { return }
            if self.audioPhase == .building {
                self.audioPhase = .failed("生成超时，稍后再试")
            }
        }
    }

    func playWholeStory() async {
        if isAudioPlaying {
            await audio.stopPlayback()
            isAudioPlaying = false
            return
        }
        guard audioPhase == .ready else { return }
        if let cached = storyAudioData {
            await playStoryAudio(data: cached)
            return
        }
        isAudioLoading = true
        defer { isAudioLoading = false }
        do {
            let data = try await services.story.storyAudio(id: materialId, force: false)
            storyAudioData = data
            await playStoryAudio(data: data)
        } catch let error as APIError {
            // 202：服务端还在构建，继续轮询（契约 §3.6 的既定路径）。
            if case .server(let code, _, let status) = error, code == .providerUnavailable, status == 202 {
                audioPhase = .building
                notice = "整段朗读还在准备，稍等一下就好了"
                startAudioPolling()
                return
            }
            present(error: error)
        } catch {
            present(error: error)
        }
    }

    func retryWholeStory() async {
        audioPhase = .building
        isAudioLoading = true
        defer { isAudioLoading = false }
        do {
            let data = try await services.story.storyAudio(id: materialId, force: true)
            storyAudioData = data
            audioPhase = .ready
            await playStoryAudio(data: data)
        } catch {
            present(error: error)
            await refreshAudioStatus()
        }
    }

    private func playStoryAudio(data: Data) async {
        do {
            try await audio.play(data: data, formatHint: "mp3")
            isAudioPlaying = true
            watchPlayback { [weak self] in
                self?.isAudioPlaying = false
            }
        } catch {
            present(error: error)
        }
    }

    // MARK: - 原声（本机 RecordingCache 副本）

    private func loadOriginalRecording() async {
        originalRecordingData = await recordingCache.data(for: materialId)
    }

    func playOriginal() async {
        guard let data = originalRecordingData else { return }
        if isOriginalPlaying {
            await audio.stopPlayback()
            isOriginalPlaying = false
            return
        }
        do {
            try await audio.play(data: data, formatHint: "m4a")
            isOriginalPlaying = true
            watchPlayback { [weak self] in
                self?.isOriginalPlaying = false
            }
        } catch {
            present(error: error)
        }
    }

    // MARK: - 复述记录（服务端可能 404，失败不阻塞）

    private func loadRetellRecords() async {
        let remote = (try? await services.story.retellRecords(materialId: materialId)) ?? []
        let local = runtime.retells(for: materialId)
        retellRecords = remote.isEmpty ? local : remote
    }

    func refreshRetellRecords() async {
        await loadRetellRecords()
    }

    // MARK: - 改名 / 删除

    func rename(to newTitle: String) async -> Bool {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRenaming else { return false }
        isRenaming = true
        defer { isRenaming = false }
        do {
            try await services.story.renameMaterial(id: materialId, title: trimmed)
            title = trimmed
            notice = "已改名"
            return true
        } catch {
            present(error: error)
            return false
        }
    }

    func delete() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await services.story.deleteMaterial(id: materialId)
            return true
        } catch {
            present(error: error)
            return false
        }
    }

    // MARK: - 交互状态

    func toggleSourceZh() {
        showsSourceZh.toggle()
    }

    func toggleImagePrompt() {
        showsImagePrompt.toggle()
    }

    func clearMessages() {
        uiError = nil
        notice = ""
    }

    func flashNotice(_ text: String) {
        notice = text
    }

    func stopAllAudio() async {
        audioPoller?.cancel()
        audioPoller = nil
        playbackWatcher?.cancel()
        playbackWatcher = nil
        await audio.stopAll()
        isAudioPlaying = false
        isOriginalPlaying = false
        playingSentenceId = nil
    }

    // MARK: - 私有

    private func resolvedVoice() -> String? {
        let voice = session.prefs.voice().trimmingCharacters(in: .whitespaces)
        return voice.isEmpty ? nil : voice
    }

    private func resolvedTTSRate() -> TTSRate {
        let fallback = session.capabilities.prefersSlowDemo ? "slow" : "normal"
        let raw = session.prefs.rateOr(fallback)
        return TTSRate(rawValue: raw) ?? .normal
    }

    /// 播放结束后清除「正在播放」标记（AudioCoordinator 没有完成回调，用小轮询）。
    private func watchPlayback(onFinish: @escaping @MainActor () -> Void) {
        playbackWatcher?.cancel()
        playbackWatcher = Task { @MainActor in
            while !Task.isCancelled, audio.isPlaying {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }

    private func present(error: Error) {
        if let apiError = error as? APIError, apiError.isCancelled { return }
        let message = ErrorMapper.message(for: error, isChild: session.isChild)
        if message.isSilent { return }
        uiError = message
    }
}

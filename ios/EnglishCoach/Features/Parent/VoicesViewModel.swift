import Foundation
import Observation

/// 音色页状态（`VoicesView(services:audio:)`）。
///
/// 9 个内置音色来自 `MediaService.voicesConst`（服务端 `/tts/voices` 线上 404）；
/// 试听 = `POST /tts` 合成一小段 → `AudioCoordinator` 播放；保存 = `PATCH /settings.tts_voice`
///（空串表示恢复默认音色，按契约用 `SettingsPatchDTO.clear(.ttsVoice)` 发 `null`）。
@MainActor
@Observable
final class VoicesViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(UIMessage)
    }

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore
    let isChild: Bool

    let voices = MediaService.voicesConst

    private(set) var currentVoice = ""
    private(set) var rate = "normal"
    private(set) var loadState: LoadState = .idle
    private(set) var didLoad = false
    private(set) var isSaving = false
    private(set) var saveError: UIMessage?
    private(set) var notice: String?
    private(set) var previewingId = ""
    private(set) var isSynthesizing = false
    private(set) var previewError: UIMessage?

    private var previewPollTask: Task<Void, Never>?

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
        self.isChild = session.isChild
        self.rate = session.isChild ? "slow" : "normal"
    }

    var englishVoices: [VoiceOption] {
        voices.filter { $0.lang == "en" }
    }

    var chineseVoices: [VoiceOption] {
        voices.filter { $0.lang == "zh" }
    }

    func voiceLabel(_ id: String) -> String {
        if id.isEmpty {
            return "默认音色（provider 决定）"
        }
        return MediaService.findVoice(id)?.labelZh ?? id
    }

    // MARK: - 加载

    func load(force: Bool = false) async {
        if didLoad && !force { return }
        if case .loading = loadState { return }
        loadState = .loading
        saveError = nil
        do {
            let settings = try await services.account.settings()
            if let prefs = settings.prefs {
                currentVoice = prefs.ttsVoice ?? ""
                if let serverRate = prefs.ttsRate, !serverRate.isEmpty {
                    rate = serverRate
                }
            }
            didLoad = true
            loadState = .loaded
        } catch let error as APIError {
            loadState = .failed(ErrorMapper.message(for: error, isChild: isChild))
        } catch {
            loadState = .failed(ErrorMapper.message(for: error, isChild: isChild))
        }
    }

    // MARK: - 试听

    func togglePreview(_ voice: VoiceOption) async {
        if previewingId == voice.id {
            await stopPreview()
            return
        }
        await stopPreview()
        previewError = nil
        notice = nil
        let text = voice.sample ?? "Hello! Let's practice English together."
        let ttsRate = TTSRate(rawValue: rate) ?? .normal
        isSynthesizing = true
        previewingId = voice.id
        defer { isSynthesizing = false }
        do {
            let data = try await services.practice.synthesize(
                text: text,
                rate: ttsRate,
                voice: voice.id,
                format: .mp3
            )
            try await audio.play(data: data, formatHint: "mp3")
            startPolling(voiceId: voice.id)
        } catch let error as APIError {
            previewingId = ""
            previewError = ErrorMapper.message(for: error, isChild: isChild)
        } catch let error as AudioError {
            previewingId = ""
            previewError = ErrorMapper.message(for: error, isChild: isChild)
        } catch {
            previewingId = ""
            previewError = ErrorMapper.message(for: error, isChild: isChild)
        }
    }

    func stopPreview() async {
        previewPollTask?.cancel()
        previewPollTask = nil
        previewingId = ""
        await audio.stopPlayback()
    }

    private func startPolling(voiceId: String) {
        previewPollTask?.cancel()
        previewPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.audio.isPlaying {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            if self.previewingId == voiceId {
                self.previewingId = ""
            }
        }
    }

    // MARK: - 保存

    func save(_ voiceId: String) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        saveError = nil
        notice = nil
        defer { isSaving = false }
        do {
            var body = SettingsPatchDTO(
                displayName: nil,
                dailyLimitMinutes: nil,
                allowFreeChat: nil,
                autoIllustrate: nil,
                gender: nil,
                storySentences: nil,
                correctionLevel: nil,
                ttsRate: nil,
                ttsVoice: nil,
                showWordIpa: nil
            )
            if voiceId.isEmpty {
                body.clear(.ttsVoice)
            } else {
                body.ttsVoice = voiceId
            }
            _ = try await services.account.patchSettings(body)
            currentVoice = voiceId
            let previous = session.prefs.snapshot
            session.prefs.apply(
                AccountPrefsSnapshot(
                    ttsVoice: voiceId,
                    ttsRate: previous.ttsRate,
                    showWordIpa: previous.showWordIpa,
                    storySentences: previous.storySentences,
                    autoIllustrate: previous.autoIllustrate
                )
            )
            notice = "已保存音色偏好"
            return true
        } catch let error as APIError {
            saveError = ErrorMapper.message(for: error, isChild: isChild)
            return false
        } catch {
            saveError = ErrorMapper.message(for: error, isChild: isChild)
            return false
        }
    }
}

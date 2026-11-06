import Foundation
import Observation
import OSLog

private let coordinatorLogger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "audio")

/// 音频错误（契约 §3.10）。用户可见文案统一由 `ErrorMapper` 生成，这里只表达原因。
enum AudioError: Error, Equatable, Sendable {
    case permissionDenied
    case tooShort
    case silent
    case tooLong
    case tooLarge
    case engine(String)
}

/// 音频总门面：页面**只**通过它录音/播放，不直接创建 `AVAudioRecorder` / `AVAudioPlayer`。
///
/// 核心不变量（audio.md §7）：`mode` 任意时刻只能是 `idle / recording / playing` 之一。
/// - 开始录音：先停播放 → 等真正停止 → 切 `.playAndRecord` → 开录；
/// - 录音中收到播放请求：抛 `AudioError`，不偷偷停录音（用户明确点了“开始说”）；
/// - 中断（来电/闹钟）与拔耳机：停止并把原因记在 `interruptionReason`，由页面决定提示。
@MainActor
@Observable
final class AudioCoordinator {
    enum Mode: Sendable, Equatable {
        case idle
        case recording
        case playing
    }

    private(set) var mode: Mode = .idle
    /// 录音电平 0...1（20Hz 更新，供波形条）。
    private(set) var level: Double = 0
    private(set) var permission: MicPermission
    /// 最近一次系统中断/路由变化的诊断原因（nil = 没有发生过）。
    /// 系统回收音频焦点时本门面会主动停止录音/播放，页面据此切换引导文案。
    private(set) var interruptionReason: String?

    @ObservationIgnored private let sessionController: AudioSessionController
    @ObservationIgnored private let recorder: VoiceRecorder
    @ObservationIgnored private let player: AudioPlayer
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    init(
        sessionController: AudioSessionController? = nil,
        recorder: VoiceRecorder? = nil,
        player: AudioPlayer? = nil
    ) {
        let resolvedSession = sessionController ?? AudioSessionController()
        let resolvedRecorder = recorder ?? VoiceRecorder()
        let resolvedPlayer = player ?? AudioPlayer()
        self.sessionController = resolvedSession
        self.recorder = resolvedRecorder
        self.player = resolvedPlayer
        self.permission = MicPermission.current()
        resolvedRecorder.onLevel = { [weak self] level in
            self?.level = level
        }
        let events = resolvedSession.events
        self.eventTask = Task { @MainActor [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    /// 只读派生状态，供 UI 直接绑定。
    var isRecording: Bool { mode == .recording }
    var isPlaying: Bool { mode == .playing }

    // MARK: - 准备与权限

    /// 提前把 `AVAudioSession` 配置到可用状态（**不**激活，避免冷启动打断其他 App 的声音）。
    func prepare() async {
        permission = MicPermission.current()
        CacheLocator.ensureAll()
        await sessionController.prepare()
    }

    /// 首次点“开始录音”时调用（audio.md §2.2：不在启动时请求）。
    func requestPermission() async -> Bool {
        let result = await MicPermission.request()
        permission = result
        return result == .granted
    }

    func openSettings() {
        MicPermission.openSettings()
    }

    // MARK: - 录音

    func startRecording() async throws {
        guard mode != .recording else { return }

        let currentPermission = MicPermission.current()
        permission = currentPermission
        guard currentPermission == .granted else {
            throw AudioError.permissionDenied
        }

        // 互斥：先停下正在播的音频（蓝牙 A2DP → HFP 需要时间，Session 激活再等系统切完）。
        await stopPlayback()
        interruptionReason = nil

        do {
            try await sessionController.activate(.recording)
            try recorder.start()
        } catch {
            await sessionController.deactivate()
            throw error
        }

        level = 0
        mode = .recording
    }

    func stopRecording() async throws -> RecordedAudio {
        guard mode == .recording else {
            throw AudioError.engine("not_recording")
        }
        let audio: RecordedAudio
        do {
            audio = try await recorder.stop()
        } catch {
            mode = .idle
            level = 0
            await sessionController.deactivate()
            throw error
        }
        mode = .idle
        level = 0
        await sessionController.deactivate()

        // 全静音在本层拦截（audio.md §4.3：提示“没有听到声音”，允许重录）。
        guard !audio.isSilent else {
            throw AudioError.silent
        }
        return audio
    }

    func cancelRecording() async {
        recorder.cancel()
        level = 0
        guard mode == .recording else { return }
        mode = .idle
        await sessionController.deactivate()
    }

    // MARK: - 播放

    func play(data: Data, formatHint: String?) async throws {
        guard mode != .recording else {
            throw AudioError.engine("playback_blocked_while_recording")
        }
        await stopPlayback()
        try await sessionController.activate(.playback)

        mode = .playing
        do {
            try player.play(data: data, formatHint: formatHint) { [weak self] in
                self?.handlePlaybackCompleted()
            }
        } catch {
            mode = .idle
            await sessionController.deactivate()
            throw error
        }
    }

    func play(fileURL: URL) async throws {
        guard mode != .recording else {
            throw AudioError.engine("playback_blocked_while_recording")
        }
        await stopPlayback()
        try await sessionController.activate(.playback)

        mode = .playing
        do {
            try player.play(fileURL: fileURL) { [weak self] in
                self?.handlePlaybackCompleted()
            }
        } catch {
            mode = .idle
            await sessionController.deactivate()
            throw error
        }
    }

    func stopPlayback() async {
        player.stop()
        guard mode == .playing else { return }
        mode = .idle
        level = 0
        await sessionController.deactivate()
    }

    /// 页面切走 / 切后台：停止播放并丢弃当前录音（audio.md §3.2、§7）。
    func stopAll() async {
        recorder.cancel()
        player.stop()
        mode = .idle
        level = 0
        await sessionController.deactivate()
    }

    // MARK: - 系统事件

    private func handlePlaybackCompleted() {
        guard mode == .playing else { return }
        mode = .idle
        level = 0
        Task { @MainActor [weak self] in
            guard let self, self.mode == .idle else { return }
            await self.sessionController.deactivate()
        }
    }

    private func handle(_ event: AudioEvent) async {
        switch event {
        case .interruptionBegan:
            // 来电/闹钟：录音中止（不保存半句）、播放停止（不自动续播）。
            coordinatorLogger.debug("audio interruption began")
            interruptionReason = "interruption"
            await haltForSystemEvent()
        case .interruptionEnded:
            interruptionReason = "interruption_ended"
        case .routeChanged(let change):
            interruptionReason = Self.reasonText(for: change)
            guard change == .oldDeviceUnavailable, mode == .playing else { return }
            // 拔耳机：立即暂停，不自动外放（audio.md §6.5）；录音继续（输入会回退到手机麦克风）。
            player.stop()
            mode = .idle
            await sessionController.deactivate()
        case .mediaServicesWereReset:
            coordinatorLogger.debug("audio media services reset")
            interruptionReason = "media_services_reset"
            await haltForSystemEvent()
        }
    }

    /// 系统级事件：中止录音、停止播放并归还音频焦点。
    private func haltForSystemEvent() async {
        if mode == .recording {
            recorder.cancel()
        }
        player.stop()
        mode = .idle
        level = 0
        await sessionController.deactivate()
    }

    private static func reasonText(for change: AudioRouteChange) -> String {
        switch change {
        case .oldDeviceUnavailable:
            return "route_old_device_unavailable"
        case .newDeviceAvailable:
            return "route_new_device_available"
        case .other:
            return "route_changed"
        }
    }
}

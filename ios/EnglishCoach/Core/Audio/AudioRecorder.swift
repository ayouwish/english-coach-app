import AVFAudio
import AVFoundation
import AudioToolbox
import Foundation

enum MicPermission: Sendable, Equatable {
    case undetermined
    case granted
    case denied
}

struct RecordedAudio: Sendable, Equatable {
    let url: URL
    let durationMs: Int
    let byteCount: Int
    let filename: String
    let mimeType: String

    var durationSeconds: Double {
        Double(durationMs) / 1000
    }
}

/// 录音门面：16kHz / 单声道 / AAC-LC 65kbps 的 m4a。
///
/// 关键约束：
/// - 一次“开始→停止” = 一个文件 = 一次上传，绝不切片（服务端连续识别，切碎会丢句）；
/// - 开始录音前先停播放：录音要用 `.playAndRecord + .allowBluetooth`，
///   蓝牙会从 A2DP 降为 HFP（窄带），如果这时还有声音在放，既会录进 TTS 自己，也会让音质变闷；
/// - 不用 delegate（Swift 6 下 @objc 协议 + MainActor 隔离容易踩坑），用 Task 轮询电平。
@MainActor
final class AudioRecorder {
    static let maxDuration: TimeInterval = 60
    static let minDuration: TimeInterval = 0.5
    static let maxBytes = 12 * 1024 * 1024
    static let mimeType = "audio/mp4"
    /// -45dB 以下视为整段静音（只用于拦截“没听到声音”，不做切句）。
    static let silenceThreshold: Float = -45

    private let playback: AudioPlayer
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var startedAt: Date?
    private var meteringTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    /// 用于让“还在等路由切换的 start()”作废（页面已离开时不要真的开录）。
    private var activationToken = 0

    private(set) var isRecording = false
    private(set) var level: Double = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var limitReached = false
    private var peakPower: Float = -160

    init(playback: AudioPlayer) {
        self.playback = playback
    }

    var needsAutoStop: Bool {
        limitReached
    }

    func currentPermission() -> MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .denied
        }
    }

    func requestPermission() async -> MicPermission {
        let status = currentPermission()
        guard status == .undetermined else { return status }

        // iOS 17+ 提供 async 版本（class func），最低 iOS 26，无需 continuation 包装。
        let granted = await AVAudioApplication.requestRecordPermission()
        return granted ? .granted : currentPermission()
    }

    func start() async throws {
        guard !isRecording else { return }
        guard currentPermission() == .granted else {
            throw AudioError.permissionDenied
        }

        activationToken += 1
        let token = activationToken

        // 先停播放，并留一小段时间给音频路由切换（蓝牙 A2DP → HFP 不是瞬时的）。
        playback.stop()
        try? await Task.sleep(for: .milliseconds(80))
        // 等待路由切换期间页面可能已经消失/取消；此时不要再把录音打开。
        guard !Task.isCancelled, token == activationToken else {
            throw AudioError.interrupted
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setPreferredSampleRate(16_000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            throw AudioError.sessionFailed
        }

        let url: URL
        do {
            url = try Self.makeRecordingURL()
        } catch {
            deactivateSession()
            throw error
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 65_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.prepareToRecord(), newRecorder.record() else {
                throw AudioError.recorderFailed
            }
            recorder = newRecorder
            outputURL = url
        } catch let error as AudioError {
            try? FileManager.default.removeItem(at: url)
            deactivateSession()
            throw error
        } catch {
            try? FileManager.default.removeItem(at: url)
            deactivateSession()
            throw AudioError.recorderFailed
        }

        isRecording = true
        startedAt = Date()
        elapsed = 0
        level = 0
        peakPower = -160
        limitReached = false
        startMetering()
        startLimitTimer()
    }

    /// 停止并返回可上传的录音。调用前无需判断是否到 60s：
    /// 到点由 `limitTask` 先停 recorder，这里再读文件仍然有效。
    func stop() throws -> RecordedAudio {
        guard isRecording, let activeRecorder = recorder, let url = outputURL else {
            throw AudioError.noRecording
        }

        activeRecorder.stop()
        isRecording = false
        stopTasks()
        let measured = Self.duration(of: url)
        let fallback = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let seconds: TimeInterval
        if let measured, measured > 0 {
            seconds = measured
        } else {
            seconds = fallback
        }
        elapsed = min(max(seconds, 0), Self.maxDuration)
        deactivateSession()

        guard seconds >= Self.minDuration else {
            discardFile(at: url)
            reset()
            throw AudioError.tooShort
        }

        if peakPower < Self.silenceThreshold {
            discardFile(at: url)
            reset()
            throw AudioError.noSpeech
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let byteCount = (attributes?[.size] as? NSNumber)?.intValue, byteCount > 0 else {
            discardFile(at: url)
            reset()
            throw AudioError.fileUnavailable
        }
        guard byteCount <= Self.maxBytes else {
            discardFile(at: url)
            reset()
            throw AudioError.fileTooLarge(bytes: byteCount)
        }

        let recorded = RecordedAudio(
            url: url,
            durationMs: Int((elapsed * 1000).rounded()),
            byteCount: byteCount,
            filename: url.lastPathComponent,
            mimeType: Self.mimeType
        )
        reset()
        return recorded
    }

    /// 让尚在等待激活的 `start()` 作废；页面离开/切后台时调用。
    func cancelPendingStart() {
        activationToken += 1
    }

    func cancel() {
        activationToken += 1
        recorder?.stop()
        isRecording = false
        stopTasks()
        if let url = outputURL {
            discardFile(at: url)
        }
        deactivateSession()
        reset()
    }

    // MARK: - 私有

    private func startMetering() {
        meteringTask?.cancel()
        meteringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRecording, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let db = recorder.averagePower(forChannel: 0)
                self.peakPower = max(self.peakPower, db)
                self.level = Self.normalizedLevel(db)
                self.elapsed = min(
                    Date().timeIntervalSince(self.startedAt ?? Date()),
                    Self.maxDuration
                )
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func startLimitTimer() {
        limitTask?.cancel()
        limitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxDuration))
            // sleep 被取消时 try? 会吞掉 CancellationError，必须显式检查，
            // 否则上一轮的 60s 计时器可能把刚开始的新一轮录音停掉。
            guard !Task.isCancelled, let self, self.isRecording else { return }
            self.recorder?.stop()
            self.limitReached = true
        }
    }

    private func stopTasks() {
        meteringTask?.cancel()
        meteringTask = nil
        limitTask?.cancel()
        limitTask = nil
    }

    private func reset() {
        recorder = nil
        outputURL = nil
        startedAt = nil
        level = 0
        peakPower = -160
        limitReached = false
    }

    private func discardFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func normalizedLevel(_ db: Float) -> Double {
        let clamped = max(-50, min(0, db))
        return Double((clamped + 50) / 50)
    }

    private static func makeRecordingURL() throws -> URL {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw AudioError.fileUnavailable
        }
        let directory = base.appendingPathComponent("Recordings", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw AudioError.fileUnavailable
        }
        return directory.appendingPathComponent("\(UUID().uuidString).m4a")
    }

    /// 读文件真实时长（`AVAudioFile` 同步读容器头）；失败时调用方回退到墙钟差。
    private static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0, file.length > 0 else { return nil }
        return Double(file.length) / sampleRate
    }
}

import AVFoundation
import Foundation
import OSLog

private let recorderLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "audio")

/// 一次录音的产物（契约 §3.10）：直接携带字节，上传路径不需要再碰临时文件。
struct RecordedAudio: Sendable, Equatable {
    let data: Data
    let durationMs: Int
    let peakDb: Double
    let isSilent: Bool

    /// 上传 multipart 用的 MIME（m4a 容器 + AAC 编码）。
    var mimeType: String { "audio/mp4" }
    /// 上传 multipart 用的文件名。
    var filename: String { "recording.m4a" }

    var durationSeconds: Double {
        Double(durationMs) / 1_000
    }
}

/// 录音门面：m4a / AAC-LC / 16kHz / 单声道 / 65kbps（audio.md §4.1，唯一配置，不做 A/B 兜底）。
///
/// 只负责“把麦克风的声音写成文件 → 读成 Data”；`AVAudioSession` 的 category/active
/// 由 `AudioSessionController` 串行管理，录音与播放的互斥由 `AudioCoordinator` 保证。
///
/// 关键约束：
/// - 一次“开始→停止” = 一个文件 = 一次上传，**绝不**切片（audio.md §4.4）；
/// - 60s 硬上限由内部计时器自动停掉底层 `AVAudioRecorder`（不丢已录音频，仍可 stop 取回）；
/// - 500ms 下限、12MB 上限、-45dB 整段静音都在本地拦掉，不浪费服务端评分配额；
/// - `AVAudioRecorder` 非 Sendable，因此整类限定在 `@MainActor`。
@MainActor
final class VoiceRecorder {
    /// 单段硬上限（audio.md §4.3）。
    static let maxDuration: TimeInterval = 60
    /// 最小有效时长：更短则本地拦截（audio.md §4.3）。
    static let minDuration: TimeInterval = 0.5
    /// 服务端单文件上限（audio.md §4.2）。
    static let maxBytes = 12 * 1024 * 1024
    /// 开始录音前要求的最小可用空间（audio.md §9“磁盘满”）。
    static let minFreeDiskBytes = 50 * 1024 * 1024
    /// 整段静音阈值：峰值低于 -45dB 视为“没有听到声音”（audio.md §4.3）。
    static let silenceThresholdDb: Float = -45
    /// 电平映射的下限：-50dB → 0，0dB → 1（audio.md §4.5）。
    static let levelFloorDb: Float = -50
    /// 20Hz 采样（≤30fps 刷新要求，audio.md §4.5）。
    static let meterIntervalMs = 50

    /// 电平回调（0...1），由 `AudioCoordinator` 转发到可观察的 `level`。
    var onLevel: (@MainActor (Double) -> Void)?

    private let fileManager = FileManager.default
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var startedAt: Date?
    private var meteringTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?

    private(set) var isRecording = false
    /// 平均电平（波形条用），0...1。
    private(set) var level: Double = 0
    /// 峰值电平，0...1。
    private(set) var peakLevel: Double = 0
    /// 录音时长（秒），最多 `maxDuration`。
    private(set) var elapsed: TimeInterval = 0
    /// 是否已经到达 60s 自动停止（页面可据此提示“到时间了”）。
    private(set) var limitReached = false

    private var peakDb: Float = -160

    // MARK: - 开始 / 停止 / 取消

    /// 单次启动尝试的结果（`Result` 的 Failure 必须是 Error，这里用自定义枚举更直白）。
    private enum StartOutcome {
        case started(AVAudioRecorder)
        case failed(String)
    }

    /// 真机 / 模拟器标记（模拟器没有麦克风输入，录音失败是预期行为）。
    private static var environmentTag: String {
        #if targetEnvironment(simulator)
        return "sim"
        #else
        return "device"
        #endif
    }

    func start() async throws {
        guard !isRecording else { return }
        guard MicPermission.current() == .granted else {
            throw AudioError.permissionDenied
        }
        CacheLocator.ensureAll()
        guard Self.hasEnoughDiskSpace() else {
            throw AudioError.engine("disk_low")
        }

        // 逐级尝试编码参数：契约配置（16k/65k）失败时，先去掉显式码率（仍 16k），
        // 再退到 44.1k（服务端会重采样到 16k 评分，不影响结果），避免某些机型/OS 上
        // AAC 编码器直接拒绝组合、prepareToRecord 返回 false 导致“音频暂时不可用”。
        var failures: [String] = []
        for candidate in Self.settingsCandidates() {
            let url = CacheLocator.recordingsDir()
                .appendingPathComponent("\(UUID().uuidString).m4a")

            switch await Self.beginRecording(url: url, settings: candidate.settings) {
            case .started(let newRecorder):
                recorder = newRecorder
                fileURL = url
                startedAt = Date()
                isRecording = true
                limitReached = false
                level = 0
                peakLevel = 0
                elapsed = 0
                peakDb = -160
                startMetering()
                startLimitTimer()
                recorderLogger.debug("recording started via \(candidate.name, privacy: .public)")
                return
            case .failed(let detail):
                try? fileManager.removeItem(at: url)
                failures.append("\(candidate.name):\(detail)")
            }
        }

        let detail = "recorder_start_failed(\(Self.environmentTag) \(failures.joined(separator: " | ")))"
        recorderLogger.error("\(detail, privacy: .public)")
        throw AudioError.engine(detail)
    }

    /// 创建并启动 `AVAudioRecorder`：prepare/record 各重试一次（iOS 27 上会话激活可能异步完成），
    /// 失败时返回带输入路由/权限/目录的诊断串。
    @MainActor
    private static func beginRecording(
        url: URL,
        settings: [String: Any]
    ) async -> StartOutcome {
        let newRecorder: AVAudioRecorder
        do {
            newRecorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            let nsError = error as NSError
            return .failed("init(\(nsError.domain)#\(nsError.code))")
        }

        newRecorder.isMeteringEnabled = true
        var prepared = newRecorder.prepareToRecord()
        var recording = prepared && newRecorder.record()
        var attempts = 1
        while (!prepared || !recording), attempts < 3 {
            // 路由刚从 A2DP/HFP 切换、或会话激活在系统侧异步完成时，prepare 会立刻失败；
            // 100ms / 250ms 再试两次。
            try? await Task.sleep(for: .milliseconds(attempts == 1 ? 100 : 250))
            prepared = newRecorder.prepareToRecord()
            recording = prepared && newRecorder.record()
            attempts += 1
        }
        guard prepared, recording else {
            return .failed(Self.startFailureDetail(prepared: prepared, recording: recording))
        }
        return .started(newRecorder)
    }

    /// 编码参数候选（顺序即优先级）：契约配置在最前，回退只改码率/采样率，容器与编码不变。
    static func settingsCandidates() -> [(name: String, settings: [String: Any])] {
        [
            ("16k/aac/65k", audioSettings()),
            ("16k/aac/auto", [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]),
            ("44.1k/aac/64k", [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]),
        ]
    }

    /// 停止录音并返回 `RecordedAudio`。
    ///
    /// 时长优先读文件真实时长（`AVURLAsset` → `AVAudioFile`），失败才回退
    /// `currentTime` 与墙钟差；不直接依赖 `recorder.currentTime`（audio.md §4.7）。
    /// 到 60s 已被自动停掉时，本方法仍然有效（文件已落盘）。
    func stop() async throws -> RecordedAudio {
        guard isRecording, let activeRecorder = recorder, let url = fileURL else {
            throw AudioError.engine("not_recording")
        }

        let currentTime = activeRecorder.currentTime
        let wallClock = Date().timeIntervalSince(startedAt ?? Date())
        activeRecorder.stop()
        stopTasks()
        recorder = nil
        fileURL = nil
        startedAt = nil
        isRecording = false

        let measured = await Self.measuredDuration(of: url)
        let fallback = min(max(currentTime, wallClock), Self.maxDuration)
        let seconds = min(max(measured ?? fallback, 0), Self.maxDuration)

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            try? fileManager.removeItem(at: url)
            resetLiveState()
            recorderLogger.error("recorded file unreadable")
            throw AudioError.engine("recording_unreadable")
        }
        try? fileManager.removeItem(at: url)

        defer { resetLiveState() }

        guard seconds >= Self.minDuration else {
            throw AudioError.tooShort
        }
        guard data.count <= Self.maxBytes else {
            throw AudioError.tooLarge
        }

        let recorded = RecordedAudio(
            data: data,
            durationMs: Int((seconds * 1_000).rounded()),
            peakDb: Double(peakDb),
            isSilent: peakDb < Self.silenceThresholdDb
        )
        return recorded
    }

    /// 取消：丢弃半截文件，不产生任何结果（页面消失 / 切后台 / 中断时调用）。
    func cancel() {
        if isRecording {
            recorder?.stop()
        }
        isRecording = false
        stopTasks()
        recorder = nil
        if let url = fileURL {
            try? fileManager.removeItem(at: url)
        }
        fileURL = nil
        startedAt = nil
        resetLiveState()
    }

    // MARK: - 电平与上限

    private func startMetering() {
        meteringTask?.cancel()
        meteringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRecording, let recorder = self.recorder else {
                    return
                }
                recorder.updateMeters()
                let average = recorder.averagePower(forChannel: 0)
                let peak = recorder.peakPower(forChannel: 0)
                self.peakDb = max(self.peakDb, peak)
                let normalized = Self.normalizedLevel(average)
                self.level = normalized
                self.peakLevel = Self.normalizedLevel(self.peakDb)
                self.elapsed = min(
                    Date().timeIntervalSince(self.startedAt ?? Date()),
                    Self.maxDuration
                )
                self.onLevel?(normalized)
                try? await Task.sleep(for: .milliseconds(Self.meterIntervalMs))
            }
        }
    }

    private func startLimitTimer() {
        limitTask?.cancel()
        limitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxDuration))
            // sleep 被取消时 `try?` 会吞掉 CancellationError，必须显式检查，
            // 否则上一轮的 60s 计时器可能把刚开始的新一轮录音停掉。
            guard !Task.isCancelled, let self, self.isRecording else { return }
            self.recorder?.stop()
            self.limitReached = true
            self.elapsed = Self.maxDuration
            self.level = 0
            self.onLevel?(0)
        }
    }

    private func stopTasks() {
        meteringTask?.cancel()
        meteringTask = nil
        limitTask?.cancel()
        limitTask = nil
    }

    private func resetLiveState() {
        level = 0
        peakLevel = 0
        elapsed = 0
        peakDb = -160
        limitReached = false
    }

    // MARK: - 工具

    private static func normalizedLevel(_ db: Float) -> Double {
        let clamped = max(levelFloorDb, min(0, db))
        return Double((clamped - levelFloorDb) / -levelFloorDb)
    }

    /// 录音启动失败时的诊断串：把权限、输入路由、会话配置、缓存目录、剩余空间一次带出来。
    /// 只写日志 / DEBUG 文案，不含用户数据。
    private static func startFailureDetail(prepared: Bool, recording: Bool) -> String {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")
        let available = (session.availableInputs ?? []).map(\.portType.rawValue).joined(separator: ",")
        let permission = AVAudioApplication.shared.recordPermission
        let directory = CacheLocator.recordingsDir()
        let dirOK = FileManager.default.fileExists(atPath: directory.path)
        let freeBytes = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        let freeMB = freeBytes.map { $0 / 1_048_576 } ?? -1
        #if targetEnvironment(simulator)
        let tag = "sim"
        #else
        let tag = "device"
        #endif
        return "recorder_start_failed(\(tag) prepare=\(prepared) record=\(recording) "
            + "permission=\(permission) category=\(session.category.rawValue) mode=\(session.mode.rawValue) "
            + "inputAvailable=\(session.isInputAvailable) inputs=[\(inputs)] available=[\(available)] "
            + "dir=\(dirOK) freeMB=\(freeMB))"
    }

    /// 开始录音前的磁盘空间预检；读不到容量时放行（预检本身不能挡住录音）。
    private static func hasEnoughDiskSpace() -> Bool {
        let url = CacheLocator.recordingsDir()
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage
        else {
            return true
        }
        return available >= Int64(minFreeDiskBytes)
    }

}

// MARK: - 编码参数与时长探测（audio.md §4.1 / §4.7）

extension VoiceRecorder {
    /// 唯一推荐配置：m4a 容器 / AAC-LC 编码 / 16kHz / 单声道 / 65kbps（audio.md §4.1）。
    /// 不设可选码率/采样率分支：评分口径必须稳定，真机异常时先回报再单点调整。
    static func audioSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 65_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }

    /// 读文件真实时长（audio.md §4.7 的第一优先级）：`AVURLAsset` 读容器头，
    /// 失败回退 `AVAudioFile`。两处都失败返回 nil，由调用方回退 `currentTime` 与墙钟差。
    static func measuredDuration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                return seconds
            }
        }
        if let file = try? AVAudioFile(forReading: url) {
            let sampleRate = file.fileFormat.sampleRate
            if sampleRate > 0, file.length > 0 {
                return Double(file.length) / sampleRate
            }
        }
        return nil
    }
}

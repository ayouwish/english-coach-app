import AVFAudio
import Foundation
import OSLog

private let sessionLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "audio")

/// 音频子系统事件：`AudioSessionController` 统一监听系统通知后转成的事件流。
///
/// 页面**不直接**监听 `NotificationCenter`，只消费协调器/会话控制器暴露的事件，
/// 这样 category/active 的变更和中断处理永远不会出现两处并发执行。
enum AudioEvent: Sendable, Equatable {
    /// 来电、闹钟、其他 App 抢占音频焦点：录音必须中止，播放必须停下。
    case interruptionBegan
    /// 中断结束。`shouldResume` 只作为提示：本实现对录音**绝不**自动续录，
    /// 对播放也不自动恢复（避免通话挂断后突然外放）。
    case interruptionEnded(shouldResume: Bool)
    /// 路由变化（拔耳机、接蓝牙等）。
    case routeChanged(AudioRouteChange)
    /// 媒体服务重启（AVAudioSession 与本进程的音视频对象需要重建）。
    case mediaServicesWereReset
}

enum AudioRouteChange: Sendable, Equatable {
    case oldDeviceUnavailable
    case newDeviceAvailable
    case other
}

/// `AVAudioSession` 的唯一开关人：category / mode / options / active 全部串行切换。
///
/// 为什么固定在主线程（architecture.md §6）：录音阶段用 `.playAndRecord`、
/// 播放阶段用 `.playback`，两处若并发 `setCategory` 会互相覆盖；`@MainActor` 天然串行，
/// “先停播放 → 等真正停止 → 切 category → 激活”的顺序才有保证。同时 AVFoundation 的
/// 会话/录音器/播放器都按“主线程配置”的惯例使用——iPadOS 27 真机实测，在 actor 后台
/// 执行器上激活会话会返回 `NSCocoaErrorDomain#-50`，随后录音器也 prepare 失败。
///
/// 注意：这里只做会话配置，**不**决定录音与播放互斥——那是 `AudioCoordinator` 的职责。
@MainActor
final class AudioSessionController {
    /// 两种互斥的会话阶段（对应 audio.md §3.1 的两行配置）。
    enum Configuration: Sendable, Equatable {
        case recording
        case playback
    }

    /// 录音编码采样率：受硬件限制，会话采样率可能被系统定在 48kHz，
    /// 但 `AVAudioRecorder` 会按 `AVSampleRateKey = 16_000` 编码输出（audio.md §3.1）。
    static let preferredRecordingSampleRate: Double = 16_000
    /// 5ms 的 IO buffer，降低“按下录音 → 真正开始”的延迟（audio.md §3.1）。
    static let preferredIOBufferDuration: TimeInterval = 0.005

    /// 系统事件流（`AsyncStream` 是 Sendable 的，可跨隔离安全传递）。
    let events: AsyncStream<AudioEvent>

    private let session: AVAudioSession
    private var observers: [any NSObjectProtocol]
    private var activeConfiguration: Configuration?
    private var isActive = false

    init() {
        let (stream, continuation) = AsyncStream<AudioEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        self.events = stream
        self.session = AVAudioSession.sharedInstance()
        self.observers = []
        self.observers = Self.installObservers(continuation: continuation)
    }

    // MARK: - 配置与激活

    /// 空闲阶段只配置 category（**不** `setActive(true)`），不打断其他 App 的声音；
    /// 同时把播放配置提前设好，减少首次起播的切换延迟。
    func prepare() {
        // 与 `activate(.playback)` 同一套回退链：iOS 27 上 `.spokenAudio` + `.allowBluetoothA2DP`
        // 的组合可能被系统以 -50（paramErr）拒绝；这里失败也不影响后续激活（真正激活时会重新配置）。
        for candidate in Self.playbackCandidates() {
            do {
                try session.setCategory(candidate.category, mode: candidate.mode, options: candidate.options)
                try? session.setPreferredIOBufferDuration(Self.preferredIOBufferDuration)
                sessionLogger.debug("prepare ok via \(candidate.name, privacy: .public)")
                return
            } catch {
                sessionLogger.debug(
                    "prepare failed via \(candidate.name, privacy: .public) \(Self.errorCode(error), privacy: .public)"
                )
            }
        }
    }

    /// 串行激活会话。重复激活同一阶段直接返回，避免无谓的 category 抖动。
    ///
    /// iPadOS 27 实测：`setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])`
    /// 会返回 `NSCocoaErrorDomain#-50`（paramErr）。因此每个阶段都按“原设计 → 通用”逐级回退，
    /// 任一档成功即使用；全部失败时把每一档的失败原因一起抛出（DEBUG 下直接显示在错误文案里）。
    func activate(_ configuration: Configuration) throws {
        if isActive, activeConfiguration == configuration {
            return
        }
        do {
            switch configuration {
            case .recording:
                try activateRecording()
            case .playback:
                try activatePlayback()
            }
            activeConfiguration = configuration
            isActive = true
        } catch let audioError as AudioError {
            activeConfiguration = nil
            isActive = false
            if case .engine(let detail) = audioError {
                sessionLogger.error("audio session activate failed: \(detail, privacy: .public)")
            }
            throw audioError
        } catch {
            activeConfiguration = nil
            isActive = false
            let detail = "session_activation_failed(\(configuration) \(Self.environmentTag) \(Self.errorCode(error)))"
            sessionLogger.error("audio session activate failed: \(detail, privacy: .public)")
            throw AudioError.engine(detail)
        }
    }

    // MARK: - 各阶段的回退激活

    /// 播放：优先保留原配置（spokenAudio 适合人声、A2DP 保持蓝牙音质），失败再退回通用配置。
    private func activatePlayback() throws {
        var failures: [String] = []
        for candidate in Self.playbackCandidates() {
            do {
                try session.setCategory(candidate.category, mode: candidate.mode, options: candidate.options)
            } catch {
                failures.append("\(candidate.name):setCategory(\(Self.errorCode(error)))")
                continue
            }
            guard activateSession(attemptName: candidate.name, failures: &failures) else {
                continue
            }
            sessionLogger.debug("playback activated via \(candidate.name, privacy: .public)")
            Self.routeToSpeakerIfNeeded(session: session)
            return
        }
        throw AudioError.engine(
            "playback_failed(\(Self.environmentTag) \(failures.joined(separator: " | ")))"
        )
    }

    /// 录音：`defaultToSpeaker` 保证外放不是听筒；HFP 让蓝牙耳机麦克风可用。
    /// 个别路由会拒绝某个选项组合（-50），逐级去掉选项重试。
    private func activateRecording() throws {
        var failures: [String] = []
        for candidate in Self.recordingCandidates() {
            do {
                try session.setCategory(candidate.category, mode: .default, options: candidate.options)
            } catch {
                failures.append("\(candidate.name):setCategory(\(Self.errorCode(error)))")
                continue
            }
            // 采样率 / IO buffer 只是“偏好”：蓝牙 HFP、外接声卡等路由可能直接拒绝。
            // 拒绝时用系统默认值即可，**不能**因此让整次录音激活失败。
            try? session.setPreferredSampleRate(Self.preferredRecordingSampleRate)
            try? session.setPreferredIOBufferDuration(Self.preferredIOBufferDuration)
            guard activateSession(attemptName: candidate.name, failures: &failures) else {
                continue
            }
            sessionLogger.debug("recording activated via \(candidate.name, privacy: .public)")
            return
        }
        throw AudioError.engine(
            "recording_failed(\(Self.environmentTag) \(failures.joined(separator: " | ")))"
        )
    }

    /// `setActive(true)` 失败后先复位再试一次：媒体服务刚重启 / 路由刚切换时，
    /// 第一次激活可能返回 paramErr（-50），复位后通常能成功。
    private func activateSession(attemptName: String, failures: inout [String]) -> Bool {
        do {
            try session.setActive(true)
            return true
        } catch {
            failures.append("\(attemptName):setActive(\(Self.errorCode(error)))")
            try? session.setActive(false)
            do {
                try session.setActive(true)
                return true
            } catch {
                failures.append("\(attemptName):setActiveRetry(\(Self.errorCode(error)))")
                return false
            }
        }
    }

    // MARK: - 回退候选与诊断工具

    private static func playbackCandidates()
        -> [(name: String, category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)] {
        [
            ("playback/spokenAudio/A2DP", .playback, .spokenAudio, [.allowBluetoothA2DP]),
            ("playback/default", .playback, .default, []),
            ("playAndRecord/defaultToSpeaker", .playAndRecord, .default, [.defaultToSpeaker]),
        ]
    }

    private static func recordingCandidates()
        -> [(name: String, category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions)] {
        [
            ("playAndRecord/defaultToSpeaker/HFP", .playAndRecord, [.defaultToSpeaker, .allowBluetoothHFP]),
            ("playAndRecord/defaultToSpeaker", .playAndRecord, [.defaultToSpeaker]),
            ("playAndRecord/noOptions", .playAndRecord, []),
            // 最后兜底：只要输入，不需要边录边放（播放阶段会另行切回 .playback）。
            ("record/noOptions", .record, []),
        ]
    }

    /// 真机 / 模拟器标记：模拟器没有麦克风输入，录音失败是预期行为，诊断串里要能区分。
    private static var environmentTag: String {
        #if targetEnvironment(simulator)
        return "sim"
        #else
        return "device"
        #endif
    }

    private static func errorCode(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }

    /// 归还音频焦点，让其他 App 恢复声音。
    func deactivate() {
        activeConfiguration = nil
        guard isActive else { return }
        isActive = false
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            sessionLogger.debug("audio session deactivate failed")
        }
    }

    // MARK: - 观察者

    /// 注册全部音频通知，只把「归一化后的事件」交给事件流。
    /// 闭包里只捕获 `continuation`（Sendable），不捕获 actor 自身，避免跨隔离访问。
    private static func installObservers(
        continuation: AsyncStream<AudioEvent>.Continuation
    ) -> [any NSObjectProtocol] {
        let center = NotificationCenter.default
        var tokens: [any NSObjectProtocol] = []

        tokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { notification in
                guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType)
                else {
                    return
                }
                switch type {
                case .began:
                    continuation.yield(.interruptionBegan)
                case .ended:
                    let rawOption = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                    let shouldResume = rawOption.map {
                        AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume)
                    } ?? false
                    continuation.yield(.interruptionEnded(shouldResume: shouldResume))
                @unknown default:
                    continuation.yield(.interruptionEnded(shouldResume: false))
                }
            }
        )

        tokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { notification in
                guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
                else {
                    continuation.yield(.routeChanged(.other))
                    return
                }
                switch reason {
                case .oldDeviceUnavailable:
                    continuation.yield(.routeChanged(.oldDeviceUnavailable))
                case .newDeviceAvailable:
                    continuation.yield(.routeChanged(.newDeviceAvailable))
                default:
                    continuation.yield(.routeChanged(.other))
                }
            }
        )

        tokens.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { _ in
                continuation.yield(.mediaServicesWereReset)
            }
        )

        return tokens
    }

    // MARK: - 路由

    /// 输出被系统切到听筒时，播放前覆盖回扬声器（audio.md §6.5）。
    /// 只在播放阶段调用，录音阶段覆盖会破坏 HFP，不做。
    private static func routeToSpeakerIfNeeded(session: AVAudioSession) {
        let outputs = session.currentRoute.outputs
        let hasReceiver = outputs.contains { $0.portType == .builtInReceiver }
        guard hasReceiver else { return }
        do {
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            sessionLogger.debug("override output port failed")
        }
    }
}

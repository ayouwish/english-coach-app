import AVFAudio
import Foundation
import OSLog

private let sessionLogger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "audio")

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
/// 为什么必须是 actor（architecture.md §6）：录音阶段用 `.playAndRecord`、
/// 播放阶段用 `.playback`，两处若并发 `setCategory` 会互相覆盖；
/// 串行化之后“先停播放 → 等真正停止 → 切 category → 激活”的顺序才有保证。
///
/// 注意：这里只做会话配置，**不**决定录音与播放互斥——那是 `AudioCoordinator` 的职责。
actor AudioSessionController {
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
    nonisolated let events: AsyncStream<AudioEvent>

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
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
            try session.setPreferredIOBufferDuration(Self.preferredIOBufferDuration)
        } catch {
            sessionLogger.debug("audio session prepare failed")
        }
    }

    /// 串行激活会话。重复激活同一阶段直接返回，避免无谓的 category 抖动。
    func activate(_ configuration: Configuration) throws {
        if isActive, activeConfiguration == configuration {
            return
        }
        do {
            switch configuration {
            case .recording:
                // 录音：需要输入；defaultToSpeaker 保证外放不是听筒；allowBluetooth 支持耳机 HFP 麦克风。
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .allowBluetooth]
                )
                try session.setPreferredSampleRate(Self.preferredRecordingSampleRate)
                try session.setPreferredIOBufferDuration(Self.preferredIOBufferDuration)
                try session.setActive(true)
            case .playback:
                // 播放：A2DP 保持蓝牙音质；spokenAudio 适配人声且静音键不会静音（audio.md §3.1）。
                try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
                try session.setActive(true)
                Self.routeToSpeakerIfNeeded(session: session)
            }
            activeConfiguration = configuration
            isActive = true
        } catch {
            activeConfiguration = nil
            isActive = false
            sessionLogger.error("audio session activate failed")
            throw AudioError.engine("session_activation_failed")
        }
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

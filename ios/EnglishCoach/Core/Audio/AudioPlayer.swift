import AVFoundation
import Foundation
import Observation

enum AudioError: Error, Equatable, Sendable {
    case permissionDenied
    case sessionFailed
    case recorderFailed
    case playerFailed
    case tooShort
    case noSpeech
    case fileTooLarge(bytes: Int)
    case noRecording
    case fileUnavailable
    case interrupted

    func userMessage(forChild isChild: Bool) -> String {
        switch self {
        case .permissionDenied:
            return isChild ? "麦克风被关掉了，去设置里打开就能录音啦" : "麦克风权限被关闭了，请到系统设置里打开"
        case .sessionFailed:
            return isChild ? "没能打开麦克风，再试一次" : "音频会话启动失败，请重试或换一副耳机"
        case .recorderFailed:
            return isChild ? "录音没有开始，再点一下试试" : "录音启动失败，请重试"
        case .playerFailed:
            return isChild ? "这段声音暂时放不出来" : "音频播放失败，请重试"
        case .tooShort:
            return isChild ? "太短啦，再说一次" : "录音太短了，请再说一次"
        case .noSpeech:
            return isChild ? "没有听到声音，靠近一点再说一次" : "没有检测到人声，请靠近麦克风重试"
        case .fileTooLarge:
            return isChild ? "说得太久啦，短一点再试" : "录音文件超过 12MB，请缩短录音"
        case .noRecording:
            return isChild ? "还没有录音哦" : "尚无可用的录音"
        case .fileUnavailable:
            return isChild ? "录音找不到了" : "录音文件不可用，请重新录制"
        case .interrupted:
            return isChild ? "刚刚被打断了，再录一次" : "录音被系统中断，请重新录制"
        }
    }
}

/// 播放器门面：同一时刻只允许一个实例在播。
///
/// 不用 `AVAudioPlayerDelegate`（避免在 Swift 6 下给 @objc 协议补 nonisolated 实现）：
/// 用 100ms 轮询 `isPlaying` 观察播放结束，对短句 TTS 足够。
@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    func play(url: URL) throws {
        stop(deactivateSession: false)
        try activatePlaybackSession()

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.volume = 1
            guard newPlayer.prepareToPlay(), newPlayer.play() else {
                throw AudioError.playerFailed
            }
            player = newPlayer
            isPlaying = true

            let currentGeneration = UUID()
            generation = currentGeneration
            watcher = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self, self.generation == currentGeneration, let current = self.player else {
                        return
                    }
                    if !current.isPlaying {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard let self, self.generation == currentGeneration else { return }
                self.player = nil
                self.isPlaying = false
                self.deactivateSession()
            }
        } catch let error as AudioError {
            throw error
        } catch {
            throw AudioError.playerFailed
        }
    }

    /// 播完再返回。“跟我读”依赖它实现“示范音结束自动开录”。
    func playAndWait(url: URL) async throws {
        try play(url: url)
        await waitUntilFinished()
    }

    func waitUntilFinished() async {
        while isPlaying {
            if Task.isCancelled {
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func stop(deactivateSession: Bool = true) {
        generation = UUID()
        watcher?.cancel()
        watcher = nil
        player?.stop()
        player = nil
        isPlaying = false
        if deactivateSession {
            self.deactivateSession()
        }
    }

    private func activatePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // 播放阶段用 .playback + .spokenAudio：不走听筒、静音键不会静音；
            // A2DP 让蓝牙输出保持好音质（与录音阶段的 HFP 区分，见 audio.md §3）。
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            throw AudioError.sessionFailed
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

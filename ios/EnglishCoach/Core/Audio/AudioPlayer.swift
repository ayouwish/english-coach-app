import AVFoundation
import Foundation
import OSLog

private let playerLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "audio")

/// 播放器门面：**同一时刻只播一个音频**，换源 = 先停旧的再播新的。
///
/// 设计要点：
/// - `AVAudioPlayer` 非 Sendable，整个类限定在 `@MainActor`；
/// - 完成回调走 `AVAudioPlayerDelegate`（`nonisolated` 实现里 hop 回主线程），
///   同时提供 `playAndWait*` 的 continuation 版本给“播完自动开录”这类串行动作；
/// - 传入 `Data` 时先写临时文件再播（audio.md §6.1：统一“先落盘再播”，
///   `formatHint` 决定临时文件扩展名），播完/停止即删；
/// - 不碰 `AVAudioSession`（category/active 只由 `AudioSessionController` 负责）。
@MainActor
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var completionHandler: (@MainActor () -> Void)?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var progressTask: Task<Void, Never>?
    private var temporaryFileURL: URL?
    /// 每次播放/停止递增；迟到的进度任务与 delegate 回调靠它自证归属。
    private var generation = 0

    /// `nonisolated` 覆写 `NSObject.init()`：全部存储属性都有默认值，构造本身不需要主线程；
    /// 真正的 `AVAudioPlayer` 操作仍然只在 `@MainActor` 方法里发生。
    nonisolated override init() {
        super.init()
    }

    // MARK: - 播放

    /// 播放内存字节（TTS 返回的 mp3/wav）。
    func play(
        data: Data,
        formatHint: String?,
        completion: (@MainActor () -> Void)? = nil
    ) throws {
        let tempURL: URL
        do {
            tempURL = try writeTemporaryFile(data: data, formatHint: formatHint)
        } catch {
            playerLogger.error("write playback temp file failed")
            throw AudioError.engine("player_temp_file_failed")
        }
        do {
            try startPlayback(fileURL: tempURL, ownsFile: true, completion: completion)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    /// 播放本地文件（录音回放、已落盘的 TTS）。
    func play(fileURL: URL, completion: (@MainActor () -> Void)? = nil) throws {
        try startPlayback(fileURL: fileURL, ownsFile: false, completion: completion)
    }

    /// 播完再返回（“示范音结束自动开录”依赖它）。
    func playAndWait(data: Data, formatHint: String?) async throws {
        try play(data: data, formatHint: formatHint)
        await waitUntilFinished()
    }

    func playAndWait(fileURL: URL) async throws {
        try play(fileURL: fileURL)
        await waitUntilFinished()
    }

    /// 主动停止。不会触发完成回调（调用方自己知道是主动停的）。
    func stop() {
        teardown()
    }

    // MARK: - 内部

    private func startPlayback(
        fileURL: URL,
        ownsFile: Bool,
        completion: (@MainActor () -> Void)?
    ) throws {
        teardown()

        let newPlayer: AVAudioPlayer
        do {
            newPlayer = try AVAudioPlayer(contentsOf: fileURL)
        } catch {
            let nsError = error as NSError
            let detail = "player_decode_failed(\(nsError.domain)#\(nsError.code))"
            playerLogger.error("\(detail, privacy: .public) ext=\(fileURL.pathExtension, privacy: .public)")
            throw AudioError.engine(detail)
        }

        newPlayer.delegate = self
        newPlayer.volume = 1
        newPlayer.rate = 1
        guard newPlayer.prepareToPlay() else {
            let detail = "player_prepare_failed(ext=\(fileURL.pathExtension))"
            playerLogger.error("\(detail, privacy: .public)")
            throw AudioError.engine(detail)
        }
        guard newPlayer.play() else {
            // play() 返回 false 表示系统拒绝起播：把会话状态一起记下来，便于区分
            // “category/active 不对”还是“被其他 App 抢占/设备路由不可用”。
            let detail = "player_play_failed(\(Self.sessionSnapshot()))"
            playerLogger.error("\(detail, privacy: .public)")
            throw AudioError.engine(detail)
        }

        player = newPlayer
        duration = newPlayer.duration
        currentTime = 0
        progress = 0
        completionHandler = completion
        temporaryFileURL = ownsFile ? fileURL : nil
        isPlaying = true

        let currentGeneration = generation
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self,
                      self.generation == currentGeneration,
                      let current = self.player
                else {
                    return
                }
                let time = current.currentTime
                let total = current.duration
                self.currentTime = time
                self.duration = total
                self.progress = total > 0 ? min(max(time / total, 0), 1) : 0
                if !current.isPlaying {
                    // delegate 通常先到；这里兜底，避免个别格式不回调时 UI 一直显示“播放中”。
                    self.finishPlayback()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// 自然播放结束：清状态 → 调完成回调。
    private func finishPlayback() {
        guard isPlaying else { return }
        let finishedDuration = duration
        let handler = completionHandler
        teardown()
        duration = finishedDuration
        currentTime = finishedDuration
        progress = 1
        handler?()
    }

    /// 解码/播放出错：清状态并把完成回调也走掉，让协调器回到 idle（错误细节只写日志）。
    private func failPlayback() {
        guard isPlaying else { return }
        playerLogger.error("audio player decode error")
        let handler = completionHandler
        teardown()
        handler?()
    }

    /// 释放播放器与临时文件；重复调用安全。
    private func teardown() {
        generation += 1
        progressTask?.cancel()
        progressTask = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        completionHandler = nil
        isPlaying = false
        currentTime = 0
        progress = 0
        duration = 0
        cleanupTemporaryFile()
        resumeWaiters()
    }

    private func waitUntilFinished() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if isPlaying {
                    waiters.append(continuation)
                } else {
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
    }

    private func resumeWaiters() {
        guard !waiters.isEmpty else { return }
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    private func cleanupTemporaryFile() {
        guard let url = temporaryFileURL else { return }
        temporaryFileURL = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func writeTemporaryFile(data: Data, formatHint: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ec-audio-\(UUID().uuidString).\(Self.fileExtension(for: formatHint))")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileExtension(for formatHint: String?) -> String {
        switch formatHint?.lowercased() ?? "" {
        case "mp3", "mpeg":
            return "mp3"
        case "wav", "wave":
            return "wav"
        case "m4a", "aac", "mp4":
            return "m4a"
        case "caf":
            return "caf"
        default:
            return "m4a"
        }
    }

    /// 起播失败时的 `AVAudioSession` 快照（只读、不含用户数据），仅用于日志/诊断。
    private static func sessionSnapshot() -> String {
        let session = AVAudioSession.sharedInstance()
        let category = session.category.rawValue
        let mode = session.mode.rawValue
        return "category=\(category) mode=\(mode) otherAudio=\(session.isOtherAudioPlaying)"
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finishPlayback()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.failPlayback()
        }
    }
}

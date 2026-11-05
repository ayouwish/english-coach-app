import Foundation
import Observation

/// 整段回放状态机（会话页 / 历史详情页共用）。
///
/// 协议约束（`port-contract.md` §3.6 已确认）：`ChatService.audio` 的 202 无法从
/// `APITransport` 拿到状态码，所以**先轮询 `audioStatus` 到 ready 再取音频**；
/// 失败时可 `force` 强制重生成。轮询任务在退出页面 / 切后台时取消。
@MainActor
@Observable
final class ChatReplayController {
    enum State: Equatable {
        case idle
        case loading
        case building
        case ready
        case failed
    }

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let audio: AudioCoordinator
    @ObservationIgnored private let sessionID: String
    @ObservationIgnored private let isChild: Bool

    private(set) var state: State = .idle
    private(set) var errorMessage = ""
    private(set) var durationMs = 0
    private(set) var isPlaying = false

    @ObservationIgnored private var data: Data?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watchTask: Task<Void, Never>?

    /// 轮询间隔 2s、最多 30 次（60s）。
    private static let pollInterval: Duration = .seconds(2)
    private static let pollMaxTries = 30

    init(sessionID: String, services: AppServices, audio: AudioCoordinator, isChild: Bool) {
        self.sessionID = sessionID
        self.services = services
        self.audio = audio
        self.isChild = isChild
    }

    var durationText: String {
        durationMs > 0 ? "总长约 " + EcFormat.clock(milliseconds: durationMs) : "整段回放已经准备好啦"
    }

    /// 首次生成：只查状态（不触发构建），ready 才取音频，building 则轮询。
    func begin() async {
        guard state == .idle || state == .failed else { return }
        state = .loading
        errorMessage = ""
        await queryStatus()
    }

    /// 强制重新生成（失败后的入口）。
    func regenerate() async {
        pollTask?.cancel()
        state = .loading
        errorMessage = ""
        do {
            let result = try await services.chat.audio(sessionId: sessionID, force: true)
            switch result.state {
            case .ready(let bytes):
                data = bytes
                state = .ready
            case .building:
                state = .building
                schedulePoll()
            case .failed(let message):
                state = .failed
                errorMessage = message.isEmpty ? fallbackErrorText() : message
            }
        } catch {
            state = .failed
            errorMessage = describe(error)
        }
    }

    func togglePlay() async {
        guard let data else { return }
        if isPlaying {
            await stop()
            return
        }
        do {
            try await audio.play(data: data, formatHint: "wav")
            isPlaying = true
            watchPlayback()
        } catch {
            isPlaying = false
            state = .failed
            errorMessage = describe(error)
        }
    }

    /// 停止回放（页面退出、开始录音等场景由 `ChatSessionStore` 调用）。
    func stop() async {
        watchTask?.cancel()
        await audio.stopPlayback()
        isPlaying = false
    }

    func pauseForBackground() {
        pollTask?.cancel()
        watchTask?.cancel()
        isPlaying = false
        // 构建中的轮询被取消：回到 idle，回到前台后可重新点「生成整段回放」。
        if state == .building || state == .loading {
            state = .idle
        }
    }

    func dispose() {
        pollTask?.cancel()
        watchTask?.cancel()
        pollTask = nil
        watchTask = nil
    }

    // MARK: - 内部

    private func queryStatus() async {
        do {
            let status = try await services.chat.audioStatus(sessionId: sessionID)
            if let duration = status.durationMs, duration > 0 {
                durationMs = duration
            }
            switch status.status ?? "" {
            case "ready":
                await fetchAudio()
            case "building":
                state = .building
                schedulePoll()
            case "failed":
                state = .failed
                errorMessage = status.error ?? ""
            default:
                state = .building
                schedulePoll()
            }
        } catch {
            state = .failed
            errorMessage = describe(error)
        }
    }

    private func fetchAudio() async {
        do {
            let result = try await services.chat.audio(sessionId: sessionID, force: false)
            switch result.state {
            case .ready(let bytes):
                data = bytes
                state = .ready
            case .building:
                state = .building
                schedulePoll()
            case .failed(let message):
                state = .failed
                errorMessage = message.isEmpty ? fallbackErrorText() : message
            }
        } catch {
            state = .failed
            errorMessage = describe(error)
        }
    }

    private func schedulePoll() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<Self.pollMaxTries {
                do { try await Task.sleep(for: Self.pollInterval) } catch { return }
                guard !Task.isCancelled else { return }
                do {
                    let status = try await self.services.chat.audioStatus(sessionId: self.sessionID)
                    if let duration = status.durationMs, duration > 0 {
                        self.durationMs = duration
                    }
                    switch status.status ?? "" {
                    case "ready":
                        await self.fetchAudio()
                        return
                    case "failed":
                        self.state = .failed
                        self.errorMessage = status.error ?? ""
                        return
                    default:
                        self.state = .building
                    }
                } catch {
                    self.state = .failed
                    self.errorMessage = self.describe(error)
                    return
                }
            }
            self.state = .failed
            self.errorMessage = ""
        }
    }

    private func watchPlayback() {
        watchTask?.cancel()
        watchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                if !self.audio.isPlaying || self.audio.mode != .playing {
                    self.isPlaying = false
                    return
                }
            }
        }
    }

    private func describe(_ error: any Error) -> String {
        let ui = ErrorMapper.message(for: error, isChild: isChild)
        let parts = [ui.title, ui.body].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: "；")
    }

    private func fallbackErrorText() -> String {
        describe(APIError.server(code: .providerError, message: nil, status: 500))
    }
}

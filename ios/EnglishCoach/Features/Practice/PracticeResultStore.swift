import Foundation
import Observation
import SwiftUI

/// 跟读详细结果页状态（`.practiceResult`）。
///
/// 数据来源优先级：
/// 1. `PracticeResultHandoff`（刚评测完的本次结果，含逐词/音素明细）；
/// 2. `GET /attempts?limit=50` 按 attemptId 兜底（历史记录没有逐词/音素明细）；
/// 3. 单句历史 `PracticeService.attemptsForSentence(id:)` → 进步曲线。
@MainActor
@Observable
final class PracticeResultStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed
    }

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore

    private(set) var result: PracticeAttemptResult?
    private(set) var history: [PracticeHistoryEntry] = []
    private(set) var phase: Phase = .idle
    private(set) var historyPhase: Phase = .idle
    private(set) var errorMessage: UIMessage?
    private(set) var historyError: UIMessage?
    private(set) var isPlayingRecording = false
    private(set) var playingHistoryId: String?

    private let attemptId: String?
    private var historyAttemptId: String?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore, attemptId: String?) {
        self.services = services
        self.audio = audio
        self.session = session
        self.attemptId = attemptId
    }

    var caps: RoleCapabilities { session.capabilities }
    var sentenceId: String { result?.sentenceId ?? "" }

    var historyScores: [Double] { history.map(\.score) }

    var firstHistoryScore: Double? { history.first?.score }
    var lastHistoryScore: Double? { history.last?.score }

    var historyDeltaText: String {
        guard let first = firstHistoryScore, let last = lastHistoryScore else { return "" }
        let delta = last - first
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", delta))"
    }

    // MARK: - 加载

    func loadIfNeeded() async {
        guard phase == .idle else { return }
        await load()
    }

    func load() async {
        phase = .loading
        errorMessage = nil
        historyError = nil

        if let handoff = PracticeResultHandoff.result(matching: attemptId) {
            result = handoff
            phase = .loaded
        } else {
            do {
                let list = try await services.practice.attempts(limit: 50)
                let item: AttemptItemDTO? = {
                    guard let attemptId, !attemptId.isEmpty else { return list.first }
                    return list.first { $0.id == attemptId }
                }()
                guard let item, let mapped = PracticeResultMapper.make(item: item) else {
                    phase = .empty
                    return
                }
                result = mapped
                phase = .loaded
            } catch is CancellationError {
                return
            } catch {
                if let apiError = error as? APIError, apiError.isCancelled {
                    return
                }
                let message = ErrorMapper.message(for: error, isChild: caps.isChild)
                errorMessage = message
                phase = .failed
                if message.action == .relogin {
                    await session.handleSessionExpired()
                }
                return
            }
        }

        await loadHistory()
    }

    private func loadHistory() async {
        guard let sentenceId = result?.sentenceId, !sentenceId.isEmpty else {
            historyPhase = .loaded
            return
        }
        historyPhase = .loading
        do {
            let list = try await services.practice.attemptsForSentence(id: sentenceId)
            let entries = list.compactMap { item -> PracticeHistoryEntry? in
                guard item.pending != true, let score = item.scores?.pron else { return nil }
                let label = historyLabel(from: item.createdAt)
                return PracticeHistoryEntry(attemptId: item.id, score: score, label: label)
            }
            // 服务端按时间倒序返回；曲线按「旧 → 新」。
            history = Array(entries.prefix(10).reversed())
            historyPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            if let apiError = error as? APIError, apiError.isCancelled {
                return
            }
            let message = ErrorMapper.message(for: error, isChild: caps.isChild)
            historyError = message
            historyPhase = .failed
        }
    }

    private func historyLabel(from raw: String?) -> String {
        if let date = ECJSON.date(from: raw) {
            return EcFormat.relative(date)
        }
        return ""
    }

    // MARK: - 回放

    func playRecording() {
        guard let attemptId = result?.attemptId, !attemptId.isEmpty else { return }
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await self.services.practice.audioData(audioId: attemptId)
                try Task.checkCancellation()
                self.isPlayingRecording = true
                try await self.audio.play(data: data, formatHint: "m4a")
                await self.waitForPlaybackEnd()
            } catch is CancellationError {
                // 主动停止。
            } catch {
                await self.handle(error)
            }
            self.isPlayingRecording = false
        }
    }

    func playHistory(entry: PracticeHistoryEntry) {
        playbackTask?.cancel()
        playbackTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await self.services.practice.audioData(audioId: entry.attemptId)
                try Task.checkCancellation()
                self.playingHistoryId = entry.attemptId
                try await self.audio.play(data: data, formatHint: "m4a")
                await self.waitForPlaybackEnd()
            } catch is CancellationError {
                // 主动停止。
            } catch {
                await self.handle(error)
            }
            self.playingHistoryId = nil
        }
    }

    /// degraded 结果重评（结果页只读，不提供重新上传）。
    func retryEvaluate() async {
        guard let attemptId = result?.attemptId, !attemptId.isEmpty else { return }
        errorMessage = nil
        do {
            let response = try await services.practice.retryAttempt(id: attemptId)
            try Task.checkCancellation()
            if let usage = response.usage {
                session.apply(usage: usage)
            }
            if let mapped = PracticeResultMapper.make(response: response, sentenceId: sentenceId) {
                result = mapped
                PracticeResultHandoff.store(mapped)
                await loadHistory()
            }
        } catch is CancellationError {
            // 页面已离开。
        } catch {
            await handle(error)
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlayingRecording = false
        playingHistoryId = nil
        Task { @MainActor [weak self] in
            await self?.audio.stopPlayback()
        }
    }

    // MARK: - 错误

    private func handle(_ error: Error) async {
        if let apiError = error as? APIError, apiError.isCancelled {
            return
        }
        if error is CancellationError {
            return
        }
        let message = ErrorMapper.message(for: error, isChild: caps.isChild)
        guard !message.isSilent else { return }
        errorMessage = message
        if message.action == .relogin {
            await session.handleSessionExpired()
        }
    }

    private func waitForPlaybackEnd(timeoutMs: Int = 30_000) async {
        var waited = 0
        while audio.isPlaying && waited < timeoutMs {
            if Task.isCancelled {
                await audio.stopPlayback()
                return
            }
            try? await Task.sleep(for: .milliseconds(80))
            waited += 80
        }
    }
}

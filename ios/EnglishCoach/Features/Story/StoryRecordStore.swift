import Foundation
import Observation
import UIKit

/// 讲故事（录音/拍照 → 中文 → 改写 → 保存）状态。
///
/// 线上没有 `POST story/recordings`（404），所以录音走 `StoryService.asr(language: "zh-CN")`；
/// 原始录音只在本机留一份（`RecordingCache`，7 天）供详情页「我当时讲的原话」回放。
@MainActor
@Observable
final class StoryRecordStore {
    enum BusyKind: String, Equatable {
        case none
        case ocr
        case asr
        case rewrite
        case save
    }

    // MARK: 输入（可编辑，View 直接绑定）

    var textZh: String = ""
    var title: String = ""
    var level: String = "A1"
    var maxSentences: Int = 5
    /// 保存后是否自动生成插画（初值来自账号偏好 `auto_illustrate`，可在本页临时改）。
    var autoIllustrate: Bool = false
    /// 是否让服务端把最近最弱的音素练进故事（web 默认勾选；task-50）。
    var useWeakPhonemes: Bool = true

    // MARK: 状态

    private(set) var busyKind: BusyKind = .none
    private(set) var busyText: String = ""
    private(set) var notice: String = ""
    private(set) var inlineError: String = ""
    private(set) var uiError: UIMessage?
    private(set) var hasResult = false
    private(set) var sentences: [StorySentenceItem] = []
    private(set) var readabilityText = ""
    private(set) var unknownWordsText = ""
    private(set) var warningText = ""
    private(set) var weakPhonemes: [String] = []
    private(set) var isRecording = false
    private(set) var isPreparing = false
    private(set) var isSaving = false
    private(set) var elapsedMs = 0
    private(set) var ocrCapable = true
    private(set) var imageCapable = true

    // MARK: 依赖

    private let services: AppServices
    private let audio: AudioCoordinator
    private let session: SessionStore
    private let runtime: StoryRuntime
    private let recordingCache = RecordingCache()

    private var hasLoaded = false
    private var recordedAudio: RecordedAudio?
    private var originalTextZh = ""
    private var timerTask: Task<Void, Never>?
    private var lastFailure: BusyKind = .none

    static let levels = ["A1", "A2", "B1", "B2", "C1"]
    static let sentenceOptions = Array(3...12)
    private static let maxStoryChars = 2000

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
        self.runtime = StoryRuntime.shared
    }

    var isChild: Bool { session.isChild }
    var isBusy: Bool { busyKind != .none || isSaving }
    var canRewrite: Bool { !textZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy }

    // MARK: - 初次加载

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        level = session.user?.normalizedLevel ?? (session.isChild ? "A1" : "A2")
        maxSentences = session.isChild ? 5 : 8
        let preferred = session.prefs.storySentences
        if preferred >= 3 && preferred <= 12 {
            maxSentences = preferred
        }
        autoIllustrate = session.prefs.autoIllustrate
        let capabilities = await StoryCapabilities.load(services: services)
        ocrCapable = capabilities.ocr
        imageCapable = capabilities.image
    }

    // MARK: - 图片 → OCR

    func recognizePickedImage(_ image: UIImage) async {
        guard !isBusy else { return }
        guard ocrCapable else {
            inlineError = "当前服务器暂不支持拍照识别，请直接手动输入中文。"
            return
        }
        guard let data = ImageTranscoder.jpegData(
            from: image,
            maxDimension: ImageTranscoder.defaultMaxDimension,
            quality: ImageTranscoder.defaultQuality
        ) else {
            inlineError = "这张图片读不出来，换一张试试。"
            return
        }
        guard data.count <= ImageTranscoder.maxUploadBytes else {
            inlineError = "图片太大了，换一张或重新拍一张。"
            return
        }
        clearMessages()
        busyKind = .ocr
        busyText = isChild ? "正在看图片上的字…" : "正在识别书页文字…"
        lastFailure = .ocr
        defer {
            busyKind = .none
            busyText = ""
        }
        do {
            let result = try await services.media.ocr(
                imageData: data,
                filename: "page.jpg",
                mimeType: "image/jpeg"
            )
            let recognized = (result.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recognized.isEmpty else {
                let warnings = (result.warnings ?? []).joined(separator: "；")
                inlineError = warnings.isEmpty
                    ? "没认出文字，试试光线亮一点，或换一张照片。"
                    : "没认出文字：\(warnings)"
                return
            }
            appendRecognizedText(recognized)
            notice = "认出文字啦，已经写进上面的框里了"
        } catch {
            present(error: error)
        }
    }

    // MARK: - 录音 → ASR

    func startRecording() async {
        guard !isRecording, !isPreparing, !isBusy else { return }
        clearMessages()
        isPreparing = true
        defer { isPreparing = false }
        do {
            if audio.permission != .granted {
                let granted = await audio.requestPermission()
                guard granted else {
                    recordFailure(error: AudioError.permissionDenied)
                    return
                }
            }
            try await audio.startRecording()
            isRecording = true
            elapsedMs = 0
            startTimer()
        } catch {
            recordFailure(error: error)
        }
    }

    func stopRecordingAndRecognize() async {
        guard isRecording else { return }
        isRecording = false
        stopTimer()
        let recorded: RecordedAudio
        do {
            recorded = try await audio.stopRecording()
        } catch {
            recordFailure(error: error)
            return
        }
        recordedAudio = recorded
        await recognize(audioData: recorded.data)
    }

    func cancelRecording() async {
        isRecording = false
        stopTimer()
        elapsedMs = 0
        await audio.cancelRecording()
    }

    /// 失败重试（识别失败 → 用同一段录音重试；改写失败 → 重新改写）。
    func retryLastFailure() async {
        uiError = nil
        switch lastFailure {
        case .asr:
            guard let recordedAudio else { return }
            await recognize(audioData: recordedAudio.data)
        case .rewrite:
            await rewrite()
        case .ocr, .save, .none:
            break
        }
    }

    private func recognize(audioData: Data) async {
        clearMessages()
        busyKind = .asr
        busyText = isChild ? "正在听懂你的话…" : "正在识别中文录音…"
        lastFailure = .asr
        defer {
            busyKind = .none
            busyText = ""
        }
        do {
            let text = try await services.story.asr(audioData: audioData, language: "zh-CN")
            let recognized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recognized.isEmpty else {
                inlineError = "这次没听清，换个说法再讲一次吧。"
                return
            }
            appendRecognizedText(recognized)
            notice = "听到啦，已经写进上面的框里了"
        } catch {
            present(error: error)
        }
    }

    private func appendRecognizedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let current = textZh.trimmingCharacters(in: .whitespacesAndNewlines)
        textZh = current.isEmpty ? trimmed : current + "\n" + trimmed
        hasResult = false
    }

    // MARK: - 改写

    func rewrite() async {
        guard !isBusy else { return }
        let text = textZh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            inlineError = isChild ? "先讲讲你的故事吧 🙂" : "请先用中文讲讲你的故事（不能为空）"
            return
        }
        guard text.count <= Self.maxStoryChars else {
            inlineError = "故事太长了（\(text.count) 字），最多 \(Self.maxStoryChars) 字。"
            return
        }
        clearMessages()
        hasResult = false
        sentences = []
        busyKind = .rewrite
        busyText = isChild ? "正在把故事变成英文…大约几秒" : "正在把你的故事变成英文…"
        lastFailure = .rewrite
        do {
            let dto = try await services.story.rewrite(
                textZh: text,
                level: level,
                maxSentences: maxSentences,
                tense: "auto",
                useWeakPhonemes: useWeakPhonemes
            )
            apply(rewrite: dto)
            originalTextZh = text
            notice = isChild ? "写好英文故事啦 ⭐" : "英文故事已生成，可逐句修改后再保存"
        } catch {
            present(error: error)
        }
        busyKind = .none
        busyText = ""
    }

    private func apply(rewrite dto: StoryRewriteDTO) {
        hasResult = true
        let rawTitle = (dto.titleEn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        title = rawTitle.isEmpty ? "My Story" : rawTitle

        var items: [StorySentenceItem] = []
        for sentence in dto.sentences {
            let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            items.append(StorySentenceItem(index: items.count + 1, en: text))
        }
        if items.isEmpty {
            let fallbackText = dto.textEn ?? ""
            let pieces = StorySplit.sentences(from: fallbackText)
            for piece in pieces {
                items.append(StorySentenceItem(index: items.count + 1, en: piece))
            }
        }
        sentences = items

        if let readability = dto.readability {
            let count = readability.sentenceCount ?? items.count
            let average = readability.avgWords ?? 0
            let longest = readability.maxWords ?? 0
            readabilityText = "可读性：\(count) 句 · 平均 \(Self.formatTenths(average)) 词/句 · 最长 \(longest) 词"
            let unknown = readability.unknownWords ?? []
            unknownWordsText = unknown.isEmpty ? "" : "可能偏难的词：\(unknown.joined(separator: "、"))"
        } else {
            readabilityText = ""
            unknownWordsText = ""
        }

        let warnings = dto.warnings ?? []
        if warnings.contains("too_hard") {
            warningText = "这段可能有点难，要不要点「再简单一点」？"
        } else if warnings.contains("too_many_sentences") {
            warningText = "故事偏长（超过设定的句数），可以调高句子数，或删掉几句再保存。"
        } else if warnings.contains("tense_mismatch") {
            warningText = "时态可能和中文原意不一致（叙事一般用过去时），可以点「换一版」再试一次。"
        } else {
            warningText = ""
        }
        weakPhonemes = dto.weakPhonemesUsed ?? []
    }

    // MARK: - 编辑与保存

    func setLevel(_ value: String) {
        guard Self.levels.contains(value), value != level else { return }
        level = value
        if hasResult && !isBusy {
            Task { await rewrite() }
        }
    }

    func adjustLevel(by delta: Int) {
        let index = Self.levels.firstIndex(of: level) ?? 0
        let next = min(max(index + delta, 0), Self.levels.count - 1)
        setLevel(Self.levels[next])
    }

    func setMaxSentences(_ value: Int) {
        maxSentences = min(max(value, Self.sentenceOptions.first ?? 3), Self.sentenceOptions.last ?? 12)
    }

    func updateSentence(id: Int, text: String) {
        guard let index = sentences.firstIndex(where: { $0.id == id }) else { return }
        sentences[index].en = text
    }

    /// 保存并返回 `material_id`（nil = 失败，错误已写入 `uiError`/`inlineError`）。
    func save() async -> String? {
        guard hasResult, !isSaving else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            inlineError = "给故事起个标题吧"
            return nil
        }
        let parts = sentences
            .map { $0.en.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            inlineError = "英文故事不能为空，先点「换一版」试试。"
            return nil
        }

        clearMessages()
        isSaving = true
        busyKind = .save
        lastFailure = .save
        defer {
            isSaving = false
            busyKind = .none
            busyText = ""
        }
        do {
            let created = try await services.story.createMaterial(
                title: trimmedTitle,
                text: parts.joined(separator: "\n"),
                sourceZh: originalTextZh.isEmpty ? textZh : originalTextZh,
                level: level
            )
            if let recordedAudio = self.recordedAudio {
                _ = await recordingCache.save(recordedAudio.data, id: created.id)
            }
            runtime.markSaved()
            // auto_illustrate 打开且服务端有绘图能力时，后台补一张插画（失败静默，详情页可手动重画）。
            if autoIllustrate && imageCapable {
                let services = self.services
                let materialId = created.id
                Task {
                    _ = try? await services.story.illustrate(id: materialId, force: false)
                }
            }
            return created.id
        } catch {
            present(error: error)
            return nil
        }
    }

    // MARK: - 清理

    /// 保存成功后清空创作区（故事首页内嵌时用；独立页保存后会跳走）。
    func resetAfterSave() {
        textZh = ""
        originalTextZh = ""
        title = ""
        hasResult = false
        sentences = []
        readabilityText = ""
        unknownWordsText = ""
        warningText = ""
        weakPhonemes = []
        recordedAudio = nil
        clearMessages()
    }

    func clearInlineError() {
        inlineError = ""
    }

    func clearMessages() {
        inlineError = ""
        uiError = nil
        notice = ""
    }

    func stopAudio() async {
        await audio.stopAll()
        isRecording = false
        stopTimer()
    }

    // MARK: - 私有

    private func startTimer() {
        stopTimer()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.isRecording else { return }
                self.elapsedMs = min(self.elapsedMs + 200, 60_000)
                if self.elapsedMs >= 60_000 {
                    await self.stopRecordingAndRecognize()
                    return
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func recordFailure(error: Error) {
        isRecording = false
        stopTimer()
        present(error: error)
    }

    private func present(error: Error) {
        let message = ErrorMapper.message(for: error, isChild: session.isChild)
        if message.isSilent {
            return
        }
        uiError = message
    }

    private static func formatTenths(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 10).rounded() / 10
        let text = String(rounded)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

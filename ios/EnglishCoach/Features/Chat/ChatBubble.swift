import Foundation

/// 气泡角色（对应服务端 `role` 字段）。
enum ChatSpeaker: String, Sendable {
    case user
    case assistant
}

/// 单条气泡的播放状态（页面态，不写回 DTO）。
enum ChatPlaybackState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case failed
}

/// 对话气泡（页面态模型）。
///
/// 页面只渲染它，不直接读 `ChatMessageDTO`：DTO 的 `pron`/`correction` 是异步补下来的，
/// 这里用可变字段承接（成人展示分数/弱音/逐词，儿童只展示鼓励文案，由 View 决定）。
struct ChatBubble: Identifiable, Sendable, Equatable {
    /// 逐词分数（`pron.words`，最多 24 个）。
    struct Word: Identifiable, Sendable, Equatable {
        let id: Int
        let text: String
        let score: Double?
    }

    let id: String
    let speaker: ChatSpeaker
    /// 服务端消息 id（用于 pron 轮询匹配；乐观插入时为空）。
    var serverID = ""
    var text = ""
    var textZh = ""
    var hasCorrection = false
    var better = ""
    var explainZh = ""
    var unsafeFiltered = false
    var hasPron = false
    /// nil = 本轮评分未完成（不要落 0）。
    var pronScore: Double?
    var pronPending = false
    var pronTimedOut = false
    var weakLabels: [String] = []
    var words: [Word] = []
    /// `audioUrl` 形如 `/api/audio/cm_xxx`（用户录音）。
    var audioURL = ""
    /// 刚录完、还没从服务端取回时的本地录音（回放用）。
    var localAudio: Data?
    var playback: ChatPlaybackState = .idle

    var isUser: Bool { speaker == .user }
    var hasAudio: Bool { localAudio != nil || !audioURL.isEmpty }
}

/// DTO → 气泡，以及 `pron` / `correction` 的增量合并。
enum ChatBubbleFactory {
    /// 乐观插入的用户语音气泡：只保存本地录音与识别文本，界面不展示文字（纯语音）。
    static func makeLocalUser(text: String, audio: Data) -> ChatBubble {
        ChatBubble(
            id: "local-\(UUID().uuidString)",
            speaker: .user,
            serverID: "",
            text: text,
            localAudio: audio
        )
    }

    static func makeAssistant(text: String, textZh: String, serverID: String, unsafeFiltered: Bool) -> ChatBubble {
        ChatBubble(
            id: serverID.isEmpty ? "assistant-\(UUID().uuidString)" : serverID,
            speaker: .assistant,
            serverID: serverID,
            text: text,
            textZh: textZh,
            unsafeFiltered: unsafeFiltered
        )
    }

    static func from(dto: ChatMessageDTO, isChild: Bool) -> ChatBubble {
        // 服务端在“创建会话”响应里可能不给消息 id（见 `ChatMessageDTO.id` 注释）；
        // 没有服务端 id 时用本地临时 id 渲染，`serverID` 留空表示无法参与 pron 轮询匹配。
        let serverID = dto.id ?? ""
        let text = dto.text ?? ""
        var textZh = dto.textZh ?? ""
        // 开场白服务端常不给 text_zh（随机变体开场白 + opening-zh 只覆盖少数固定句），
        // 用内置场景的英文原文兜底翻译，保证第一句也有中文。
        // 能按原文命中内置开场白时，优先用本地译文（服务端对“变体开场白”可能给的是
        // 固定开场白的译文，会张冠李戴）；未命中才保留服务端 text_zh。
        if dto.role == ChatSpeaker.assistant.rawValue,
           let translated = ChatOpeningTranslations.zh(for: text) {
            textZh = translated
        }
        var bubble = ChatBubble(
            id: serverID.isEmpty ? "message-\(UUID().uuidString)" : serverID,
            speaker: dto.role == ChatSpeaker.user.rawValue ? .user : .assistant,
            serverID: serverID,
            text: text,
            textZh: textZh,
            unsafeFiltered: dto.flag == "unsafe_filtered",
            audioURL: dto.audioUrl ?? ""
        )
        applyCorrection(dto.correction, to: &bubble)
        applyPron(dto.pron, to: &bubble, isChild: isChild)
        return bubble
    }

    /// 「更自然」提示：只有 `hasError == true` 才展示（服务端会带 `type: none` 的空壳）。
    static func applyCorrection(_ correction: ChatCorrectionDTO?, to bubble: inout ChatBubble) {
        guard let correction, correction.hasError == true else {
            bubble.hasCorrection = false
            bubble.better = ""
            bubble.explainZh = ""
            return
        }
        bubble.hasCorrection = true
        bubble.better = (correction.better ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        bubble.explainZh = (correction.explainZh ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 发音评分：只在 `GET .../messages` 里出现；儿童永不展示 IPA/分数/逐词。
    static func applyPron(_ pron: ChatPronDTO?, to bubble: inout ChatBubble, isChild: Bool) {
        guard let pron else {
            bubble.hasPron = false
            return
        }
        bubble.hasPron = true
        bubble.pronPending = false
        bubble.pronTimedOut = false
        bubble.pronScore = pron.pron
        guard !isChild else {
            bubble.weakLabels = []
            bubble.words = []
            return
        }
        var labels: [String] = []
        for item in (pron.weakPhonemes ?? []).prefix(3) {
            let label = (item.label ?? "").isEmpty ? (item.ipa ?? "") : (item.label ?? "")
            if !label.isEmpty {
                labels.append(label)
            }
        }
        bubble.weakLabels = labels
        var words: [ChatBubble.Word] = []
        for (index, item) in (pron.words ?? []).prefix(24).enumerated() {
            words.append(ChatBubble.Word(id: index, text: item.word ?? "", score: item.score))
        }
        bubble.words = words
    }
}

/// 对话页的本地偏好（HOS 场景页的「自动朗读 / 语速」开关）。
///
/// 走 `UserDefaults` 而不是 SwiftUI `@AppStorage`：场景页写入、会话页读取，
/// 不污染 Core，也不需要跨页面传参。
enum ChatSettings {
    private static let autoReadKey = "chat.autoRead"
    private static let rateKey = "chat.rate"

    /// 默认开：回复后自动朗读（与 HOS 一致）。
    static func autoRead(defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: autoReadKey) as? Bool) ?? true
    }

    static func setAutoRead(_ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: autoReadKey)
    }

    /// `slow` / `normal`（与 `TTSRate` 的 rawValue 对齐）。
    static func rateText(defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: rateKey) ?? ""
        return raw == TTSRate.slow.rawValue ? TTSRate.slow.rawValue : TTSRate.normal.rawValue
    }

    static func setRateText(_ raw: String, defaults: UserDefaults = .standard) {
        defaults.set(raw == TTSRate.slow.rawValue ? TTSRate.slow.rawValue : TTSRate.normal.rawValue, forKey: rateKey)
    }

    /// 用户是否在对话页手动切过语速（决定「本地开关 > 账号偏好」的优先级）。
    static func hasRateOverride(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: rateKey) != nil
    }

    static func rate(defaults: UserDefaults = .standard) -> TTSRate {
        rateText(defaults: defaults) == TTSRate.slow.rawValue ? .slow : .normal
    }
}

import Foundation

// MARK: - 阶段 / 状态

/// 连读阶段：setup → running → summary（「再读一遍」回 running，「再读一段」回 setup）。
enum FlowPhase: Equatable {
    case setup
    case running
    case summary
}

/// 连读来源（HOS 还有「我的书页 / 拍照识别」，iOS 归故事域，连读只保留语料与自定义输入）。
enum FlowSource: Int, CaseIterable, Identifiable, Equatable {
    case corpus
    case custom

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .corpus: return "从语料选"
        case .custom: return "自己输入"
        }
    }
}

/// 单句状态：未读 / 上传中 / 待评分 / 评分中 / 完成 / 失败。
enum FlowItemStatus: String, Equatable, Sendable {
    case unsent
    case uploading
    case pending
    case scoring
    case done
    case failed
}

// MARK: - 单句结果（`/attempts/status` → 页面模型）

struct FlowAttemptResult: Hashable, Sendable {
    var pron: Double?
    var accuracy: Double?
    var fluency: Double?
    var completeness: Double?
    var prosody: Double?
    var recognizedText: String
    var noSpeech: Bool
    var feedbackSummary: String
    var feedbackPraise: String
    var feedbackClosing: String
    var pointTitles: [String]
    var pointHows: [String]
    var wordTexts: [String]
    var wordScores: [Double?]
    var issueTexts: [String]
}

/// 连读里的一句（服务端 attempt 的可视化镜像）。
struct FlowItem: Identifiable, Hashable, Sendable {
    let id: Int
    var index: Int
    var text: String
    var sentenceId: String
    var source: String
    var status: FlowItemStatus
    var attemptId: String
    var errorText: String
    var result: FlowAttemptResult?

    init(index: Int, text: String, sentenceId: String, source: String) {
        self.id = index
        self.index = index
        self.text = text
        self.sentenceId = sentenceId
        self.source = source
        self.status = .unsent
        self.attemptId = ""
        self.errorText = ""
        self.result = nil
    }

    var hasResult: Bool { result != nil }
    var scorePron: Double? { result?.pron }

    /// 「重录这句」：清掉上一轮 attempt 的展示数据。
    mutating func resetForRedo() {
        attemptId = ""
        status = .unsent
        errorText = ""
        result = nil
    }
}

/// 一批句子（「再读一遍」复用，不重新抽句/切句）。
struct FlowRunSentence: Hashable, Sendable {
    let text: String
    let sentenceId: String
    let source: String
}

/// 汇总页「最需要再练的几句」。
struct FlowWorstItem: Identifiable, Hashable, Sendable {
    var id: Int { index }
    let index: Int
    let score: Double?
    let text: String
}

/// 汇总页鼓励语（本地确定性挑选；中英双语，成长型措辞）。
struct FlowEncouragement: Hashable, Sendable {
    var tier: String
    var zh: String
    var en: String
    var praise: String
}

/// 汇总页渲染快照（一次构建，页面不重复计算）。
struct FlowSummaryData: Hashable, Sendable {
    var round: Int = 1
    var total: Int = 0
    var doneCount: Int = 0
    var failedCount: Int = 0
    var avgScore: Double?
    var worst: [FlowWorstItem] = []
    var encouragement: FlowEncouragement = FlowEncouragement(tier: "C", zh: "", en: "", praise: "")
    /// 参与 `GET /diagnosis?scope=batch` 的 attempt id（≤ 20）。
    var attemptIds: [String] = []
    var items: [FlowItem] = []
}

/// 汇总页诊断标签（文案已按儿童/成人处理，颜色由 View 映射）。
struct FlowDiagnosisTag: Identifiable, Hashable, Sendable {
    var id: Int { index }
    let index: Int
    let label: String
    /// weak | watch | ok
    let status: String
}

// MARK: - 连读运行态注册表

/// `FlowView`（Tab 根页）与 `FlowSummaryView`（路由 `.flowSummary`）共享同一份运行态。
///
/// 契约 §3.15.1 的 `FlowSummaryView` 没有 Store 构造参数，因此汇总页通过本注册表拿到
/// FlowView 创建的 `FlowStore`；直达汇总页（没有进行中的连读）时显示空态。
@MainActor
enum FlowRunRegistry {
    static weak var store: FlowStore?
}

// MARK: - 文本工具

/// 纯文本切句（规格 §5.2：按 `. ! ? 。！？` 切，保留句末标点，丢弃没有字母的碎片）。
enum FlowText {
    static func splitSentences(_ input: String) -> [String] {
        var raw: [String] = []
        var current = ""
        for character in input {
            current.append(character)
            if character == "." || character == "!" || character == "?" || character == "。" || character == "！" || character == "？" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    raw.append(trimmed)
                }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            raw.append(tail)
        }
        return raw.filter { letterCount($0) > 0 }
    }

    /// 英文字母个数（判断「有没有听到内容」用；数字/标点不算）。
    static func letterCount(_ text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if character.isLetter, character.isASCII {
                count += 1
            }
        }
    }
}

// MARK: - 汇总页鼓励语（本地 6 档 × 5 条，确定性挑选）

/// 成长型措辞：绝不含否定词；同一批结果永远选到同一条（hash 种子 = attempt ids + tier + total）。
enum FlowEncouragementBuilder {
    static func make(
        items: [FlowItem],
        total: Int,
        doneCount: Int,
        avgScore: Double?,
        attemptIds: [String]
    ) -> FlowEncouragement {
        var minCompleteness: Double?
        for item in items where item.status == .done {
            guard let value = item.result?.completeness else { continue }
            if let current = minCompleteness {
                minCompleteness = min(current, value)
            } else {
                minCompleteness = value
            }
        }

        let tier: String
        if doneCount == 0 {
            tier = "no_speech"
        } else if let minCompleteness, minCompleteness < 60 {
            tier = "incomplete"
        } else if let avgScore, avgScore >= 85 {
            tier = "S"
        } else if let avgScore, avgScore >= 70 {
            tier = "A"
        } else if let avgScore, avgScore >= 55 {
            tier = "B"
        } else {
            tier = "C"
        }

        let pool = pool(for: tier)
        var seed = attemptIds.joined(separator: "|") + ":" + tier + ":" + String(total)
        seed += ":" + String(doneCount)
        let index = hash(seed) % max(pool.count, 1)
        let variant = pool.isEmpty ? (zh: "", en: "") : pool[index]
        return FlowEncouragement(
            tier: tier,
            zh: variant.zh,
            en: variant.en,
            praise: bestWordPraise(items: items)
        )
    }

    private static func bestWordPraise(items: [FlowItem]) -> String {
        var bestWord = ""
        var bestScore = -1.0
        for item in items where item.status == .done {
            guard let result = item.result else { continue }
            for (index, score) in result.wordScores.enumerated() where index < result.wordTexts.count {
                guard let score, score >= 85, score > bestScore else { continue }
                bestScore = score
                bestWord = result.wordTexts[index]
            }
        }
        guard !bestWord.isEmpty else { return "" }
        return "「\(bestWord)」这个词读得特别清楚。"
    }

    private static func hash(_ input: String) -> Int {
        var value = 0
        for scalar in input.unicodeScalars {
            value = (value * 31 + Int(scalar.value)) % 1_000_000_007
        }
        return max(value, 0)
    }

    private static func pool(for tier: String) -> [(zh: String, en: String)] {
        switch tier {
        case "S": return poolS
        case "A": return poolA
        case "B": return poolB
        case "C": return poolC
        case "incomplete": return poolIncomplete
        default: return poolNoSpeech
        }
    }

    private static let poolS: [(zh: String, en: String)] = [
        ("太棒了！这次特别清楚！", "Great job! That was so clear!"),
        ("哇，这次读得特别棒！", "Wow, you did great!"),
        ("进步好大，继续保持！", "Big progress! Keep going!"),
        ("这次的声音又清楚又好听！", "That sounded clear and lovely!"),
        ("太厉害了，一口气读下来了！", "Amazing! You read the whole thing!")
    ]

    private static let poolA: [(zh: String, en: String)] = [
        ("读得很好！继续这样就好。", "Nice reading! Keep it up."),
        ("很稳！保持这个节奏。", "Very steady! Keep this rhythm."),
        ("这次比上次更顺了。", "Smoother than last time!"),
        ("很好，句子都读完整了。", "Good job finishing every sentence."),
        ("听起来很棒，再来一次会更好。", "Sounds great! One more time will be even better.")
    ]

    private static let poolB: [(zh: String, en: String)] = [
        ("很认真！再读一遍会更顺。", "Good try! Reading again will be smoother."),
        ("看到你在努力，继续保持。", "I can see your effort. Keep going!"),
        ("大部分都读到了，真棒！", "You got most of it. Nice work!"),
        ("慢一点会更清楚，我们再试试。", "Slow down a little and try again."),
        ("你的声音很响亮，很好！", "Your voice was nice and loud!")
    ]

    private static let poolC: [(zh: String, en: String)] = [
        ("谢谢你勇敢地读出来。我们慢慢来。", "Thank you for reading! Let us take our time."),
        ("敢开口就很了不起，我们一起再试试。", "Speaking up is brave. Let us try together."),
        ("今天已经在进步的路上了。", "You are on the way. Keep going!"),
        ("我听到你的声音了，我们再练一次。", "I heard your voice! Let us practice again."),
        ("一点点来，你已经在变好了。", "Little by little, you are getting better.")
    ]

    private static let poolNoSpeech: [(zh: String, en: String)] = [
        ("这次好像没听到你的声音，我们再来一次好吗？", "Let us try again! I will listen."),
        ("麦克风可能没收到，靠近一点再说一次吧。", "Come a little closer and say it again."),
        ("没关系，我们深呼吸一下再来一次。", "No worries. Take a breath and try again."),
        ("准备好了吗？我在这儿听着呢。", "Ready? I am listening."),
        ("我们慢慢来，先大声说一句试试。", "Take your time. Say one sentence loudly.")
    ]

    private static let poolIncomplete: [(zh: String, en: String)] = [
        ("有几句话没读完，没关系，我们试试一口气读完。", "You can do it! Let us finish the whole page."),
        ("读到一半也很好，下次把它读完吧。", "Halfway is good too. Let us finish next time."),
        ("慢慢来，把每一句都读完就更棒了。", "Take your time and finish each sentence."),
        ("我们已经读了一大半了，再读一点点就好。", "We are almost done. Just a little more."),
        ("一句一句来，读完最后一句我们就成功啦。", "One sentence at a time. Let us finish the last one!")
    ]
}

// MARK: - DTO → 页面模型

enum FlowResultMapper {
    static func status(from raw: String) -> FlowItemStatus {
        switch raw {
        case "pending": return .pending
        case "scoring": return .scoring
        case "done": return .done
        case "failed": return .failed
        default: return .pending
        }
    }

    /// `AsyncResultDTO` → 单句结果。连读详情不含音素明细与语调图（`async` 不返回），
    /// 逐词按分数升序取前 10 个（成人）；儿童不展示分数，仅有鼓励语。
    static func make(from dto: AsyncResultDTO, isChild: Bool) -> FlowAttemptResult {
        let recognized = (dto.recognizedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let words = dto.words ?? []
        var sorted = words.enumerated().map { index, word in (index: index, word: word) }
        sorted.sort { lhs, rhs in
            let left = lhs.word.score ?? 101
            let right = rhs.word.score ?? 101
            return left < right
        }
        var wordTexts: [String] = []
        var wordScores: [Double?] = []
        if !isChild {
            for entry in sorted.prefix(10) {
                wordTexts.append(entry.word.word)
                wordScores.append(entry.word.score)
            }
        }

        var issueTexts: [String] = []
        if !isChild {
            for issue in (dto.issues ?? []).prefix(2) {
                issueTexts.append(issueText(issue))
            }
        }

        var titles: [String] = []
        var hows: [String] = []
        if let feedback = dto.feedback, !isChild {
            for point in (feedback.points ?? []).prefix(2) {
                titles.append(point.title ?? "")
                hows.append(point.how ?? "")
            }
        }

        return FlowAttemptResult(
            pron: dto.scores?.pron,
            accuracy: dto.scores?.accuracy,
            fluency: dto.scores?.fluency,
            completeness: dto.scores?.completeness,
            prosody: dto.scores?.prosody,
            recognizedText: recognized,
            noSpeech: FlowText.letterCount(recognized) <= 1,
            feedbackSummary: dto.feedback?.summary ?? "",
            feedbackPraise: dto.feedback?.praise ?? "",
            feedbackClosing: dto.feedback?.closing ?? "",
            pointTitles: titles,
            pointHows: hows,
            wordTexts: wordTexts,
            wordScores: wordScores,
            issueTexts: issueTexts
        )
    }

    private static func issueText(_ issue: IssueDTO) -> String {
        let word = issue.word ?? ""
        let expected = issue.expected ?? ""
        let actual = issue.actual ?? ""
        if word.isEmpty {
            return issue.type ?? "发音小问题"
        }
        if !expected.isEmpty, !actual.isEmpty {
            return "\(word)：\(expected) 发成了 \(actual)"
        }
        return word + (issue.type.map { "：\($0)" } ?? " 发音注意一下")
    }
}

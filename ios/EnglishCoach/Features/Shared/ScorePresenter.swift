import SwiftUI

/// 分数展示规则（成人 / 儿童两套）。
///
/// - 颜色与星级唯一来源是 `Tokens.Score`（Core），本枚举只负责**文案与展示判定**，
///   避免 DesignSystem 反向依赖 Features；
/// - 成人：0–100 数字 + 四级语义色（<60 标红）；
/// - 儿童：不显示数字、不用红色，只有 1–3 星 + 鼓励语（`ChildTier`）。
enum ScorePresenter {

    // MARK: - 成人等级

    enum Level: String, CaseIterable, Sendable {
        case excellent
        case good
        case fair
        case weak
    }

    // MARK: - 儿童鼓励档

    enum ChildTier: String, CaseIterable, Sendable {
        /// 3 星：读得很棒。
        case celebrate
        /// 2 星：读得不错，还能更好。
        case encourage
        /// 1 星：再来一次（不出现「失败/低分」字样）。
        case retry
    }

    // MARK: - 判定

    /// 成人等级；无分数返回 nil。
    static func level(for score: Double?) -> Level? {
        guard let score, score.isFinite else { return nil }
        if score >= 85 { return .excellent }
        if score >= 70 { return .good }
        if score >= 60 { return .fair }
        return .weak
    }

    /// 儿童星级对应的鼓励档；无分数一律 `retry`（附「等下再看星星」文案，不用否定词）。
    static func childTier(for score: Double?) -> ChildTier {
        guard let score, score.isFinite else { return .retry }
        if score >= 85 { return .celebrate }
        if score >= 60 { return .encourage }
        return .retry
    }

    /// 星级（1...3）：85+ 三星、70+ 两星、其余一星。
    static func stars(for score: Double?) -> Int {
        Tokens.Score.stars(for: score)
    }

    /// 是否展示数字：成人有分即展示；儿童只在 ≥60 时展示（HOS `EcScore.showNumber` 同规则），
    /// 组件层仍会按 `caps.showsNumericScore` 再兜底隐藏。
    static func showsNumber(for score: Double?, isChild: Bool) -> Bool {
        guard let score, score.isFinite else { return false }
        return isChild ? score >= 60 : true
    }

    /// 数字文本：`78` / `—`（不可得时）。
    static func numberText(for score: Double?) -> String {
        guard let score, score.isFinite else { return "—" }
        return String(Int(score.rounded()))
    }

    // MARK: - 颜色（委托 Tokens）

    /// 分数色：成人四级、儿童鼓励色（<60 不红）。
    static func color(for score: Double?, isChild: Bool) -> Color {
        Tokens.Score.color(for: score, isChild: isChild)
    }

    /// 分数浅底（徽标/标签）。
    static func softBackground(for score: Double?, isChild: Bool) -> Color {
        Tokens.Score.softBackground(for: score, isChild: isChild)
    }

    // MARK: - 文案

    /// 成人等级标题（用于结果卡角标）。
    static func levelTitle(for score: Double?) -> String {
        switch level(for: score) {
        case .excellent: return "很棒"
        case .good: return "不错"
        case .fair: return "基本达标"
        case .weak: return "需加强"
        case nil: return "暂无评分"
        }
    }

    /// 儿童档位标题（短，用于徽标/星级旁）。
    static func childTierTitle(for score: Double?) -> String {
        switch childTier(for: score) {
        case .celebrate: return "太棒啦"
        case .encourage: return "读得真好"
        case .retry: return "再试一次吧"
        }
    }

    /// 一句话鼓励。儿童不出现否定词/术语；成人可指出下一步。
    static func encouragement(for score: Double?, isChild: Bool) -> String {
        guard let score, score.isFinite else {
            return isChild ? "录好啦，等下再看星星" : "本次没有拿到分数，可稍后重试评测"
        }
        if isChild {
            if score >= 90 { return "太棒啦，读得非常清楚 🌟" }
            if score >= 80 { return "读得真好，继续加油 ⭐" }
            if score >= 70 { return "不错哦，再读一遍会更顺 💪" }
            if score >= 60 { return "有进步，再试一次吧 🌱" }
            return "再来一次会更好 💪"
        }
        if score >= 90 { return "很稳，几乎和示范一样清楚" }
        if score >= 80 { return "整体很好，个别词再注意一下" }
        if score >= 70 { return "不错，节奏和重音还能更自然" }
        if score >= 60 { return "基本能听懂，慢一点会更清楚" }
        return "这句话有点难，放慢速度再读一遍，注意加粗的词"
    }

    /// 子项名称（成人用术语；儿童用可读说法）。
    static func subScoreLabel(_ key: String, isChild: Bool = false) -> String {
        let normalized = key.lowercased()
        if isChild {
            switch normalized {
            case "accuracy": return "说得准"
            case "fluency": return "说得顺"
            case "completeness": return "没漏词"
            case "prosody": return "节奏"
            default: return key
            }
        }
        switch normalized {
        case "accuracy": return "准确度"
        case "fluency": return "流利度"
        case "completeness": return "完整度"
        case "prosody": return "语调"
        default: return key
        }
    }

    /// 星级符号串（日志/分享/家长端文本用；UI 请用 `StarRow`）。
    static func starSymbols(for score: Double?) -> String {
        String(repeating: "⭐", count: max(1, stars(for: score)))
    }

    /// 结果页主标题（成人/儿童两套语气）。
    static func resultTitle(for score: Double?, isChild: Bool) -> String {
        if isChild {
            switch childTier(for: score) {
            case .celebrate: return "太棒啦！"
            case .encourage: return "读得真好！"
            case .retry: return "再来一次吧"
            }
        }
        switch level(for: score) {
        case .excellent: return "读得非常清楚"
        case .good: return "读得不错"
        case .fair: return "基本能听懂"
        case .weak: return "还要再练一练"
        case nil: return "暂无评分"
        }
    }
}

import Foundation

/// 统一格式化（纯展示、无副作用，不依赖 DTO / 网络）。
///
/// 约定：所有返回值都是**用户可见简体中文**；数字用等宽字体由使用处追加 `.monospacedDigit()`。
/// 时间计算走 `Calendar`（不用 `DateFormatter`，避免 Swift 6 严格并发下的非 Sendable 静态属性）。
enum EcFormat {

    // MARK: - 时长（mm:ss）

    /// 秒 → `mm:ss`；超过 1 小时 → `h:mm:ss`。
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):\(pad2(minutes)):\(pad2(secs))"
        }
        return "\(pad2(minutes)):\(pad2(secs))"
    }

    /// 毫秒 → `mm:ss`（录音时长、评测耗时）。
    static func clock(milliseconds: Int) -> String {
        clock(Double(milliseconds) / 1000)
    }

    /// 秒 → 「42 分钟」/「1 小时 5 分钟」/「不到 1 分钟」。
    static func durationText(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "不到 1 分钟" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(rest) 分钟"
    }

    /// 秒 → 分钟数文案（家长面板、今日用量）。`durationText` 的语义别名。
    static func minutesText(_ seconds: Double) -> String {
        durationText(seconds)
    }

    // MARK: - 相对时间

    /// 相对时间：「刚刚 / N 分钟前 / 今天 19:20 / 昨天 08:05 / N 天前 / 11月4日 / 2024年11月4日」。
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 {
            return "\(max(1, Int(interval / 60))) 分钟前"
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 \(timeText(date))"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(timeText(date))"
        }
        let days = Int(interval / 86400)
        if days < 7 { return "\(max(2, days)) 天前" }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return monthDayText(date)
        }
        return yearMonthDayText(date)
    }

    /// `19:20`。
    static func timeText(_ date: Date) -> String {
        let components = dateComponents(date, units: [.hour, .minute])
        return "\(pad2(components.hour ?? 0)):\(pad2(components.minute ?? 0))"
    }

    /// `11月4日`。
    static func monthDayText(_ date: Date) -> String {
        let components = dateComponents(date, units: [.month, .day])
        return "\(components.month ?? 1)月\(components.day ?? 1)日"
    }

    /// `2024年11月4日`。
    static func yearMonthDayText(_ date: Date) -> String {
        let components = dateComponents(date, units: [.year, .month, .day])
        return "\(components.year ?? 0)年\(components.month ?? 1)月\(components.day ?? 1)日"
    }

    /// `11月4日 19:20`（家长面板「最近练习」）。
    static func dateTimeText(_ date: Date) -> String {
        "\(monthDayText(date)) \(timeText(date))"
    }

    // MARK: - 百分比

    /// 0...100 → `78%`（clamp 到 0...100；`fractionDigits` 0...2）。
    static func percent(_ value: Double, fractionDigits: Int = 0) -> String {
        guard value.isFinite else { return "—" }
        let clamped = min(max(value, 0), 100)
        return "\(numberText(clamped, fractionDigits: fractionDigits))%"
    }

    /// 0...1 → `67%`。
    static func ratioPercent(_ ratio: Double, fractionDigits: Int = 0) -> String {
        guard ratio.isFinite else { return "—" }
        return percent(ratio * 100, fractionDigits: fractionDigits)
    }

    // MARK: - 计数与分数

    /// `12 句` / `3 个`。
    static func countText(_ count: Int, unit: String) -> String {
        "\(max(0, count)) \(unit)"
    }

    /// 分数文本：`78` / `—`。
    static func scoreText(_ score: Double?) -> String {
        guard let score, score.isFinite else { return "—" }
        return String(Int(score.rounded()))
    }

    // MARK: - 私有

    private static func pad2(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func dateComponents(_ date: Date, units: Set<Calendar.Component>) -> DateComponents {
        Calendar.current.dateComponents(units, from: date)
    }

    private static func numberText(_ value: Double, fractionDigits: Int) -> String {
        let digits = min(max(fractionDigits, 0), 2)
        if digits == 0 { return String(Int(value.rounded())) }
        let factor = pow(10.0, Double(digits))
        let rounded = (value * factor).rounded() / factor
        var text = String(rounded)
        if text.hasSuffix(".0") {
            text.removeLast(2)
        }
        return text
    }
}

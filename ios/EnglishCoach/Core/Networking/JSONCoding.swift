import Foundation

/// JSON 编解码的唯一入口。
///
/// 服务端契约全部是 `snake_case` 字段（`max_sentences`、`sentence_id`、`tts_voice`…），
/// 而 Swift 侧属性是 `lowerCamelCase`。所有请求体与响应体都必须经过这里，
/// 否则会出现「本地能编、服务端 422」的隐性错误。
///
/// 规则：
/// - 编码：`keyEncodingStrategy = .convertToSnakeCase`（属性 `maxSentences` → `max_sentences`）。
///   **例外**：个别字段需要完全自定义键名时，用显式 `CodingKeys`（显式键名优先于策略）。
/// - 解码：`keyDecodingStrategy = .convertFromSnakeCase`（`snake_case` → `lowerCamelCase`）。
/// - 日期：服务端是 ISO8601 字符串（可能带/不带毫秒），解析失败按 `nil` 处理（DTO 里多为 `String?`，
///   需要 `Date` 的地方用 `ECJSON.date(from:)` 宽松解析）。
enum ECJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// 编码请求体；失败时抛 `APIError.decoding(path:)`（调用方给 path，便于定位）。
    static func encode<T: Encodable>(_ value: T, path: String) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw APIError.decoding(path: path)
        }
    }

    /// 宽松解析服务端时间字符串（`2026-11-04T10:32:48.123Z` 或 `2026-11-04T10:32:48Z`）。
    static func date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// 相对时间文案（"刚刚 / 3 分钟前 / 2 小时前 / 昨天 / 11-02"），用于历史列表。
    static func relativeText(from raw: String?) -> String {
        guard let date = date(from: raw) else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) 小时前" }
        if seconds < 172_800 { return "昨天" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }
}

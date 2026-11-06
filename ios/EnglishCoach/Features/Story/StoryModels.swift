import Foundation
import Observation

// MARK: - 页面模型（契约 §3.6：StoryCardItem / StorySentenceItem / StoryTextPair 由 B3 定义）

/// 故事库卡片（列表页展示模型，不直接暴露 DTO 给 View）。
struct StoryCardItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let level: String
    let sentenceCount: Int
    let authorName: String
    let authorId: String
    let hasImage: Bool
    let hasSourceZh: Bool
    /// 服务端原始时间（ISO8601 字符串，仅用于排序/调试，展示用 `dateLabel`）。
    let createdAtRaw: String
    /// 本地日期键 `yyyy-MM-dd`；空串表示时间不可解析。
    let dateKey: String
    /// 「今天 / 昨天 / 更早」。
    let dateLabel: String
    /// 图片缓存版本（由 `updatedAt` 派生的稳定整数）。
    let imageVersion: Int

    init(material: StoryMaterialDTO, now: Date = Date()) {
        let rawTitle = (material.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = material.id
        self.title = rawTitle.isEmpty ? "未命名故事" : rawTitle
        self.level = (material.level ?? "").uppercased()
        self.sentenceCount = max(0, material.sentenceCount ?? 0)
        self.authorName = material.createdByName ?? ""
        self.authorId = material.createdBy ?? ""
        self.hasImage = material.hasImage == true
        self.hasSourceZh = material.hasSourceZh == true
        self.createdAtRaw = material.createdAt ?? ""
        self.dateKey = StoryDates.key(fromISO: material.createdAt)
        self.dateLabel = StoryDates.label(for: self.dateKey, now: now)
        self.imageVersion = StoryDates.versionToken(from: material.updatedAt ?? material.createdAt)
    }
}

/// 故事的一句话（讲述预览 / 详情逐句朗读用）。
struct StorySentenceItem: Identifiable, Hashable, Sendable {
    let id: Int
    var en: String
    var zh: String?

    init(index: Int, en: String, zh: String? = nil) {
        self.id = index
        self.en = en
        self.zh = zh
    }
}

/// 中英对照句对（复述页/详情页的只读展示）。
struct StoryTextPair: Identifiable, Hashable, Sendable {
    let id: Int
    let en: String
    let zh: String?

    init(index: Int, en: String, zh: String? = nil) {
        self.id = index
        self.en = en
        self.zh = zh
    }
}

/// 按日期分组的故事列表（今天/昨天/更早）。
struct StoryGroup: Identifiable, Hashable, Sendable {
    var id: String { label }
    let label: String
    let items: [StoryCardItem]
}

// MARK: - 日期与切句

/// 故事域本地日期工具（设备时区；只负责展示，不做服务端时区换算）。
enum StoryDates {
    static func key(fromISO iso: String?) -> String {
        guard let date = ECJSON.date(from: iso) else { return "" }
        return key(from: date)
    }

    static func key(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(pad2(components.month ?? 1))-\(pad2(components.day ?? 1))"
    }

    static func label(for key: String, now: Date = Date()) -> String {
        guard !key.isEmpty else { return "更早" }
        let todayKey = self.key(from: now)
        if key == todayKey { return "今天" }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        if key == self.key(from: yesterday) { return "昨天" }
        return "更早"
    }

    /// `2026-11-04` → `11月4日`。
    static func displayText(for key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              month >= 1, month <= 12, day >= 1, day <= 31
        else {
            return ""
        }
        return "\(month)月\(day)日"
    }

    /// 卡片副标题：今天/昨天显示相对日期，更早显示 `11月4日`。
    static func subtitle(for card: StoryCardItem) -> String {
        if card.dateLabel == "更早" {
            let text = displayText(for: card.dateKey)
            return text.isEmpty ? "更早" : text
        }
        return card.dateLabel
    }

    /// 由时间字符串生成稳定的整数版本号（跨启动一致，供 `ImageCache` 键使用）。
    static func versionToken(from raw: String?) -> Int {
        guard let raw, !raw.isEmpty else { return 0 }
        var hash = 5381
        for byte in raw.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        // 用位掩码保证非负，避免 abs(Int.min) 溢出。
        return hash & Int.max
    }

    /// 从「今天/昨天」往前数连续有故事的天数（HOS `computeStreak` 同规则）。
    static func streakDays(from cards: [StoryCardItem], now: Date = Date()) -> Int {
        let keys = Set(cards.map(\.dateKey).filter { !$0.isEmpty })
        guard !keys.isEmpty else { return 0 }
        let todayKey = key(from: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayKey = key(from: yesterday)
        var cursor: Date
        if keys.contains(todayKey) {
            cursor = now
        } else if keys.contains(yesterdayKey) {
            cursor = yesterday
        } else {
            return 0
        }
        var count = 0
        while keys.contains(key(from: cursor)) {
            count += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private static func pad2(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// 英文正文 → 句子数组：先按换行，只有一句时再按句号拆（HOS `splitSentences` 同规则）。
enum StorySplit {
    static func sentences(from text: String) -> [String] {
        let lines = text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count <= 1 else { return lines }
        let single = lines.first ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !single.isEmpty else { return [] }

        var result: [String] = []
        var buffer = ""
        for character in single {
            buffer.append(character)
            if character == "." || character == "!" || character == "?" {
                let piece = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty {
                    result.append(piece)
                }
                buffer = ""
            }
        }
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty {
            result.append(rest)
        }
        return result.isEmpty ? [single] : result
    }
}

// MARK: - 跨页内存态

/// 本次 App 会话内的跨页共享状态。
///
/// 线上没有「故事原始录音留存 / 复述历史」接口（2026-11-03 实测），这里只做两件事：
/// - `savedTick`：新建故事后通知故事集刷新；
/// - `retells`：本次会话里的复述结果（详情页展示，关 App 即清空）。
@MainActor
@Observable
final class StoryRuntime {
    static let shared = StoryRuntime()

    /// 保存成功一次 +1（故事集根页监听它刷新）。
    private(set) var savedTick = 0
    /// materialId → 本次会话的复述记录（最多保留 5 条）。
    private(set) var retellRecords: [String: [StoryRetellRecordDTO]] = [:]

    private init() {}

    func markSaved() {
        savedTick += 1
    }

    func addRetell(materialId: String, record: StoryRetellRecordDTO) {
        guard !materialId.isEmpty else { return }
        var list = retellRecords[materialId] ?? []
        list.insert(record, at: 0)
        if list.count > 5 {
            list.removeLast(list.count - 5)
        }
        retellRecords[materialId] = list
    }

    func retells(for materialId: String) -> [StoryRetellRecordDTO] {
        retellRecords[materialId] ?? []
    }
}

// MARK: - 能力开关

/// 故事/书页能力快照（来源 `GET /health` 的 `voice.capabilities`）。
///
/// 只取故事页用得到的两个：
/// - `ocr == false` → 隐藏拍照/相册识别入口（screens.md §6.5）；
/// - `image == false` → 隐藏「生成插画」。
///
/// 缺省 `true`：宁可让用户点、服务端返回可读错误，也不要误藏功能（HOS 语义）。
/// 说明：`SiteCapabilities` 没有 `heic` 字段，所以相册/相机统一转 JPEG（见回报偏差项）。
@MainActor
enum StoryCapabilities {
    static func load(services: AppServices) async -> (ocr: Bool, image: Bool) {
        guard let health = try? await services.practice.health(),
              let capabilities = health.voice?.capabilities
        else {
            return (true, true)
        }
        return (capabilities.ocr ?? true, capabilities.image ?? true)
    }
}

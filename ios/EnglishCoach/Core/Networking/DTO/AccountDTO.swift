import Foundation

// MARK: - 账号 / 设置 / 家庭成员 / 家长面板 / 建议箱 / 虚拟形象 DTO
//
// 事实来源：`hos/entry/src/main/ets/core/net/AccountDtos.ets`（逐字段迁移）+ 后端 route 形状。
// 解码统一走 `HTTPClient.decode`（`convertFromSnakeCase`）：响应字段用 Swift 驼峰属性名即可，
// 不需要手写 CodingKeys。请求体由 `AccountService` 用 `.convertToSnakeCase` 编码。

// ---------------------------------------------------------------------------
// MARK: /settings
// ---------------------------------------------------------------------------

/// `GET /settings`（全量 user + prefs + usage）与 `PATCH /settings`（瘦身 user + prefs + usage）。
struct SettingsResponseDTO: Decodable, Sendable {
    let user: AccountUserDTO?
    let prefs: PrefsDTO?
    let usage: UsageDTO?
}

/// 账号偏好；`prefs` 是 camelCase（PATCH 入参才是 snake_case）。
struct PrefsDTO: Decodable, Sendable, Equatable {
    /// gentle | standard | none
    let correctionLevel: String?
    /// 9 个音色 id 或 nil（provider 默认）
    let ttsVoice: String?
    /// slow | normal
    let ttsRate: String?
    /// 点单词显示音标（nil = 默认开）
    let showWordIpa: Bool?
}

/// `PATCH /settings` 请求体（服务端 snake_case，由编码策略转换）。
///
/// 语义（与 HOS `SettingsPatchBodyDto` 一致）：除 `clears` 里声明的字段外，`nil` 一律表示
/// “本次不修改”。需要把服务端字段恢复默认（发送 JSON `null`）时，用 `clear(_:)` 显式声明，
/// 例如 `body.clear(.ttsVoice)`。
///
/// 儿童**绝不能**带 `dailyLimitMinutes` / `allowFreeChat`（服务端 403，整单失败）。
struct SettingsPatchDTO: Encodable, Sendable {
    var displayName: String?
    var dailyLimitMinutes: Int?
    var allowFreeChat: Bool?
    var autoIllustrate: Bool?
    /// girl | boy | woman | man | other
    var gender: String?
    /// 3–12；服务端语义 nil = 恢复角色默认（儿童 5 / 成人 8）
    var storySentences: Int?
    /// gentle | standard | none
    var correctionLevel: String?
    /// slow | normal
    var ttsRate: String?
    /// 9 个音色 id 或 nil（provider 默认）
    var ttsVoice: String?
    /// 点单词显示音标（nil = 默认开）
    var showWordIpa: Bool?
    /// 显式发送 JSON `null` 的字段集合（其余 `nil` 字段不参与请求）。
    var clears: Set<ClearField> = []

    /// 服务端允许用 `null` 重置的字段。
    enum ClearField: String, Sendable, Hashable, CaseIterable {
        case gender
        case storySentences
        case ttsVoice
        case showWordIpa
    }

    mutating func clear(_ field: ClearField) {
        clears.insert(field)
    }

    enum CodingKeys: String, CodingKey {
        case displayName
        case dailyLimitMinutes
        case allowFreeChat
        case autoIllustrate
        case gender
        case storySentences
        case correctionLevel
        case ttsRate
        case ttsVoice
        case showWordIpa
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try container.encodeIfPresent(allowFreeChat, forKey: .allowFreeChat)
        try container.encodeIfPresent(autoIllustrate, forKey: .autoIllustrate)
        try container.encodeIfPresent(correctionLevel, forKey: .correctionLevel)
        try container.encodeIfPresent(ttsRate, forKey: .ttsRate)

        if clears.contains(.gender) {
            try container.encodeNil(forKey: .gender)
        } else {
            try container.encodeIfPresent(gender, forKey: .gender)
        }
        if clears.contains(.storySentences) {
            try container.encodeNil(forKey: .storySentences)
        } else {
            try container.encodeIfPresent(storySentences, forKey: .storySentences)
        }
        if clears.contains(.ttsVoice) {
            try container.encodeNil(forKey: .ttsVoice)
        } else {
            try container.encodeIfPresent(ttsVoice, forKey: .ttsVoice)
        }
        if clears.contains(.showWordIpa) {
            try container.encodeNil(forKey: .showWordIpa)
        } else {
            try container.encodeIfPresent(showWordIpa, forKey: .showWordIpa)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: /family/members
// ---------------------------------------------------------------------------

struct FamilyMemberStatsDTO: Decodable, Sendable, Equatable {
    let attempts: Int?
    let lastActiveAt: String?
}

/// 家庭成员列表是 **snake_case**，与 `/auth/me` 的 camelCase user 是两套 DTO。
struct FamilyMemberDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let email: String?
    let displayName: String?
    /// parent | child
    let role: String?
    let ageBand: String?
    let cefrLevel: String?
    let avatar: String?
    let birthYear: Int?
    let dailyLimitMinutes: Int?
    let allowFreeChat: Bool?
    let createdAt: String?
    let stats: FamilyMemberStatsDTO?
}

struct FamilyMemberListDTO: Decodable, Sendable {
    let items: [FamilyMemberDTO]?
    let count: Int?
}

/// `POST /family/members` 请求体。
struct FamilyCreateDTO: Encodable, Sendable {
    let displayName: String
    /// 可只写简称，服务端自动补 `@family.local`
    let login: String
    let password: String
    /// parent | child
    let role: String
    /// A1 | A2 | B1 | B2 | C1
    let cefrLevel: String
    var birthYear: Int?
    var avatar: String?
    var dailyLimitMinutes: Int?
    var allowFreeChat: Bool?
}

/// `PATCH /family/members/:id` 请求体（传 role 会 400）。
struct FamilyPatchDTO: Encodable, Sendable {
    var displayName: String?
    var cefrLevel: String?
    var dailyLimitMinutes: Int?
    var allowFreeChat: Bool?
    var avatar: String?
}

struct FamilyMemberResponseDTO: Decodable, Sendable {
    let ok: Bool?
    let member: FamilyMemberDTO?
}

struct ResetPasswordBodyDTO: Encodable, Sendable {
    let newPassword: String
}

// ---------------------------------------------------------------------------
// MARK: /parent/summary
// ---------------------------------------------------------------------------

struct ParentSummaryDTO: Decodable, Sendable {
    let generatedAt: String?
    let family: ParentFamilyDTO?
    let members: [ParentMemberDTO]?

    /// 聚合里的儿童条目。
    struct ParentChildDTO: Decodable, Sendable, Equatable {
        let id: String
        let displayName: String?
        let remainingMinutes: Double?
        let limitMinutes: Double?
    }
}

/// 家庭聚合块。
struct ParentFamilyDTO: Decodable, Sendable {
    let members: Int?
    let minutesToday: Double?
    /// 服务端字段是 `minutes_7d`（JSON 键含数字，转换后为 `minutes7d`）。
    let minutes7d: Double?
    let sentenceCount: Int?
    let scenarioCount: Int?
    let children: [ParentSummaryDTO.ParentChildDTO]?
}

struct ParentTodayDTO: Decodable, Sendable, Equatable {
    let minutes: Double?
    let blindMinutes: Double?
    let totalMinutes: Double?
    let attemptCount: Int?
    let chatTurns: Int?
    /// 仅 role == "child" 有值，家长为 nil
    let remainingMinutes: Double?
    let exceeded: Bool?
}

struct ParentWeekDTO: Decodable, Sendable, Equatable {
    let minutes: Double?
    let attempts: Int?
    let avgPron: Double?
}

struct ParentTotalsDTO: Decodable, Sendable, Equatable {
    let attempts: Int?
    let chatSessions: Int?
    let phonemeRows: Int?
    let avgPron: Double?
}

struct ParentTrendPointDTO: Decodable, Sendable, Equatable {
    let date: String?
    let attempts: Int?
    let avgPron: Double?
}

/// 盲测成绩块（current / previous / series 共用）。
struct ParentBlindScoreDTO: Decodable, Sendable, Equatable {
    let blindTestId: String?
    let endedAt: String?
    let avgPron: Double?
    let avgAccuracy: Double?
    let avgFluency: Double?
    let avgIntonationDistance: Double?
    let itemCount: Int?
}

struct ParentBlindDTO: Decodable, Sendable {
    let weeks: Int?
    let current: ParentBlindScoreDTO?
    let previous: ParentBlindScoreDTO?
    let deltaPron: Double?
    let series: [ParentBlindScoreDTO]?
    let inProgressId: String?
}

struct ParentPhonemeDTO: Decodable, Sendable, Equatable {
    let phoneme: String?
    let count: Int?
    let avgScore: Double?
    let hardHits: Int?
    let titleZh: String?
}

struct ParentWordDTO: Decodable, Sendable, Equatable {
    let word: String?
    let count: Int?
    let avgScore: Double?
    let coarse: Bool?
}

struct ParentMemberDTO: Decodable, Sendable {
    let id: String
    let displayName: String?
    let avatar: String?
    let role: String?
    let ageBand: String?
    let cefrLevel: String?
    let birthYear: Int?
    let dailyLimitMinutes: Int?
    let today: ParentTodayDTO?
    let week: ParentWeekDTO?
    let totals: ParentTotalsDTO?
    let trend: [ParentTrendPointDTO]?
    let blind: ParentBlindDTO?
    let topPhonemes: [ParentPhonemeDTO]?
    let topWords: [ParentWordDTO]?
}

// ---------------------------------------------------------------------------
// MARK: /suggestions
// ---------------------------------------------------------------------------

struct SuggestionViewportDTO: Codable, Sendable, Equatable {
    var w: Double?
    var h: Double?
}

struct SuggestionContextDTO: Codable, Sendable {
    var ua: String?
    var appVersion: String?
    var voiceMode: String?
    var viewport: SuggestionViewportDTO?
    var storyId: String?
    var storyTitle: String?
    var style: String?
    var prompt: String?
    var kind: String?
}

struct SuggestionDTO: Decodable, Sendable {
    let id: String
    /// child | parent
    let userRole: String?
    let page: String?
    /// experience | content | feature | bug | other
    let category: String?
    let content: String?
    /// open | read | resolved
    let status: String?
    let createdAt: String?
    let handledAt: String?
    let context: SuggestionContextDTO?
}

struct SuggestionCountsDTO: Decodable, Sendable, Equatable {
    let open: Int?
    let read: Int?
    let resolved: Int?
}

struct SuggestionListDTO: Decodable, Sendable {
    let items: [SuggestionDTO]?
    let counts: SuggestionCountsDTO?
    let total: Int?
    let generatedAt: String?
    let maxLength: Int?
}

/// `POST /suggestions` 请求体（所有人含儿童都能提；user_id 由服务端从会话取）。
struct SuggestionCreateDTO: Encodable, Sendable {
    /// experience | content | feature | bug | other
    let category: String
    let content: String
    var page: String?
    var context: SuggestionContextDTO?
}

struct SuggestionCreateResultDTO: Decodable, Sendable {
    let ok: Bool?
    let id: String?
    let maxLength: Int?
}

/// `PATCH /suggestions/:id` 请求体。
struct SuggestionPatchDTO: Encodable, Sendable {
    /// open | read | resolved
    let status: String
}

// ---------------------------------------------------------------------------
// MARK: /avatar + /avatar/presets
// ---------------------------------------------------------------------------

/// `/avatar` 的 styles 字段：5 种风格 id → 中文名。
struct AvatarStyleLabelsDTO: Decodable, Sendable, Equatable {
    let watercolor: String?
    let cartoon: String?
    let pixel: String?
    let papercut: String?
    let clay: String?
}

struct AvatarStyleDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let labelZh: String?
}

/// 角色图映射：键固定为 5 个风格 id，值是**站内绝对路径**（`/avatars/presets/...`）。
/// 移动端必须拼上 `AppConfig.baseURL` 才能加载（静态图无需鉴权）。
struct AvatarImagesDTO: Decodable, Sendable, Equatable {
    let watercolor: String?
    let cartoon: String?
    let pixel: String?
    let papercut: String?
    let clay: String?
}

struct AvatarPresetCharacterDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let labelZh: String?
    let descEn: String?
    /// girl | boy | woman | man | other
    let gender: String?
    /// child | adult
    let audience: String?
    let images: AvatarImagesDTO?
}

struct AvatarPresetsDTO: Decodable, Sendable {
    let count: Int?
    /// true = 服务端用的是占位图，UI 要提示「预览图」
    let placeholder: Bool?
    let styles: [AvatarStyleDTO]?
    let characters: [AvatarPresetCharacterDTO]?
}

/// `GET/POST/PATCH /avatar` 的返回（PATCH 多一个 message）。
struct AvatarStateDTO: Decodable, Sendable {
    let ok: Bool?
    /// 预置图 → 静态路径；自定义图 → `/api/avatar/image?...`（当前策略下不会出现）
    let avatarUrl: String?
    let presetId: String?
    let style: String?
    let characterDesc: String?
    let promptUsed: String?
    let updatedAt: String?
    let styles: AvatarStyleLabelsDTO?
    let message: String?
}

/// `POST /avatar` 请求体。
struct AvatarSelectBodyDTO: Encodable, Sendable {
    let presetId: String
    let style: String
}

/// `PATCH /avatar` 请求体（只允许改角色卡描述）。
struct AvatarDescBodyDTO: Encodable, Sendable {
    let characterDesc: String
}

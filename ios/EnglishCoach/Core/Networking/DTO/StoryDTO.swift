import Foundation

// 故事域网络 DTO：字段名与可空性照 `hos/entry/src/main/ets/core/net/StoryDtos.ets` 逐项迁移。
// 服务端 snake_case 由 `HTTPClient.decode` 的 `convertFromSnakeCase` 统一转换；
// 数组/子对象一律可选，使用处兜底（契约 §2.8）。
// HOS 文件尾部的展示模型（StoryCardItem / StoryGroup / StorySentenceItem …）属于页面 VM 形状，
// 由 Features/Story 自己定义，不在这里。

// MARK: - materials（kind=story）

/// 故事 / 书页（材料）：列表项是 summary，详情多 `text` / `sourceZh` / `image*` 字段。
struct StoryMaterialDTO: Decodable, Sendable {
    let id: String
    let title: String?
    /// 英文正文（详情才有；句子以换行分隔）
    let text: String?
    /// 中文原文（详情才有）
    let sourceZh: String?
    let kind: String?
    let level: String?
    let sentenceCount: Int?
    let source: String?
    let hasImage: Bool?
    let hasSourceZh: Bool?
    /// 详情：`materials/:id/image`（需要 Bearer，不能直接交给 Image 用）
    let imageUrl: String?
    /// 详情：上次生成插画用的提示词
    let imagePrompt: String?
    let imageCharacterUsed: Bool?
    let createdBy: String?
    let createdByName: String?
    let createdByAvatarUrl: String?
    let createdAt: String?
    let updatedAt: String?
}

struct StoryMaterialListDTO: Decodable, Sendable {
    let count: Int?
    let items: [StoryMaterialDTO]?
}

/// `POST materials` 请求体（kind=story）。编码走 `ECJSON.encode`（camelCase → snake_case）。
struct StoryMaterialCreateDTO: Codable, Sendable {
    let title: String
    let text: String
    let kind: String
    let sourceZh: String?
    let level: String?
    let source: String?
}

/// `POST materials` 响应（201，summary + limits）。
struct StoryMaterialCreatedDTO: Decodable, Sendable {
    let id: String
    let title: String?
    let createdByName: String?
    let sentenceCount: Int?
    let hasImage: Bool?
    let source: String?
    let kind: String?
    let level: String?
    let hasSourceZh: Bool?
    let createdBy: String?
    let createdAt: String?
    let updatedAt: String?
}

// MARK: - asr（线上降级路径：中文 / 英文转录）

/// `POST asr` 响应。故事域只认 `text`；空文本由页面判断「没听清」。
struct StoryAsrDTO: Decodable, Sendable {
    let text: String?
    let language: String?
    let provider: String?
    let durationMs: Int?
    let error: String?
}

// MARK: - story/rewrite

struct StoryReadabilityDTO: Decodable, Sendable {
    let sentenceCount: Int?
    let avgWords: Double?
    let maxWords: Int?
    let unknownWords: [String]?
    let ok: Bool?
}

/// `POST story/rewrite` 响应（中文 → 分级英文）。
struct StoryRewriteDTO: Decodable, Sendable {
    let titleEn: String?
    /// 英文句子。服务端正常形状是 `["…", "…"]`；历史版本可能返回 `[{en, zh}]`，
    /// 这里兼容两种并统一成 `[String]`（对象取 `en`，缺失时取 `text`）。
    let sentences: [String]
    let textEn: String?
    let level: String?
    let readability: StoryReadabilityDTO?
    let warnings: [String]?
    let provider: String?
    let weakPhonemesUsed: [String]?

    private enum CodingKeys: String, CodingKey {
        case titleEn
        case sentences
        case textEn
        case level
        case readability
        case warnings
        case provider
        case weakPhonemesUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        titleEn = try container.decodeIfPresent(String.self, forKey: .titleEn)
        sentences = Self.decodeSentences(container)
        textEn = try container.decodeIfPresent(String.self, forKey: .textEn)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        readability = try container.decodeIfPresent(StoryReadabilityDTO.self, forKey: .readability)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        weakPhonemesUsed = try container.decodeIfPresent([String].self, forKey: .weakPhonemesUsed)
    }

    private static func decodeSentences(_ container: KeyedDecodingContainer<CodingKeys>) -> [String] {
        if let list = try? container.decode([String].self, forKey: .sentences), !list.isEmpty {
            return list
        }
        if let pairs = try? container.decode([StorySentenceEnvelope].self, forKey: .sentences) {
            let values = pairs.compactMap { $0.en ?? $0.text }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !values.isEmpty {
                return values
            }
        }
        // 兜底：个别版本把多句塞进一个字符串（换行分隔）。
        if let raw = try? container.decode(String.self, forKey: .sentences) {
            return raw
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}

/// 兼容 `sentences: [{en, zh}]` 形状的解码辅助（契约只保证 `[String]`）。
private struct StorySentenceEnvelope: Decodable {
    let en: String?
    let zh: String?
    let text: String?
}

// MARK: - story/retell

/// `POST story/retell` 响应（不评发音分）。
struct StoryRetellDTO: Decodable, Sendable {
    let id: String?
    /// 0–1 的覆盖率（儿童端不显示百分比）
    let coverage: Double?
    let coveredPoints: [String]?
    let missingPoints: [String]?
    let feedbackZh: String?
    let feedbackEn: String?
    let warnings: [String]?
    let provider: String?
}

/// `GET story/:id/retells` 的列表项。
/// **契约未定**：HOS 没有这个接口（复述结果只在本会话内存保留），线上可能 404；
/// 服务层按「失败返回 []」处理，字段先对齐 HOS 的展示模型 `StoryRetellRecord`。
struct StoryRetellRecordDTO: Decodable, Sendable {
    let createdAt: String?
    let coverage: Double?
    let coveredCount: Int?
    let coveredPoints: [String]?
    let missingPoints: [String]?
    let feedbackZh: String?
    let feedbackEn: String?
    let transcript: String?
}

// MARK: - story/:id/illustrate

/// `POST story/:id/illustrate` 响应。
struct StoryIllustrationDTO: Decodable, Sendable {
    let ok: Bool?
    let imageUrl: String?
    let imagePath: String?
    let mime: String?
    let provider: String?
    let model: String?
    let size: String?
    let elapsedMs: Int?
    let warnings: [String]?
    let promptUsed: String?
    let characterUsed: Bool?
    let characterDescUsed: String?
    let characterStyleUsed: String?
    let force: Bool?
}

// MARK: - story/:id/audio/status（整段朗读回放）

/// 服务端状态：ready | building | failed；客户端补充 noAudio（404，没有任何朗读录音）。
struct StoryAudioStatusDTO: Decodable, Sendable {
    let status: String?
    let attemptCount: Int?
    let single: Bool?
    let durationMs: Int?
    let error: String?
    let errorCode: String?
    let retryAfterMs: Int?
}

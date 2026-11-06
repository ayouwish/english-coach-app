import Foundation

/// 单词音标查询结果（浮层只显示 `/ipa/`，不提供发音按钮）。
///
/// 契约 §3.8 声明了 `word / ipa / syllables / error` 四个字段；线上 `/words/:word`
/// （HOS `DictionaryService`、Android `DictionaryService.kt`）实际还返回
/// `variants`（多变体读音）与 `ipa_disabled`（设置里关闭了音标），这两个字段
/// UI 需要用来显示「其它读音」与「音标已关闭」，因此这里一并保留为可选。
struct WordIpaDTO: Decodable, Sendable, Equatable {
    let word: String
    let ipa: String?
    let syllables: [String]?
    let error: String?
    let variants: [String]?
    let ipaDisabled: Bool?

    enum CodingKeys: String, CodingKey {
        case word
        case ipa
        case syllables
        case error
        case variants
        case ipaDisabled
    }
}

extension WordIpaDTO {
    /// 防御式解码：`syllables` 在 HOS/线上是 Int（音节数），契约里写的是 `[String]`。
    /// 两种都接受：数组直接用，数字则忽略（本字段不参与 UI 展示）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.decodeIfPresent(String.self, forKey: .word) ?? ""
        ipa = try container.decodeIfPresent(String.self, forKey: .ipa)
        if let list = try? container.decodeIfPresent([String].self, forKey: .syllables) {
            syllables = list
        } else {
            syllables = nil
        }
        error = try container.decodeIfPresent(String.self, forKey: .error)
        if let list = try? container.decodeIfPresent([String].self, forKey: .variants) {
            variants = list
        } else {
            variants = nil
        }
        ipaDisabled = try container.decodeIfPresent(Bool.self, forKey: .ipaDisabled)
    }
}

/// `GET /words/:word`、`GET /words?words=a,b` 的音标服务。
/// 只负责取数：404 / `ipa == nil` 的「暂无音标」判定与进程内缓存由调用方（内容/页面层）决定。
struct DictionaryService: Sendable {
    let transport: APITransport

    private static let timeout: TimeInterval = 8

    /// `GET /words/:word`。词为空时直接返回空结果（不发请求），UI 显示「暂无音标」。
    func wordIpa(word: String) async throws -> WordIpaDTO {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return WordIpaDTO(
                word: "",
                ipa: nil,
                syllables: nil,
                error: nil,
                variants: nil,
                ipaDisabled: nil
            )
        }
        let endpoint = Endpoint(
            method: .get,
            path: "words/\(trimmed)",
            timeout: Self.timeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: WordIpaDTO.self)
    }

    /// `GET /words?words=a,b` 批量音标（点词浮层的降级方案：一次取回整句的词）。
    /// 返回顺序与请求顺序一致（服务端按入参顺序返回）。
    func wordIpaBatch(words: [String]) async throws -> [WordIpaDTO] {
        let trimmed = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else {
            return []
        }
        let endpoint = Endpoint(
            method: .get,
            path: "words",
            query: [URLQueryItem(name: "words", value: trimmed.joined(separator: ","))],
            timeout: Self.timeout,
            authPolicy: .bearer
        )
        let response = try await transport.send(endpoint, as: WordIpaBatchEnvelope.self)
        return response.items
    }
}

/// 批量响应的两种可能形状：裸数组 或 `{ words: [...] }`。
private struct WordIpaBatchEnvelope: Decodable, Sendable {
    let items: [WordIpaDTO]

    private enum CodingKeys: String, CodingKey {
        case words
    }

    init(from decoder: Decoder) throws {
        if let list = try? [WordIpaDTO](from: decoder) {
            items = list
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([WordIpaDTO].self, forKey: .words) ?? []
    }
}

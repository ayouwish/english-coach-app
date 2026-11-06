import Foundation

/// 内置音色（`GET /api/tts/voices` 线上 404，按 `chat-story.md` §5.1 内置）。
/// 字段与服务端一致：id / label_zh / lang / sample（没有 gender 字段）。
struct VoiceOption: Identifiable, Sendable, Equatable {
    let id: String
    let labelZh: String
    /// "en" | "zh"
    let lang: String
    let sample: String?
}

/// 媒体侧公共能力：内置音色常量、图片 Content-Type / 文件名推断、书页 OCR。
///
/// 注意：契约 §3.8 把 `imageContentType` / `imageFileName` / `ocr` 归到 MediaService
/// （HOS 里前两者在 FlowService、ocr 在 FlowService）；iOS 侧统一收口到这里。
struct MediaService: Sendable {
    let transport: APITransport

    /// 9 个内置音色（照 HOS `core/service/MediaService.ets` 的 `voices()` 全量迁移）。
    static let voicesConst: [VoiceOption] = [
        VoiceOption(
            id: "en-US-JennyNeural",
            labelZh: "Jenny · 英语女声（默认）",
            lang: "en",
            sample: "Hello! Let's practice English together."
        ),
        VoiceOption(
            id: "en-US-AriaNeural",
            labelZh: "Aria · 英语女声（活泼）",
            lang: "en",
            sample: "Hi there! Ready for a story?"
        ),
        VoiceOption(
            id: "en-US-AnaNeural",
            labelZh: "Ana · 英语童声",
            lang: "en",
            sample: "I like playing with my friends!"
        ),
        VoiceOption(
            id: "en-US-GuyNeural",
            labelZh: "Guy · 英语男声",
            lang: "en",
            sample: "Good job! Let's try the next sentence."
        ),
        VoiceOption(
            id: "en-US-MichelleNeural",
            labelZh: "Michelle · 英语女声（温柔）",
            lang: "en",
            sample: "Take your time. You are doing great."
        ),
        VoiceOption(
            id: "zh-CN-XiaoxiaoNeural",
            labelZh: "晓晓 · 中文女声（默认）",
            lang: "zh",
            sample: "你好呀，我们一起来练习吧。"
        ),
        VoiceOption(
            id: "zh-CN-XiaoyiNeural",
            labelZh: "晓伊 · 中文女声（温柔）",
            lang: "zh",
            sample: "慢慢来，不着急。"
        ),
        VoiceOption(
            id: "zh-CN-YunxiNeural",
            labelZh: "云希 · 中文男声",
            lang: "zh",
            sample: "太棒了，继续加油！"
        ),
        VoiceOption(
            id: "zh-CN-YunjianNeural",
            labelZh: "云健 · 中文男声（沉稳）",
            lang: "zh",
            sample: "今天我们一起读一个小故事。"
        )
    ]

    private static let ocrTimeout: TimeInterval = 60

    /// 按 id 找内置音色；找不到返回 nil（页面显示「默认音色」）。
    static func findVoice(_ id: String) -> VoiceOption? {
        voicesConst.first { $0.id == id }
    }

    /// 是否为内置音色 id（用于校验 PATCH settings 的 `tts_voice`）。
    static func isKnownVoice(_ id: String) -> Bool {
        findVoice(id) != nil
    }

    /// 按文件扩展名推断图片 Content-Type。服务端会按文件头二次校验，
    /// 但显式给正确的类型可避免 HEIC 被当作 JPEG 解码。
    static func imageContentType(path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".png") {
            return "image/png"
        }
        if lower.hasSuffix(".heic") {
            return "image/heic"
        }
        if lower.hasSuffix(".heif") {
            return "image/heif"
        }
        if lower.hasSuffix(".webp") {
            return "image/webp"
        }
        return "image/jpeg"
    }

    /// 上传时使用的远程文件名（服务端按扩展名/文件头识别格式）。
    static func imageFileName(path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".png") {
            return "page.png"
        }
        if lower.hasSuffix(".heic") {
            return "page.heic"
        }
        if lower.hasSuffix(".heif") {
            return "page.heif"
        }
        if lower.hasSuffix(".webp") {
            return "page.webp"
        }
        return "page.jpg"
    }

    /// `POST /ocr`（multipart `image`）→ 书页文字识别结果。
    /// 首次识别可能 1–2s，超时给足 60s（与 HOS / architecture.md §4.5 一致）。
    func ocr(imageData: Data, filename: String, mimeType: String) async throws -> OCRResultDTO {
        guard !imageData.isEmpty else {
            throw APIError.server(code: .badRequest, message: nil, status: 0)
        }
        var builder = MultipartFormDataBuilder()
        builder.addFile(name: "image", filename: filename, mimeType: mimeType, data: imageData)
        let endpoint = Endpoint(
            method: .post,
            path: "ocr",
            body: .multipart(builder.finalize()),
            timeout: Self.ocrTimeout,
            authPolicy: .bearer
        )
        return try await transport.send(endpoint, as: OCRResultDTO.self)
    }
}

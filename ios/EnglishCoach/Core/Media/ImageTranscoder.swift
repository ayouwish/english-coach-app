import CoreGraphics
import Foundation
import OSLog
import UIKit

private let transcodeLogger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "media")

/// 图片解码/缩放/编码（task-14 冻结签名）。
///
/// 服务端 `POST /ocr` 与图片上传都能吃 JPEG；HEIC 只有在 `/health` 的
/// `voice.capabilities.heic == true` 时才允许原图上传（screens.md §6.2），
/// 所以统一入口是 `uploadPayload`：
/// - 能原样直传 HEIC 时返回 `image/heic`；
/// - 否则解码后按长边缩放重编码成 JPEG，质量 0.8 起步，体积超 5MB 依次降质，
///   仍然超限返回 `nil`（文案由调用方给，见 docs/roadmap.md 的验收项）。
///
/// 两个函数都是**纯 CPU**、无全局状态、可在任意线程调用；页面从主线程调用时请用
/// `uploadPayloadInBackground`（内部 `Task.detached`），避免把解码/编码压在主线程上。
enum ImageTranscoder {
    /// 上传体积上限（服务端图片契约，见 docs/roadmap.md“总体积 <5MB”）。
    static let maxUploadBytes = 5 * 1024 * 1024
    /// OCR/故事页的默认长边（task-14 / docs/android-feature-list.md 的实践值）。
    static let defaultMaxDimension: CGFloat = 1_600
    /// JPEG 起始质量。
    static let defaultQuality: CGFloat = 0.8

    /// 超限时的降质阶梯：每档重新编码，命中 ≤5MB 即返回。
    private static let qualitySteps: [CGFloat] = [0.8, 0.65, 0.5, 0.4, 0.3]
    private static let minimumQuality: CGFloat = 0.05

    // MARK: - 冻结 API

    /// `UIImage` → 长边不超过 `maxDimension` 的 JPEG 数据（像素尺寸，不放大）。
    static func jpegData(from image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let targetSize = fittedPixelSize(of: image, maxDimension: maxDimension)
        guard targetSize.width >= 1, targetSize.height >= 1 else { return nil }

        // scale = 1 让“点”等于“像素”，长边才会真的落在 maxDimension 上；
        // opaque = true 去掉 alpha（JPEG 不支持透明），先铺白底避免透明区域变黑。
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        let normalizedQuality = min(max(quality, Self.minimumQuality), 1)
        return rendered.jpegData(compressionQuality: normalizedQuality)
    }

    /// 原始照片/文件字节 → 可上传载荷 `(data, mimeType, filename)`。
    ///
    /// - HEIC/HEIF 且 `allowsHEIC == true` 且 ≤5MB：原样上传（`image/heic`）；
    /// - 其余情况（含 HEIC 降级、JPEG、PNG、其它可解码格式）：统一转 JPEG；
    /// - 解码失败或降质后仍 >5MB：返回 `nil`，调用方提示“换一张图片/重新拍摄”。
    static func uploadPayload(
        from data: Data,
        fileExtensionHint: String?,
        allowsHEIC: Bool,
        maxDimension: CGFloat
    ) -> (data: Data, mimeType: String, filename: String)? {
        guard !data.isEmpty else { return nil }
        let dimension = maxDimension > 0 ? maxDimension : Self.defaultMaxDimension
        let kind = detectedKind(of: data, hint: fileExtensionHint)

        if kind == .heic {
            if allowsHEIC {
                if data.count <= Self.maxUploadBytes {
                    return (data, "image/heic", "page.heic")
                }
                transcodeLogger.debug("heic payload over limit, falling back to jpeg")
            }
            guard let image = UIImage(data: data) else {
                transcodeLogger.error("heic decode failed")
                return nil
            }
            return jpegPayload(from: image, maxDimension: dimension)
        }

        guard let image = UIImage(data: data) else {
            transcodeLogger.error("image decode failed")
            return nil
        }
        return jpegPayload(from: image, maxDimension: dimension)
    }

    /// `uploadPayload` 的后台版本：解码/缩放/编码都在 `Task.detached` 里完成，
    /// 页面（`@MainActor` Store）从此入口调用即可不阻塞主线程。
    static func uploadPayloadInBackground(
        from data: Data,
        fileExtensionHint: String?,
        allowsHEIC: Bool,
        maxDimension: CGFloat
    ) async -> (data: Data, mimeType: String, filename: String)? {
        let boxed = await Task.detached(priority: .userInitiated) { () -> PayloadBox? in
            guard let payload = Self.uploadPayload(
                from: data,
                fileExtensionHint: fileExtensionHint,
                allowsHEIC: allowsHEIC,
                maxDimension: maxDimension
            ) else {
                return nil
            }
            return PayloadBox(data: payload.data, mimeType: payload.mimeType, filename: payload.filename)
        }.value
        guard let boxed else { return nil }
        return (data: boxed.data, mimeType: boxed.mimeType, filename: boxed.filename)
    }

    // MARK: - 内部

    private struct PayloadBox: Sendable {
        let data: Data
        let mimeType: String
        let filename: String
    }

    private enum ImageKind: Equatable {
        case heic
        case jpeg
        case png
        case other
    }

    private static func jpegPayload(
        from image: UIImage,
        maxDimension: CGFloat
    ) -> (data: Data, mimeType: String, filename: String)? {
        for quality in Self.qualitySteps {
            guard let data = Self.jpegData(from: image, maxDimension: maxDimension, quality: quality) else {
                continue
            }
            if data.count <= Self.maxUploadBytes {
                return (data, "image/jpeg", "page.jpg")
            }
        }
        transcodeLogger.error("jpeg still over limit after quality fallback")
        return nil
    }

    /// 由 `UIImage` 的像素尺寸（点 × scale）算出缩放后的目标像素尺寸；不放大。
    private static func fittedPixelSize(of image: UIImage, maxDimension: CGFloat) -> CGSize {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0, pixelHeight > 0 else { return .zero }

        let limit = maxDimension > 0 ? maxDimension : Self.defaultMaxDimension
        let longestSide = max(pixelWidth, pixelHeight)
        guard longestSide > limit else {
            return CGSize(width: pixelWidth.rounded(), height: pixelHeight.rounded())
        }

        let ratio = limit / longestSide
        return CGSize(
            width: max(1, (pixelWidth * ratio).rounded()),
            height: max(1, (pixelHeight * ratio).rounded())
        )
    }

    /// 先用文件头识别（最可靠），再退回扩展名提示。
    private static func detectedKind(of data: Data, hint: String?) -> ImageKind {
        let header = [UInt8](data.prefix(12))

        if header.count >= 3, header[0] == 0xFF, header[1] == 0xD8, header[2] == 0xFF {
            return .jpeg
        }
        if header.count >= 8, header[0] == 0x89, header[1] == 0x50, header[2] == 0x4E, header[3] == 0x47 {
            return .png
        }
        if looksLikeHEIC(data) {
            return .heic
        }

        switch hint?.lowercased() ?? "" {
        case "heic", "heif":
            return .heic
        case "jpg", "jpeg":
            return .jpeg
        case "png":
            return .png
        default:
            return .other
        }
    }

    /// HEIC/HEIF 的 ISO-BMFF 文件头：`....ftyp` + brand（heic/heix/heif/hevc/hevx/mif1/msf1）。
    private static func looksLikeHEIC(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let header = [UInt8](data.prefix(12))
        guard header[4] == 0x66, header[5] == 0x74, header[6] == 0x79, header[7] == 0x70 else {
            return false
        }
        let brand = String(bytes: header[8..<12], encoding: .ascii)
        let heicBrands = ["heic", "heix", "heif", "hevc", "hevx", "mif1", "msf1"]
        return brand.map(heicBrands.contains) ?? false
    }
}

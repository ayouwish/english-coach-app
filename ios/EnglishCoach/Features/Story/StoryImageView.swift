import SwiftUI
import UIKit

// MARK: - 图片加载（带 Bearer + ImageCache）

/// 故事/书页图片加载：先查 `ImageCache`，未命中再走 `StoryService.materialImageData`。
///
/// 键 = `ImageCache.imageKey(materialId:version:)`（architecture.md §7.2），
/// 版本号由 `updatedAt` 派生，重新生成插画后自动失效。
@MainActor
enum StoryImageLoader {
    private static let cache = ImageCache()

    static func load(materialId: String, version: Int, services: AppServices) async -> Data? {
        let key = ImageCache.imageKey(materialId: materialId, version: version)
        if let cached = await cache.data(for: key) {
            return cached
        }
        guard let data = try? await services.story.materialImageData(materialId: materialId), !data.isEmpty else {
            return nil
        }
        await cache.store(data, for: key)
        return data
    }

    /// 强制刷新（重新生成插画后调用）：先清内存/磁盘命中再拉取。
    static func reload(materialId: String, version: Int, services: AppServices) async -> Data? {
        guard let data = try? await services.story.materialImageData(materialId: materialId), !data.isEmpty else {
            return nil
        }
        let key = ImageCache.imageKey(materialId: materialId, version: version)
        await cache.store(data, for: key)
        return data
    }
}

// MARK: - 图片视图

/// 故事图片（Data → UIImage）；无图/失败时显示浅底占位图标，不阻塞卡片布局。
struct StoryImageView: View {
    var data: Data?
    var height: CGFloat = 160
    var cornerRadius: CGFloat = Tokens.Radius.large
    var placeholderIcon: String = "book.closed"

    var body: some View {
        ZStack {
            Tokens.Colors.surfaceSunken
            if let data = self.data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(data == nil)
    }
}

/// 远程故事图：自动缓存、版本变化自动重拉、加载中显示骨架。
struct StoryRemoteImageView: View {
    let materialId: String
    let version: Int
    let services: AppServices
    var height: CGFloat = 160
    var cornerRadius: CGFloat = Tokens.Radius.large
    var placeholderIcon: String = "book.closed"

    @State private var data: Data?
    @State private var isLoading = true

    var body: some View {
        StoryImageView(
            data: data,
            height: height,
            cornerRadius: cornerRadius,
            placeholderIcon: placeholderIcon
        )
        .overlay {
            if isLoading {
                SkeletonBlock(height: height, cornerRadius: cornerRadius)
            }
        }
        .task(id: "\(materialId)#\(version)") {
            isLoading = true
            data = await StoryImageLoader.load(
                materialId: materialId,
                version: version,
                services: services
            )
            isLoading = false
        }
    }
}

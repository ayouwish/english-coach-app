import Foundation
import OSLog

private let imageCacheLogger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "storage")

/// 插画/虚拟形象图片缓存（契约 §3.11）：`Caches/Images`，LRU 100MB。
///
/// 键 = `sha256(image|materialId|version)`（`CacheKey.image`）。图片永久有效，
/// 超限时按 LRU 淘汰；退出登录按目录整体清理（architecture.md §7.2）。
actor ImageCache {
    static let maxBytes = 100 * 1024 * 1024

    private let directory: URL

    init(directory: URL = CacheLocator.imagesDir()) {
        self.directory = directory
        CacheFileStore.ensureDirectory(directory)
    }

    /// 键计算入口：`version` 用服务端的插画版本/更新时间，避免重生成后仍命中旧图。
    static func imageKey(materialId: String, version: Int) -> String {
        CacheKey.image(materialId: materialId, version: version)
    }

    func data(for key: String) -> Data? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        CacheFileStore.touch(url)
        return data
    }

    func store(_ data: Data, for key: String) {
        guard !data.isEmpty, data.count <= Self.maxBytes else {
            imageCacheLogger.debug("image cache store skipped")
            return
        }
        guard CacheFileStore.writeAtomically(data, to: fileURL(for: key)) else {
            return
        }
        if CacheFileStore.totalSize(in: directory) > Self.maxBytes {
            trim()
        }
    }

    func trim() {
        CacheFileStore.trim(directory, to: Self.maxBytes)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(Hashing.sha256Hex(key) + ".image")
    }
}

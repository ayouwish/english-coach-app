import Foundation
import OSLog

private let cacheLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "storage")

/// 缓存目录（契约 §3.11 / architecture.md §7.1）。
///
/// - 可淘汰（`Caches/`）：TTS 音频、插画/形象图片、录音副本；
/// - 不可淘汰（`Application Support/`）：小体积 JSON 快照（语料、诊断等）。
///
/// `Caches/` 天然不进 iCloud 备份；所有失败都静默降级，不能因为缓存目录建不出来就崩。
enum CacheLocator {
    static func ttsDir() -> URL {
        cachesRoot().appendingPathComponent("TTS", isDirectory: true)
    }

    static func imagesDir() -> URL {
        cachesRoot().appendingPathComponent("Images", isDirectory: true)
    }

    static func recordingsDir() -> URL {
        cachesRoot().appendingPathComponent("Recordings", isDirectory: true)
    }

    static func jsonDir() -> URL {
        applicationSupportRoot().appendingPathComponent("json", isDirectory: true)
    }

    /// 创建全部缓存目录（幂等；失败只记日志）。
    static func ensureAll() {
        for directory in [ttsDir(), imagesDir(), recordingsDir(), jsonDir()] {
            CacheFileStore.ensureDirectory(directory)
        }
    }

    // MARK: - 根目录

    static func cachesRoot() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static func applicationSupportRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? cachesRoot()
    }
}

/// 缓存键拼装（architecture.md §7.2）：所有键统一 `sha256`，用户级键把 `userId` 放在最前，
/// 避免共用一台 iPad 时串号。
enum CacheKey {
    /// `sha256(userId|parts...)`；`userId` 为空时退化为 `sha256(parts...)`（仅用于非个人资源）。
    static func make(_ parts: [String], userId: String? = nil) -> String {
        var segments: [String] = []
        if let userId, !userId.isEmpty {
            segments.append("user=\(userId)")
        }
        segments.append(contentsOf: parts)
        return Hashing.sha256Hex(segments.joined(separator: "|"))
    }

    /// TTS 键 = `sha256(text|rate|voice|format)`（契约 §3.11 明文规定，不含 userId：
    /// 合成内容与账号无关，退出登录时按目录整体清理）。
    static func tts(text: String, rate: String, voice: String?, format: String) -> String {
        Hashing.sha256Hex([text, rate, voice ?? "default", format].joined(separator: "|"))
    }

    /// 插画/形象键 = `sha256(image|materialId|version)`。
    static func image(materialId: String, version: Int) -> String {
        Hashing.sha256Hex(["image", materialId, String(version)].joined(separator: "|"))
    }

    /// 给已经拼好的键再加用户维度（例如 recent-* 快照）。
    static func scoped(_ key: String, userId: String) -> String {
        Hashing.sha256Hex("user=\(userId)|\(key)")
    }
}

/// 文件缓存底层操作：LRU 淘汰、过期清理、原子写。全部失败静默（缓存不能影响主流程）。
///
/// `AudioCache` / `ImageCache` / `RecordingCache` 与 `CacheJanitor` 共用同一套文件语义，
/// 避免“启动清理”和“运行期淘汰”两套实现漂移。
enum CacheFileStore {
    struct Entry {
        let url: URL
        let size: Int
        let modifiedAt: Date
    }

    static func ensureDirectory(_ directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            cacheLogger.debug("create cache directory failed")
        }
    }

    static func entries(in directory: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var result: [Entry] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else {
                continue
            }
            result.append(
                Entry(
                    url: url,
                    size: values.fileSize ?? 0,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }
        return result
    }

    static func totalSize(in directory: URL) -> Int {
        entries(in: directory).reduce(0) { $0 + $1.size }
    }

    @discardableResult
    static func writeAtomically(_ data: Data, to url: URL) -> Bool {
        ensureDirectory(url.deletingLastPathComponent())
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            cacheLogger.debug("write cache file failed")
            return false
        }
    }

    /// 命中缓存时把修改时间刷新成“现在”，作为 LRU 的访问时间。
    static func touch(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func removePartFiles(in directory: URL) {
        for entry in entries(in: directory) where entry.url.lastPathComponent.contains(".part") {
            remove(entry.url)
        }
    }

    static func removeFiles(in directory: URL, olderThan date: Date) {
        for entry in entries(in: directory) where entry.modifiedAt < date {
            remove(entry.url)
        }
    }

    /// 按 LRU（最后修改时间）淘汰到 `maxBytes` 以内。
    static func trim(_ directory: URL, to maxBytes: Int) {
        var entries = entries(in: directory).sorted { $0.modifiedAt < $1.modifiedAt }
        var total = entries.reduce(0) { $0 + $1.size }
        while total > maxBytes, !entries.isEmpty {
            let oldest = entries.removeFirst()
            remove(oldest.url)
            total -= oldest.size
        }
    }

    static func clearContents(of directory: URL) {
        for entry in entries(in: directory) {
            remove(entry.url)
        }
    }
}

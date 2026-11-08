import Foundation
import OSLog

private let audioCacheLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "storage")

/// TTS 音频字节缓存（契约 §3.11）：`Caches/TTS`，LRU 200MB。
///
/// 键 = `sha256(text|rate|voice|format)`（`CacheKey.tts`）。TTS 永久有效，
/// 只有超出体积上限时才按 LRU（最后访问时间）淘汰。
actor AudioCache {
    static let maxBytes = 200 * 1024 * 1024

    private let directory: URL

    init(directory: URL = CacheLocator.ttsDir()) {
        self.directory = directory
        CacheFileStore.ensureDirectory(directory)
    }

    /// 键计算入口：调用方拿到 TTS 字节前先用它算 key（不要在别处另写一套拼接规则）。
    static func ttsKey(text: String, rate: String, voice: String?, format: String) -> String {
        CacheKey.tts(text: text, rate: rate, voice: voice, format: format)
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
            audioCacheLogger.debug("tts cache store skipped")
            return
        }
        guard CacheFileStore.writeAtomically(data, to: fileURL(for: key)) else {
            return
        }
        if CacheFileStore.totalSize(in: directory) > Self.maxBytes {
            trim()
        }
    }

    /// 淘汰到 200MB 以内（启动清理与写入超限都会调用）。
    func trim() {
        CacheFileStore.trim(directory, to: Self.maxBytes)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(Hashing.sha256Hex(key) + ".audio")
    }
}

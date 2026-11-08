import Foundation
import OSLog

private let recordingCacheLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "storage")

/// 录音副本缓存（契约 §3.11）：`Caches/Recordings`，300MB / 7 天。
///
/// 用途：任务描述里“回放我的录音”（上传成功后按 `attemptId` 留一份副本）。
/// 文件名为 `sha256(id).m4a`，7 天按文件修改时间过期，超限按 LRU 淘汰。
actor RecordingCache {
    static let maxBytes = 300 * 1024 * 1024
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private let directory: URL

    init(directory: URL = CacheLocator.recordingsDir()) {
        self.directory = directory
        CacheFileStore.ensureDirectory(directory)
    }

    /// 保存一份录音副本并返回文件 URL。
    ///
    /// 契约签名不抛错：写失败时静默降级（返回目标 URL，但文件可能不存在），
    /// 页面按“可回放则播，不可回放则提示”处理，不能因缓存失败阻塞上传。
    func save(_ data: Data, id: String) -> URL {
        let url = fileURL(for: id)
        guard CacheFileStore.writeAtomically(data, to: url) else {
            recordingCacheLogger.debug("recording cache save failed")
            return url
        }
        trim()
        return url
    }

    func data(for id: String) -> Data? {
        try? Data(contentsOf: fileURL(for: id))
    }

    func fileURL(for id: String) -> URL {
        directory.appendingPathComponent(Hashing.sha256Hex(id) + ".m4a")
    }

    /// 先清 7 天前的副本，再按 300MB 上限 LRU 淘汰。
    func trim() {
        CacheFileStore.removeFiles(
            in: directory,
            olderThan: Date().addingTimeInterval(-Self.maxAge)
        )
        CacheFileStore.trim(directory, to: Self.maxBytes)
    }
}

import Foundation
import OSLog

private let janitorLogger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "storage")

/// 启动清理 + 用户级清理（契约 §3.11，architecture.md §7.2）。
///
/// 全部是同步文件操作、失败静默：启动清理绝不能拖慢或阻塞冷启动。
/// 淘汰语义与各缓存 actor 共用 `CacheFileStore`，避免两套规则漂移。
enum CacheJanitor {
    /// 启动时调用一次：建目录、清 `.part` 残留、清过期录音、把三个可淘汰缓存压回上限。
    static func cleanupOnBoot() {
        CacheLocator.ensureAll()

        let tts = CacheLocator.ttsDir()
        let images = CacheLocator.imagesDir()
        let recordings = CacheLocator.recordingsDir()
        let json = CacheLocator.jsonDir()

        CacheFileStore.removePartFiles(in: tts)
        CacheFileStore.removePartFiles(in: images)
        CacheFileStore.removePartFiles(in: recordings)
        CacheFileStore.removePartFiles(in: json)

        CacheFileStore.removeFiles(
            in: recordings,
            olderThan: Date().addingTimeInterval(-RecordingCache.maxAge)
        )

        CacheFileStore.trim(tts, to: AudioCache.maxBytes)
        CacheFileStore.trim(images, to: ImageCache.maxBytes)
        CacheFileStore.trim(recordings, to: RecordingCache.maxBytes)

        janitorLogger.debug("cache cleanup on boot finished")
    }

    /// 退出登录 / 会话失效：清掉 TTS、图片、录音副本与用户相关 JSON 快照。
    ///
    /// 语料快照本身不含个人数据，但按 architecture.md §7.2 的“统一走 clearUserScoped”
    /// 一并清掉，登录后首次进入会重新拉取。
    static func clearUserScoped() {
        CacheFileStore.clearContents(of: CacheLocator.ttsDir())
        CacheFileStore.clearContents(of: CacheLocator.imagesDir())
        CacheFileStore.clearContents(of: CacheLocator.recordingsDir())
        CacheFileStore.clearContents(of: CacheLocator.jsonDir())
        CacheLocator.ensureAll()
    }
}

import Foundation
import OSLog

private let corpusLogger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "storage")

/// 语料仓库（契约 §3.11）：`/sentences` 快照 24h、合并同 level 的并发请求、按 userId 分键。
///
/// 三层：
/// 1. 内存快照（进程内，命中即返回）；
/// 2. `DiskCache` 磁盘快照（24h TTL，冷启动/弱网可用）；
/// 3. 网络（`PracticeService.sentences`），并发请求通过 in-flight 任务合并成一次。
///
/// 语料保留策略（architecture.md §7.3）：无网时可浏览已缓存语料；首次安装无缓存显示空态。
actor CorpusRepository {
    static let defaultTTL: TimeInterval = 24 * 60 * 60

    private struct MemoryEntry {
        let expiresAt: Date
        let sentences: [SentenceDTO]
    }

    private let diskCache: DiskCache
    private let ttl: TimeInterval
    private let fetcher: @Sendable (String, String) async throws -> [SentenceDTO]

    private var memory: [String: MemoryEntry] = [:]
    private var inFlight: [String: Task<[SentenceDTO], any Error>] = [:]

    /// 生产装配：直接吃 A2 的 `PracticeService`。
    init(
        service: PracticeService,
        diskCache: DiskCache = DiskCache(),
        ttl: TimeInterval = CorpusRepository.defaultTTL
    ) {
        self.diskCache = diskCache
        self.ttl = ttl
        self.fetcher = { level, focus in
            let list = try await service.sentences(level: level, focus: focus)
            return list.sentences ?? []
        }
    }

    /// 测试/降级装配：注入任意取数闭包（不关心 `SentenceListDTO` 的形状）。
    init(
        diskCache: DiskCache = DiskCache(),
        ttl: TimeInterval = CorpusRepository.defaultTTL,
        fetcher: @escaping @Sendable (String, String) async throws -> [SentenceDTO]
    ) {
        self.diskCache = diskCache
        self.ttl = ttl
        self.fetcher = fetcher
    }

    /// 取某个 level/focus 的句子列表。
    ///
    /// - `force == true` 时跳过内存与磁盘快照，直接请求（下拉刷新）；
    /// - 同一 `(userId, level, focus)` 的并发请求只发一次网络请求；
    /// - 网络失败时**不**删除旧快照：页面可先展示旧数据再由上层提示“可能不是最新”。
    func sentences(level: String, focus: String, userId: String, force: Bool) async throws -> [SentenceDTO] {
        let key = Self.cacheKey(level: level, focus: focus, userId: userId)

        if !force {
            if let entry = memory[key], entry.expiresAt > Date() {
                return entry.sentences
            }
            if let cached = await diskCache.read([SentenceDTO].self, key: key) {
                memory[key] = MemoryEntry(expiresAt: Date().addingTimeInterval(ttl), sentences: cached)
                return cached
            }
        }

        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task { [fetcher] in
            try await fetcher(level, focus)
        }
        inFlight[key] = task

        do {
            let sentences = try await task.value
            inFlight[key] = nil
            memory[key] = MemoryEntry(
                expiresAt: Date().addingTimeInterval(ttl),
                sentences: sentences
            )
            await diskCache.write(sentences, key: key, ttl: ttl)
            return sentences
        } catch {
            inFlight[key] = nil
            corpusLogger.debug("corpus fetch failed")
            throw error
        }
    }

    /// 本地缓存是否可用（页面在无网时可据此决定是否禁用“换等级”）。
    func hasSnapshot(level: String, focus: String, userId: String) async -> Bool {
        let key = Self.cacheKey(level: level, focus: focus, userId: userId)
        if let entry = memory[key], entry.expiresAt > Date() {
            return true
        }
        return await diskCache.read([SentenceDTO].self, key: key) != nil
    }

    /// 主动失效（例如家长端新增自定义句子后）。
    func invalidate(level: String, focus: String, userId: String) async {
        let key = Self.cacheKey(level: level, focus: focus, userId: userId)
        memory[key] = nil
        inFlight[key] = nil
    }

    private static func cacheKey(level: String, focus: String, userId: String) -> String {
        CacheKey.make(["sentences", "level=\(level)", "focus=\(focus)"], userId: userId)
    }
}

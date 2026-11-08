import Foundation
import OSLog

private let diskCacheLogger = Logger(subsystem: "top.dreamsearch.english.coach", category: "storage")

/// 小体积 JSON 磁盘缓存（契约 §3.11）：带 TTL，落 `Application Support/json`。
///
/// 用途：语料快照（`CorpusRepository`）、诊断/最近练习等 `recent-*` 数据。
/// 过期读取时顺手删除；解码失败一律当成 miss（防御服务端/旧版本落盘格式漂移）。
actor DiskCache {
    private struct EncodableEnvelope<Payload: Encodable>: Encodable {
        let createdAt: Double
        let expiresAt: Double
        let payload: Payload
    }

    private struct DecodableEnvelope<Payload: Decodable>: Decodable {
        let createdAt: Double
        let expiresAt: Double
        let payload: Payload
    }

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL = CacheLocator.jsonDir()) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        CacheFileStore.ensureDirectory(directory)
    }

    /// 写 JSON + TTL。`ttl <= 0` 视为“立即过期”（等价于不写），避免语义含糊。
    func write<T: Encodable>(_ value: T, key: String, ttl: TimeInterval) {
        guard ttl > 0 else { return }
        let now = Date().timeIntervalSince1970
        let envelope = EncodableEnvelope(
            createdAt: now,
            expiresAt: now + ttl,
            payload: value
        )
        do {
            let data = try encoder.encode(envelope)
            guard CacheFileStore.writeAtomically(data, to: fileURL(for: key)) else {
                diskCacheLogger.debug("disk cache write skipped")
                return
            }
        } catch {
            diskCacheLogger.debug("disk cache encode failed")
        }
    }

    func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let envelope = try? decoder.decode(DecodableEnvelope<T>.self, from: data) else {
            // 旧格式/半截文件：删掉当 miss，下次重写。
            CacheFileStore.remove(url)
            return nil
        }
        guard envelope.expiresAt > Date().timeIntervalSince1970 else {
            CacheFileStore.remove(url)
            return nil
        }
        return envelope.payload
    }

    func clearAll() {
        CacheFileStore.clearContents(of: directory)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(Hashing.sha256Hex(key) + ".json")
    }
}

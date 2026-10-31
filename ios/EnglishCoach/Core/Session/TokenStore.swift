import Foundation
import OSLog
import Security

/// 一次性保存在内存里的凭据快照。token 只从 Keychain 读出、用完即弃，
/// 不会出现在 UserDefaults、日志或崩溃信息里。
struct StoredTokens: Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    /// token 与服务器绑定：换 base URL 后旧 token 不可复用（见 ADR-0003）。
    let baseURL: String?

    func hasUsableAccessToken(leeway: TimeInterval = 30) -> Bool {
        !accessToken.isEmpty && expiresAt.timeIntervalSinceNow > leeway
    }
}

protocol TokenStoring: Sendable {
    func load() async -> StoredTokens?
    func save(_ tokens: StoredTokens) async throws
    func clear() async
}

/// Keychain 存取。`actor` 保证读、写、清不会互相穿插。
///
/// 可访问性用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`：
/// 设备重启后首次解锁前不可读（后台任务无需 token），换机/备份不迁移。
actor TokenStore: TokenStoring {
    private static let service = "top.dreamsearch.englishcoach.auth"
    private let logger = Logger(subsystem: "top.dreamsearch.englishcoach", category: "session")

    private enum Account: String, CaseIterable {
        case accessToken
        case refreshToken
        case tokenMeta
    }

    private struct TokenMeta: Codable {
        /// Unix 秒；避免 Date 编码策略在读写两端不一致。
        let expiresAt: TimeInterval
        let baseURL: String?
    }

    func load() async -> StoredTokens? {
        let access = read(.accessToken) ?? ""
        let refresh = read(.refreshToken) ?? ""
        guard !access.isEmpty || !refresh.isEmpty else { return nil }

        var meta: TokenMeta?
        if let raw = read(.tokenMeta), let data = raw.data(using: .utf8) {
            meta = try? JSONDecoder().decode(TokenMeta.self, from: data)
        }
        let expiresAt = meta.map { Date(timeIntervalSince1970: $0.expiresAt) } ?? .distantPast
        return StoredTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresAt,
            baseURL: meta?.baseURL
        )
    }

    func save(_ tokens: StoredTokens) async throws {
        let meta = TokenMeta(expiresAt: tokens.expiresAt.timeIntervalSince1970, baseURL: tokens.baseURL)
        guard let metaData = try? JSONEncoder().encode(meta),
              let metaText = String(data: metaData, encoding: .utf8)
        else {
            throw APIError.credentialStorage
        }

        let statuses = [
            write(tokens.accessToken, account: .accessToken),
            write(tokens.refreshToken, account: .refreshToken),
            write(metaText, account: .tokenMeta),
        ]
        guard statuses.allSatisfy({ $0 == errSecSuccess }) else {
            // 部分写入会导致“有 access 没 refresh”的坏状态，直接整体清掉要求重登。
            deleteAll()
            throw APIError.credentialStorage
        }
    }

    func clear() async {
        deleteAll()
    }

    // MARK: - Keychain 原子操作（全部在 actor 内串行）

    private func baseQuery(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    private func read(_ account: Account) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            // 只记录错误码，不记录 token 内容。
            logger.error("Keychain read \(account.rawValue, privacy: .public) failed: \(status)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func write(_ value: String, account: Account) -> OSStatus {
        let query = baseQuery(account)
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return errSecSuccess
        }
        guard updateStatus == errSecItemNotFound else {
            logger.error("Keychain update \(account.rawValue, privacy: .public) failed: \(updateStatus)")
            return updateStatus
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.error("Keychain add \(account.rawValue, privacy: .public) failed: \(addStatus)")
        }
        return addStatus
    }

    private func deleteAll() {
        for account in Account.allCases {
            let status = SecItemDelete(baseQuery(account) as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                logger.error("Keychain delete \(account.rawValue, privacy: .public) failed: \(status)")
            }
        }
    }
}

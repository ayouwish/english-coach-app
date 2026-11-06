import Foundation

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

/// Keychain 存取（`actor` 保证读、写、清不会互相穿插）。
///
/// 底层只通过 `KeychainStore` 碰 Security 框架（service `top.dreamsearch.englishcoach.auth`，
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）。对外契约保持不变（契约 §3.9）。
actor TokenStore: TokenStoring {
    private let keychain: KeychainStore

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

    init(keychain: KeychainStore = .shared) {
        self.keychain = keychain
    }

    func load() async -> StoredTokens? {
        let access = keychain.read(Account.accessToken.rawValue) ?? ""
        let refresh = keychain.read(Account.refreshToken.rawValue) ?? ""
        guard !access.isEmpty || !refresh.isEmpty else { return nil }

        var meta: TokenMeta?
        if let raw = keychain.read(Account.tokenMeta.rawValue), let data = raw.data(using: .utf8) {
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

        do {
            try keychain.write(tokens.accessToken, account: Account.accessToken.rawValue)
            try keychain.write(tokens.refreshToken, account: Account.refreshToken.rawValue)
            try keychain.write(metaText, account: Account.tokenMeta.rawValue)
        } catch {
            // 部分写入会导致“有 access 没 refresh”的坏状态，直接整体清掉要求重登。
            deleteAll()
            throw APIError.credentialStorage
        }
    }

    func clear() async {
        deleteAll()
    }

    private func deleteAll() {
        keychain.deleteAll(accounts: Account.allCases.map(\.rawValue))
    }
}

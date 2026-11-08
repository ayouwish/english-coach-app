import Foundation
import OSLog
import Security

/// Keychain 低层封装：只做 `kSecClassGenericPassword` 的读 / 写 / 删。
///
/// 约定（`ios/docs/architecture.md` §8）：
/// - 全 App 只有一个 service：`top.dreamsearch.english.coach.auth`；
/// - 可访问性固定 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`：
///   设备重启后首次解锁前不可读（后台任务不需要凭据），换机 / 备份不迁移；
/// - 只接受 `String`，序列化由调用方负责（`TokenStore` 存 token，`CredentialStore` 存“记住登录”）；
/// - token / 密码绝不写 `UserDefaults`、绝不出现在日志里（日志只记 OSStatus）。
struct KeychainStore: Sendable {
    static let service = "top.dreamsearch.english.coach.auth"
    static let shared = KeychainStore(service: KeychainStore.service)

    private let serviceName: String
    private let logger = Logger(subsystem: "top.dreamsearch.english.coach", category: "session")

    init(service: String = KeychainStore.service) {
        self.serviceName = service
    }

    /// 读取指定 account 的 UTF-8 字符串；不存在或读取失败返回 nil。
    func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            // 只记录错误码，不记录内容。
            logger.error("keychain read \(account, privacy: .public) failed: \(status)")
            return nil
        }
        return text
    }

    /// 写入（已存在则更新）。失败抛 `APIError.credentialStorage`，调用方负责兜底清理。
    func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            logger.error("keychain update \(account, privacy: .public) failed: \(updateStatus)")
            throw APIError.credentialStorage
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logger.error("keychain add \(account, privacy: .public) failed: \(addStatus)")
            throw APIError.credentialStorage
        }
    }

    /// 删除单个 account；不存在视为成功。
    func delete(_ account: String) {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("keychain delete \(account, privacy: .public) failed: \(status)")
        }
    }

    /// 批量删除（token 的三个 account 一起清）。
    func deleteAll(accounts: [String]) {
        for account in accounts {
            delete(account)
        }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
    }
}

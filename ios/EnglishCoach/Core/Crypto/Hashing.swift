import CryptoKit
import Foundation

enum Hashing {
    /// 用于本地缓存键（TTS、录音文件名等），不是安全边界。
    static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", Int($0)) }.joined()
    }
}

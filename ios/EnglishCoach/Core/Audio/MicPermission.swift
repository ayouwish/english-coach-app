import AVFAudio
import Foundation
import UIKit

/// 麦克风权限三态（契约 §3.10）。
///
/// 与 `AVAudioApplication.recordPermission` 一一对应：`undetermined → .unknown`。
/// 系统对麦克风只有 granted / denied / undetermined 三态，**没有** `.restricted`；
/// 家长控制/MDM 拒绝时系统返回 denied，所以引导卡按“去设置”处理即可（audio.md §2.3）。
enum MicPermission: Sendable, Equatable {
    case unknown
    case granted
    case denied

    /// 当前状态（每次都重新读系统，不缓存：用户可能刚从设置页返回）。
    static func current() -> MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .unknown
        @unknown default:
            return .denied
        }
    }

    /// 请求权限。已决定（granted/denied）时不再弹系统框，直接返回缓存状态。
    ///
    /// 用 continuation 包 `requestRecordPermission(completionHandler:)`：
    /// 与 audio.md §2.2 的写法一致，不依赖系统是否提供 async 重载。
    static func request() async -> MicPermission {
        let status = current()
        guard status == .unknown else {
            return status
        }
        let granted: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return granted ? .granted : current()
    }

    /// 跳到本 App 的系统设置页（audio.md §2.3 的“去设置”）。
    ///
    /// 从设置返回后，页面应在 `scenePhase == .active` 时重新调用 `current()`，
    /// 不要复用旧值。
    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

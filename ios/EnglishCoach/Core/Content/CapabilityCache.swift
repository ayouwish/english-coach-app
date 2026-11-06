import Foundation
import Observation

/// `/api/health` 的 voice 能力开关（与网络 DTO 解耦的稳定快照）。
///
/// 客户端按能力隐藏/禁用入口（`ios/README.md` §2.4）：
/// - `image == false` → 不显示“给我画一张”；
/// - `ocr == false` → 不显示拍照识别；
/// - `avatarPresets == false` → 形象库入口提示不可用。
struct SiteCapabilities: Sendable, Equatable {
    var image: Bool
    var ocr: Bool
    var avatarPresets: Bool
    var phonemeLevel: Bool
    var prosody: Bool
    var intonationCurve: Bool

    /// 缺省全部可用：宁可让用户点、服务端返回可读错误，也不要误藏功能（HOS 语义）。
    static let defaults = SiteCapabilities(
        image: true,
        ocr: true,
        avatarPresets: true,
        phonemeLevel: true,
        prosody: true,
        intonationCurve: true
    )
}

/// `/api/health` 能力开关的进程内缓存（只拉一次）。
///
/// 拉取失败按“全部可用”处理（入口照常显示，服务端 503 给可读提示）；
/// `reload()` 只把 `isLoaded` 复位，下次 `ensure` 重新拉。数据来源通过 `loader` 注入，
/// 本类型不直接依赖 `PracticeService` / `HealthDTO`。
@MainActor
@Observable
final class CapabilityCache {
    private(set) var isLoaded = false
    private(set) var capabilities = SiteCapabilities.defaults

    var image: Bool { capabilities.image }
    var ocr: Bool { capabilities.ocr }
    var avatarPresets: Bool { capabilities.avatarPresets }
    var phonemeLevel: Bool { capabilities.phonemeLevel }
    var prosody: Bool { capabilities.prosody }
    var intonationCurve: Bool { capabilities.intonationCurve }

    /// 直接用一次 `/health` 的结果整体替换（服务状态页“强制刷新”也走这里）。
    func apply(_ capabilities: SiteCapabilities) {
        self.capabilities = capabilities
        isLoaded = true
    }

    /// 首次用到时拉一次；失败保留默认（全部可用）并标记已加载，避免每次页面出现都重试。
    func ensure(loader: @MainActor () async -> SiteCapabilities?) async {
        guard !isLoaded else { return }
        defer { isLoaded = true }
        if let latest = await loader() {
            apply(latest)
        }
    }

    /// 强制下次重新拉取（设置页 / 服务状态页手动刷新）。
    func reload() {
        isLoaded = false
    }

    /// 退出 / 换账号时回到默认值。
    func reset() {
        capabilities = .defaults
        isLoaded = false
    }
}

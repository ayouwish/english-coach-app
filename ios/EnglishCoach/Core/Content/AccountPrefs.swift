import Foundation
import Observation

/// 账号偏好快照：与网络 DTO 解耦，便于缓存、单测与页面读取。
///
/// 字段来源（`GET /api/settings`，见 HOS `core/content/AccountPrefs.ets`）：
/// - `prefs.ttsVoice` / `prefs.ttsRate` / `prefs.showWordIpa`；
/// - `user.storySentences` / `user.autoIllustrate`。
struct AccountPrefsSnapshot: Sendable, Equatable {
    var ttsVoice: String
    var ttsRate: String
    var showWordIpa: Bool
    var storySentences: Int
    var autoIllustrate: Bool

    /// 服务端默认值：音色空 = 服务端默认；音标默认开（成人/儿童一致）。
    static let defaults = AccountPrefsSnapshot(
        ttsVoice: "",
        ttsRate: "",
        showWordIpa: true,
        storySentences: 0,
        autoIllustrate: false
    )
}

/// 账号偏好缓存（进程内只拉一次，设置页保存后 `reload()`）。
///
/// 为什么单独缓存：TTS 示范音语速/音色、故事句数、自动插画都要读它，但每次调接口太慢。
/// 拉取失败不阻塞主流程（保留默认值 / 上一次缓存）。数据来源通过 `loader` 注入，
/// 本类型不直接依赖 `AccountService`，避免 Core/Content 与网络层的类型耦合。
@MainActor
@Observable
final class AccountPrefs {
    private(set) var isLoaded = false
    private(set) var snapshot = AccountPrefsSnapshot.defaults

    var ttsVoice: String { snapshot.ttsVoice }
    var ttsRate: String { snapshot.ttsRate }
    var showWordIpa: Bool { snapshot.showWordIpa }
    var storySentences: Int { snapshot.storySentences }
    var autoIllustrate: Bool { snapshot.autoIllustrate }

    /// 用一次 `/settings` 的结果整体替换（SessionStore.reloadUser 会调用）。
    func apply(_ snapshot: AccountPrefsSnapshot) {
        self.snapshot = snapshot
        isLoaded = true
    }

    /// 退出 / 换账号时回到默认值（下一个账号重新拉取）。
    func reset() {
        snapshot = .defaults
        isLoaded = false
    }

    /// 首次进入某个页面时调用：只拉一次，失败静默用默认值（与 HOS `ensure()` 一致）。
    func ensure(loader: @MainActor () async -> AccountPrefsSnapshot?) async {
        guard !isLoaded else { return }
        isLoaded = true
        if let latest = await loader() {
            apply(latest)
        }
    }

    /// 设置页保存成功后调用：强制重新拉取。
    func reload(loader: @MainActor () async -> AccountPrefsSnapshot?) async {
        isLoaded = true
        if let latest = await loader() {
            apply(latest)
        }
    }

    // MARK: - 读取便利（HOS `AccountPrefs.voice()` / `rateOr(fallback:)`）

    /// 音色 id（空 = 服务端默认）。
    func voice() -> String {
        snapshot.ttsVoice
    }

    /// 语速：账号偏好优先，否则用传入默认值。
    func rateOr(_ fallback: String) -> String {
        snapshot.ttsRate.isEmpty ? fallback : snapshot.ttsRate
    }
}

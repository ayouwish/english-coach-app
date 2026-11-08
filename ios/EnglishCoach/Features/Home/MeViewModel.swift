import Foundation
import Observation

/// 「我的」页状态：账号摘要 + 刷新 + 退出登录。
///
/// 页面只读 `SessionStore` 的会话事实（user/usage/capabilities）；本 VM 只做动作，
/// 不再复制一份用户数据，避免两处状态不一致。
@MainActor
@Observable
final class MeViewModel {
    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore

    private(set) var isRefreshing = false
    private(set) var isSigningOut = false
    private(set) var notice: String?

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
    }

    var isChild: Bool {
        session.isChild
    }

    var user: UserProfile? {
        session.user
    }

    var displayName: String {
        let name = session.user?.displayName ?? ""
        return name.isEmpty ? "我的账号" : name
    }

    var avatarEmoji: String {
        session.user?.avatarEmoji ?? "👤"
    }

    var roleText: String {
        guard let user = session.user else { return "学习者" }
        if user.isChild {
            return "小朋友 · \(user.normalizedLevel)"
        }
        return (user.role == .parent ? "家长" : "学习者") + " · \(user.normalizedLevel)"
    }

    /// 今日用量：`今日 12 / 20 分钟`（无 usage 时显示“—”，不编造 0）。
    var usageText: String {
        guard let usage = session.usage else { return "今日用量统计中" }
        let minutes = usage.minutes ?? 0
        let limit = usage.limitMinutes ?? 0
        let used = Self.minutesText(minutes)
        if limit > 0 {
            return "今日 \(used) / \(limit) 分钟"
        }
        return "今日 \(used) 分钟"
    }

    var remainingText: String? {
        guard let usage = session.usage else { return nil }
        if usage.exceeded == true {
            return "今日时长已达上限"
        }
        guard let remaining = usage.remainingMinutes, remaining > 0 else { return nil }
        return "剩余 \(Self.minutesText(remaining)) 分钟"
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await session.reloadUser()
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await session.signOut()
        CacheJanitor.clearUserScoped()
        notice = "已在本机退出；服务器上的登录凭证可能仍未过期。"
    }

    static func minutesText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

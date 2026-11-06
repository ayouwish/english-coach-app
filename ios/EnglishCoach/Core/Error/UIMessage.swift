import Foundation

/// 用户可见的错误文案（契约 §3.13）。
///
/// 页面只渲染 `UIMessage`，不自己拼“网络错误”之类的中文；文案统一由 `ErrorMapper` 生产
/// （`ios/docs/port-contract.md` §2.4：错误文案唯一来源）。
/// 本类型是纯数据、不依赖 SwiftUI（Core/Error 只做映射）。
struct UIMessage: Sendable, Equatable {
    let title: String
    let body: String?
    let actionTitle: String?
    let action: Action?
    let isRetryable: Bool
    /// 客户端短 id：同时写 OSLog，家长反馈时用于定位（日志不含凭据/邮箱/音频）。
    let diagnosticID: String?

    enum Action: Sendable, Equatable {
        case retry
        case relogin
        case openSettings
        case back
        case none
    }

    /// 无需展示（`cancelled` 等）：页面应直接跳过错误态。
    var isSilent: Bool {
        title.isEmpty && (body ?? "").isEmpty
    }

    /// `cancelled` 的规范值：不弹任何 UI。
    static func silent() -> UIMessage {
        UIMessage(
            title: "",
            body: nil,
            actionTitle: nil,
            action: Action.none,
            isRetryable: false,
            diagnosticID: nil
        )
    }
}

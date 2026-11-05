import CoreGraphics

/// 角色能力（契约 §3.9）：页面与组件只读这里，**禁止**在 View 里写 `role == .child`。
///
/// 归属说明：本类型从 `Core/DesignSystem/Tokens/Theme.swift` 抽出到 `Core/Session`，
/// 因为“儿童/成人”是会话事实（`SessionStore.user`）而不是样式；SwiftUI 环境注入仍留在
/// `Theme.swift`（组件读 `\.roleCapabilities`，M0 遗留的 `\.capabilities` 是同一存储的别名）。
struct RoleCapabilities: Sendable, Equatable {
    // MARK: 契约 §3.9（字段名与语义不得改）

    let isChild: Bool
    var canSeeIPA: Bool
    var showsNumericScore: Bool
    var usesEncouragementOnly: Bool
    /// 最小点击区：儿童 56pt，成人 44pt（`ios/docs/port-contract.md` §2.10）。
    var minTapTarget: CGFloat

    // MARK: 排版与既有能力（M0 在用，保留以免打断既有页面）

    /// 正文缩放：儿童 1.15（`Typography` / `AppFont` 读取）。
    let bodyFontScale: Double
    let canChangeLevel: Bool
    let prefersSlowDemo: Bool
    let showsLowScoreWarning: Bool
    let canOpenParentPanel: Bool
    let canEditServerURL: Bool

    /// M0 兼容别名：旧代码读 `caps.showsIPA`，语义等同契约的 `canSeeIPA`。
    var showsIPA: Bool { canSeeIPA }

    static let adult = RoleCapabilities(
        isChild: false,
        canSeeIPA: true,
        showsNumericScore: true,
        usesEncouragementOnly: false,
        minTapTarget: 44,
        bodyFontScale: 1.0,
        canChangeLevel: true,
        prefersSlowDemo: false,
        showsLowScoreWarning: true,
        canOpenParentPanel: true,
        canEditServerURL: true
    )

    static let child = RoleCapabilities(
        isChild: true,
        canSeeIPA: false,
        showsNumericScore: false,
        usesEncouragementOnly: true,
        minTapTarget: 56,
        bodyFontScale: 1.15,
        canChangeLevel: false,
        prefersSlowDemo: true,
        showsLowScoreWarning: false,
        canOpenParentPanel: false,
        canEditServerURL: false
    )

    static func make(isChild: Bool) -> RoleCapabilities {
        isChild ? .child : .adult
    }
}

import SwiftUI

/// 角色能力。页面与组件只读这里，禁止在 View 里散落 `role == .child` 判断。
struct RoleCapabilities: Sendable, Equatable {
    let isChild: Bool
    let showsIPA: Bool
    let showsNumericScore: Bool
    let minTapTarget: CGFloat
    let bodyFontScale: Double
    let canChangeLevel: Bool
    let prefersSlowDemo: Bool

    static let adult = RoleCapabilities(
        isChild: false,
        showsIPA: true,
        showsNumericScore: true,
        minTapTarget: 44,
        bodyFontScale: 1.0,
        canChangeLevel: true,
        prefersSlowDemo: false
    )

    static let child = RoleCapabilities(
        isChild: true,
        showsIPA: false,
        showsNumericScore: false,
        minTapTarget: 56,
        bodyFontScale: 1.15,
        canChangeLevel: false,
        prefersSlowDemo: true
    )

    static func make(isChild: Bool) -> RoleCapabilities {
        isChild ? .child : .adult
    }
}

private struct CapabilitiesKey: EnvironmentKey {
    static let defaultValue: RoleCapabilities = .adult
}

extension EnvironmentValues {
    var capabilities: RoleCapabilities {
        get { self[CapabilitiesKey.self] }
        set { self[CapabilitiesKey.self] = newValue }
    }
}

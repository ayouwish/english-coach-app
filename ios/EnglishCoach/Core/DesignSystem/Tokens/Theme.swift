import SwiftUI

// `RoleCapabilities` 已抽到 `Core/Session/RoleCapabilities.swift`（契约 §3.9，A4）：
// 全仓只有那一处类型定义，本文件只保留 SwiftUI 环境注入。
//
// 规范键：组件/页面统一读 `\.roleCapabilities`。
// 兼容键：M0 的 `\.capabilities` 与它共享同一个 `CapabilitiesKey` 存储（读写完全等价），
// 仅为既有 Features/Auth、Features/Practice 暂不炸；新代码一律用 `\.roleCapabilities`。

private struct CapabilitiesKey: EnvironmentKey {
    static let defaultValue: RoleCapabilities = .adult
}

extension EnvironmentValues {
    /// 角色能力（规范键）。
    var roleCapabilities: RoleCapabilities {
        get { self[CapabilitiesKey.self] }
        set { self[CapabilitiesKey.self] = newValue }
    }

    /// M0 兼容别名：与 `roleCapabilities` 是同一份存储，取值永远一致。
    var capabilities: RoleCapabilities {
        get { self[CapabilitiesKey.self] }
        set { self[CapabilitiesKey.self] = newValue }
    }
}

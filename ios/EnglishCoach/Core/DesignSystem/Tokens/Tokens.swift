import SwiftUI

/// 设计令牌唯一来源。**hex 只允许出现在本文件**，其它文件只引用语义名
/// （取值对齐仓库根 `docs/design-tokens.md` 与 `ios/docs/design-system.md`）。
enum Tokens {
    enum Colors {
        static let canvas = Color(hex: 0xF5F7FF)
        static let surfaceCard = Color(hex: 0xFFFFFF)
        static let surfaceMuted = Color(hex: 0xECEBFF)
        static let surfaceSunken = Color(hex: 0xF1F5F9)

        static let primary = Color(hex: 0x5B5BD6)
        static let primaryPressed = Color(hex: 0x4A4AC4)
        static let primaryDisabled = Color(hex: 0xC7D2FE)
        static let onPrimary = Color(hex: 0xFFFFFF)

        static let textPrimary = Color(hex: 0x1F2937)
        static let textSecondary = Color(hex: 0x6B7280)
        static let textTertiary = Color(hex: 0x9CA3AF)

        static let borderSubtle = Color(hex: 0xE5E7EB)
        static let success = Color(hex: 0x16A34A)
        static let successText = Color(hex: 0x15803D)
        static let warning = Color(hex: 0xB45309)
        static let danger = Color(hex: 0xDC2626)

        static let childAccent = Color(hex: 0xF59E0B)
        static let childAccentSoft = Color(hex: 0xFEF3C7)
        static let childAccentText = Color(hex: 0x78350F)
        static let recordingRed = Color(hex: 0xEF4444)
        static let playbackBlue = Color(hex: 0x0EA5E9)

        // 分数色阶仅成人使用；孩子只有星级。
        static let scoreExcellent = Color(hex: 0x16A34A)
        static let scoreGood = Color(hex: 0x5B5BD6)
        static let scoreFair = Color(hex: 0xB45309)
        static let scoreWeak = Color(hex: 0xDC2626)

        static let overlayScrim = Color(hex: 0x0F172A).opacity(0.35)
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        /// 输入框、次级按钮（Web 按钮 0.9rem ≈ 14）。
        static let button: CGFloat = 14
        /// 卡片、主按钮（Web 卡片 1.25rem = 20）。
        static let large: CGFloat = 20
        /// Sheet、底部弹层（Web 1.75rem = 28）。
        static let xLarge: CGFloat = 28
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let s2: CGFloat = 2
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
        static let s40: CGFloat = 40
    }

    enum Shadow {
        static let cardPrimary = Color(hex: 0x1F2937).opacity(0.06)
        static let cardTint = Color(hex: 0x5B5BD6).opacity(0.04)
        static let floatingTint = Color(hex: 0x5B5BD6).opacity(0.12)
        static let buttonTint = Color(hex: 0x5B5BD6).opacity(0.28)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

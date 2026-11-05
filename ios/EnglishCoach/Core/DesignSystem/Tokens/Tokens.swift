import SwiftUI

/// 设计令牌唯一来源。**hex 只允许出现在本文件**，其它文件只引用语义名。
///
/// 取值对齐仓库根 `docs/design-tokens.md`（跨端唯一权威，从 Web CSS 提取）与
/// `ios/docs/design-system.md`；与 HOS `design/DesignTokens.ets` + `resources/base/element/color.json` 同源：
/// - 背景 `#F5F7FF`、主色 `#5B5BD6`、卡片 20、弹层 28、按钮 14；
/// - 文字/状态色区分「填充值」与「文字值」：填充用 `success/warning/danger`，
///   正文用对比度更高的 `successText/warningText/dangerText`（正文 ≥4.5:1）。
///
/// 约定：页面只写 `AppFont.*`、`Tokens.Colors.*`、`Tokens.Spacing.*`、`Tokens.Radius.*`，
/// 不写魔法数字、不写十六进制。
enum Tokens {

    // MARK: - 颜色

    enum Colors {
        // 背景与表面
        /// 页面背景（Web `--bg`，浅蓝）。
        static let canvas = Color(hex: 0xF5F7FF)
        /// 卡片、输入框、Sheet 背景。
        static let surfaceCard = Color(hex: 0xFFFFFF)
        /// 次级按钮底、选中态底、标签底（Web `primarySoft`）。
        static let surfaceMuted = Color(hex: 0xECEBFF)
        /// 分组长条、骨架底色（HOS `ec_surface_alt`）。
        static let surfaceSunken = Color(hex: 0xF1F3FF)

        // 主色
        static let primary = Color(hex: 0x5B5BD6)
        static let primaryPressed = Color(hex: 0x4A4AC4)
        static let primaryDisabled = Color(hex: 0xC7D2FE)
        static let onPrimary = Color(hex: 0xFFFFFF)

        // 文字（ink / muted，HOS `ec_ink` `ec_muted`）
        static let textPrimary = Color(hex: 0x1B1F3B)
        static let textSecondary = Color(hex: 0x6B7290)
        /// 占位符、时间戳；不承载关键信息（对比度 ≈2.8:1，仅装饰）。
        static let textTertiary = Color(hex: 0x9CA3AF)
        /// 深色表面上的文字（主色渐变、录音球内）。
        static let textOnAccent = Color(hex: 0xFFFFFF)

        // 描边与聚焦
        static let borderSubtle = Color(hex: 0xE3E6F3)
        static let borderFocus = Color(hex: 0xA5B4FC)

        // 状态：填充色 / 文字色 / 浅底（三档，HOS 同名三组）
        static let success = Color(hex: 0x16A34A)
        static let successText = Color(hex: 0x15803D)
        static let successBackground = Color(hex: 0xF0FDF4)

        static let warning = Color(hex: 0xF59E0B)
        static let warningText = Color(hex: 0xB45309)
        static let warningBackground = Color(hex: 0xFFF3D6)

        static let danger = Color(hex: 0xEF4444)
        static let dangerText = Color(hex: 0xB91C1C)
        static let dangerBackground = Color(hex: 0xFEF2F2)

        static let info = Color(hex: 0x0EA5E9)

        // 分数色阶（**仅成人**；孩子只映射星级，永不用 scoreWeak）
        static let scoreExcellent = Color(hex: 0x16A34A)
        static let scoreGood = Color(hex: 0x5B5BD6)
        static let scoreFair = Color(hex: 0xB45309)
        static let scoreWeak = Color(hex: 0xDC2626)

        // 品牌与儿童
        static let brandGradientStart = Color(hex: 0x5B5BD6)
        static let brandGradientEnd = Color(hex: 0x7C7CE6)
        /// 孩子模式星星、坚持天数、庆祝。
        static let childAccent = Color(hex: 0xF59E0B)
        static let childAccentSoft = Color(hex: 0xFEF3C7)
        /// 琥珀底上的文字（≈8:1）。
        static let childAccentText = Color(hex: 0x78350F)
        /// 孩子模式次要强调（如「听一听」）。
        static let childSky = Color(hex: 0x0EA5E9)

        // 词级色块（成年四级 / 儿童两色）
        static let wordGoodBackground = Color(hex: 0xECFDF5)
        static let wordGoodText = Color(hex: 0x15803D)
        static let wordFairBackground = Color(hex: 0xFEF3C7)
        static let wordFairText = Color(hex: 0x78350F)
        static let wordWeakBackground = Color(hex: 0xFEF2F2)
        static let wordWeakText = Color(hex: 0xB91C1C)

        // 录音与播放
        static let recordingRed = Color(hex: 0xEF4444)
        static let playbackBlue = Color(hex: 0x0EA5E9)

        // 模态遮罩（HOS `ec_overlay` #5C1B1F3B）
        static let overlayScrim = Color(hex: 0x1B1F3B).opacity(0.36)
    }

    // MARK: - 圆角

    enum Radius {
        /// 标签、Chip、输入框内小元素。
        static let small: CGFloat = 8
        /// 输入框、次级按钮（Web 按钮 0.9rem ≈ 14）。
        static let medium: CGFloat = 14
        /// 输入框、次级按钮（语义别名，与 `medium` 同值）。
        static let button: CGFloat = 14
        /// 卡片、主按钮（Web 卡片 1.25rem = 20）。
        static let large: CGFloat = 20
        /// Sheet、底部弹层（Web 1.75rem = 28）。
        static let xLarge: CGFloat = 28
        static let pill: CGFloat = 999

        // 契约 §3.12 的短名别名。
        static var sm: CGFloat { small }
        static var md: CGFloat { medium }
        static var lg: CGFloat { large }
        static var xl: CGFloat { xLarge }
    }

    // MARK: - 间距

    enum Spacing {
        static let s2: CGFloat = 2
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        /// 页面左右边距（孩子 20，由页面按 `caps.isChild` 选择）。
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
        static let s40: CGFloat = 40
        /// 登录页/成就页大留白（HOS `EcSpace.x12`）。
        static let s48: CGFloat = 48

        /// 间距阶梯（索引 1...8 → 4/8/12/16/20/24/32/40，契约 §3.12 的 `Tokens.space[1...8]`）。
        static let scale: [CGFloat] = [s4, s8, s12, s16, s20, s24, s32, s40]

        /// 按阶梯取值（1...8，越界自动夹取）。
        static func space(_ step: Int) -> CGFloat {
            let index = min(max(step, 1), scale.count) - 1
            return scale[index]
        }

        /// 页面水平边距：成人 16、孩子 20（design-system §4）。
        static func pageMargin(isChild: Bool) -> CGFloat {
            isChild ? s20 : s16
        }
    }

    // MARK: - 阴影与层级

    enum Shadow {
        static let cardPrimary = Color(hex: 0x1B1F3B).opacity(0.06)
        static let cardTint = Color(hex: 0x5B5BD6).opacity(0.04)
        static let floatingTint = Color(hex: 0x5B5BD6).opacity(0.12)
        static let buttonTint = Color(hex: 0x5B5BD6).opacity(0.28)
    }

    /// 层级（阴影半径/位移/透明度集中在这里，避免页面写死）。
    enum Elevation {
        /// 卡片：几乎不可见，靠留白分层。
        static let cardRadius: CGFloat = 3
        static let cardY: CGFloat = 1
        /// 悬浮层（录音球、浮动按钮）。
        static let floatingRadius: CGFloat = 24
        static let floatingY: CGFloat = 8
        /// 主按钮。
        static let buttonRadius: CGFloat = 8
        static let buttonY: CGFloat = 6
    }

    // MARK: - 分数色档

    /// 分数 → 语义色/星级。**唯一实现**：`Features/Shared/ScorePresenter` 与
    /// `Core/DesignSystem/Components/ScoreViews` 都从里取色，保证 Core 不反向依赖 Features。
    enum Score {
        enum Tone: Sendable, Equatable {
            case excellent
            case good
            case fair
            case weak
        }

        /// 成人四级色阶；null/非有限值返回 nil（展示层用「—」与三级灰）。
        static func tone(for score: Double?) -> Tone? {
            guard let score, score.isFinite else { return nil }
            if score >= 85 { return .excellent }
            if score >= 70 { return .good }
            if score >= 60 { return .fair }
            return .weak
        }

        /// 成人：85+ 绿、70+ 主色、60+ 琥珀、<60 红（<60 标红仅成人）。
        /// 孩子：85+ 绿、60+ 主色、<60 用琥珀鼓励色，**永不出现红色**。
        static func color(for score: Double?, isChild: Bool) -> Color {
            guard let score, score.isFinite else { return Colors.textTertiary }
            if isChild {
                if score >= 85 { return Colors.success }
                if score >= 60 { return Colors.primary }
                return Colors.childAccent
            }
            switch tone(for: score) {
            case .excellent: return Colors.scoreExcellent
            case .good: return Colors.scoreGood
            case .fair: return Colors.scoreFair
            case .weak: return Colors.scoreWeak
            case nil: return Colors.textTertiary
            }
        }

        /// 分数的浅色背景（Badge/Chip 底），孩子模式一律用琥珀软底，避免「低分=错误」暗示。
        static func softBackground(for score: Double?, isChild: Bool) -> Color {
            guard let score, score.isFinite else { return Colors.surfaceSunken }
            if isChild { return Colors.childAccentSoft }
            switch tone(for: score) {
            case .excellent: return Colors.successBackground
            case .good: return Colors.surfaceMuted
            case .fair: return Colors.warningBackground
            case .weak: return Colors.dangerBackground
            case nil: return Colors.surfaceSunken
            }
        }

        /// 星级：85+ 三星、70+ 两星、其余一星；null 给一星（不展示「失败」）。
        static func stars(for score: Double?) -> Int {
            guard let score, score.isFinite else { return 1 }
            if score >= 85 { return 3 }
            if score >= 70 { return 2 }
            return 1
        }

        /// 环/条进度 0...1（非法值兜底 0）。
        static func progress(for score: Double?) -> Double {
            guard let score, score.isFinite else { return 0 }
            return min(max(score, 0), 100) / 100
        }
    }

    // MARK: - 契约 §3.12 的扁平别名（页面可直接用 `Tokens.primary` 等）

    static var primary: Color { Colors.primary }
    static var secondary: Color { Colors.textSecondary }
    static var success: Color { Colors.success }
    static var warn: Color { Colors.warning }
    static var danger: Color { Colors.danger }
    static var muted: Color { Colors.textSecondary }
    static var background: Color { Colors.canvas }
    static var surface: Color { Colors.surfaceCard }
    static var stroke: Color { Colors.borderSubtle }
}

extension Color {
    /// 十六进制初始化（`0xRRGGBB`）。**仅允许在 `Tokens.swift` 内使用**。
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

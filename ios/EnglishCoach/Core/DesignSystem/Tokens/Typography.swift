import SwiftUI

enum AppFont {
    static func display(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(40 * caps.bodyFontScale), weight: .bold)
    }

    static func titleLarge(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(28 * caps.bodyFontScale), weight: .bold)
    }

    static func title(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(22 * caps.bodyFontScale), weight: .semibold)
    }

    static func heading(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(20 * caps.bodyFontScale), weight: .semibold)
    }

    /// 跟读页英文句子：全 App 唯一的大字号正文。
    static func sentence(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(26 * caps.bodyFontScale), weight: .semibold)
    }

    static func body(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(17 * caps.bodyFontScale), weight: .regular)
    }

    static func bodyEmphasis(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(17 * caps.bodyFontScale), weight: .semibold)
    }

    static func callout(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(16 * caps.bodyFontScale), weight: .regular)
    }

    static func footnote(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(13 * caps.bodyFontScale), weight: .regular)
    }

    static func caption(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(12 * caps.bodyFontScale), weight: .medium)
    }

    static func button(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat((caps.isChild ? 20 : 17) * caps.bodyFontScale), weight: .semibold)
    }

    static var ipa: Font {
        .system(size: 16, design: .monospaced)
    }

    static func score(_ caps: RoleCapabilities) -> Font {
        .system(size: caps.isChild ? 36 : 44, weight: .bold, design: .rounded)
    }

    static func metricNumber(_ caps: RoleCapabilities) -> Font {
        .system(size: CGFloat(15 * caps.bodyFontScale), weight: .semibold)
    }
}

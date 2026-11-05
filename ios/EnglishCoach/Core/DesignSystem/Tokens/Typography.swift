import SwiftUI

/// 字号层级。对齐 `ios/docs/design-system.md` §3 与 `docs/design-tokens.md`：
///
/// | 令牌 | 成人 | 孩子 | 字重 |
/// | --- | --- | --- | --- |
/// | display | 40 | ×1.15 | Bold |
/// | titleLarge | 28 | ×1.15 | Bold |
/// | title | 22 | ×1.15 | Semibold |
/// | heading | 20 | ×1.15 | Semibold |
/// | sentence | 26 | ×1.15 | Semibold |
/// | body | 17 | ×1.15 | Regular |
/// | bodyEmphasis | 17 | ×1.15 | Semibold |
/// | callout | 16 | ×1.15 | Regular |
/// | footnote | 13 | ×1.15 | Regular |
/// | caption | 12 | ×1.15 | Medium |
/// | micro | 11 | ×1.15 | Regular |
/// | score | 44 | 36 | Bold + Rounded |
/// | ipa | 16 | — | Monospaced（仅成人） |
///
/// 孩子模式统一乘 `childScale = 1.15`（design-system §3：「不要逐页改字号」），
/// 页面/组件只调用这里的函数并在需要时传 `RoleCapabilities`。
///
/// 说明：自定义字号使用 `Font.system(size:)`，不随系统 Dynamic Type 缩放；
/// 页面若需支持 AX 字号，应对正文优先使用系统文本样式（见 `ios/README.md` 未做项）。
enum AppFont {

    // MARK: - 缩放

    /// 孩子模式字号倍率（design-system §3：childScale = 1.15）。
    static func scale(_ caps: RoleCapabilities) -> CGFloat {
        caps.isChild ? 1.15 : 1.0
    }

    /// 把基础字号按角色缩放（供页面在特殊处复用同一规则）。
    static func scaled(_ baseSize: CGFloat, _ caps: RoleCapabilities) -> CGFloat {
        (baseSize * scale(caps)).rounded()
    }

    // MARK: - 层级

    static func display(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(40, caps), weight: .bold)
    }

    static func titleLarge(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(28, caps), weight: .bold)
    }

    static func title(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(22, caps), weight: .semibold)
    }

    static func heading(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(20, caps), weight: .semibold)
    }

    /// 跟读页英文句子：全 App 唯一的大字号正文。
    static func sentence(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(26, caps), weight: .semibold)
    }

    static func body(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(17, caps), weight: .regular)
    }

    static func bodyEmphasis(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(17, caps), weight: .semibold)
    }

    static func callout(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(16, caps), weight: .regular)
    }

    static func footnote(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(13, caps), weight: .regular)
    }

    static func caption(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(12, caps), weight: .medium)
    }

    /// 最小字号（标签、悬浮提示、图表轴）。成人 11，孩子约 13。
    static func micro(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(11, caps), weight: .regular)
    }

    static func button(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(caps.isChild ? 20 : 17, caps), weight: .semibold)
    }

    // MARK: - 专用

    /// IPA 音标（等宽，仅成人；孩子由 `RoleCapabilities.canSeeIPA == false` 隐藏整块）。
    static var ipa: Font {
        .system(size: 16, weight: .regular, design: .monospaced)
    }

    /// 分数环中心数字（仅成人；孩子用星级）。
    static func score(_ caps: RoleCapabilities) -> Font {
        scoreCompact(caps, base: caps.isChild ? 36 : 44)
    }

    /// 行内分数/角标数字（Badge、词条）。
    static func scoreCompact(_ caps: RoleCapabilities, base: CGFloat = 30) -> Font {
        .system(size: scaled(base, caps), weight: .bold, design: .rounded)
    }

    /// 数字统计（用量、时长、句数）：等宽数字由使用处追加 `.monospacedDigit()`。
    static func metricNumber(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(15, caps), weight: .semibold)
    }

    /// 大号数字（家长面板 MetricTile、成就页）。调用处自行加 `.monospacedDigit()`。
    static func metricLarge(_ caps: RoleCapabilities) -> Font {
        .system(size: scaled(28, caps), weight: .bold, design: .rounded)
    }
}

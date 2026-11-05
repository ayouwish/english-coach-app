import SwiftUI

/// 按钮层级：primary / tonal / ghost / text / danger（对齐 `docs/design-tokens.md` §组件层级
/// 与契约 §3.12 的 `EcButtonKind` 对应关系）。
///
/// - `primary`：每屏**唯一**主行动（实心主色 + 按钮阴影），成人 48 / 孩子 56；
/// - `tonal`：次行动（`surfaceMuted` 底 + 主色字）；
/// - `ghost`：白底 + 描边（听示范、换一版）；
/// - `text`：无底无边（跳过、查看更多）；
/// - `danger`：白底 + 深红字（删除、退出）；`destructive` 是 M0 的旧名，行为等价。
struct AppButton: View {
    enum Kind {
        case primary
        case tonal
        case ghost
        case text
        case danger
        /// M0 兼容别名，等价 `danger`。
        case destructive
    }

    let title: String
    var icon: String?
    var kind: Kind
    var isLoading: Bool
    var isEnabled: Bool
    let action: () -> Void

    @Environment(\.roleCapabilities) private var caps

    init(
        title: String,
        icon: String? = nil,
        kind: Kind = .primary,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button {
            guard !isLoading else { return }
            action()
        } label: {
            HStack(spacing: Tokens.Spacing.s8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                } else if let icon = self.icon {
                    Image(systemName: icon)
                        .font(AppFont.button(caps))
                }
                Text(title)
                    .font(AppFont.button(caps))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.button, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.button, style: .continuous)
                    .strokeBorder(border, lineWidth: borderWidth)
            )
            .shadow(color: shadowColor, radius: 8, x: 0, y: 6)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(Text(title))
    }

    private var height: CGFloat {
        switch kind {
        case .primary:
            return caps.isChild ? 56 : 48
        case .ghost, .tonal, .danger, .destructive:
            return caps.isChild ? 52 : 44
        case .text:
            return caps.isChild ? 48 : 44
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            return Tokens.Colors.onPrimary
        case .ghost, .tonal, .text:
            return Tokens.Colors.primary
        case .danger, .destructive:
            // 白底上的红色文字用更深的 dangerText（对比度 ≈5.9:1），填充/图标仍用 danger。
            return Tokens.Colors.dangerText
        }
    }

    private var fill: Color {
        switch kind {
        case .primary:
            return isEnabled ? Tokens.Colors.primary : Tokens.Colors.primaryDisabled
        case .tonal:
            return Tokens.Colors.surfaceMuted
        case .ghost, .danger, .destructive:
            return Tokens.Colors.surfaceCard
        case .text:
            return .clear
        }
    }

    private var border: Color {
        switch kind {
        case .ghost, .danger, .destructive:
            return Tokens.Colors.borderSubtle
        case .primary, .tonal, .text:
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        switch kind {
        case .ghost, .danger, .destructive:
            return 1
        case .primary, .tonal, .text:
            return 0
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .primary:
            return Tokens.Shadow.buttonTint
        case .tonal, .ghost, .text, .danger, .destructive:
            return .clear
        }
    }
}

/// 按压缩放 0.98，动效 0.12s（Reduce Motion 时由系统关闭缩放动画基本无感）。
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

import SwiftUI

/// 按钮层级：primary / ghost / text / destructive（对应 design-tokens 的四个层级）。
struct AppButton: View {
    enum Kind {
        case primary
        case ghost
        case text
        case destructive
    }

    let title: String
    var icon: String?
    var kind: Kind
    var isLoading: Bool
    var isEnabled: Bool
    let action: () -> Void

    @Environment(\.capabilities) private var caps

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
        case .ghost, .destructive:
            return caps.isChild ? 52 : 44
        case .text:
            return caps.isChild ? 48 : 44
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            return Tokens.Colors.onPrimary
        case .ghost, .text:
            return Tokens.Colors.primary
        case .destructive:
            return Tokens.Colors.danger
        }
    }

    private var fill: Color {
        switch kind {
        case .primary:
            return isEnabled ? Tokens.Colors.primary : Tokens.Colors.primaryDisabled
        case .ghost, .destructive:
            return Tokens.Colors.surfaceCard
        case .text:
            return .clear
        }
    }

    private var border: Color {
        switch kind {
        case .ghost, .destructive:
            return Tokens.Colors.borderSubtle
        case .primary, .text:
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        switch kind {
        case .ghost, .destructive:
            return 1
        case .primary, .text:
            return 0
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .primary:
            return Tokens.Shadow.buttonTint
        case .ghost, .text, .destructive:
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

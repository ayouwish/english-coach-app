import SwiftUI

/// 白卡片 + 20 圆角 + 极轻双层阴影（design-system §5）。
struct CardStyle: ViewModifier {
    var padding: CGFloat = Tokens.Spacing.s16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Tokens.Colors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                    .strokeBorder(Tokens.Colors.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Tokens.Shadow.cardPrimary, radius: 3, x: 0, y: 1)
            .shadow(color: Tokens.Shadow.cardTint, radius: 2, x: 0, y: 1)
    }
}

extension View {
    func cardStyle(padding: CGFloat = Tokens.Spacing.s16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

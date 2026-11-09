import SwiftUI

/// 统一的内容列宽度。
///
/// - 容器宽度 ≤ 1100（iPhone / iPad 竖屏）：固定 900（iPhone 上自然是屏宽减边距）；
/// - 容器宽度 > 1100（iPad 横屏）：按 90% 放宽，上限 1180，避免两侧留白过多。
///
/// 用 `GeometryReader` 量**外层全宽**，旋转/分屏时自动更新，不依赖 `UIScreen`。
extension View {
    func contentColumn(alignment: Alignment = .leading) -> some View {
        modifier(ContentColumnModifier(alignment: alignment))
    }
}

private struct ContentColumnModifier: ViewModifier {
    let alignment: Alignment
    @State private var availableWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: columnWidth, alignment: alignment)
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.width, initial: true) { _, newValue in
                            availableWidth = newValue
                        }
                }
            )
    }

    private var columnWidth: CGFloat {
        guard availableWidth > 1100 else { return 900 }
        return min(availableWidth * 0.9, 1180)
    }
}

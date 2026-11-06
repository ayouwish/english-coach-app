import SwiftUI

// MARK: - 底部弹层容器

/// 统一底部弹层容器：标题行（可关闭）+ 内容，28 圆角、拖拽指示、半屏/全屏两档。
///
/// 用法（由页面挂 `.sheet`）：
/// ```swift
/// .sheet(isPresented: $showsSheet) {
///     BottomSheetContainer(title: "选择语速") {
///         // 内容
///     }
/// }
/// ```
struct BottomSheetContainer<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var showsCloseButton: Bool = true
    var isScrollable: Bool = true
    var onClose: (() -> Void)? = nil

    private let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps

    init(
        title: String? = nil,
        subtitle: String? = nil,
        showsCloseButton: Bool = true,
        isScrollable: Bool = true,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsCloseButton = showsCloseButton
        self.isScrollable = isScrollable
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
            if hasHeader {
                header
            }
            if isScrollable {
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Tokens.Spacing.s20)
        .padding(.top, Tokens.Spacing.s16)
        .padding(.bottom, Tokens.Spacing.s24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colors.surfaceCard)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Tokens.Radius.xLarge)
        .presentationBackground(Tokens.Colors.surfaceCard)
    }

    private var hasHeader: Bool {
        title != nil || subtitle != nil || showsCloseButton
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                if let title = self.title {
                    Text(title)
                        .font(AppFont.heading(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subtitle = self.subtitle {
                    Text(subtitle)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsCloseButton {
                Button {
                    if let onClose = self.onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .frame(width: caps.minTapTarget, height: caps.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("关闭"))
            }
        }
    }
}

// MARK: - 确认弹层

/// 二次确认（删除、退出、重置密码等）。确认后自动关闭；破坏性操作标题用红色文字按钮。
///
/// 用法：
/// ```swift
/// .sheet(isPresented: $showsConfirm) {
///     ConfirmDialog(title: "退出登录？", message: "退出后需要重新输入密码", confirmTitle: "退出", isDestructive: true) {
///         viewModel.signOut()
///     }
/// }
/// ```
struct ConfirmDialog: View {
    let title: String
    var message: String? = nil
    var confirmTitle: String = "确定"
    var cancelTitle: String = "取消"
    var isDestructive: Bool = false
    var icon: String? = nil
    var onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps

    init(
        title: String,
        message: String? = nil,
        confirmTitle: String = "确定",
        cancelTitle: String = "取消",
        isDestructive: Bool = false,
        icon: String? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.icon = icon
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: Tokens.Spacing.s16) {
            if let icon = self.icon {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(isDestructive ? Tokens.Colors.danger : Tokens.Colors.primary)
                    .accessibilityHidden(true)
            }
            VStack(spacing: Tokens.Spacing.s8) {
                Text(title)
                    .font(AppFont.heading(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = self.message {
                    Text(message)
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: Tokens.Spacing.s8) {
                AppButton(
                    title: confirmTitle,
                    kind: isDestructive ? .destructive : .primary
                ) {
                    onConfirm()
                    dismiss()
                }
                AppButton(title: cancelTitle, kind: .text) {
                    if let onCancel = self.onCancel {
                        onCancel()
                    }
                    dismiss()
                }
            }
        }
        .padding(.horizontal, Tokens.Spacing.s20)
        .padding(.vertical, Tokens.Spacing.s24)
        .frame(maxWidth: .infinity)
        .background(Tokens.Colors.surfaceCard)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Tokens.Radius.xLarge)
        .presentationBackground(Tokens.Colors.surfaceCard)
        .accessibilityElement(children: .contain)
    }
}

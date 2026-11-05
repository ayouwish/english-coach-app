import SwiftUI

// MARK: - 空态

/// 空列表/首屏无内容：图标 + 一句人话 + 一个**可执行**动作（design-system §7）。
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(spacing: Tokens.Spacing.s16) {
            Image(systemName: icon)
                .font(.system(size: caps.isChild ? 56 : 44, weight: .regular))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(AppFont.heading(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .multilineTextAlignment(.center)
            if let message = self.message {
                Text(message)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle = self.actionTitle, let action = self.action {
                AppButton(title: actionTitle, kind: .primary, action: action)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Spacing.s32)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 错误态

/// 全页失败：图标 + 标题 + 说明 + 重试（文案由 `ErrorMapper` 提供，不在组件里造）。
struct ErrorStateView: View {
    let title: String
    let message: String
    var retryTitle: String = "重试"
    var onRetry: (() -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(spacing: Tokens.Spacing.s16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: caps.isChild ? 56 : 44, weight: .regular))
                .foregroundStyle(caps.isChild ? Tokens.Colors.childAccent : Tokens.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(AppFont.heading(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry = self.onRetry {
                AppButton(title: retryTitle, icon: "arrow.clockwise", kind: .primary, action: onRetry)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Spacing.s32)
        .accessibilityElement(children: .contain)
    }
}

/// 表单/提交失败：内联红字 + 可选「重试」，不遮挡内容。
struct InlineErrorView: View {
    let message: String
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(caps.isChild ? Tokens.Colors.childAccent : Tokens.Colors.danger)
                    .font(AppFont.footnote(caps))
                    .accessibilityHidden(true)
                Text(message)
                    .font(AppFont.footnote(caps))
                    .foregroundStyle(caps.isChild ? Tokens.Colors.childAccentText : Tokens.Colors.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let retryTitle = self.retryTitle, let onRetry = self.onRetry {
                Button(retryTitle, action: onRetry)
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(minHeight: caps.minTapTarget, alignment: .leading)
                    .accessibilityLabel(Text(retryTitle))
            }
        }
        .padding(Tokens.Spacing.s12)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(caps.isChild ? Tokens.Colors.childAccentSoft : Tokens.Colors.surfaceSunken)
        )
        .accessibilityElement(children: .contain)
    }
}

/// 麦克风/相机被拒：说明 + 去设置 + 兜底路径（文案由页面按 `ErrorMapper`/audio 文档给）。
struct PermissionCard: View {
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            HStack(spacing: Tokens.Spacing.s8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Tokens.Colors.warning)
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppFont.heading(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
            }
            Text(message)
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AppButton(title: primaryTitle, icon: "gearshape.fill", kind: .primary, action: primaryAction)
            if let secondaryTitle = self.secondaryTitle, let secondaryAction = self.secondaryAction {
                AppButton(title: secondaryTitle, kind: .text, action: secondaryAction)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}

/// 页内错误条（顶部常驻/降级提示）：浅底 + 文案 + 可执行动作，不遮挡主内容。
struct ErrorBanner: View {
    let message: String
    var retryTitle: String = "重试"
    var onRetry: (() -> Void)? = nil

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(Tokens.Colors.warningText)
                .font(AppFont.footnote(caps))
                .accessibilityHidden(true)
            Text(message)
                .font(AppFont.footnote(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry = self.onRetry {
                Button(retryTitle, action: onRetry)
                    .font(AppFont.footnote(caps).weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(minHeight: caps.minTapTarget, alignment: .trailing)
                    .accessibilityLabel(Text(retryTitle))
            }
        }
        .padding(Tokens.Spacing.s12)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(Tokens.Colors.surfaceSunken)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 加载态

/// 加载中：spinner + 一句进度文案。**不显示假百分比**（design-tokens 状态语义）。
struct LoadingBlock: View {
    var text: String = "加载中…"
    var subText: String? = nil
    var showsSpinner: Bool = true

    @Environment(\.roleCapabilities) private var caps

    init(text: String = "加载中…", subText: String? = nil, showsSpinner: Bool = true) {
        self.text = text
        self.subText = subText
        self.showsSpinner = showsSpinner
    }

    var body: some View {
        VStack(spacing: Tokens.Spacing.s8) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Tokens.Colors.primary)
            }
            Text(text)
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            if let subText = self.subText {
                Text(subText)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Spacing.s32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
    }
}

/// 骨架块：`surfaceSunken` 圆角底 + 微光扫过；Reduce Motion 时静态（design-system §8）。
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = Tokens.Radius.small
    var isShimmering: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.2

    init(width: CGFloat? = nil, height: CGFloat = 16, cornerRadius: CGFloat = Tokens.Radius.small, isShimmering: Bool = true) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.isShimmering = isShimmering
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(Tokens.Colors.surfaceSunken)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? CGFloat.infinity : nil)
            .overlay {
                if isShimmering && !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.55), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(proxy.size.width, 1) * 0.6)
                        .offset(x: proxy.size.width * phase)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(shape)
            .onAppear {
                guard isShimmering && !reduceMotion else { return }
                phase = -1.2
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.8
                }
            }
            .accessibilityLabel(Text("内容加载中"))
    }
}

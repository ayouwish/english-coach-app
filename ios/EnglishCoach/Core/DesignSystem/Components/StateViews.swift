import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.capabilities) private var caps

    var body: some View {
        VStack(spacing: Tokens.Spacing.s16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Tokens.Colors.textTertiary)
            Text(title)
                .font(AppFont.heading(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .multilineTextAlignment(.center)
            if let message = self.message {
                Text(message)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle = self.actionTitle, let action = self.action {
                AppButton(title: actionTitle, kind: .primary, action: action)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Spacing.s32)
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    var retryTitle: String = "重试"
    var onRetry: (() -> Void)?

    @Environment(\.capabilities) private var caps

    var body: some View {
        VStack(spacing: Tokens.Spacing.s16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(caps.isChild ? Tokens.Colors.childAccent : Tokens.Colors.textSecondary)
            Text(title)
                .font(AppFont.heading(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            if let onRetry = self.onRetry {
                AppButton(title: retryTitle, icon: "arrow.clockwise", kind: .primary, action: onRetry)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Spacing.s32)
    }
}

struct InlineErrorView: View {
    let message: String
    var retryTitle: String?
    var onRetry: (() -> Void)?

    @Environment(\.capabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(caps.isChild ? Tokens.Colors.childAccent : Tokens.Colors.danger)
                    .font(AppFont.footnote(caps))
                Text(message)
                    .font(AppFont.footnote(caps))
                    .foregroundStyle(caps.isChild ? Tokens.Colors.childAccentText : Tokens.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let retryTitle = self.retryTitle, let onRetry = self.onRetry {
                Button(retryTitle, action: onRetry)
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(minHeight: caps.minTapTarget)
            }
        }
        .padding(Tokens.Spacing.s12)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(caps.isChild ? Tokens.Colors.childAccentSoft : Tokens.Colors.surfaceSunken)
        )
    }
}

struct PermissionCard: View {
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    @Environment(\.capabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            HStack(spacing: Tokens.Spacing.s8) {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(Tokens.Colors.warning)
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
    }
}

struct ErrorBanner: View {
    let message: String
    var retryTitle: String = "重试"
    var onRetry: (() -> Void)?

    @Environment(\.capabilities) private var caps

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(Tokens.Colors.warning)
                .font(AppFont.footnote(caps))
            Text(message)
                .font(AppFont.footnote(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry = self.onRetry {
                Button(retryTitle, action: onRetry)
                    .font(AppFont.footnote(caps).weight(.semibold))
                    .foregroundStyle(Tokens.Colors.primary)
            }
        }
        .padding(Tokens.Spacing.s12)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(Tokens.Colors.surfaceSunken)
        )
    }
}

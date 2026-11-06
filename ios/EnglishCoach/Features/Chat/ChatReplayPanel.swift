import SwiftUI

/// 整段回放面板：idle → loading/building → ready（播放）→ failed（显示 error + 重新生成）。
struct ChatReplayPanel: View {
    let state: ChatReplayController.State
    let durationText: String
    let errorMessage: String
    let isPlaying: Bool
    let isChild: Bool
    var onBegin: () -> Void
    var onPlay: () -> Void
    var onRegenerate: () -> Void

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            Text(isChild ? "🎧 听一听我们的对话" : "🎧 回放整段对话")
                .font(AppFont.heading(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            switch state {
            case .idle:
                AppButton(title: "▶ 生成整段回放", kind: .tonal, action: onBegin)
            case .loading, .building:
                HStack(spacing: Tokens.Spacing.s8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("🎧 正在生成整段回放…（可以先看文字）")
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .ready:
                HStack(spacing: Tokens.Spacing.s8) {
                    AppButton(title: isPlaying ? "⏸ 暂停" : "▶ 播放", kind: .tonal, action: onPlay)
                    Text(durationText)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            case .failed:
                VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                    Text("🎧 整段回放还没好")
                        .font(AppFont.bodyEmphasis(caps))
                        .foregroundStyle(Tokens.Colors.warningText)
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.dangerText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: Tokens.Spacing.s8) {
                        AppButton(title: "🔄 重新生成", kind: .tonal, action: onRegenerate)
                        Text("可以先看文字记录")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textTertiary)
                    }
                }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .stroke(Tokens.Colors.borderSubtle, lineWidth: 1)
        )
    }
}

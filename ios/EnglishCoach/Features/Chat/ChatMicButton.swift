import SwiftUI

/// 会话页唯一的输入控件（纯语音）：点一下开始录音，再点一下说完了。
struct ChatMicButton: View {
    let isRecording: Bool
    let isBusy: Bool
    let isPreparing: Bool
    let elapsedMs: Int
    let isChild: Bool
    let isEnabled: Bool
    var onTap: () -> Void

    @Environment(\.roleCapabilities) private var caps

    private var diameter: CGFloat {
        isChild ? 112 : 88
    }

    var body: some View {
        VStack(spacing: Tokens.Spacing.s8) {
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(isRecording ? Tokens.Colors.danger : Tokens.Colors.primary)
                        .frame(width: diameter, height: diameter)
                        .shadow(
                            color: isRecording ? Tokens.Colors.danger.opacity(0.35) : Tokens.Shadow.buttonTint,
                            radius: Tokens.Elevation.buttonRadius,
                            y: Tokens.Elevation.buttonY
                        )
                    if isBusy || isPreparing {
                        ProgressView()
                            .tint(Tokens.Colors.onPrimary)
                            .controlSize(.large)
                    } else {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: diameter * 0.36, weight: .semibold))
                            .foregroundStyle(Tokens.Colors.onPrimary)
                    }
                }
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled || isBusy || isPreparing)
            .opacity(isEnabled || isBusy || isPreparing ? 1 : 0.5)
            .accessibilityLabel(Text(actionTitle))
            .accessibilityHint(Text(isRecording ? "点一下结束并发送" : "点一下开始录音"))

            Text(actionTitle)
                .font(AppFont.bodyEmphasis(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            if isRecording {
                Text("正在听你说…说完点上面按钮")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
    }

    private var actionTitle: String {
        if isRecording {
            return "⏹ 说完啦 \(max(0, elapsedMs / 1000))s"
        }
        if isPreparing {
            return "正在打开麦克风…"
        }
        if isBusy {
            return "正在处理…"
        }
        return "🎤 开始录音"
    }
}

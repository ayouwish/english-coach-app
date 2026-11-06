import SwiftUI

/// 一条对话气泡（助手文本 / 用户语音）。儿童不显示分数、弱音与逐词。
struct ChatBubbleView: View {
    let bubble: ChatBubble
    let isChild: Bool
    var onPlay: () -> Void

    @Environment(\.roleCapabilities) private var caps
    @State private var showsWords = false
    @State private var showsChinese = false

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
            if bubble.isUser {
                Spacer(minLength: 40)
            }
            VStack(alignment: bubble.isUser ? .trailing : .leading, spacing: Tokens.Spacing.s4) {
                bubbleBody
                if bubble.isUser, bubble.hasCorrection {
                    correctionView
                }
                if bubble.isUser {
                    pronView
                    playButton
                } else {
                    chineseToggle
                    playButton
                }
            }
            if !bubble.isUser {
                Spacer(minLength: 40)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 气泡主体

    @ViewBuilder
    private var bubbleBody: some View {
        if bubble.isUser {
            HStack(spacing: Tokens.Spacing.s8) {
                Image(systemName: "mic.fill")
                    .font(AppFont.footnote(caps))
                    .accessibilityHidden(true)
                Text("你的语音")
                    .font(AppFont.body(caps))
                playbackIcon
            }
            .foregroundStyle(Tokens.Colors.onPrimary)
            .padding(.horizontal, Tokens.Spacing.s16)
            .padding(.vertical, Tokens.Spacing.s12)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                    .fill(Tokens.Colors.primary)
            )
            .accessibilityLabel(Text("你的语音"))
        } else {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                Text(bubble.text)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if bubble.unsafeFiltered {
                    Text("（内容已按儿童安全规则替换）")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.warningText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Spacing.s16)
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

    @ViewBuilder
    private var playbackIcon: some View {
        switch bubble.playback {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .tint(Tokens.Colors.onPrimary)
        case .playing:
            Image(systemName: "speaker.wave.2.fill")
                .font(AppFont.micro(caps))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.micro(caps))
        case .idle:
            EmptyView()
        }
    }

    // MARK: - 中文翻译

    @ViewBuilder
    private var chineseToggle: some View {
        let zh = bubble.textZh.trimmingCharacters(in: .whitespacesAndNewlines)
        if !zh.isEmpty {
            if isChild {
                Button(showsChinese ? "收起中文" : "听不懂？看中文") {
                    showsChinese.toggle()
                }
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.primary)
                .frame(minHeight: caps.minTapTarget, alignment: .leading)
                .accessibilityLabel(Text(showsChinese ? "收起中文翻译" : "看中文翻译"))
                if showsChinese {
                    Text(zh)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(zh)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 校正 / 发音

    private var correctionView: some View {
        VStack(alignment: .trailing, spacing: Tokens.Spacing.s2) {
            Text("更自然：\(bubble.better)")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.successText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            if !bubble.explainZh.isEmpty {
                Text(bubble.explainZh)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 280, alignment: .trailing)
    }

    @ViewBuilder
    private var pronView: some View {
        if bubble.hasPron {
            if isChild {
                Text("这次说得很清楚，继续说！🌟")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.childAccentText)
            } else {
                VStack(alignment: .trailing, spacing: Tokens.Spacing.s4) {
                    Text(pronLine)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    if !bubble.words.isEmpty {
                        Button(showsWords ? "收起逐词" : "看逐词(\(bubble.words.count) 个词)") {
                            showsWords.toggle()
                        }
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.primary)
                        .frame(minHeight: caps.minTapTarget)
                        .accessibilityLabel(Text(showsWords ? "收起逐词" : "看逐词"))
                        if showsWords {
                            WordChipRow(items: bubble.words.map { WordChipItem(id: $0.id, word: $0.text, score: $0.score) })
                        }
                    }
                }
                .frame(maxWidth: 300, alignment: .trailing)
            }
        } else if bubble.pronPending {
            Text("评分中…")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
        } else if bubble.pronTimedOut {
            Text("评分稍后可在历史中查看")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
        }
    }

    private var pronLine: String {
        var line = "发音 " + EcFormat.scoreText(bubble.pronScore)
        if !bubble.weakLabels.isEmpty {
            line += " · 最弱 " + bubble.weakLabels.joined(separator: "/")
        }
        return line
    }

    // MARK: - 播放按钮

    private var playButton: some View {
        AppButton(title: playLabel, kind: .text, action: onPlay)
            .accessibilityLabel(Text(playLabel))
    }

    private var playLabel: String {
        switch bubble.playback {
        case .loading:
            return bubble.isUser ? "⏳ 正在取录音…" : "⏳ 语音生成中…（通常几秒）"
        case .playing:
            return bubble.isUser ? "⏸ 正在回放…" : "🔊 正在说话…（点一下停）"
        case .failed:
            return bubble.isUser ? "▶ 录音没取到，点这里重试" : "⚠️ 语音没出来，点这里重试"
        case .idle:
            return bubble.isUser ? "🔁 回放我刚才说的话" : "🔊 再听一遍"
        }
    }
}

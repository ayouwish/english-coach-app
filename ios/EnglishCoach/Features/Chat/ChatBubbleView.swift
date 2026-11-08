import SwiftUI

/// 一条对话气泡（对齐 web 聊天气泡）：
/// - 助手：浅底气泡，英文 + 中文翻译 + 琥珀色「更自然」纠正框 + 播放器条；
/// - 用户：主色气泡，显示识别出的英文 + 发音分 + 播放器条；
/// - 气泡按内容宽度收缩，最宽 560pt（手机约 80% 屏宽）。
struct ChatBubbleView: View {
    let bubble: ChatBubble
    /// 播放进度从这里读（只有正在播的这条气泡会订阅它，避免整条时间线每 100ms 重绘）。
    let audio: AudioCoordinator
    let isChild: Bool
    var onPlay: () -> Void

    @Environment(\.roleCapabilities) private var caps
    @State private var showsWords = false
    @State private var showsChinese = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if bubble.isUser {
                Spacer(minLength: 48)
            }
            VStack(alignment: bubble.isUser ? .trailing : .leading, spacing: Tokens.Spacing.s4) {
                if bubble.isUser {
                    userBubble
                    if !isChild, bubble.hasPron, !bubble.words.isEmpty {
                        wordsToggle
                    }
                } else {
                    assistantBubble
                }
            }
            .frame(maxWidth: 560, alignment: bubble.isUser ? .trailing : .leading)
            if !bubble.isUser {
                Spacer(minLength: 48)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 用户气泡

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: Tokens.Spacing.s8) {
            if !bubble.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bubble.text)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.onPrimary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !isChild, let pron = userPronText {
                Text(pron)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.onPrimary.opacity(0.82))
            }
            playerRow(onDark: true)
        }
        .padding(.horizontal, Tokens.Spacing.s16)
        .padding(.vertical, Tokens.Spacing.s12)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.primary)
        )
        .accessibilityLabel(Text("你说的：\(bubble.text)"))
    }

    private var userPronText: String? {
        if bubble.hasPron {
            var line = "发音 \(EcFormat.scoreText(bubble.pronScore))"
            if !bubble.weakLabels.isEmpty {
                line += " · 最弱 \(bubble.weakLabels.joined(separator: "/"))"
            }
            return line
        }
        if bubble.pronPending { return "发音 评分中…" }
        if bubble.pronTimedOut { return "发音 稍后可在历史中查看" }
        return nil
    }

    private var wordsToggle: some View {
        VStack(alignment: .trailing, spacing: Tokens.Spacing.s4) {
            Button(showsWords ? "收起逐词" : "看逐词（\(bubble.words.count) 个词）") {
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

    // MARK: - 助手气泡

    private var assistantBubble: some View {
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

            chineseText

            if bubble.hasCorrection, !bubble.better.isEmpty {
                correctionBox
            }

            playerRow(onDark: false)
        }
        .padding(.horizontal, Tokens.Spacing.s16)
        .padding(.vertical, Tokens.Spacing.s12)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceSunken)
        )
        .accessibilityLabel(Text(bubble.text))
    }

    @ViewBuilder
    private var chineseText: some View {
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

    /// 与 web 一致的琥珀色「更自然」提示块（在助手气泡内部）。
    private var correctionBox: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
            Text("更自然：\(bubble.better)")
                .font(AppFont.caption(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.warningText)
                .fixedSize(horizontal: false, vertical: true)
            if !bubble.explainZh.isEmpty {
                Text(bubble.explainZh)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.warningText.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Tokens.Spacing.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(Tokens.Colors.warningBackground)
        )
    }

    // MARK: - 播放器条

    private var isLivePlaying: Bool { bubble.playback == .playing }
    private var liveProgress: Double { isLivePlaying ? audio.playbackProgress : 0 }
    private var liveCurrentTime: TimeInterval { isLivePlaying ? audio.playbackCurrentTime : 0 }
    private var liveDuration: TimeInterval { isLivePlaying ? audio.playbackDuration : 0 }

    private func playerRow(onDark: Bool) -> some View {
        Button(action: onPlay) {
            HStack(spacing: Tokens.Spacing.s8) {
                playbackGlyph(onDark: onDark)
                if bubble.playback == .loading || bubble.playback == .failed {
                    Text(playerLabel)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(onDark ? Tokens.Colors.onPrimary : Tokens.Colors.primary)
                        .lineLimit(1)
                } else {
                    Text(liveDuration > 0
                         ? "\(timeText(liveCurrentTime)) / \(timeText(liveDuration))"
                         : timeText(liveCurrentTime))
                        .font(AppFont.caption(caps).monospacedDigit())
                        .foregroundStyle(onDark ? Tokens.Colors.onPrimary : Tokens.Colors.primary)
                        .lineLimit(1)
                    progressTrack(onDark: onDark)
                        .frame(width: 84, height: 4)
                }
                Image(systemName: "speaker.wave.2.fill")
                    .font(AppFont.micro(caps))
                    .foregroundStyle((onDark ? Tokens.Colors.onPrimary : Tokens.Colors.primary).opacity(0.65))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Tokens.Spacing.s12)
            .frame(minWidth: 168, minHeight: 38)
            .background(
                Capsule(style: .continuous)
                    .fill(onDark ? Tokens.Colors.onPrimary.opacity(0.18) : Tokens.Colors.surfaceCard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(playerLabel))
    }

    @ViewBuilder
    private func playbackGlyph(onDark: Bool) -> some View {
        switch bubble.playback {
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .tint(onDark ? Tokens.Colors.onPrimary : Tokens.Colors.primary)
        case .playing:
            Image(systemName: "pause.fill")
                .font(AppFont.micro(caps))
                .foregroundStyle(onDark ? Tokens.Colors.onPrimary : Tokens.Colors.primary)
        case .failed:
            Image(systemName: "arrow.clockwise")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.warningText)
        case .idle:
            Image(systemName: "play.fill")
                .font(AppFont.micro(caps))
                .foregroundStyle(onDark ? Tokens.Colors.onPrimary : Tokens.Colors.primary)
        }
    }

    /// 与 web 播放器一致的进度条（已播部分填充）。
    private func progressTrack(onDark: Bool) -> some View {
        let base = onDark ? Tokens.Colors.onPrimary : Tokens.Colors.primary
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(base.opacity(0.3))
                Capsule(style: .continuous)
                    .fill(base.opacity(0.85))
                    .frame(width: geo.size.width * min(max(liveProgress, 0), 1))
            }
        }
        .accessibilityHidden(true)
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var playerLabel: String {
        switch bubble.playback {
        case .loading:
            return bubble.isUser ? "正在取录音…" : "语音生成中…"
        case .playing:
            return bubble.isUser ? "正在回放…" : "正在说话…"
        case .failed:
            return bubble.isUser ? "录音没取到，重试" : "语音没出来，重试"
        case .idle:
            return bubble.isUser ? "回放我的录音" : "播放"
        }
    }
}

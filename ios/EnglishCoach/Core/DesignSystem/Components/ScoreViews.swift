import SwiftUI

// MARK: - 星级

/// 1–3 颗星（孩子模式的主要分数表达；成人也可用于成绩条目）。
/// 空星用描边，实星用 `childAccent`；VoiceOver 读出「N 颗星，共 3 颗」。
struct StarRow: View {
    let filled: Int
    var total: Int = 3
    var starSize: CGFloat = 22
    var tint: Color = Tokens.Colors.childAccent

    init(filled: Int, total: Int = 3, starSize: CGFloat = 22, tint: Color = Tokens.Colors.childAccent) {
        self.filled = filled
        self.total = total
        self.starSize = starSize
        self.tint = tint
    }

    private var safeTotal: Int { max(total, 0) }
    private var safeFilled: Int { min(max(filled, 0), safeTotal) }

    var body: some View {
        HStack(spacing: Tokens.Spacing.s4) {
            ForEach(0..<safeTotal, id: \.self) { index in
                Image(systemName: index < safeFilled ? "star.fill" : "star")
                    .font(.system(size: starSize, weight: .semibold))
                    .foregroundStyle(index < safeFilled ? tint : Tokens.Colors.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(safeTotal > 0 ? "\(safeFilled) 颗星，共 \(safeTotal) 颗" : "暂无星级"))
    }
}

// MARK: - 分数徽标

/// 分数徽标：成人显示「78 分」（语义色 + 浅底），孩子显示星级 + 一句短鼓励，**永不显示数字**。
struct ScoreBadge: View {
    enum Size {
        case small
        case medium
        case large
    }

    let score: Double?
    var title: String? = nil
    var size: Size = .medium

    @Environment(\.roleCapabilities) private var caps

    init(score: Double?, title: String? = nil, size: Size = .medium) {
        self.score = score
        self.title = title
        self.size = size
    }

    var body: some View {
        Group {
            if caps.isChild {
                HStack(spacing: Tokens.Spacing.s8) {
                    StarRow(filled: Tokens.Score.stars(for: score), starSize: starSize)
                    Text(childPraise)
                        .font(AppFont.footnote(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.childAccentText)
                        .lineLimit(2)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s4) {
                    Text(scoreText)
                        .font(AppFont.scoreCompact(caps, base: numberSize))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.Score.color(for: score, isChild: false))
                    Text(title ?? "分")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(Tokens.Score.softBackground(for: score, isChild: caps.isChild))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var numberSize: CGFloat {
        switch size {
        case .small: return 20
        case .medium: return 30
        case .large: return 44
        }
    }

    private var starSize: CGFloat {
        switch size {
        case .small: return 14
        case .medium: return 18
        case .large: return 24
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return Tokens.Spacing.s8
        case .medium: return Tokens.Spacing.s12
        case .large: return Tokens.Spacing.s16
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .small: return Tokens.Spacing.s2
        case .medium: return Tokens.Spacing.s4
        case .large: return Tokens.Spacing.s8
        }
    }

    private var scoreText: String {
        guard let score, score.isFinite else { return "—" }
        return String(Int(score.rounded()))
    }

    /// 组件自带极简鼓励语（Core 不能反向依赖 `Features/Shared/ScorePresenter`）；
    /// 页面要完整两句文案时用 `ScorePresenter.encouragement`。
    private var childPraise: String {
        guard let score, score.isFinite else { return "等下再看星星" }
        if score >= 85 { return "太棒啦" }
        if score >= 60 { return "读得真好" }
        return "再试一次吧"
    }

    private var accessibilityText: String {
        if caps.isChild {
            return "\(Tokens.Score.stars(for: score)) 颗星，\(childPraise)"
        }
        return "\(scoreText) 分\(title.map { "，\($0)" } ?? "")"
    }
}

// MARK: - 子项分数条

/// 子项分数条（准确度/流利度/完整度/语调）：成人显示数字，孩子只显示进度与鼓励色。
struct ScoreBar: View {
    let label: String
    let score: Double?
    var showsValue: Bool = true
    var barHeight: CGFloat = 8

    @Environment(\.roleCapabilities) private var caps

    init(label: String, score: Double?, showsValue: Bool = true, barHeight: CGFloat = 8) {
        self.label = label
        self.score = score
        self.showsValue = showsValue
        self.barHeight = barHeight
    }

    private var barColor: Color {
        Tokens.Score.color(for: score, isChild: caps.isChild)
    }

    private var showsNumber: Bool {
        showsValue && caps.showsNumericScore && score != nil
    }

    var body: some View {
        HStack(spacing: Tokens.Spacing.s8) {
            Text(label)
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: caps.isChild ? 72 : 56, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                    Capsule(style: .continuous)
                        .fill(barColor)
                        .frame(width: max(0, proxy.size.width * Tokens.Score.progress(for: score)))
                }
            }
            .frame(height: barHeight)
            if showsNumber {
                Text(numberText)
                    .font(AppFont.caption(caps))
                    .monospacedDigit()
                    .foregroundStyle(barColor)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .frame(minHeight: max(24, barHeight + Tokens.Spacing.s8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var numberText: String {
        guard let score, score.isFinite else { return "—" }
        return String(Int(score.rounded()))
    }

    private var accessibilityValue: String {
        guard let score, score.isFinite else { return "暂无数据" }
        if caps.showsNumericScore { return "\(numberText) 分" }
        if score >= 85 { return "很好" }
        if score >= 60 { return "不错" }
        return "继续加油"
    }
}

// MARK: - 分数环

/// 分数环：轨道 `surfaceSunken`，进度用分数色；成人中心是 `scoreNumber`，孩子中心是星级。
/// 出现动画 0.6s easeOut（Reduce Motion 时直接到目标值）。
struct ScoreRing: View {
    let score: Double?
    var label: String = "总分"
    var ringSize: CGFloat = 120
    var lineWidth: CGFloat = 10

    @Environment(\.roleCapabilities) private var caps
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    init(score: Double?, label: String = "总分", ringSize: CGFloat = 120, lineWidth: CGFloat = 10) {
        self.score = score
        self.label = label
        self.ringSize = ringSize
        self.lineWidth = lineWidth
    }

    private var ringColor: Color {
        caps.isChild ? Tokens.Colors.childAccent : Tokens.Score.color(for: score, isChild: false)
    }

    private var centerNumberSize: CGFloat {
        ringSize >= 140 ? 52 : (ringSize >= 100 ? 44 : 32)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.Colors.surfaceSunken, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(animatedProgress, 1)))
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: Tokens.Spacing.s2) {
                if caps.isChild {
                    StarRow(filled: Tokens.Score.stars(for: score), starSize: starSize)
                } else {
                    Text(numberText)
                        .font(.system(size: AppFont.scaled(centerNumberSize, caps), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ringColor)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Text(label)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, lineWidth + Tokens.Spacing.s4)
        }
        .frame(width: ringSize, height: ringSize)
        .onAppear { applyProgress() }
        .onChange(of: score) { _, _ in applyProgress() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var starSize: CGFloat {
        ringSize >= 140 ? 22 : (ringSize >= 100 ? 18 : 14)
    }

    private var numberText: String {
        guard let score, score.isFinite else { return "—" }
        return String(Int(score.rounded()))
    }

    private var accessibilityText: String {
        if caps.isChild {
            return "\(label)，\(Tokens.Score.stars(for: score)) 颗星"
        }
        return "\(label)，\(numberText) 分"
    }

    private func applyProgress() {
        let target = Tokens.Score.progress(for: score)
        guard !reduceMotion else {
            animatedProgress = target
            return
        }
        withAnimation(.easeOut(duration: 0.6)) {
            animatedProgress = target
        }
    }
}

// MARK: - 词级色块

/// 词级得分的展示模型（与 DTO 解耦，页面自行把 `WordScoreDTO` 映射过来）。
struct WordChipItem: Identifiable, Hashable, Sendable {
    let id: Int
    let word: String
    /// nil 表示没有逐词分（只展示中性样式）。
    let score: Double?
    /// 音标（可选；仅成人展示）。
    let ipa: String?

    init(id: Int, word: String, score: Double? = nil, ipa: String? = nil) {
        self.id = id
        self.word = word
        self.score = score
        self.ipa = ipa
    }
}

/// 词级色块行：成人四级色阶、孩子只标「说对了 / 再试试」两色，且**不显示数字**。
/// 点击回调由页面注入（例如调 `DictionaryService.wordIpa` 后再决定弹窗），组件内不发请求。
struct WordChipRow: View {
    let items: [WordChipItem]
    var onTapWord: ((WordChipItem) -> Void)? = nil
    var spacing: CGFloat = Tokens.Spacing.s8

    @Environment(\.roleCapabilities) private var caps

    init(items: [WordChipItem], onTapWord: ((WordChipItem) -> Void)? = nil, spacing: CGFloat = Tokens.Spacing.s8) {
        self.items = items
        self.onTapWord = onTapWord
        self.spacing = spacing
    }

    var body: some View {
        WordChipFlowLayout(spacing: spacing, lineSpacing: spacing) {
            ForEach(items) { item in
                if let onTapWord = self.onTapWord {
                    Button {
                        onTapWord(item)
                    } label: {
                        chipBody(for: item)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityLabel(Text(item.word))
                    .accessibilityHint(Text(caps.canSeeIPA ? "查看这个单词的音标" : "查看这个单词"))
                } else {
                    chipBody(for: item)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(accessibilityText(for: item)))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chipBody(for item: WordChipItem) -> some View {
        let palette = palette(for: item)
        return VStack(spacing: 1) {
            Text(item.word)
                .font(AppFont.body(caps).weight(.medium))
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
            if caps.canSeeIPA, let ipa = item.ipa, !ipa.isEmpty {
                Text("/\(ipa)/")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(palette.foreground.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Tokens.Spacing.s8)
        .padding(.vertical, Tokens.Spacing.s4)
        .frame(minHeight: onTapWord == nil ? nil : caps.minTapTarget)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                .fill(palette.background)
        )
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous))
    }

    private struct ChipPalette {
        let background: Color
        let foreground: Color
    }

    private func palette(for item: WordChipItem) -> ChipPalette {
        if caps.isChild {
            // 孩子只有两档：说对了（绿）/ 再试试（琥珀），没有数字、没有红色。
            let isGood = (item.score ?? 0) >= 60
            return isGood
                ? ChipPalette(background: Tokens.Colors.wordGoodBackground, foreground: Tokens.Colors.wordGoodText)
                : ChipPalette(background: Tokens.Colors.childAccentSoft, foreground: Tokens.Colors.childAccentText)
        }
        switch Tokens.Score.tone(for: item.score) {
        case .excellent:
            return ChipPalette(background: Tokens.Colors.wordGoodBackground, foreground: Tokens.Colors.wordGoodText)
        case .good:
            return ChipPalette(background: Tokens.Colors.surfaceMuted, foreground: Tokens.Colors.primary)
        case .fair:
            return ChipPalette(background: Tokens.Colors.wordFairBackground, foreground: Tokens.Colors.wordFairText)
        case .weak:
            return ChipPalette(background: Tokens.Colors.wordWeakBackground, foreground: Tokens.Colors.wordWeakText)
        case nil:
            return ChipPalette(background: Tokens.Colors.surfaceSunken, foreground: Tokens.Colors.textSecondary)
        }
    }

    private func accessibilityText(for item: WordChipItem) -> String {
        guard let score = item.score, score.isFinite else { return item.word }
        if caps.isChild {
            return score >= 60 ? "\(item.word)，说对了" : "\(item.word)，再试试"
        }
        return "\(item.word)，\(Int(score.rounded())) 分"
    }
}

// MARK: - 换行布局

/// 简单的流式换行布局（词块、标签用）。iOS 16+ 的 `Layout`，缓存为 Void。
private struct WordChipFlowLayout: Layout {
    var spacing: CGFloat = Tokens.Spacing.s8
    var lineSpacing: CGFloat = Tokens.Spacing.s8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0 && cursorX + size.width > maxWidth {
                cursorX = 0
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, cursorX - spacing)
        }
        let width = maxWidth.isFinite ? maxWidth : widest
        return CGSize(width: width, height: cursorY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > bounds.minX && cursorX + size.width > bounds.maxX {
                cursorX = bounds.minX
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: cursorX, y: cursorY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

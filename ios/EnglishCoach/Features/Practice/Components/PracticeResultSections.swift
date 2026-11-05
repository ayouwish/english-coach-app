import SwiftUI

/// 详细结果分区组件集合的命名空间（各分区是独立 View，这里只用于文件/类型命名对齐）。
enum PracticeResultSections {}

/// 详细结果页的分区组件（`PracticeResultView` 组合使用；页内结果只用其中一部分）。
@MainActor
struct PracticeScoreSection: View {
    let result: PracticeAttemptResult

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            HStack(alignment: .center, spacing: Tokens.Spacing.s16) {
                ScoreRing(score: result.scores.pron, label: caps.isChild ? "这次" : "综合分", ringSize: 108)
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    ScoreBar(label: ScorePresenter.subScoreLabel("accuracy", isChild: caps.isChild), score: result.scores.accuracy)
                    ScoreBar(label: ScorePresenter.subScoreLabel("fluency", isChild: caps.isChild), score: result.scores.fluency)
                    ScoreBar(label: ScorePresenter.subScoreLabel("completeness", isChild: caps.isChild), score: result.scores.completeness)
                    ScoreBar(label: ScorePresenter.subScoreLabel("prosody", isChild: caps.isChild), score: result.scores.prosody)
                }
            }
            if !caps.isChild {
                Text("综合分 = pron（服务端 voice 计算）；不可得项显示「—」。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
            if !result.recognizedText.isEmpty, !caps.isChild {
                Text("识别结果：\(result.recognizedText)")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.referenceText.isEmpty, result.referenceText != result.recognizedText, !caps.isChild {
                Text("参考文本：\(result.referenceText)")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

@MainActor
struct PracticeRadarSection: View {
    let scores: PracticeScores

    @Environment(\.roleCapabilities) private var caps

    private var metrics: [RadarMetric] {
        ChartsData.radarMetrics(
            labels: [
                ScorePresenter.subScoreLabel("accuracy", isChild: caps.isChild),
                ScorePresenter.subScoreLabel("fluency", isChild: caps.isChild),
                ScorePresenter.subScoreLabel("completeness", isChild: caps.isChild),
                ScorePresenter.subScoreLabel("prosody", isChild: caps.isChild)
            ],
            values: [scores.accuracy, scores.fluency, scores.completeness, scores.prosody]
        )
    }

    private var weakestText: String {
        let pairs: [(String, Double?)] = [
            (ScorePresenter.subScoreLabel("accuracy", isChild: caps.isChild), scores.accuracy),
            (ScorePresenter.subScoreLabel("fluency", isChild: caps.isChild), scores.fluency),
            (ScorePresenter.subScoreLabel("completeness", isChild: caps.isChild), scores.completeness),
            (ScorePresenter.subScoreLabel("prosody", isChild: caps.isChild), scores.prosody)
        ]
        let valid = pairs.compactMap { label, value -> (String, Double)? in
            guard let value else { return nil }
            return (label, value)
        }
        guard let weakest = valid.min(by: { $0.1 < $1.1 }) else { return "" }
        if caps.showsNumericScore {
            return "最需要练的是 \(weakest.0) \(String(format: "%.1f", weakest.1))"
        }
        return "最需要练的是 \(weakest.0)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            PhonemeRadarChart(metrics: metrics, size: 260, showsValues: caps.showsNumericScore)
            if !weakestText.isEmpty {
                Text(weakestText)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.warningText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

@MainActor
struct PracticeIntonationSection: View {
    let intonation: PracticeIntonation

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("虚线是示范音高，蓝色实线是你的曲线（已按 DTW 对齐）" + (intonation.dtwDistance.isEmpty ? "" : " · 语调差异 \(intonation.dtwDistance)，越小越接近"))
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            IntonationChart(user: intonation.user, reference: intonation.reference)
            if !intonation.regionTexts.isEmpty {
                BulletList(items: intonation.regionTexts, bulletColor: Tokens.Colors.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// 逐词得分单行（`score < 60` 标红并文字备注，仅成人页展示）。
@MainActor
struct PracticeWordBarRow: View {
    let word: String
    let score: Double?

    @Environment(\.roleCapabilities) private var caps

    private var isWeak: Bool {
        guard let score else { return false }
        return score < 60
    }

    private var color: Color {
        isWeak ? Tokens.Colors.dangerText : ScorePresenter.color(for: score, isChild: caps.isChild)
    }

    var body: some View {
        HStack(spacing: Tokens.Spacing.s8) {
            Text(word)
                .font(AppFont.caption(caps))
                .foregroundStyle(isWeak ? Tokens.Colors.dangerText : Tokens.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: caps.isChild ? 90 : 104, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: max(0, proxy.size.width * Tokens.Score.progress(for: score)))
                }
            }
            .frame(height: 8)
            Text(ScorePresenter.numberText(for: score))
                .font(AppFont.caption(caps))
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 34, alignment: .trailing)
            if isWeak {
                Text("再练")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.dangerText)
            }
        }
        .frame(minHeight: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isWeak ? "\(word)，低于 60 分，需要再练" : "\(word)，\(ScorePresenter.numberText(for: score)) 分"))
    }
}

@MainActor
struct PracticeWordSection: View {
    let result: PracticeAttemptResult

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            if result.weakWordCount > 0 {
                Text("红色 = 低于 60 分，需要重点练（这一句有 \(result.weakWordCount) 个）")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(result.words) { word in
                PracticeWordBarRow(word: word.word, score: word.score)
            }
            if !result.phonemes.isEmpty {
                Text("音素明细")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .padding(.top, Tokens.Spacing.s8)
                PracticePhonemeChipGrid(chips: result.phonemes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// 音素 chips（成人；儿童视图不会渲染本组件）。
@MainActor
private struct PracticePhonemeChipGrid: View {
    let chips: [PracticePhonemeChip]

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        // 流式换行用 Core 的 `WordChipRow` 会丢掉音素的下标语义，这里用 LazyVGrid 两列。
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: Tokens.Spacing.s8)],
            alignment: .leading,
            spacing: Tokens.Spacing.s8
        ) {
            ForEach(chips) { chip in
                HStack(spacing: Tokens.Spacing.s4) {
                    Text("/\(chip.phoneme)/")
                        .font(AppFont.ipa)
                        .foregroundStyle(ScorePresenter.color(for: chip.score, isChild: caps.isChild))
                    Text(ScorePresenter.numberText(for: chip.score))
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                .padding(.horizontal, Tokens.Spacing.s8)
                .padding(.vertical, Tokens.Spacing.s4)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("/\(chip.phoneme)/ \(ScorePresenter.numberText(for: chip.score)) 分"))
            }
        }
    }
}

@MainActor
struct PracticeIssueSection: View {
    let issues: [PracticeIssueCard]

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            ForEach(issues) { card in
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                        Text(card.title)
                            .font(AppFont.bodyEmphasis(caps))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                        Spacer(minLength: 0)
                        if let score = card.score {
                            Text("\(String(Int(score.rounded()))) 分")
                                .font(AppFont.caption(caps))
                                .foregroundStyle(ScorePresenter.color(for: score, isChild: caps.isChild))
                        }
                    }
                    if !card.word.isEmpty {
                        Text("单词：\(card.word)"
                            + (card.expected.isEmpty ? "" : " · 音素 \(card.expected)")
                            + (card.actual.isEmpty ? "" : " → 实际读成 \(card.actual)"))
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !card.why.isEmpty {
                        Text("为什么：\(card.why)")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !card.how.isEmpty {
                        Text("怎么改：\(card.how)")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !card.practiceWords.isEmpty {
                        Text("练习词：\(card.practiceWords)")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Tokens.Spacing.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(Tokens.Colors.dangerBackground)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

@MainActor
struct PracticeFeedbackSection: View {
    let feedback: PracticeFeedback

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            if !feedback.summary.isEmpty {
                Text(feedback.summary)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !feedback.praise.isEmpty {
                Text("👍 \(feedback.praise)")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.successText)
            }
            ForEach(feedback.points) { point in
                VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                    if !point.title.isEmpty {
                        Text("· \(point.title)")
                            .font(AppFont.caption(caps).weight(.semibold))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                    }
                    if !point.why.isEmpty, !caps.isChild {
                        Text("为什么：\(point.why)")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                    if !point.how.isEmpty {
                        Text("怎么改：\(point.how)")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                    if !point.practiceWords.isEmpty {
                        Text("练习词：\(point.practiceWords)")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.primary)
                    }
                }
                .padding(Tokens.Spacing.s8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
            }
            if !feedback.closing.isEmpty {
                Text(feedback.closing)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// 单句历史 + 进步曲线 + 逐次回放（旧 → 新）。
@MainActor
struct PracticeHistorySection: View {
    let store: PracticeResultStore

    @Environment(\.roleCapabilities) private var caps

    private var trendPoints: [TrendPoint] {
        ChartsData.trendPoints(
            labels: store.history.map { $0.label },
            values: store.history.map(\.score)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            switch store.historyPhase {
            case .loading:
                LoadingBlock(text: "正在读这一句的历史…")
            case .failed:
                if let error = store.historyError {
                    InlineErrorView(message: [error.title, error.body].compactMap { $0 }.joined(separator: " "))
                }
            default:
                if store.history.isEmpty {
                    Text(caps.isChild ? "这一句还没有读过，先读一遍吧 🙂" : "这一句还没有历史记录，先读一遍再来看进步曲线")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("共 \(store.history.count) 次 · 这一句的进步曲线（旧 → 新）")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    TrendLineChart(points: trendPoints, height: 150)
                    if !store.historyDeltaText.isEmpty {
                        Text("首末对比：\(ScorePresenter.numberText(for: store.firstHistoryScore)) → \(ScorePresenter.numberText(for: store.lastHistoryScore))（\(store.historyDeltaText)）")
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                    }
                    VStack(spacing: Tokens.Spacing.s4) {
                        ForEach(store.history.reversed()) { entry in
                            HStack(spacing: Tokens.Spacing.s8) {
                                Text(entry.label.isEmpty ? "一次朗读" : entry.label)
                                    .font(AppFont.micro(caps))
                                    .foregroundStyle(Tokens.Colors.textSecondary)
                                    .frame(minWidth: 84, alignment: .leading)
                                Text(caps.showsNumericScore ? ScorePresenter.numberText(for: entry.score) : "读完了")
                                    .font(AppFont.caption(caps))
                                    .foregroundStyle(ScorePresenter.color(for: entry.score, isChild: caps.isChild))
                                Spacer(minLength: 0)
                                Button {
                                    store.playHistory(entry: entry)
                                } label: {
                                    Text(store.playingHistoryId == entry.attemptId ? "播放中…" : "▶ 回放")
                                        .font(AppFont.caption(caps))
                                        .foregroundStyle(Tokens.Colors.primary)
                                        .frame(minHeight: caps.minTapTarget, alignment: .trailing)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("回放这一次朗读"))
                            }
                            .frame(minHeight: 26)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

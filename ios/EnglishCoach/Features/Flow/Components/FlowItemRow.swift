import SwiftUI

/// 连读逐句行（running 的实时评分列表 + 汇总页列表复用）。
///
/// 只有「完成 / 失败」的行可展开；失败行提供「重录这句」。
@MainActor
struct FlowItemRow: View {
    let item: FlowItem
    let badge: String
    let tone: PillTag.Tone
    let isExpanded: Bool
    var onTap: () -> Void
    var onRetry: () -> Void

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                Text("\(item.index + 1). \(item.text)")
                    .font(caps.isChild ? AppFont.body(caps) : AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PillTag(text: badge, tone: tone)
            }

            if item.status == .failed {
                HStack(spacing: Tokens.Spacing.s8) {
                    Text(item.errorText.isEmpty ? "评分没有成功" : item.errorText)
                        .font(AppFont.micro(caps))
                        .foregroundStyle(caps.isChild ? Tokens.Colors.warningText : Tokens.Colors.dangerText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("重录这句", action: onRetry)
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.primary)
                        .frame(minHeight: caps.minTapTarget)
                }
            }

            if isExpanded, let result = item.result {
                FlowItemDetailBlock(result: result)
            }
        }
        .padding(Tokens.Spacing.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .strokeBorder(Tokens.Colors.borderSubtle, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if item.hasResult || item.status == .failed {
                onTap()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// 单句详情（连读详情不含音素明细与语调图；儿童只看鼓励语）。
@MainActor
struct FlowItemDetailBlock: View {
    let result: FlowAttemptResult

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            if result.noSpeech {
                Text("这次好像没有听到声音，可以点「重录这句」再读一次")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if caps.isChild {
                HStack(spacing: Tokens.Spacing.s8) {
                    StarRow(filled: ScorePresenter.stars(for: result.pron), starSize: 22)
                    Text(ScorePresenter.encouragement(for: result.pron, isChild: true))
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.childAccentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: Tokens.Spacing.s12) {
                    ScoreRing(score: result.pron, label: "这一句", ringSize: 76)
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                        ScoreBar(label: ScorePresenter.subScoreLabel("accuracy"), score: result.accuracy)
                        ScoreBar(label: ScorePresenter.subScoreLabel("fluency"), score: result.fluency)
                        ScoreBar(label: ScorePresenter.subScoreLabel("completeness"), score: result.completeness)
                        ScoreBar(label: ScorePresenter.subScoreLabel("prosody"), score: result.prosody)
                    }
                }
            }

            if !result.feedbackSummary.isEmpty {
                Text(result.feedbackSummary)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.feedbackPraise.isEmpty {
                Text("👍 \(result.feedbackPraise)")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.successText)
            }
            if !result.wordTexts.isEmpty, !caps.isChild {
                WordChipRow(
                    items: result.wordTexts.enumerated().map { index, word in
                        WordChipItem(
                            id: index,
                            word: word,
                            score: index < result.wordScores.count ? result.wordScores[index] : nil
                        )
                    }
                )
            }
            if !result.issueTexts.isEmpty {
                BulletList(items: result.issueTexts, bulletColor: Tokens.Colors.warning)
            }
            if !result.feedbackClosing.isEmpty {
                Text(result.feedbackClosing)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("连读详情不含音素明细与语调图。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
        }
        .padding(.top, Tokens.Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

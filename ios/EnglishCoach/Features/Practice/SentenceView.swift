import SwiftUI
import UIKit

struct SentenceView: View {
    let viewModel: PracticeViewModel
    let initialIndex: Int

    @Environment(\.capabilities) private var caps
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var didSelectInitialIndex = false
    @State private var followTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            if let sentence = viewModel.currentSentence {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s20) {
                    sentenceCard(sentence)
                    demoSection
                    recordSection
                    errorSections
                    if let message = viewModel.attemptMessage {
                        statusNote(message)
                    }
                    if let score = viewModel.score {
                        scoreCard(score)
                    }
                }
                .padding(.horizontal, Tokens.Spacing.s16)
                .padding(.vertical, Tokens.Spacing.s16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .tint(Tokens.Colors.primary)
                    .padding(Tokens.Spacing.s32)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .navigationTitle("跟读")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let level = viewModel.currentSentence?.level, !level.isEmpty {
                    Text(level)
                        .font(AppFont.caption(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.primary)
                }
            }
        }
        .task {
            if !didSelectInitialIndex {
                didSelectInitialIndex = true
                viewModel.select(index: initialIndex)
            }
        }
        .task(id: viewModel.currentIndex) {
            await viewModel.prepareDemo()
        }
        .onDisappear {
            followTask?.cancel()
            followTask = nil
            viewModel.stopAllAudio()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.refreshPermission()
            } else {
                // 不支持后台录音：切后台立即停止并丢弃本轮。
                followTask?.cancel()
                followTask = nil
                viewModel.stopAllAudio()
            }
        }
    }

    // MARK: - 句子卡

    private func sentenceCard(_ sentence: Sentence) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            HStack(spacing: Tokens.Spacing.s8) {
                if let level = sentence.level, !level.isEmpty {
                    chip(level)
                }
                if !caps.isChild {
                    ForEach(sentence.tags.prefix(3), id: \.self) { tag in
                        chip(tag)
                    }
                }
                Spacer(minLength: 0)
            }

            Text(sentence.text)
                .font(AppFont.sentence(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if caps.showsIPA, !sentence.focusPhonemes.isEmpty {
                HStack(spacing: Tokens.Spacing.s8) {
                    Text("重点")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    Text(sentence.focusPhonemes.joined(separator: "  "))
                        .font(AppFont.ipa)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }

            if let translation = sentence.translationZh, !translation.isEmpty {
                Text(translation)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private var demoSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(
                    title: "播放示范",
                    icon: viewModel.isPreparingDemo ? "hourglass" : "play.fill",
                    kind: .ghost,
                    isEnabled: !viewModel.isScoring,
                    action: { Task { await viewModel.playDemo() } }
                )
                AppButton(
                    title: "跟我读",
                    icon: "mic.fill",
                    kind: .primary,
                    isEnabled: !viewModel.isScoring && viewModel.permission != .denied,
                    action: {
                        followTask?.cancel()
                        followTask = Task { await viewModel.followAndRecord() }
                    }
                )
            }

            if let demoErrorMessage = viewModel.demoErrorMessage {
                InlineErrorView(message: demoErrorMessage)
            } else {
                Text(caps.isChild ? "点「跟我读」，听完就可以开始读啦。" : "「跟我读」会先播示范音，播完自动开始录音。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
    }

    // MARK: - 录音

    @ViewBuilder
    private var recordSection: some View {
        if viewModel.permission == .denied {
            PermissionCard(
                title: "麦克风被关掉了",
                message: "去设置里打开就能录音啦。路径：设置 → English Coach → 麦克风。",
                primaryTitle: "去设置",
                primaryAction: { openSettings() },
                secondaryTitle: "先听示范",
                secondaryAction: { Task { await viewModel.playDemo() } }
            )
        } else {
            VStack(spacing: Tokens.Spacing.s12) {
                Button {
                    Task { await viewModel.toggleRecording() }
                } label: {
                    recordOrb
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(viewModel.isScoring)
                .accessibilityLabel(viewModel.isRecording ? "正在录音，双击结束" : "开始录音")

                if viewModel.isRecording {
                    LevelWaveform(level: viewModel.levelValue)
                    Text("正在录音… \(Int(viewModel.elapsed.rounded())) 秒 / 60 秒，点一下结束")
                        .font(AppFont.footnote(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                } else if viewModel.isScoring {
                    HStack(spacing: Tokens.Spacing.s8) {
                        ProgressView().tint(Tokens.Colors.primary)
                        Text("正在听你的发音…")
                            .font(AppFont.body(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                } else {
                    Text(viewModel.score == nil ? "点一下开始录音" : "点一下再录一次")
                        .font(AppFont.footnote(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }

                if viewModel.permission == .undetermined, !viewModel.isRecording {
                    Text("第一次录音时系统会请求麦克风权限。")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Spacing.s8)
        }
    }

    private var recordOrb: some View {
        let size: CGFloat = caps.isChild ? 96 : 80
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: viewModel.isRecording
                            ? [Tokens.Colors.recordingRed, Tokens.Colors.recordingRed.opacity(0.78)]
                            : [Tokens.Colors.primary, Tokens.Colors.primary.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Tokens.Shadow.floatingTint, radius: 14, x: 0, y: 8)

            Circle()
                .stroke(Tokens.Colors.recordingRed.opacity(viewModel.isRecording ? 0.25 : 0), lineWidth: 10)
                .frame(width: size + 20, height: size + 20)

            Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(Tokens.Colors.onPrimary)
        }
    }

    // MARK: - 错误与状态

    @ViewBuilder
    private var errorSections: some View {
        if let audioError = viewModel.audioError, viewModel.permission != .denied {
            InlineErrorView(message: audioError.userMessage(forChild: caps.isChild))
        }

        if let error = viewModel.submissionError {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                InlineErrorView(message: error.userMessage(forChild: caps.isChild))
                HStack(spacing: Tokens.Spacing.s8) {
                    if error.canRetry {
                        AppButton(
                            title: "重试提交",
                            icon: "arrow.clockwise",
                            kind: .ghost,
                            action: { Task { await viewModel.retrySubmission() } }
                        )
                    }
                    AppButton(
                        title: "重新录音",
                        icon: "mic.fill",
                        kind: error.canRetry ? .ghost : .primary,
                        action: { Task { await viewModel.recordAgain() } }
                    )
                }
            }
        }
    }

    private func statusNote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Tokens.Colors.warning)
                .font(AppFont.footnote(caps))
            Text(message)
                .font(AppFont.footnote(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Spacing.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(Tokens.Colors.surfaceSunken)
        )
    }

    // MARK: - 评分结果

    private func scoreCard(_ score: ScorePresentation) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
            HStack(alignment: .center, spacing: Tokens.Spacing.s16) {
                if caps.showsNumericScore {
                    ScoreRing(score: score.numericScore)
                } else {
                    StarRow(stars: score.stars)
                }
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text(score.headline)
                        .font(AppFont.title(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    Text(score.encouragement)
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !score.metrics.isEmpty {
                VStack(spacing: Tokens.Spacing.s8) {
                    ForEach(score.metrics) { metric in
                        metricRow(metric)
                    }
                }
            }

            if !score.words.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                    Text("单词")
                        .font(AppFont.footnote(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: caps.isChild ? 112 : 132), spacing: Tokens.Spacing.s8)],
                        alignment: .leading,
                        spacing: Tokens.Spacing.s8
                    ) {
                        ForEach(score.words) { word in
                            WordChipView(item: word)
                        }
                    }
                }
            }

            if !score.issues.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text("可以注意")
                        .font(AppFont.footnote(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    ForEach(score.issues.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                            Text("•").foregroundStyle(Tokens.Colors.warning)
                            Text(score.issues[index])
                                .font(AppFont.footnote(caps))
                                .foregroundStyle(Tokens.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            feedbackSection(score)
            actionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func metricRow(_ metric: ScorePresentation.Metric) -> some View {
        HStack(spacing: Tokens.Spacing.s8) {
            Text(metric.title)
                .font(AppFont.footnote(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .frame(width: 56, alignment: .leading)

            ProgressView(value: metric.value ?? 0)
                .tint(Tokens.Colors.primary)
                .progressViewStyle(.linear)

            Text(metric.value.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                .font(AppFont.metricNumber(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func feedbackSection(_ score: ScorePresentation) -> some View {
        if score.feedbackSummary != nil || score.feedbackPraise != nil || !score.feedbackPoints.isEmpty || score.feedbackClosing != nil {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                if let praise = score.feedbackPraise, !praise.isEmpty {
                    Text(praise)
                        .font(AppFont.bodyEmphasis(caps))
                        .foregroundStyle(Tokens.Colors.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let summary = score.feedbackSummary, !summary.isEmpty {
                    Text(summary)
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(score.feedbackPoints.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.footnote(caps))
                            .foregroundStyle(Tokens.Colors.success)
                        Text(score.feedbackPoints[index])
                            .font(AppFont.footnote(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
                if let closing = score.feedbackClosing, !closing.isEmpty {
                    Text(closing)
                        .font(AppFont.footnote(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Tokens.Spacing.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                    .fill(Tokens.Colors.surfaceSunken)
            )
        }
    }

    private var actionButtons: some View {
        VStack(spacing: Tokens.Spacing.s8) {
            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(
                    title: "再听我的",
                    icon: "play.fill",
                    kind: .ghost,
                    isEnabled: viewModel.lastRecording != nil,
                    action: { viewModel.playMyRecording() }
                )
                AppButton(
                    title: "重录",
                    icon: "arrow.counterclockwise",
                    kind: .ghost,
                    action: { Task { await viewModel.recordAgain() } }
                )
            }
            AppButton(
                title: viewModel.canGoNext ? "下一句" : "回到列表",
                icon: "arrow.right",
                kind: .primary,
                action: {
                    followTask?.cancel()
                    followTask = nil
                    if !viewModel.advance() {
                        dismiss()
                    }
                }
            )
        }
    }

    // MARK: - 小工具

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption(caps))
            .foregroundStyle(Tokens.Colors.primary)
            .padding(.horizontal, Tokens.Spacing.s8)
            .padding(.vertical, Tokens.Spacing.s2)
            .background(Capsule().fill(Tokens.Colors.surfaceMuted))
    }
}

// MARK: - 评分组件

private struct ScoreRing: View {
    let score: Int?

    @Environment(\.capabilities) private var caps

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.Colors.borderSubtle, lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(score.map { "\($0)" } ?? "—")
                .font(AppFont.score(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .monospacedDigit()
        }
        .frame(width: 120, height: 120)
        .accessibilityLabel(score.map { "总分 \($0)" } ?? "暂无分数")
    }

    private var color: Color {
        guard let score = self.score else { return Tokens.Colors.textTertiary }
        if score >= 85 { return Tokens.Colors.scoreExcellent }
        if score >= 70 { return Tokens.Colors.scoreGood }
        if score >= 55 { return Tokens.Colors.scoreFair }
        return Tokens.Colors.scoreWeak
    }
}

private struct StarRow: View {
    let stars: Int

    var body: some View {
        HStack(spacing: Tokens.Spacing.s4) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < stars ? "star.fill" : "star")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(index < stars ? Tokens.Colors.childAccent : Tokens.Colors.textTertiary)
            }
        }
        .accessibilityLabel("\(stars) 颗星")
    }
}

private struct WordChipView: View {
    let item: ScorePresentation.WordItem

    @Environment(\.capabilities) private var caps

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            HStack(spacing: Tokens.Spacing.s4) {
                Text(item.word)
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if caps.showsNumericScore, let score = item.score {
                    Text("\(score)")
                        .font(AppFont.metricNumber(caps))
                        .foregroundStyle(color(for: score))
                        .monospacedDigit()
                }
            }

            if caps.isChild {
                Text(item.isGood ? "说对了" : "再试试")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(item.isGood ? Tokens.Colors.successText : Tokens.Colors.textSecondary)
            } else {
                ProgressView(value: Double(item.score ?? 0) / 100)
                    .tint(color(for: item.score ?? 0))
                    .progressViewStyle(.linear)
            }
        }
        .padding(Tokens.Spacing.s8)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                .fill(caps.isChild && item.isGood ? Tokens.Colors.childAccentSoft : Tokens.Colors.surfaceSunken)
        )
    }

    private func color(for score: Int) -> Color {
        if caps.isChild { return item.isGood ? Tokens.Colors.successText : Tokens.Colors.textSecondary }
        if score >= 85 { return Tokens.Colors.scoreExcellent }
        if score >= 70 { return Tokens.Colors.scoreGood }
        if score >= 55 { return Tokens.Colors.scoreFair }
        return Tokens.Colors.scoreWeak
    }
}

private struct LevelWaveform: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<24, id: \.self) { index in
                let factor = 0.3 + 0.7 * Double((index * 7) % 11) / 10
                Capsule()
                    .fill(Tokens.Colors.recordingRed.opacity(0.75))
                    .frame(width: 3, height: max(4, CGFloat(level * 44 * factor + 4)))
            }
        }
        .frame(height: 52)
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

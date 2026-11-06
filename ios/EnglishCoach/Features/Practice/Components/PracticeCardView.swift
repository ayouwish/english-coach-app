import SwiftUI

/// 跟读卡片：句子 + 示范/录音动作 + 页内结果。
///
/// 被 `PracticeView`（卡片流）与 `SentencePracticeView`（单句）复用；所有网络/录音动作
/// 都委托给 `PracticeStore`，本视图只负责渲染与交互编排。
@MainActor
struct PracticeCardView: View {
    let store: PracticeStore
    var onFinish: (() -> Void)? = nil

    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps
    @State private var ipaSheet: PracticeIPASheet?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
            sentenceSection
            actionSection
            statusSection
            if let result = store.result {
                resultSection(result)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Tokens.Spacing.s20)
        .sheet(item: $ipaSheet) { sheet in
            BottomSheetContainer(title: sheet.word, subtitle: "音标") {
                ipaContent(sheet)
            }
        }
    }

    // MARK: - 句子

    private var sentenceSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            HStack(spacing: Tokens.Spacing.s8) {
                if let level = store.currentSentence?.level, !level.isEmpty {
                    PillTag(text: level, tone: .primary)
                }
                if !caps.isChild {
                    ForEach(store.focusPhonemes.prefix(3), id: \.self) { phoneme in
                        PillTag(text: phoneme, tone: .neutral)
                    }
                }
                Spacer(minLength: 0)
                if store.result != nil {
                    PillTag(text: "已评分", tone: .success)
                }
            }

            WordTextView(
                text: store.currentText,
                showIPA: caps.canSeeIPA,
                onTapWord: caps.canSeeIPA ? { word in openIPA(word) } : nil
            )

            if !store.currentTranslation.isEmpty {
                Text(store.currentTranslation)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !caps.isChild, let sentence = store.currentSentence, !sentence.tags.isEmpty {
                HStack(spacing: Tokens.Spacing.s8) {
                    ForEach(sentence.tags.prefix(3), id: \.self) { tag in
                        PillTag(text: tag, tone: .neutral)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 动作

    @ViewBuilder
    private var actionSection: some View {
        if store.permission == .denied {
            PermissionCard(
                title: "麦克风被关掉了",
                message: "去设置里打开就能录音啦。路径：设置 → English Coach → 麦克风。文本、翻译和示范音仍可正常使用。",
                primaryTitle: "去设置",
                primaryAction: { store.audio.openSettings() },
                secondaryTitle: "先听示范",
                secondaryAction: { store.playDemo(autoRecord: false) }
            )
        } else {
            VStack(spacing: Tokens.Spacing.s12) {
                if store.isRecording {
                    HStack(spacing: Tokens.Spacing.s8) {
                        AppButton(
                            title: "⏹ 说完啦 \(store.elapsedMs / 1000)s",
                            kind: .danger,
                            isEnabled: !store.isEvaluating,
                            action: { Task { await store.stopRecordingAndEvaluate() } }
                        )
                        AppButton(title: "✖️ 不要了", kind: .ghost) {
                            Task { await store.cancelRecording() }
                        }
                    }
                } else {
                    VStack(spacing: Tokens.Spacing.s8) {
                        HStack(spacing: Tokens.Spacing.s8) {
                            AppButton(
                                title: "🔊 听示范",
                                kind: .tonal,
                                isLoading: store.isPreparingDemo,
                                isEnabled: !store.isEvaluating,
                                action: { store.playDemo(autoRecord: false) }
                            )
                            AppButton(
                                title: "🎧 跟我读",
                                kind: .tonal,
                                isEnabled: !store.isEvaluating && !store.isLimitReached,
                                action: { store.playDemo(autoRecord: true) }
                            )
                        }
                        AppButton(
                            title: store.isEvaluating ? "评分中…" : "🎤 开始说",
                            kind: .primary,
                            isLoading: store.isEvaluating,
                            isEnabled: !store.isLimitReached && !store.isPreparingDemo,
                            action: { Task { await store.startRecording() } }
                        )
                    }
                    .frame(minHeight: caps.minTapTarget)
                }

                if store.permission == .unknown {
                    Text("第一次点「开始说」时，系统会请求麦克风权限。")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 状态 / 错误

    @ViewBuilder
    private var statusSection: some View {
        if store.isRecording {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                PracticeLevelMeter(level: store.audio.level)
                Text("正在听你说…读完点「说完啦」（最长 60 秒，到点自动提交）")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let limit = store.limitMessage {
            Banner(
                message: [limit.title, limit.body].compactMap { $0 }.joined(separator: " "),
                kind: .warning,
                icon: "moon.zzz.fill"
            )
        }

        if let info = store.infoMessage {
            Banner(
                message: [info.title, info.body].compactMap { $0 }.joined(separator: " "),
                kind: .warning,
                icon: "exclamationmark.triangle.fill",
                actionTitle: store.canRetryEvaluate ? "重试评测" : nil,
                onAction: store.canRetryEvaluate ? { Task { await store.retryEvaluate() } } : nil
            )
        }

        if let error = store.errorMessage {
            InlineErrorView(
                message: [error.title, error.body].compactMap { $0 }.joined(separator: " "),
                retryTitle: error.actionTitle,
                onRetry: { Task { await store.retryLastFailedAction() } }
            )
        }
    }

    // MARK: - 页内结果

    private func resultSection(_ result: PracticeAttemptResult) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            Divider().foregroundStyle(Tokens.Colors.borderSubtle)

            if caps.isChild {
                HStack(spacing: Tokens.Spacing.s12) {
                    StarRow(filled: ScorePresenter.stars(for: result.scores.pron), starSize: 28)
                    Text(ScorePresenter.encouragement(for: result.scores.pron, isChild: true))
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.childAccentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .center, spacing: Tokens.Spacing.s16) {
                    ScoreBadge(score: result.scores.pron, size: .large)
                    Text(ScorePresenter.resultTitle(for: result.scores.pron, isChild: false))
                        .font(AppFont.heading(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: Tokens.Spacing.s4) {
                ScoreBar(label: ScorePresenter.subScoreLabel("accuracy", isChild: caps.isChild), score: result.scores.accuracy)
                ScoreBar(label: ScorePresenter.subScoreLabel("fluency", isChild: caps.isChild), score: result.scores.fluency)
                ScoreBar(label: ScorePresenter.subScoreLabel("completeness", isChild: caps.isChild), score: result.scores.completeness)
                ScoreBar(label: ScorePresenter.subScoreLabel("prosody", isChild: caps.isChild), score: result.scores.prosody)
            }

            if !result.noSpeech, !caps.isChild, !result.recognizedText.isEmpty {
                Text("我听到的是：\(result.recognizedText)")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !result.words.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                    Text("逐词一句一句看")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    WordChipRow(
                        items: result.words.map { word in
                            WordChipItem(id: word.id, word: word.word, score: word.score)
                        },
                        onTapWord: caps.canSeeIPA ? { item in openIPA(item.word) } : nil
                    )
                }
            }

            if !caps.isChild, !result.issues.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                    Text("这次可以注意")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    BulletList(items: result.issues.map(\.title), bulletColor: Tokens.Colors.warning)
                }
            }

            if !caps.isChild, !result.feedback.summary.isEmpty {
                Text(result.feedback.summary)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.feedback.praise.isEmpty, !caps.isChild {
                Text("👍 \(result.feedback.praise)")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.successText)
            }

            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(title: "详细结果", kind: .ghost) {
                    router.push(.practiceResult(attemptId: result.attemptId))
                }
                AppButton(
                    title: store.isPlayingRecording ? "播放中…" : "🔁 回放",
                    kind: .tonal,
                    isEnabled: !store.isEvaluating,
                    action: { store.playRecording() }
                )
            }

            if store.canGoNext {
                AppButton(title: "下一句 →", kind: .primary) {
                    store.next()
                }
            } else if let onFinish {
                AppButton(title: "完成", kind: .primary, action: onFinish)
            } else {
                AppButton(title: "已经是最后一句", kind: .primary, isEnabled: false) {}
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 音标浮层

    private func ipaContent(_ sheet: PracticeIPASheet) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            if let ipa = sheet.ipa, !ipa.isEmpty {
                Text("/\(ipa)/")
                    .font(AppFont.ipa)
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .textSelection(.enabled)
            }
            if !sheet.variants.isEmpty, !caps.isChild {
                Text("其它读音：\(sheet.variants.joined(separator: " · "))")
                    .font(AppFont.footnote(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = sheet.note, !note.isEmpty {
                Text(note)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            Text("点单词查音标；儿童模式下默认关闭。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openIPA(_ word: String) {
        Task {
            if let sheet = await store.lookupIPA(for: word) {
                ipaSheet = sheet
            }
        }
    }
}

// MARK: - 录音电平条

/// 录音电平条（24 根，视觉反馈；不做静音切分，audio.md §4.5）。
private struct PracticeLevelMeter: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<24, id: \.self) { index in
                let factor = 0.3 + 0.7 * Double((index * 7) % 11) / 10
                Capsule(style: .continuous)
                    .fill(Tokens.Colors.recordingRed.opacity(0.78))
                    .frame(width: 3, height: max(4, CGFloat(level) * 44 * factor + 4))
            }
        }
        .frame(height: 52)
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

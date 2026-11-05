import SwiftUI

/// 盲测进行中的题目卡：盲听四选一 / 盲跟读 + 揭晓原文 + 下一题。
///
/// 从 `BlindTestView` 拆出（契约 §2.9：单文件 > 700 行时拆到 `Components/`）。
/// 所有状态都在 `BlindTestStore`；本视图只负责呈现与转发交互。
@MainActor
struct BlindTestQuestionView: View {
    let store: BlindTestStore
    let onRequestExit: () -> Void

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        if let question = store.currentQuestion {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                header
                if store.index == 0, let notice = store.setupNotice {
                    Banner(message: notice, kind: .info)
                }
                Text(question.mode == .listen ? "听一听，选出这句话的意思" : "听示范，然后跟读这一句")
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)

                audioControls

                if store.audioErrorText != nil {
                    Button {
                        Task { await store.skipQuestion() }
                    } label: {
                        Text("跳过这题")
                            .font(AppFont.caption(caps))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                }

                if question.mode == .listen {
                    listenOptions(question)
                } else {
                    readControls()
                }

                if store.isRevealed {
                    revealCard(question)
                }
            }
            .padding(Tokens.Spacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        } else {
            LoadingBlock(text: "正在准备这一题…")
                .cardStyle()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: Tokens.Spacing.s8) {
            if let question = store.currentQuestion {
                PillTag(
                    text: question.mode == .listen ? "盲听选择" : "盲跟读",
                    tone: .primary
                )
            }
            Text(store.questionNumberText)
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRequestExit) {
                Text("退出")
                    .font(AppFont.caption(caps))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.Colors.textSecondary)
        }
    }

    // MARK: - 音频

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            if store.isAudioLoading {
                HStack(spacing: Tokens.Spacing.s8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在准备示范音…")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                .frame(minHeight: 44)
            } else if let audioError = store.audioErrorText {
                InlineErrorView(
                    message: audioError,
                    retryTitle: "重试",
                    onRetry: { Task { await store.retryAudio() } }
                )
            } else {
                AppButton(
                    title: store.replayCount == 0
                        ? "🔊 听一听"
                        : "🔊 再听一次（还剩 \(store.replayRemaining) 次）",
                    kind: .tonal,
                    isEnabled: store.canReplay,
                    action: { Task { await store.replay() } }
                )
            }

            if store.audio.mode == .playing {
                HStack(spacing: Tokens.Spacing.s8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在播放…")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - 盲听选项

    private func listenOptions(_ question: BlindQuestion) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Tokens.Spacing.s8),
                GridItem(.flexible(), spacing: Tokens.Spacing.s8)
            ],
            spacing: Tokens.Spacing.s8
        ) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, text in
                optionButton(text: text, index: index, question: question)
            }
        }
        .disabled(!store.canAnswerListen)
    }

    private func optionButton(text: String, index: Int, question: BlindQuestion) -> some View {
        let revealed = store.isRevealed
        let isCorrect = index == question.correctIndex
        let isSelected = store.selectedOption == index
        let background: Color = {
            guard revealed else {
                return Tokens.Colors.surfaceSunken
            }
            if isCorrect {
                return Tokens.Colors.successBackground
            }
            return isSelected ? Tokens.Colors.warningBackground : Tokens.Colors.surfaceSunken
        }()
        let foreground: Color = {
            guard revealed else {
                return Tokens.Colors.textPrimary
            }
            if isCorrect {
                return Tokens.Colors.successText
            }
            return isSelected ? Tokens.Colors.warningText : Tokens.Colors.textSecondary
        }()
        return Button {
            store.selectOption(index)
        } label: {
            Text(text)
                .font(AppFont.body(caps))
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: max(caps.minTapTarget, 56))
                .padding(.horizontal, Tokens.Spacing.s8)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(revealed || !store.canAnswerListen)
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 盲跟读

    @ViewBuilder
    private func readControls() -> some View {
        if store.isRevealed {
            EmptyView()
        } else if store.audio.permission == .denied {
            PermissionCard(
                title: "需要麦克风才能跟读",
                message: "跟读要录下你的声音，录音会上传到学习服务器做发音评测。",
                primaryTitle: "去系统设置打开",
                primaryAction: { store.audio.openSettings() },
                secondaryTitle: "跳过这题",
                secondaryAction: { Task { await store.skipQuestion() } }
            )
        } else {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                if store.isScoring {
                    HStack(spacing: Tokens.Spacing.s8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("听听你说的像不像…")
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                    .frame(minHeight: 44)
                } else if store.audio.mode == .recording {
                    AppButton(
                        title: "🔴 结束并提交",
                        kind: .primary,
                        action: { Task { await store.stopRecordingAndSubmit() } }
                    )
                    ProgressView(value: min(max(store.audio.level, 0), 1))
                        .tint(Tokens.Colors.recordingRed)
                        .accessibilityLabel("录音音量")
                } else {
                    AppButton(
                        title: "🎤 开始跟读",
                        kind: .primary,
                        isEnabled: !store.isScoring,
                        action: { Task { await store.startRecording() } }
                    )
                }

                if let error = store.recordError {
                    InlineErrorView(message: error.body ?? error.title)
                }

                Button {
                    Task { await store.skipQuestion() }
                } label: {
                    Text("跳过这题")
                        .font(AppFont.caption(caps))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .disabled(store.isScoring)
            }
        }
    }

    // MARK: - 揭晓

    private func revealCard(_ question: BlindQuestion) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Divider()
                .overlay(Tokens.Colors.borderSubtle)
            Text("这句话是")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
            Text(question.sentence.text)
                .font(AppFont.sentence(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("原文：\(question.sentence.text)")
            if let translation = question.sentence.translationZh, !translation.isEmpty {
                Text(translation)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if question.mode == .listen {
                Text(listenResultText(question))
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            } else if let notice = store.inlineNotice {
                Text(notice)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AppButton(
                title: store.index + 1 < store.questions.count ? "下一题" : "结束并查看报告",
                icon: "arrow.right",
                kind: .primary,
                isLoading: store.isFinishing,
                action: { Task { await store.advance() } }
            )
        }
        .padding(.top, Tokens.Spacing.s4)
    }

    private func listenResultText(_ question: BlindQuestion) -> String {
        guard let selected = store.selectedOption else {
            return "先听一听，再选一个意思。"
        }
        if selected == question.correctIndex {
            return store.isChild ? "真棒，听出来啦！" : "回答正确。"
        }
        return store.isChild
            ? "没关系，记住这句就好。"
            : "没关系，记住这句的发音和意思，下次就听出来了。"
    }
}

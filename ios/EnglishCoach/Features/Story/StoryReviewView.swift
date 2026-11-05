import SwiftUI

/// 故事复述（契约 §3.15.1 冻结签名：`(materialId:sentences:services:audio:)`）。
///
/// 两步闭环：录音 → ASR（en-US）→ `story/retell`；也可切换成打字复述。
/// 成人显示覆盖率百分比，儿童只用星星 + 中文反馈（screens.md §6.3）。
struct StoryReviewView: View {
    private let materialId: String
    private let sentences: [String]
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(\.roleCapabilities) private var caps

    @State private var store: StoryReviewStore?

    init(materialId: String, sentences: [String], services: AppServices, audio: AudioCoordinator) {
        self.materialId = materialId
        self.sentences = sentences
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store = self.store {
                content(store)
            } else {
                LoadingBlock(text: "准备中…")
            }
        }
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .navigationTitle("复述故事")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                store = StoryReviewStore(
                    materialId: materialId,
                    sentences: sentences,
                    services: services,
                    audio: audio,
                    session: session
                )
            }
            await store?.loadIfNeeded()
        }
        .onDisappear {
            Task { await store?.stopAll() }
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(_ store: StoryReviewStore) -> some View {
        switch store.phase {
        case .loading:
            LoadingBlock(text: "正在打开故事…")
        case .failed(let message):
            ErrorStateView(
                title: message.title,
                message: message.body ?? "",
                retryTitle: message.actionTitle ?? "重试"
            ) {
                Task { await store.loadIfNeeded() }
            }
        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                    intro(store)
                    modePicker(store)
                    storyTextSection(store)
                    if store.mode == .voice {
                        voiceSection(store)
                    } else {
                        typingSection(store)
                    }
                    if !store.busyText.isEmpty {
                        LoadingBlock(text: store.busyText)
                    }
                    messages(store)
                    if store.hasResult {
                        resultSection(store)
                    }
                    footerHint
                }
                .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
                .padding(.vertical, Tokens.Spacing.s16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: 顶部

    private func intro(_ store: StoryReviewStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("🎤 讲给我听")
                .font(AppFont.heading(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            Text("不看屏幕，用 2–3 句话把《\(store.storyTitle)》讲一遍 🙂")
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if caps.showsNumericScore {
                Text("复述只看「讲清楚没有」，不计发音分。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
        }
    }

    private func modePicker(_ store: StoryReviewStore) -> some View {
        Picker(
            "复述方式",
            selection: Binding(
                get: { store.mode },
                set: { store.setMode($0) }
            )
        ) {
            Text("🎤 说英文").tag(StoryReviewStore.Mode.voice)
            Text("✍️ 打字复述").tag(StoryReviewStore.Mode.typing)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text("复述方式"))
    }

    // MARK: 原文偷看

    private func storyTextSection(_ store: StoryReviewStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Button {
                store.toggleStoryText()
            } label: {
                HStack(spacing: Tokens.Spacing.s8) {
                    Text("故事原文（想不起来可以偷看）")
                        .font(AppFont.bodyEmphasis(caps))
                        .foregroundStyle(Tokens.Colors.primary)
                    Spacer(minLength: 0)
                    Image(systemName: store.showsStoryText ? "chevron.up" : "chevron.down")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                }
                .frame(minHeight: caps.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(store.showsStoryText ? "收起故事原文" : "展开故事原文"))

            if store.showsStoryText {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    ForEach(store.storyPairs) { pair in
                        HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                            Text("\(pair.id).")
                                .font(AppFont.caption(caps))
                                .foregroundStyle(Tokens.Colors.textTertiary)
                                .frame(width: 24, alignment: .trailing)
                            Text(pair.en)
                                .font(AppFont.callout(caps))
                                .foregroundStyle(Tokens.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(Tokens.Spacing.s12)
        .cardStyle(padding: Tokens.Spacing.s12)
    }

    // MARK: 语音复述

    private func voiceSection(_ store: StoryReviewStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            HStack(spacing: Tokens.Spacing.s12) {
                AppButton(
                    title: store.isRecording ? "说完了" : "开始复述",
                    icon: store.isRecording ? "stop.fill" : "mic.fill",
                    kind: store.isRecording ? .tonal : .primary,
                    isLoading: store.isPreparing
                ) {
                    Task {
                        if store.isRecording {
                            await store.stopRecordingAndSubmit()
                        } else {
                            await store.startRecording()
                        }
                    }
                }
                if store.isRecording {
                    Text(EcFormat.clock(milliseconds: store.elapsedMs))
                        .font(AppFont.caption(caps))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.Colors.primary)
                    Button("取消") {
                        Task { await store.cancelRecording() }
                    }
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .frame(minHeight: caps.minTapTarget)
                }
            }
            if store.recordedData != nil && !store.isRecording {
                AppButton(
                    title: store.isPlayingRecording ? "停止" : "听我的复述",
                    icon: store.isPlayingRecording ? "stop.fill" : "play.fill",
                    kind: .ghost
                ) {
                    Task { await store.playRecording() }
                }
            }
            Text("最多 60 秒；复述录音只在本机内存里，离开页面就没了。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Spacing.s12)
        .cardStyle(padding: Tokens.Spacing.s12)
    }

    // MARK: 打字复述

    private func typingSection(_ store: StoryReviewStore) -> some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            SectionHeader(title: "打字复述", subtitle: "用英文写几句")
            TextEditor(text: $store.typedText)
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(Tokens.Spacing.s4)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
                .accessibilityLabel(Text("英文复述内容"))
            AppButton(title: "提交复述", icon: "paperplane.fill", kind: .primary, isLoading: store.isSubmitting) {
                Task { await store.submitTyped() }
            }
        }
        .padding(Tokens.Spacing.s12)
        .cardStyle(padding: Tokens.Spacing.s12)
    }

    // MARK: 结果

    private func resultSection(_ store: StoryReviewStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            SectionHeader(title: "复述结果")
            HStack(alignment: .center, spacing: Tokens.Spacing.s16) {
                CoverageRing(coverage: store.coverage, stars: store.coverageStars, isChild: caps.isChild)
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text(store.coveredCountText)
                        .font(AppFont.bodyEmphasis(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    if !store.missingPoints.isEmpty {
                        Text("下一次可以试试：")
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
            }
            if !store.coveredPoints.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text("✅ 说到了：")
                        .font(AppFont.footnote(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.successText)
                    BulletList(items: store.coveredPoints, bulletColor: Tokens.Colors.success)
                }
            }
            if !store.missingPoints.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text("⬜ 还差：")
                        .font(AppFont.footnote(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.warningText)
                    BulletList(items: store.missingPoints, bulletColor: Tokens.Colors.warning)
                }
            }
            if !store.feedbackZh.isEmpty {
                Text(store.feedbackZh)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !caps.isChild, !store.feedbackEn.isEmpty {
                Text(store.feedbackEn)
                    .font(AppFont.callout(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !store.transcript.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text("你说的：")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    Text(store.transcript)
                        .font(AppFont.callout(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Tokens.Spacing.s8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
            }
            AppButton(title: "再复述一次", icon: "arrow.clockwise", kind: .tonal) {
                store.resetResult()
            }
        }
        .padding(Tokens.Spacing.s12)
        .cardStyle(padding: Tokens.Spacing.s12)
    }

    // MARK: 提示

    @ViewBuilder
    private func messages(_ store: StoryReviewStore) -> some View {
        if !store.inlineError.isEmpty {
            InlineErrorView(message: store.inlineError)
        }
        if let error = store.uiError {
            ErrorBanner(message: error.body ?? error.title, retryTitle: error.actionTitle ?? "重试") {
                Task {
                    store.clearMessages()
                    if store.recordedData != nil {
                        await store.retryRecognize()
                    } else {
                        await store.retryRetell()
                    }
                }
            }
        }
    }

    private var footerHint: some View {
        Text("复述不评分、不扣次数；说得越完整，覆盖的要点越多。")
            .font(AppFont.micro(caps))
            .foregroundStyle(Tokens.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

// MARK: - 覆盖率环

/// 复述覆盖率环：成人显示百分比，儿童只显示星星（不显示数字）。
private struct CoverageRing: View {
    let coverage: Double
    let stars: Int
    let isChild: Bool

    @Environment(\.roleCapabilities) private var caps

    private var progress: Double {
        guard coverage.isFinite, coverage > 0 else { return 0 }
        return min(max(coverage, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.Colors.surfaceSunken, lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isChild ? Tokens.Colors.childAccent : Tokens.Colors.primary,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if isChild {
                StarRow(filled: stars, starSize: 16)
            } else {
                VStack(spacing: Tokens.Spacing.s2) {
                    Text(coverage >= 0 ? "\(Int((coverage * 100).rounded()))%" : "—")
                        .font(AppFont.scoreCompact(caps, base: 26))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.Colors.primary)
                    Text("覆盖")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
        }
        .frame(width: 116, height: 116)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        if isChild {
            return "覆盖了 \(stars) 颗星"
        }
        guard coverage >= 0 else { return "暂无覆盖率" }
        return "覆盖率 \(Int((coverage * 100).rounded()))%"
    }
}

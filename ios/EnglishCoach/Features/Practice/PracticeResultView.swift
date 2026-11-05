import SwiftUI

/// 跟读详细结果（路由 `.practiceResult(attemptId:)`，全屏页）。
///
/// 分区：本次评分 → 能力雷达 → 语调曲线（成人）→ 单句历史/进步曲线 → 逐词得分（成人，
/// 只显示一遍且 <60 标红）→ 需要纠正的地方（成人）→ 整体点评。儿童不显示数字分、IPA、语调。
@MainActor
struct PracticeResultView: View {
    let attemptId: String?

    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    @State private var store: PracticeResultStore?

    init(attemptId: String?, services: AppServices, audio: AudioCoordinator) {
        self.attemptId = attemptId
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                LoadingBlock(text: "正在读取这次的结果…")
            }
        }
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .navigationTitle("详细结果")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await bootstrap()
        }
        .onDisappear {
            store?.stopPlayback()
        }
    }

    private func bootstrap() async {
        guard store == nil else { return }
        let created = PracticeResultStore(
            services: services,
            audio: audio,
            session: session,
            attemptId: attemptId
        )
        store = created
        await created.loadIfNeeded()
    }

    @ViewBuilder
    private func content(_ store: PracticeResultStore) -> some View {
        switch store.phase {
        case .idle, .loading:
            LoadingBlock(text: "正在读取这次的结果…")
                .frame(maxHeight: .infinity)
        case .failed:
            if let error = store.errorMessage {
                ErrorStateView(
                    title: error.title,
                    message: error.body ?? "",
                    retryTitle: error.actionTitle ?? "重试",
                    onRetry: { Task { await store.load() } }
                )
                .frame(maxHeight: .infinity)
            } else {
                ErrorStateView(title: "没有读取到结果", message: "请稍后重试。", onRetry: { Task { await store.load() } })
                    .frame(maxHeight: .infinity)
            }
        case .empty:
            EmptyStateView(
                icon: "chart.bar.doc.horizontal",
                title: "还没有可以查看的详细结果",
                message: "先读一句，评测完成后就能看到逐词得分、能力雷达和进步曲线了。",
                actionTitle: "返回跟读",
                action: { router.pop() }
            )
            .frame(maxHeight: .infinity)
        case .loaded:
            if let result = store.result {
                detail(result, store)
            } else {
                LoadingBlock(text: "正在读取这次的结果…")
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func detail(_ result: PracticeAttemptResult, _ store: PracticeResultStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                summaryHeader(result)

                if !caps.isChild, !result.issues.isEmpty {
                    sectionTitle("这一句的问题")
                    PracticeIssueSection(issues: result.issues)
                }

                sectionTitle("本次评分")
                PracticeScoreSection(result: result)

                if result.scores.hasAny {
                    sectionTitle("能力多边形")
                    PracticeRadarSection(scores: result.scores)
                }

                sectionTitle("这一句的历史")
                PracticeHistorySection(store: store)

                if !caps.isChild, !result.words.isEmpty {
                    sectionTitle("逐词得分")
                    PracticeWordSection(result: result)
                }

                if !caps.isChild, result.intonation.available {
                    sectionTitle("语调对比")
                    PracticeIntonationSection(intonation: result.intonation)
                }

                if !result.feedback.summary.isEmpty
                    || !result.feedback.praise.isEmpty
                    || !result.feedback.closing.isEmpty
                    || !result.feedback.points.isEmpty {
                    sectionTitle("整体点评")
                    PracticeFeedbackSection(feedback: result.feedback)
                }

                actionRow(result, store)
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryHeader(_ result: PracticeAttemptResult) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .center, spacing: Tokens.Spacing.s12) {
                if caps.isChild {
                    StarRow(filled: ScorePresenter.stars(for: result.scores.pron), starSize: 28)
                } else {
                    Text(ScorePresenter.numberText(for: result.scores.pron))
                        .font(AppFont.score(caps))
                        .monospacedDigit()
                        .foregroundStyle(ScorePresenter.color(for: result.scores.pron, isChild: false))
                }
                VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                    Text(ScorePresenter.resultTitle(for: result.scores.pron, isChild: caps.isChild))
                        .font(AppFont.title(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    Text(ScorePresenter.encouragement(for: result.scores.pron, isChild: caps.isChild))
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !result.referenceText.isEmpty {
                Text(result.referenceText)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !caps.isChild {
                HStack(spacing: Tokens.Spacing.s8) {
                    if !result.provider.isEmpty {
                        PillTag(text: result.provider, tone: .neutral)
                    }
                    if !result.durationText.isEmpty {
                        PillTag(text: result.durationText, tone: .neutral)
                    }
                    if let createdAt = result.createdAt, !createdAt.isEmpty {
                        Text(EcFormat.relative(ECJSON.date(from: createdAt) ?? Date()))
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func sectionTitle(_ title: String) -> some View {
        SectionHeader(title: title)
            .padding(.top, Tokens.Spacing.s4)
    }

    private func actionRow(_ result: PracticeAttemptResult, _ store: PracticeResultStore) -> some View {
        VStack(spacing: Tokens.Spacing.s8) {
            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(
                    title: store.isPlayingRecording ? "播放中…" : "🔁 回放这次录音",
                    kind: .ghost,
                    action: { store.playRecording() }
                )
                if result.degraded || result.retryable {
                    AppButton(title: "重试评测", kind: .tonal) {
                        Task { await store.retryEvaluate() }
                    }
                }
            }
            AppButton(title: "再读一遍") {
                PracticeResultHandoff.requestRecord()
                store.stopPlayback()
                router.pop()
            }
        }
        .padding(.top, Tokens.Spacing.s8)
    }
}

import Foundation
import SwiftUI

/// 盲测（契约 §3.15.1 / screens.md §7）：一页闭环。
///
/// 开始 → 逐题（盲听四选一 / 盲跟读，全程不给分数）→ 结束 → 周报与趋势。
/// 硬规则：揭晓前不显示原文；答错只做中性提示；儿童模式不显示数字分。
struct BlindTestView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        BlindTestScreen(services: services, audio: audio, session: session)
    }
}

// MARK: - 页面

@MainActor
private struct BlindTestScreen: View {
    @State private var store: BlindTestStore
    @State private var showsExitConfirm = false

    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        _store = State(
            initialValue: BlindTestStore(services: services, audio: audio, session: session)
        )
    }

    var body: some View {
        ZStack {
            Tokens.Colors.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                    headerCard
                    content
                }
                .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: store.isChild))
                .padding(.vertical, Tokens.Spacing.s16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle(store.isChild ? "小测验" : "盲测")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(store.phase == .running)
        .toolbar {
            if store.phase == .running {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsExitConfirm = true
                    } label: {
                        Label("退出", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("退出盲测")
                }
            }
        }
        .task {
            if !store.hasLoaded {
                await store.loadOverview()
            }
        }
        .onDisappear {
            Task { await store.teardown() }
        }
        .sheet(isPresented: $showsExitConfirm) {
            ConfirmDialog(
                title: "退出这次盲测？",
                message: "这一轮不保存进度，下次要重新开始。",
                confirmTitle: "退出",
                isDestructive: true,
                onConfirm: {
                    showsExitConfirm = false
                    Task { await store.teardown() }
                    router.pop()
                },
                onCancel: { showsExitConfirm = false }
            )
        }
    }

    // MARK: - 头部

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                Text(store.isChild ? "🎯 小测验（不给分数哦）" : "🎯 盲测（Blind Test）")
                    .font(AppFont.title(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await store.loadOverview() }
                } label: {
                    Text("刷新")
                        .font(AppFont.caption(caps))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.Colors.primary)
                .disabled(store.isLoading)
                .accessibilityLabel("刷新盲测记录")
            }

            Text(
                store.isChild
                    ? "同一组句子、全程不给分数，做完才看得到结果 —— 这样才测得准 🙂"
                    : "同一组句子、全程不给任何反馈，和上一次的成绩对比 —— 这是唯一能证明「真的进步了」的指标。"
            )
            .font(AppFont.footnote(caps))
            .foregroundStyle(Tokens.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if store.isChild, let name = store.session.user?.displayName, !name.isEmpty {
                Text("你好 \(name)！")
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
            }

            if let inProgress = store.inProgress {
                Banner(
                    message: "上一次的盲测还有 \(max(inProgress.itemCount ?? 0, 0)) 句的记录（已评 \(inProgress.scored ?? 0) · 待评 \(inProgress.pending ?? 0)）。继续会把没做的句子做完。",
                    title: "盲测进行中",
                    kind: .info
                )
            }

            if let alertCount = store.overview?.pendingTotal, alertCount > 0 {
                Banner(
                    message: "还有 \(alertCount) 条暂时显示为待评分（后台评分中…），报告里的平均分只基于已评完的记录。",
                    title: "待评分",
                    kind: .warning
                )
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if store.isLoading && !store.hasLoaded {
            LoadingBlock(text: "正在取盲测记录…")
                .cardStyle()
        } else if let error = store.loadError, !store.hasReport, store.phase == .setup {
            ErrorStateView(
                title: error.title,
                message: error.body ?? error.title,
                retryTitle: error.actionTitle ?? "重试",
                onRetry: { Task { await store.loadOverview() } }
            )
            .cardStyle()
        } else {
            if let error = store.loadError, store.hasReport {
                InlineErrorView(
                    message: error.body ?? error.title,
                    retryTitle: error.actionTitle,
                    onRetry: { Task { await store.loadOverview() } }
                )
            }
            switch store.phase {
            case .setup:
                setupSection
                if store.hasReport {
                    reportSection
                }
            case .running:
                BlindTestQuestionView(
                    store: store,
                    onRequestExit: { showsExitConfirm = true }
                )
            case .summary:
                summarySection
                reportSection
            }
        }
    }

    // MARK: - 设置

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            SectionHeader(title: "怎么测", subtitle: "先听再答，或直接跟读；全程看不到分数")
            modeChips

            if let error = store.startError {
                InlineErrorView(
                    message: error.body ?? error.title,
                    retryTitle: error.actionTitle,
                    onRetry: { Task { await store.start() } }
                )
            }
            if let notice = store.setupNotice {
                Banner(message: notice, kind: .info)
            }

            AppButton(
                title: store.isPreparing
                    ? "正在抽题…"
                    : (store.inProgress == nil ? "开始盲测" : "继续上一次盲测"),
                icon: "play.fill",
                kind: .primary,
                isLoading: store.isPreparing,
                action: { Task { await store.start() } }
            )

            if store.inProgress != nil {
                AppButton(
                    title: "结束上一次并查看报告",
                    kind: .tonal,
                    isLoading: store.isFinishing,
                    action: { Task { await store.finishInProgress() } }
                )
            }

            Text("抽题来自你练过的语料；同一用户每次得到同一组句子。没有练过的句子时服务端会提示先练习。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var modeChips: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("出题方式")
                .font(AppFont.footnote(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
            HStack(spacing: Tokens.Spacing.s8) {
                modeChip(.listen, title: "盲听选择")
                modeChip(.read, title: "盲跟读")
                modeChip(.alternating, title: "交替")
            }
        }
    }

    private func modeChip(_ option: BlindModeOption, title: String) -> some View {
        let selected = store.modeOption == option
        return Button {
            store.modeOption = option
        } label: {
            Text(title)
                .font(AppFont.caption(caps))
                .foregroundStyle(selected ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
                .padding(.horizontal, Tokens.Spacing.s12)
                .padding(.vertical, Tokens.Spacing.s8)
                .frame(minHeight: max(caps.minTapTarget, 36))
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Tokens.Colors.primary : Tokens.Colors.surfaceSunken)
                )
        }
        .buttonStyle(.plain)
        .disabled(store.phase != .setup)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 结束

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            SectionHeader(title: "🎉 盲测完成", subtitle: "这一轮结束，看看和上次比有没有进步")

            if let notice = store.finishNotice, !notice.isEmpty {
                Banner(message: notice, kind: .warning)
            }

            if let error = store.finishError {
                InlineErrorView(
                    message: error.body ?? error.title,
                    retryTitle: error.actionTitle,
                    onRetry: { Task { await store.finish() } }
                )
            }

            if let result = store.finishResult {
                if store.isChild {
                    childFinishSummary(result)
                } else {
                    adultFinishSummary(result)
                }
                Text(countsText)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AppButton(
                title: "再测一次",
                icon: "arrow.clockwise",
                kind: .tonal,
                action: { store.restart() }
            )
            AppButton(
                title: "去错音本复习",
                icon: "text.book.closed.fill",
                kind: .ghost,
                action: { router.push(.review) }
            )
            AppButton(
                title: "去跟读练习",
                icon: "mic.fill",
                kind: .text,
                action: { router.push(.sentences) }
            )
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func adultFinishSummary(_ result: BlindFinishDTO) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            HStack(alignment: .center, spacing: Tokens.Spacing.s16) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                    Text(EcFormat.scoreText(result.avgPron))
                        .font(AppFont.score(caps))
                        .foregroundStyle(Tokens.Score.color(for: result.avgPron, isChild: false))
                        .monospacedDigit()
                    Text("综合分")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    ScoreBar(label: "准确度", score: result.avgAccuracy)
                    ScoreBar(label: "流利度", score: result.avgFluency)
                    ScoreBar(label: "语调差异", score: result.avgIntonationDistance)
                }
            }
        }
    }

    private func childFinishSummary(_ result: BlindFinishDTO) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(spacing: Tokens.Spacing.s8) {
                StarRow(filled: ScorePresenter.stars(for: result.avgPron))
                Text(ScorePresenter.encouragement(for: result.avgPron, isChild: true))
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !store.wrongSentences.isEmpty {
                Text("有 \(store.wrongSentences.count) 句没听出来，等会儿多读两遍就好啦。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
    }

    private var countsText: String {
        var parts: [String] = []
        parts.append("已评 \(store.finishScoredCount) 句")
        if store.finishPendingCount > 0 {
            parts.append("另有 \(store.finishPendingCount) 条待评分（未计入）")
        }
        return "本次报告基于：" + parts.joined(separator: "；") + "。"
    }

    // MARK: - 周报

    @ViewBuilder
    private var reportSection: some View {
        if store.hasReport {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("📈 盲测周报")
                        .font(AppFont.heading(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    Spacer(minLength: Tokens.Spacing.s8)
                    Text("已完成 \(store.weeks) 次")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                }

                if store.isChild {
                    Text("你做完 \(store.weeks) 次小测验啦，做得很好！")
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                } else {
                    HStack(alignment: .center, spacing: Tokens.Spacing.s16) {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                            Text(EcFormat.scoreText(store.currentPron))
                                .font(AppFont.score(caps))
                                .foregroundStyle(Tokens.Score.color(for: store.currentPron, isChild: false))
                                .monospacedDigit()
                            Text("最近一次综合分")
                                .font(AppFont.micro(caps))
                                .foregroundStyle(Tokens.Colors.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                            Text("与上一次相比")
                                .font(AppFont.micro(caps))
                                .foregroundStyle(Tokens.Colors.textSecondary)
                            Text(deltaText)
                                .font(AppFont.heading(caps))
                                .foregroundStyle(deltaColor)
                            Text("上次：\(EcFormat.scoreText(store.previousPron)) 分")
                                .font(AppFont.micro(caps))
                                .foregroundStyle(Tokens.Colors.textTertiary)
                        }
                    }
                    if let current = store.trend?.current {
                        ScoreBar(label: "准确度", score: current.avgAccuracy)
                        ScoreBar(label: "流利度", score: current.avgFluency)
                        ScoreBar(label: "语调差异", score: current.avgIntonationDistance)
                    }
                }

                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text("历次盲测（柱越高越好）")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                    BarChartView(
                        items: store.seriesBars,
                        height: 150,
                        showsValues: !store.isChild
                    )
                }

                if !store.history.isEmpty {
                    Divider()
                        .overlay(Tokens.Colors.borderSubtle)
                    Text("历史记录")
                        .font(AppFont.footnote(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    ForEach(store.history.prefix(5)) { test in
                        historyRow(test)
                    }
                }
            }
            .padding(Tokens.Spacing.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    private func historyRow(_ test: BlindTestDTO) -> some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.s8) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text(historyDateText(test) + " · \(test.itemCount ?? 0) 句")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                if !store.isChild {
                    Text("综合分 \(EcFormat.scoreText(test.avgPron)) · 准确 \(EcFormat.scoreText(test.avgAccuracy)) · 流利 \(EcFormat.scoreText(test.avgFluency))")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    StarRow(filled: ScorePresenter.stars(for: test.avgPron), starSize: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let pending = test.pending, pending > 0 {
                PillTag(text: "待评分 \(pending)", tone: .warning, isCompact: true)
            }
        }
        .padding(.vertical, Tokens.Spacing.s2)
    }

    private func historyDateText(_ test: BlindTestDTO) -> String {
        guard let date = ECJSON.date(from: test.endedAt) else {
            return "—"
        }
        return EcFormat.monthDayText(date)
    }

    private var deltaText: String {
        guard store.trend != nil else {
            return "还没有盲测数据"
        }
        guard let delta = store.deltaPron else {
            return "首次（无对比）"
        }
        if delta > 0 {
            return "▲ +" + oneDecimal(delta)
        }
        if delta < 0 {
            return "▼ " + oneDecimal(delta)
        }
        return "＝ 0"
    }

    private var deltaColor: Color {
        guard let delta = store.deltaPron else {
            return Tokens.Colors.textSecondary
        }
        if delta > 0 {
            return Tokens.Colors.successText
        }
        if delta < 0 {
            return Tokens.Colors.dangerText
        }
        return Tokens.Colors.textSecondary
    }

    private func oneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f", rounded)
    }
}

import SwiftUI

/// 错音本（SRS，契约 §3.15.1 / screens.md §8）：卡片 + 4 档评分 + 弱音素趋势。
///
/// 端点注意：评分实际是 `POST /review {card_id, grade}`（HOS/Android 实测），
/// 契约 §3.7 注释里的 `review/:id/grade` 是笔误。
struct ReviewView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        ReviewScreen(services: services, audio: audio, session: session)
    }
}

// MARK: - 页面

@MainActor
private struct ReviewScreen: View {
    @State private var store: ReviewStore

    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        _store = State(
            initialValue: ReviewStore(services: services, audio: audio, session: session)
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
        .navigationTitle(store.isChild ? "小错音本" : "错音本")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !store.hasLoaded {
                await store.load()
            }
        }
        .onDisappear {
            Task { await store.audio.stopAll() }
        }
    }

    // MARK: - 头部

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text(store.isChild ? "📒 我的小错音本" : "📒 错音本 / SRS 复习")
                .font(AppFont.title(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if store.hasLoaded {
                Text(headerStatsText)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(store.algorithmText)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = store.gradeNotice {
                Banner(message: notice, kind: .success)
            }
            if let error = store.gradeError {
                InlineErrorView(message: error.body ?? error.title)
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var headerStatsText: String {
        "待复习 \(store.dueCards) 张 · 卡片总数 \(store.totalCards) 张 · 音素记录 \(store.phonemeRows) 条 · 今日 \(store.minutesTodayText) 分钟"
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if store.isLoading && !store.hasLoaded {
            LoadingBlock(text: "正在整理错音本…")
                .cardStyle()
        } else if let error = store.loadError, !store.hasAnyData {
            ErrorStateView(
                title: error.title,
                message: error.body ?? error.title,
                retryTitle: error.actionTitle ?? "重试",
                onRetry: { Task { await store.load() } }
            )
            .cardStyle()
        } else {
            if let error = store.loadError {
                InlineErrorView(
                    message: error.body ?? error.title,
                    retryTitle: error.actionTitle,
                    onRetry: { Task { await store.load() } }
                )
            }

            if store.cards.isEmpty {
                EmptyStateView(
                    icon: "📒",
                    title: "今天没有要复习的了",
                    message: store.isChild
                        ? "读错的句子会出现在这里，隔几天再来看看就好。"
                        : "错音本按遗忘曲线排期；现在没有到期卡片，去跟读几句就会有新的了。",
                    actionTitle: "去跟读练习",
                    action: { router.push(.sentences) }
                )
                .cardStyle()
            } else {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                    SectionHeader(
                        title: "待复习（\(store.cards.count)）",
                        subtitle: "选一个最符合你感觉的按钮"
                    )
                    ForEach(store.cards) { card in
                        cardView(card)
                    }
                }
            }

            if !store.weakPhonemes.isEmpty {
                weakPhonemesSection
            }
            if !store.wordErrors.isEmpty {
                wordErrorsSection
            }
        }
    }

    // MARK: - 卡片

    private func cardView(_ card: ReviewCardDTO) -> some View {
        let isGrading = store.gradingCardID == card.id
        return VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                let badge = store.badgeText(card)
                if !badge.isEmpty {
                    PillTag(text: badge, tone: .primary)
                }
                Text(store.cardTitle(card))
                    .font(AppFont.heading(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let meta = store.metaText(card)
            if !meta.isEmpty {
                Text(meta)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let why = store.whyText(card)
            if !why.isEmpty {
                Text(why)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let how = store.howText(card)
            if !how.isEmpty {
                Text(how)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let words = store.practiceWordsText(card)
            if !words.isEmpty {
                Text(words)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AppButton(
                title: store.isPreparingDemo ? "正在准备示范…" : "🔊 听示范",
                kind: .ghost,
                isLoading: store.isPreparingDemo,
                isEnabled: store.gradingCardID == nil,
                action: { Task { await store.playDemo(card) } }
            )

            if isGrading {
                HStack(spacing: Tokens.Spacing.s8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在记录…")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                .frame(minHeight: 44)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Tokens.Spacing.s8),
                        GridItem(.flexible(), spacing: Tokens.Spacing.s8)
                    ],
                    spacing: Tokens.Spacing.s8
                ) {
                    ForEach(ReviewStore.gradeKinds, id: \.self) { grade in
                        gradeButton(card: card, grade: grade)
                    }
                }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func gradeButton(card: ReviewCardDTO, grade: String) -> some View {
        Button {
            Task { await store.grade(cardID: card.id, grade: grade) }
        } label: {
            Text(store.gradeLabel(grade))
                .font(AppFont.callout(caps))
                .foregroundStyle(grade == "good" ? Tokens.Colors.onPrimary : Tokens.Colors.primary)
                .frame(maxWidth: .infinity, minHeight: max(caps.minTapTarget, 44))
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(
                            grade == "good"
                                ? Tokens.Colors.primary
                                : Tokens.Colors.surfaceMuted
                        )
                )
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(store.gradingCardID != nil)
        .accessibilityLabel(store.gradeLabel(grade))
    }

    // MARK: - 弱音素

    private var weakPhonemesSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            SectionHeader(title: "弱音素趋势", subtitle: "按平均分从低到高")
            ForEach(Array(store.weakestThree().enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                        Text(store.weakPhonemeLabel(item))
                            .font(AppFont.heading(caps))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                        Spacer(minLength: Tokens.Spacing.s8)
                        if !store.isChild {
                            Text("\(item.attempts ?? 0) 次")
                                .font(AppFont.micro(caps))
                                .foregroundStyle(Tokens.Colors.textTertiary)
                        }
                    }
                    ScoreBar(
                        label: store.isChild ? "掌握度" : "平均分",
                        score: item.avgScore,
                        showsValue: !store.isChild
                    )
                    let points = store.trendPoints(for: item)
                    if points.count >= 2 {
                        TrendLineChart(points: points, height: 84, showsPointLabels: false)
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
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - 高频错词

    private var wordErrorsSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            SectionHeader(title: "高频错词", subtitle: "最近评测里最常读错的词")
            ForEach(Array(store.wordErrors.prefix(8).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                    Text(item.word ?? "—")
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(item.count ?? 0) 次")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    if !store.isChild, let avg = item.avgScore {
                        Text("\(EcFormat.scoreText(avg)) 分")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Score.color(for: avg, isChild: false))
                    }
                }
                .frame(minHeight: 36)
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

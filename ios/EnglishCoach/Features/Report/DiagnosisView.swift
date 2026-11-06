import SwiftUI

/// 成长（发音诊断 + 最近 7 天趋势，契约 §3.15.1 / screens.md §8）。
///
/// 数据：`GET /diagnosis`（四个 scope，attempt/batch 需上游带评测 id）+
/// `GET /attempts?limit=`（本地近 7 天趋势）+ `GET /review`（错音本待复习数）。
/// 儿童：不显示 IPA / 数字分 / 百分比，只给星星、进度条和可读建议。
struct DiagnosisView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        DiagnosisScreen(services: services, audio: audio, session: session)
    }
}

// MARK: - 页面

@MainActor
private struct DiagnosisScreen: View {
    @State private var store: DiagnosisStore

    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        _store = State(
            initialValue: DiagnosisStore(services: services, audio: audio, session: session)
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
        .navigationTitle(store.isChild ? "我的成长" : "发音诊断")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !store.hasLoaded {
                await store.load()
            }
            if !store.hasLoadedGrowth {
                await store.loadGrowth()
            }
        }
        .onDisappear {
            Task { await store.audio.stopAll() }
        }
    }

    // MARK: - 头部

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            Text(store.isChild ? "🔍 我的发音报告" : "🔍 发音诊断报告")
                .font(AppFont.title(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            scopeChips

            if let notice = store.scopeNotice {
                Banner(message: notice, kind: .info)
            }

            if !store.summaryZh.isEmpty {
                Text(store.summaryZh)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.hasLoaded {
                Text(store.metricText)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !store.topItems.isEmpty {
                HStack(spacing: Tokens.Spacing.s8) {
                    Text(store.isChild ? "🎯 可以再练一练：" : "🎯 最近最需要练的：")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    ForEach(Array(store.topItems.enumerated()), id: \.offset) { _, item in
                        PillTag(
                            text: store.itemTitle(item),
                            tone: store.statusTone(item.status)
                        )
                    }
                }
            }

            if let mastery = store.masteryScore {
                if store.isChild {
                    HStack(spacing: Tokens.Spacing.s8) {
                        StarRow(filled: ScorePresenter.stars(for: mastery))
                        Text("多练几次会更清楚")
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                } else {
                    ScoreBar(label: "掌握度总览", score: mastery, showsValue: true)
                }
            }

            if let first = store.items.first {
                let tip = store.tipText(first)
                if !tip.isEmpty {
                    Text((store.isChild ? "💡 " : "💡 建议：") + tip)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(
                    title: store.isChild ? "🎯 去练一练" : "🚀 去跟读练习",
                    kind: .primary,
                    action: { router.push(.sentences) }
                )
                AppButton(
                    title: store.dueCards > 0 ? "错音本 \(store.dueCards)" : "错音本",
                    kind: .tonal,
                    action: { router.push(.review) }
                )
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.s8) {
                ForEach(DiagnosisScope.allCases, id: \.rawValue) { scope in
                    scopeChip(scope)
                }
            }
            .padding(.vertical, Tokens.Spacing.s2)
        }
    }

    private func scopeChip(_ scope: DiagnosisScope) -> some View {
        let selected = store.scope == scope
        let gated = scope.needsAttemptIDs && store.pendingAttemptIds.isEmpty
        return Button {
            Task { await store.switchScope(scope) }
        } label: {
            HStack(spacing: Tokens.Spacing.s4) {
                Text(scope.title)
                    .font(AppFont.caption(caps))
                if gated {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
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
        .disabled(store.isLoading)
        .accessibilityLabel(scope.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if store.isLoading && !store.hasLoaded {
            LoadingBlock(text: "正在统计发音…")
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

            growthSection

            if store.hasLoaded && store.items.isEmpty && store.okItems.isEmpty {
                EmptyStateView(
                    icon: "📊",
                    title: "还没有足够的记录",
                    message: store.isChild
                        ? "还没有够多的练习记录，多读几句就有报告啦"
                        : "每个音素至少 \(store.minSamples) 次评测才会统计，先去跟读几句吧",
                    actionTitle: "去跟读练习",
                    action: { router.push(.sentences) }
                )
                .cardStyle()
            } else {
                if !store.items.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                        SectionHeader(
                            title: "需要练的音素",
                            subtitle: "薄弱 \(store.weakCount) · 待巩固 \(store.watchCount)"
                        )
                        ForEach(Array(store.items.enumerated()), id: \.offset) { _, item in
                            itemCard(item)
                        }
                    }
                }
                if !store.okItems.isEmpty {
                    okSection
                }
            }

            Text("诊断依据：每个音素的历次评测均分与最近 3 次趋势；" +
                 (store.minSamples < 2 ? "本口径 1 次记录也参与。" : "1 次记录不参与（噪声太大）。"))
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 最近 7 天（本地）

    private var growthSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            SectionHeader(title: "最近 7 天练习", subtitle: "来自本机的评测记录")
            if store.weekAttemptCount > 0 {
                TrendLineChart(
                    points: store.weekTrend,
                    height: 150,
                    showsPointLabels: !store.isChild
                )
                Text(weekSummaryText)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                    Text(store.hasLoadedGrowth ? "最近 7 天还没有练习记录。" : "正在读取练习记录…")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    if store.hasLoadedGrowth {
                        AppButton(
                            title: "先去读 3 句",
                            kind: .ghost,
                            action: { router.push(.sentences) }
                        )
                    }
                }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var weekSummaryText: String {
        let count = store.weekAttemptCount
        if store.isChild {
            return "最近 7 天练了 \(count) 次，坚持得真好！"
        }
        let avg = EcFormat.scoreText(store.weekAverage)
        return "最近 7 天练了 \(count) 次，平均 \(avg) 分。"
    }

    // MARK: - 音素卡片

    private func itemCard(_ item: DiagnosisItemDTO) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                Text(store.itemTitle(item))
                    .font(AppFont.heading(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                PillTag(text: store.statusTitle(item.status), tone: store.statusTone(item.status))
            }

            Text(store.scoreLine(item))
                .font(AppFont.caption(caps))
                .foregroundStyle(scoreLineColor(item.status))

            let trend = store.trendText(item)
            if !trend.isEmpty {
                Text(trend)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }

            let tip = store.tipText(item)
            if !tip.isEmpty {
                Text((item.status == "weak" ? "👄 口型要点：" : "👄 ") + tip)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !store.isChild, let errors = item.commonErrors, !errors.isEmpty {
                Text("⚠️ 常见错误：" + errors.joined(separator: " · "))
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let contrasts = store.contrasts(item)
            if !contrasts.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                    ForEach(Array(contrasts.enumerated()), id: \.offset) { _, contrast in
                        let pair = (contrast.pair ?? []).joined(separator: " → ")
                        Text("🔀 \(pair)：\(contrast.note ?? "")")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let examples = item.examples, !examples.isEmpty {
                Text("相关的词：" + examples.joined(separator: " · "))
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(
                    title: "🔊 听示范",
                    kind: .ghost,
                    action: { Task { await store.playDemo(item) } }
                )
                if !store.practiceCountText(item).isEmpty {
                    AppButton(
                        title: store.practiceCountText(item),
                        kind: .tonal,
                        action: { router.push(.sentences) }
                    )
                }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .stroke(
                    item.status == "weak" ? Tokens.Colors.warning : Tokens.Colors.borderSubtle,
                    lineWidth: item.status == "weak" ? 1.5 : 1
                )
        )
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private func scoreLineColor(_ status: String?) -> Color {
        switch status {
        case "weak":
            return Tokens.Colors.dangerText
        case "watch":
            return Tokens.Colors.warningText
        default:
            return Tokens.Colors.successText
        }
    }

    private var okSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Button {
                store.showOk.toggle()
            } label: {
                HStack {
                    Text("已经掌握的音素（\(store.okItems.count)）")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    Spacer(minLength: Tokens.Spacing.s8)
                    Text(store.showOk ? "收起" : "点击展开")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.primary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            if store.showOk {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: Tokens.Spacing.s8)],
                    alignment: .leading,
                    spacing: Tokens.Spacing.s8
                ) {
                    ForEach(Array(store.okItems.enumerated()), id: \.offset) { _, item in
                        PillTag(text: store.itemTitle(item), tone: .success)
                    }
                }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

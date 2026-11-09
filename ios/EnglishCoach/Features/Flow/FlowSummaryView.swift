import SwiftUI

/// 连读汇总（路由 `.flowSummary`）：平均分 / 最差句 / 鼓励语 / 批次诊断 / 逐句列表 / 再读一遍。
///
/// 数据来自 `FlowRunRegistry.store`（FlowView 创建并持有的运行态）；直达该路由时显示空态。
@MainActor
struct FlowSummaryView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    @State private var store: FlowStore?

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                EmptyStateView(
                    icon: "chart.bar.doc.horizontal",
                    title: "还没有读完一轮连读",
                    message: "先回连读页读几句，读完就能看到这一批的汇总与诊断。",
                    actionTitle: "返回连读",
                    action: { router.pop() }
                )
                .frame(maxHeight: .infinity)
            }
        }
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .navigationTitle("连读汇总")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await bootstrap()
        }
    }

    private func bootstrap() async {
        if store == nil {
            store = FlowRunRegistry.store
        }
        await store?.loadDiagnosisIfNeeded()
    }

    // MARK: - 内容

    private func content(_ store: FlowStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                headerCard(store)
                encouragementCard(store)
                diagnosisCard(store)

                sectionTitle(caps.isChild ? "这几句可以再读一遍" : "最需要再练的几句")
                worstCard(store)

                actionRow(store)

                sectionTitle("逐句列表")
                LazyVStack(spacing: Tokens.Spacing.s8) {
                    ForEach(store.items) { item in
                        FlowItemRow(
                            item: item,
                            badge: store.statusBadge(item),
                            tone: store.statusTone(item),
                            isExpanded: store.expandedIndex == item.index,
                            onTap: {
                                store.toggleExpanded(index: item.index)
                            },
                            onRetry: {
                                store.retryItem(index: item.index)
                                router.pop()
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
            .contentColumn(alignment: .center)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        SectionHeader(title: title)
            .padding(.top, Tokens.Spacing.s4)
    }

    // MARK: - 头部

    private func headerCard(_ store: FlowStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                Text(caps.isChild ? "🎉 读完啦！" : "🎉 连读完成")
                    .font(AppFont.title(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Spacer(minLength: 0)
                if store.summary.round > 1 {
                    PillTag(text: "第 \(store.summary.round) 遍", tone: .primary)
                }
            }
            Text(summaryLine(store))
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            if let avg = store.summary.avgScore, caps.showsNumericScore {
                HStack(spacing: Tokens.Spacing.s12) {
                    ScoreRing(score: avg, label: "平均分", ringSize: 92)
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                        Text("已评分 \(store.summary.doneCount) 句")
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                        Text("失败 \(store.summary.failedCount) 句")
                            .font(AppFont.caption(caps))
                            .foregroundStyle(store.summary.failedCount > 0 ? Tokens.Colors.dangerText : Tokens.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func summaryLine(_ store: FlowStore) -> String {
        let data = store.summary
        var text = "共 \(data.total) 句 · 已评分 \(data.doneCount) 句"
        if data.failedCount > 0 {
            text += " · 失败 \(data.failedCount) 句"
        }
        if let avg = data.avgScore, caps.showsNumericScore {
            text += " · 平均 \(ScorePresenter.numberText(for: avg)) 分"
        }
        if data.round > 1 {
            text += " · 第 \(data.round) 遍"
        }
        return text
    }

    // MARK: - 鼓励语

    private func encouragementCard(_ store: FlowStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            Text(caps.isChild ? "听听夸奖" : "鼓励语")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
            Text(encouragementText(store))
                .font(caps.isChild ? AppFont.body(caps) : AppFont.bodyEmphasis(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !store.summary.encouragement.en.isEmpty {
                Text(store.summary.encouragement.en)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceMuted)
        )
    }

    private func encouragementText(_ store: FlowStore) -> String {
        let data = store.summary.encouragement
        guard !data.praise.isEmpty else { return data.zh }
        return data.zh + data.praise
    }

    // MARK: - 批次诊断

    private func diagnosisCard(_ store: FlowStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("这一批（\(store.summary.doneCount) 句）的问题")
                .font(AppFont.bodyEmphasis(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            switch store.diagnosisPhase {
            case .idle, .loading:
                LoadingBlock(text: "正在统计…")
            case .failed:
                if let error = store.diagnosisError {
                    InlineErrorView(
                        message: [error.title, error.body].compactMap { $0 }.joined(separator: " "),
                        retryTitle: "重试",
                        onRetry: { Task { await store.loadDiagnosis() } }
                    )
                }
            default:
                if !store.diagnosisSummary.isEmpty {
                    Text(store.diagnosisSummary)
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !store.diagnosisTags.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120), spacing: Tokens.Spacing.s8)],
                        alignment: .leading,
                        spacing: Tokens.Spacing.s8
                    ) {
                        ForEach(store.diagnosisTags) { tag in
                            PillTag(text: tag.label, tone: diagnosisTone(tag.status))
                        }
                    }
                }
                if store.summary.doneCount == 0 {
                    Text("这一批还没有评完的句子，暂时没有诊断。")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func diagnosisTone(_ status: String) -> PillTag.Tone {
        switch status {
        case "weak": return caps.isChild ? .warning : .danger
        case "watch": return .warning
        case "ok": return .success
        default: return .neutral
        }
    }

    // MARK: - 最差句

    private func worstCard(_ store: FlowStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            if store.summary.worst.isEmpty {
                Text("这一批没有拿到分数，先不用纠结分数，读得开心最重要 🙂")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(store.summary.worst) { row in
                    Text(worstLine(row))
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func worstLine(_ row: FlowWorstItem) -> String {
        if caps.showsNumericScore, let score = row.score {
            return "· \(ScorePresenter.numberText(for: score)) 分 · \(row.text)"
        }
        return "· \(row.text)"
    }

    // MARK: - 动作

    private func actionRow(_ store: FlowStore) -> some View {
        VStack(spacing: Tokens.Spacing.s8) {
            AppButton(title: caps.isChild ? "🔁 再读一遍～" : "🔁 再读一遍") {
                store.reread()
                router.pop()
            }
            AppButton(title: "再读一段", kind: .ghost) {
                store.backToSetup()
                router.pop()
            }
        }
        .padding(.top, Tokens.Spacing.s8)
    }
}

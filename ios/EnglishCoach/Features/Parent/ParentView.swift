import SwiftUI

/// 家长面板（契约 §3.15.1：`ParentView(services:audio:)`）。
///
/// 数据：`GET /parent/summary`（结构【待确认】→ 容错渲染）。403 显示无权限页，
/// 但不跳登录（儿童误入只提示“仅家长可用”）。设计参照 `ios/docs/screens.md` §9。
struct ParentView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    @State private var viewModel: ParentViewModel?

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingBlock(text: "正在加载家长数据…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("家长面板")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = ParentViewModel(services: services, audio: audio, session: session)
            await model.load()
            viewModel = model
        }
    }

    @ViewBuilder
    private func content(_ model: ParentViewModel) -> some View {
        switch model.loadState {
        case .idle, .loading:
            ScrollView {
                VStack(spacing: Tokens.Spacing.s12) {
                    SkeletonBlock(height: 96)
                    SkeletonBlock(height: 72)
                    SkeletonBlock(height: 140)
                }
                .padding(Tokens.Spacing.s16)
            }
            .background(Tokens.Colors.canvas.ignoresSafeArea())

        case .failed(let message):
            if model.forbidden {
                EmptyStateView(
                    icon: "lock.shield",
                    title: message.title,
                    message: message.body,
                    actionTitle: "返回",
                    action: { router.pop() }
                )
                .padding(Tokens.Spacing.s24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.Colors.canvas.ignoresSafeArea())
            } else {
                ErrorStateView(
                    title: message.title,
                    message: message.body ?? "",
                    retryTitle: "重试",
                    onRetry: { Task { await model.load(force: true) } }
                )
                .padding(Tokens.Spacing.s24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.Colors.canvas.ignoresSafeArea())
            }

        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                    summaryCard(model)

                    if !model.children.isEmpty {
                        childrenSection(model)
                    }

                    quickActions

                    if model.members.isEmpty {
                        EmptyStateView(
                            icon: "person.badge.plus",
                            title: "还没有孩子账号",
                            message: "先在「家庭成员」里建一个孩子账号，练习数据才会出现在这里。",
                            actionTitle: "去添加成员",
                            action: { router.push(.family) }
                        )
                        .cardStyle()
                    } else {
                        Text("成员明细")
                            .font(AppFont.caption(caps).weight(.semibold))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .padding(.leading, Tokens.Spacing.s4)

                        ForEach(model.members, id: \.id) { member in
                            memberCard(model, member)
                        }
                    }

                    Text("家长只能看汇总与诊断，不能浏览孩子的录音列表；这是隐私边界（screens.md §9.4）。")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Tokens.Spacing.s16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Tokens.Colors.canvas.ignoresSafeArea())
            .refreshable { await model.load(force: true) }
        }
    }

    // MARK: - 汇总卡

    private func summaryCard(_ model: ParentViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(spacing: Tokens.Spacing.s8) {
                Image(systemName: "person.2.badge.gearshape")
                    .foregroundStyle(Tokens.Colors.primary)
                    .accessibilityHidden(true)
                Text("家长看板")
                    .font(AppFont.heading(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Spacer(minLength: 0)
            }
            Text(model.familyText)
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.memberCountText)
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private func childrenSection(_ model: ParentViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text("今日剩余时长")
                .font(AppFont.caption(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .padding(.leading, Tokens.Spacing.s4)
            HStack(spacing: Tokens.Spacing.s8) {
                ForEach(model.children, id: \.id) { child in
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                        Text(child.displayName ?? "孩子")
                            .font(AppFont.footnote(caps).weight(.semibold))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                        Text(model.childRemainingText(child))
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                    .padding(Tokens.Spacing.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                            .fill(Tokens.Colors.surfaceSunken)
                    )
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: Tokens.Spacing.s8) {
            AppButton(title: "家庭成员", icon: "person.3", kind: .tonal) {
                router.push(.family)
            }
            AppButton(title: "建议箱", icon: "tray.full", kind: .tonal) {
                router.push(.suggestions)
            }
            AppButton(title: "服务状态", icon: "stethoscope", kind: .tonal) {
                router.push(.health)
            }
        }
    }

    // MARK: - 成员卡

    private func memberCard(_ model: ParentViewModel, _ member: ParentMemberDTO) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                Text(model.memberTitle(member))
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                PillTag(text: model.memberBadge(member), tone: .primary)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: Tokens.Spacing.s2) {
                    Text("最近一次盲测综合分")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                    Text(model.blindScoreText(member))
                        .font(AppFont.scoreCompact(caps, base: 24))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                }
            }

            Text(model.todayText(member))
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let week = model.weekText(member) {
                Text(week)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Tokens.Spacing.s8) {
                Text("本周 vs 上次")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                if let delta = model.blindDelta(member) {
                    PillTag(text: delta.text, tone: tone(for: delta.tone))
                }
                if let weeks = model.blindWeeksText(member) {
                    PillTag(text: weeks, tone: .neutral)
                }
                Spacer(minLength: 0)
            }

            if let series = model.blindSeriesText(member) {
                Text(series)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }

            if let trend = model.trendTail(member) {
                Text(trend)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }

            if model.topPhonemes(member).isEmpty {
                Text("高频错音：暂无数据")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            } else {
                let phonemes = model.topPhonemes(member)
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text("高频错音")
                        .font(AppFont.micro(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    ForEach(Array(phonemes.prefix(3).indices), id: \.self) { index in
                        HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                            Text(model.phonemeText(phonemes[index]))
                                .font(AppFont.caption(caps))
                                .foregroundStyle(Tokens.Colors.textPrimary)
                            Text(model.phonemeMeta(phonemes[index]))
                                .font(AppFont.micro(caps))
                                .foregroundStyle(Tokens.Colors.textSecondary)
                        }
                    }
                }
            }

            if !model.topWords(member).isEmpty {
                let words = model.topWords(member)
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text("高频错词（单词级粗评）")
                        .font(AppFont.micro(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    ForEach(Array(words.prefix(3).indices), id: \.self) { index in
                        Text(model.wordText(words[index]))
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
            }

            Text("盲测：同一组句子、全程不给反馈。日常练习的分数会因为「看完反馈立刻重读」而虚高，只有盲测能证明真的进步了。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private func tone(for tone: ParentViewModel.DeltaTone) -> PillTag.Tone {
        switch tone {
        case .up: return .success
        case .down: return .danger
        case .flat: return .neutral
        case .unknown: return .neutral
        }
    }
}

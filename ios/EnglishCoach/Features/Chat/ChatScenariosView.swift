import SwiftUI

/// 对话场景列表（Tab 2 / `.chatScenarios`）。
///
/// 入口：`.task` + `.onAppear`（从自定义场景页返回时刷新）；点卡片直接开会话并 push `.chatSession`。
struct ChatScenariosView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var store: ChatScenariosStore?

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        ZStack {
            Tokens.Colors.canvas.ignoresSafeArea()
            if let store {
                ChatScenariosContent(
                    store: store,
                    onOpenHistory: { router.push(.chatHistory) },
                    onStart: { scenario in
                        Task {
                            if let sessionID = await store.start(scenario) {
                                router.push(.chatSession(sessionId: sessionID))
                            }
                        }
                    },
                    onCreate: { router.push(.chatCustom(scenarioId: nil)) },
                    onEdit: { scenario in router.push(.chatCustom(scenarioId: scenario.id)) }
                )
            } else {
                LoadingBlock(text: "正在取场景…")
            }
        }
        .task {
            let resolved = store ?? ChatScenariosStore(services: services, audio: audio, session: session)
            store = resolved
            await resolved.appear()
        }
        .onAppear {
            guard let store else { return }
            Task { await store.appear() }
        }
    }
}

// MARK: - 内容

private struct ChatScenariosContent: View {
    let store: ChatScenariosStore
    let onOpenHistory: () -> Void
    let onStart: (ChatScenarioDTO) -> Void
    let onCreate: () -> Void
    let onEdit: (ChatScenarioDTO) -> Void

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                heroCard
                if let failure = store.failure {
                    ErrorBanner(
                        message: failure.body ?? failure.title,
                        retryTitle: failure.isRetryable ? "重试" : "知道了",
                        onRetry: { Task { await store.reload() } }
                    )
                }
                if store.isQuotaExceeded {
                    Banner(message: store.quotaText.isEmpty ? "今天的练习时间到啦，明天再来" : store.quotaText, kind: .warning)
                }
                content
                footer
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
        }
        .refreshable { await store.reload() }
    }

    /// 对齐 web：一张 hero 卡里放标题/用量 + 大号「自动朗读」按钮 + 语速胶囊。
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s12) {
                Text(store.isChild ? "💬 和我聊聊天吧！" : "💬 对话训练")
                    .font(AppFont.titleLarge(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Spacer(minLength: 0)
                Button(action: onOpenHistory) {
                    Text("🕘 历史")
                        .font(AppFont.caption(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.primary)
                        .padding(.horizontal, Tokens.Spacing.s12)
                        .frame(minHeight: caps.minTapTarget)
                        .background(Capsule(style: .continuous).fill(Tokens.Colors.surfaceMuted))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("打开对话历史"))
            }

            Text(store.audienceHint)
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let usage = store.usageText {
                Text(usage)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }

            Button {
                store.setAutoRead(!store.autoRead)
            } label: {
                HStack(spacing: Tokens.Spacing.s8) {
                    Image(systemName: store.autoRead ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    Text("自动朗读：\(store.autoRead ? "开" : "关")")
                    Spacer(minLength: 0)
                }
                .font(AppFont.bodyEmphasis(caps))
                .foregroundStyle(store.autoRead ? Tokens.Colors.onPrimary : Tokens.Colors.primary)
                .padding(.horizontal, Tokens.Spacing.s16)
                .frame(maxWidth: .infinity, minHeight: caps.minTapTarget, alignment: .leading)
                .background(
                    Capsule(style: .continuous)
                        .fill(store.autoRead ? Tokens.Colors.primary : Tokens.Colors.surfaceMuted)
                )
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(Text(store.autoRead ? "关闭自动朗读" : "打开自动朗读"))

            Text(store.autoRead
                 ? "每条回复会自动读出来；点气泡上的 ▶ 也可以再听一遍。"
                 : "关着：点气泡上的 ▶ 才读。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Tokens.Spacing.s8) {
                Text("朗读语速：")
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                ratePill(title: "🐢 慢速", value: TTSRate.slow.rawValue)
                ratePill(title: "🐇 正常", value: TTSRate.normal.rawValue)
                Spacer(minLength: 0)
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .strokeBorder(Tokens.Colors.borderSubtle, lineWidth: 1)
        )
    }

    private func ratePill(title: String, value: String) -> some View {
        Button {
            store.setRateText(value)
        } label: {
            Text(title)
                .font(AppFont.caption(caps).weight(.semibold))
                .foregroundStyle(store.rateText == value ? Tokens.Colors.onPrimary : Tokens.Colors.primary)
                .padding(.horizontal, Tokens.Spacing.s16)
                .frame(minHeight: caps.minTapTarget)
                .background(
                    Capsule(style: .continuous)
                        .fill(store.rateText == value ? Tokens.Colors.primary : Tokens.Colors.surfaceMuted)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("语速 \(title)"))
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .loading:
            LoadingBlock(text: "正在取场景…")
        case .failed(let message):
            ErrorStateView(
                title: message.title,
                message: message.body ?? "",
                retryTitle: "重试",
                onRetry: { Task { await store.reload() } }
            )
        case .ready:
            if store.isAllEmpty {
                emptyState
            } else {
                groups
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "bubble.left.and.bubble.right",
            title: store.isChild ? "现在还没有适合你的场景" : "暂时没有可用场景",
            message: store.isChild
                ? "等一下再来看看吧"
                : "点「＋ 自定义场景」写一个你自己的",
            actionTitle: store.isChild ? nil : "＋ 自定义场景",
            action: store.isChild ? nil : onCreate
        )
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
            customSection
            if store.isChild {
                scenarioSection(title: "选一个场景开始（\(store.childScenarios.count)）", items: store.childScenarios)
                if store.childScenarios.isEmpty {
                    emptyHint("暂时没有可用的儿童场景")
                }
            } else {
                scenarioSection(title: "成人场景（\(store.adultScenarios.count)）", items: store.adultScenarios)
                childToggleCard
                if store.includeChild {
                    scenarioSection(title: "小朋友的场景（\(store.childScenarios.count)）", items: store.childScenarios)
                    if store.childScenarios.isEmpty {
                        emptyHint("暂时没有可用的儿童场景")
                    }
                }
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            SectionHeader(
                title: "我的自定义场景（\(store.customScenarios.count)）",
                actionTitle: "＋ 自定义场景",
                onAction: onCreate
            )
            if store.customScenarios.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                    Text("还没有自定义场景；点「＋ 自定义场景」写一个你自己的。")
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    Text("可以自定义角色设定和开场白，练你想练的生活场景。")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(Tokens.Spacing.s16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
            } else {
                ForEach(store.customScenarios, id: \.id) { scenario in
                    ChatScenarioCard(
                        scenario: scenario,
                        isChild: store.isChild,
                        isStarting: store.startingScenarioID == scenario.id,
                        onStart: { onStart(scenario) },
                        onEdit: { onEdit(scenario) }
                    )
                }
            }
        }
    }

    private func scenarioSection(title: String, items: [ChatScenarioDTO]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            SectionHeader(title: title)
            // 对齐 web：两列紧凑场景卡，整卡可点开始。
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Tokens.Spacing.s8),
                    GridItem(.flexible(), spacing: Tokens.Spacing.s8)
                ],
                alignment: .leading,
                spacing: Tokens.Spacing.s8
            ) {
                ForEach(items, id: \.id) { scenario in
                    ChatScenarioCard(
                        scenario: scenario,
                        isChild: store.isChild,
                        isStarting: store.startingScenarioID == scenario.id,
                        onStart: { onStart(scenario) },
                        compact: true
                    )
                }
            }
        }
    }

    private var childToggleCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            HStack(spacing: Tokens.Spacing.s12) {
                Text("再看小朋友的场景")
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Spacer(minLength: 0)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { store.includeChild },
                        set: { on in
                            Task { await store.setIncludeChild(on) }
                        }
                    )
                )
                .labelsHidden()
                .accessibilityLabel(Text("再看小朋友的场景"))
            }
            Text(store.childToggleSubtitle)
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .stroke(Tokens.Colors.borderSubtle, lineWidth: 1)
        )
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption(caps))
            .foregroundStyle(Tokens.Colors.textTertiary)
    }

    private var footer: some View {
        Text("点场景卡就开始了；对话里只有语音输入，没有文字输入框。")
            .font(AppFont.micro(caps))
            .foregroundStyle(Tokens.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Tokens.Spacing.s8)
    }
}

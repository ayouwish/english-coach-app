import SwiftUI

/// 跟读根页（Tab 0）：卡片流 + 页内结果。
///
/// 结构：页头（问候 / 今日用量 / 等级 / 句子列表入口）→ 练习游标横幅 → 句子卡片
/// （示范音 / 录音 / 评测 / 结果）→ 上一句/下一句。四态齐全：loading / empty / error / 权限。
@MainActor
struct PracticeView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: PracticeStore?
    /// 纵向卡片流当前停在哪一句（`scrollPosition(id:)` 绑定）。
    @State private var pagerSentenceID: String?

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                LoadingBlock(text: "正在准备跟读…")
            }
        }
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .task {
            await bootstrap()
        }
        .onAppear {
            consumeRecordRequestIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard let store else { return }
            Task { await store.handleScenePhase(newPhase) }
        }
        .onDisappear {
            guard let store else { return }
            Task { await store.stopAll() }
        }
    }

    private func bootstrap() async {
        if store == nil {
            let created = PracticeStore(
                services: services,
                audio: audio,
                session: session,
                level: session.user?.normalizedLevel ?? "A1"
            )
            store = created
            await created.startIfNeeded()
        } else {
            await store?.startIfNeeded()
        }
        consumeRecordRequestIfNeeded()
    }

    private func consumeRecordRequestIfNeeded() {
        guard PracticeResultHandoff.consumeRecordRequest() else { return }
        Task { await store?.startRecording() }
    }

    // MARK: - 内容

    /// 页头固定；句子本身是**纵向卡片流**（与 HOS `PracticePage` 一致）：
    /// 每张卡片占满可视高度，上下滑动切换句子（`.viewAligned` 保证卡片比屏幕高时也能读完整）。
    private func content(_ store: PracticeStore) -> some View {
        VStack(spacing: 0) {
            header(store)
                .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
                .padding(.top, Tokens.Spacing.s16)
                .padding(.bottom, Tokens.Spacing.s8)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)

            if store.loadPhase == .failed, store.sentences.isEmpty, let error = store.loadError {
                ScrollView {
                    ErrorStateView(
                        title: error.title,
                        message: error.body ?? "",
                        retryTitle: error.actionTitle ?? "重试",
                        onRetry: { Task { await store.reload(force: true) } }
                    )
                    .padding(Tokens.Spacing.pageMargin(isChild: caps.isChild))
                }
            } else if store.loadPhase == .loading, store.sentences.isEmpty {
                ScrollView {
                    loadingView
                        .padding(Tokens.Spacing.pageMargin(isChild: caps.isChild))
                }
            } else if store.sentences.isEmpty {
                ScrollView {
                    EmptyStateView(
                        icon: "text.book.closed",
                        title: "这个等级还没有句子",
                        message: caps.isChild
                            ? "这个等级还没有句子，等爸爸妈妈加一点再来吧。"
                            : "换个等级看看，或检查服务器上的语料库。",
                        actionTitle: "换个等级",
                        action: { Task { await store.selectLevel(nextLevel(after: store.level)) } }
                    )
                    .padding(Tokens.Spacing.pageMargin(isChild: caps.isChild))
                }
            } else {
                if let error = store.loadError {
                    ErrorBanner(
                        message: [error.title, error.body].compactMap { $0 }.joined(separator: " "),
                        onRetry: { Task { await store.reload(force: true) } }
                    )
                    .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
                    .padding(.bottom, Tokens.Spacing.s4)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                if store.showsResumeBanner {
                    resumeBanner(store)
                        .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
                        .padding(.bottom, Tokens.Spacing.s4)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
                pager(store)
                pagerFooter(store)
            }
        }
    }

    // MARK: - 纵向卡片流

    private func pager(_ store: PracticeStore) -> some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(store.sentences) { sentence in
                        PracticeCardView(
                            store: store,
                            sentence: sentence,
                            isActive: sentence.id == store.currentSentence?.id
                        )
                        .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
                        .padding(.bottom, Tokens.Spacing.s8)
                        // 卡片至少占满一屏；内容更长时允许在卡片内部滚到尾部再切下一张。
                        .frame(minHeight: geo.size.height, alignment: .top)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                        .id(sentence.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $pagerSentenceID)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                await store.reload(force: true)
            }
            .onAppear {
                if pagerSentenceID == nil {
                    pagerSentenceID = store.currentSentence?.id
                }
            }
            .onChange(of: pagerSentenceID) { _, newValue in
                guard let newValue,
                      let index = store.sentences.firstIndex(where: { $0.id == newValue }),
                      index != store.index
                else { return }
                store.select(index: index)
                store.dismissResumeBanner()
            }
            .onChange(of: store.currentSentence?.id) { _, newValue in
                guard let newValue, pagerSentenceID != newValue else { return }
                // 程序化切句（「下一句 →」/继续上次/换等级）时平滑滚动过去。
                withAnimation(.easeInOut(duration: 0.24)) {
                    pagerSentenceID = newValue
                }
            }
        }
    }

    private func pagerFooter(_ store: PracticeStore) -> some View {
        VStack(spacing: Tokens.Spacing.s2) {
            HStack(spacing: Tokens.Spacing.s8) {
                Text("上滑 / 下滑切换句子")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                Spacer(minLength: 0)
                Text(store.progressText)
                    .font(AppFont.micro(caps).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            Text("录音最长 60 秒；一次「开始→结束」= 一段音频 = 一次评测。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
        .padding(.top, Tokens.Spacing.s2)
        .padding(.bottom, Tokens.Spacing.s8)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 页头

    private func header(_ store: PracticeStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .top, spacing: Tokens.Spacing.s12) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                    Text("你好，\(displayName)")
                        .font(AppFont.title(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    if !store.usageText.isEmpty {
                        Text(store.usageText)
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    router.push(.sentences)
                } label: {
                    Text("句子列表")
                        .font(AppFont.caption(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.primary)
                        .padding(.horizontal, Tokens.Spacing.s12)
                        .frame(minHeight: caps.minTapTarget)
                        .background(Capsule(style: .continuous).fill(Tokens.Colors.surfaceMuted))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("打开句子列表"))
            }

            if caps.canChangeLevel {
                levelTabs(store)
            } else if let level = store.currentSentence?.level, !level.isEmpty {
                HStack(spacing: Tokens.Spacing.s8) {
                    PillTag(text: level, tone: .primary)
                    Text("等级由家长设置")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
        }
    }

    private var displayName: String {
        let name = session.user?.displayName ?? ""
        return name.isEmpty ? "朋友" : name
    }

    private func levelTabs(_ store: PracticeStore) -> some View {
        HStack(spacing: Tokens.Spacing.s8) {
            ForEach(PracticeLevels.all, id: \.self) { level in
                Button {
                    Task { await store.selectLevel(level) }
                } label: {
                    Text(level)
                        .font(AppFont.caption(caps).weight(.medium))
                        .foregroundStyle(store.level == level ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
                        .padding(.horizontal, Tokens.Spacing.s12)
                        .frame(minHeight: caps.minTapTarget)
                        .background(
                            Capsule(style: .continuous)
                                .fill(store.level == level ? Tokens.Colors.primary : Tokens.Colors.surfaceSunken)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("等级 \(level)"))
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.reload(force: true) }
            } label: {
                Text("↻ 换一批")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(minHeight: caps.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("重新加载语料"))
        }
    }

    private func nextLevel(after level: String) -> String {
        let levels = PracticeLevels.all
        guard let index = levels.firstIndex(of: level), index + 1 < levels.count else {
            return levels.first ?? "A1"
        }
        return levels[index + 1]
    }

    // MARK: - 练习游标

    private func resumeBanner(_ store: PracticeStore) -> some View {
        HStack(spacing: Tokens.Spacing.s8) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Tokens.Colors.primary)
                .accessibilityHidden(true)
            Text("上次练到第 \(store.resumeIndex + 1) 句（共 \(store.total) 句）")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("继续上次") {
                store.continueFromResume()
            }
            .font(AppFont.caption(caps).weight(.semibold))
            .foregroundStyle(Tokens.Colors.primary)
            .frame(minHeight: caps.minTapTarget)
            Button("从头开始") {
                store.startFromBeginning()
            }
            .font(AppFont.micro(caps))
            .foregroundStyle(Tokens.Colors.textSecondary)
            .frame(minHeight: caps.minTapTarget)
        }
        .padding(.horizontal, Tokens.Spacing.s12)
        .padding(.vertical, Tokens.Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(Tokens.Colors.surfaceMuted)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - 加载骨架

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            SkeletonBlock(height: 180, cornerRadius: Tokens.Radius.large)
            SkeletonBlock(height: 48, cornerRadius: Tokens.Radius.medium)
            SkeletonBlock(height: 48, cornerRadius: Tokens.Radius.medium)
            LoadingBlock(text: "正在取句子…", showsSpinner: true)
        }
    }
}

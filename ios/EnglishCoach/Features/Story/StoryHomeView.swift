import SwiftUI

/// 故事集（Tab 3）。契约 §3.15.1 冻结签名：`(services: AppServices, audio: AudioCoordinator)`。
///
/// 列表按「今天/昨天/更早」分组（两列卡片），支持全家/只看我的筛选、
/// 下拉刷新、四态（loading/empty/error/内容）与儿童文案。
struct StoryHomeView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    @State private var store: StoryHomeStore?
    /// 内嵌的创作区状态（对齐 web：故事首页同时是创作页）。
    @State private var createStore: StoryRecordStore?

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store = self.store {
                StoryHomeContent(
                    store: store,
                    services: services,
                    creationStore: createStore,
                    onOpen: open,
                    onRead: { materialId in router.push(.flowStory(materialId: materialId)) },
                    onCreated: handleCreated
                )
                    .onChange(of: store.savedTick) { _, _ in
                        Task { await store.reload() }
                    }
            } else {
                LoadingBlock(text: "正在打开故事书…", subText: nil, showsSpinner: true)
            }
        }
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .navigationTitle(session.isChild ? "我的故事书" : "我的故事")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if store == nil {
                store = StoryHomeStore(services: services, session: session)
            }
            if createStore == nil {
                let created = StoryRecordStore(services: services, audio: audio, session: session)
                createStore = created
                await created.loadIfNeeded()
            }
            await store?.loadIfNeeded()
        }
    }

    private func open(_ materialId: String) {
        router.push(.storyDetail(materialId: materialId))
    }

    /// 内嵌创作区保存成功后：刷新故事集并打开详情（web 保存后直接进入阅读）。
    private func handleCreated(_ materialId: String) {
        createStore?.resetAfterSave()
        Task { await store?.reload() }
        router.push(.storyDetail(materialId: materialId))
    }
}

// MARK: - 内容

private struct StoryHomeContent: View {
    let store: StoryHomeStore
    let services: AppServices
    let creationStore: StoryRecordStore?
    let onOpen: (String) -> Void
    let onRead: (String) -> Void
    let onCreated: (String) -> Void

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s24) {
                introCard
                // 对齐 web：创作区直接内嵌在故事首页顶部（写完/生成后下面就是故事集）。
                if let creationStore {
                    StoryCreateSection(store: creationStore, services: services, onSaved: onCreated)
                }
                SectionHeader(title: "📚 我的故事集", subtitle: "\(store.total) 篇")
                filterRow
                switch store.phase {
                case .loading:
                    skeleton
                case .failed(let message):
                    ErrorStateView(
                        title: message.title,
                        message: message.body ?? "",
                        retryTitle: message.actionTitle ?? "重试"
                    ) {
                        Task { await store.load() }
                    }
                case .ready:
                    if store.filteredCount == 0 {
                        emptyState
                    } else {
                        groups
                    }
                }
                footerHint
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .contentColumn(alignment: .center)
            .padding(.bottom, Tokens.Spacing.s32)
        }
        .refreshable { await store.reload() }
        .scrollIndicators(.hidden)
    }

    // MARK: 统计卡

    private var introCard: some View {
        HStack(spacing: Tokens.Spacing.s16) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                Text(caps.isChild ? "📖 我的故事书" : "📖 我的故事")
                    .font(AppFont.title(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text(caps.isChild ? "用中文讲讲今天发生的事，我帮你变英文故事" : "中文讲、中文写都可以；存下来就是家庭共享的英文故事书")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Tokens.Spacing.s8)
            VStack(alignment: .trailing, spacing: Tokens.Spacing.s2) {
                if store.streakDays > 0 {
                    Text("连续 \(store.streakDays) 天")
                        .font(AppFont.caption(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.childAccentText)
                        .padding(.horizontal, Tokens.Spacing.s8)
                        .padding(.vertical, Tokens.Spacing.s2)
                        .background(Capsule(style: .continuous).fill(Tokens.Colors.childAccentSoft))
                }
                Text("共 \(store.total) 篇")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: 筛选

    private var filterRow: some View {
        HStack(spacing: Tokens.Spacing.s8) {
            Button {
                store.setOnlyMine(false)
            } label: {
                filterChip(title: "全家", isOn: !store.onlyMine)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("显示全家故事"))

            Button {
                store.setOnlyMine(true)
            } label: {
                filterChip(title: "只看我的", isOn: store.onlyMine)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("只看我创建的故事"))

            Spacer(minLength: 0)
            if store.isRefreshing {
                ProgressView().controlSize(.small).tint(Tokens.Colors.primary)
            }
            Text("\(store.filteredCount) 篇")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
    }

    private func filterChip(title: String, isOn: Bool) -> some View {
        Text(title)
            .font(AppFont.caption(caps).weight(.semibold))
            .foregroundStyle(isOn ? Tokens.Colors.onPrimary : Tokens.Colors.textSecondary)
            .padding(.horizontal, Tokens.Spacing.s16)
            .frame(minHeight: caps.minTapTarget)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? Tokens.Colors.primary : Tokens.Colors.surfaceCard)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Tokens.Colors.borderSubtle, lineWidth: 1)
            )
    }

    // MARK: 分组列表

    private var groups: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s20) {
            ForEach(store.groups) { group in
                VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                    SectionHeader(title: group.label, subtitle: "\(group.items.count) 篇")
                    LazyVStack(spacing: Tokens.Spacing.s8) {
                        ForEach(group.items) { item in
                            card(item)
                        }
                    }
                }
            }
        }
    }

    /// 对齐 web「我的故事集」：一列行式卡片（缩略图 + 标题/元信息 + ▶ 读这篇）。
    private func card(_ item: StoryCardItem) -> some View {
        HStack(spacing: Tokens.Spacing.s12) {
            Button {
                onOpen(item.id)
            } label: {
                HStack(spacing: Tokens.Spacing.s12) {
                    StoryRemoteImageView(
                        materialId: item.id,
                        version: item.imageVersion,
                        services: services,
                        height: 64,
                        cornerRadius: Tokens.Radius.medium,
                        placeholderIcon: item.hasImage ? "photo" : "book.closed"
                    )
                    .frame(width: 64, height: 64)
                    .clipped()

                    VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                        Text(item.title)
                            .font(AppFont.bodyEmphasis(caps))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(metaLine(item))
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(item.title)，\(metaLine(item))"))

            AppButton(title: "▶ 读这篇", kind: .ghost) {
                onRead(item.id)
            }
            .frame(width: 116)
            .accessibilityLabel(Text("连读《\(item.title)》"))
        }
        .padding(Tokens.Spacing.s12)
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

    private func metaLine(_ item: StoryCardItem) -> String {
        var parts: [String] = []
        parts.append("\(item.sentenceCount) 句")
        if !item.level.isEmpty { parts.append(item.level) }
        parts.append(StoryDates.subtitle(for: item))
        if !item.authorName.isEmpty { parts.append(item.authorName) }
        return parts.joined(separator: " · ")
    }

    // MARK: 状态

    private var skeleton: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Tokens.Spacing.s12),
                GridItem(.flexible(), spacing: Tokens.Spacing.s12)
            ],
            spacing: Tokens.Spacing.s12
        ) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                    SkeletonBlock(height: 104, cornerRadius: Tokens.Radius.medium)
                    SkeletonBlock(height: 16)
                    SkeletonBlock(width: 80, height: 12)
                }
                .padding(Tokens.Spacing.s8)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                        .fill(Tokens.Colors.surfaceCard)
                )
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "book.closed",
            title: store.onlyMine ? "你还没有讲过故事" : "还没有故事",
            message: store.onlyMine
                ? "讲讲今天发生的事，存下来就是你的第一本英文故事书。"
                : "在上面写一段中文故事，点「变英文故事」，保存后就会出现在这里。",
            actionTitle: store.onlyMine ? "看全家故事" : nil,
            action: store.onlyMine ? { store.setOnlyMine(false) } : nil
        )
    }

    private var footerHint: some View {
        Text(caps.isChild
             ? "故事保存在家庭共享的书架上，全家都能看到。"
             : "故事保存在家庭共享的书架上，全家都能看到；关掉 App 后原始录音不可再听。")
            .font(AppFont.micro(caps))
            .foregroundStyle(Tokens.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

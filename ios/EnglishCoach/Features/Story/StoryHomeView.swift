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

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store = self.store {
                StoryHomeContent(store: store, services: services, onOpen: open, onNew: newStory)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: newStory) {
                    Label(session.isChild ? "讲故事" : "新建", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: caps.minTapTarget, minHeight: caps.minTapTarget)
                }
                .accessibilityLabel(Text(session.isChild ? "讲一个故事" : "新建故事"))
            }
        }
        .task {
            if store == nil {
                store = StoryHomeStore(services: services, session: session)
            }
            await store?.loadIfNeeded()
        }
    }

    private func open(_ materialId: String) {
        router.push(.storyDetail(materialId: materialId))
    }

    private func newStory() {
        router.push(.storyRecord)
    }
}

// MARK: - 内容

private struct StoryHomeContent: View {
    let store: StoryHomeStore
    let services: AppServices
    let onOpen: (String) -> Void
    let onNew: () -> Void

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s24) {
                introCard
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
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Tokens.Spacing.s12),
                            GridItem(.flexible(), spacing: Tokens.Spacing.s12)
                        ],
                        alignment: .leading,
                        spacing: Tokens.Spacing.s12
                    ) {
                        ForEach(group.items) { item in
                            card(item)
                        }
                    }
                }
            }
        }
    }

    private func card(_ item: StoryCardItem) -> some View {
        Button {
            onOpen(item.id)
        } label: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                StoryRemoteImageView(
                    materialId: item.id,
                    version: item.imageVersion,
                    services: services,
                    height: 104,
                    cornerRadius: Tokens.Radius.medium,
                    placeholderIcon: item.hasImage ? "photo" : "book.closed"
                )
                Text(item.title)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Tokens.Spacing.s4) {
                    if !item.level.isEmpty {
                        PillTag(text: item.level, tone: .primary)
                    }
                    Text("\(item.sentenceCount) 句")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                HStack(spacing: Tokens.Spacing.s4) {
                    Text(item.authorName.isEmpty ? StoryDates.subtitle(for: item) : item.authorName)
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(StoryDates.subtitle(for: item))
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                }
            }
            .padding(Tokens.Spacing.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                    .fill(Tokens.Colors.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                    .strokeBorder(Tokens.Colors.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Tokens.Shadow.cardPrimary, radius: Tokens.Elevation.cardRadius, x: 0, y: Tokens.Elevation.cardY)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(Text("\(item.title)，\(item.sentenceCount) 句，\(StoryDates.subtitle(for: item))"))
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
        let action: () -> Void = store.onlyMine ? { store.setOnlyMine(false) } : onNew
        return EmptyStateView(
            icon: "book.closed",
            title: store.onlyMine ? "你还没有讲过故事" : "还没有故事",
            message: store.onlyMine
                ? "讲讲今天发生的事，存下来就是你的第一本英文故事书。"
                : "讲讲今天发生的事，存下来就是家庭共享的英文故事书。",
            actionTitle: store.onlyMine ? "看全家故事" : "讲一个故事",
            action: action
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

import SwiftUI

/// 对话历史列表（`.chatHistory`）：点一行进 `.chatDetail`（只读详情）。
struct ChatHistoryView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var store: ChatHistoryStore?

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        ZStack {
            Tokens.Colors.canvas.ignoresSafeArea()
            if let store {
                ChatHistoryContent(
                    store: store,
                    onOpen: { item in router.push(.chatDetail(sessionId: item.id)) },
                    onGoChat: { router.pop() }
                )
            } else {
                LoadingBlock(text: "正在取历史记录…")
            }
        }
        .navigationTitle("对话历史")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let resolved = store ?? ChatHistoryStore(services: services, session: session)
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

private struct ChatHistoryContent: View {
    let store: ChatHistoryStore
    let onOpen: (ChatSessionListItemDTO) -> Void
    let onGoChat: () -> Void

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                if let failure = store.failure {
                    ErrorBanner(
                        message: failure.body ?? failure.title,
                        retryTitle: "重试",
                        onRetry: { Task { await store.load() } }
                    )
                }
                switch store.loadState {
                case .loading:
                    LoadingBlock(text: "正在取历史记录…")
                case .failed(let message):
                    ErrorStateView(
                        title: message.title,
                        message: message.body ?? "",
                        retryTitle: "重试",
                        onRetry: { Task { await store.load() } }
                    )
                case .ready:
                    if store.items.isEmpty {
                        EmptyStateView(
                            icon: "clock.arrow.circlepath",
                            title: "还没有对话记录",
                            message: "去「对话」选个场景开始吧",
                            actionTitle: "去对话",
                            action: onGoChat
                        )
                    } else {
                        list
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
        }
        .refreshable { await store.load() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            Text("最近 \(store.items.count) 次对话")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
            ForEach(store.items, id: \.id) { item in
                row(item)
            }
            Text("历史记录按时间顺序保存，家长可回看每次对话的校正与评价。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tokens.Spacing.s8)
        }
    }

    private func row(_ item: ChatSessionListItemDTO) -> some View {
        Button {
            onOpen(item)
        } label: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                    Text(store.title(for: item))
                        .font(AppFont.bodyEmphasis(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(store.statusText(for: item))
                        .font(AppFont.micro(caps))
                        .foregroundStyle(store.isEnded(item) ? Tokens.Colors.textTertiary : Tokens.Colors.successText)
                }
                HStack(spacing: Tokens.Spacing.s8) {
                    Text("\(item.turnCount ?? 0) 轮")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    Text(store.timeText(for: item))
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .accessibilityHidden(true)
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
                    .stroke(Tokens.Colors.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("查看这次对话的详情"))
    }
}

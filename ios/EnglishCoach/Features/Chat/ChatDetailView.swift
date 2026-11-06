import SwiftUI

/// 对话详情（只读历史，`.chatDetail`）。
///
/// 数据源 `GET chat/sessions/:id`：**不含 `pron`**（发音评价只在结束对话当时展示），
/// 但保留完整对话、每条校正与录音；可复听单条录音与整段回放。
struct ChatDetailView: View {
    private let sessionID: String
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @State private var store: ChatSessionStore?

    init(sessionId: String, services: AppServices, audio: AudioCoordinator) {
        self.sessionID = sessionId
        self.services = services
        self.audio = audio
    }

    var body: some View {
        ZStack {
            Tokens.Colors.canvas.ignoresSafeArea()
            if let store {
                ChatDetailContent(store: store)
            } else {
                LoadingBlock(text: "正在取对话记录…")
            }
        }
        .navigationTitle(store?.title ?? "对话详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let resolved = store ?? ChatSessionStore(
                sessionID: sessionID,
                readOnly: true,
                scenario: nil,
                services: services,
                audio: audio,
                session: session
            )
            store = resolved
            await resolved.loadIfNeeded()
        }
        .onAppear {
            guard let store else { return }
            Task { await store.loadIfNeeded() }
        }
    }
}

// MARK: - 内容

private struct ChatDetailContent: View {
    let store: ChatSessionStore

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        Group {
            switch store.loadState {
            case .loading:
                LoadingBlock(text: "正在取对话记录…")
            case .failed(let message):
                ErrorStateView(
                    title: message.title,
                    message: message.body ?? "",
                    retryTitle: "重试",
                    onRetry: { Task { await store.reload() } }
                )
            case .ready:
                readyContent
            }
        }
    }

    private var readyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                header
                ChatReplayPanel(
                    state: store.replay.state,
                    durationText: store.replay.durationText,
                    errorMessage: store.replay.errorMessage,
                    isPlaying: store.replay.isPlaying,
                    isChild: store.isChild,
                    onBegin: { Task { await store.replay.begin() } },
                    onPlay: { Task { await store.replay.togglePlay() } },
                    onRegenerate: { Task { await store.replay.regenerate() } }
                )
                if let failure = store.failure {
                    ErrorBanner(
                        message: failure.body ?? failure.title,
                        retryTitle: "重试",
                        onRetry: { Task { await store.retry() } }
                    )
                }
                timeline
                note
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(spacing: Tokens.Spacing.s8) {
                PillTag(text: store.isEnded ? "已结束" : "还在进行", tone: store.isEnded ? .neutral : .primary)
                PillTag(text: store.isChild ? "儿童的对话" : "完整记录", tone: .primary)
                Text("\(store.turnCount) 轮")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            if !store.subtitle.isEmpty {
                Text(store.subtitle)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var timeline: some View {
        LazyVStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            ForEach(store.bubbles) { bubble in
                ChatBubbleView(bubble: bubble, isChild: store.isChild) {
                    Task { await store.play(bubble.id) }
                }
            }
        }
    }

    private var note: some View {
        Text(
            store.isChild
                ? "这次聊得很棒，慢慢看都可以 🌟"
                : "发音评价只在「结束对话」当时展示；历史记录保留完整对话、每条校正与录音。"
        )
        .font(AppFont.micro(caps))
        .foregroundStyle(Tokens.Colors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Tokens.Spacing.s8)
    }
}

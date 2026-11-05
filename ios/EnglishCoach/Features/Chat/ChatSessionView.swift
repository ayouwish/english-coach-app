import SwiftUI

/// 对话会话页（纯语音，**没有文本输入**）。
///
/// 一轮三步由 `ChatSessionStore` 编排：`asr` → `turn` → TTS 自动播放；
/// 每轮后台轮询 `messages` 补 `pron`（≤15s）；整段回放先轮询 `audioStatus` 到 ready。
struct ChatSessionView: View {
    private let sessionID: String
    private let scenario: ChatScenarioDTO?
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: ChatSessionStore?
    @State private var showsEndConfirm = false

    init(sessionId: String, scenario: ChatScenarioDTO?, services: AppServices, audio: AudioCoordinator) {
        self.sessionID = sessionId
        self.scenario = scenario
        self.services = services
        self.audio = audio
    }

    var body: some View {
        ZStack {
            Tokens.Colors.canvas.ignoresSafeArea()
            if let store {
                ChatSessionContent(
                    store: store,
                    audio: audio,
                    onRequestEnd: { showsEndConfirm = true },
                    onExit: { router.pop() }
                )
            } else {
                LoadingBlock(text: "正在打开对话…")
            }
        }
        .navigationTitle(store?.title ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let store, store.canEnd {
                    Button(store.isEnding ? "结束中…" : "结束") {
                        showsEndConfirm = true
                    }
                    .disabled(store.isEnding)
                    .accessibilityLabel(Text("结束这次对话"))
                }
            }
        }
        .task {
            let resolved = store ?? ChatSessionStore(
                sessionID: sessionID,
                readOnly: false,
                scenario: scenario,
                services: services,
                audio: audio,
                session: session
            )
            store = resolved
            await resolved.loadIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, let store else { return }
            Task { await store.pauseForBackground() }
        }
        .onDisappear {
            store?.dispose()
        }
        .sheet(isPresented: $showsEndConfirm) {
            ConfirmDialog(
                title: "结束这次对话？",
                message: "结束后会生成整段回放，想聊多久都可以，随时可以结束。",
                confirmTitle: "🏁 结束对话",
                cancelTitle: "再聊会儿",
                isDestructive: true,
                onConfirm: {
                    guard let store else { return }
                    Task { _ = await store.endSession() }
                }
            )
        }
    }
}

// MARK: - 内容

private struct ChatSessionContent: View {
    let store: ChatSessionStore
    let audio: AudioCoordinator
    let onRequestEnd: () -> Void
    let onExit: () -> Void

    @Environment(\.roleCapabilities) private var caps
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch store.loadState {
            case .loading:
                LoadingBlock(text: "正在打开对话…")
            case .failed(let message):
                failureView(message)
            case .ready:
                readyContent
            }
        }
    }

    private func failureView(_ message: UIMessage) -> some View {
        VStack(spacing: Tokens.Spacing.s12) {
            ErrorStateView(
                title: message.title,
                message: message.body ?? "",
                retryTitle: "重试",
                onRetry: { Task { await store.reload() } }
            )
            AppButton(title: "返回", kind: .ghost, action: onExit)
        }
        .padding(Tokens.Spacing.pageMargin(isChild: caps.isChild))
    }

    private var readyContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                        statusHeader
                        replayPanel
                        timeline
                        suggestionArea
                        hintArea
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
                    .padding(.vertical, Tokens.Spacing.s16)
                }
                .onChange(of: store.bubbles.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
            bottomBar
        }
    }

    private static let bottomID = "chat-bottom"

    // MARK: - 状态区

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(spacing: Tokens.Spacing.s8) {
                PillTag(
                    text: store.isEnded ? "已结束" : "第 \(store.turnCount + 1) 轮",
                    tone: .primary
                )
                Text(store.isEnded ? "回放与文字记录都会保留" : "不限轮数，想聊多久都可以")
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

    @ViewBuilder
    private var replayPanel: some View {
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
    }

    @ViewBuilder
    private var timeline: some View {
        if store.bubbles.isEmpty {
            Text("正在等第一句开场白…")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
        } else {
            LazyVStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                ForEach(store.bubbles) { bubble in
                    ChatBubbleView(bubble: bubble, isChild: store.isChild) {
                        Task { await store.play(bubble.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionArea: some View {
        if !store.suggestedReplies.isEmpty, !store.isBusy, !store.isRecording, !store.isQuotaExceeded {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                Text("可以这样回：")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                ForEach(store.suggestedReplies, id: \.self) { suggestion in
                    Button {
                        store.useSuggestion(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(AppFont.body(caps))
                            .foregroundStyle(Tokens.Colors.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Tokens.Spacing.s12)
                            .background(
                                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                                    .fill(Tokens.Colors.surfaceMuted)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("照着说：\(suggestion)"))
                }
            }
        }
    }

    @ViewBuilder
    private var hintArea: some View {
        if !store.hintText.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("照着这句说：")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    Spacer(minLength: 0)
                    Button("收起") {
                        store.clearHint()
                    }
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.primary)
                    .frame(minHeight: caps.minTapTarget)
                }
                Text(store.hintText)
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("提示句只给你参考，发出去的是你说的录音。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
            .padding(Tokens.Spacing.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                    .fill(Tokens.Colors.surfaceMuted)
            )
        }
    }

    // MARK: - 底部操作区

    private var bottomBar: some View {
        VStack(spacing: Tokens.Spacing.s8) {
            if let failure = store.failure {
                ErrorBanner(
                    message: failure.body ?? failure.title,
                    retryTitle: failure.actionTitle ?? "重试",
                    onRetry: { handleFailureAction(failure) }
                )
            }
            if store.isQuotaExceeded {
                Banner(
                    message: store.quotaText.isEmpty ? "今天的练习时间到啦，明天再来" : store.quotaText,
                    kind: .warning
                )
            }
            if store.isDegradedLlm {
                Banner(message: "当前回复来自内置话术（还没接入大模型），先练着，不影响记录。", kind: .warning)
            }
            if store.isDegraded {
                Banner(message: "对话服务暂时不可用，已切换到本地固定话术（数据仍然完整保存）。", kind: .warning)
            }
            if store.isDone, !store.isEnded {
                VStack(spacing: Tokens.Spacing.s8) {
                    Banner(message: "这个场景练完啦，辛苦了！换个场景继续，或者去「错音本」复习一下。", kind: .success)
                    AppButton(title: "🏁 结束对话并生成回放", kind: .primary, action: onRequestEnd)
                }
            }
            if store.isEnded {
                endedBar
            } else if audio.permission == .denied {
                PermissionCard(
                    title: "本页需要麦克风才能对话（没有输入框）",
                    message: "麦克风权限被关闭了；去系统设置里打开后回来再试。",
                    primaryTitle: "去设置",
                    primaryAction: { audio.openSettings() },
                    secondaryTitle: "重新检查",
                    secondaryAction: { Task { _ = await audio.requestPermission() } }
                )
            } else {
                micBar
            }
        }
        .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
        .padding(.top, Tokens.Spacing.s8)
        .padding(.bottom, Tokens.Spacing.s12)
        .background(Tokens.Colors.canvas)
    }

    private var micBar: some View {
        VStack(spacing: Tokens.Spacing.s8) {
            if store.isBusy || store.isPreparing {
                HStack(spacing: Tokens.Spacing.s8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(store.progressLabel + (store.showsSlowHint ? "（有点慢，再等一下）" : ""))
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
            ChatMicButton(
                isRecording: store.isRecording,
                isBusy: store.isBusy,
                isPreparing: store.isPreparing,
                elapsedMs: store.elapsedMs,
                isChild: store.isChild,
                isEnabled: store.canRecord || store.isRecording
            ) {
                Task { await store.toggleMic() }
            }
            if store.isRecording {
                AppButton(title: "✖️ 不要了", kind: .text) {
                    Task { await store.cancelRecording() }
                }
                .accessibilityLabel(Text("取消这次录音"))
            }
        }
    }

    private var endedBar: some View {
        VStack(spacing: Tokens.Spacing.s8) {
            Banner(message: "这段对话已经结束啦，回放和文字记录都会保存下来。", kind: .info)
            AppButton(title: "返回场景", kind: .primary, action: onExit)
        }
    }

    private func handleFailureAction(_ failure: UIMessage) {
        switch failure.action ?? .none {
        case .openSettings:
            audio.openSettings()
        case .relogin:
            Task { await session.handleSessionExpired() }
        case .back:
            onExit()
        case .retry, .none:
            Task { await store.retry() }
        }
    }
}

import SwiftUI

/// 连读根页（Tab 1）：setup → running →（全部 settled）自动进入汇总页。
///
/// 页面不可见 / 切后台时 `pause()` 停轮询与录音；回到前台 `resumePolling()`。
@MainActor
struct FlowView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: FlowStore?
    @State private var showsExitConfirm = false

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store {
                switch store.phase {
                case .setup:
                    FlowSetupView(store: store)
                case .running:
                    if store.items.isEmpty {
                        EmptyStateView(
                            icon: "link",
                            title: "还没有选句子",
                            message: caps.isChild ? "还没有选句子哦。" : "还没有选连读的句子。",
                            actionTitle: "去选句子",
                            action: { store.backToSetup() }
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        FlowRunningView(store: store, onExit: { requestExit(store) })
                    }
                case .summary:
                    finishedView(store)
                }
            } else {
                LoadingBlock(text: "正在准备连读…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .task {
            await bootstrap()
        }
        .onAppear {
            store?.isVisible = true
            store?.resumePolling()
        }
        .onDisappear {
            store?.isVisible = false
            store?.pause()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard let store else { return }
            Task { await store.handleScenePhase(newPhase) }
        }
        .sheet(isPresented: $showsExitConfirm) {
            ConfirmDialog(
                title: "退出这次连读？",
                message: "已经读过的句子会保留在记录里，回去可以重新选句或接着读。",
                confirmTitle: "退出",
                cancelTitle: "继续练",
                isDestructive: true,
                icon: "arrow.uturn.backward",
                onConfirm: {
                    store?.backToSetup()
                    store?.pause()
                }
            )
        }
    }

    // MARK: - 汇总残留页

    private func bootstrap() async {
        guard store == nil else {
            store?.isVisible = true
            await store?.startIfNeeded()
            return
        }
        let created = FlowStore(services: services, audio: audio, session: session)
        created.onFinished = {
            guard FlowRunRegistry.store?.isVisible == true else { return }
            router.push(.flowSummary)
        }
        FlowRunRegistry.store = created
        store = created
        created.isVisible = true
        await created.startIfNeeded()
    }

    private func finishedView(_ store: FlowStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                    Text(caps.isChild ? "🎉 读完啦！" : "🎉 连读完成")
                        .font(AppFont.title(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                    Text(summaryLine(store))
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    Text(store.summary.encouragement.zh)
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                AppButton(title: "📊 查看本轮汇总") {
                    router.push(.flowSummary)
                }
                HStack(spacing: Tokens.Spacing.s8) {
                    AppButton(
                        title: caps.isChild ? "🔁 再读一遍～" : "🔁 再读一遍",
                        kind: .tonal
                    ) {
                        store.reread()
                    }
                    AppButton(title: "再读一段", kind: .ghost) {
                        store.backToSetup()
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
            .contentColumn(alignment: .center)
        }
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

    // MARK: - 退出确认

    private func requestExit(_ store: FlowStore) {
        let hasProgress = store.submittedCount > 0 || store.currentIndex > 0
        if hasProgress {
            showsExitConfirm = true
        } else {
            store.backToSetup()
            store.pause()
        }
    }
}

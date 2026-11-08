import SwiftUI

/// 「连读这一篇」：从故事详情进入，复用连读运行态（`FlowStore` + `FlowRunningView`），
/// 不走连读 Tab 的 setup；读完自动进汇总。对齐 web `/flow?material=<id>`。
struct StoryFlowReadView: View {
    private let materialId: String
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps
    @State private var store: FlowStore?
    @State private var bootstrapped = false

    init(materialId: String, services: AppServices, audio: AudioCoordinator) {
        self.materialId = materialId
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store {
                switch store.phase {
                case .running:
                    FlowRunningView(store: store, onExit: { router.pop() })
                case .summary:
                    doneView
                case .setup:
                    if let error = store.setupError {
                        ErrorStateView(
                            title: "这篇故事暂时不能连读",
                            message: error,
                            retryTitle: "重试",
                            onRetry: {
                                Task { await store.loadForStoryRead(materialId: materialId) }
                            }
                        )
                    } else {
                        LoadingBlock(text: "正在准备这篇故事…")
                    }
                }
            } else {
                LoadingBlock(text: "正在准备这篇故事…")
            }
        }
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .navigationTitle("连读故事")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private var doneView: some View {
        VStack(spacing: Tokens.Spacing.s16) {
            Text("🎉 这一篇读完啦")
                .font(AppFont.title(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            Text("评分会在后台陆续完成；先去汇总看看这一篇的表现。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AppButton(title: "📊 查看本轮汇总") {
                router.push(.flowSummary)
            }
            AppButton(title: "返回故事", kind: .ghost) {
                router.pop()
            }
        }
        .padding(Tokens.Spacing.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        let created = FlowStore(services: services, audio: audio, session: session)
        // 汇总页从 FlowRunRegistry 取运行态；这里也要注册，否则「查看汇总」是空态。
        FlowRunRegistry.store = created
        created.onFinished = {
            guard FlowRunRegistry.store?.isVisible == true else { return }
            router.push(.flowSummary)
        }
        created.isVisible = true
        store = created
        await created.loadForStoryRead(materialId: materialId)
    }
}

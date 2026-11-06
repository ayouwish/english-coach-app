import SwiftUI

/// 单句跟读页（路由 `.practice(SentenceDTO)`）：由句子列表点入，只练这一句。
///
/// 与 Tab 根页共用 `PracticeStore` / `PracticeCardView`；区别是单句模式不显示等级切换、
/// 不写练习游标，结果区最后一个按钮是「完成」。
@MainActor
struct SentencePracticeView: View {
    let sentence: SentenceDTO
    let level: String

    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: PracticeStore?

    init(sentence: SentenceDTO, level: String, services: AppServices, audio: AudioCoordinator) {
        self.sentence = sentence
        self.level = level
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                        HStack(spacing: Tokens.Spacing.s8) {
                            if let sentenceLevel = store.currentSentence?.level, !sentenceLevel.isEmpty {
                                PillTag(text: sentenceLevel, tone: .primary)
                            }
                            Spacer(minLength: 0)
                            Text(store.total > 0 ? "单句跟读" : "")
                                .font(AppFont.caption(caps))
                                .foregroundStyle(Tokens.Colors.textSecondary)
                        }
                        PracticeCardView(store: store, onFinish: { dismiss() })
                    }
                    .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
                    .padding(.vertical, Tokens.Spacing.s16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .background(Tokens.Colors.canvas.ignoresSafeArea())
            } else {
                LoadingBlock(text: "正在准备这一句…")
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("跟读")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard let store else { return }
            Task { await store.handleScenePhase(newPhase) }
        }
        .onAppear {
            // 从详细结果页点「再读一遍」返回：自动开始录音。
            guard PracticeResultHandoff.consumeRecordRequest() else { return }
            Task { await store?.startRecording() }
        }
        .onDisappear {
            guard let store else { return }
            Task { await store.stopAll() }
        }
    }

    private func bootstrap() async {
        guard store == nil else {
            await store?.startIfNeeded()
            return
        }
        let created = PracticeStore(services: services, audio: audio, session: session, level: level)
        created.configureSingle(sentence: sentence, level: level)
        store = created
        await created.startIfNeeded()
    }
}

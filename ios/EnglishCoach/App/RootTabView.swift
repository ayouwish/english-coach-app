import SwiftUI

/// 已登录主界面（契约 §3.15）：5 Tab + voice 降级横幅 + **全量** `AppRoute` 分发。
///
/// Tab（契约 §3.15.1 的冻结入口）：
/// 0 跟读 `PracticeView` / 1 连读 `FlowView` / 2 对话 `ChatScenariosView` /
/// 3 故事 `StoryHomeView` / 4 我的 `MeView`。
///
/// 路由：单个 `NavigationStack(path: router.path)` 包住整个 Tab 容器，
/// 二级页面以 push 覆盖 Tab（HOS `Index.ets` 的 Navigation 语义），返回由系统手势/返回键处理。
/// 每个 `AppRoute` case 都必须在这里有分发（`check_ios.py` §6.7 会校验）。
struct RootTabView: View {
    private enum Tab: Hashable {
        case practice
        case flow
        case chat
        case story
        case me
    }

    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var selection: Tab = .practice

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            VStack(spacing: 0) {
                if let reason = session.degradedReason {
                    VoiceDegradedBanner(text: reason)
                }
                TabView(selection: $selection) {
                    PracticeView(services: services, audio: audio)
                        .tabItem {
                            Label("跟读", systemImage: "mic.fill")
                        }
                        .tag(Tab.practice)

                    FlowView(services: services, audio: audio)
                        .tabItem {
                            Label("连读", systemImage: "link")
                        }
                        .tag(Tab.flow)

                    ChatScenariosView(services: services, audio: audio)
                        .tabItem {
                            Label("对话", systemImage: "bubble.left.and.bubble.right.fill")
                        }
                        .tag(Tab.chat)

                    StoryHomeView(services: services, audio: audio)
                        .tabItem {
                            Label("故事", systemImage: "book.fill")
                        }
                        .tag(Tab.story)

                    MeView(services: services, audio: audio)
                        .tabItem {
                            Label("我的", systemImage: "person.crop.circle.fill")
                        }
                        .tag(Tab.me)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
        // iPad 上 horizontalSizeClass 是 regular，系统会把 TabView 的标签栏挪到**顶部**
        // （iPadOS 18 起的新样式）。本 App 的布局与交互都是 iPhone 单栏设计（契约 Q8：
        // iPad 分栏留到 M4），标签栏必须固定在底部，因此整棵主界面强制 compact 宽度：
        // 系统继续用底部标签栏，页面也保持与 iPhone 一致的排版。
        .environment(\.horizontalSizeClass, .compact)
        .tint(Tokens.Colors.primary)
    }

    // MARK: - 路由分发（22 个 case，签名见契约 §3.15.1）

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .sentences:
            SentenceListView(services: services, audio: audio)

        case .practice(let sentence):
            SentencePracticeView(
                sentence: sentence,
                level: level(for: sentence),
                services: services,
                audio: audio
            )

        case .practiceResult(let attemptId):
            PracticeResultView(attemptId: attemptId, services: services, audio: audio)

        case .flowSummary:
            FlowSummaryView(services: services, audio: audio)

        case .chatScenarios:
            ChatScenariosView(services: services, audio: audio)

        case .chatSession(let sessionId):
            ChatSessionView(sessionId: sessionId, scenario: nil, services: services, audio: audio)

        case .chatHistory:
            ChatHistoryView(services: services, audio: audio)

        case .chatDetail(let sessionId):
            ChatDetailView(sessionId: sessionId, services: services, audio: audio)

        case .chatCustom(let scenarioId):
            ChatCustomView(scenarioId: scenarioId, services: services, audio: audio)

        case .storyRecord:
            StoryRecordView(services: services, audio: audio)

        case .storyDetail(let materialId):
            StoryDetailView(materialId: materialId, services: services, audio: audio)

        case .storyReview(let materialId, let sentences):
            StoryReviewView(
                materialId: materialId,
                sentences: sentences,
                services: services,
                audio: audio
            )

        case .flowStory(let materialId):
            StoryFlowReadView(materialId: materialId, services: services, audio: audio)

        case .blindTest:
            BlindTestView(services: services, audio: audio)

        case .diagnosis:
            DiagnosisView(services: services, audio: audio)

        case .review:
            ReviewView(services: services, audio: audio)

        case .parent:
            ParentView(services: services, audio: audio)

        case .family:
            FamilyView(services: services, audio: audio)

        case .suggestions:
            SuggestionsView(services: services, audio: audio)

        case .avatar:
            AvatarView(services: services, audio: audio)

        case .voices:
            VoicesView(services: services, audio: audio)

        case .health:
            HealthView(services: services, audio: audio)

        case .settings:
            SettingsView(services: services, audio: audio)
        }
    }

    /// `.practice(SentenceDTO)` 只带句子；`SentencePracticeView` 需要等级：
    /// 优先用句子自带 `level`，缺失时回退当前账号等级（`UserProfile.normalizedLevel`）。
    private func level(for sentence: SentenceDTO) -> String {
        if let level = sentence.level, !level.isEmpty {
            return level
        }
        return session.user?.normalizedLevel ?? "A1"
    }
}

// MARK: - voice 降级横幅

/// `voice.reachable == false` 时显示在 5 Tab 顶部的琥珀条（HOS `HomeTabs.degradedBanner`）。
/// 文案来自 `SessionStore.degradedReason`（含儿童/成人两套），这里只负责呈现。
private struct VoiceDegradedBanner: View {
    let text: String

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.footnote(caps))
                .foregroundStyle(Tokens.Colors.warningText)
                .accessibilityHidden(true)
            Text(text)
                .font(AppFont.footnote(caps))
                .foregroundStyle(Tokens.Colors.warningText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Tokens.Spacing.s16)
        .padding(.vertical, Tokens.Spacing.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colors.warningBackground)
        .accessibilityElement(children: .combine)
    }
}

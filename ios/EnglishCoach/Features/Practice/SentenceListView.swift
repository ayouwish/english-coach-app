import SwiftUI

/// 句子列表（路由 `.sentences`）：按等级浏览语料，点一句进入单句跟读。
///
/// 数据走 `CorpusRepository`（24h 快照，离线可读上一次的语料）；
/// 四态：loading / empty / error /（列表正常）。
@MainActor
struct SentenceListView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    @State private var store: SentenceListStore?

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                LoadingBlock(text: "正在准备句子列表…")
            }
        }
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .navigationTitle("句子列表")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await bootstrap()
        }
    }

    private func bootstrap() async {
        guard store == nil else {
            await store?.loadIfNeeded()
            return
        }
        let created = SentenceListStore(services: services, session: session)
        store = created
        await created.loadIfNeeded()
    }

    private func content(_ store: SentenceListStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            if caps.canChangeLevel {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tokens.Spacing.s8) {
                        ForEach(store.levels, id: \.self) { level in
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
                    }
                    .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
                }
            } else {
                HStack(spacing: Tokens.Spacing.s8) {
                    PillTag(text: store.level, tone: .primary)
                    Text("等级由家长设置")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            }

            switch store.phase {
            case .loading where store.sentences.isEmpty:
                LoadingBlock(text: "正在取句子…")
                    .frame(maxHeight: .infinity)
            case .failed where store.sentences.isEmpty:
                if let error = store.errorMessage {
                    ErrorStateView(
                        title: error.title,
                        message: error.body ?? "",
                        retryTitle: error.actionTitle ?? "重试",
                        onRetry: { Task { await store.load() } }
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    EmptyStateView(icon: "wifi.exclamationmark", title: "没有取到句子", message: "检查网络后重试。")
                        .frame(maxHeight: .infinity)
                }
            default:
                if store.sentences.isEmpty {
                    EmptyStateView(
                        icon: "text.book.closed",
                        title: "这个等级还没有句子",
                        message: caps.isChild ? "换个等级看看吧。" : "换个等级，或检查服务器上的语料库。",
                        actionTitle: "刷新",
                        action: { Task { await store.load() } }
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    list(store)
                }
            }
        }
        .padding(.vertical, Tokens.Spacing.s8)
        .refreshable {
            await store.load()
        }
    }

    private func list(_ store: SentenceListStore) -> some View {
        ScrollView {
            LazyVStack(spacing: Tokens.Spacing.s12) {
                if let error = store.errorMessage {
                    ErrorBanner(
                        message: [error.title, error.body].compactMap { $0 }.joined(separator: " "),
                        onRetry: { Task { await store.load() } }
                    )
                }
                ForEach(store.sentences) { sentence in
                    Button {
                        router.push(.practice(sentence))
                    } label: {
                        row(sentence)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityLabel(Text(sentence.text))
                    .accessibilityHint(Text("进入这句的跟读练习"))
                }
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.bottom, Tokens.Spacing.s24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ sentence: SentenceDTO) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text(sentence.text)
                .font(caps.isChild ? AppFont.sentence(caps) : AppFont.title(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if let translation = sentence.translationZh, !translation.isEmpty {
                Text(translation)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Tokens.Spacing.s8) {
                if let level = sentence.level, !level.isEmpty {
                    PillTag(text: level, tone: .primary)
                }
                if !caps.isChild {
                    ForEach(sentence.focusPhonemes.prefix(3), id: \.self) { phoneme in
                        PillTag(text: phoneme, tone: .neutral)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

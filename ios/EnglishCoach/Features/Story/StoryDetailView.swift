import SwiftUI
import UIKit

/// 故事详情（契约 §3.15.1 冻结签名：`(materialId:services:audio:)`）。
///
/// 内容：插画、中英对照逐句、逐句朗读、整段朗读（audio/status 轮询）、本次会话原声回放、
/// 复述入口与记录、改名/复制/导出/删除。
struct StoryDetailView: View {
    private let materialId: String
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    @State private var store: StoryDetailStore?
    @State private var showRename = false
    @State private var showDelete = false
    @State private var showExport = false
    @State private var renameText = ""

    init(materialId: String, services: AppServices, audio: AudioCoordinator) {
        self.materialId = materialId
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store = self.store {
                content(store)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            menu(store)
                        }
                    }
                    .sheet(isPresented: $showRename) {
                        renameSheet(store)
                    }
                    .sheet(isPresented: $showDelete) {
                        ConfirmDialog(
                            title: "删除这个故事？",
                            message: "删除后无法恢复，家人也看不到它了。",
                            confirmTitle: "删除",
                            isDestructive: true,
                            icon: "trash"
                        ) {
                            Task {
                                if await store.delete() {
                                    router.pop()
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showExport) {
                        exportSheet(store)
                    }
                    .onDisappear {
                        Task { await store.stopAllAudio() }
                    }
            } else {
                LoadingBlock(text: "正在打开故事…")
            }
        }
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .navigationTitle(store?.title ?? "故事详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let store = self.store {
                Task { await store.refreshRetellRecords() }
            }
        }
        .task {
            if store == nil {
                store = StoryDetailStore(
                    materialId: materialId,
                    services: services,
                    audio: audio,
                    session: session
                )
            }
            await store?.loadIfNeeded()
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(_ store: StoryDetailStore) -> some View {
        switch store.phase {
        case .loading:
            LoadingBlock(text: "正在打开故事…")
        case .failed(let message):
            ErrorStateView(
                title: message.title,
                message: message.body ?? "",
                retryTitle: message.actionTitle ?? "重试"
            ) {
                Task { await store.load() }
            }
        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                    heroSection(store)
                    metaSection(store)
                    messages(store)
                    sourceSection(store)
                    audioSection(store)
                    sentencesSection(store)
                    originalSection(store)
                    retellSection(store)
                    retellRecordsSection(store)
                    footerHint
                }
                .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
                .padding(.vertical, Tokens.Spacing.s16)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: 插画

    @ViewBuilder
    private func heroSection(_ store: StoryDetailStore) -> some View {
        if store.imageData != nil || store.hasImage || store.isIllustrating {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                ZStack {
                    StoryImageView(data: store.imageData, height: 220, placeholderIcon: "photo")
                    if store.isIllustrating {
                        LoadingBlock(text: store.busyText.isEmpty ? "正在画插画…" : store.busyText)
                            .background(Tokens.Colors.surfaceCard.opacity(0.92))
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous))
                    }
                }
                if store.imageCapable {
                    HStack(spacing: Tokens.Spacing.s8) {
                        AppButton(
                            title: store.hasImage ? "重新画一张" : "画一张插画",
                            icon: "wand.and.stars",
                            kind: .ghost,
                            isLoading: store.isIllustrating
                        ) {
                            Task { await store.illustrate(force: store.hasImage) }
                        }
                        if !store.imagePrompt.isEmpty {
                            AppButton(
                                title: store.showsImagePrompt ? "收起提示词" : "看提示词",
                                icon: "text.quote",
                                kind: .text
                            ) {
                                store.toggleImagePrompt()
                            }
                        }
                    }
                }
                if let data = store.imageData, let image = UIImage(data: data) {
                    AppButton(title: "保存插画到相册", icon: "square.and.arrow.down", kind: .ghost) {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        store.flashNotice("插画已保存到相册")
                    }
                }
                if store.showsImagePrompt, !store.imagePrompt.isEmpty {
                    Text(store.imagePrompt)
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("说明：整段朗读来自你的连读/跟读录音；没读过就是空的。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
        }
    }

    // MARK: 元信息

    private func metaSection(_ store: StoryDetailStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            Text(store.title)
                .font(AppFont.title(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Tokens.Spacing.s8) {
                if !store.level.isEmpty {
                    PillTag(text: store.level, tone: .primary)
                }
                PillTag(text: "\(store.sentences.count) 句", tone: .neutral)
                Spacer(minLength: 0)
                Text(metaText(store))
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private func metaText(_ store: StoryDetailStore) -> String {
        var parts: [String] = []
        if !store.authorName.isEmpty { parts.append(store.authorName) }
        if !store.dateText.isEmpty { parts.append(store.dateText) }
        return parts.joined(separator: " · ")
    }

    // MARK: 中文原文

    @ViewBuilder
    private func sourceSection(_ store: StoryDetailStore) -> some View {
        if store.hasSourceZh {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                Button {
                    store.toggleSourceZh()
                } label: {
                    HStack(spacing: Tokens.Spacing.s8) {
                        Text("🗒️ 看看你当时怎么讲的（中文）")
                            .font(AppFont.bodyEmphasis(caps))
                            .foregroundStyle(Tokens.Colors.primary)
                        Spacer(minLength: 0)
                        Image(systemName: store.showsSourceZh ? "chevron.up" : "chevron.down")
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textTertiary)
                    }
                    .frame(minHeight: caps.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.showsSourceZh ? "收起中文原文" : "展开中文原文"))
                if store.showsSourceZh {
                    Text(store.sourceZh)
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Tokens.Spacing.s12)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                    .fill(Tokens.Colors.surfaceCard)
            )
        }
    }

    // MARK: 整段朗读

    @ViewBuilder
    private func audioSection(_ store: StoryDetailStore) -> some View {
        if store.audioPhase != .unknown && store.audioPhase != .noAudio {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                SectionHeader(title: "整段朗读")
                switch store.audioPhase {
                case .ready:
                    HStack(spacing: Tokens.Spacing.s8) {
                        AppButton(
                            title: store.isAudioPlaying ? "停止" : "听整段",
                            icon: store.isAudioPlaying ? "stop.fill" : "play.fill",
                            kind: .ghost,
                            isLoading: store.isAudioLoading
                        ) {
                            Task { await store.playWholeStory() }
                        }
                        if !store.audioDurationText.isEmpty {
                            Text(store.audioDurationText)
                                .font(AppFont.caption(caps))
                                .monospacedDigit()
                                .foregroundStyle(Tokens.Colors.textSecondary)
                        }
                    }
                case .building:
                    LoadingBlock(text: "整段朗读准备中…", subText: "可以先去听单句，准备好了再回来")
                case .failed(let message):
                    InlineErrorView(
                        message: message.isEmpty ? "整段朗读暂时不可用" : message,
                        retryTitle: "重新生成"
                    ) {
                        Task { await store.retryWholeStory() }
                    }
                case .unknown, .noAudio:
                    EmptyView()
                }
            }
            .padding(Tokens.Spacing.s12)
            .cardStyle(padding: Tokens.Spacing.s12)
        }
    }

    // MARK: 逐句

    private func sentencesSection(_ store: StoryDetailStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            SectionHeader(title: "一句一句听 / 跟读", subtitle: "点 ▶ 听示范；点 🎤 跟读这一句（会打分）")
            ForEach(store.sentences) { sentence in
                HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                    Text("\(sentence.id).")
                        .font(AppFont.bodyEmphasis(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .frame(width: 28, alignment: .trailing)
                        .padding(.top, Tokens.Spacing.s8)
                    Text(sentence.en)
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Tokens.Spacing.s8)
                    Button {
                        Task { await store.speak(sentence: sentence) }
                    } label: {
                        Image(systemName: store.playingSentenceId == sentence.id ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(Tokens.Colors.primary)
                            .frame(width: caps.minTapTarget, height: caps.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isTTSLoading && store.playingSentenceId != sentence.id)
                    .accessibilityLabel(Text(store.playingSentenceId == sentence.id ? "停止第 \(sentence.id) 句" : "播放第 \(sentence.id) 句"))

                    Button {
                        openPractice(sentence: sentence, level: store.level)
                    } label: {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(Tokens.Colors.primary)
                            .frame(width: caps.minTapTarget, height: caps.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("跟读第 \(sentence.id) 句"))
                }
                .padding(.vertical, Tokens.Spacing.s2)
            }
        }
        .padding(Tokens.Spacing.s12)
        .cardStyle(padding: Tokens.Spacing.s12)
    }

    /// 故事句子 → 单句跟读页（`.practice(SentenceDTO)`）：复用跟读页的
    /// 听示范 / 跟我读 / 开始说 / 评分，句子 id 用 `story:` 前缀避免与语料 id 冲突。
    private func openPractice(sentence: StorySentenceItem, level: String) {
        let dto = SentenceDTO(
            id: "story:\(materialId):\(sentence.id)",
            text: sentence.en,
            translationZh: sentence.zh,
            level: level.isEmpty ? (session.user?.normalizedLevel ?? "A2") : level,
            focusPhonemes: [],
            tags: ["story"],
            source: "story"
        )
        router.push(.practice(dto))
    }

    // MARK: 原声

    @ViewBuilder
    private func originalSection(_ store: StoryDetailStore) -> some View {
        if store.originalRecordingData != nil {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                SectionHeader(title: "🎙️ 我当时讲的原话", subtitle: "只在本机保留 7 天")
                AppButton(
                    title: store.isOriginalPlaying ? "停止" : "听我的原声",
                    icon: store.isOriginalPlaying ? "stop.fill" : "play.fill",
                    kind: .ghost
                ) {
                    Task { await store.playOriginal() }
                }
                Text("线上暂时没有保存故事原始录音的接口，所以关掉 App 或换设备后这段就听不到了。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Tokens.Spacing.s12)
            .cardStyle(padding: Tokens.Spacing.s12)
        }
    }

    // MARK: 复述入口

    private func retellSection(_ store: StoryDetailStore) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            AppButton(title: "复述这个故事", icon: "mic.fill", kind: .primary) {
                router.push(.storyReview(materialId: materialId, sentences: store.sentences.map(\.en)))
            }
            Text("不看屏幕，用 2–3 句话把故事讲一遍 🙂")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
            Text("复述只看「讲清楚没有」，不计发音分。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
        }
        .padding(Tokens.Spacing.s12)
        .cardStyle(padding: Tokens.Spacing.s12)
    }

    // MARK: 复述记录

    @ViewBuilder
    private func retellRecordsSection(_ store: StoryDetailStore) -> some View {
        if !store.retellRecords.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                SectionHeader(title: "复述记录", subtitle: "本次会话")
                ForEach(store.retellRecords.indices, id: \.self) { index in
                    let record = store.retellRecords[index]
                    let feedback = (record.feedbackZh ?? "").isEmpty ? (record.feedbackEn ?? "") : (record.feedbackZh ?? "")
                    HStack(spacing: Tokens.Spacing.s8) {
                        Text(coverageText(record))
                            .font(AppFont.caption(caps).weight(.semibold))
                            .foregroundStyle(Tokens.Colors.primary)
                        if !feedback.isEmpty {
                            Text(feedback)
                                .font(AppFont.caption(caps))
                                .foregroundStyle(Tokens.Colors.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Tokens.Spacing.s2)
                }
            }
            .padding(Tokens.Spacing.s12)
            .cardStyle(padding: Tokens.Spacing.s12)
        }
    }

    private func coverageText(_ record: StoryRetellRecordDTO) -> String {
        if let count = record.coveredCount, count > 0 {
            return "覆盖 \(count) 个要点"
        }
        if let coverage = record.coverage, coverage.isFinite {
            return caps.showsNumericScore ? "覆盖 \(Int((coverage * 100).rounded()))%" : "已复述"
        }
        return "已复述"
    }

    // MARK: 提示

    @ViewBuilder
    private func messages(_ store: StoryDetailStore) -> some View {
        if !store.notice.isEmpty {
            Banner(message: store.notice, kind: .success)
        }
        if let error = store.uiError {
            ErrorBanner(message: error.body ?? error.title, retryTitle: error.actionTitle ?? "重试") {
                Task {
                    store.clearMessages()
                    await store.load()
                }
            }
        }
    }

    private var footerHint: some View {
        Text("插画与整段朗读由服务器生成，可能需要几十秒；期间可以先听单句或返回稍后再来。")
            .font(AppFont.micro(caps))
            .foregroundStyle(Tokens.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    // MARK: 菜单与弹层

    private func menu(_ store: StoryDetailStore) -> some View {
        Menu {
            Button {
                renameText = store.title
                showRename = true
            } label: {
                Label("改名", systemImage: "pencil")
            }
            Button {
                UIPasteboard.general.string = store.fullText
                store.flashNotice("全文已复制")
            } label: {
                Label("复制全文", systemImage: "doc.on.doc")
            }
            Button {
                showExport = true
            } label: {
                Label("导出 / 打印", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                showDelete = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .frame(width: caps.minTapTarget, height: caps.minTapTarget)
        }
        .accessibilityLabel(Text("更多操作"))
    }

    private func renameSheet(_ store: StoryDetailStore) -> some View {
        BottomSheetContainer(title: "给故事改个名字", isScrollable: false) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                TextField("故事标题", text: $renameText)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .padding(Tokens.Spacing.s12)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                            .fill(Tokens.Colors.surfaceSunken)
                    )
                    .accessibilityLabel(Text("新的标题"))
                HStack(spacing: Tokens.Spacing.s8) {
                    AppButton(title: "保存", kind: .primary, isLoading: store.isRenaming) {
                        Task {
                            if await store.rename(to: renameText) {
                                showRename = false
                            }
                        }
                    }
                    AppButton(title: "取消", kind: .text) {
                        showRename = false
                    }
                }
            }
        }
    }

    private func exportSheet(_ store: StoryDetailStore) -> some View {
        BottomSheetContainer(
            title: "导出 / 打印",
            subtitle: "手机端先复制全文，再粘贴到备忘录/邮件里打印",
            isScrollable: false
        ) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                ScrollView {
                    Text(store.fullText)
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Tokens.Spacing.s12)
                }
                .frame(maxHeight: 260)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
                AppButton(title: "复制全文", icon: "doc.on.doc", kind: .primary) {
                    UIPasteboard.general.string = store.fullText
                    store.flashNotice("全文已复制")
                }
            }
        }
    }
}

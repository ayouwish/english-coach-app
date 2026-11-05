import SwiftUI
import UIKit

/// 讲故事（契约 §3.15.1 冻结签名：`(services: AppServices, audio: AudioCoordinator)`）。
///
/// 一页完成：拍照/相册识别（OCR）或手动输入中文 → 录音转写（ASR）→ 改写成分级英文
/// → 逐句校对 → 保存（可选自动插画）→ 跳详情。
struct StoryRecordView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.roleCapabilities) private var caps

    @State private var store: StoryRecordStore?

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let store = self.store {
                StoryRecordContent(store: store, services: services, onSaved: handleSaved)
            } else {
                LoadingBlock(text: "准备中…")
            }
        }
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .navigationTitle(session.isChild ? "讲一个故事" : "讲故事")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                store = StoryRecordStore(services: services, audio: audio, session: session)
            }
            await store?.loadIfNeeded()
        }
        .onDisappear {
            Task { await store?.stopAudio() }
        }
    }

    private func handleSaved(_ materialId: String) {
        if router.top == .storyRecord {
            router.pop()
        }
        router.push(.storyDetail(materialId: materialId))
    }
}

// MARK: - 内容

private struct StoryRecordContent: View {
    @Bindable var store: StoryRecordStore
    let services: AppServices
    let onSaved: (String) -> Void

    @Environment(\.roleCapabilities) private var caps
    @Environment(\.openURL) private var openURL

    @State private var showCamera = false
    @State private var cameraDenied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s20) {
                intro
                sourceSection
                editorSection
                recordSection
                optionsSection
                actionSection
                messages
                if store.hasResult {
                    resultSection
                }
                footerHint
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
        }
        .scrollDismissesKeyboard(.interactively)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onImage: { image in
                    showCamera = false
                    Task { await store.recognizePickedImage(image) }
                },
                onCancel: {
                    showCamera = false
                    cameraDenied = true
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: store.notice) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task {
                try? await Task.sleep(for: .seconds(3))
                store.clearMessages()
            }
        }
    }

    // MARK: 顶部说明

    private var intro: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            Text(caps.isChild ? "说说今天发生的事，我帮你写成英文故事" : "拍一张书页，或用中文讲讲你的故事")
                .font(AppFont.heading(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            Text("说中文会被转成文字写进下面的框里；录音本身只留在这台设备，不会上传保存。")
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 来源（拍照/相册/手动）

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            SectionHeader(title: "从哪里开始")
            if cameraDenied {
                PermissionCard(
                    title: "需要相机权限",
                    message: "拍书页需要相机权限。也可以在「设置」里打开，或直接从相册选择、手动输入中文。",
                    primaryTitle: "去设置",
                    primaryAction: openSettings,
                    secondaryTitle: "知道了",
                    secondaryAction: { cameraDenied = false }
                )
            }
            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(title: "拍照", icon: "camera.fill", kind: .ghost) {
                    cameraDenied = false
                    showCamera = true
                }
                AppButton(title: "手动输入", icon: "keyboard", kind: .ghost) {
                    store.clearMessages()
                }
            }
            PhotoLibraryPicker { image in
                Task { await store.recognizePickedImage(image) }
            }
            if !store.ocrCapable {
                Text("当前服务器暂不支持拍照识别，请直接手动输入中文。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.warningText)
            }
        }
        .cardStyle(padding: Tokens.Spacing.s12)
    }

    // MARK: 中文输入

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            SectionHeader(title: "中文故事", subtitle: "可编辑")
            ZStack(alignment: .topLeading) {
                if store.textZh.isEmpty {
                    Text("用中文讲讲：今天发生了什么？和谁一起？你开心吗？")
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .padding(.horizontal, Tokens.Spacing.s8)
                        .padding(.vertical, Tokens.Spacing.s12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $store.textZh)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .padding(Tokens.Spacing.s4)
                    .accessibilityLabel(Text("中文故事内容"))
            }
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                    .fill(Tokens.Colors.surfaceSunken)
            )
            Text("\(store.textZh.count) / 2000 字")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .cardStyle()
    }

    // MARK: 录音

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            SectionHeader(title: "用说的也行", subtitle: caps.isChild ? "说一句就好" : "录音会转成上面的文字")
            HStack(spacing: Tokens.Spacing.s12) {
                AppButton(
                    title: store.isRecording ? "说完了" : "开始说",
                    icon: store.isRecording ? "stop.fill" : "mic.fill",
                    kind: store.isRecording ? .tonal : .ghost,
                    isLoading: store.isPreparing
                ) {
                    Task {
                        if store.isRecording {
                            await store.stopRecordingAndRecognize()
                        } else {
                            await store.startRecording()
                        }
                    }
                }
                if store.isRecording {
                    Text(EcFormat.clock(milliseconds: store.elapsedMs))
                        .font(AppFont.caption(caps))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.Colors.primary)
                    Button("取消") {
                        Task { await store.cancelRecording() }
                    }
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .frame(minHeight: caps.minTapTarget)
                }
            }
            Text("最多 60 秒；录音只保留在这台设备（详情页可回放，7 天后自动清理）。")
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    // MARK: 难度 / 句数

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                SectionHeader(title: "难度")
                HStack(spacing: Tokens.Spacing.s8) {
                    ForEach(StoryRecordStore.levels, id: \.self) { level in
                        Button {
                            store.setLevel(level)
                        } label: {
                            Text(level)
                                .font(AppFont.caption(caps).weight(.semibold))
                                .foregroundStyle(store.level == level ? Tokens.Colors.onPrimary : Tokens.Colors.primary)
                                .frame(minWidth: 44, minHeight: caps.minTapTarget)
                                .background(
                                    RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                                        .fill(store.level == level ? Tokens.Colors.primary : Tokens.Colors.surfaceMuted)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("难度 \(level)"))
                    }
                }
            }
            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                SectionHeader(
                    title: "句子数",
                    subtitle: "儿童默认 5 句 / 成人默认 8 句"
                )
                HStack(spacing: Tokens.Spacing.s8) {
                    AppButton(title: "少一点", icon: "minus", kind: .ghost, isEnabled: store.maxSentences > 3) {
                        store.setMaxSentences(store.maxSentences - 1)
                    }
                    Text("\(store.maxSentences) 句")
                        .font(AppFont.bodyEmphasis(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .frame(minWidth: 64)
                    AppButton(title: "多一点", icon: "plus", kind: .ghost, isEnabled: store.maxSentences < 12) {
                        store.setMaxSentences(store.maxSentences + 1)
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: 主行动

    private var actionSection: some View {
        VStack(spacing: Tokens.Spacing.s8) {
            if store.isBusy && store.busyKind != .save {
                LoadingBlock(text: store.busyText)
            } else {
                AppButton(
                    title: store.hasResult ? "换一版" : "变英文故事",
                    icon: "wand.and.stars",
                    kind: .primary,
                    isEnabled: store.canRewrite
                ) {
                    Task { await store.rewrite() }
                }
            }
        }
    }

    // MARK: 提示与错误

    @ViewBuilder
    private var messages: some View {
        if !store.notice.isEmpty {
            Banner(message: store.notice, kind: .success)
        }
        if !store.inlineError.isEmpty {
            InlineErrorView(message: store.inlineError)
        }
        if let error = store.uiError {
            ErrorBanner(
                message: error.body ?? error.title,
                retryTitle: error.actionTitle ?? "重试"
            ) {
                Task { await store.retryLastFailure() }
            }
        }
    }

    // MARK: 英文预览

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
            SectionHeader(title: "英文故事预览", subtitle: "可逐句修改")

            TextField("故事标题", text: $store.title)
                .font(AppFont.title(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .textFieldStyle(.plain)
                .padding(Tokens.Spacing.s8)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
                .accessibilityLabel(Text("故事标题"))

            if !store.readabilityText.isEmpty {
                Text(store.readabilityText)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !store.unknownWordsText.isEmpty {
                Text(store.unknownWordsText)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !store.warningText.isEmpty {
                Banner(message: store.warningText, kind: .warning)
            }
            if !store.weakPhonemes.isEmpty {
                HStack(spacing: Tokens.Spacing.s4) {
                    Text("练到这些音：")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                    ForEach(store.weakPhonemes, id: \.self) { phoneme in
                        PillTag(text: "/\(phoneme)/", tone: .primary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                ForEach(store.sentences) { item in
                    HStack(alignment: .top, spacing: Tokens.Spacing.s8) {
                        Text("\(item.id).")
                            .font(AppFont.bodyEmphasis(caps))
                            .foregroundStyle(Tokens.Colors.primary)
                            .frame(width: 28, alignment: .trailing)
                        TextField(
                            "英文句子",
                            text: Binding(
                                get: { item.en },
                                set: { store.updateSentence(id: item.id, text: $0) }
                            ),
                            axis: .vertical
                        )
                        .font(AppFont.body(caps))
                        .foregroundStyle(Tokens.Colors.textPrimary)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .accessibilityLabel(Text("第 \(item.id) 句英文"))
                    }
                    .padding(Tokens.Spacing.s8)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                            .fill(Tokens.Colors.surfaceSunken)
                    )
                }
            }

            if store.isChild, !store.sentences.isEmpty {
                Text("保存后可以在详情页一句一句听示范。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }

            AppButton(
                title: store.isSaving ? "保存中…" : "保存故事",
                icon: "tray.and.arrow.down.fill",
                kind: .primary,
                isLoading: store.isSaving
            ) {
                Task {
                    if let materialId = await store.save() {
                        onSaved(materialId)
                    }
                }
            }
            if store.imageCapable {
                Toggle(isOn: $store.autoIllustrate) {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                        Text("保存后自动生成插画")
                            .font(AppFont.body(caps))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                        Text("每张约 ¥0.1；失败不影响故事保存，之后可以在详情页重画。")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textTertiary)
                    }
                }
                .tint(Tokens.Colors.primary)
                .frame(minHeight: caps.minTapTarget)
            }
            if store.imageCapable {
                Text("保存后可以生成插画、听整段朗读、做复述。")
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
        }
        .cardStyle()
    }

    private var footerHint: some View {
        Text("改写会按你的难度和句数生成；不满意可以点「换一版」。")
            .font(AppFont.micro(caps))
            .foregroundStyle(Tokens.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

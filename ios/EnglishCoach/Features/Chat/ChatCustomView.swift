import SwiftUI

/// 自定义场景（`.chatCustom`）：新建 / 编辑 / 删除。
///
/// 会话页是纯语音，但**本页是表单**，可以用键盘输入（HOS 同结构）。
struct ChatCustomView: View {
    private let scenarioID: String?
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var store: ChatCustomStore?

    init(scenarioId: String?, services: AppServices, audio: AudioCoordinator) {
        self.scenarioID = scenarioId
        self.services = services
        self.audio = audio
    }

    var body: some View {
        ZStack {
            Tokens.Colors.canvas.ignoresSafeArea()
            if let store {
                ChatCustomContent(
                    store: store,
                    onSaved: { router.pop() },
                    onCancel: { router.pop() }
                )
            } else {
                LoadingBlock(text: "正在取场景…")
            }
        }
        .navigationTitle(store?.isEdit == true ? "编辑自定义场景" : "自定义场景")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let resolved = store ?? ChatCustomStore(scenarioID: scenarioID, services: services, session: session)
            store = resolved
            await resolved.load()
        }
    }
}

// MARK: - 内容

private struct ChatCustomContent: View {
    @Bindable var store: ChatCustomStore
    let onSaved: () -> Void
    let onCancel: () -> Void

    @Environment(\.roleCapabilities) private var caps
    @State private var showsDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                intro
                switch store.loadState {
                case .loading:
                    LoadingBlock(text: "正在取场景…")
                case .failed(let message):
                    ErrorStateView(
                        title: message.title,
                        message: message.body ?? "",
                        retryTitle: "重试",
                        onRetry: { Task { await store.load() } }
                    )
                case .ready:
                    form
                    if let failure = store.failure {
                        ErrorBanner(
                            message: failure.body ?? failure.title,
                            retryTitle: "重试",
                            onRetry: { Task { _ = await store.save() } }
                        )
                    }
                    actions
                }
            }
            .padding(.horizontal, Tokens.Spacing.pageMargin(isChild: caps.isChild))
            .padding(.vertical, Tokens.Spacing.s16)
        }
        .sheet(isPresented: $showsDeleteConfirm) {
            ConfirmDialog(
                title: "删除这个场景？",
                message: "删除后就找不回来了，确定吗？",
                confirmTitle: "确认删除",
                cancelTitle: "先不删",
                isDestructive: true,
                onConfirm: {
                    Task {
                        if await store.delete() {
                            onSaved()
                        }
                    }
                }
            )
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            Text(store.isEdit ? "编辑自定义场景" : "自定义场景")
                .font(AppFont.title(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            Text(
                store.isEdit
                    ? "改完点「保存修改」；角色设定留空则保持原来的设定。"
                    : "写一个你想练的场景：角色设定和开场白都用英文，说出你自己的话。"
            )
            .font(AppFont.caption(caps))
            .foregroundStyle(Tokens.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
            fieldLabel("英文标题", "1–40 个字符")
            TextField("例如 My weekend plan", text: $store.title)
                .font(AppFont.body(caps))
                .padding(Tokens.Spacing.s12)
                .background(inputBackground)
                .accessibilityLabel(Text("英文标题"))
            fieldError(store.error(for: .title))

            fieldLabel("中文标题", "1–40 个字符")
            TextField("例如 我的周末计划", text: $store.titleZh)
                .font(AppFont.body(caps))
                .padding(Tokens.Spacing.s12)
                .background(inputBackground)
                .accessibilityLabel(Text("中文标题"))
            fieldError(store.error(for: .titleZh))

            fieldLabel("场景说明", "1–200 个字符，中文")
            textEditor(text: $store.settingZh, minHeight: 72, accessibilityLabel: "场景说明")
            fieldError(store.error(for: .settingZh))

            fieldLabel("角色设定", store.isEdit ? "留空 = 不修改（20–1500 个字符）" : "20–1500 个字符，英文")
            textEditor(text: $store.rolePrompt, minHeight: 120, accessibilityLabel: "角色设定")
            fieldError(store.error(for: .rolePrompt))

            fieldLabel("开场白", "5–200 个字符，英文")
            textEditor(text: $store.openingLine, minHeight: 64, accessibilityLabel: "开场白")
            fieldError(store.error(for: .openingLine))

            fieldLabel("难度", "")
            Picker("难度", selection: $store.level) {
                ForEach(ChatCustomStore.levels, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(Text("难度"))

            if store.isChild {
                Text("小朋友的场景（儿童账号只能创建「小朋友」场景）")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            } else {
                fieldLabel("场景类型", "")
                Picker("场景类型", selection: $store.audience) {
                    Text("成人场景").tag("adult")
                    Text("小朋友的场景").tag("child")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(Text("场景类型"))
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Tokens.Spacing.s8) {
            AppButton(
                title: store.isEdit ? "保存修改" : "保存场景",
                kind: .primary,
                isLoading: store.isSaving
            ) {
                Task {
                    if await store.save() {
                        onSaved()
                    }
                }
            }
            AppButton(title: "取消", kind: .ghost, action: onCancel)
            if store.isEdit {
                AppButton(title: "删除这个场景", kind: .danger, isLoading: store.isDeleting) {
                    showsDeleteConfirm = true
                }
                .accessibilityLabel(Text("删除这个场景"))
            }
        }
    }

    private func fieldLabel(_ title: String, _ hint: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
            Text(title)
                .font(AppFont.bodyEmphasis(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
            Spacer(minLength: 0)
            if !hint.isEmpty {
                Text(hint)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func fieldError(_ message: String?) -> some View {
        if let message {
            Text(message)
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.dangerText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func textEditor(text: Binding<String>, minHeight: CGFloat, accessibilityLabel: String) -> some View {
        TextEditor(text: text)
            .font(AppFont.body(caps))
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(Tokens.Spacing.s8)
            .background(inputBackground)
            .accessibilityLabel(Text(accessibilityLabel))
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
            .fill(Tokens.Colors.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                    .stroke(Tokens.Colors.borderSubtle, lineWidth: 1)
            )
    }
}

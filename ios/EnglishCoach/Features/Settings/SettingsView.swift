import SwiftUI
import UIKit

/// 设置页（契约 §3.15.1：`SettingsView(services:audio:)`）。
///
/// 语义（`ios/docs/screens.md` §10、HOS `AccountVM.AccountSettingsVM`）：
/// - 偏好保存走 `PATCH /settings`；可空字段“恢复默认”用 `SettingsPatchDTO.clear(...)` 发 `null`；
/// - 儿童不展示/不提交每日限额与自由话题（服务端 403）；
/// - 服务器地址与 token 绑定：修改后必须重新登录；
/// - 退出登录 = revoke（尽力）→ 清 token → 清用户级缓存 → 回登录页。
struct SettingsView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(AppConfig.self) private var config
    @Environment(\.roleCapabilities) private var caps

    @State private var viewModel: SettingsViewModel?
    @State private var activeSheet: SettingsSheet?

    /// 多个弹层收敛到一个 `.sheet(item:)`（SwiftUI 对同一 view 上多个 sheet 修饰器行为不可靠）。
    private enum SettingsSheet: String, Identifiable {
        case signOut
        case clearAll
        case password
        case server

        var id: String { rawValue }
    }

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let viewModel {
                if case .failed(let message) = viewModel.loadState {
                    ErrorStateView(
                        title: message.title,
                        message: message.body ?? "",
                        retryTitle: "重试",
                        onRetry: { Task { await viewModel.load(force: true) } }
                    )
                    .padding(Tokens.Spacing.s20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
                } else {
                    form(viewModel)
                }
            } else {
                LoadingBlock(text: "正在加载设置…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = SettingsViewModel(services: services, audio: audio, session: session, config: config)
            await model.load()
            viewModel = model
            await model.checkServer()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .signOut:
                ConfirmDialog(
                    title: "退出登录？",
                    message: "退出后需要重新输入账号密码；本机的示范音、图片与录音副本会被清理。",
                    confirmTitle: "退出登录",
                    isDestructive: true,
                    icon: "rectangle.portrait.and.arrow.right",
                    onConfirm: { Task { await viewModel?.signOut() } }
                )
            case .clearAll:
                ConfirmDialog(
                    title: "清除全部本地数据？",
                    message: "会清空本机的示范音、图片、录音副本与语料快照，并退出登录；服务器上的账号数据不受影响。",
                    confirmTitle: "清除并退出",
                    isDestructive: true,
                    icon: "trash",
                    onConfirm: { Task { await viewModel?.signOut() } }
                )
            case .password:
                ChangePasswordSheet()
            case .server:
                if let viewModel {
                    ServerAddressSheet(currentAddress: viewModel.currentServerAddress) { text in
                        await viewModel.applyServerAddress(text)
                    }
                }
            }
        }
    }

    // MARK: - 表单

    private func form(_ model: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                accountCard(model)

                title("账号偏好")
                card {
                    labeledField("昵称") {
                        TextField("昵称", text: Binding(
                            get: { model.displayName },
                            set: { model.displayName = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }

                    divider

                    InfoRow(
                        icon: "speaker.wave.2",
                        title: "音色",
                        value: model.voiceLabel,
                        showsChevron: true,
                        onTap: { router.push(.voices) }
                    )

                    divider

                    VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                        rowTitle("示范语速")
                        Picker("示范语速", selection: Binding(
                            get: { model.ttsRate },
                            set: { model.ttsRate = $0 }
                        )) {
                            Text("慢速").tag("slow")
                            Text("正常").tag("normal")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, Tokens.Spacing.s8)

                    divider

                    toggleRow(
                        title: "自动生成插画",
                        detail: "保存故事后自动画；关闭后仍可在故事页手动生成",
                        isOn: Binding(
                            get: { model.autoIllustrate },
                            set: { model.autoIllustrate = $0 }
                        )
                    )

                    divider

                    VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                        rowTitle("故事句子数")
                        Picker("故事句子数", selection: Binding(
                            get: { model.storySentences },
                            set: { model.storySentences = $0 }
                        )) {
                            Text("默认（\(model.storySentencesDefault) 句）").tag(-1)
                            ForEach(3...12, id: \.self) { count in
                                Text("\(count) 句").tag(count)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, Tokens.Spacing.s8)

                    divider

                    toggleRow(
                        title: "点单词显示音标",
                        detail: "关闭后正文中的单词不再显示 IPA（儿童默认隐藏）",
                        isOn: Binding(
                            get: { model.showWordIpa },
                            set: { model.setShowWordIpa($0) }
                        )
                    )

                    divider

                    VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                        rowTitle("性别（只用于插画提示词与形象筛选）")
                        Picker("性别", selection: Binding(
                            get: { model.gender },
                            set: { model.gender = $0 }
                        )) {
                            Text("未设置").tag("")
                            Text("女孩").tag("girl")
                            Text("男孩").tag("boy")
                            Text("女性").tag("woman")
                            Text("男性").tag("man")
                            Text("其他").tag("other")
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, Tokens.Spacing.s8)

                    divider

                    VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                        rowTitle("纠正强度")
                        Picker("纠正强度", selection: Binding(
                            get: { model.correctionLevel },
                            set: { model.correctionLevel = $0 }
                        )) {
                            Text("温和（多鼓励）").tag("gentle")
                            Text("标准").tag("standard")
                            Text("不纠正").tag("none")
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, Tokens.Spacing.s8)

                    if model.isParent {
                        divider
                        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
                            rowTitle("每日时长上限")
                            Stepper(
                                "\(model.dailyLimit) 分钟",
                                value: Binding(
                                    get: { model.dailyLimit },
                                    set: { model.dailyLimit = $0 }
                                ),
                                in: 5...180,
                                step: 5
                            )
                            .font(AppFont.body(caps))
                        }
                        .padding(.vertical, Tokens.Spacing.s8)

                        divider

                        toggleRow(
                            title: "允许自由话题",
                            detail: "关闭后对话强制 child_safe 安全模式",
                            isOn: Binding(
                                get: { model.allowFreeChat },
                                set: { model.allowFreeChat = $0 }
                            )
                        )
                    } else {
                        divider
                        Text("每日时长与自由话题由家长账号设置；孩子账号不能自行修改。")
                            .font(AppFont.caption(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                            .padding(.vertical, Tokens.Spacing.s8)
                    }

                    if let error = model.saveError {
                        InlineErrorView(message: errorText(error))
                            .padding(.vertical, Tokens.Spacing.s8)
                    }
                    if let notice = model.notice {
                        Banner(message: notice, kind: .success)
                            .padding(.vertical, Tokens.Spacing.s8)
                    }

                    AppButton(
                        title: "保存偏好",
                        icon: "checkmark.circle.fill",
                        isLoading: model.isSaving
                    ) {
                        Task { await model.save() }
                    }
                    .padding(.vertical, Tokens.Spacing.s12)

                    AppButton(title: "恢复默认值", kind: .text) {
                        model.restoreDefaults()
                    }
                }

                title("用量")
                card {
                    InfoRow(icon: "clock", title: model.usageText)
                    divider
                    InfoRow(icon: "person.text.rectangle", title: "账号", value: model.email)
                }

                title("服务器")
                card {
                    InfoRow(icon: "server.rack", title: "服务器地址", detail: model.currentServerAddress, showsChevron: true) {
                        activeSheet = .server
                    }
                    divider
                    HStack(spacing: Tokens.Spacing.s12) {
                        InfoRow(icon: "waveform.path.ecg", title: "连通状态", value: model.isCheckingServer ? "检查中…" : (model.serverStatus.isEmpty ? "未检查" : model.serverStatus))
                        Button("检查") {
                            Task { await model.checkServer() }
                        }
                        .font(AppFont.footnote(caps).weight(.semibold))
                        .foregroundStyle(Tokens.Colors.primary)
                        .frame(minHeight: caps.minTapTarget)
                    }
                    divider
                    InfoRow(icon: "lock.shield", title: "凭据保存", detail: "token 只存本机 Keychain（设备专用，不随备份迁移）")
                }

                title("存储与隐私")
                card {
                    InfoRow(icon: "internaldrive", title: "清除缓存", detail: "示范音、图片、录音副本、语料快照", showsChevron: true) {
                        model.clearCache()
                    }
                    divider
                    InfoRow(icon: "trash", title: "清除全部本地数据", detail: "清缓存并退出登录（不影响服务器账号）", showsChevron: true) {
                        activeSheet = .clearAll
                    }
                    divider
                    Text("隐私说明：录音会经家庭 NAS 转发到云端语音服务做识别与评分，不是纯本地处理；照片同理。")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Tokens.Spacing.s8)
                }

                title("关于")
                card {
                    InfoRow(icon: "info.circle", title: "版本", value: AppConfig.appVersion)
                    divider
                    InfoRow(icon: "iphone", title: "构建说明", detail: "本机构建未在 App Store 分发，NAS 地址由家庭自行维护")
                    divider
                    InfoRow(icon: "questionmark.circle", title: "问题反馈", detail: "设置 → 服务状态可复制诊断信息，不含 token/邮箱", showsChevron: true) {
                        router.push(.health)
                    }
                }

                AppButton(title: "修改密码", icon: "key", kind: .ghost) {
                    activeSheet = .password
                }

                AppButton(title: "退出登录", icon: "rectangle.portrait.and.arrow.right", kind: .ghost) {
                    activeSheet = .signOut
                }
            }
            .padding(.horizontal, Tokens.Spacing.s16)
            .padding(.vertical, Tokens.Spacing.s16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Tokens.Colors.canvas.ignoresSafeArea())
        .refreshable {
            await model.load(force: true)
            await model.checkServer()
        }
    }

    // MARK: - 小组件

    private func accountCard(_ model: SettingsViewModel) -> some View {
        HStack(spacing: Tokens.Spacing.s16) {
            Text(model.avatarEmoji.isEmpty ? "👤" : model.avatarEmoji)
                .font(.system(size: 30, weight: .bold))
                .frame(width: 64, height: 64)
                .background(Circle().fill(Tokens.Colors.surfaceMuted))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
                Text(model.accountName.isEmpty ? "我的账号" : model.accountName)
                    .font(AppFont.title(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text("\(model.roleText) · \(model.levelText)")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                Text(model.email)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Tokens.Spacing.s16)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption(caps).weight(.semibold))
            .foregroundStyle(Tokens.Colors.textSecondary)
            .padding(.leading, Tokens.Spacing.s4)
            .accessibilityAddTraits(.isHeader)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, Tokens.Spacing.s12)
        .padding(.vertical, Tokens.Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }

    private var divider: some View {
        Divider().overlay(Tokens.Colors.borderSubtle)
    }

    private func rowTitle(_ text: String) -> some View {
        Text(text)
            .font(AppFont.body(caps))
            .foregroundStyle(Tokens.Colors.textPrimary)
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            Text(label)
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
            content()
                .font(AppFont.body(caps))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .padding(.horizontal, Tokens.Spacing.s12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
        }
        .padding(.vertical, Tokens.Spacing.s8)
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                Text(title)
                    .font(AppFont.body(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                Text(detail)
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Tokens.Colors.primary)
        .padding(.vertical, Tokens.Spacing.s12)
    }

    private func errorText(_ message: UIMessage) -> String {
        let body = message.body ?? ""
        if message.title.isEmpty { return body }
        return body.isEmpty ? message.title : "\(message.title)：\(body)"
    }
}

// MARK: - 修改密码（后端未上线：降级说明）

private struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps
    @State private var copied = false

    private let explanation = "暂不支持在 App 内修改家长密码：后端 /auth/password 尚未上线。请在 NAS 上由管理员修改密码；孩子的密码可以在「家长面板 → 家庭成员 → 重置密码」里由家长重置。"

    var body: some View {
        BottomSheetContainer(title: "修改密码", subtitle: "家长本人密码") {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                Banner(message: explanation, kind: .info)
                Text("修改成功后请用新密码重新登录；本机会清掉旧 token。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                AppButton(title: copied ? "已复制" : "复制说明", icon: "doc.on.doc") {
                    UIPasteboard.general.string = explanation
                    copied = true
                }

                AppButton(title: "知道了", kind: .text) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 修改服务器地址

private struct ServerAddressSheet: View {
    let currentAddress: String
    let onSave: @MainActor (String) async -> UIMessage?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppConfig.self) private var config
    @Environment(\.roleCapabilities) private var caps

    @State private var text = ""
    @State private var error: UIMessage?
    @State private var isSaving = false

    var body: some View {
        BottomSheetContainer(
            title: "服务器地址",
            subtitle: "token 与服务器绑定，修改后需要重新登录"
        ) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s16) {
                InfoRow(title: "当前地址", value: currentAddress)

                TextField("https://english.dreamsearch.top/api", text: $text)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppFont.body(caps))
                    .padding(.horizontal, Tokens.Spacing.s12)
                    .frame(minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.button, style: .continuous)
                            .fill(Tokens.Colors.surfaceSunken)
                    )

                Text("只填主机名也可以；系统会自动补 https:// 与 /api。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)

                if let error {
                    InlineErrorView(message: errorText(error))
                }

                AppButton(
                    title: "保存并重新登录",
                    icon: "arrow.right.circle.fill",
                    isLoading: isSaving,
                    isEnabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    isSaving = true
                    Task {
                        if let message = await onSave(text) {
                            error = message
                        } else {
                            dismiss()
                        }
                        isSaving = false
                    }
                }
            }
        }
        .onAppear {
            text = config.baseURLText
        }
    }

    private func errorText(_ message: UIMessage) -> String {
        let body = message.body ?? ""
        if message.title.isEmpty { return body }
        return body.isEmpty ? message.title : "\(message.title)：\(body)"
    }
}

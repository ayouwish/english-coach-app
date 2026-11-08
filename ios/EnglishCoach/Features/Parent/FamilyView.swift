import SwiftUI

/// 家庭成员（契约 §3.15.1：`FamilyView(services:audio:)`）。
/// 服务端没有删除成员接口 → 页面只提供“新建 / 编辑 / 重置密码”，并在页脚说明原因。
struct FamilyView: View {
    private let services: AppServices
    private let audio: AudioCoordinator

    @Environment(SessionStore.self) private var session
    @Environment(\.roleCapabilities) private var caps

    @State private var viewModel: FamilyViewModel?
    @State private var activeSheet: FamilySheet?

    private enum FamilySheet: Identifiable {
        case add
        case edit(FamilyMemberDTO)
        case reset(FamilyMemberDTO)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let member): return "edit-\(member.id)"
            case .reset(let member): return "reset-\(member.id)"
            }
        }
    }

    init(services: AppServices, audio: AudioCoordinator) {
        self.services = services
        self.audio = audio
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingBlock(text: "正在加载家庭成员…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Colors.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("家庭成员")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .add
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .accessibilityLabel(Text("添加成员"))
                }
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = FamilyViewModel(services: services, audio: audio, session: session)
            await model.load()
            viewModel = model
        }
        .sheet(item: $activeSheet) { sheet in
            if let viewModel {
                switch sheet {
                case .add:
                    AddMemberSheet(viewModel: viewModel)
                case .edit(let member):
                    EditMemberSheet(viewModel: viewModel, member: member)
                case .reset(let member):
                    ResetPasswordSheet(viewModel: viewModel, member: member)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: FamilyViewModel) -> some View {
        switch model.loadState {
        case .idle, .loading:
            ScrollView {
                VStack(spacing: Tokens.Spacing.s12) {
                    SkeletonBlock(height: 84)
                    SkeletonBlock(height: 84)
                }
                .padding(Tokens.Spacing.s16)
            }
            .background(Tokens.Colors.canvas.ignoresSafeArea())

        case .failed(let message):
            ErrorStateView(
                title: message.title,
                message: message.body ?? "",
                retryTitle: "重试",
                onRetry: { Task { await model.load(force: true) } }
            )
            .padding(Tokens.Spacing.s24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Colors.canvas.ignoresSafeArea())

        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                    Text("给家里人各建一个账号（不同英语水平）。登录名可以只写简称，服务端会自动补 @family.local。")
                        .font(AppFont.caption(caps))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let notice = model.notice {
                        Banner(message: notice, kind: .success)
                    }

                    if model.items.isEmpty {
                        EmptyStateView(
                            icon: "person.badge.plus",
                            title: "还没有其他成员",
                            message: "点右上角「＋」给家人建一个账号吧。",
                            actionTitle: "添加成员",
                            action: { activeSheet = .add }
                        )
                        .cardStyle()
                    } else {
                        ForEach(model.items, id: \.id) { member in
                            memberRow(model, member)
                        }
                    }

                    Text("说明：服务端暂未提供删除成员接口，所以这里只能新建 / 编辑 / 重置密码；如需停用账号请在 NAS 侧处理。")
                        .font(AppFont.micro(caps))
                        .foregroundStyle(Tokens.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Tokens.Spacing.s8)
                }
                .padding(Tokens.Spacing.s16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Tokens.Colors.canvas.ignoresSafeArea())
            .refreshable { await model.load(force: true) }
        }
    }

    private func memberRow(_ model: FamilyViewModel, _ member: FamilyMemberDTO) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s8) {
                Text(model.memberTitle(member))
                    .font(AppFont.bodyEmphasis(caps))
                    .foregroundStyle(Tokens.Colors.textPrimary)
                PillTag(text: model.memberBadge(member), tone: member.role == "child" ? .child : .primary)
                Spacer(minLength: 0)
            }
            let email = model.memberEmail(member)
            if !email.isEmpty {
                Text(email)
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            Text(model.memberSubText(member))
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)

            HStack(spacing: Tokens.Spacing.s8) {
                AppButton(title: "编辑", kind: .ghost) {
                    model.beginEdit(member)
                    activeSheet = .edit(member)
                }
                AppButton(title: "重置密码", kind: .ghost) {
                    model.newPassword = ""
                    activeSheet = .reset(member)
                }
            }
            .padding(.top, Tokens.Spacing.s4)
        }
        .padding(Tokens.Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .fill(Tokens.Colors.surfaceCard)
        )
    }
}

// MARK: - 新建成员

private struct AddMemberSheet: View {
    @Bindable var viewModel: FamilyViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        BottomSheetContainer(title: "添加成员", subtitle: "显示名、登录名、初始密码") {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                labeledField("显示名") {
                    TextField("例如：小明", text: $viewModel.createName)
                }
                labeledField("登录名") {
                    TextField("例如：xiaoming（自动补 @family.local）", text: $viewModel.createLogin)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                labeledField("初始密码") {
                    SecureField("至少 8 位", text: $viewModel.createPassword)
                }

                Text("角色")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                Picker("角色", selection: $viewModel.createRole) {
                    Text("孩子").tag("child")
                    Text("家长").tag("parent")
                }
                .pickerStyle(.segmented)

                Text("英语等级")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                Picker("英语等级", selection: $viewModel.createCefrLevel) {
                    ForEach(FamilyViewModel.cefrLevels, id: \.self) { level in
                        Text(level).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Stepper("每日时长上限：\(viewModel.createDailyLimit) 分钟", value: $viewModel.createDailyLimit, in: 5...180, step: 5)
                    .font(AppFont.body(caps))

                Toggle(isOn: $viewModel.createAllowFreeChat) {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
                        Text("允许自由对话（不按剧本）")
                            .font(AppFont.body(caps))
                            .foregroundStyle(Tokens.Colors.textPrimary)
                        Text("孩子在对话页可以自由聊天；关闭后强制 child_safe 安全模式。")
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
                .tint(Tokens.Colors.primary)

                if let error = viewModel.createError {
                    InlineErrorView(message: errorText(error))
                }

                AppButton(
                    title: "创建成员",
                    icon: "person.badge.plus",
                    isLoading: viewModel.isCreating
                ) {
                    Task {
                        if await viewModel.create() {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.resetCreateForm() }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
            Text(label)
                .font(AppFont.caption(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
            content()
                .font(AppFont.body(caps))
                .padding(.horizontal, Tokens.Spacing.s12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
        }
    }

    private func errorText(_ message: UIMessage) -> String {
        let body = message.body ?? ""
        return message.title.isEmpty ? body : "\(message.title)：\(body)"
    }
}

// MARK: - 编辑成员

private struct EditMemberSheet: View {
    @Bindable var viewModel: FamilyViewModel
    let member: FamilyMemberDTO
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        BottomSheetContainer(title: "编辑成员", subtitle: member.displayName ?? member.email) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                Text("昵称")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                TextField("昵称", text: $viewModel.editName)
                    .font(AppFont.body(caps))
                    .padding(.horizontal, Tokens.Spacing.s12)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                            .fill(Tokens.Colors.surfaceSunken)
                    )

                Text("英语等级")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)
                Picker("英语等级", selection: $viewModel.editCefrLevel) {
                    ForEach(FamilyViewModel.cefrLevels, id: \.self) { level in
                        Text(level).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Stepper("每日时长上限：\(viewModel.editDailyLimit) 分钟", value: $viewModel.editDailyLimit, in: 5...180, step: 5)
                    .font(AppFont.body(caps))

                Toggle("允许自由对话", isOn: $viewModel.editAllowFreeChat)
                    .font(AppFont.body(caps))
                    .tint(Tokens.Colors.primary)

                if let error = viewModel.editError {
                    InlineErrorView(message: errorText(error))
                }

                AppButton(title: "保存", icon: "checkmark.circle.fill", isLoading: viewModel.isSavingEdit) {
                    Task {
                        if await viewModel.saveEdit(member) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.beginEdit(member) }
    }

    private func errorText(_ message: UIMessage) -> String {
        let body = message.body ?? ""
        return message.title.isEmpty ? body : "\(message.title)：\(body)"
    }
}

// MARK: - 重置密码

private struct ResetPasswordSheet: View {
    @Bindable var viewModel: FamilyViewModel
    let member: FamilyMemberDTO
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roleCapabilities) private var caps
    @State private var confirmPassword = ""

    private var matchProblem: String? {
        if viewModel.newPassword.isEmpty { return nil }
        if viewModel.newPassword.count < 8 { return "新密码至少 8 位" }
        if viewModel.newPassword != confirmPassword { return "两次输入的密码不一致" }
        return nil
    }

    var body: some View {
        BottomSheetContainer(
            title: "重置密码",
            subtitle: (member.displayName ?? "") + (member.email.map { " · \($0)" } ?? "")
        ) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.s12) {
                Text("不需要旧密码；重置后孩子下次登录用新密码。")
                    .font(AppFont.caption(caps))
                    .foregroundStyle(Tokens.Colors.textSecondary)

                SecureField("新密码（至少 8 位）", text: $viewModel.newPassword)
                    .font(AppFont.body(caps))
                    .padding(.horizontal, Tokens.Spacing.s12)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                            .fill(Tokens.Colors.surfaceSunken)
                    )
                SecureField("再次输入新密码", text: $confirmPassword)
                    .font(AppFont.body(caps))
                    .padding(.horizontal, Tokens.Spacing.s12)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                            .fill(Tokens.Colors.surfaceSunken)
                    )

                if let problem = matchProblem {
                    InlineErrorView(message: problem)
                }
                if let error = viewModel.resetError {
                    InlineErrorView(message: errorText(error))
                }

                AppButton(
                    title: "重置密码",
                    icon: "key.fill",
                    isLoading: viewModel.isResetting,
                    isEnabled: matchProblem == nil && !viewModel.newPassword.isEmpty
                ) {
                    Task {
                        if await viewModel.resetPassword(member) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.newPassword = ""
            viewModel.clearResetError()
            confirmPassword = ""
        }
    }

    private func errorText(_ message: UIMessage) -> String {
        let body = message.body ?? ""
        return message.title.isEmpty ? body : "\(message.title)：\(body)"
    }
}

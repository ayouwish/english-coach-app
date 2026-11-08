import Foundation
import Observation

/// 家庭成员状态（`FamilyView(services:audio:)`）。
///
/// 语义对齐 HOS `AccountVM.FamilyVM`：新建（显示名/登录名/初始密码/角色/CEFR/每日时长/自由对话）、
/// 编辑（昵称/等级/时长/自由对话）、重置密码（≥8 位，不要求旧密码）。
/// 服务端**没有删除成员接口**，页面不提供删除（screens.md §9.2 标注【待确认】）。
@MainActor
@Observable
final class FamilyViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(UIMessage)
    }

    static let cefrLevels = ["A1", "A2", "B1", "B2", "C1"]

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore

    private(set) var items: [FamilyMemberDTO] = []
    private(set) var loadState: LoadState = .idle
    private(set) var didLoad = false
    private(set) var notice: String?

    // 新建表单
    var createName = ""
    var createLogin = ""
    var createPassword = ""
    var createRole = "child"
    var createCefrLevel = "A2"
    var createDailyLimit = 20
    var createAllowFreeChat = false
    private(set) var createError: UIMessage?
    private(set) var isCreating = false

    // 编辑
    var editName = ""
    var editCefrLevel = "A2"
    var editDailyLimit = 20
    var editAllowFreeChat = false
    private(set) var editError: UIMessage?
    private(set) var isSavingEdit = false

    // 重置密码
    var newPassword = ""
    private(set) var resetError: UIMessage?
    private(set) var isResetting = false

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
    }

    // MARK: - 加载

    func load(force: Bool = false) async {
        if didLoad && !force { return }
        if case .loading = loadState { return }
        loadState = .loading
        do {
            items = try await services.account.familyMembers()
            didLoad = true
            loadState = .loaded
        } catch let error as APIError {
            loadState = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
        } catch {
            loadState = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
        }
    }

    // MARK: - 新建

    func resetCreateForm() {
        createName = ""
        createLogin = ""
        createPassword = ""
        createRole = "child"
        createCefrLevel = "A2"
        createDailyLimit = 20
        createAllowFreeChat = false
        createError = nil
    }

    func create() async -> Bool {
        guard !isCreating else { return false }
        createError = nil
        notice = nil
        let name = createName.trimmingCharacters(in: .whitespacesAndNewlines)
        let login = createLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > 20 {
            createError = localError("请填写昵称（最多 20 字）")
            return false
        }
        if login.isEmpty {
            createError = localError("请填写登录名（可只写简称，例如 xiaoming）")
            return false
        }
        if createPassword.count < 8 {
            createError = localError("初始密码至少 8 位")
            return false
        }
        if createDailyLimit < 5 || createDailyLimit > 180 {
            createError = localError("每日时长需要在 5–180 分钟之间")
            return false
        }
        isCreating = true
        defer { isCreating = false }
        do {
            let body = FamilyCreateDTO(
                displayName: name,
                login: login,
                password: createPassword,
                role: createRole,
                cefrLevel: createCefrLevel,
                birthYear: nil,
                avatar: nil,
                dailyLimitMinutes: createDailyLimit,
                allowFreeChat: createAllowFreeChat
            )
            let result = try await services.account.createMember(body)
            let memberName = result.member?.displayName ?? name
            let memberEmail = result.member?.email ?? ""
            notice = memberEmail.isEmpty
                ? "已创建 \(memberName)"
                : "已创建 \(memberName)（登录名 \(memberEmail)）"
            resetCreateForm()
            didLoad = false
            await load(force: true)
            return true
        } catch let error as APIError {
            if case .server(_, _, let status) = error, status == 409 {
                createError = localError("登录名已经有人用了，换一个吧")
            } else {
                createError = ErrorMapper.message(for: error, isChild: session.isChild)
            }
            return false
        } catch {
            createError = ErrorMapper.message(for: error, isChild: session.isChild)
            return false
        }
    }

    // MARK: - 编辑

    func beginEdit(_ member: FamilyMemberDTO) {
        editName = member.displayName ?? ""
        editCefrLevel = member.cefrLevel ?? "A2"
        editDailyLimit = member.dailyLimitMinutes ?? 20
        editAllowFreeChat = member.allowFreeChat == true
        editError = nil
        notice = nil
    }

    func saveEdit(_ member: FamilyMemberDTO) async -> Bool {
        guard !isSavingEdit else { return false }
        editError = nil
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > 20 {
            editError = localError("昵称需为 1–20 个字符")
            return false
        }
        if editDailyLimit < 5 || editDailyLimit > 180 {
            editError = localError("每日时长需要在 5–180 分钟之间")
            return false
        }
        isSavingEdit = true
        defer { isSavingEdit = false }
        do {
            let body = FamilyPatchDTO(
                displayName: name,
                cefrLevel: editCefrLevel,
                dailyLimitMinutes: editDailyLimit,
                allowFreeChat: editAllowFreeChat,
                avatar: nil
            )
            _ = try await services.account.updateMember(id: member.id, body)
            notice = "已保存成员信息"
            didLoad = false
            await load(force: true)
            return true
        } catch let error as APIError {
            editError = ErrorMapper.message(for: error, isChild: session.isChild)
            return false
        } catch {
            editError = ErrorMapper.message(for: error, isChild: session.isChild)
            return false
        }
    }

    // MARK: - 重置密码

    /// 重置密码弹层每次出现时清空上一次失败提示（error 是 private(set)，由 ViewModel 负责清）。
    func clearResetError() {
        resetError = nil
    }

    func resetPassword(_ member: FamilyMemberDTO) async -> Bool {
        guard !isResetting else { return false }
        resetError = nil
        if newPassword.count < 8 {
            resetError = localError("新密码至少 8 位")
            return false
        }
        isResetting = true
        defer { isResetting = false }
        do {
            try await services.account.resetMemberPassword(id: member.id, newPassword: newPassword)
            newPassword = ""
            notice = "密码已重置（旧密码已失效），请告诉孩子用新密码登录"
            return true
        } catch let error as APIError {
            resetError = ErrorMapper.message(for: error, isChild: session.isChild)
            return false
        } catch {
            resetError = ErrorMapper.message(for: error, isChild: session.isChild)
            return false
        }
    }

    // MARK: - 展示

    func memberTitle(_ member: FamilyMemberDTO) -> String {
        let name = member.displayName ?? "成员"
        let isChild = member.role == "child"
        let avatar = (member.avatar?.isEmpty == false) ? (member.avatar ?? "") : (isChild ? "🧒" : "👤")
        return "\(avatar) \(name)"
    }

    func memberBadge(_ member: FamilyMemberDTO) -> String {
        let role = member.role == "parent" ? "家长" : "孩子"
        let level = member.cefrLevel ?? ""
        return level.isEmpty ? role : "\(role) · \(level)"
    }

    func memberSubText(_ member: FamilyMemberDTO) -> String {
        let limit = member.dailyLimitMinutes ?? 20
        let attempts = member.stats?.attempts ?? 0
        return "\(limit) 分钟/天 · 练过 \(attempts) 次"
    }

    func memberEmail(_ member: FamilyMemberDTO) -> String {
        member.email ?? ""
    }

    private func localError(_ text: String) -> UIMessage {
        UIMessage(
            title: "无法保存",
            body: text,
            actionTitle: nil,
            action: UIMessage.Action.none,
            isRetryable: false,
            diagnosticID: nil
        )
    }
}

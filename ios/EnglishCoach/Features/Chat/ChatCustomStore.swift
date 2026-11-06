import Foundation
import Observation

/// 自定义场景表单 Store（`.chatCustom`，新建 / 编辑 / 删除）。
///
/// 字段与校验照 HOS `ChatCustomPage`：英文标题 1–40、中文标题 1–40、场景说明 1–200、
/// 角色设定 20–1500（编辑时留空 = 不修改）、开场白 5–200。儿童账号只能创建儿童场景。
@MainActor
@Observable
final class ChatCustomStore {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(UIMessage)
    }

    enum Field: Hashable, Sendable {
        case title
        case titleZh
        case settingZh
        case rolePrompt
        case openingLine
    }

    /// CEFR 等级（与 HOS `ChatCustomPage` 的五档一致）。
    static let levels: [String] = ["A1", "A2", "B1", "B2", "C1"]

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored let scenarioID: String?

    private(set) var loadState: LoadState = .loading
    private(set) var isSaving = false
    private(set) var isDeleting = false
    private(set) var failure: UIMessage?
    private(set) var fieldErrors: [Field: String] = [:]
    private(set) var isChild: Bool

    var title = ""
    var titleZh = ""
    var settingZh = ""
    var rolePrompt = ""
    var openingLine = ""
    var level = "A2"
    /// child | adult（儿童账号强制 child，界面不展示选择）。
    var audience = "adult"

    var isEdit: Bool { scenarioID != nil }

    init(scenarioID: String?, services: AppServices, session: SessionStore) {
        self.scenarioID = scenarioID
        self.services = services
        self.session = session
        self.isChild = session.isChild
        self.level = session.user?.normalizedLevel ?? "A2"
        self.audience = session.isChild ? "child" : "adult"
    }

    func error(for field: Field) -> String? {
        fieldErrors[field]
    }

    // MARK: - 加载

    func load() async {
        guard let scenarioID else {
            loadState = .ready
            return
        }
        loadState = .loading
        failure = nil
        do {
            let list = try await services.chat.scenarios(includeChild: true)
            guard let scenario = (list.scenarios ?? []).first(where: { $0.id == scenarioID }) else {
                loadState = .failed(ErrorMapper.message(for: APIError.server(code: .notFound, message: nil, status: 404), isChild: isChild))
                return
            }
            title = scenario.title ?? ""
            titleZh = scenario.titleZh ?? ""
            settingZh = scenario.settingZh ?? ""
            rolePrompt = scenario.rolePrompt ?? ""
            openingLine = scenario.openingLine ?? ""
            if let value = scenario.level, !value.isEmpty {
                level = value.uppercased()
            }
            if let value = scenario.audience?.lowercased(), value == "child" || value == "adult" {
                audience = session.isChild ? "child" : value
            }
            loadState = .ready
        } catch {
            loadState = .failed(ErrorMapper.message(for: error, isChild: isChild))
        }
    }

    // MARK: - 保存 / 删除

    /// 返回 true = 已保存，可返回上一页。
    func save() async -> Bool {
        guard validate() else { return false }
        isSaving = true
        failure = nil
        do {
            if let scenarioID {
                try await services.chat.updateScenario(
                    id: scenarioID,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    titleZh: titleZh.trimmingCharacters(in: .whitespacesAndNewlines),
                    settingZh: settingZh.trimmingCharacters(in: .whitespacesAndNewlines),
                    rolePrompt: rolePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    openingLine: openingLine.trimmingCharacters(in: .whitespacesAndNewlines),
                    level: level
                )
            } else {
                _ = try await services.chat.createScenario(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    titleZh: titleZh.trimmingCharacters(in: .whitespacesAndNewlines),
                    settingZh: settingZh.trimmingCharacters(in: .whitespacesAndNewlines),
                    rolePrompt: rolePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    openingLine: openingLine.trimmingCharacters(in: .whitespacesAndNewlines),
                    level: level,
                    audience: isChild ? "child" : audience
                )
            }
            isSaving = false
            return true
        } catch {
            let message = ErrorMapper.message(for: error, isChild: isChild)
            failure = message.isSilent ? nil : message
            isSaving = false
            return false
        }
    }

    /// 返回 true = 已删除，可返回上一页。
    func delete() async -> Bool {
        guard let scenarioID else { return false }
        isDeleting = true
        failure = nil
        do {
            try await services.chat.deleteScenario(id: scenarioID)
            isDeleting = false
            return true
        } catch {
            let message = ErrorMapper.message(for: error, isChild: isChild)
            failure = message.isSilent ? nil : message
            isDeleting = false
            return false
        }
    }

    func dismissFailure() {
        failure = nil
    }

    // MARK: - 校验

    private func validate() -> Bool {
        var errors: [Field: String] = [:]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(1...40).contains(trimmedTitle.count) {
            errors[.title] = "英文标题需为 1–40 个字符"
        }
        let trimmedTitleZh = titleZh.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(1...40).contains(trimmedTitleZh.count) {
            errors[.titleZh] = "中文标题需为 1–40 个字符"
        }
        let trimmedSetting = settingZh.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(1...200).contains(trimmedSetting.count) {
            errors[.settingZh] = "场景说明需为 1–200 个字符"
        }
        let trimmedRole = rolePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEdit {
            if !trimmedRole.isEmpty, !(20...1500).contains(trimmedRole.count) {
                errors[.rolePrompt] = "角色设定需为 20–1500 个字符（留空 = 不修改）"
            }
        } else if !(20...1500).contains(trimmedRole.count) {
            errors[.rolePrompt] = "角色设定需为 20–1500 个字符"
        }
        let trimmedOpening = openingLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(5...200).contains(trimmedOpening.count) {
            errors[.openingLine] = "开场白需为 5–200 个字符"
        }
        fieldErrors = errors
        return errors.isEmpty
    }
}

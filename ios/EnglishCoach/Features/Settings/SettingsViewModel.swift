import Foundation
import Observation

/// 设置页状态（`SettingsView(services:audio:)`，契约 §3.15.1）。
///
/// 语义对齐 HOS `AccountVM.AccountSettingsVM`：
/// - 儿童 PATCH 不带 `daily_limit_minutes` / `allow_free_chat`（服务端会 403 整单失败）；
/// - PATCH 返回的 user 是瘦身版，不用它覆盖表单，只同步 `prefs` 与 `usage`；
/// - 需要“恢复默认”的字段用 `SettingsPatchDTO.clear(_:)` 发 JSON `null`（否则服务端不清空）。
@MainActor
@Observable
final class SettingsViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(UIMessage)
    }

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore
    let config: AppConfig

    // 账号信息（只读）
    private(set) var accountName = ""
    private(set) var email = ""
    private(set) var roleText = ""
    private(set) var levelText = ""
    private(set) var avatarEmoji = ""
    private(set) var isChild = false

    // 偏好表单
    var displayName = ""
    var autoIllustrate = false
    var gender = ""
    var storySentences = -1
    var dailyLimit = 20
    var allowFreeChat = false
    var correctionLevel = "gentle"
    var ttsVoice = ""
    var ttsRate = "normal"
    var showWordIpa = true
    private var showWordIpaIsExplicit = true

    // 用量
    private(set) var usageMinutes: Double = 0
    private(set) var usageLimit = 0

    // 页面状态
    private(set) var loadState: LoadState = .idle
    private(set) var isSaving = false
    private(set) var saveError: UIMessage?
    private(set) var notice: String?
    private(set) var isCheckingServer = false
    private(set) var serverStatus = ""
    private(set) var isSigningOut = false

    private var didLoad = false

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore, config: AppConfig) {
        self.services = services
        self.audio = audio
        self.session = session
        self.config = config
    }

    // MARK: - 派生展示

    var isParent: Bool {
        !isChild
    }

    var storySentencesDefault: Int {
        isChild ? 5 : 8
    }

    var usageText: String {
        let used = Self.minutesText(usageMinutes)
        if usageLimit > 0 {
            return "今日已练 \(used) / \(usageLimit) 分钟"
        }
        return "今日已练 \(used) 分钟"
    }

    private static func minutesText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    var voiceLabel: String {
        if ttsVoice.isEmpty {
            return "默认音色（provider 决定）"
        }
        return MediaService.findVoice(ttsVoice)?.labelZh ?? ttsVoice
    }

    var storySentencesLabel: String {
        storySentences < 0 ? "默认（\(isChild ? "孩子 5" : "家长 8") 句）" : "\(storySentences) 句"
    }

    var correctionLevelLabel: String {
        switch correctionLevel {
        case "standard": return "标准"
        case "none": return "不纠正"
        default: return "温和"
        }
    }

    var genderLabel: String {
        switch gender {
        case "girl": return "女孩"
        case "boy": return "男孩"
        case "woman": return "女性"
        case "man": return "男性"
        case "other": return "其他"
        default: return "未设置（按角色默认）"
        }
    }

    var currentServerAddress: String {
        config.baseURLText.isEmpty ? "未配置" : config.baseURLText
    }

    // MARK: - 加载

    func load(force: Bool = false) async {
        if didLoad && !force { return }
        if case .loading = loadState { return }
        loadState = .loading
        saveError = nil
        do {
            let dto = try await services.account.settings()
            apply(dto: dto)
            didLoad = true
            loadState = .loaded
        } catch let error as APIError {
            loadState = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
        } catch {
            loadState = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
        }
    }

    private func apply(dto: SettingsResponseDTO) {
        if let user = dto.user {
            accountName = user.displayName
            email = user.email
            isChild = user.isChildAccount
            avatarEmoji = user.avatar ?? ""
            levelText = user.normalizedLevel
            roleText = user.isChildAccount ? "小朋友" : (user.role.lowercased() == "parent" ? "家长" : "学习者")

            displayName = user.displayName
            autoIllustrate = user.autoIllustrate == true
            gender = user.gender ?? ""
            storySentences = user.storySentences ?? -1
            dailyLimit = user.dailyLimitMinutes ?? 20
            allowFreeChat = user.allowFreeChat == true
        }
        if let prefs = dto.prefs {
            correctionLevel = prefs.correctionLevel ?? "gentle"
            ttsVoice = prefs.ttsVoice ?? ""
            ttsRate = prefs.ttsRate ?? (isChild ? "slow" : "normal")
            showWordIpa = prefs.showWordIpa ?? true
            showWordIpaIsExplicit = prefs.showWordIpa != nil
        }
        if let usage = dto.usage {
            usageMinutes = usage.minutes ?? 0
            usageLimit = usage.limitMinutes ?? 0
            session.apply(usage: usage)
        }
    }

    // MARK: - 校验与保存

    /// 前端前置校验（服务端「先写 users 再校验 prefs」，必须客户端兜住）。
    func validationProblem() -> String? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > 30 {
            return "昵称需为 1–30 个字符"
        }
        if isParent && (dailyLimit < 5 || dailyLimit > 180) {
            return "每日时长上限需在 5–180 分钟之间"
        }
        if !gender.isEmpty && !Self.isKnownGender(gender) {
            return "性别取值不合法"
        }
        if storySentences != -1 && (storySentences < 3 || storySentences > 12) {
            return "故事句子数需在 3–12 之间"
        }
        if !["gentle", "standard", "none"].contains(correctionLevel) {
            return "纠正强度取值不合法"
        }
        if !["slow", "normal"].contains(ttsRate) {
            return "语速取值不合法"
        }
        if !ttsVoice.isEmpty && !MediaService.isKnownVoice(ttsVoice) {
            return "音色不在可选范围内"
        }
        return nil
    }

    func save() async -> Bool {
        guard !isSaving else { return false }
        saveError = nil
        notice = nil
        if let problem = validationProblem() {
            saveError = localMessage(problem)
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let dto = try await services.account.patchSettings(buildPatch())
            applyPatchedResponse(dto)
            await session.reloadUser()
            session.prefs.apply(
                AccountPrefsSnapshot(
                    ttsVoice: ttsVoice,
                    ttsRate: ttsRate,
                    showWordIpa: showWordIpa,
                    storySentences: storySentences < 0 ? 0 : storySentences,
                    autoIllustrate: autoIllustrate
                )
            )
            notice = "已保存"
            return true
        } catch let error as APIError {
            if Self.isPatchUnsupported(error) {
                saveError = localMessage("该设置暂不可用（当前服务器不支持保存偏好）")
            } else if case .forbidden = error {
                saveError = localMessage("每日时长与自由话题由家长设置，孩子账号不能自行修改")
            } else {
                saveError = ErrorMapper.message(for: error, isChild: isChild)
            }
            // 服务端可能「先落库再校验失败」：400 后重新拉一次同步真实状态。
            if case .server(_, _, 400) = error {
                await load(force: true)
            }
            return false
        } catch {
            saveError = ErrorMapper.message(for: error, isChild: isChild)
            return false
        }
    }

    /// 恢复默认：清空可空字段，由 PATCH 发 `null` 让服务端回到角色默认。
    func restoreDefaults() {
        autoIllustrate = false
        gender = ""
        storySentences = -1
        dailyLimit = 20
        allowFreeChat = false
        correctionLevel = "gentle"
        ttsVoice = ""
        ttsRate = isChild ? "slow" : "normal"
        showWordIpa = true
        showWordIpaIsExplicit = false
        saveError = nil
        notice = "已恢复默认值，点“保存”后生效"
    }

    func setShowWordIpa(_ value: Bool) {
        showWordIpa = value
        showWordIpaIsExplicit = true
    }

    private func buildPatch() -> SettingsPatchDTO {
        var patch = SettingsPatchDTO(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            dailyLimitMinutes: nil,
            allowFreeChat: nil,
            autoIllustrate: autoIllustrate,
            gender: nil,
            storySentences: nil,
            correctionLevel: correctionLevel,
            ttsRate: ttsRate,
            ttsVoice: nil,
            showWordIpa: nil
        )
        // 儿童绝不能带 dailyLimitMinutes / allowFreeChat（服务端 403）。
        if isParent {
            patch.dailyLimitMinutes = dailyLimit
            patch.allowFreeChat = allowFreeChat
        }
        if gender.isEmpty {
            patch.clear(.gender)
        } else {
            patch.gender = gender
        }
        if storySentences < 0 {
            patch.clear(.storySentences)
        } else {
            patch.storySentences = storySentences
        }
        if ttsVoice.isEmpty {
            patch.clear(.ttsVoice)
        } else {
            patch.ttsVoice = ttsVoice
        }
        if showWordIpaIsExplicit {
            patch.showWordIpa = showWordIpa
        } else {
            patch.clear(.showWordIpa)
        }
        return patch
    }

    private func applyPatchedResponse(_ dto: SettingsResponseDTO) {
        if let prefs = dto.prefs {
            correctionLevel = prefs.correctionLevel ?? correctionLevel
            ttsVoice = prefs.ttsVoice ?? ""
            ttsRate = prefs.ttsRate ?? ttsRate
            showWordIpa = prefs.showWordIpa ?? true
            showWordIpaIsExplicit = prefs.showWordIpa != nil
        }
        if let usage = dto.usage {
            usageMinutes = usage.minutes ?? usageMinutes
            usageLimit = usage.limitMinutes ?? usageLimit
        }
    }

    // MARK: - 服务器 / 缓存 / 退出

    func checkServer() async {
        guard !isCheckingServer else { return }
        isCheckingServer = true
        serverStatus = ""
        defer { isCheckingServer = false }
        do {
            let health = try await services.practice.health()
            if health.voice?.reachable == false {
                serverStatus = "已连接；语音服务未就绪（录音会先保存，可稍后重试评测）"
            } else if health.db?.ok == false {
                serverStatus = "已连接；数据库异常"
            } else {
                serverStatus = "已连接"
            }
        } catch let error as APIError {
            serverStatus = ErrorMapper.message(for: error, isChild: false).body
                ?? ErrorMapper.message(for: error, isChild: false).title
        } catch {
            serverStatus = "连不上服务器，请检查地址与网络"
        }
    }

    /// 修改服务器地址：token 与服务器绑定，保存后必须重新登录。
    func applyServerAddress(_ text: String) async -> UIMessage? {
        guard let normalized = AppConfig.normalize(text) else {
            return ErrorMapper.message(for: APIError.invalidBaseURL, isChild: false)
        }
        if let current = config.baseURL, current.absoluteString == normalized.absoluteString {
            notice = "服务器地址没有变化"
            return nil
        }
        config.updateBaseURL(normalized.absoluteString)
        await session.signOut()
        CacheJanitor.clearUserScoped()
        return nil
    }

    func clearCache() {
        CacheJanitor.clearUserScoped()
        notice = "已清除示范音、图片、录音副本与语料快照缓存（账号数据不受影响）"
        saveError = nil
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await session.signOut()
        CacheJanitor.clearUserScoped()
    }

    func clearNotice() {
        notice = nil
    }

    // MARK: - 工具

    private func localMessage(_ text: String) -> UIMessage {
        UIMessage(
            title: "无法保存",
            body: text,
            actionTitle: nil,
            action: UIMessage.Action.none,
            isRetryable: false,
            diagnosticID: nil
        )
    }

    static func isKnownGender(_ value: String) -> Bool {
        ["girl", "boy", "woman", "man", "other"].contains(value)
    }

    static func isPatchUnsupported(_ error: APIError) -> Bool {
        if case .server(_, _, let status) = error {
            return status == 405 || status == 501
        }
        return false
    }
}

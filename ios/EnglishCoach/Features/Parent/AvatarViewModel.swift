import Foundation
import Observation

/// 虚拟形象状态（`AvatarView(services:audio:)`）。
///
/// 对齐 HOS `AccountVM.AvatarVM`：预置形象（12 角色 × 5 风格）+ 风格切换 + 按性别筛选 +
/// 描述编辑 + 清空。图片是站内静态路径（无需鉴权），下载字节后写 `ImageCache` 再展示；
/// 自定义照片路径（`/api/avatar/image`）按隐私策略不展示。
@MainActor
@Observable
final class AvatarViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(UIMessage)
    }

    let services: AppServices
    let audio: AudioCoordinator
    let session: SessionStore

    private let imageCache = ImageCache()

    private(set) var loadState: LoadState = .idle
    private(set) var styles: [AvatarStyleDTO] = []
    private(set) var characters: [AvatarPresetCharacterDTO] = []
    private(set) var placeholder = false
    private(set) var myGender = ""
    private(set) var audience = "child"
    private(set) var current: AvatarStateDTO?

    var selectedStyle = "watercolor"
    var showAllGender = false
    var descDraft = ""

    private(set) var isSavingPreset = false
    private(set) var isSavingDesc = false
    private(set) var isClearing = false
    private(set) var notice: String?
    private(set) var error: UIMessage?
    private(set) var didLoad = false

    init(services: AppServices, audio: AudioCoordinator, session: SessionStore) {
        self.services = services
        self.audio = audio
        self.session = session
        self.audience = session.isChild ? "child" : "adult"
    }

    // MARK: - 加载

    func load(force: Bool = false) async {
        if didLoad && !force { return }
        if case .loading = loadState { return }
        loadState = .loading
        error = nil
        do {
            let presets = try await services.account.avatarPresets()
            styles = presets.styles ?? []
            characters = presets.characters ?? []
            placeholder = presets.placeholder == true
            if selectedStyle.isEmpty, let first = styles.first {
                selectedStyle = first.id
            }
            do {
                let state = try await services.account.avatar()
                current = state
                if let style = state.style, !style.isEmpty {
                    selectedStyle = style
                }
                descDraft = state.characterDesc ?? ""
            } catch {
                current = nil
            }
            do {
                let settings = try await services.account.settings()
                myGender = settings.user?.gender ?? ""
            } catch {
                myGender = ""
            }
            didLoad = true
            loadState = .loaded
        } catch let apiError as APIError {
            loadState = .failed(ErrorMapper.message(for: apiError, isChild: session.isChild))
        } catch {
            loadState = .failed(ErrorMapper.message(for: error, isChild: session.isChild))
        }
    }

    // MARK: - 展示数据

    var currentDesc: String {
        current?.characterDesc ?? ""
    }

    var hasAvatar: Bool {
        guard let url = current?.avatarUrl else { return false }
        return !url.isEmpty
    }

    func styleLabel(_ styleId: String) -> String {
        styles.first(where: { $0.id == styleId })?.labelZh ?? styleId
    }

    /// 当前形象图（只展示公共静态路径；`/api/avatar/image` 按隐私策略隐藏）。
    var currentImageURL: URL? {
        guard let url = current?.avatarUrl, !url.isEmpty else { return nil }
        guard !url.hasPrefix("/api/") else { return nil }
        return publicURL(path: url)
    }

    func imagePath(for character: AvatarPresetCharacterDTO) -> String? {
        guard let images = character.images else { return nil }
        switch selectedStyle {
        case "watercolor": return images.watercolor
        case "cartoon": return images.cartoon
        case "pixel": return images.pixel
        case "papercut": return images.papercut
        case "clay": return images.clay
        default: return images.watercolor
        }
    }

    func imageURL(for character: AvatarPresetCharacterDTO) -> URL? {
        publicURL(path: imagePath(for: character))
    }

    /// 按 audience + 性别过滤（性别未知/关闭筛选时显示全部）。
    func visibleCharacters() -> [AvatarPresetCharacterDTO] {
        characters.filter { character in
            if let characterAudience = character.audience, characterAudience != audience {
                return false
            }
            guard !showAllGender, !myGender.isEmpty else { return true }
            guard let gender = character.gender else { return true }
            return gender == myGender || gender == "other"
        }
    }

    func isSelected(_ character: AvatarPresetCharacterDTO) -> Bool {
        guard let state = current, let presetId = state.presetId else { return false }
        return presetId == character.id && state.style == selectedStyle
    }

    func publicURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            return URL(string: path)
        }
        guard let base = session.baseURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// 图片字节：先查 `ImageCache`，未命中用 `StoryService.imageData` 下载并回填。
    func imageData(for url: URL) async -> Data? {
        let key = CacheKey.image(materialId: "avatar|\(url.absoluteString)", version: 0)
        if let cached = await imageCache.data(for: key) {
            return cached
        }
        do {
            let data = try await services.story.imageData(url: url.absoluteString)
            await imageCache.store(data, for: key)
            return data
        } catch {
            return nil
        }
    }

    // MARK: - 动作

    func selectPreset(_ character: AvatarPresetCharacterDTO) async {
        guard !isSavingPreset else { return }
        isSavingPreset = true
        error = nil
        notice = nil
        defer { isSavingPreset = false }
        do {
            let state = try await services.account.selectAvatar(presetId: character.id, style: selectedStyle)
            current = state
            notice = "已选择「\(character.labelZh ?? "这个形象")」，立即生效"
            await session.reloadUser()
        } catch let apiError as APIError {
            error = ErrorMapper.message(for: apiError, isChild: session.isChild)
        } catch {
            error = ErrorMapper.message(for: error, isChild: session.isChild)
        }
    }

    func saveDescription() async -> Bool {
        guard !isSavingDesc else { return false }
        let text = descDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            error = UIMessage(
                title: "无法保存",
                body: "形象描述不能为空",
                actionTitle: nil,
                action: UIMessage.Action.none,
                isRetryable: false,
                diagnosticID: nil
            )
            return false
        }
        isSavingDesc = true
        error = nil
        notice = nil
        defer { isSavingDesc = false }
        do {
            let state = try await services.account.updateAvatarDescription(text)
            current = state
            notice = state.message ?? "形象描述已更新"
            return true
        } catch let apiError as APIError {
            error = ErrorMapper.message(for: apiError, isChild: session.isChild)
            return false
        } catch {
            error = ErrorMapper.message(for: error, isChild: session.isChild)
            return false
        }
    }

    func clear() async -> Bool {
        guard !isClearing else { return false }
        isClearing = true
        error = nil
        notice = nil
        defer { isClearing = false }
        do {
            try await services.account.clearAvatar()
            current = nil
            descDraft = ""
            notice = "已清空虚拟形象"
            await session.reloadUser()
            return true
        } catch let apiError as APIError {
            error = ErrorMapper.message(for: apiError, isChild: session.isChild)
            return false
        } catch {
            error = ErrorMapper.message(for: error, isChild: session.isChild)
            return false
        }
    }
}

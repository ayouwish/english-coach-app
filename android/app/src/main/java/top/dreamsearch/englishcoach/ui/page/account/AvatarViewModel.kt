package top.dreamsearch.englishcoach.ui.page.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.dto.AvatarPresetCharacterDto
import top.dreamsearch.englishcoach.core.net.dto.AvatarStateDto
import top.dreamsearch.englishcoach.core.net.dto.AvatarStyleDto

/**
 * 虚拟形象 VM（对应 hos `AvatarVM`，`hos/entry/.../viewmodel/AccountVM.ets` L1214-1484）。
 *
 * 数据来源：`AccountService.avatarPresets/avatar/selectAvatar/updateAvatarDescription/clearAvatar`
 * + `GET /settings`（只读 `user.gender` 用于默认筛选，不写回）。
 *
 * 关键约束：
 * - **不提供照片上传**：照片生成形象已按隐私策略关闭（服务端 403 `policy_disabled`），页面无入口；
 * - 形象图只加载预置静态图 `/avatars/...`（无需鉴权）；其他路径一律不展示（隐私）；
 * - 选择形象 = `POST /avatar {preset_id, style}`，**立即生效、不生成图片**（不扣费）；
 * - `presets.placeholder=true` 时提示「当前展示的是占位图」。
 */
data class AvatarUiState(
    val loading: Boolean = true,
    val loadedOnce: Boolean = false,
    val error: UiError? = null,
    val notice: String = "",
    /** 描述/清空等写操作的内联错误（不遮断页面） */
    val actionError: String = "",

    val styles: List<AvatarStyleDto> = emptyList(),
    val characters: List<AvatarPresetCharacterDto> = emptyList(),
    val placeholder: Boolean = false,
    val selectedStyle: String = "watercolor",
    /** child | adult（按当前账号角色） */
    val audience: String = "child",
    val showAllGender: Boolean = false,
    val myGender: String = "",

    val current: AvatarStateDto? = null,
    val saving: Boolean = false,
    val descDraft: String = "",
    val savingDesc: Boolean = false,
    val clearing: Boolean = false,
    /** 服务端未开启预置形象库（`capability.avatarPresets == false`）→ 页面显示「形象库暂不可用」+ 重试 */
    val unavailable: Boolean = false,
    /** 能力探测失败次数（重试时对 capability 用 force=true 绕过 5 分钟缓存） */
    val forcedCheck: Boolean = false,
)

class AvatarViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(AvatarUiState())
    val state: StateFlow<AvatarUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            c.session.state.collect { session ->
                val audience = if (session.isChild) "child" else "adult"
                if (_state.value.audience != audience) {
                    _state.update { it.copy(audience = audience) }
                }
            }
        }
        load()
    }

    /** 拉取形象库；[forceCapability] = 重试时强制刷新能力开关（跳过 5 分钟缓存）。 */
    fun load(forceCapability: Boolean = false) {
        _state.update {
            it.copy(loading = true, error = null, actionError = "", forcedCheck = forceCapability)
        }
        viewModelScope.launch {
            // 能力开关统一走 CapabilityCache（ROUND2 §1.1 / §4-④）：avatar_presets=false → 不请求预置库
            val caps = runCatching { c.capability.refresh(force = forceCapability) }.getOrNull()
            if (caps != null && !caps.avatarPresets) {
                _state.update {
                    it.copy(
                        loading = false,
                        loadedOnce = true,
                        unavailable = true,
                        error = null,
                    )
                }
                return@launch
            }
            try {
                val presets = c.account.avatarPresets()
                _state.update {
                    it.copy(
                        styles = presets.styles,
                        characters = presets.characters,
                        placeholder = presets.placeholder,
                        selectedStyle = presets.styles.firstOrNull()?.id ?: it.selectedStyle,
                        unavailable = false,
                    )
                }
                // 当前形象（失败不算致命：用户可能还没设置过）
                val current = runCatching { c.account.avatar() }.getOrNull()
                current?.style?.takeIf { style -> style.isNotEmpty() }?.let { style ->
                    _state.update { it.copy(selectedStyle = style) }
                }
                _state.update {
                    it.copy(
                        current = current,
                        descDraft = current?.characterDesc.orEmpty(),
                        loading = false,
                        loadedOnce = true,
                    )
                }
                // 性别只用于默认筛选（只读，不写回 settings）
                val gender = runCatching { c.account.settings().user?.gender }.getOrNull().orEmpty()
                _state.update { it.copy(myGender = gender) }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(loading = false, loadedOnce = true, error = c.session.toUiErrorAsync(e))
                }
            }
        }
    }

    /** 失败/不可用后重试：能力开关也强制刷新一次（服务端可能刚开启形象库）。 */
    fun retry() = load(forceCapability = true)

    fun clearNotice() = _state.update { it.copy(notice = "", actionError = "") }

    fun setStyle(styleId: String) {
        if (_state.value.styles.none { it.id == styleId }) return
        _state.update { it.copy(selectedStyle = styleId, actionError = "") }
    }

    fun setShowAllGender(value: Boolean) = _state.update { it.copy(showAllGender = value) }

    fun setDescDraft(value: String) = _state.update { it.copy(descDraft = value, actionError = "") }

    /** 点角色卡：`POST /avatar {preset_id, style}`，立即生效。 */
    fun selectPreset(characterId: String) {
        val s = _state.value
        if (s.saving || characterId.isEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(saving = true, notice = "", actionError = "") }
            try {
                val state = c.account.selectAvatar(characterId, s.selectedStyle)
                _state.update {
                    it.copy(current = state, saving = false, notice = "就用这个！已立即生效 ✅")
                }
            } catch (e: Throwable) {
                val apiError = e as? ApiError
                val message = if (apiError != null && apiError.code == "policy_disabled") {
                    apiError.detail.ifEmpty { "按隐私策略，照片生成形象已关闭" }
                } else {
                    c.session.toUiErrorAsync(e).message
                }
                _state.update { it.copy(saving = false, actionError = message) }
            }
        }
    }

    fun saveDescription() {
        val s = _state.value
        if (s.savingDesc) return
        val desc = s.descDraft.trim()
        if (desc.isEmpty()) {
            _state.update { it.copy(actionError = "形象描述不能为空") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(savingDesc = true, notice = "", actionError = "") }
            try {
                val state = c.account.updateAvatarDescription(desc)
                _state.update {
                    it.copy(
                        current = state,
                        savingDesc = false,
                        notice = state.message.ifEmpty { "形象描述已更新" },
                    )
                }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(savingDesc = false, actionError = c.session.toUiErrorAsync(e).message)
                }
            }
        }
    }

    fun clearAvatar() {
        val s = _state.value
        if (s.clearing) return
        viewModelScope.launch {
            _state.update { it.copy(clearing = true, notice = "", actionError = "") }
            try {
                c.account.clearAvatar()
                _state.update {
                    it.copy(current = null, descDraft = "", clearing = false, notice = "已清空虚拟形象")
                }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(clearing = false, actionError = c.session.toUiErrorAsync(e).message)
                }
            }
        }
    }

    // ------------------------------------------------------------------ 展示用派生值

    /** 当前风格下该角色的图片 URL（预置静态图，无需鉴权）；无图返回空串 → 页面用占位。 */
    fun imageOf(character: AvatarPresetCharacterDto): String =
        AccountFormat.avatarPath(character.images, _state.value.selectedStyle)

    /** 当前形象图：只接受 `/avatars/...` 静态路径，其余（照片接口）不展示。 */
    fun currentImageUrl(): String {
        val url = _state.value.current?.avatarUrl.orEmpty()
        if (url.isEmpty() || !AccountFormat.isPublicAvatarPath(url)) return ""
        return AccountFormat.publicUrl(url)
    }

    fun hasAvatar(): Boolean = _state.value.current?.avatarUrl.orEmpty().isNotEmpty()

    fun currentDesc(): String = _state.value.current?.characterDesc.orEmpty()

    fun currentPresetId(): String = _state.value.current?.presetId.orEmpty()

    fun styleLabel(styleId: String): String =
        _state.value.styles.firstOrNull { it.id == styleId }?.labelZh?.ifEmpty { styleId } ?: styleId

    fun currentStyleLabel(): String {
        val style = _state.value.current?.style.orEmpty()
        return if (style.isEmpty()) "" else styleLabel(style)
    }

    /** 按受众 + 性别过滤后的角色（性别未知时显示全部；`showAllGender` 打开显示全部）。 */
    fun visibleCharacters(): List<AvatarPresetCharacterDto> {
        val s = _state.value
        return s.characters.filter { character ->
            if (character.audience.isNotEmpty() && character.audience != s.audience) {
                false
            } else if (!s.showAllGender && s.myGender.isNotEmpty()) {
                character.gender == s.myGender || character.gender == "other"
            } else {
                true
            }
        }
    }

    fun isCurrent(character: AvatarPresetCharacterDto): Boolean =
        currentPresetId() == character.id &&
            (_state.value.current?.style.orEmpty() == _state.value.selectedStyle)

    /** 角色卡标题：中文名（缺省回退 id）。 */
    fun characterTitle(character: AvatarPresetCharacterDto): String =
        character.labelZh.ifEmpty { character.id }
}

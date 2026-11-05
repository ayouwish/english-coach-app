package top.dreamsearch.englishcoach.ui.page.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioDto

/**
 * 自定义对话场景（列表 + 新建 + 编辑 + 删除）ViewModel。
 *
 * 对应 hos：`pages/ChatCustomPage.ets`（表单在独立页）+ `ChatScenarioVM`（列表刷新）。
 * Android 侧签名固定为 `ChatCustomScreen(onBack)`，所以把「列表 + 表单」放在同一页：
 * 列表来自 `GET /chat/scenarios?include_child=1` 里 `is_custom == true` 的项。
 *
 * 校验文案照抄服务端逐字段口径：
 * 「英文标题需为 1–40 个字符」「角色设定需为 20–1500 个字符」「开场白需为 5–200 个字符」。
 * 保存/删除成功后 [ChatRefreshBus] 通知场景 Tab 刷新。
 */
data class ChatCustomForm(
    val open: Boolean = false,
    /** 非空 = 编辑态（对应 hos `isEdit/editId`） */
    val editingId: String = "",
    val title: String = "",
    val titleZh: String = "",
    val settingZh: String = "",
    val rolePrompt: String = "",
    val openingLine: String = "",
    val level: String = "A2",
    /** adult | child（儿童账号强制 child） */
    val audience: String = "adult",
    /** 字段名 → 校验错误文案 */
    val errors: Map<String, String> = emptyMap(),
)

data class ChatCustomUiState(
    val loading: Boolean = true,
    val error: UiError? = null,
    val items: List<ChatScenarioDto> = emptyList(),
    val isChild: Boolean = false,
    val form: ChatCustomForm = ChatCustomForm(),
    val saving: Boolean = false,
    val saveError: UiError? = null,
    val notice: String = "",
    /** 待确认删除的场景 id（空 = 没有打开确认弹层） */
    val confirmingDeleteId: String = "",
)

class ChatCustomViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(ChatCustomUiState(isChild = c.session.state.value.isChild))
    val state: StateFlow<ChatCustomUiState> = _state.asStateFlow()

    init {
        load()
        // 场景 Tab 的入口意图：带场景进入 = 直接编辑；「＋ 自定义场景」= 直接开表单
        val edit = ChatCustomHandoff.consumeEdit()
        if (edit != null) {
            openEdit(edit)
        } else if (ChatCustomHandoff.consumeCreate()) {
            openCreate()
        }
    }

    /** 只取自己的自定义场景。 */
    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null, isChild = c.session.state.value.isChild) }
            try {
                val items = c.chat.scenarios(includeChild = true).filter { it.isCustom }
                _state.update { it.copy(items = items, loading = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update {
                    it.copy(loading = false, error = c.session.toUiErrorAsync(e), items = emptyList())
                }
            }
        }
    }

    // ------------------------------------------------------------------ 表单

    fun openCreate() {
        val snapshot = _state.value
        _state.update {
            it.copy(
                form = ChatCustomForm(
                    open = true,
                    level = defaultLevel(),
                    audience = if (snapshot.isChild) "child" else "adult",
                ),
                saveError = null,
                notice = "",
            )
        }
    }

    fun openEdit(item: ChatScenarioDto) {
        _state.update {
            it.copy(
                form = ChatCustomForm(
                    open = true,
                    editingId = item.id,
                    title = item.title,
                    titleZh = item.titleZh,
                    settingZh = item.settingZh,
                    // 列表接口不返回 role_prompt：留空 = 服务端保持原值
                    rolePrompt = "",
                    openingLine = item.openingLine,
                    level = item.level.ifEmpty { defaultLevel() },
                    audience = if (item.audience == "child") "child" else "adult",
                ),
                saveError = null,
                notice = "",
            )
        }
    }

    fun closeForm() {
        _state.update { it.copy(form = ChatCustomForm(), saveError = null) }
    }

    fun updateTitle(value: String) = updateForm { it.copy(title = value, errors = it.errors - KEY_TITLE) }

    fun updateTitleZh(value: String) = updateForm { it.copy(titleZh = value, errors = it.errors - KEY_TITLE_ZH) }

    fun updateSettingZh(value: String) =
        updateForm { it.copy(settingZh = value, errors = it.errors - KEY_SETTING_ZH) }

    fun updateRolePrompt(value: String) =
        updateForm { it.copy(rolePrompt = value, errors = it.errors - KEY_ROLE_PROMPT) }

    fun updateOpeningLine(value: String) =
        updateForm { it.copy(openingLine = value, errors = it.errors - KEY_OPENING_LINE) }

    fun setLevel(value: String) = updateForm { it.copy(level = value) }

    fun setAudience(value: String) = updateForm {
        if (_state.value.isChild) it else it.copy(audience = value)
    }

    /** 前端校验（与 hos / 服务端同口径）；通过后调用 create/update。 */
    fun save() {
        val snapshot = _state.value
        if (snapshot.saving) return
        val form = snapshot.form
        val errors = validate(form)
        if (errors.isNotEmpty()) {
            _state.update { it.copy(form = it.form.copy(errors = errors)) }
            return
        }
        val title = form.title.trim()
        val titleZh = form.titleZh.trim()
        val setting = form.settingZh.trim()
        val role = form.rolePrompt.trim()
        val opening = form.openingLine.trim()
        viewModelScope.launch {
            _state.update {
                it.copy(saving = true, saveError = null, form = it.form.copy(errors = emptyMap()))
            }
            try {
                if (form.editingId.isNotEmpty()) {
                    c.chat.updateScenario(form.editingId, title, titleZh, setting, role, opening, form.level)
                } else {
                    val audience = if (snapshot.isChild) "child" else form.audience
                    c.chat.createScenario(title, titleZh, setting, role, opening, form.level, audience)
                }
                _state.update {
                    it.copy(
                        saving = false,
                        form = ChatCustomForm(),
                        notice = if (form.editingId.isNotEmpty()) "场景已更新" else "场景已创建",
                    )
                }
                ChatRefreshBus.bump()
                load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(saving = false, saveError = c.session.toUiErrorAsync(e)) }
            }
        }
    }

    // ------------------------------------------------------------------ 删除

    fun requestDelete(id: String) {
        _state.update { it.copy(confirmingDeleteId = id) }
    }

    fun cancelDelete() {
        _state.update { it.copy(confirmingDeleteId = "") }
    }

    fun confirmDelete() {
        val id = _state.value.confirmingDeleteId
        if (id.isEmpty() || _state.value.saving) return
        viewModelScope.launch {
            _state.update { it.copy(saving = true, confirmingDeleteId = "", saveError = null) }
            try {
                c.chat.deleteScenario(id)
                _state.update { it.copy(saving = false, notice = "场景已删除") }
                ChatRefreshBus.bump()
                load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update { it.copy(saving = false, saveError = c.session.toUiErrorAsync(e)) }
            }
        }
    }

    fun consumeNotice() {
        _state.update { it.copy(notice = "") }
    }

    // ------------------------------------------------------------------ 内部

    private fun updateForm(block: (ChatCustomForm) -> ChatCustomForm) {
        _state.update { it.copy(form = block(it.form), saveError = null) }
    }

    private fun validate(form: ChatCustomForm): Map<String, String> {
        val errors = LinkedHashMap<String, String>()
        if (form.title.trim().length !in 1..40) {
            errors[KEY_TITLE] = "英文标题需为 1–40 个字符"
        }
        if (form.titleZh.trim().length !in 1..40) {
            errors[KEY_TITLE_ZH] = "中文标题需为 1–40 个字符"
        }
        if (form.settingZh.trim().length !in 1..200) {
            errors[KEY_SETTING_ZH] = "场景说明需为 1–200 个字符"
        }
        // 编辑时留空 = 不修改角色设定（列表接口不返回 role_prompt）
        if (form.editingId.isEmpty() || form.rolePrompt.trim().isNotEmpty()) {
            if (form.rolePrompt.trim().length !in 20..1500) {
                errors[KEY_ROLE_PROMPT] = "角色设定需为 20–1500 个字符"
            }
        }
        if (form.openingLine.trim().length !in 5..200) {
            errors[KEY_OPENING_LINE] = "开场白需为 5–200 个字符"
        }
        return errors
    }

    private fun defaultLevel(): String {
        val cefr = c.session.state.value.cefrLevel.trim().uppercase()
        return if (cefr in LEVELS) cefr else "A2"
    }

    companion object {
        private const val KEY_TITLE = "title"
        private const val KEY_TITLE_ZH = "titleZh"
        private const val KEY_SETTING_ZH = "settingZh"
        private const val KEY_ROLE_PROMPT = "rolePrompt"
        private const val KEY_OPENING_LINE = "openingLine"

        /** 难度档位（与服务端 level 校验一致）。 */
        val LEVELS: List<String> = listOf("A1", "A2", "B1", "B2", "C1")
    }
}

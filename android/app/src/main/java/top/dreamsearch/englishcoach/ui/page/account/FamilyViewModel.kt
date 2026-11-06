package top.dreamsearch.englishcoach.ui.page.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.dto.FamilyCreateBodyDto
import top.dreamsearch.englishcoach.core.net.dto.FamilyMemberDto
import top.dreamsearch.englishcoach.core.net.dto.FamilyPatchBodyDto

/**
 * 家庭成员 VM（对应 hos `FamilyVM`，`hos/entry/.../viewmodel/AccountVM.ets` L442-671）。
 *
 * 数据来源：`AccountService.familyMembers/createMember/updateMember/resetMemberPassword`
 * （`/api/family/members`，仅家长）。
 *
 * 关键约定（照抄 hos）：
 * - **没有删除成员接口**（服务端未提供），页面不出现删除入口；
 * - 新建校验：昵称 1–20 / 登录名非空 / 密码 ≥8 / 每日时长 5–180；409 → 「登录名已经有人用了」；
 * - 编辑**不能改角色**（服务端传 role 会 400），只改昵称/等级/时长/自由对话；
 * - 重置密码是家长管理员操作（**没有旧密码校验**），成功后提示「旧密码已失效」。
 */
data class FamilyUiState(
    val loading: Boolean = true,
    val error: UiError? = null,
    val members: List<FamilyMemberDto> = emptyList(),
    val notice: String = "",

    // ---- 新建表单
    val formVisible: Boolean = false,
    val formName: String = "",
    val formLogin: String = "",
    val formPassword: String = "",
    /** parent | child */
    val formRole: String = "child",
    val formCefr: String = "A1",
    val formLimit: Int = 20,
    val formFreeChat: Boolean = false,
    val formError: String = "",
    val creating: Boolean = false,

    // ---- 行内编辑
    val editingId: String = "",
    val editName: String = "",
    val editCefr: String = "A2",
    val editLimit: Int = 20,
    val editFreeChat: Boolean = false,
    val editError: String = "",
    val savingEdit: Boolean = false,

    // ---- 重置密码（弹层）
    val resettingId: String = "",
    val resetPassword: String = "",
    val resetError: String = "",
    val resetting: Boolean = false,
)

class FamilyViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(FamilyUiState())
    val state: StateFlow<FamilyUiState> = _state.asStateFlow()

    private var loadJob: Job? = null

    init {
        load()
    }

    fun load() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _state.update { it.copy(loading = it.members.isEmpty(), error = null) }
            try {
                val members = c.account.familyMembers()
                _state.update { it.copy(loading = false, members = members, error = null) }
            } catch (e: Throwable) {
                _state.update { it.copy(loading = false, error = c.session.toUiErrorAsync(e)) }
            }
        }
    }

    fun retry() = load()

    fun clearNotice() {
        _state.update { it.copy(notice = "") }
    }

    // ------------------------------------------------------------------ 新建

    fun toggleForm() {
        _state.update {
            if (it.formVisible) {
                it.copy(formVisible = false, formError = "")
            } else {
                it.copy(
                    formVisible = true,
                    formError = "",
                    formName = "",
                    formLogin = "",
                    formPassword = "",
                    formRole = "child",
                    formCefr = "A1",
                    formLimit = 20,
                    formFreeChat = false,
                    editingId = "",
                )
            }
        }
    }

    fun setFormName(value: String) = _state.update { it.copy(formName = value) }

    fun setFormLogin(value: String) = _state.update { it.copy(formLogin = value) }

    fun setFormPassword(value: String) = _state.update { it.copy(formPassword = value) }

    fun setFormRole(role: String) {
        if (role != "parent" && role != "child") return
        _state.update { it.copy(formRole = role) }
    }

    fun setFormCefr(level: String) = _state.update { it.copy(formCefr = level) }

    fun setFormLimit(value: Int) = _state.update { it.copy(formLimit = value.coerceIn(5, 180)) }

    fun setFormFreeChat(value: Boolean) = _state.update { it.copy(formFreeChat = value) }

    fun create() {
        val s = _state.value
        if (s.creating) return
        val name = s.formName.trim()
        val problem = when {
            name.length !in 1..20 -> "请填写昵称（最多 20 字）"
            s.formLogin.trim().isEmpty() -> "请填写登录名（可只写简称，例如 laoba）"
            s.formPassword.length < 8 -> "密码至少 8 位"
            s.formLimit !in 5..180 -> "每日时长需要在 5–180 分钟之间"
            else -> ""
        }
        if (problem.isNotEmpty()) {
            _state.update { it.copy(formError = problem) }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(creating = true, formError = "") }
            try {
                val member = c.account.createMember(
                    FamilyCreateBodyDto(
                        displayName = name,
                        login = s.formLogin.trim(),
                        password = s.formPassword,
                        role = s.formRole,
                        cefrLevel = s.formCefr,
                        dailyLimitMinutes = s.formLimit,
                        allowFreeChat = s.formFreeChat,
                    ),
                )
                val createdName = member.displayName.ifEmpty { name }
                val login = member.email
                _state.update {
                    it.copy(
                        creating = false,
                        formVisible = false,
                        formName = "",
                        formLogin = "",
                        formPassword = "",
                        notice = "已创建 $createdName" + if (login.isEmpty()) "" else "（登录名 $login）",
                    )
                }
                load()
            } catch (e: Throwable) {
                val apiError = e as? ApiError
                val message = if (apiError != null && apiError.status == 409) {
                    apiError.detail.ifEmpty { "登录名已经有人用了，换一个吧" }
                } else {
                    c.session.toUiErrorAsync(e).message
                }
                _state.update { it.copy(creating = false, formError = message) }
            }
        }
    }

    // ------------------------------------------------------------------ 编辑

    fun beginEdit(member: FamilyMemberDto) {
        _state.update {
            it.copy(
                editingId = member.id,
                editName = member.displayName,
                editCefr = member.cefrLevel.ifEmpty { "A2" },
                editLimit = member.dailyLimitMinutes.coerceIn(5, 180),
                editFreeChat = member.allowFreeChat,
                editError = "",
                resettingId = "",
                formVisible = false,
            )
        }
    }

    fun cancelEdit() = _state.update { it.copy(editingId = "", editError = "") }

    fun setEditName(value: String) = _state.update { it.copy(editName = value) }

    fun setEditCefr(level: String) = _state.update { it.copy(editCefr = level) }

    fun setEditLimit(value: Int) = _state.update { it.copy(editLimit = value.coerceIn(5, 180)) }

    fun setEditFreeChat(value: Boolean) = _state.update { it.copy(editFreeChat = value) }

    fun saveEdit() {
        val s = _state.value
        if (s.savingEdit || s.editingId.isEmpty()) return
        val name = s.editName.trim()
        val problem = when {
            name.length !in 1..20 -> "昵称需为 1–20 个字符"
            s.editLimit !in 5..180 -> "每日时长需要在 5–180 分钟之间"
            else -> ""
        }
        if (problem.isNotEmpty()) {
            _state.update { it.copy(editError = problem) }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(savingEdit = true, editError = "") }
            try {
                c.account.updateMember(
                    s.editingId,
                    FamilyPatchBodyDto(
                        displayName = name,
                        cefrLevel = s.editCefr,
                        dailyLimitMinutes = s.editLimit,
                        allowFreeChat = s.editFreeChat,
                    ),
                )
                _state.update {
                    it.copy(editingId = "", savingEdit = false, notice = "已保存成员信息 ✅")
                }
                load()
            } catch (e: Throwable) {
                _state.update {
                    it.copy(savingEdit = false, editError = c.session.toUiErrorAsync(e).message)
                }
            }
        }
    }

    // ------------------------------------------------------------------ 重置密码

    fun beginReset(member: FamilyMemberDto) {
        _state.update {
            it.copy(
                resettingId = member.id,
                resetPassword = "",
                resetError = "",
                editingId = "",
                formVisible = false,
            )
        }
    }

    fun cancelReset() = _state.update { it.copy(resettingId = "", resetError = "") }

    fun setResetPassword(value: String) = _state.update { it.copy(resetPassword = value) }

    fun resetPassword() {
        val s = _state.value
        if (s.resetting || s.resettingId.isEmpty()) return
        if (s.resetPassword.length < 8) {
            _state.update { it.copy(resetError = "密码至少 8 位") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(resetting = true, resetError = "") }
            try {
                c.account.resetMemberPassword(s.resettingId, s.resetPassword)
                _state.update {
                    it.copy(
                        resetting = false,
                        resettingId = "",
                        resetPassword = "",
                        notice = "密码已重置（旧密码已失效）",
                    )
                }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(resetting = false, resetError = c.session.toUiErrorAsync(e).message)
                }
            }
        }
    }

    // ------------------------------------------------------------------ 展示用

    fun memberTitle(member: FamilyMemberDto): String =
        "${AccountFormat.memberAvatar(member.avatar, member.role)} " +
            member.displayName.ifEmpty { "成员" }

    fun memberBadge(member: FamilyMemberDto): String =
        AccountFormat.roleBadge(member.role, member.cefrLevel)

    fun memberSubText(member: FamilyMemberDto): String {
        val attempts = member.stats?.attempts ?: 0
        return "${member.dailyLimitMinutes} 分钟/天 · 练过 $attempts 次" +
            if (member.allowFreeChat) " · 允许自由对话" else ""
    }

    fun memberEmail(member: FamilyMemberDto): String = member.email

    /** 重置密码弹层里显示的成员名（按 id 反查，避免页面再传参数）。 */
    fun resettingMember(): FamilyMemberDto? {
        val id = _state.value.resettingId
        if (id.isEmpty()) return null
        return _state.value.members.firstOrNull { it.id == id }
    }
}

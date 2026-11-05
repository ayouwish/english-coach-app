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
import top.dreamsearch.englishcoach.core.net.dto.SuggestionCountsDto
import top.dreamsearch.englishcoach.core.net.dto.SuggestionDto

/**
 * 建议箱 VM（对应 hos `SuggestionsVM`，`hos/entry/.../viewmodel/AccountVM.ets` L978-1207）。
 *
 * 数据来源：`AccountService.submitSuggestion/listSuggestions/patchSuggestionStatus/exportSuggestionsMarkdown`。
 *
 * 关键约定（照抄 hos + 任务书）：
 * - 提交：所有人（含儿童）；分类成人 5 类 / 儿童 3 类；正文 1–`maxLength`（默认 2000，服务端可下发）；
 * - 列表 / 标记 / 导出：**仅家长**（儿童不请求，入口也不渲染）；
 * - 导出 Markdown：响应是纯文本，**不下载文件**，弹层展示 + 复制到剪贴板；
 * - 状态非法值不过滤（服务端行为），这里只传空或 open/read/resolved。
 */
data class SuggestionsUiState(
    val isChild: Boolean = false,
    val categories: List<SuggestionCategory> = AccountFormat.CATEGORIES,
    val category: String = "experience",
    val content: String = "",
    val maxLength: Int = 2000,
    val submitting: Boolean = false,
    val submitError: String = "",
    val notice: String = "",

    // ---- 家长列表
    val listLoading: Boolean = false,
    val listLoadedOnce: Boolean = false,
    val listError: UiError? = null,
    val items: List<SuggestionDto> = emptyList(),
    val counts: SuggestionCountsDto? = null,
    val total: Int = 0,
    val filterStatus: String = "",
    val markingId: String = "",

    // ---- 导出（弹层展示 + 复制）
    val exporting: Boolean = false,
    val exportText: String = "",
    val exportVisible: Boolean = false,
    val exportError: String = "",
    val exportNotice: String = "",
)

class SuggestionsViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(SuggestionsUiState())
    val state: StateFlow<SuggestionsUiState> = _state.asStateFlow()

    private var listJob: Job? = null

    init {
        viewModelScope.launch {
            c.session.state.collect { session ->
                val isChild = session.isChild
                val wasChild = _state.value.isChild
                _state.update {
                    it.copy(
                        isChild = isChild,
                        categories = AccountFormat.categoriesFor(isChild),
                        category = if (isChild) "experience" else it.category,
                    )
                }
                // 首次知道「是家长」时拉一次列表（儿童不请求）
                if (!isChild && (wasChild || !_state.value.listLoadedOnce)) loadList()
            }
        }
    }

    // ------------------------------------------------------------------ 提交

    fun setCategory(key: String) {
        if (_state.value.categories.none { it.key == key }) return
        _state.update { it.copy(category = key, submitError = "") }
    }

    fun setContent(value: String) = _state.update { it.copy(content = value, submitError = "") }

    fun clearNotice() = _state.update { it.copy(notice = "") }

    fun submit() {
        val s = _state.value
        if (s.submitting) return
        val text = s.content.trim()
        if (text.isEmpty()) {
            _state.update { it.copy(submitError = if (s.isChild) "先写一句想说的话吧" else "请先写点什么再提交") }
            return
        }
        if (text.length > s.maxLength) {
            _state.update { it.copy(submitError = "建议最多 ${s.maxLength} 字（当前 ${text.length} 字）") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(submitting = true, submitError = "", notice = "") }
            try {
                val result = c.account.submitSuggestion(category = s.category, content = text, page = "/settings")
                _state.update {
                    it.copy(
                        submitting = false,
                        content = "",
                        maxLength = if (result.maxLength > 0) result.maxLength else it.maxLength,
                        notice = if (it.isChild) "收到啦，谢谢你！🌟" else "收到啦，谢谢！已记到建议列表里。",
                    )
                }
                if (!s.isChild) loadList()
            } catch (e: Throwable) {
                _state.update {
                    it.copy(submitting = false, submitError = c.session.toUiErrorAsync(e).message)
                }
            }
        }
    }

    // ------------------------------------------------------------------ 家长列表

    fun setFilter(status: String) {
        if (_state.value.filterStatus == status) return
        _state.update { it.copy(filterStatus = status, listLoadedOnce = false) }
        loadList()
    }

    fun loadList() {
        val s = _state.value
        if (s.isChild) return
        listJob?.cancel()
        listJob = viewModelScope.launch {
            _state.update { it.copy(listLoading = true, listError = null) }
            try {
                val dto = c.account.listSuggestions(status = _state.value.filterStatus, limit = 50, offset = 0)
                _state.update {
                    it.copy(
                        listLoading = false,
                        listLoadedOnce = true,
                        listError = null,
                        items = dto.items,
                        counts = dto.counts,
                        total = dto.total,
                        maxLength = if (dto.maxLength > 0) dto.maxLength else it.maxLength,
                    )
                }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(listLoading = false, listLoadedOnce = true, listError = c.session.toUiErrorAsync(e))
                }
            }
        }
    }

    fun retryList() = loadList()

    fun mark(suggestionId: String, status: String) {
        val s = _state.value
        if (s.markingId.isNotEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(markingId = suggestionId) }
            try {
                c.account.patchSuggestionStatus(suggestionId, status)
                _state.update { it.copy(markingId = "") }
                loadList()
            } catch (e: Throwable) {
                _state.update {
                    it.copy(markingId = "", listError = c.session.toUiErrorAsync(e))
                }
            }
        }
    }

    // ------------------------------------------------------------------ 导出 Markdown

    fun exportMarkdown() {
        val s = _state.value
        if (s.exporting || s.isChild) return
        viewModelScope.launch {
            _state.update { it.copy(exporting = true, exportError = "", exportNotice = "") }
            try {
                val text = c.account.exportSuggestionsMarkdown(status = _state.value.filterStatus)
                _state.update {
                    it.copy(
                        exporting = false,
                        exportText = text,
                        exportVisible = true,
                        exportNotice = "已生成 Markdown，可复制给开发者 / AI 继续优化。",
                    )
                }
            } catch (e: Throwable) {
                _state.update {
                    it.copy(exporting = false, exportError = c.session.toUiErrorAsync(e).message)
                }
            }
        }
    }

    fun dismissExport() = _state.update { it.copy(exportVisible = false) }

    fun clearExportText() = _state.update { it.copy(exportText = "", exportNotice = "") }

    fun onCopied() = _state.update { it.copy(exportNotice = "已复制到剪贴板 ✅") }
}

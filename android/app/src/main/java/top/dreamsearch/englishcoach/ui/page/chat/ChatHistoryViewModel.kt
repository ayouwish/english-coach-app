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
import top.dreamsearch.englishcoach.core.net.dto.ChatSessionSummaryDto

/**
 * 对话历史列表 ViewModel。
 *
 * 对应 hos：`viewmodel/ChatVM.ets` 的 `ChatHistoryVM` + `pages/ChatHistoryPage.ets`。
 *
 * 数据来源：`GET /api/chat/sessions?limit=20`（`ChatService.sessions`，按时间倒序）。
 * 说明（沿袭 hos 的产品口径）：列表接口没有平均发音字段，列表只显示
 * 「时间 · 场景中文名 · N 轮 · 状态」，不编造分数。
 */
data class ChatHistoryUiState(
    val loading: Boolean = true,
    val error: UiError? = null,
    val items: List<ChatSessionSummaryDto> = emptyList(),
    val isChild: Boolean = false,
)

class ChatHistoryViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(ChatHistoryUiState(isChild = c.session.state.value.isChild))
    val state: StateFlow<ChatHistoryUiState> = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null, isChild = c.session.state.value.isChild) }
            try {
                val items = c.chat.sessions(HISTORY_LIMIT)
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

    companion object {
        /** 历史列表条数：与 hos `ChatService.sessions()`（服务端默认最近 30 条）一致。 */
        const val HISTORY_LIMIT = 30
    }
}

package top.dreamsearch.englishcoach.ui.page.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.dto.ChatScenarioDto

/**
 * 对话训练场景列表（Tab 根页）ViewModel。
 *
 * 对应 hos：`viewmodel/ChatVM.ets` 的 `ChatScenarioVM` + `pages/ChatScenariosPage.ets`。
 *
 * 数据来源：`GET /api/chat/scenarios[?include_child=1]`（`ChatService.scenarios`），
 * 点场景卡 → `POST /api/chat/sessions`（`ChatService.createSession`）。
 *
 * 规则：
 * - 成人默认只看成人场景；「再看小朋友的场景」开关落偏好 `chat_include_child`；
 * - 儿童账号只拿服务端返回的适龄场景（include_child 强制 false，不显示开关）；
 * - 429（今日额度）单独用横幅提示，不弹错误条；
 * - 自定义场景保存/删除后由 [ChatRefreshBus] 通知本页重新拉取。
 */
data class ChatScenariosUiState(
    val loading: Boolean = true,
    val error: UiError? = null,
    val isChild: Boolean = false,
    val includeChild: Boolean = false,
    val customItems: List<ChatScenarioDto> = emptyList(),
    val adultItems: List<ChatScenarioDto> = emptyList(),
    val childItems: List<ChatScenarioDto> = emptyList(),
    /** 正在创建会话的场景 id（卡片转圈、防重复点击） */
    val startingId: String = "",
    /** 创建成功后的会话 id：页面据此写 `NavParams.chatSessionId` 并导航，然后清空 */
    val pendingSessionId: String = "",
    val quotaExceeded: Boolean = false,
    val quotaText: String = "",
    val autoRead: Boolean = true,
    val ttsRate: String = "normal",
    val minutesToday: Int = 0,
    val dailyLimitMinutes: Int = 20,
    val remainingMinutes: Int = 0,
)

class ChatScenariosViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(ChatScenariosUiState())
    val state: StateFlow<ChatScenariosUiState> = _state.asStateFlow()

    init {
        val session = c.session.state.value
        val prefs = ChatVoicePrefs.load(c.prefs, session.isChild)
        _state.update {
            it.copy(
                isChild = session.isChild,
                includeChild = readIncludeChildPref(session.isChild),
                autoRead = prefs.autoRead,
                ttsRate = prefs.rate,
                minutesToday = session.minutesToday,
                dailyLimitMinutes = session.dailyLimitMinutes,
                remainingMinutes = session.remainingMinutes,
            )
        }
        // 用量 / 儿童态随全局会话变化
        viewModelScope.launch {
            c.session.state.collect { s ->
                _state.update {
                    it.copy(
                        isChild = s.isChild,
                        minutesToday = s.minutesToday,
                        dailyLimitMinutes = s.dailyLimitMinutes,
                        remainingMinutes = s.remainingMinutes,
                    )
                }
            }
        }
        load()
        // 自定义场景页保存/删除后刷新（等价 hos 的 chat_scenarios_rev）
        viewModelScope.launch {
            ChatRefreshBus.revision.drop(1).collect { load() }
        }
    }

    /** 拉场景列表。默认只拉成人场景；打开开关/儿童账号时按服务端规则返回。 */
    fun load() {
        viewModelScope.launch {
            val snapshot = _state.value
            _state.update { it.copy(loading = true, error = null) }
            try {
                val items = c.chat.scenarios(includeChild = snapshot.includeChild && !snapshot.isChild)
                apply(items)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update {
                    it.copy(
                        loading = false,
                        error = c.session.toUiErrorAsync(e),
                        customItems = emptyList(),
                        adultItems = emptyList(),
                        childItems = emptyList(),
                    )
                }
            }
        }
    }

    /** 成人开关：只看成人 / 再看小朋友；儿童账号忽略。 */
    fun setIncludeChild(value: Boolean) {
        if (_state.value.isChild) return
        _state.update { it.copy(includeChild = value) }
        c.prefs.putString(ChatVoicePrefs.KEY_CHAT_INCLUDE_CHILD, if (value) "1" else "0")
        load()
    }

    /** 场景页的「自动朗读」偏好（本机，供会话页初始读取）。 */
    fun setAutoRead(value: Boolean) {
        _state.update { it.copy(autoRead = value) }
        c.prefs.putString(ChatVoicePrefs.KEY_CHAT_AUTO_READ, if (value) "1" else "0")
    }

    /** 场景页的对话语速偏好（slow / normal）。 */
    fun setTtsRate(rate: String) {
        _state.update { it.copy(ttsRate = rate) }
        c.prefs.putString(ChatVoicePrefs.KEY_CHAT_TTS_RATE, rate)
    }

    /** 点场景卡：`POST /chat/sessions` → 交接会话数据（页面的 LaunchedEffect 负责导航）。 */
    fun start(scenario: ChatScenarioDto) {
        val snapshot = _state.value
        if (snapshot.startingId.isNotEmpty() || snapshot.pendingSessionId.isNotEmpty()) return
        _state.update { it.copy(startingId = scenario.id, quotaExceeded = false, error = null) }
        viewModelScope.launch {
            try {
                val session = c.chat.createSession(scenario.id)
                ChatSessionHandoff.put(session, scenario)
                _state.update { it.copy(startingId = "", pendingSessionId = session.sessionId) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                if ((e as? ApiError)?.status == 429) {
                    _state.update {
                        it.copy(
                            startingId = "",
                            quotaExceeded = true,
                            quotaText = ui.message.ifEmpty {
                                if (it.isChild) "今天已经练得很棒啦，明天再来 🌙" else "今天的练习时间到了，明天再来"
                            },
                        )
                    }
                } else {
                    _state.update { it.copy(startingId = "", error = ui) }
                }
            }
        }
    }

    /** 页面完成导航后清空 pendingSessionId，避免重复 push。 */
    fun consumePendingSession() {
        _state.update { it.copy(pendingSessionId = "") }
    }

    private fun apply(items: List<ChatScenarioDto>) {
        val custom = items.filter { it.isCustom }
        val child = items.filter { !it.isCustom && it.audience == "child" }
        val adult = items.filter { !it.isCustom && it.audience != "child" }
        _state.update {
            it.copy(
                loading = false,
                error = null,
                customItems = custom,
                adultItems = adult,
                childItems = child,
            )
        }
    }

    private fun readIncludeChildPref(isChild: Boolean): Boolean =
        !isChild && c.prefs.getString(ChatVoicePrefs.KEY_CHAT_INCLUDE_CHILD, "0") == "1"
}

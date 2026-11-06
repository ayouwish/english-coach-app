package top.dreamsearch.englishcoach.ui.page.practice

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.dto.SentenceDto
import top.dreamsearch.englishcoach.ui.nav.NavParams

/**
 * 句子列表页状态（对应 hos `viewmodel/SentenceListVM.ets` + `pages/SentenceListPage.ets`）。
 *
 * 职责：
 * - 按账号等级（C1 → B2 回退）拉当前等级**全部句子**；
 * - 列表缓存（`CacheStore.readJson/writeJson`）：**先显示缓存再刷新**（`refreshing`）；
 * - 高亮「当前句」：读本地练习游标 `AppPrefs.practice_cursor_<level>`；
 * - 点选：写 [NavParams.practiceSentenceId]/[NavParams.practiceLevel] 后由页面 `onBack()` 回跟读页；
 * - 空态 / 错误态 / 加载态都通过字段表达，页面不猜测。
 */
class SentenceListViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(SentenceListUiState())
    val state: StateFlow<SentenceListUiState> = _state.asStateFlow()

    private var loadJob: Job? = null

    init {
        // 从跟读页进来时带了当前练习等级（NavParams.practiceLevel）；否则用账号等级
        val navLevel = NavParams.practiceLevel?.uppercase()?.takeIf { it in PracticeLevels.ALL }
        val level = navLevel ?: c.config.levelForCefr(c.session.state.value.cefrLevel)
        _state.update {
            it.copy(
                level = level,
                isChild = c.session.isChild,
                currentSentenceId = cursorOf(level),
            )
        }
        load(level)
    }

    /** 切换等级：换一批句子（缓存优先），并同步该等级的「当前句」高亮。 */
    fun selectLevel(level: String) {
        if (level == _state.value.level || level !in PracticeLevels.ALL) return
        _state.update {
            it.copy(
                level = level,
                currentSentenceId = cursorOf(level),
                sentences = emptyList(),
                error = null,
                loading = true,
                loadedOnce = false,
            )
        }
        load(level)
    }

    /** 重试 / 下拉刷新（跳过缓存直接请求）。 */
    fun reload() {
        load(_state.value.level, force = true)
    }

    /** 点选一句：写跨页参数（等级 + 句子 id），跟读 Tab 下次进入时定位到该句。 */
    fun pick(sentenceId: String) {
        if (sentenceId.isEmpty()) return
        NavParams.practiceSentenceId = sentenceId
        NavParams.practiceLevel = _state.value.level
    }

    private fun cursorOf(level: String): String = c.prefs.getString(practiceCursorKey(level), "")

    /**
     * 加载当前等级语料：缓存先显示（`loading=false, refreshing=true`）→ 网络刷新 → 写缓存。
     * 有缓存但刷新失败：保留列表 + 顶部错误条（可重试）；无缓存失败：整页错误态。
     */
    private fun load(level: String, force: Boolean = false) {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            val cached = if (force) emptyList() else withContext(Dispatchers.IO) {
                readSentencesCache(c.cache, level, "")
            }
            val hasCached = cached.isNotEmpty()
            _state.update {
                it.copy(
                    loading = !hasCached,
                    refreshing = hasCached,
                    error = null,
                    loadedOnce = hasCached || it.loadedOnce,
                )
            }
            if (hasCached) applyList(level, cached)
            try {
                val list = c.practice.sentences(level, "")
                withContext(Dispatchers.IO) { writeSentencesCache(c.cache, level, "", list) }
                applyList(level, list)
                _state.update {
                    it.copy(loading = false, refreshing = false, loadedOnce = true)
                }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update {
                    if (hasCached) {
                        it.copy(loading = false, refreshing = false, error = ui)
                    } else {
                        it.copy(loading = false, refreshing = false, error = ui, sentences = emptyList())
                    }
                }
            }
        }
    }

    private fun applyList(level: String, list: List<SentenceDto>) {
        val isChild = c.session.isChild
        val sentences = list.mapIndexed { index, dto -> dto.toPracticeUi(index, list.size, isChild) }
        // 没有游标（第一次练）时跟读页默认第一句，这里也高亮第一句
        val current = cursorOf(level).ifEmpty { sentences.firstOrNull()?.id.orEmpty() }
        _state.update {
            it.copy(
                level = level,
                isChild = isChild,
                sentences = sentences,
                currentSentenceId = current,
            )
        }
    }
}

/** 句子列表页状态（页面只渲染这里的数据）。 */
data class SentenceListUiState(
    val loading: Boolean = true,
    /** 有缓存先显示、后台刷新中 */
    val refreshing: Boolean = false,
    /** 已成功加载过（用于区分「还没加载」和「确实为空」） */
    val loadedOnce: Boolean = false,
    val error: UiError? = null,
    val level: String = "A1",
    val levels: List<String> = PracticeLevels.ALL,
    val sentences: List<PracticeSentenceUi> = emptyList(),
    /** 本地练习游标指向的句子（高亮「正在练」） */
    val currentSentenceId: String = "",
    val isChild: Boolean = false,
) {
    /** 真空态：加载过、不在加载、没有错误、确实没有句子。 */
    val isEmpty: Boolean get() = loadedOnce && !loading && error == null && sentences.isEmpty()
}

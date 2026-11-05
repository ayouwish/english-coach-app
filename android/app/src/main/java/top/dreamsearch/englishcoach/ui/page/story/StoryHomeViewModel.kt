package top.dreamsearch.englishcoach.ui.page.story

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.dto.StoryMaterialDto

/**
 * 故事集 Tab 的 ViewModel（对应 hos `StoryHomeVM`）。
 *
 * 数据来源：`StoryService.materials(kind, limit)`（家庭共享、服务端已排序）。
 * - 「全家 / 只看我的」：**客户端过滤** `created_by == 当前 userId`（后端没有 mine 参数）；
 * - 「故事 / 书页」：kind=story 走默认，kind=page 传 `materials("page")`；
 * - **第二轮新增**：按 `created_at` 分「今天 / 昨天 / 更早」三组；顶部「🔥 连续讲故事 N 天」按
 *   本机 `AppPrefs` 里记录的历史日期集合计算（见 [StoryDates.streakDays]，无数据返回 0 不显示）；
 * - 新建/改名/删除后由 [StoryRuntime.refreshTick] 通知本 VM 重新拉列表（Tab 根页没有 onPageShow）。
 */
data class StoryListItem(
    val id: String,
    val title: String,
    val level: String,
    val sentenceCount: Int,
    val authorName: String,
    val authorId: String,
    val hasImage: Boolean,
    val dateText: String,
    /** 本地时区的 yyyy-MM-dd；解析失败为空串（归到「更早」） */
    val dateKey: String,
    val kind: String,
)

/** 一段日期分组的展示模型（组内保持服务端顺序）。 */
data class StoryGroup(
    val label: String,
    val items: List<StoryListItem>,
)

data class StoryHomeUiState(
    val loading: Boolean = true,
    val error: UiError? = null,
    /** story | page */
    val kind: String = StoryHomeViewModel.KIND_STORY,
    val onlyMine: Boolean = false,
    /** 当前 kind 下服务端返回的全部条目（未做「只看我的」过滤） */
    val allItems: List<StoryListItem> = emptyList(),
    /** 过滤后的平铺条目（数量统计用） */
    val items: List<StoryListItem> = emptyList(),
    /** 过滤 + 按「今天/昨天/更早」分组后的列表（页面渲染用） */
    val groups: List<StoryGroup> = emptyList(),
    /** 连续讲故事天数；0 = 不显示 chip */
    val streakDays: Int = 0,
    val isChild: Boolean = false,
)

class StoryHomeViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(StoryHomeUiState())
    val state: StateFlow<StoryHomeUiState> = _state.asStateFlow()

    private var userId: String = ""
    private var loadJob: Job? = null

    /** 本机记录过的故事日期（yyyy-MM-dd），跨启动保留。 */
    private val seenDates: MutableSet<String> = LinkedHashSet()

    init {
        seenDates.addAll(readSeenDates())
        // 会话状态（userId 用于「只看我的」过滤；儿童用于文案）
        viewModelScope.launch {
            c.session.state.collect { session ->
                userId = session.userId
                _state.update { it.copy(isChild = session.isChild) }
                rebuild()
            }
        }
        load()
        // 新建 / 改名 / 删除后刷新（collect 会先发当前值 0，跳过）
        viewModelScope.launch {
            StoryRuntime.refreshTick.collect { tick ->
                if (tick > 0) load()
            }
        }
    }

    /** 拉当前 kind 的列表；已有数据时保留旧列表，失败只出错误条。 */
    fun load() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            val kind = _state.value.kind
            _state.update { it.copy(loading = it.allItems.isEmpty(), error = null) }
            try {
                val list = c.story.materials(kind = kind, limit = PAGE_LIMIT)
                _state.update { current ->
                    if (current.kind != kind) {
                        current
                    } else {
                        val mapped = list.map(::toItem)
                        current.copy(
                            loading = false,
                            error = null,
                            allItems = mapped,
                        )
                    }
                }
                // 只有「故事」计入连续天数；书页不算讲故事（kind 中途被切换时丢弃本次结果）
                val current = _state.value
                if (current.kind == kind && kind == KIND_STORY) {
                    val added = current.allItems.map { it.dateKey }.filter { it.isNotEmpty() }
                    if (added.isNotEmpty()) {
                        seenDates.addAll(added)
                        writeSeenDates()
                    }
                }
                rebuild()
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(loading = false, error = ui) }
            }
        }
    }

    /** 「全家 / 只看我的」切换：纯客户端过滤，不重新请求。 */
    fun setOnlyMine(value: Boolean) {
        if (_state.value.onlyMine == value) return
        _state.update { it.copy(onlyMine = value) }
        rebuild()
    }

    /** 「故事 / 书页」切换：kind 变化才重新请求。 */
    fun setKind(kind: String) {
        if (kind != KIND_STORY && kind != KIND_PAGE) return
        if (_state.value.kind == kind) return
        _state.update { it.copy(kind = kind, allItems = emptyList(), items = emptyList(), groups = emptyList()) }
        load()
    }

    fun retry() = load()

    // ------------------------------------------------------------------ 过滤 / 分组

    private fun rebuild() {
        _state.update { current ->
            val visible = filter(current.onlyMine, current.allItems)
            current.copy(
                items = visible,
                groups = buildGroups(visible),
                streakDays = if (current.kind == KIND_STORY) {
                    StoryDates.streakDays(seenDates)
                } else {
                    0
                },
            )
        }
    }

    private fun filter(onlyMine: Boolean, items: List<StoryListItem>): List<StoryListItem> {
        if (!onlyMine) return items
        if (userId.isEmpty()) return emptyList()
        return items.filter { it.authorId == userId }
    }

    /** 按「今天 / 昨天 / 更早」分组；组顺序固定，组内保持服务端顺序。 */
    private fun buildGroups(items: List<StoryListItem>): List<StoryGroup> {
        if (items.isEmpty()) return emptyList()
        val today = java.time.LocalDate.now()
        val todayKey = StoryDates.keyOf(today)
        val yesterdayKey = StoryDates.yesterdayKey(today)
        val buckets = linkedMapOf<String, MutableList<StoryListItem>>(
            LABEL_TODAY to ArrayList(),
            LABEL_YESTERDAY to ArrayList(),
            LABEL_EARLIER to ArrayList(),
        )
        items.forEach { item ->
            val label = if (item.dateKey.isEmpty()) {
                LABEL_EARLIER
            } else {
                StoryDates.labelOf(item.dateKey, todayKey, yesterdayKey)
            }
            buckets.getValue(label).add(item)
        }
        return GROUPS.mapNotNull { label ->
            val groupItems = buckets.getValue(label)
            if (groupItems.isEmpty()) null else StoryGroup(label = label, items = groupItems)
        }
    }

    // ------------------------------------------------------------------ 本地日期集合

    private fun readSeenDates(): List<String> {
        val raw = c.prefs.getString(KEY_SEEN_DATES, "")
        if (raw.isEmpty()) return emptyList()
        return raw.split(',').map { it.trim() }.filter { DATE_KEY_RE.matches(it) }
    }

    private fun writeSeenDates() {
        val kept = seenDates.sortedDescending().take(SEEN_DATES_LIMIT)
        c.prefs.putString(KEY_SEEN_DATES, kept.joinToString(","))
    }

    private fun toItem(dto: StoryMaterialDto): StoryListItem = StoryListItem(
        id = dto.id,
        title = dto.title.trim().ifEmpty { "未命名故事" },
        level = dto.level.orEmpty(),
        sentenceCount = dto.sentenceCount,
        authorName = dto.createdByName,
        authorId = dto.createdBy.orEmpty(),
        hasImage = dto.hasImage,
        dateText = StoryText.dateTextOf(dto.createdAt),
        dateKey = StoryDates.keyFromIso(dto.createdAt),
        kind = dto.kind.ifEmpty { KIND_STORY },
    )

    companion object {
        const val KIND_STORY = "story"
        const val KIND_PAGE = "page"

        private const val PAGE_LIMIT = 50

        /** `AppPrefs` 里的故事日期集合（逗号分隔的 yyyy-MM-dd）。 */
        private const val KEY_SEEN_DATES = "story_seen_dates"

        /** 最多保留 400 个日期，控制偏好体积。 */
        private const val SEEN_DATES_LIMIT = 400

        private const val LABEL_TODAY = "今天"
        private const val LABEL_YESTERDAY = "昨天"
        private const val LABEL_EARLIER = "更早"
        private val GROUPS = listOf(LABEL_TODAY, LABEL_YESTERDAY, LABEL_EARLIER)

        private val DATE_KEY_RE = Regex("^\\d{4}-\\d{2}-\\d{2}$")
    }
}

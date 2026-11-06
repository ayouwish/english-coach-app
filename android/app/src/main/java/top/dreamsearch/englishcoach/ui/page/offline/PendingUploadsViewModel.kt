package top.dreamsearch.englishcoach.ui.page.offline

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import java.io.File

/**
 * 待补评分录音页 ViewModel（离线能力，ROUND2_CONTRACT §1.3 / §4）。
 *
 * 数据来源：[AppContainer.pendingUploads]（`PendingUploadQueue`，录音与索引都存在本机）：
 * - `list()/count()` 读列表；`remove(id)/clear()` 删单条/全部；
 * - `retryAll(practice)` 串行重试（内部用 `PracticeService.evaluate`，成功即删、失败保留并记
 *   `retryCount/lastError`），返回 `RetrySummary(attempted/succeeded/failed/lastError)`；
 * - 用量同步：`RetrySummary` 按契约不含 usage，补评分成功后用 `GET /auth/me` 的 usage 兜底
 *   调一次 `SessionStore.updateUsage`（服务端没返回 usage 就跳过，不影响结果）。
 *
 * 页面不直接发网络请求；播放走 `AudioController`；删除/重试都经本 VM。
 */

/** 列表条目（页面只渲染这个，不直接依赖队列内部类型）。 */
data class PendingUploadItemUi(
    val id: String,
    val sentenceId: String,
    val referenceText: String,
    val fileName: String,
    val durationMs: Int,
    val createdAt: Long,
    val retryCount: Int,
    val lastError: String?,
    val file: File,
)

/** 一次「全部重试」的结果汇总。 */
data class PendingRetryResult(
    val attempted: Int,
    val succeeded: Int,
    val failed: Int,
    val lastError: String?,
    val minutesToday: Int,
    val dailyLimitMinutes: Int,
)

data class PendingUploadsUiState(
    val loading: Boolean = true,
    val error: UiError? = null,
    val items: List<PendingUploadItemUi> = emptyList(),
    val isChild: Boolean = false,
    /** 是否有可用网络（Wi-Fi/以太网/VPN/移动网络任一 transport；家庭 NAS 可能没有公网） */
    val online: Boolean = true,
    /** 正在试听的条目 id（空 = 没在播） */
    val playingId: String = "",
    /** 待二次确认删除的单条 id */
    val deletingId: String = "",
    /** 待二次确认「清除全部」 */
    val confirmClearAll: Boolean = false,
    val retrying: Boolean = false,
    val retryProgress: String = "",
    val retryProcessed: Int = 0,
    val retryTotal: Int = 0,
    val result: PendingRetryResult? = null,
    /** 非错误提示（已删除/已清空/播放失败等） */
    val notice: String = "",
    val noticeWarn: Boolean = false,
)

class PendingUploadsViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(PendingUploadsUiState(isChild = c.session.state.value.isChild))
    val state: StateFlow<PendingUploadsUiState> = _state.asStateFlow()

    private var progressJob: Job? = null

    init {
        load()
    }

    // ------------------------------------------------------------------ 列表

    /** 首次加载（带整页 loading）。 */
    fun load() {
        loadInternal(showLoading = true)
    }

    /** 回到前台/从别处返回时静默刷新（不闪 loading；首次加载还没结束就跳过，避免重复拉取）。 */
    fun refresh() {
        if (_state.value.loading) return
        loadInternal(showLoading = _state.value.items.isEmpty())
    }

    private fun loadInternal(showLoading: Boolean) {
        viewModelScope.launch {
            val online = checkOnline()
            if (showLoading) {
                _state.update { it.copy(loading = true, error = null, online = online, isChild = c.session.state.value.isChild) }
            } else {
                _state.update { it.copy(online = online, isChild = c.session.state.value.isChild) }
            }
            try {
                val items = loadItems()
                _state.update { current ->
                    val playing = current.playingId
                    current.copy(
                        loading = false,
                        error = null,
                        items = items,
                        // 列表里已经没有这条（被删/补评分成功）→ 清掉播放态
                        playingId = if (items.any { it.id == playing }) playing else "",
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(loading = false, error = ui) }
            }
        }
    }

    /** 读队列（磁盘 IO 放到 IO 线程，保持主线程不卡）。 */
    private suspend fun loadItems(): List<PendingUploadItemUi> = withContext(Dispatchers.IO) {
        c.pendingUploads.list().map { upload ->
            PendingUploadItemUi(
                id = upload.id,
                sentenceId = upload.sentenceId,
                referenceText = upload.referenceText,
                fileName = upload.fileName,
                durationMs = upload.durationMs,
                createdAt = upload.createdAt,
                retryCount = upload.retryCount,
                lastError = upload.lastError,
                file = upload.file,
            )
        }
    }

    // ------------------------------------------------------------------ 试听

    /** 试听本机录音；再点一次停止。 */
    fun playItem(itemId: String) {
        val snapshot = _state.value
        val item = snapshot.items.firstOrNull { it.id == itemId } ?: return
        if (snapshot.playingId == itemId) {
            runCatching { c.audio.stopPlayback() }
            _state.update { it.copy(playingId = "") }
            return
        }
        viewModelScope.launch {
            runCatching { c.audio.stopPlayback() }
            _state.update { it.copy(playingId = "", notice = "", noticeWarn = false) }
            try {
                c.audio.playFile(item.file)
                _state.update { it.copy(playingId = itemId) }
                // playFile 没有完成回调：等 playing 归零（带超时兜底）
                withTimeoutOrNull(PLAY_WAIT_MS) { c.audio.playing.first { !it } }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                _state.update {
                    it.copy(
                        playingId = "",
                        notice = if (it.isChild) "这条声音暂时放不出来，等一下再试" else "这条录音暂时放不出来，请稍后再试",
                        noticeWarn = true,
                    )
                }
                return@launch
            }
            _state.update { if (it.playingId == itemId) it.copy(playingId = "") else it }
        }
    }

    // ------------------------------------------------------------------ 删除

    fun requestDelete(itemId: String) {
        if (_state.value.retrying) return
        _state.update { it.copy(deletingId = itemId) }
    }

    fun cancelDelete() {
        _state.update { it.copy(deletingId = "") }
    }

    /** 二次确认后删除单条（队列文件与索引一起删）。 */
    fun confirmDelete() {
        val snapshot = _state.value
        val id = snapshot.deletingId
        if (id.isEmpty() || snapshot.retrying) return
        if (snapshot.playingId == id) {
            runCatching { c.audio.stopPlayback() }
            _state.update { it.copy(playingId = "") }
        }
        _state.update { it.copy(deletingId = "") }
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { c.pendingUploads.remove(id) }
                val items = loadItems()
                _state.update {
                    it.copy(
                        items = items,
                        error = null,
                        result = null,
                        notice = if (it.isChild) "删掉啦" else "已删除 1 条本机录音",
                        noticeWarn = false,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(error = ui) }
            }
        }
    }

    fun requestClearAll() {
        if (_state.value.retrying || _state.value.items.isEmpty()) return
        _state.update { it.copy(confirmClearAll = true) }
    }

    fun cancelClearAll() {
        _state.update { it.copy(confirmClearAll = false) }
    }

    /** 二次确认后清空整个队列（含录音文件）。 */
    fun confirmClearAll() {
        val snapshot = _state.value
        if (snapshot.retrying || snapshot.loading) return
        val removed = snapshot.items.size
        _state.update { it.copy(confirmClearAll = false) }
        viewModelScope.launch {
            runCatching { c.audio.stopPlayback() }
            _state.update { it.copy(playingId = "") }
            try {
                withContext(Dispatchers.IO) { c.pendingUploads.clear() }
                _state.update {
                    it.copy(
                        items = emptyList(),
                        error = null,
                        result = null,
                        retryProgress = "",
                        retrying = false,
                        notice = if (it.isChild) "都清干净啦" else "已清除 $removed 条本机录音",
                        noticeWarn = false,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(error = ui) }
            }
        }
    }

    // ------------------------------------------------------------------ 全部重试（retryAll）

    /**
     * 串行补评分：
     * 1. 没网直接提示（按钮此时也是禁用的，这里是兜底）；
     * 2. `pendingUploads.retryAll(practice)` 内部逐条 `evaluate`，成功即删；
     *    `retryAll` 是单个 suspend 调用，所以用一个 1.2s 的计数器轮询 `count()` 给「已处理 i/N」进度；
     * 3. 有成功项 → `/auth/me` 同步 usage（`session.updateUsage`）；
     * 4. 重新读列表（失败项保留并带最新 lastError），把汇总放到 [PendingUploadsUiState.result]。
     */
    fun retryAll() {
        val snapshot = _state.value
        if (snapshot.retrying || snapshot.items.isEmpty()) return
        if (!checkOnline()) {
            _state.update {
                it.copy(
                    online = false,
                    notice = if (it.isChild) {
                        "现在没有网络。等连上家里的 Wi-Fi 再点「全部补评分」吧"
                    } else {
                        "现在没有网络。连上家里的 Wi-Fi 后再点「全部重试」。"
                    },
                    noticeWarn = true,
                )
            }
            return
        }
        val total = snapshot.items.size
        _state.update {
            it.copy(
                retrying = true,
                retryTotal = total,
                retryProcessed = 0,
                retryProgress = "正在逐条补评分… 0/$total 条",
                result = null,
                error = null,
                notice = "",
                noticeWarn = false,
            )
        }
        viewModelScope.launch {
            progressJob?.cancel()
            progressJob = launch {
                while (isActive) {
                    delay(PROGRESS_TICK_MS)
                    val remaining = runCatching {
                        withContext(Dispatchers.IO) { c.pendingUploads.count() }
                    }.getOrDefault(total)
                    val processed = (total - remaining).coerceIn(0, total)
                    _state.update {
                        it.copy(
                            retryProcessed = processed,
                            retryProgress = if (it.isChild) {
                                "正在一条一条地补评分… 已补好 $processed/$total 条"
                            } else {
                                "正在逐条补评分… 已补好 $processed/$total 条"
                            },
                        )
                    }
                }
            }
            try {
                // 队列内部逐条串行上传；每次重试前它自己会重新读 token
                val summary = c.pendingUploads.retryAll(c.practice)
                if (summary.succeeded > 0) syncUsageAfterRetry()
                val items = loadItems()
                val session = c.session.state.value
                _state.update { current ->
                    current.copy(
                        items = items,
                        retrying = false,
                        retryProgress = "",
                        retryProcessed = summary.attempted,
                        retryTotal = total,
                        playingId = if (items.any { item -> item.id == current.playingId }) current.playingId else "",
                        result = PendingRetryResult(
                            attempted = summary.attempted,
                            succeeded = summary.succeeded,
                            failed = summary.failed,
                            lastError = summary.lastError,
                            minutesToday = session.minutesToday,
                            dailyLimitMinutes = session.dailyLimitMinutes,
                        ),
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                val items = runCatching { loadItems() }.getOrDefault(_state.value.items)
                val ui = c.session.toUiErrorAsync(e)
                _state.update {
                    it.copy(
                        items = items,
                        retrying = false,
                        retryProgress = "",
                        error = ui,
                    )
                }
            } finally {
                progressJob?.cancel()
                progressJob = null
                _state.update { it.copy(retrying = false, retryProgress = "") }
            }
        }
    }

    /**
     * 补评分成功后的用量同步。
     *
     * ROUND2 §1.3 的 `RetrySummary` 不含 usage（队列拿不到 SessionStore），所以这里用
     * `GET /auth/me` 的 usage 兜底调用 [SessionStore.updateUsage]；拿不到就静默跳过——
     * 用量只是展示信息，不能因为它失败而让「已补评分」显示成失败。
     */
    private suspend fun syncUsageAfterRetry() {
        val me = try {
            c.auth.me()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            null
        } ?: return
        me.usage?.let { c.session.updateUsage(it) }
    }

    // ------------------------------------------------------------------ 状态清理

    fun dismissResult() {
        _state.update { it.copy(result = null) }
    }

    fun consumeNotice() {
        _state.update { it.copy(notice = "", noticeWarn = false) }
    }

    /** 页面离开：停播放（录音是队列文件，不动）。 */
    fun onLeave() {
        runCatching { c.audio.stopPlayback() }
        _state.update { it.copy(playingId = "") }
    }

    override fun onCleared() {
        super.onCleared()
        progressJob?.cancel()
        progressJob = null
        runCatching { c.audio.stopPlayback() }
    }

    // ------------------------------------------------------------------ 内部

    /**
     * 本机是否有可用网络。
     *
     * 注意：家庭 NAS 只在局域网可达、不一定有公网，所以**不要求** VALIDATED/INTERNET 能力，
     * 只要有 Wi-Fi / 以太网 / VPN / 移动网络任一 transport 就视为「有网」（真正连不连得上
     * 仍由 retryAll 的请求结果决定）。
     */
    private fun checkOnline(): Boolean {
        return try {
            val manager = c.appContextRef.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return true
            val network = manager.activeNetwork ?: return false
            val capabilities = manager.getNetworkCapabilities(network) ?: return false
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
        } catch (e: Throwable) {
            // 读网络状态失败时按「有网」处理，让真正的请求去报错
            true
        }
    }

    companion object {
        /** 播放等待兜底（本机录音最长 60s，给 2 分钟）。 */
        private const val PLAY_WAIT_MS = 120_000L

        /** 重试进度轮询间隔。 */
        private const val PROGRESS_TICK_MS = 1_200L
    }
}

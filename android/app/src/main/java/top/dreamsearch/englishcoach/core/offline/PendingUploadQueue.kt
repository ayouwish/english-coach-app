package top.dreamsearch.englishcoach.core.offline

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.EcJson
import top.dreamsearch.englishcoach.core.service.PracticeService
import top.dreamsearch.englishcoach.core.storage.CacheStore
import top.dreamsearch.englishcoach.core.util.FileUtil
import java.io.File
import java.util.UUID

/**
 * 失败录音的**待补评分队列**（离线能力，对应 ROUND2_CONTRACT §1.3）。
 *
 * 场景：跟读/连读提交 `POST /attempts` 时网络失败或服务端 5xx（**不是** 4xx 业务错误）→
 * VM 调 [enqueue] 把录音拷进队列目录并提示「已保存到本机，稍后可补评分」；
 * 首页「待补评分」横幅 / 离线页通过 [count] / [list] / [retryAll] 消费。
 *
 * 存储：
 * - 目录 = `CacheStore.pendingUploadsDir()`；
 * - 索引 = `queue.json`（`kotlinx.serialization`，与项目其它 JSON 一致）；
 * - 录音 = 同目录 `pending_<uuid>.m4a`（[enqueue] **拷贝**，调用方随后可删原文件）。
 *
 * 健壮性：
 * - 所有索引读写走同一把锁（线程安全）；
 * - 索引损坏/半截 JSON → 丢弃坏索引并返回空队列（自愈）；索引里指向的录音不存在 → 自动剔除；
 * - 索引里没引用的孤儿录音 → 顺手清理；
 * - [retryAll] 串行重试，每个请求由 `ApiClient` 重新读取当前 token；
 *   成功项删除，失败项 `retryCount + 1` 并记录 `lastError`。
 */
class PendingUploadQueue(
    @Suppress("unused") // 保留 Context 以匹配 DI 签名（AppContainer 已声明）；目录统一由 CacheStore 管理
    private val context: Context,
    private val cacheStore: CacheStore,
) {

    /** 一条待补评分录音（`file` = 队列目录 + [fileName]）。 */
    data class PendingUpload(
        val id: String,
        val sentenceId: String,
        val referenceText: String,
        val fileName: String,
        val durationMs: Int,
        val mode: String,
        val blindTestId: String?,
        val createdAt: Long,
        val retryCount: Int,
        val lastError: String?,
    ) {
        /** 录音文件（由 [PendingUploadQueue] 在返回列表前把队列目录写入 companion）。 */
        val file: File get() = File(queueDirectory, fileName)

        companion object {
            /** 队列目录（同一进程只有一个队列实例，由队列在构造/读取时绑定）。 */
            @Volatile
            internal var queueDirectory: File = File(".")
        }
    }

    /** [retryAll] 的汇总（页面据此提示「成功 N 条 / 仍失败 M 条」）。 */
    data class RetrySummary(
        val attempted: Int,
        val succeeded: Int,
        val failed: Int,
        val lastError: String?,
    )

    private val lock = Any()

    // ------------------------------------------------------------------ 入队 / 查询

    /**
     * 把 [audioFile] **拷贝**进队列目录并追加索引。
     *
     * @return false = 落盘失败（原文件缺失/为空、拷贝失败、写索引失败），页面提示但不阻塞主流程。
     */
    fun enqueue(
        audioFile: File,
        sentenceId: String,
        referenceText: String,
        durationMs: Int,
        mode: String = "scripted",
        blindTestId: String? = null,
    ): Boolean {
        if (!audioFile.isFile || audioFile.length() <= 0L) return false
        return synchronized(lock) {
            runCatching {
                val dir = cacheStore.pendingUploadsDir()
                PendingUpload.queueDirectory = dir
                val id = UUID.randomUUID().toString()
                val dest = File(dir, "pending_${id.replace("-", "")}.m4a")
                audioFile.copyTo(dest, overwrite = true)
                if (!dest.isFile || dest.length() <= 0L) {
                    dest.delete()
                    return@runCatching false
                }
                val items = loadItemsLocked().toMutableList()
                items.add(
                    QueueItemDto(
                        id = id,
                        sentenceId = sentenceId,
                        referenceText = referenceText,
                        fileName = dest.name,
                        durationMs = durationMs.coerceAtLeast(0),
                        mode = mode.ifBlank { MODE_SCRIPTED },
                        blindTestId = blindTestId?.takeIf { it.isNotBlank() },
                        createdAt = System.currentTimeMillis(),
                        retryCount = 0,
                        lastError = null,
                    )
                )
                saveItemsLocked(items)
                true
            }.getOrDefault(false)
        }
    }

    /** 全部待补评分（按入队时间升序 = 先录的先重试）。 */
    fun list(): List<PendingUpload> = synchronized(lock) {
        val dir = cacheStore.pendingUploadsDir()
        PendingUpload.queueDirectory = dir
        loadItemsLocked()
            .sortedBy { it.createdAt }
            .map { it.toPendingUpload() }
    }

    /** 待补评分条数（首页横幅/入口角标用；不读音频内容）。 */
    fun count(): Int = synchronized(lock) { loadItemsLocked().size }

    /** 删除单条（索引 + 录音文件）。 */
    fun remove(id: String) {
        if (id.isBlank()) return
        synchronized(lock) {
            val items = loadItemsLocked().toMutableList()
            val target = items.firstOrNull { it.id == id } ?: return
            items.removeAll { it.id == id }
            saveItemsLocked(items)
            runCatching { File(cacheStore.pendingUploadsDir(), target.fileName).delete() }
        }
    }

    /** 清空队列（索引 + 目录内全部文件）。 */
    fun clear() {
        synchronized(lock) {
            val dir = cacheStore.pendingUploadsDir()
            PendingUpload.queueDirectory = dir
            runCatching { FileUtil.removeDir(dir) }
            runCatching { FileUtil.ensureDir(dir) }
        }
    }

    // ------------------------------------------------------------------ 重试

    /**
     * 串行重试全部录音（`POST /attempts`）。
     *
     * - 每条重试前由 `ApiClient` 重新读取当前 access token（不会用入队时的旧 token）；
     * - 成功 → 删除索引条目与录音文件；失败 → `retryCount + 1`、记录 `lastError`，保留待下次；
     * - 一条失败不阻塞后续条目；汇总里 `attempted` = 本次尝试条数。
     *
     * 说明：`RetrySummary` 按契约只有四个字段，**不含 usage**；页面重试成功后可自行
     * `session.updateUsage(...)` / 拉 `/auth/me` 刷新剩余时长。
     */
    suspend fun retryAll(practice: PracticeService): RetrySummary {
        // 索引/录音都是磁盘 IO：统一放到 Dispatchers.IO，避免调用方在 viewModelScope(主线程) 直接跑
        val pending = withContext(Dispatchers.IO) { list() }
        if (pending.isEmpty()) {
            return RetrySummary(attempted = 0, succeeded = 0, failed = 0, lastError = null)
        }
        var succeeded = 0
        var failed = 0
        var lastError: String? = null
        for (item in pending) {
            try {
                val bytes = withContext(Dispatchers.IO) {
                    if (item.file.isFile) item.file.readBytes() else ByteArray(0)
                }
                if (bytes.isEmpty()) {
                    throw ApiError.local(ApiErrorCode.RECORD_FAILED, "录音文件不存在或为空")
                }
                practice.evaluate(
                    audio = bytes,
                    sentenceId = item.sentenceId,
                    referenceText = item.referenceText,
                    durationMs = item.durationMs,
                    blindTestId = item.blindTestId,
                    mode = item.mode,
                )
                withContext(Dispatchers.IO) { remove(item.id) }
                succeeded++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                failed++
                val message = retryErrorMessage(e)
                lastError = message
                withContext(Dispatchers.IO) { markFailed(item.id, message) }
            }
        }
        return RetrySummary(
            attempted = pending.size,
            succeeded = succeeded,
            failed = failed,
            lastError = lastError,
        )
    }

    // ------------------------------------------------------------------ 索引读写（调用方已持锁）

    /** 读索引：缺失=空；损坏=删掉并返回空（自愈）；无录音的条目/孤儿文件顺手清理。 */
    private fun loadItemsLocked(): List<QueueItemDto> {
        val dir = cacheStore.pendingUploadsDir()
        val index = indexFile(dir)
        if (!index.isFile || index.length() <= 0L) return emptyList()
        val text = runCatching { index.readText() }.getOrNull()
        val dto = text?.let {
            runCatching { EcJson.decodeFromString<QueueIndexDto>(it) }.getOrNull()
        }
        if (dto == null) {
            // 索引损坏：丢弃坏索引（音频文件保留在目录里，下次 enqueue 不会复用它们，但不会阻塞功能）
            runCatching { index.delete() }
            return emptyList()
        }
        val kept = dto.items.filter { item ->
            item.id.isNotBlank() && item.fileName.isNotBlank() &&
                File(dir, item.fileName).let { it.isFile && it.length() > 0L }
        }
        // 孤儿文件清理（索引里没引用的录音）
        val referenced = kept.map { it.fileName }.toSet()
        runCatching {
            dir.listFiles()
                ?.filter { it.isFile && it.name != INDEX_NAME && it.name !in referenced }
                ?.forEach { it.delete() }
        }
        return kept
    }

    private fun saveItemsLocked(items: List<QueueItemDto>) {
        val dir = cacheStore.pendingUploadsDir()
        val json = EcJson.encodeToString(QueueIndexDto(items = items))
        FileUtil.writeBytesAtomic(indexFile(dir), json.toByteArray(Charsets.UTF_8))
    }

    private fun markFailed(id: String, message: String?) {
        synchronized(lock) {
            val items = loadItemsLocked().toMutableList()
            val index = items.indexOfFirst { it.id == id }
            if (index < 0) return
            val old = items[index]
            items[index] = old.copy(retryCount = old.retryCount + 1, lastError = message)
            runCatching { saveItemsLocked(items) }
        }
    }

    private fun indexFile(dir: File): File = File(dir, INDEX_NAME)

    private fun QueueItemDto.toPendingUpload(): PendingUpload = PendingUpload(
        id = id,
        sentenceId = sentenceId,
        referenceText = referenceText,
        fileName = fileName,
        durationMs = durationMs,
        mode = mode,
        blindTestId = blindTestId,
        createdAt = createdAt,
        retryCount = retryCount,
        lastError = lastError,
    )

    /** 错误 → 可读文案（`ApiError.detail` 已是服务端中文，优先用）。 */
    private fun retryErrorMessage(e: Throwable): String {
        if (e is ApiError) {
            return e.detail.ifEmpty { e.message ?: "重试失败" }
        }
        return e.message?.takeIf { it.isNotBlank() } ?: "重试失败"
    }

    companion object {
        private const val INDEX_NAME = "queue.json"
        private const val MODE_SCRIPTED = "scripted"
    }
}

// ---------------------------------------------------------------------------
// queue.json 的序列化形状（与对外 [PendingUploadQueue.PendingUpload] 解耦：
// 索引里只存 fileName，绝对路径在读取时用队列目录拼）
// ---------------------------------------------------------------------------

@Serializable
private data class QueueIndexDto(
    val items: List<QueueItemDto> = emptyList(),
)

@Serializable
private data class QueueItemDto(
    val id: String = "",
    val sentenceId: String = "",
    val referenceText: String = "",
    val fileName: String = "",
    val durationMs: Int = 0,
    val mode: String = "scripted",
    val blindTestId: String? = null,
    val createdAt: Long = 0L,
    val retryCount: Int = 0,
    val lastError: String? = null,
)

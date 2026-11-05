package top.dreamsearch.englishcoach.core.storage

import android.content.Context
import top.dreamsearch.englishcoach.core.util.FileUtil
import java.io.File

/**
 * 目录与缓存策略（对应 hos `CacheService`，docs/architecture.md §7、docs/audio.md §7；
 * ROUND2_CONTRACT §1.4 增补 LRU / 待补评分队列 / 最近结果缓存）。
 *
 * - `filesDir/recordings/`        当前录音（上传成功后按策略清理）
 * - `cacheDir/tts/`               TTS 示范音（按文本哈希缓存，**200MB LRU**）
 * - `cacheDir/audio/`             回放缓存（录音回放 / 整段对话 / 故事朗读，**300MB LRU**）
 * - `cacheDir/images/`            插画 / 头像 / 预置形象图
 * - `cacheDir/json/`              列表与详情缓存（语料、故事集、健康状态）
 * - `filesDir/pending_uploads/`   离线「待补评分」录音队列（queue.json + 录音，**登出清空**）
 * - `cacheDir/recent_results/`    最近评测结果 JSON（最多 50 条 LRU，离线可看）
 *
 * 淘汰策略：TTS/回放按 `lastModified` 做 LRU；启动时（[cleanupOnBoot]）触发一次，
 * 失败忽略、不阻塞启动。
 */
class CacheStore(private val context: Context) {

    fun recordingsDir(): File = File(context.filesDir, "recordings").also { FileUtil.ensureDir(it) }

    fun ttsDir(): File = File(context.cacheDir, "tts").also { FileUtil.ensureDir(it) }

    fun audioDir(): File = File(context.cacheDir, "audio").also { FileUtil.ensureDir(it) }

    fun imagesDir(): File = File(context.cacheDir, "images").also { FileUtil.ensureDir(it) }

    fun jsonDir(): File = File(context.cacheDir, "json").also { FileUtil.ensureDir(it) }

    /**
     * 离线「待补评分」队列目录（ROUND2_CONTRACT §1.3）：`queue.json` + 录音文件。
     *
     * 放 `filesDir` 而不是 `cacheDir`：系统「清理缓存」不应该把用户还没补评分的录音删掉。
     */
    fun pendingUploadsDir(): File =
        File(context.filesDir, "pending_uploads").also { FileUtil.ensureDir(it) }

    /** 最近评测结果缓存目录（离线查看，最多 50 条 LRU）。 */
    fun recentResultsDir(): File =
        File(context.cacheDir, "recent_results").also { FileUtil.ensureDir(it) }

    fun ensureAll() {
        recordingsDir(); ttsDir(); audioDir(); imagesDir(); jsonDir()
        pendingUploadsDir(); recentResultsDir()
    }

    fun cleanupOnBoot() {
        runCatching {
            ensureAll()
            FileUtil.removePartFiles(ttsDir())
            FileUtil.removePartFiles(audioDir())
            FileUtil.removePartFiles(imagesDir())
            // LRU 淘汰（异常忽略，不阻塞启动）
            trimTtsCache()
            trimAudioCache()
        }
    }

    fun newRecordingFile(prefix: String = "rec"): File =
        File(recordingsDir(), "${prefix}_${System.currentTimeMillis()}.m4a")

    fun ttsFile(key: String): File = File(ttsDir(), FileUtil.safeName(key) + ".wav")

    fun audioFile(key: String, ext: String = "wav"): File =
        File(audioDir(), FileUtil.safeName(key) + "." + ext)

    fun imageFile(key: String, ext: String = "jpg"): File =
        File(imagesDir(), FileUtil.safeName(key) + "." + ext)

    /** 接口响应的轻量缓存（列表/详情/健康状态）。 */
    fun readJson(key: String): String? {
        val file = File(jsonDir(), FileUtil.safeName(key) + ".json")
        return FileUtil.readBytes(file)?.toString(Charsets.UTF_8)
    }

    fun writeJson(key: String, value: String) {
        runCatching { FileUtil.writeBytesAtomic(File(jsonDir(), FileUtil.safeName(key) + ".json"), value.toByteArray()) }
    }

    // ------------------------------------------------------------------ 缓存 LRU（ROUND2 §1.4）

    /** TTS 缓存 LRU：按 `lastModified` 淘汰到 [maxBytes] 以内（默认 200MB）。 */
    fun trimTtsCache(maxBytes: Long = 200L * 1024 * 1024) {
        trimLru(ttsDir(), maxBytes)
    }

    /** 回放缓存 LRU：默认 300MB。 */
    fun trimAudioCache(maxBytes: Long = 300L * 1024 * 1024) {
        trimLru(audioDir(), maxBytes)
    }

    // ------------------------------------------------------------------ 最近评测结果（离线查看）

    /** 读最近评测结果；命中时刷新 LRU 时间戳。 */
    fun readRecentResult(key: String): String? {
        val file = File(recentResultsDir(), FileUtil.safeName(key) + ".json")
        val text = FileUtil.readBytes(file)?.toString(Charsets.UTF_8)
        if (text != null) runCatching { file.setLastModified(System.currentTimeMillis()) }
        return text
    }

    /** 写最近评测结果（最多保留 [MAX_RECENT_RESULTS] 条，最旧先淘汰）。 */
    fun writeRecentResult(key: String, json: String) {
        runCatching {
            val dir = recentResultsDir()
            val file = File(dir, FileUtil.safeName(key) + ".json")
            FileUtil.writeBytesAtomic(file, json.toByteArray(Charsets.UTF_8))
            trimRecentResultsLocked(dir, MAX_RECENT_RESULTS)
        }
    }

    /** 清空最近评测结果（登出 / 手动清理）。 */
    fun clearRecentResults() {
        runCatching {
            FileUtil.removeDir(recentResultsDir())
            FileUtil.ensureDir(recentResultsDir())
        }
    }

    /** 登出 / 清缓存：删除 TTS 与回放音频（不动 baseUrl 等配置）。 */
    fun clearAudioCache() {
        FileUtil.removeDir(ttsDir())
        FileUtil.removeDir(audioDir())
        FileUtil.removeDir(imagesDir())
        ensureAll()
    }

    /**
     * 登出：额外清掉录音、**待补评分队列**、最近结果与 JSON 缓存（避免下一个账号拿到上一个账号的数据）。
     */
    fun clearAll() {
        clearAudioCache()
        FileUtil.removeDir(recordingsDir())
        FileUtil.removeDir(pendingUploadsDir())
        FileUtil.removeDir(jsonDir())
        clearRecentResults()
        ensureAll()
    }

    // ------------------------------------------------------------------ 内部实现

    /**
     * 按 `lastModified` 从旧到新删除，直到目录总大小 ≤ [maxBytes]。
     * 目录不存在/不可写时静默返回（缓存淘汰永远不能把启动流程打挂）。
     */
    private fun trimLru(dir: File, maxBytes: Long) {
        if (maxBytes <= 0L) return
        runCatching {
            if (!dir.isDirectory) return
            val files = dir.listFiles()?.filter { it.isFile } ?: return
            var total = files.sumOf { it.length() }
            if (total <= maxBytes) return
            files
                .sortedBy { it.lastModified() }
                .forEach { file ->
                    if (total <= maxBytes) return@forEach
                    val size = file.length()
                    if (file.delete()) total -= size
                }
        }
    }

    /** 最近结果只保留 [max] 条（按 `lastModified` 最旧先删）。 */
    private fun trimRecentResultsLocked(dir: File, max: Int) {
        if (max <= 0) return
        runCatching {
            val files = dir.listFiles()?.filter { it.isFile } ?: return
            if (files.size <= max) return
            files
                .sortedBy { it.lastModified() }
                .take(files.size - max)
                .forEach { it.delete() }
        }
    }

    companion object {
        /** 最近评测结果最多保留条数（ROUND2_CONTRACT §1.4）。 */
        const val MAX_RECENT_RESULTS: Int = 50
    }
}

package top.dreamsearch.englishcoach.core.storage

import android.content.Context
import top.dreamsearch.englishcoach.core.util.FileUtil
import java.io.File

/**
 * 目录与缓存策略（对应 hos `CacheService`，docs/architecture.md §7、docs/audio.md §7）。
 *
 * - `filesDir/recordings/`  当前录音（上传成功后按策略清理）
 * - `cacheDir/tts/`         TTS 示范音（按文本哈希缓存）
 * - `cacheDir/audio/`       回放缓存（录音回放 / 整段对话 / 故事朗读）
 * - `cacheDir/images/`      插画 / 头像 / 预置形象图
 * - `cacheDir/json/`        列表与详情缓存（语料、故事集、健康状态）
 *
 * M1 不做 LRU 与过期淘汰：只做「登出清空 + 启动清理 .part」。
 */
class CacheStore(private val context: Context) {

    fun recordingsDir(): File = File(context.filesDir, "recordings").also { FileUtil.ensureDir(it) }

    fun ttsDir(): File = File(context.cacheDir, "tts").also { FileUtil.ensureDir(it) }

    fun audioDir(): File = File(context.cacheDir, "audio").also { FileUtil.ensureDir(it) }

    fun imagesDir(): File = File(context.cacheDir, "images").also { FileUtil.ensureDir(it) }

    fun jsonDir(): File = File(context.cacheDir, "json").also { FileUtil.ensureDir(it) }

    fun ensureAll() {
        recordingsDir(); ttsDir(); audioDir(); imagesDir(); jsonDir()
    }

    fun cleanupOnBoot() {
        runCatching {
            ensureAll()
            FileUtil.removePartFiles(ttsDir())
            FileUtil.removePartFiles(audioDir())
            FileUtil.removePartFiles(imagesDir())
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

    /** 登出 / 清缓存：删除 TTS 与回放音频（不动 baseUrl 等配置）。 */
    fun clearAudioCache() {
        FileUtil.removeDir(ttsDir())
        FileUtil.removeDir(audioDir())
        FileUtil.removeDir(imagesDir())
        ensureAll()
    }

    /** 登出：额外清掉录音、待上传目录与 JSON 缓存。 */
    fun clearAll() {
        clearAudioCache()
        FileUtil.removeDir(recordingsDir())
        FileUtil.removeDir(jsonDir())
        ensureAll()
    }
}

package top.dreamsearch.englishcoach.core.util

import java.io.File

/** 文件工具（对应 hos `FileUtil`）：原子写、目录清理。 */
object FileUtil {

    fun ensureDir(dir: File): File {
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    /** 写 `.part` 再 rename，避免半截文件被当成有效音频播放。 */
    fun writeBytesAtomic(dest: File, bytes: ByteArray) {
        dest.parentFile?.let { ensureDir(it) }
        val tmp = File(dest.parentFile, dest.name + ".part")
        tmp.writeBytes(bytes)
        if (dest.exists()) dest.delete()
        if (!tmp.renameTo(dest)) {
            // 某些文件系统 rename 会失败，退化为复制
            tmp.copyTo(dest, overwrite = true)
            tmp.delete()
        }
    }

    fun readBytes(file: File): ByteArray? =
        if (file.exists() && file.length() > 0) runCatching { file.readBytes() }.getOrNull() else null

    fun removeDir(dir: File) {
        if (!dir.exists()) return
        runCatching { dir.deleteRecursively() }
    }

    fun removePartFiles(dir: File) {
        if (!dir.exists()) return
        dir.listFiles()?.filter { it.isFile && it.name.endsWith(".part") }?.forEach { it.delete() }
    }

    /** 缓存过半时清空（非 LRU，与 hos M0 策略一致）。 */
    fun cacheSizeBytes(dir: File): Long {
        if (!dir.exists()) return 0L
        return dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    fun mimeForAudio(fileName: String): String = when {
        fileName.endsWith(".wav", true) -> "audio/wav"
        fileName.endsWith(".mp3", true) -> "audio/mpeg"
        fileName.endsWith(".m4a", true) || fileName.endsWith(".mp4", true) -> "audio/mp4"
        fileName.endsWith(".webm", true) -> "audio/webm"
        fileName.endsWith(".ogg", true) -> "audio/ogg"
        else -> "application/octet-stream"
    }

    fun mimeForImage(fileName: String): String = when {
        fileName.endsWith(".png", true) -> "image/png"
        fileName.endsWith(".webp", true) -> "image/webp"
        fileName.endsWith(".jpg", true) || fileName.endsWith(".jpeg", true) -> "image/jpeg"
        else -> "application/octet-stream"
    }

    /** 把任意字符串变成安全文件名（含 sha1，避免碰撞与非法字符）。 */
    fun safeName(raw: String, maxLen: Int = 40): String {
        val cleaned = raw.map { ch ->
            if (ch.isLetterOrDigit() || ch == '-' || ch == '_') ch else '_'
        }.joinToString("")
        val digest = java.security.MessageDigest.getInstance("SHA-1")
            .digest(raw.toByteArray())
            .joinToString("") { "%02x".format(it) }
            .take(12)
        return cleaned.take(maxLen) + "_" + digest
    }
}

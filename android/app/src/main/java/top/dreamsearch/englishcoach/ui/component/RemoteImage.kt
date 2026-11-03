package top.dreamsearch.englishcoach.ui.component

import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.util.FileUtil
import top.dreamsearch.englishcoach.ui.design.EcColor
import java.net.HttpURLConnection
import java.net.URL

/**
 * 远程图片（签名按 android/CONTRACT.md §4）。
 *
 * 两种来源：
 * - `withAuth = true`：需要 Authorization 的接口图（如 `/materials/:id/image`），
 *   走 `AppGraph.container.api.getBytes(path)`（path 不含 `/api`，函数内部会容错去掉误传的前缀）；
 * - `withAuth = false`：站内静态图（如 `/avatars/presets/x.png`），直接拼 `AppConfig.baseUrl`，不带鉴权。
 *
 * 缓存：内存 LRU（约 24MB）+ `cacheDir/images` 磁盘缓存（key = 来源+path 的哈希），
 * 网络或解码失败时渲染 `fallback()`（页面给占位图/占位文案），不抛异常。
 */
@Composable
fun RemoteImage(
    path: String,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    withAuth: Boolean = false,
    fallback: @Composable () -> Unit = {},
) {
    val trimmed = path.trim()
    if (trimmed.isEmpty()) {
        fallback()
        return
    }

    var image by remember(trimmed, withAuth) { mutableStateOf<ImageBitmap?>(null) }
    var failed by remember(trimmed, withAuth) { mutableStateOf(false) }

    LaunchedEffect(trimmed, withAuth) {
        image = null
        failed = false
        val loaded = runCatching { loadImage(trimmed, withAuth) }.getOrNull()
        if (loaded != null) {
            image = loaded
        } else {
            failed = true
        }
    }

    val current = image
    when {
        current != null -> Image(
            bitmap = current,
            contentDescription = contentDescription,
            modifier = modifier,
            contentScale = ContentScale.Fit,
        )

        failed -> fallback()

        else -> Box(
            modifier = modifier.background(EcColor.surfaceAlt),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = EcColor.primary,
                strokeWidth = 2.dp,
            )
        }
    }
}

/** 读内存缓存 → 读磁盘缓存 → 走网络；失败返回 null（不抛）。 */
private suspend fun loadImage(path: String, withAuth: Boolean): ImageBitmap? = withContext(Dispatchers.IO) {
    val key = (if (withAuth) "api:" else "url:") + path
    ImageMemoryCache.get(key)?.let { return@withContext it }

    val cacheFile = runCatching {
        AppGraph.container.cache.imageFile(FileUtil.safeName(key), extensionOf(path))
    }.getOrNull()

    val cachedBytes: ByteArray? = cacheFile?.let { FileUtil.readBytes(it) }
    val bytes: ByteArray = if (cachedBytes != null) {
        cachedBytes
    } else {
        val fetched = fetchBytes(path, withAuth)
        if (fetched.isNotEmpty() && cacheFile != null) {
            runCatching { FileUtil.writeBytesAtomic(cacheFile, fetched) }
        }
        fetched
    }
    if (bytes.isEmpty()) return@withContext null

    val bitmap = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
        ?: return@withContext null
    val decoded = bitmap.asImageBitmap()
    ImageMemoryCache.put(key, decoded)
    decoded
}

/** 取图片字节：鉴权图走统一 ApiClient；静态图走公开 URL。 */
private suspend fun fetchBytes(path: String, withAuth: Boolean): ByteArray {
    if (withAuth) {
        val apiPath = path.removePrefix("/api")
        val raw = AppGraph.container.api.getBytes(path = apiPath)
        AppGraph.container.api.requireOk(raw)
        return raw.bytes ?: ByteArray(0)
    }
    val absoluteUrl = if (path.startsWith("http://", true) || path.startsWith("https://", true)) {
        path
    } else {
        AppGraph.container.config.baseUrl + path
    }
    return withContext(Dispatchers.IO) {
        val connection = URL(absoluteUrl).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = true
            connection.requestMethod = "GET"
            val code = connection.responseCode
            if (code !in 200..299) error("图片请求失败 HTTP $code")
            connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }
}

private fun extensionOf(path: String): String = when {
    path.endsWith(".png", true) -> "png"
    path.endsWith(".webp", true) -> "webp"
    else -> "jpg"
}

/** 图片内存 LRU（上限约 24MB，按像素估算大小）。 */
private object ImageMemoryCache {
    private const val MAX_BYTES = 24 * 1024 * 1024

    private val cache = object : LruCache<String, ImageBitmap>(MAX_BYTES) {
        override fun sizeOf(key: String, value: ImageBitmap): Int = value.width * value.height * 4
    }

    fun get(key: String): ImageBitmap? = cache.get(key)

    fun put(key: String, value: ImageBitmap) {
        cache.put(key, value)
    }
}

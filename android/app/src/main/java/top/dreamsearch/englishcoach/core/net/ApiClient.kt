package top.dreamsearch.englishcoach.core.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import top.dreamsearch.englishcoach.core.config.AppConfig
import top.dreamsearch.englishcoach.core.session.TokenStore
import top.dreamsearch.englishcoach.core.util.FileUtil
import top.dreamsearch.englishcoach.core.util.Logx
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit

/** 一次请求的描述（对应 hos `ApiRequest`）。path 不含 `/api` 前缀。 */
class ApiRequest(
    val method: String,
    val path: String,
    val query: Map<String, String>? = null,
    /** 已序列化的 JSON 字符串 */
    val jsonBody: String? = null,
    val form: List<FormPart>? = null,
    /** 是否注入 Bearer；/auth/token、/auth/refresh、/auth/revoke、/health 为 false */
    val auth: Boolean = true,
    /** 是否允许 401 → 单飞刷新 → 重放一次 */
    val retryOn401: Boolean = true,
    val timeoutMs: Long = DEFAULT_TIMEOUT_MS,
    /** 响应按二进制读取（TTS 音频、图片下载） */
    val wantBytes: Boolean = false,
) {
    companion object {
        const val DEFAULT_TIMEOUT_MS = 15_000L
        /** 同步评测最长约 100s，客户端给 120s */
        const val EVAL_TIMEOUT_MS = 120_000L
        /** TTS / ASR / 改写 / 插画 等长耗时接口 */
        const val LONG_TIMEOUT_MS = 90_000L
        const val DOWNLOAD_TIMEOUT_MS = 120_000L
    }
}

/** 原始响应：JSON 解析交给 service（保持网络层与契约解耦）。 */
class ApiRaw(
    val status: Int,
    val text: String,
    val bytes: ByteArray?,
)

/** multipart 的一段：文本字段或文件字段。 */
class FormPart private constructor(
    val name: String,
    val text: String?,
    val fileName: String?,
    val contentType: String?,
    val bytes: ByteArray?,
) {
    companion object {
        fun text(name: String, value: String): FormPart =
            FormPart(name, value, null, null, null)

        fun file(
            name: String,
            fileName: String,
            bytes: ByteArray,
            contentType: String? = null,
        ): FormPart = FormPart(name, null, fileName, contentType, bytes)
    }
}

/** `/auth/refresh` 最小响应（网络层不依赖 DTO 包）。 */
@Serializable
private data class RefreshResponse(
    @SerialName("access_token") val accessToken: String = "",
    @SerialName("refresh_token") val refreshToken: String = "",
    @SerialName("expires_in") val expiresIn: Int = 3600,
    @SerialName("refresh_expires_in") val refreshExpiresIn: Int = 0,
)

/**
 * 唯一 HTTP 出口（对应 hos `ApiClient`，docs/architecture.md §5）。
 *
 * 行为：
 * - Bearer 注入 + 401 单飞刷新 + 每请求最多重放一次；
 * - refresh 被拒（400/401）→ 清 token 抛 unauthorized；refresh 网络失败/5xx → **不清 token**；
 * - `/auth/...`、`/health` 不参与 401 重试（auth=false）。
 */
class ApiClient(
    private val config: AppConfig,
    private val tokenStore: TokenStore,
) {
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .readTimeout(ApiRequest.DEFAULT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .writeTimeout(ApiRequest.LONG_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .retryOnConnectionFailure(false)
        .build()

    private val refreshMutex = Mutex()

    // ------------------------------------------------------------------ 便捷入口

    suspend fun getJson(
        path: String,
        query: Map<String, String>? = null,
        timeoutMs: Long = ApiRequest.DEFAULT_TIMEOUT_MS,
    ): ApiRaw = request(ApiRequest("GET", path, query = query, timeoutMs = timeoutMs))

    suspend fun postJson(
        path: String,
        body: String,
        auth: Boolean = true,
        timeoutMs: Long = ApiRequest.DEFAULT_TIMEOUT_MS,
    ): ApiRaw = request(
        ApiRequest("POST", path, jsonBody = body, auth = auth, retryOn401 = auth, timeoutMs = timeoutMs)
    )

    suspend fun patchJson(
        path: String,
        body: String,
        timeoutMs: Long = ApiRequest.DEFAULT_TIMEOUT_MS,
    ): ApiRaw = request(ApiRequest("PATCH", path, jsonBody = body, timeoutMs = timeoutMs))

    suspend fun deleteJson(
        path: String,
        timeoutMs: Long = ApiRequest.DEFAULT_TIMEOUT_MS,
    ): ApiRaw = request(ApiRequest("DELETE", path, timeoutMs = timeoutMs))

    /** POST JSON，响应按二进制返回（TTS）。 */
    suspend fun postJsonForBytes(
        path: String,
        body: String,
        timeoutMs: Long = ApiRequest.LONG_TIMEOUT_MS,
    ): ApiRaw = request(
        ApiRequest("POST", path, jsonBody = body, timeoutMs = timeoutMs, wantBytes = true)
    )

    suspend fun postMultipart(
        path: String,
        query: Map<String, String>? = null,
        parts: List<FormPart>,
        timeoutMs: Long = ApiRequest.LONG_TIMEOUT_MS,
    ): ApiRaw = request(
        ApiRequest("POST", path, query = query, form = parts, timeoutMs = timeoutMs)
    )

    /** GET 二进制（录音回放 / 头像图片等）。 */
    suspend fun getBytes(
        path: String,
        query: Map<String, String>? = null,
        timeoutMs: Long = ApiRequest.DOWNLOAD_TIMEOUT_MS,
    ): ApiRaw = request(
        ApiRequest("GET", path, query = query, timeoutMs = timeoutMs, wantBytes = true)
    )

    /** 下载到本地文件（带 Authorization，如故事插画 `/materials/:id/image`）；失败不覆盖已有文件。 */
    suspend fun download(
        path: String,
        destFile: File,
        query: Map<String, String>? = null,
        timeoutMs: Long = ApiRequest.DOWNLOAD_TIMEOUT_MS,
    ) {
        val raw = getBytes(path = path, query = query, timeoutMs = timeoutMs)
        requireOk(raw)
        val bytes = raw.bytes ?: throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "下载内容为空")
        FileUtil.writeBytesAtomic(destFile, bytes)
    }

    // ------------------------------------------------------------------ 核心

    /**
     * 发起请求（含 401 单飞刷新与一次重放）。
     * 重放仍 401 → 清 token 并抛 unauthorized；VM 经 `SessionStore.toUiError` 回登录页。
     */
    suspend fun request(req: ApiRequest): ApiRaw = withContext(Dispatchers.IO) {
        val first = execute(req)
        if (first.status != 401 || !req.auth || !req.retryOn401) {
            return@withContext first
        }
        val staleToken = tokenStore.accessToken()
        refreshAccessToken(staleToken)
        val second = execute(req)
        if (second.status == 401) {
            tokenStore.clear()
            throw ApiError(ApiErrorCode.UNAUTHORIZED, 401, "登录已过期，请重新登录")
        }
        second
    }

    fun requireOk(raw: ApiRaw) {
        if (raw.status in 200..299) return
        throw errorOf(raw)
    }

    /** 把非 2xx 响应转成 ApiError（优先用服务端 `{error:{code,message}}`）。 */
    fun errorOf(raw: ApiRaw): ApiError {
        val text = raw.text.ifEmpty { raw.bytes?.toString(Charsets.UTF_8) ?: "" }
        var code = ApiErrorCode.forStatus(raw.status)
        var message = ""
        if (text.isNotEmpty()) {
            runCatching {
                val err = EcJson.parseToJsonElement(text).jsonObject["error"]?.jsonObject
                err?.get("code")?.jsonPrimitive?.contentOrNull
                    ?.takeIf { it.isNotEmpty() }
                    ?.let { code = it }
                err?.get("message")?.jsonPrimitive?.contentOrNull?.let { message = it }
            }
        }
        return ApiError(code, raw.status, message)
    }

    // ------------------------------------------------------------------ 内部实现

    /** 单飞刷新：并发 401 只发一次 `/auth/refresh`，其余等锁后复用新 token。 */
    private suspend fun refreshAccessToken(staleAccessToken: String) {
        refreshMutex.withLock {
            // 等待期间别的请求已经刷新过（access token 已变），直接复用
            val current = tokenStore.accessToken()
            if (current.isNotEmpty() && current != staleAccessToken) return
            val refreshToken = tokenStore.refreshToken()
            if (refreshToken.isEmpty()) {
                tokenStore.clear()
                throw ApiError(ApiErrorCode.UNAUTHORIZED, 401, "登录已失效，请重新登录")
            }
            val escaped = refreshToken.replace("\\", "\\\\").replace("\"", "\\\"")
            val raw = execute(
                ApiRequest(
                    method = "POST",
                    path = "/auth/refresh",
                    jsonBody = "{\"refresh_token\":\"$escaped\"}",
                    auth = false,
                    retryOn401 = false,
                    timeoutMs = 15_000,
                )
            )
            if (raw.status == 400 || raw.status == 401) {
                tokenStore.clear()
                throw ApiError(ApiErrorCode.UNAUTHORIZED, raw.status, "登录已过期，请重新登录")
            }
            if (raw.status != 200) {
                // 网络/5xx：不清 token，让用户重试（避免一次断网就登出）
                throw errorOf(raw)
            }
            val dto = runCatching { EcJson.decodeFromString<RefreshResponse>(raw.text) }.getOrNull()
            if (dto == null || dto.accessToken.isEmpty() || dto.refreshToken.isEmpty()) {
                throw ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, "服务器返回的登录信息不完整")
            }
            tokenStore.save(
                accessToken = dto.accessToken,
                refreshToken = dto.refreshToken,
                expiresInSec = dto.expiresIn,
                refreshExpiresInSec = dto.refreshExpiresIn,
            )
        }
    }

    private fun execute(req: ApiRequest): ApiRaw {
        val url = buildUrl(req.path, req.query)
        val builder = Request.Builder()
            .url(url)
            .header("Accept", if (req.wantBytes) "*/*" else "application/json")
            .header("User-Agent", USER_AGENT)
        if (req.auth) {
            val token = tokenStore.accessToken()
            if (token.isNotEmpty()) builder.header("Authorization", "Bearer $token")
        }
        val body: okhttp3.RequestBody? = when {
            req.jsonBody != null -> req.jsonBody.toRequestBody(JSON_MEDIA_TYPE)
            req.form != null -> buildMultipart(req.form)
            req.method in BODY_METHODS -> "".toRequestBody(JSON_MEDIA_TYPE)
            else -> null
        }
        val request = builder.method(req.method, body).build()
        // 每个请求按需覆盖读超时（连接池/dispatcher 复用，代价很小）
        val client = http.newBuilder()
            .readTimeout(req.timeoutMs, TimeUnit.MILLISECONDS)
            .build()
        val startedAt = System.currentTimeMillis()
        try {
            client.newCall(request).execute().use { response ->
                val status = response.code
                val raw = if (req.wantBytes) {
                    ApiRaw(status, "", response.body?.bytes() ?: ByteArray(0))
                } else {
                    ApiRaw(status, response.body?.string() ?: "", null)
                }
                Logx.d("Net", "${req.method} ${req.path} status=$status elapsed=${System.currentTimeMillis() - startedAt}ms")
                return raw
            }
        } catch (e: SocketTimeoutException) {
            throw ApiError(ApiErrorCode.TIMEOUT, 0, e.message ?: "请求超时")
        } catch (e: UnknownHostException) {
            throw ApiError(ApiErrorCode.NETWORK_UNREACHABLE, 0, e.message ?: "无法解析服务器地址")
        } catch (e: IOException) {
            throw ApiError(ApiErrorCode.NETWORK_UNREACHABLE, 0, e.message ?: "网络不可达")
        }
    }

    private fun buildMultipart(parts: List<FormPart>): MultipartBody {
        val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
        parts.forEach { part ->
            val bytes = part.bytes
            if (bytes != null) {
                val mediaType = part.contentType?.toMediaTypeOrNull() ?: DEFAULT_FILE_MEDIA_TYPE
                builder.addFormDataPart(
                    part.name,
                    part.fileName ?: part.name,
                    bytes.toRequestBody(mediaType),
                )
            } else {
                builder.addFormDataPart(part.name, part.text ?: "")
            }
        }
        return builder.build()
    }

    private fun buildUrl(path: String, query: Map<String, String>?): String {
        val base = config.baseUrl + "/api" + path
        if (query.isNullOrEmpty()) return base
        val qs = query.entries.joinToString("&") { (k, v) ->
            "${java.net.URLEncoder.encode(k, "UTF-8")}=${java.net.URLEncoder.encode(v, "UTF-8")}"
        }
        return "$base?$qs"
    }

    companion object {
        const val CONNECT_TIMEOUT_MS = 10_000L
        const val USER_AGENT = "EnglishCoach-Android/${AppConfig.APP_VERSION}"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaTypeOrNull()
        private val DEFAULT_FILE_MEDIA_TYPE = "application/octet-stream".toMediaTypeOrNull()
        private val BODY_METHODS = setOf("POST", "PATCH", "PUT")
    }
}

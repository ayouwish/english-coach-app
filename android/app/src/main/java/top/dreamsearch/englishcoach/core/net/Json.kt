package top.dreamsearch.englishcoach.core.net

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

/**
 * 全局唯一的 JSON 实例（对应 hos 各 Service 里的 JSON 解析约定）。
 *
 * - `ignoreUnknownKeys`：服务端新增字段不破坏客户端；
 * - `explicitNulls = false`：`@SerialName` 缺失字段回落到默认值，序列化时不输出 null；
 * - `coerceInputValues`：服务端偶尔返回 `""` / `0` 给可空枚举字段时降级为 null。
 */
val EcJson: Json = Json {
    ignoreUnknownKeys = true
    isLenient = true
    explicitNulls = false
    coerceInputValues = true
    encodeDefaults = true
    allowSpecialFloatingPointValues = true
}

/** 解析辅助：失败时抛 [ApiErrorCode.BAD_RESPONSE]，避免每个 service 写 try/catch。 */
inline fun <reified T> decodeBody(body: String, what: String): T = try {
    EcJson.decodeFromString<T>(body)
} catch (e: Exception) {
    throw ApiError(ApiErrorCode.BAD_RESPONSE, 0, "解析 $what 响应失败：${e.message ?: "格式异常"}")
}

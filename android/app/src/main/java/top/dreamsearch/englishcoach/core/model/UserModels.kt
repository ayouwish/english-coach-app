package top.dreamsearch.englishcoach.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 账号相关的**基础**模型（`/auth/me`、`/auth/token` 共用）。
 *
 * 事实来源：hos `core/net/Dtos.ets` 的 UserDto / UsageDto / TokenResponseDto / MeResponseDto，
 * 字段名与服务端保持一致（camelCase 的部分原样保留，其余用 @SerialName 映射）。
 *
 * 数据层（`core/service`、`core/net/dto`）**复用**这里的类型，不要重复定义。
 */
@Serializable
data class UserDto(
    val id: String = "",
    val email: String = "",
    val displayName: String = "",
    /** 'parent' | 'child' */
    val role: String = "child",
    /** 'child' | 'teen' | 'adult' */
    val ageBand: String = "adult",
    val cefrLevel: String = "A1",
    val avatar: String? = null,
    val birthYear: Int? = null,
    val avatarImagePath: String? = null,
    val avatarImageUrl: String? = null,
    val avatarStyle: String? = null,
    val autoIllustrate: Boolean? = null,
    /** girl | boy | woman | man | other | null */
    val gender: String? = null,
    val storySentences: Int? = null,
    val dailyLimitMinutes: Int = 20,
    val allowFreeChat: Boolean = true,
    val nativeLanguage: String? = null,
    val isChild: Boolean? = null,
)

@Serializable
data class UsageDto(
    val minutes: Int = 0,
    val limitMinutes: Int = 20,
    val remainingMinutes: Int = 0,
    val exceeded: Boolean = false,
    val attemptCount: Int = 0,
    val chatTurnCount: Int = 0,
)

@Serializable
data class MeResponseDto(
    val user: UserDto? = null,
    val usage: UsageDto? = null,
)

@Serializable
data class TokenResponseDto(
    @SerialName("access_token") val accessToken: String = "",
    @SerialName("refresh_token") val refreshToken: String = "",
    @SerialName("token_type") val tokenType: String = "Bearer",
    @SerialName("expires_in") val expiresIn: Int = 3600,
    @SerialName("refresh_expires_in") val refreshExpiresIn: Int = 0,
    val user: UserDto? = null,
    val usage: UsageDto? = null,
)

@Serializable
data class LoginBodyDto(
    val email: String,
    val password: String,
    @SerialName("user_agent") val userAgent: String? = null,
)

/** 登录结果：user 来自 `/auth/token`（并尽量用 `/auth/me` 校正），usage 可能为 null。 */
class LoginResult(
    val user: UserDto? = null,
    val usage: UsageDto? = null,
)

/** 错误信封 `{error:{code,message}}`（网络层解析失败时才用它兜底）。 */
@Serializable
data class ErrorBodyDto(
    val code: String = "",
    val message: String = "",
)

@Serializable
data class ErrorEnvelopeDto(
    val error: ErrorBodyDto? = null,
)

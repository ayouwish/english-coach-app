import { http } from '@kit.NetworkKit';
import { ApiClient, ApiRequest } from '../net/ApiClient';
import { ApiError, ApiErrorCode } from '../net/ApiError';
import { LoginBodyDto, MeResponseDto, RevokeBodyDto, TokenResponseDto, UsageDto, UserDto } from '../net/Dtos';
import { TokenSession } from '../net/TokenSession';

/** 登录结果：user 来自 `/auth/token`（并尽量用 `/auth/me` 校正），usage 可能为 null。 */
export class LoginResult {
  user: UserDto | null = null;
  usage: UsageDto | null = null;
}

/**
 * 认证服务：登录 / 恢复会话 / 退出。
 *
 * 流程（docs/architecture.md §9.1）：
 *   POST /auth/token（auth:false）→ 保存两个 token → GET /auth/me 补 usage
 * 说明：`/auth/token`、`/auth/refresh`（内部）、`/auth/revoke`、`/health` 都不参与 401 自动刷新。
 */
export class AuthService {
  private static readonly LOGIN_TIMEOUT_MS: number = 15000;
  private static readonly ME_TIMEOUT_MS: number = 15000;
  private static readonly REVOKE_TIMEOUT_MS: number = 10000;

  static async login(email: string, password: string): Promise<LoginResult> {
    const body: LoginBodyDto = { email: email.trim(), password: password };
    const raw = await ApiClient.postJson('/auth/token', JSON.stringify(body), false, AuthService.LOGIN_TIMEOUT_MS);
    if (raw.status !== 200) {
      throw ApiClient.errorOf(raw);
    }
    let dto: TokenResponseDto | null = null;
    try {
      dto = JSON.parse(raw.text) as TokenResponseDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '登录返回格式异常');
    }
    const accessToken = typeof dto.access_token === 'string' ? dto.access_token : '';
    const refreshToken = typeof dto.refresh_token === 'string' ? dto.refresh_token : '';
    if (accessToken.length === 0 || refreshToken.length === 0) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '登录返回缺少 token');
    }
    const expiresIn = typeof dto.expires_in === 'number' ? dto.expires_in : 3600;
    const refreshExpiresIn = typeof dto.refresh_expires_in === 'number' ? dto.refresh_expires_in : 0;
    await TokenSession.save(accessToken, refreshToken, expiresIn, refreshExpiresIn);

    const result = new LoginResult();
    if (dto.user !== undefined && dto.user !== null) {
      result.user = dto.user;
    }
    try {
      const me = await AuthService.me();
      if (me.user !== undefined && me.user !== null) {
        result.user = me.user;
      }
      if (me.usage !== undefined) {
        result.usage = me.usage;
      }
    } catch (err) {
      // token 已保存，usage 拉取失败不影响进入首页；但会话已失效时必须让登录失败
      const e = err as ApiError;
      if (e instanceof ApiError && e.code === ApiErrorCode.UNAUTHORIZED) {
        throw e;
      }
    }
    if (result.user === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '登录返回缺少用户信息');
    }
    return result;
  }

  /**
   * GET /auth/me。
   * 兼容「无效 Bearer 返回 200 + {user:null}」的旧行为：先刷新一次再取，仍为空则清 token 抛 unauthorized。
   */
  static async me(): Promise<MeResponseDto> {
    const first = await AuthService.fetchMe();
    const firstUser = first.user;
    if (firstUser !== undefined && firstUser !== null) {
      return first;
    }
    if (!TokenSession.hasRefresh()) {
      await TokenSession.clear();
      throw new ApiError(ApiErrorCode.UNAUTHORIZED, 200, '登录已失效，请重新登录');
    }
    await ApiClient.refreshAccessToken();
    const second = await AuthService.fetchMe();
    const secondUser = second.user;
    if (secondUser === undefined || secondUser === null) {
      await TokenSession.clear();
      throw new ApiError(ApiErrorCode.UNAUTHORIZED, 200, '登录已失效，请重新登录');
    }
    return second;
  }

  /** POST /auth/revoke（204）；失败由调用方决定是否忽略。 */
  static async revoke(): Promise<void> {
    const refreshToken = TokenSession.refreshToken();
    if (refreshToken.length === 0) {
      return;
    }
    const body: RevokeBodyDto = { refresh_token: refreshToken };
    const req = new ApiRequest();
    req.method = http.RequestMethod.POST;
    req.path = '/auth/revoke';
    req.jsonBody = JSON.stringify(body);
    req.auth = false;
    req.retryOn401 = false;
    req.timeoutMs = AuthService.REVOKE_TIMEOUT_MS;
    const raw = await ApiClient.request(req);
    if (raw.status !== 204 && raw.status !== 200) {
      throw ApiClient.errorOf(raw);
    }
  }

  private static async fetchMe(): Promise<MeResponseDto> {
    const raw = await ApiClient.getJson('/auth/me', null, AuthService.ME_TIMEOUT_MS);
    if (raw.status === 401) {
      throw ApiClient.errorOf(raw);
    }
    ApiClient.requireOk(raw);
    let dto: MeResponseDto | null = null;
    try {
      dto = JSON.parse(raw.text) as MeResponseDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '用户信息格式异常');
    }
    return dto;
  }
}

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';
import { TokenStore } from './TokenSession';
import { ApiError, ApiErrorCode } from './ApiError';
import { ErrorEnvelopeDto, RefreshBodyDto, TokenResponseDto } from './Dtos';
import { FileUtil } from '../util/FileUtil';

const DOMAIN: number = 0xEC00;
const TAG: string = 'Net';

/** 一次 API 请求的描述。用 class 给默认值，避免界面/服务层拼一堆可选参数。 */
export class ApiRequest {
  method: http.RequestMethod = http.RequestMethod.GET;
  /** 不含 `/api` 前缀，例如 '/auth/me' */
  path: string = '';
  query: Record<string, string> | null = null;
  /** 已序列化的 JSON 字符串（不传 Object，避免 ArkTS 动态对象问题） */
  jsonBody: string | null = null;
  form: http.MultiFormData[] | null = null;
  /** 是否注入 Bearer；/auth/token、/auth/refresh、/auth/revoke、/health 为 false */
  auth: boolean = true;
  /** 是否允许 401 → 单飞刷新 → 重放一次；/auth/refresh 自身为 false */
  retryOn401: boolean = true;
  timeoutMs: number = 15000;
  /** 响应按二进制读取（TTS 音频、下载） */
  wantBytes: boolean = false;
  maxLimit: number = 5 * 1024 * 1024;
}

/** 原始响应：不在这里做 JSON 解析，解析交给 service（避免泛型 + JSON.parse 的类型擦除问题）。 */
export class ApiRaw {
  status: number = 0;
  text: string = '';
  bytes: Uint8Array | null = null;
}

/**
 * 唯一 HTTP 出口（`@kit.NetworkKit` 的 http）。
 *
 * 行为（docs/architecture.md §5）：
 * - 每次请求新建 HttpRequest，finally 里 destroy()；
 * - `usingCache: false`；
 * - Bearer 注入 + 401 单飞刷新 + 每请求最多重放一次；
 * - refresh 被拒（400/401）→ 清 token 抛 unauthorized；refresh 网络失败/5xx → **不清 token**；
 * - `/auth/token`、`/auth/refresh`、`/auth/revoke`、`/health` 不参与该重试（auth:false）。
 */
export class ApiClient {
  private static readonly CONNECT_TIMEOUT_MS: number = 10000;
  private static readonly REFRESH_TIMEOUT_MS: number = 15000;
  private static refreshing: Promise<void> | null = null;

  static async getJson(path: string, query: Record<string, string> | null, timeoutMs: number): Promise<ApiRaw> {
    const req = new ApiRequest();
    req.method = http.RequestMethod.GET;
    req.path = path;
    req.query = query;
    req.timeoutMs = timeoutMs;
    return ApiClient.request(req);
  }

  static async postJson(path: string, body: string, auth: boolean, timeoutMs: number): Promise<ApiRaw> {
    const req = new ApiRequest();
    req.method = http.RequestMethod.POST;
    req.path = path;
    req.jsonBody = body;
    req.auth = auth;
    req.retryOn401 = auth;
    req.timeoutMs = timeoutMs;
    return ApiClient.request(req);
  }

  /** POST JSON，响应按二进制返回（TTS）。 */
  static async postJsonForBytes(path: string, body: string, timeoutMs: number): Promise<ApiRaw> {
    const req = new ApiRequest();
    req.method = http.RequestMethod.POST;
    req.path = path;
    req.jsonBody = body;
    req.wantBytes = true;
    req.timeoutMs = timeoutMs;
    req.maxLimit = 20 * 1024 * 1024;
    return ApiClient.request(req);
  }

  static async postMultipart(path: string, form: http.MultiFormData[], timeoutMs: number): Promise<ApiRaw> {
    const req = new ApiRequest();
    req.method = http.RequestMethod.POST;
    req.path = path;
    req.form = form;
    req.timeoutMs = timeoutMs;
    // 评测最长约 100s，给 120s；上传 12MB 也不能按 JSON 的 5MB 限制
    req.maxLimit = 20 * 1024 * 1024;
    return ApiClient.request(req);
  }

  /** 下载到本地路径（带 Authorization）。失败不覆盖已有文件。 */
  static async download(path: string, destPath: string, timeoutMs: number): Promise<void> {
    const req = new ApiRequest();
    req.method = http.RequestMethod.GET;
    req.path = path;
    req.wantBytes = true;
    req.timeoutMs = timeoutMs;
    req.maxLimit = 20 * 1024 * 1024;
    const raw = await ApiClient.request(req);
    ApiClient.requireOk(raw);
    const bytes = raw.bytes;
    if (bytes === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '下载内容为空');
    }
    FileUtil.writeBytesAtomic(destPath, bytes);
  }

  /**
   * 发起请求（含 401 单飞刷新与一次重放）。
   * 注意：重放仍 401 → 清 token 并抛 unauthorized，由调用方（SessionStore）统一跳登录。
   */
  static async request(req: ApiRequest): Promise<ApiRaw> {
    const first = await ApiClient.execute(req);
    if (first.status !== 401 || !req.auth || !req.retryOn401) {
      return first;
    }
    await ApiClient.refreshAccessToken();
    const second = await ApiClient.execute(req);
    if (second.status === 401) {
      await TokenStore.clear();
      throw new ApiError(ApiErrorCode.UNAUTHORIZED, 401, '登录已过期，请重新登录');
    }
    return second;
  }

  /** 单飞刷新：并发 401 只发一次 `/auth/refresh`，其余等待同一个 Promise。 */
  static async refreshAccessToken(): Promise<void> {
    const pending = ApiClient.refreshing;
    if (pending !== null) {
      await pending;
      return;
    }
    const task = ApiClient.doRefresh();
    ApiClient.refreshing = task;
    try {
      await task;
    } finally {
      ApiClient.refreshing = null;
    }
  }

  static requireOk(raw: ApiRaw): void {
    if (raw.status >= 200 && raw.status < 300) {
      return;
    }
    throw ApiClient.errorOf(raw);
  }

  /** 把非 2xx 响应转成 ApiError（优先用服务端 `{error:{code,message}}`）。 */
  static errorOf(raw: ApiRaw): ApiError {
    let text = raw.text;
    if (text.length === 0 && raw.bytes !== null) {
      text = ApiClient.decodeUtf8(raw.bytes);
    }
    let code = ApiErrorCode.forStatus(raw.status);
    let message = '';
    if (text.length > 0) {
      try {
        const envelope = JSON.parse(text) as ErrorEnvelopeDto;
        const body = envelope.error;
        if (body !== undefined) {
          if (body.code !== undefined && body.code.length > 0) {
            code = body.code;
          }
          if (body.message !== undefined) {
            message = body.message;
          }
        }
      } catch (err) {
        // 不是标准错误信封（例如网关 HTML），保留按状态码推断的 code
      }
    }
    return new ApiError(code, raw.status, message);
  }

  static decodeUtf8(bytes: Uint8Array): string {
    try {
      const decoder = new util.TextDecoder();
      return decoder.decodeToString(bytes);
    } catch (err) {
      return '';
    }
  }

  // ------------------------------------------------------------------ 内部实现

  private static async doRefresh(): Promise<void> {
    const refreshToken = TokenStore.refreshToken();
    if (refreshToken.length === 0) {
      await TokenStore.clear();
      throw new ApiError(ApiErrorCode.UNAUTHORIZED, 401, '登录已失效，请重新登录');
    }
    const body: RefreshBodyDto = { refresh_token: refreshToken };
    const req = new ApiRequest();
    req.method = http.RequestMethod.POST;
    req.path = '/auth/refresh';
    req.jsonBody = JSON.stringify(body);
    req.auth = false;
    req.retryOn401 = false;
    req.timeoutMs = ApiClient.REFRESH_TIMEOUT_MS;
    const raw = await ApiClient.execute(req);

    if (raw.status === 400 || raw.status === 401) {
      await TokenStore.clear();
      throw new ApiError(ApiErrorCode.UNAUTHORIZED, raw.status, '登录已过期，请重新登录');
    }
    if (raw.status !== 200) {
      // 网络/5xx：不清 token，让用户重试（避免一次断网就登出）
      throw ApiClient.errorOf(raw);
    }
    let dto: TokenResponseDto | null = null;
    try {
      dto = JSON.parse(raw.text) as TokenResponseDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '服务器返回的登录信息不完整');
    }
    const accessToken = typeof dto.access_token === 'string' ? dto.access_token : '';
    const newRefreshToken = typeof dto.refresh_token === 'string' ? dto.refresh_token : '';
    if (accessToken.length === 0 || newRefreshToken.length === 0) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '服务器返回的登录信息不完整');
    }
    const expiresIn = typeof dto.expires_in === 'number' ? dto.expires_in : 3600;
    const refreshExpiresIn = typeof dto.refresh_expires_in === 'number' ? dto.refresh_expires_in : 0;
    await TokenStore.save(accessToken, newRefreshToken, expiresIn, refreshExpiresIn);
  }

  private static async execute(req: ApiRequest): Promise<ApiRaw> {
    const url = ApiClient.buildUrl(req.path, req.query);
    const startedAt = Date.now();
    const header: Record<string, string> = {};
    header['Accept'] = req.wantBytes ? '*/*' : 'application/json';
    if (req.jsonBody !== null) {
      header['Content-Type'] = 'application/json';
    }
    if (req.form !== null) {
      header['Content-Type'] = 'multipart/form-data';
    }
    if (req.auth) {
      const token = TokenStore.accessToken();
      if (token.length > 0) {
        header['Authorization'] = 'Bearer ' + token;
      }
    }
    const options: http.HttpRequestOptions = {
      method: req.method,
      header: header,
      expectDataType: req.wantBytes ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
      connectTimeout: ApiClient.CONNECT_TIMEOUT_MS,
      readTimeout: req.timeoutMs,
      usingCache: false,
      maxLimit: req.maxLimit
    };
    if (req.jsonBody !== null) {
      options.extraData = req.jsonBody;
    }
    if (req.form !== null) {
      options.multiFormDataList = req.form;
    }

    const request = http.createHttp();
    try {
      const response = await request.request(url, options);
      const raw = new ApiRaw();
      raw.status = response.responseCode as number;
      const result = response.result;
      if (req.wantBytes) {
        if (result instanceof ArrayBuffer) {
          raw.bytes = new Uint8Array(result);
        }
      } else if (typeof result === 'string') {
        raw.text = result;
      }
      hilog.info(DOMAIN, TAG, '%{public}s status=%{public}d elapsed=%{public}dms',
        req.path, raw.status, Date.now() - startedAt);
      return raw;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, '%{public}s failed code=%{public}d elapsed=%{public}dms',
        req.path, e.code, Date.now() - startedAt);
      throw ApiClient.toNetworkError(e);
    } finally {
      request.destroy();
    }
  }

  private static buildUrl(path: string, query: Record<string, string> | null): string {
    let url = AppConfig.getBaseUrl() + '/api' + path;
    if (query !== null) {
      const keys = Object.keys(query);
      if (keys.length > 0) {
        const parts: string[] = [];
        for (const key of keys) {
          parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(query[key]));
        }
        url = url + '?' + parts.join('&');
      }
    }
    return url;
  }

  private static toNetworkError(e: BusinessError): ApiError {
    let code = ApiErrorCode.NETWORK_UNREACHABLE;
    if (e.code === 2300028) {
      code = ApiErrorCode.TIMEOUT;
    } else if (e.code === 2300997) {
      code = ApiErrorCode.CLEARTEXT_BLOCKED;
    }
    const detail = e.message ? e.message : '';
    return new ApiError(code, 0, detail);
  }
}

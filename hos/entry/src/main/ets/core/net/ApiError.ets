/**
 * 统一错误类型。
 *
 * 约定（见 docs/architecture.md §6）：
 * - 网络层、鉴权层、媒体层都抛 ApiError，页面/VM 只处理一种错误类型；
 * - `code` 仅用于日志与测试，UI 文案由 `core/error/UiError.ets` 统一映射；
 * - `status === 0` 表示「客户端本地错误」（如 mic_denied、timeout），不是 HTTP 响应。
 */
export class ApiError extends Error {
  code: string = 'internal_error';
  status: number = 0;
  /** 服务端 error.message 原样保留（后端已是中文、可操作）；本地错误为补充说明。 */
  detail: string = '';
  retryable: boolean = false;

  constructor(code: string, status: number, detail: string) {
    super(detail.length > 0 ? detail : code);
    this.name = 'ApiError';
    this.code = code;
    this.status = status;
    this.detail = detail;
    this.retryable = ApiError.isRetryable(code, status);
  }

  /** 客户端本地错误（无 HTTP 状态）。 */
  static local(code: string, detail: string): ApiError {
    return new ApiError(code, 0, detail);
  }

  static isRetryable(code: string, status: number): boolean {
    if (code === ApiErrorCode.NETWORK_UNREACHABLE) {
      return true;
    }
    if (code === ApiErrorCode.TIMEOUT) {
      return true;
    }
    if (code === ApiErrorCode.INTERNAL_ERROR && status >= 500) {
      return true;
    }
    if (code === ApiErrorCode.PROVIDER_ERROR) {
      return true;
    }
    if (code === ApiErrorCode.PROVIDER_TIMEOUT) {
      return true;
    }
    if (status === 502 || status === 503 || status === 504) {
      return true;
    }
    return false;
  }
}

/** 服务端错误码 + 客户端本地错误码。字符串常量集中一处，避免拼写漂移。 */
export class ApiErrorCode {
  // 服务端（docs/README.md §2.6）
  static readonly BAD_REQUEST: string = 'bad_request';
  static readonly UNAUTHORIZED: string = 'unauthorized';
  static readonly FORBIDDEN: string = 'forbidden';
  static readonly NOT_FOUND: string = 'not_found';
  static readonly AUDIO_NOT_FOUND: string = 'audio_not_found';
  static readonly AUDIO_GONE: string = 'audio_gone';
  static readonly PAYLOAD_TOO_LARGE: string = 'payload_too_large';
  static readonly DAILY_LIMIT_REACHED: string = 'daily_limit_reached';
  static readonly TOO_MANY_REQUESTS: string = 'too_many_requests';
  static readonly CONTENT_UNSAFE: string = 'content_unsafe';
  static readonly INTERNAL_ERROR: string = 'internal_error';
  static readonly PROVIDER_ERROR: string = 'provider_error';
  static readonly PROVIDER_UNAVAILABLE: string = 'provider_unavailable';
  static readonly PROVIDER_TIMEOUT: string = 'provider_timeout';

  // 客户端本地（docs/README.md §2.6 末段）
  static readonly NETWORK_UNREACHABLE: string = 'network_unreachable';
  static readonly TIMEOUT: string = 'timeout';
  static readonly CLEARTEXT_BLOCKED: string = 'cleartext_blocked';
  static readonly MIC_DENIED: string = 'mic_denied';
  static readonly MIC_UNAVAILABLE: string = 'mic_unavailable';
  static readonly RECORD_FAILED: string = 'record_failed';
  static readonly RECORD_TOO_SHORT: string = 'record_too_short';
  static readonly RECORD_TOO_LARGE: string = 'record_too_large';
  static readonly PLAYBACK_FAILED: string = 'playback_failed';
  static readonly CACHE_CORRUPT: string = 'cache_corrupt';
  static readonly BAD_RESPONSE: string = 'bad_response';
  static readonly BAD_BASE_URL: string = 'bad_base_url';

  /** HTTP 状态 → 默认 code（响应体没有标准错误信封时兜底）。 */
  static forStatus(status: number): string {
    if (status === 400) {
      return ApiErrorCode.BAD_REQUEST;
    }
    if (status === 401) {
      return ApiErrorCode.UNAUTHORIZED;
    }
    if (status === 403) {
      return ApiErrorCode.FORBIDDEN;
    }
    if (status === 404) {
      return ApiErrorCode.NOT_FOUND;
    }
    if (status === 413) {
      return ApiErrorCode.PAYLOAD_TOO_LARGE;
    }
    if (status === 429) {
      return ApiErrorCode.DAILY_LIMIT_REACHED;
    }
    if (status === 502) {
      return ApiErrorCode.PROVIDER_ERROR;
    }
    if (status === 503) {
      return ApiErrorCode.PROVIDER_UNAVAILABLE;
    }
    if (status === 504) {
      return ApiErrorCode.PROVIDER_TIMEOUT;
    }
    return ApiErrorCode.INTERNAL_ERROR;
  }
}

import { AppConfig, DemoAccount } from '../core/config/AppConfig';
import { ApiErrorCode } from '../core/net/ApiError';
import { ErrorMapper, UiError } from '../core/error/UiError';
import { HealthDto } from '../core/net/Dtos';
import { PracticeService } from '../core/service/PracticeService';
import { SessionStore } from '../core/session/SessionStore';

/**
 * 登录页状态。
 *
 * 校验顺序：必填 → baseUrl 合法 → 保存 baseUrl → `POST /auth/token` → `/auth/me`。
 * 成功后只写全局会话（AppStorage），页面切换由 Index 的 @StorageLink 驱动，VM 不做导航。
 */
@Observed
export class LoginVM {
  email: string = '';
  password: string = '';
  baseUrl: string = '';

  loading: boolean = false;
  checkingServer: boolean = false;
  serverStatus: string = '';

  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');

  demos: DemoAccount[] = AppConfig.DEMO_ACCOUNTS;

  async init(): Promise<void> {
    this.baseUrl = AppConfig.getBaseUrl();
    await this.checkServer();
  }

  /** GET /api/health（无需登录）：用于展示「NAS 已连接 / 连不上」。 */
  async checkServer(): Promise<void> {
    if (this.checkingServer) {
      return;
    }
    this.checkingServer = true;
    this.serverStatus = '';
    try {
      // 让健康检查反映「输入框里的地址」，而不是上次保存的地址
      const normalized = AppConfig.normalizeUrl(this.baseUrl);
      if (AppConfig.isValidUrl(normalized) && normalized !== AppConfig.getBaseUrl()) {
        await AppConfig.setBaseUrl(normalized);
        this.baseUrl = normalized;
      }
      const health = await PracticeService.health();
      this.serverStatus = LoginVM.describeHealth(health);
    } catch (err) {
      const ui = ErrorMapper.from(err as Error, false);
      this.serverStatus = ui.message;
    } finally {
      this.checkingServer = false;
    }
  }

  fillDemo(account: DemoAccount): void {
    this.email = account.email;
    this.password = account.password;
    this.hasError = false;
  }

  clearError(): void {
    this.hasError = false;
  }

  async login(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.hasError = false;
    if (this.email.trim().length === 0 || this.password.length === 0) {
      this.setError(new UiError('', '请输入邮箱和密码', '', false, ApiErrorCode.BAD_REQUEST));
      return;
    }
    const normalized = AppConfig.normalizeUrl(this.baseUrl);
    if (!AppConfig.isValidUrl(normalized)) {
      this.setError(new UiError('', ErrorMapper.messageFor(ApiErrorCode.BAD_BASE_URL, false), '', false,
        ApiErrorCode.BAD_BASE_URL));
      return;
    }
    this.loading = true;
    try {
      await AppConfig.setBaseUrl(normalized);
      this.baseUrl = normalized;
      await SessionStore.login(this.email.trim(), this.password);
    } catch (err) {
      this.setError(ErrorMapper.from(err as Error, false));
    } finally {
      this.loading = false;
    }
  }

  private setError(error: UiError): void {
    this.error = error;
    this.hasError = true;
  }

  private static describeHealth(health: HealthDto): string {
    const voice = health.voice;
    if (voice !== undefined && voice.reachable === false) {
      return '服务器已连接，但语音服务未就绪（录音会先保存，可稍后重试评测）';
    }
    const db = health.db;
    if (db !== undefined && db.ok === false) {
      return '服务器已连接，但数据库异常';
    }
    return '家庭 NAS 已连接';
  }
}

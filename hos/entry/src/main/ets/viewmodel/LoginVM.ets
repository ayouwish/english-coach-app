import { AppConfig, DemoAccount } from '../core/config/AppConfig';
import { ApiErrorCode } from '../core/net/ApiError';
import { ErrorMapper, UiError } from '../core/error/UiError';
import { HealthDto } from '../core/net/Dtos';
import { PracticeService } from '../core/service/PracticeService';
import { SessionStore } from '../core/session/SessionStore';
import { CredentialStore, SavedLogin } from '../core/session/CredentialStore';
import { TokenSession } from '../core/net/TokenSession';
import { AssetProbe } from '../core/session/AssetProbe';

const KEY_REMEMBER: string = 'cred_remember';
const KEY_SAVED_EMAIL: string = 'saved_email';

/**
 * 登录页状态。
 *
 * 校验顺序：必填 → baseUrl 合法 → 保存 baseUrl → `POST /auth/token` → `/auth/me`。
 * 成功后只写全局会话（AppStorage），页面切换由 Index 的 @StorageLink 驱动，VM 不做导航。
 *
 * 「记住密码」：登录成功且开关打开时写入 Asset Store（CredentialStore）；
 * 冷启动没有 token 时自动用记住的账号登录一次（失败则停在预填好的表单）。
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
  /** 记住密码（默认开；用户可关闭） */
  rememberPassword: boolean = true;
  rememberHint: string = '';
  /** 本机安全存储（Asset Store）是否降级：降级时登录态/密码无法持久化，会显示提示 */
  storageDegraded: boolean = false;
  /** 降级原因（Asset 错误码，便于定位机型问题） */
  storageDegradedDetail: string = '';
  /** 正在自动登录（冷启动用记住的账号） */
  autoLogging: boolean = false;

  demos: DemoAccount[] = AppConfig.DEMO_ACCOUNTS;

  private autoLoginTried: boolean = false;

  async init(): Promise<void> {
    this.baseUrl = AppConfig.getBaseUrl();
    this.rememberPassword = (await AppConfig.getNumber(KEY_REMEMBER, 1)) === 1;
    await this.checkServer();
    await this.loadRemembered();
    // Asset Store 自检：区分「本机安全存储不可用」与业务读写问题（独立 alias，不影响 token）
    await AssetProbe.run();
    if (!AssetProbe.ok()) {
      this.storageDegraded = true;
      this.storageDegradedDetail = '自检: ' + AssetProbe.result;
    }
    // 安全存储不可用时，至少把邮箱记在普通偏好里（只存邮箱，不存密码）
    if (this.email.length === 0) {
      this.email = await AppConfig.getString(KEY_SAVED_EMAIL, '');
    }
    this.storageDegraded = TokenSession.isDegraded() || CredentialStore.isDegraded();
    const tokenReason = TokenSession.degradedReason();
    const credReason = CredentialStore.degradedReason();
    if (tokenReason.length > 0) {
      this.storageDegradedDetail = 'token: ' + tokenReason;
    } else if (credReason.length > 0) {
      this.storageDegradedDetail = 'credential: ' + credReason;
    } else {
      this.storageDegradedDetail = '';
    }
    // 有记住的账号但当前没有登录态 → 静默自动登录一次
    // （刚主动退出登录时跳过，避免"退出→立刻又登进去"）
    const suppressed = CredentialStore.consumeAutoLoginSuppressed();
    if (!suppressed && this.email.length > 0 && this.password.length > 0 && !this.autoLoginTried) {
      this.autoLoginTried = true;
      this.autoLogging = true;
      try {
        await this.login();
      } finally {
        this.autoLogging = false;
      }
    }
  }

  private async loadRemembered(): Promise<void> {
    const saved = await CredentialStore.load();
    if (saved === null) {
      return;
    }
    this.email = saved.email;
    this.password = saved.password;
    this.rememberPassword = true;
    if (CredentialStore.isDegraded()) {
      this.rememberHint = '本机安全存储不可用，密码只能本次使用';
    }
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
      const ui = SessionStore.toUiError(err as Error, false);
      this.serverStatus = ui.message;
    } finally {
      this.checkingServer = false;
    }
  }

  /** 演示账号只填邮箱（线上种子密码可能被 BOOTSTRAP_* 覆盖，密码请向家长确认）。 */
  fillDemo(account: DemoAccount): void {
    this.email = account.email;
    this.hasError = false;
  }

  setRememberPassword(on: boolean): void {
    this.rememberPassword = on;
    void AppConfig.putNumber(KEY_REMEMBER, on ? 1 : 0);
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
      await this.saveCredential();
    } catch (err) {
      const ui = SessionStore.toUiError(err as Error, false);
      // 密码已失效：清掉记住的密码，避免每次启动都自动失败
      if (ui.code === ApiErrorCode.BAD_REQUEST && this.autoLoginTried) {
        this.rememberPassword = false;
        await AppConfig.putNumber(KEY_REMEMBER, 0);
        await CredentialStore.clear();
      }
      this.setError(ui);
    } finally {
      this.loading = false;
    }
  }

  private async saveCredential(): Promise<void> {
    await AppConfig.putString(KEY_SAVED_EMAIL, this.email.trim());
    await AppConfig.putNumber(KEY_REMEMBER, this.rememberPassword ? 1 : 0);
    if (!this.rememberPassword) {
      await CredentialStore.clear();
      this.rememberHint = '';
      return;
    }
    const ok = await CredentialStore.save(this.email.trim(), this.password);
    if (!ok) {
      this.rememberHint = '本机安全存储不可用，密码没有保存';
    } else {
      this.rememberHint = '';
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

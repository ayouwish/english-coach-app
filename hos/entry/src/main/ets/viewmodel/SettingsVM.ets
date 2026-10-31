import { AppConfig } from '../core/config/AppConfig';
import { ApiErrorCode } from '../core/net/ApiError';
import { ErrorMapper, UiError } from '../core/error/UiError';
import { HealthDto } from '../core/net/Dtos';
import { CacheService } from '../core/service/CacheService';
import { PracticeService } from '../core/service/PracticeService';
import { SessionStore } from '../core/session/SessionStore';
import { TokenSession } from '../core/net/TokenSession';

/** 设置页状态：服务器地址、健康检查、清缓存、退出登录。 */
@Observed
export class SettingsVM {
  baseUrl: string = '';
  savedBaseUrl: string = '';
  serverStatus: string = '';
  checkingServer: boolean = false;
  saving: boolean = false;
  loggingOut: boolean = false;

  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');
  hasNotice: boolean = false;
  notice: string = '';

  async init(): Promise<void> {
    this.baseUrl = AppConfig.getBaseUrl();
    this.savedBaseUrl = this.baseUrl;
    await this.checkServer();
  }

  async checkServer(): Promise<void> {
    if (this.checkingServer) {
      return;
    }
    this.checkingServer = true;
    this.serverStatus = '';
    try {
      const health = await PracticeService.health();
      this.serverStatus = SettingsVM.describeHealth(health);
    } catch (err) {
      const ui = SessionStore.toUiError(err as Error, false);
      this.serverStatus = ui.message;
    } finally {
      this.checkingServer = false;
    }
  }

  /** 保存服务器地址（release 包只读；M0 未区分 debug/release，见 README 待办）。 */
  async saveBaseUrl(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.hasError = false;
    this.hasNotice = false;
    const normalized = AppConfig.normalizeUrl(this.baseUrl);
    if (!AppConfig.isValidUrl(normalized)) {
      this.setError(ErrorMapper.messageFor(ApiErrorCode.BAD_BASE_URL, false));
      return;
    }
    this.saving = true;
    try {
      this.savedBaseUrl = await AppConfig.setBaseUrl(normalized);
      this.baseUrl = this.savedBaseUrl;
      this.notice = AppConfig.isCleartext(this.savedBaseUrl)
        ? '已保存。注意：http 明文在部分网络下会被系统拦截，建议使用 https'
        : '服务器地址已保存';
      this.hasNotice = true;
      await this.checkServer();
    } catch (err) {
      this.setError(SessionStore.toUiError(err as Error, false).message);
    } finally {
      this.saving = false;
    }
  }

  clearCache(): void {
    this.hasError = false;
    CacheService.clearAudioCache();
    this.notice = '已清除示范音与回放缓存';
    this.hasNotice = true;
  }

  /** 退出：revoke（失败也继续）→ 清 token/缓存/会话。页面负责清导航栈。 */
  async logout(): Promise<void> {
    if (this.loggingOut) {
      return;
    }
    this.loggingOut = true;
    try {
      await SessionStore.logout();
    } finally {
      this.loggingOut = false;
    }
  }

  tokenStorageNote(): string {
    return TokenSession.isDegraded()
      ? '凭证保存在内存（本次运行有效）：系统安全存储当前不可用'
      : '凭证保存在系统安全存储（Asset Store）';
  }

  clearNotice(): void {
    this.hasNotice = false;
  }

  private setError(message: string): void {
    this.error = new UiError('', message, '', false, '');
    this.hasError = true;
  }

  private static describeHealth(health: HealthDto): string {
    const voice = health.voice;
    if (voice !== undefined && voice.reachable === false) {
      return '已连接；语音服务未就绪（录音会先保存，可稍后重试评测）';
    }
    const db = health.db;
    if (db !== undefined && db.ok === false) {
      return '已连接；数据库异常';
    }
    return '已连接';
  }
}

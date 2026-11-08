import { AppConfig } from '../core/config/AppConfig';
import { ApiErrorCode } from '../core/net/ApiError';
import { ErrorMapper, UiError } from '../core/error/UiError';
import { HealthDto } from '../core/net/Dtos';
import { AuthService } from '../core/service/AuthService';
import { PracticeService } from '../core/service/PracticeService';
import { CredentialStore } from '../core/session/CredentialStore';
import { SessionStore } from '../core/session/SessionStore';

/**
 * 自助注册 / 用邀请码加入家庭（多家庭体系，服务端 task-97/99）。
 *
 * - 无邀请码 → 创建新家庭（role=parent）；
 * - 有邀请码 → 加入该家庭（共同家长；邀请码一次性，家长上限 3）；
 * - ALLOW_SELF_SIGNUP=0（/health.features.self_signup=false）时只允许「用邀请码加入」；
 * - 注册成功后调用 /auth/token 建立会话（注册接口只返回单个 token，没有 refresh）。
 */
@Observed
export class RegisterVM {
  mode: string = 'create';
  allowSelfSignup: boolean = true;
  featureChecked: boolean = false;

  familyName: string = '';
  inviteCode: string = '';
  displayName: string = '';
  email: string = '';
  password: string = '';

  loading: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');

  async init(): Promise<void> {
    this.mode = 'create';
    try {
      const health: HealthDto = await PracticeService.health();
      const features = health.features;
      if (features !== undefined && features.self_signup === false) {
        this.allowSelfSignup = false;
        this.mode = 'join';
      }
    } catch (err) {
      // 健康检查失败不阻塞注册：保持默认（允许创建家庭），提交时服务端会再校验
      this.allowSelfSignup = true;
    } finally {
      this.featureChecked = true;
    }
  }

  setMode(mode: string): void {
    if (mode === 'create' && !this.allowSelfSignup) {
      return;
    }
    this.mode = mode;
    this.hasError = false;
  }

  clearError(): void {
    this.hasError = false;
  }

  private setError(message: string, code: string): void {
    this.error = new UiError('', message, '', false, code);
    this.hasError = true;
  }

  async submit(): Promise<boolean> {
    if (this.loading) {
      return false;
    }
    this.hasError = false;
    const name = this.displayName.trim();
    const email = this.email.trim();
    if (name.length === 0) {
      this.setError('请填写你的昵称', ApiErrorCode.BAD_REQUEST);
      return false;
    }
    if (email.length === 0 || email.indexOf('@') <= 0) {
      this.setError('请填写正确的邮箱', ApiErrorCode.BAD_REQUEST);
      return false;
    }
    if (this.password.length < 8) {
      this.setError('密码至少 8 位', ApiErrorCode.BAD_REQUEST);
      return false;
    }
    const code = this.inviteCode.trim().toUpperCase();
    if (this.mode === 'join') {
      if (code.length === 0) {
        this.setError('请填写家长分享的邀请码', ApiErrorCode.BAD_REQUEST);
        return false;
      }
    } else {
      if (!this.allowSelfSignup) {
        this.setError('本站未开放自助注册，请用邀请码加入家庭', 'signup_disabled');
        return false;
      }
      if (this.familyName.trim().length === 0) {
        this.setError('请填写家庭名称（例如：王家）', ApiErrorCode.BAD_REQUEST);
        return false;
      }
    }
    const baseUrl = AppConfig.getBaseUrl();
    if (!AppConfig.isValidUrl(baseUrl)) {
      this.setError(ErrorMapper.messageFor(ApiErrorCode.BAD_BASE_URL, false), ApiErrorCode.BAD_BASE_URL);
      return false;
    }
    this.loading = true;
    try {
      await AuthService.register(name, email, this.password,
        this.mode === 'create' ? this.familyName.trim() : '', this.mode === 'join' ? code : '');
      // 注册接口只返回单 token；再用 /auth/token 建立可刷新会话
      await SessionStore.login(email, this.password);
      await CredentialStore.save(email, this.password);
      await AppConfig.putString('saved_email', email);
      return true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, false);
      this.hasError = true;
      return false;
    } finally {
      this.loading = false;
    }
  }
}

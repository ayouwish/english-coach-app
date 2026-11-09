import { AppConfig } from '../core/config/AppConfig';
import { ApiErrorCode } from '../core/net/ApiError';
import { ErrorMapper, UiError } from '../core/error/UiError';
import { HealthDto } from '../core/net/Dtos';
import { AuthService } from '../core/service/AuthService';
import { PracticeService } from '../core/service/PracticeService';
import { CredentialStore } from '../core/session/CredentialStore';
import { SessionStore } from '../core/session/SessionStore';

/**
 * 注册页（多家庭两级邀请，服务端 task-97/99/105）。
 *
 * - join：凭「共同家长邀请码」加入现有家庭（一次性、≤3 家长）；
 * - newfamily：凭管理员生成的「新家庭邀请码」创建全新家庭（一次性、消耗管理员 1 个名额）；
 * - create：无码公开创建家庭，仅当 `/health.features.self_signup === true` 时可用
 *   （默认关闭；无码注册服务端返回 403 signup_disabled）。
 */
@Observed
export class RegisterVM {
  /** 'join' | 'newfamily' | 'create' */
  mode: string = 'join';
  allowSelfSignup: boolean = false;
  featureChecked: boolean = false;

  familyName: string = '';
  inviteCode: string = '';
  newFamilyCode: string = '';
  displayName: string = '';
  email: string = '';
  password: string = '';

  loading: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');

  async init(): Promise<void> {
    // 默认关闭公开注册；只有服务端显式 self_signup=true 才显示「创建家庭」
    this.allowSelfSignup = false;
    this.mode = 'join';
    try {
      const health: HealthDto = await PracticeService.health();
      const features = health.features;
      if (features !== undefined && features.self_signup === true) {
        this.allowSelfSignup = true;
        this.mode = 'create';
      }
    } catch (err) {
      this.allowSelfSignup = false;
      this.mode = 'join';
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
    const invite = this.inviteCode.trim().toUpperCase();
    const newCode = this.newFamilyCode.trim().toUpperCase();
    const family = this.familyName.trim();

    if (this.mode === 'join') {
      if (invite.length === 0) {
        this.setError('请填写家长分享的邀请码', ApiErrorCode.BAD_REQUEST);
        return false;
      }
    } else if (this.mode === 'newfamily') {
      if (newCode.length === 0) {
        this.setError('请填写管理员分享的新家庭邀请码', ApiErrorCode.BAD_REQUEST);
        return false;
      }
      if (family.length === 0) {
        this.setError('请填写新家庭名称（例如：李家）', ApiErrorCode.BAD_REQUEST);
        return false;
      }
    } else {
      if (!this.allowSelfSignup) {
        this.setError('本站未开放自助注册，请联系管理员', 'signup_disabled');
        return false;
      }
      if (family.length === 0) {
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
      await AuthService.register(name, email, this.password, family,
        this.mode === 'join' ? invite : '',
        this.mode === 'newfamily' ? newCode : '');
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

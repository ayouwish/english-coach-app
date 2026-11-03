import { ApiError, ApiErrorCode } from '../net/ApiError';
import { ErrorMapper, UiError } from '../error/UiError';
import { UsageDto, UserDto } from '../net/Dtos';
import { TokenSession } from '../net/TokenSession';
import { AuthService } from '../service/AuthService';
import { CacheService } from '../service/CacheService';
import { CredentialStore } from './CredentialStore';

/**
 * 全局会话状态（登录用户 / 角色 / 今日用量）。
 *
 * 约定（docs/architecture.md §3.3）：更新时**整体替换对象**
 * （`AppStorage.setOrCreate('session', new SessionState())`），
 * 避免嵌套属性不触发刷新。
 */
@Observed
export class SessionState {
  loggedIn: boolean = false;
  userId: string = '';
  displayName: string = '';
  email: string = '';
  /** 'parent' | 'child' */
  role: string = 'child';
  cefrLevel: string = 'A1';
  /** 'child' | 'teen' | 'adult' */
  ageBand: string = 'adult';
  isChild: boolean = false;
  avatar: string = '';
  dailyLimitMinutes: number = 20;
  minutesToday: number = 0;
  remainingMinutes: number = 0;
}

/** 会话编排：启动恢复 / 登录 / 登出 / 用量同步。 */
export class SessionStore {
  static readonly STORAGE_KEY: string = 'session';

  static state(): SessionState {
    const current = AppStorage.get<SessionState>(SessionStore.STORAGE_KEY);
    if (current === undefined) {
      return new SessionState();
    }
    return current;
  }

  static set(state: SessionState): void {
    AppStorage.setOrCreate<SessionState>(SessionStore.STORAGE_KEY, state);
  }

  /**
   * 冷启动恢复：读 Asset → `/auth/me`。
   * 返回 false = 需要登录；抛错 = 网络/服务器问题（由启动页展示重试）。
   */
  static async restore(): Promise<boolean> {
    await TokenSession.load();
    if (!TokenSession.hasRefresh()) {
      SessionStore.set(new SessionState());
      return false;
    }
    try {
      const me = await AuthService.me();
      const user = me.user;
      if (user === undefined || user === null) {
        await TokenSession.clear();
        SessionStore.set(new SessionState());
        return false;
      }
      const usage = me.usage === undefined ? null : me.usage;
      SessionStore.applyUser(user, usage);
      return true;
    } catch (err) {
      const e = err as Error;
      if (e instanceof ApiError && e.code === ApiErrorCode.UNAUTHORIZED) {
        await TokenSession.clear();
        SessionStore.set(new SessionState());
        return false;
      }
      throw e;
    }
  }

  static async login(email: string, password: string): Promise<void> {
    const result = await AuthService.login(email, password);
    const user = result.user;
    if (user === null) {
      throw new ApiError(ApiErrorCode.UNAUTHORIZED, 401, '登录失败');
    }
    // 切换账号：旧账号缓存必须失效（docs/architecture.md §7.4）
    CacheService.clearAll();
    SessionStore.applyUser(user, result.usage);
  }

  /** 退出：先 revoke（失败也继续），再清 token + 缓存 + 全局状态。 */
  static async logout(): Promise<void> {
    // 主动退出后不在本次进程内自动登录（记住的密码仍保留，下次启动可自动登录）
    CredentialStore.markLoggedOut();
    try {
      await AuthService.revoke();
    } catch (err) {
      // 网络失败也要能退出本地账号（ADR-0002）
    }
    await TokenSession.clear();
    CacheService.clearAll();
    SessionStore.set(new SessionState());
  }

  /**
   * 会话失效（401/刷新被拒）：清 token + 全局会话。
   * 清完后 Index 的 @Watch 会清空导航栈并显示登录页（见 pages/Index.ets）。
   */
  static async expire(): Promise<void> {
    try {
      await TokenSession.clear();
    } catch (err) {
      // 清凭证失败也要把 UI 退回登录态
    }
    SessionStore.set(new SessionState());
  }

  /**
   * 统一错误映射：命中 unauthorized 时顺带 expire()。
   * 页面只需要展示返回的 UiError，不需要自己判断 401。
   */
  static toUiError(err: Error, isChild: boolean): UiError {
    const ui = ErrorMapper.from(err, isChild);
    if (ui.code === ApiErrorCode.UNAUTHORIZED) {
      // 不阻塞 UI：清凭证 + 会话，Index 的 @Watch 负责清导航栈
      void SessionStore.expire();
    }
    return ui;
  }

  /** 每次提交评测后同步用量（422/429 依赖它展示剩余时长）。 */
  static updateUsage(usage: UsageDto): void {
    const current = SessionStore.state();
    const next = new SessionState();
    next.loggedIn = current.loggedIn;
    next.userId = current.userId;
    next.displayName = current.displayName;
    next.email = current.email;
    next.role = current.role;
    next.cefrLevel = current.cefrLevel;
    next.ageBand = current.ageBand;
    next.isChild = current.isChild;
    next.avatar = current.avatar;
    next.dailyLimitMinutes = usage.limitMinutes;
    next.minutesToday = usage.minutes;
    next.remainingMinutes = usage.remainingMinutes;
    SessionStore.set(next);
  }

  static applyUser(user: UserDto, usage: UsageDto | null): void {
    const next = new SessionState();
    next.loggedIn = true;
    next.userId = user.id;
    next.displayName = user.displayName;
    next.email = user.email;
    next.role = user.role;
    next.cefrLevel = user.cefrLevel;
    next.ageBand = user.ageBand;
    next.isChild = user.role === 'child' || user.isChild === true;
    next.avatar = (user.avatar === undefined || user.avatar === null) ? '' : user.avatar;
    next.dailyLimitMinutes = user.dailyLimitMinutes === undefined ? 20 : user.dailyLimitMinutes;
    if (usage !== null) {
      next.dailyLimitMinutes = usage.limitMinutes;
      next.minutesToday = usage.minutes;
      next.remainingMinutes = usage.remainingMinutes;
    }
    SessionStore.set(next);
  }
}

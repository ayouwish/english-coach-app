import { common } from '@kit.AbilityKit';
import { ApiError, ApiErrorCode } from '../net/ApiError';

/**
 * 进程内运行期上下文持有者。
 *
 * 由 EntryAbility.onCreate 注入 UIAbilityContext，页面/服务通过它拿 context，
 * 避免散落的 `getContext(this)`（也避免在非 UI 文件里拿不到 context）。
 */
export class AppRuntime {
  private static abilityContext: common.UIAbilityContext | null = null;

  static init(context: common.UIAbilityContext): void {
    AppRuntime.abilityContext = context;
  }

  static context(): common.UIAbilityContext | null {
    return AppRuntime.abilityContext;
  }

  static requireContext(): common.UIAbilityContext {
    const ctx = AppRuntime.abilityContext;
    if (ctx === null) {
      throw new ApiError(ApiErrorCode.INTERNAL_ERROR, 0, '应用上下文未初始化');
    }
    return ctx;
  }

  static filesDir(): string {
    const ctx = AppRuntime.abilityContext;
    return ctx === null ? '' : ctx.filesDir;
  }

  static cacheDir(): string {
    const ctx = AppRuntime.abilityContext;
    return ctx === null ? '' : ctx.cacheDir;
  }
}

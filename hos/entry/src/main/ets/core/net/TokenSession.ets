import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';

const DOMAIN: number = 0xEC00;
const TAG: string = 'Token';

/** 【待确认】Asset Store Kit 错误码：24000001 = 资产不存在、24000002 = 资产已存在。 */
const ERR_ASSET_NOT_FOUND: number = 24000001;

/**
 * access / refresh token 的唯一存放处（Asset Store Kit）。
 *
 * 设计约束（ADR-0002）：
 * - 只走 `@kit.AssetStoreKit`（`asset.add/query/update/remove`），**绝不写 Preferences**；
 * - 过期时间戳是非敏感数据，放 Preferences（AppConfig），用于主动刷新判断；
 * - 日志里不出现 token 任何片段；
 * - refresh 一次性轮换：`save()` 先写 refresh 再写 access（refresh 不可再生）。
 *
 * 回退方案（Asset Store 不可用/接口报错时）：
 * - 置 `degraded = true`，token 只保留在**本进程内存**，不落盘、不写明文；
 * - 代价：杀进程后需重新登录；收益：绝不把凭证降级成明文。
 * - 【待确认】若 `@kit.AssetStoreKit` 导入名与本机 SDK 不符，可换成 `@ohos.security.asset`，
 *   其余调用签名相同。
 */
export class TokenSession {
  private static readonly ALIAS_ACCESS: string = 'ec_access_token';
  private static readonly ALIAS_REFRESH: string = 'ec_refresh_token';
  private static readonly KEY_ACCESS_EXP: string = 'accessExpiresAt';
  private static readonly KEY_REFRESH_EXP: string = 'refreshExpiresAt';

  private static access: string = '';
  private static refresh: string = '';
  private static accessExpiresAt: number = 0;
  private static refreshExpiresAt: number = 0;
  private static loaded: boolean = false;
  private static degraded: boolean = false;

  /** 冷启动读取一次；之后全部走内存。 */
  static async load(): Promise<void> {
    if (TokenSession.loaded) {
      return;
    }
    TokenSession.access = await TokenSession.readSecret(TokenSession.ALIAS_ACCESS);
    TokenSession.refresh = await TokenSession.readSecret(TokenSession.ALIAS_REFRESH);
    TokenSession.accessExpiresAt = await AppConfig.getNumber(TokenSession.KEY_ACCESS_EXP, 0);
    TokenSession.refreshExpiresAt = await AppConfig.getNumber(TokenSession.KEY_REFRESH_EXP, 0);
    TokenSession.loaded = true;
  }

  static accessToken(): string {
    return TokenSession.access;
  }

  static refreshToken(): string {
    return TokenSession.refresh;
  }

  static hasAccess(): boolean {
    return TokenSession.access.length > 0;
  }

  static hasRefresh(): boolean {
    return TokenSession.refresh.length > 0;
  }

  /** Asset Store 是否降级为内存模式（设置页/诊断可展示）。 */
  static isDegraded(): boolean {
    return TokenSession.degraded;
  }

  static accessExpiresAt(): number {
    return TokenSession.accessExpiresAt;
  }

  static refreshExpiresAt(): number {
    return TokenSession.refreshExpiresAt;
  }

  /** 过期或在 skew 窗口内。M0 以服务端 401 为准，此方法用于后续主动刷新优化。 */
  static needsRefresh(now: number = Date.now(), skewMs: number = 60000): boolean {
    if (!TokenSession.hasAccess()) {
      return true;
    }
    if (TokenSession.accessExpiresAt <= 0) {
      return false;
    }
    return TokenSession.accessExpiresAt - skewMs <= now;
  }

  /**
   * 原子替换一对 token（先 refresh，后 access）。
   * expiresInSec / refreshExpiresInSec 来自 `/auth/token`、`/auth/refresh` 的 `expires_in`。
   */
  static async save(accessToken: string, refreshToken: string, expiresInSec: number,
    refreshExpiresInSec: number): Promise<void> {
    const now = Date.now();
    await TokenSession.writeSecret(TokenSession.ALIAS_REFRESH, refreshToken);
    await TokenSession.writeSecret(TokenSession.ALIAS_ACCESS, accessToken);
    TokenSession.access = accessToken;
    TokenSession.refresh = refreshToken;
    TokenSession.accessExpiresAt = expiresInSec > 0 ? now + expiresInSec * 1000 : 0;
    TokenSession.refreshExpiresAt = refreshExpiresInSec > 0 ? now + refreshExpiresInSec * 1000 : 0;
    await AppConfig.putNumber(TokenSession.KEY_ACCESS_EXP, TokenSession.accessExpiresAt);
    await AppConfig.putNumber(TokenSession.KEY_REFRESH_EXP, TokenSession.refreshExpiresAt);
    TokenSession.loaded = true;
  }

  static async clear(): Promise<void> {
    TokenSession.access = '';
    TokenSession.refresh = '';
    TokenSession.accessExpiresAt = 0;
    TokenSession.refreshExpiresAt = 0;
    await TokenSession.removeSecret(TokenSession.ALIAS_ACCESS);
    await TokenSession.removeSecret(TokenSession.ALIAS_REFRESH);
    await AppConfig.putNumber(TokenSession.KEY_ACCESS_EXP, 0);
    await AppConfig.putNumber(TokenSession.KEY_REFRESH_EXP, 0);
  }

  // ---------------------------------------------------------------- Asset 封装

  private static encode(value: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(value);
  }

  private static decode(value: Uint8Array): string {
    const decoder = new util.TextDecoder();
    return decoder.decodeToString(value);
  }

  private static buildAttrs(alias: string, secret: string): asset.AssetMap {
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.ALIAS, TokenSession.encode(alias));
    attrs.set(asset.Tag.SECRET, TokenSession.encode(secret));
    // 首次解锁后即可读（App 前台使用；重启后无需再次解锁）
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    // 【待确认】SYNC_TYPE 自 API 12 提供；显式声明不参与云同步，避免 token 进备份。
    attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    return attrs;
  }

  /** 先 update（已存在），失败再 add（首次）；两次都失败则降级为内存模式。 */
  private static async writeSecret(alias: string, secret: string): Promise<void> {
    if (secret.length === 0) {
      await TokenSession.removeSecret(alias);
      return;
    }
    if (TokenSession.degraded) {
      return;
    }
    const updateMap: asset.AssetMap = new Map();
    updateMap.set(asset.Tag.ALIAS, TokenSession.encode(alias));
    updateMap.set(asset.Tag.SECRET, TokenSession.encode(secret));
    try {
      await asset.update(updateMap);
      return;
    } catch (updateErr) {
      const ue = updateErr as BusinessError;
      hilog.debug(DOMAIN, TAG, 'asset.update miss (code=%{public}d), trying add', ue.code);
    }
    try {
      await asset.add(TokenSession.buildAttrs(alias, secret));
    } catch (addErr) {
      const ae = addErr as BusinessError;
      TokenSession.degraded = true;
      hilog.error(DOMAIN, TAG, 'asset.add failed (code=%{public}d), fallback to memory only', ae.code);
    }
  }

  private static async readSecret(alias: string): Promise<string> {
    if (TokenSession.degraded) {
      return '';
    }
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, TokenSession.encode(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const result: asset.AssetMap[] = await asset.query(query);
      if (result.length === 0) {
        return '';
      }
      const secret = result[0].get(asset.Tag.SECRET);
      if (secret instanceof Uint8Array) {
        return TokenSession.decode(secret);
      }
      return '';
    } catch (err) {
      const e = err as BusinessError;
      if (e.code === ERR_ASSET_NOT_FOUND) {
        return '';
      }
      TokenSession.degraded = true;
      hilog.error(DOMAIN, TAG, 'asset.query failed (code=%{public}d), fallback to memory only', e.code);
      return '';
    }
  }

  private static async removeSecret(alias: string): Promise<void> {
    if (TokenSession.degraded) {
      return;
    }
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.ALIAS, TokenSession.encode(alias));
    try {
      await asset.remove(attrs);
    } catch (err) {
      // 不存在时忽略；其它失败也不阻塞登出
      const e = err as BusinessError;
      hilog.debug(DOMAIN, TAG, 'asset.remove ignored (code=%{public}d)', e.code);
    }
  }
}

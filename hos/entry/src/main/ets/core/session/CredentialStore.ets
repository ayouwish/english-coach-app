import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xEC00;
const TAG: string = 'Cred';

/** 「记住密码」保存的登录信息（只放 Asset Store，绝不写 Preferences/日志）。 */
export class SavedLogin {
  email: string = '';
  password: string = '';
}

/**
 * 记住密码（用户 2026-11-03 要求的基础能力）。
 *
 * 安全约束：
 * - 只存 `@kit.AssetStoreKit`（alias `ec_saved_login`），不写 Preferences、不落日志；
 * - Asset Store 不可用时**不降级为明文**：save() 返回 false，页面提示「本机无法安全保存密码」；
 * - 退出登录**不清除**记住的密码（下次仍可一键登录）；用户手动关闭开关才清除。
 */
export class CredentialStore {
  private static readonly ALIAS: string = 'ec_saved_login';
  private static degraded: boolean = false;
  private static degradedCode: number = 0;
  /** 主动退出登录后，本次进程内不再自动登录（否则退出→登录页→立刻又登回去）。 */
  private static suppressAutoLogin: boolean = false;

  static markLoggedOut(): void {
    CredentialStore.suppressAutoLogin = true;
  }

  /** 读取并复位「刚退出登录」标记。 */
  static consumeAutoLoginSuppressed(): boolean {
    const value = CredentialStore.suppressAutoLogin;
    CredentialStore.suppressAutoLogin = false;
    return value;
  }

  static async save(email: string, password: string): Promise<boolean> {
    if (email.length === 0 || password.length === 0) {
      await CredentialStore.clear();
      return true;
    }
    const saved = new SavedLogin();
    saved.email = email;
    saved.password = password;
    const value = JSON.stringify(saved);
    // 先 update（已存在）再 add（首次）
    const updateMap: asset.AssetMap = new Map();
    updateMap.set(asset.Tag.ALIAS, CredentialStore.encode(CredentialStore.ALIAS));
    updateMap.set(asset.Tag.SECRET, CredentialStore.encode(value));
    const queryMap: asset.AssetMap = new Map();
    queryMap.set(asset.Tag.ALIAS, CredentialStore.encode(CredentialStore.ALIAS));
    try {
      await asset.update(queryMap, updateMap);
      CredentialStore.degraded = false;
      return true;
    } catch (updateErr) {
      const ue = updateErr as BusinessError;
      hilog.debug(DOMAIN, TAG, 'asset.update miss (code=%{public}d), trying add', ue.code);
    }
    try {
      const attrs: asset.AssetMap = new Map();
      attrs.set(asset.Tag.ALIAS, CredentialStore.encode(CredentialStore.ALIAS));
      attrs.set(asset.Tag.SECRET, CredentialStore.encode(value));
      await asset.add(attrs);
      CredentialStore.degraded = false;
      return true;
    } catch (addErr) {
      const ae = addErr as BusinessError;
      hilog.warn(DOMAIN, TAG, 'asset.add with full attrs failed (code=%{public}d), retry minimal', ae.code);
      try {
        // 兜底：最小属性集再试一次（部分机型组合属性会报错）
        const minimal: asset.AssetMap = new Map();
        minimal.set(asset.Tag.ALIAS, CredentialStore.encode(CredentialStore.ALIAS));
        minimal.set(asset.Tag.SECRET, CredentialStore.encode(value));
        await asset.add(minimal);
        CredentialStore.degraded = false;
        return true;
      } catch (minErr) {
        const me = minErr as BusinessError;
        CredentialStore.degraded = true;
        CredentialStore.degradedCode = me.code;
        hilog.error(DOMAIN, TAG, 'asset.add failed (code=%{public}d)', me.code);
        return false;
      }
    }
  }

  /** 读取记住的账号；不存在/解析失败返回 null。 */
  static async load(): Promise<SavedLogin | null> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, CredentialStore.encode(CredentialStore.ALIAS));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const result: asset.AssetMap[] = await asset.query(query);
      if (result.length === 0) {
        return null;
      }
      const secret = result[0].get(asset.Tag.SECRET);
      if (!(secret instanceof Uint8Array)) {
        return null;
      }
      const text = CredentialStore.decode(secret);
      const saved = JSON.parse(text) as SavedLogin;
      if (saved === null || typeof saved.email !== 'string' || typeof saved.password !== 'string') {
        return null;
      }
      if (saved.email.length === 0 || saved.password.length === 0) {
        return null;
      }
      return saved;
    } catch (err) {
      const e = err as BusinessError;
      if (e.code === 24000001) {
        return null;
      }
      // 读失败不直接降级（否则首次启动读不到就永远不写）
      hilog.warn(DOMAIN, TAG, 'asset.query failed (code=%{public}d), keep writable', e.code);
      return null;
    }
  }

  static async clear(): Promise<void> {
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.ALIAS, CredentialStore.encode(CredentialStore.ALIAS));
    try {
      await asset.remove(attrs);
    } catch (err) {
      const e = err as BusinessError;
      hilog.debug(DOMAIN, TAG, 'asset.remove ignored (code=%{public}d)', e.code);
    }
  }

  static isDegraded(): boolean {
    return CredentialStore.degraded;
  }

  static degradedReason(): string {
    return CredentialStore.degradedCode > 0
      ? ('asset error ' + CredentialStore.degradedCode.toString()) : '';
  }

  private static encode(value: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(value);
  }

  private static decode(value: Uint8Array): string {
    const decoder = new util.TextDecoder();
    return decoder.decodeToString(value);
  }
}

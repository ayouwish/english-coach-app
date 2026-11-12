import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 登录页「演示账号一键填入」用的账号。 */
export class DemoAccount {
  label: string = '';
  email: string = '';
  password: string = '';

  constructor(label: string, email: string, password: string) {
    this.label = label;
    this.email = email;
    this.password = password;
  }
}

/**
 * 非敏感配置（baseUrl、语速偏好、token 过期时间戳）。
 *
 * 敏感数据（access/refresh token）**只**放 Asset Store（见 TokenSession），不得进这里。
 * 存储：Preferences（`ec_prefs`）。
 *
 * 【待确认】Preferences API：使用 `preferences.getPreferences(context, options)` +
 * `get/put/flush` 的 Promise 形式（API 10+ 稳定）；若本机 SDK 只暴露 sync 版本，
 * 改成 `getPreferencesSync` / `getSync` / `putSync` / `flushSync` 即可，调用点不变。
 */
export class AppConfig {
  private static readonly PREF_NAME: string = 'ec_prefs';
  private static store: preferences.Preferences | null = null;
  private static initialized: boolean = false;
  private static baseUrl: string = 'https://english.dreamsearch.top';

  static readonly DEFAULT_BASE_URL: string = 'https://english.dreamsearch.top';
  static readonly APP_VERSION: string = '0.1.0';

  /**
   * 后端种子账号（`english-coach/web/src/data/accounts.json`）。
   * 【待确认】部署时可用 BOOTSTRAP_DAD_EMAIL/PASSWORD 等环境变量覆盖，
   * 因此这里只是「演示填充」，不保证线上一定可用；以设置页/后端实际为准。
   */
  static readonly DEMO_ACCOUNTS: DemoAccount[] = [
    new DemoAccount('爸爸 · 家长 · B1', 'dad@example.com', 'Dad12345!'),
    new DemoAccount('女儿 · 儿童 · A1', 'girl@example.com', 'Girl12345!')
  ];

  static async init(context: common.Context): Promise<void> {
    if (AppConfig.initialized) {
      return;
    }
    const options: preferences.Options = { name: AppConfig.PREF_NAME };
    const store = await preferences.getPreferences(context, options);
    AppConfig.store = store;
    const stored = await store.get('baseUrl', AppConfig.DEFAULT_BASE_URL);
    AppConfig.baseUrl = AppConfig.normalizeUrl(stored as string);
    AppConfig.initialized = true;
  }

  static isInitialized(): boolean {
    return AppConfig.initialized;
  }

  static getBaseUrl(): string {
    return AppConfig.baseUrl;
  }

  /** 保存并立即生效；返回规范化后的地址。 */
  static async setBaseUrl(raw: string): Promise<string> {
    const url = AppConfig.normalizeUrl(raw);
    AppConfig.baseUrl = url;
    await AppConfig.putString('baseUrl', url);
    return url;
  }

  /** 去掉尾部 `/` 与误填的 `/api`，补全 scheme。空串回落到默认值。 */
  static normalizeUrl(raw: string): string {
    let url = raw.trim();
    if (url.length === 0) {
      return AppConfig.DEFAULT_BASE_URL;
    }
    const lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      url = 'https://' + url;
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.toLowerCase().endsWith('/api')) {
      url = url.substring(0, url.length - 4);
    }
    return url;
  }

  /** 轻量校验：只要求 scheme + 非空 host；不在这里做 DNS/可达性判断。 */
  static isValidUrl(url: string): boolean {
    const lower = url.toLowerCase();
    let rest = '';
    if (lower.startsWith('https://')) {
      rest = url.substring(8);
    } else if (lower.startsWith('http://')) {
      rest = url.substring(7);
    } else {
      return false;
    }
    if (rest.length === 0 || rest.indexOf(' ') >= 0) {
      return false;
    }
    const host = rest.split('/')[0].split(':')[0];
    return host.length > 0;
  }

  static isCleartext(url: string): boolean {
    return url.toLowerCase().startsWith('http://');
  }

  static async getString(key: string, defaultValue: string): Promise<string> {
    const store = AppConfig.store;
    if (store === null) {
      return defaultValue;
    }
    const value = await store.get(key, defaultValue);
    return value as string;
  }

  static async putString(key: string, value: string): Promise<void> {
    const store = AppConfig.store;
    if (store === null) {
      return;
    }
    await store.put(key, value);
    await store.flush();
  }

  static async getNumber(key: string, defaultValue: number): Promise<number> {
    const store = AppConfig.store;
    if (store === null) {
      return defaultValue;
    }
    const value = await store.get(key, defaultValue);
    return value as number;
  }

  static async putNumber(key: string, value: number): Promise<void> {
    const store = AppConfig.store;
    if (store === null) {
      return;
    }
    await store.put(key, value);
    await store.flush();
  }

  /** 当前账号 cefrLevel → 可用的语料等级（服务端没有 C1 语料，回退 B2）。 */
  static levelForCefr(cefr: string): string {
    const upper = cefr.trim().toUpperCase();
    if (upper === 'A1' || upper === 'A2' || upper === 'B1' || upper === 'B2' ||
      upper === 'C1' || upper === 'C2') {
      return upper;
    }
    return 'B2';
  }
}

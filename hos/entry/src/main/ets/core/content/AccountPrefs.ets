import { AccountService } from '../service/AccountService';

/**
 * 账号偏好缓存（GET /api/settings 的三个字段：ttsVoice / ttsRate / storySentences / autoIllustrate）。
 *
 * 为什么单独缓存：TTS 示范音、故事句数、保存后自动插画都要读它，但每次调接口太慢；
 * 进程内只拉一次，设置页保存后调 `reload()`。
 */
export class AccountPrefs {
  static loaded: boolean = false;
  static ttsVoice: string = '';
  static ttsRate: string = '';
  static storySentences: number = 0;
  static autoIllustrate: boolean = false;

  static async ensure(): Promise<void> {
    if (AccountPrefs.loaded) {
      return;
    }
    AccountPrefs.loaded = true;
    await AccountPrefs.reload();
  }

  static async reload(): Promise<void> {
    try {
      const dto = await AccountService.settings();
      const prefs = dto.prefs;
      if (prefs !== undefined && prefs !== null) {
        const voice = prefs.ttsVoice;
        AccountPrefs.ttsVoice = (voice === undefined || voice === null) ? '' : voice;
        const rate = prefs.ttsRate;
        AccountPrefs.ttsRate = (rate === undefined || rate === null) ? '' : rate;
      }
      const user = dto.user;
      if (user !== undefined && user !== null) {
        const sentences = user.storySentences;
        AccountPrefs.storySentences = (sentences === undefined || sentences === null) ? 0 : sentences;
        AccountPrefs.autoIllustrate = user.autoIllustrate === true;
      }
    } catch (err) {
      // 偏好拉取失败不阻塞主流程（用默认值）
    }
  }

  /** 音色（空 = 服务端默认）。 */
  static voice(): string {
    return AccountPrefs.ttsVoice;
  }

  /** 语速：账号偏好优先，否则用传入默认值。 */
  static rateOr(fallback: string): string {
    return AccountPrefs.ttsRate.length > 0 ? AccountPrefs.ttsRate : fallback;
  }
}

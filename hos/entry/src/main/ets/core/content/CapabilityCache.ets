import { PracticeService } from '../service/PracticeService';

/**
 * `/api/health` 能力开关缓存（进程内一次）。
 *
 * 客户端按能力隐藏/禁用入口（README §2.4）：
 * - `image=false` → 不显示「给我画一张」
 * - `ocr=false` → 不显示拍照识别（FlowPage 已用 health 判断，这里统一供其它页面）
 * - `avatar_presets=false` → 形象库入口提示不可用
 */
export class CapabilityCache {
  static loaded: boolean = false;
  /** voice 能力（缺省 true：宁可让用户点，服务端 503 给可读提示，也别误藏功能） */
  static image: boolean = true;
  static ocr: boolean = true;
  static avatarPresets: boolean = true;
  static phonemeLevel: boolean = true;
  static prosody: boolean = true;
  static intonationCurve: boolean = true;

  static async ensure(): Promise<void> {
    if (CapabilityCache.loaded) {
      return;
    }
    try {
      const health = await PracticeService.health();
      const voice = health.voice;
      if (voice !== undefined && voice !== null) {
        const caps = voice.capabilities;
        if (caps !== undefined && caps !== null) {
          CapabilityCache.image = caps.image === true;
          CapabilityCache.ocr = caps.ocr === true;
          CapabilityCache.avatarPresets = caps.avatar_presets === true;
          CapabilityCache.phonemeLevel = caps.phoneme_level === true;
          CapabilityCache.prosody = caps.prosody === true;
          CapabilityCache.intonationCurve = caps.intonation_curve === true;
        }
      }
    } catch (err) {
      // 拉不到就按默认（全部可用），入口照常显示，服务端返回可读错误兜底
    } finally {
      CapabilityCache.loaded = true;
    }
  }

  static reload(): void {
    CapabilityCache.loaded = false;
  }
}

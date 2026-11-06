import { AppConfig } from '../config/AppConfig';
import { AudioController } from '../audio/AudioController';
import { PracticeService } from './PracticeService';
import { ApiError, ApiErrorCode } from '../net/ApiError';

/**
 * 内置音色常量（`GET /api/tts/voices` 线上 404，按规格 chat-story.md §5.1 内置）。
 * 字段与服务端一致：id / label_zh / lang / sample（没有 gender 字段）。
 */
export class VoiceOption {
  id: string = '';
  labelZh: string = '';
  /** 'en' | 'zh' */
  lang: string = '';
  sample: string = '';

  constructor(id: string, labelZh: string, lang: string, sample: string) {
    this.id = id;
    this.labelZh = labelZh;
    this.lang = lang;
    this.sample = sample;
  }
}

/**
 * 媒体侧公共能力：音色常量、试听（TTS 落盘 → AudioController 播放）、
 * 站内静态资源 URL 拼接（形象预置图 `/avatars/presets/...` 不带 /api、无需鉴权）。
 */
export class MediaService {
  private static readonly VOICES: VoiceOption[] = [
    new VoiceOption('en-US-JennyNeural', 'Jenny · 英语女声（默认）', 'en',
      'Hello! Let\'s practice English together.'),
    new VoiceOption('en-US-AriaNeural', 'Aria · 英语女声（活泼）', 'en', 'Hi there! Ready for a story?'),
    new VoiceOption('en-US-AnaNeural', 'Ana · 英语童声', 'en', 'I like playing with my friends!'),
    new VoiceOption('en-US-GuyNeural', 'Guy · 英语男声', 'en', 'Good job! Let\'s try the next sentence.'),
    new VoiceOption('en-US-MichelleNeural', 'Michelle · 英语女声（温柔）', 'en',
      'Take your time. You are doing great.'),
    new VoiceOption('zh-CN-XiaoxiaoNeural', '晓晓 · 中文女声（默认）', 'zh', '你好呀，我们一起来练习吧。'),
    new VoiceOption('zh-CN-XiaoyiNeural', '晓伊 · 中文女声（温柔）', 'zh', '慢慢来，不着急。'),
    new VoiceOption('zh-CN-YunxiNeural', '云希 · 中文男声', 'zh', '太棒了，继续加油！'),
    new VoiceOption('zh-CN-YunjianNeural', '云健 · 中文男声（沉稳）', 'zh', '今天我们一起读一个小故事。')
  ];

  private static lastPreviewPath: string = '';

  /** 9 个内置音色（返回副本，避免页面误改常量）。 */
  static voices(): VoiceOption[] {
    const list: VoiceOption[] = [];
    for (let i = 0; i < MediaService.VOICES.length; i++) {
      list.push(MediaService.VOICES[i]);
    }
    return list;
  }

  /** 按 id 找音色；找不到返回 null（页面显示「默认音色」）。 */
  static findVoice(voiceId: string): VoiceOption | null {
    for (let i = 0; i < MediaService.VOICES.length; i++) {
      if (MediaService.VOICES[i].id === voiceId) {
        return MediaService.VOICES[i];
      }
    }
    return null;
  }

  /** 是否为内置音色 id（用于校验 PATCH settings.tts_voice）。 */
  static isKnownVoice(voiceId: string): boolean {
    return MediaService.findVoice(voiceId) !== null;
  }

  /**
   * 试听：POST /api/tts（JSON {text,voice,rate,format:'mp3'} → 二进制）落盘后播放。
   * 播放失败（被占用/无音频设备）抛 ApiError，由页面提示。
   * `onDone` 在播完或失败时回调（页面用来复位「试听中…」状态）。
   */
  static async preview(voiceId: string, sample: string, rate: string, onDone: (() => void) | null): Promise<void> {
    if (sample.length === 0) {
      throw ApiError.local(ApiErrorCode.BAD_REQUEST, '这个音色没有试听文本');
    }
    await MediaService.stopPreview();
    const path = await PracticeService.fetchTtsFile(sample, rate, voiceId, 'mp3');
    MediaService.lastPreviewPath = path;
    await AudioController.play(path, () => {
      MediaService.lastPreviewPath = '';
      if (onDone !== null) {
        onDone();
      }
    });
  }

  /** 停止试听（切音色 / 离开页面时调用）。 */
  static async stopPreview(): Promise<void> {
    MediaService.lastPreviewPath = '';
    await AudioController.stopPlayback();
  }

  static isPreviewing(): boolean {
    return MediaService.lastPreviewPath.length > 0 && AudioController.isPlaying();
  }

  /**
   * 站内静态资源 → 绝对 URL。
   * `/avatars/presets/c1-watercolor.png` → `{baseUrl}/avatars/presets/c1-watercolor.png`。
   * 已经是 http(s) 的原样返回；空串返回空串（调用方显示占位）。
   */
  static publicUrl(path: string): string {
    const trimmed = path.trim();
    if (trimmed.length === 0) {
      return '';
    }
    const lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    if (!trimmed.startsWith('/')) {
      return AppConfig.getBaseUrl() + '/' + trimmed;
    }
    return AppConfig.getBaseUrl() + trimmed;
  }

  /**
   * 形象图是否可安全公开展示：只有预置静态图（`/avatars/...`）可以。
   * 照片路径 `/api/avatar/image` 已按隐私策略关闭（403 policy_disabled），入口直接隐藏。
   */
  static isPublicAvatarPath(path: string): boolean {
    return path.startsWith('/avatars/');
  }
}

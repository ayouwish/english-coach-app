import { AppRuntime } from '../config/AppRuntime';
import { FileUtil } from '../util/FileUtil';

/**
 * 目录与缓存策略（docs/architecture.md §7、docs/audio.md §7）。
 *
 * filesDir/recordings/   当前录音（上传成功后按策略清理）
 * cacheDir/tts/          TTS 示范音
 * cacheDir/audio/        回放缓存
 *
 * M0 不做 LRU 与过期淘汰（见 README「待办」），只做「登出清空 + 启动清理 .part」。
 */
export class CacheService {
  static recordingsDir(): string {
    return AppRuntime.filesDir() + '/recordings';
  }

  static ttsDir(): string {
    return AppRuntime.cacheDir() + '/tts';
  }

  static audioDir(): string {
    return AppRuntime.cacheDir() + '/audio';
  }

  static ensureAll(): void {
    FileUtil.ensureDir(CacheService.recordingsDir());
    FileUtil.ensureDir(CacheService.ttsDir());
    FileUtil.ensureDir(CacheService.audioDir());
  }

  static cleanupOnBoot(): void {
    try {
      CacheService.ensureAll();
      FileUtil.removePartFiles(CacheService.ttsDir());
      FileUtil.removePartFiles(CacheService.audioDir());
    } catch (err) {
      // 启动清理失败不阻塞 App
    }
  }

  /** 登出 / 清缓存：删除 TTS 与回放音频（不动 baseUrl 等配置）。 */
  static clearAudioCache(): void {
    FileUtil.removeDir(CacheService.ttsDir());
    FileUtil.removeDir(CacheService.audioDir());
    CacheService.ensureAll();
  }

  /** 登出：额外清掉录音与待上传目录。 */
  static clearAll(): void {
    CacheService.clearAudioCache();
    FileUtil.removeDir(CacheService.recordingsDir());
    CacheService.ensureAll();
  }
}

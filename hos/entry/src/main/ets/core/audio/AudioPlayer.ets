import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiError, ApiErrorCode } from '../net/ApiError';
import { FileUtil } from '../util/FileUtil';

const DOMAIN: number = 0xEC00;
const TAG: string = 'Audio';

/**
 * AVPlayer 封装：**只播本地文件**（fd://）。
 *
 * 为什么不能直接播 URL（docs/audio.md §4.1）：
 * `/api/audio/:id`、`/api/tts` 都需要 `Authorization`，而 AVPlayer.url 不带请求头；
 * 且音频接口 `accept-ranges: none`，不适合边下边播。
 * 因此统一「先下载到 cacheDir → 再 fd:// 播放」。
 *
 * 【待确认】`audioRendererInfo` 的 `usage` 枚举（STREAM_USAGE_MUSIC）在目标机型上的路由行为；
 * 若被路由到听筒，改用 STREAM_USAGE_VOICE_ASSISTANT 或系统推荐值。
 */
export class AudioPlayer {
  private player: media.AVPlayer | null = null;
  private file: fileIo.File | null = null;
  private playing: boolean = false;
  private onCompleted: (() => void) | null = null;

  isPlaying(): boolean {
    return this.playing;
  }

  /**
   * 播放本地音频；`completed` 在自然播完后回调一次（失败不回调）。
   * 同一时刻只有一个播放器：调用前会先释放上一个。
   */
  async play(path: string, completed: (() => void) | null): Promise<void> {
    await this.release();
    if (!FileUtil.exists(path)) {
      throw ApiError.local(ApiErrorCode.PLAYBACK_FAILED, '音频文件不存在');
    }
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    } catch (err) {
      throw ApiError.local(ApiErrorCode.PLAYBACK_FAILED, '无法打开音频文件');
    }
    if (file === null) {
      throw ApiError.local(ApiErrorCode.PLAYBACK_FAILED, '无法打开音频文件');
    }
    this.file = file;
    this.onCompleted = completed;

    let player: media.AVPlayer;
    try {
      player = await media.createAVPlayer();
    } catch (err) {
      await this.release();
      throw ApiError.local(ApiErrorCode.PLAYBACK_FAILED, '播放器创建失败');
    }
    this.player = player;
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (state === 'completed') {
        this.handleCompleted();
      }
    });
    player.on('error', (err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'player error code=%{public}d', err.code);
      this.playing = false;
      void this.release();
    });

    player.url = 'fd://' + file.fd.toString();
    const rendererInfo: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
      rendererFlags: 0
    };
    player.audioRendererInfo = rendererInfo;
    try {
      await player.prepare();
      await player.play();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'prepare/play failed code=%{public}d', e.code);
      await this.release();
      throw ApiError.local(ApiErrorCode.PLAYBACK_FAILED, '声音播放失败');
    }
    this.playing = true;
  }

  async stop(): Promise<void> {
    await this.release();
  }

  private handleCompleted(): void {
    this.playing = false;
    const callback = this.onCompleted;
    this.onCompleted = null;
    void this.release();
    if (callback !== null) {
      callback();
    }
  }

  /** 释放 player 与 fd。重复调用安全。 */
  async release(): Promise<void> {
    this.playing = false;
    this.onCompleted = null;
    const player = this.player;
    this.player = null;
    if (player !== null) {
      try {
        await player.release();
      } catch (err) {
        const e = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'player.release failed code=%{public}d', e.code);
      }
    }
    const file = this.file;
    this.file = null;
    if (file !== null) {
      try {
        fileIo.closeSync(file);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close player fd failed');
      }
    }
  }
}

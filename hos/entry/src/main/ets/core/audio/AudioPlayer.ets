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
 * 2026-11-03 重写：改用**状态机**驱动（initialized → 设置 audioRendererInfo → prepare →
 * prepared → play），不再在 url 赋值后立刻同步 prepare。
 * Web 端能播而 App 不能播时的常见原因是属性设置时机与 prepare 的竞态，
 * 这里每一步都打 hilog，真机日志可直接定位（tag=Audio）。
 */
export class AudioPlayer {
  private player: media.AVPlayer | null = null;
  private file: fileIo.File | null = null;
  private playing: boolean = false;
  private onCompleted: (() => void) | null = null;
  /** 最近一次播放的状态/错误，页面可读出来做诊断展示 */
  private lastState: string = '';
  private lastError: string = '';

  isPlaying(): boolean {
    return this.playing;
  }

  stateText(): string {
    return this.lastError.length > 0 ? this.lastError : this.lastState;
  }

  async play(path: string, completed: (() => void) | null): Promise<void> {
    await this.release();
    if (!FileUtil.exists(path)) {
      throw ApiError.local(ApiErrorCode.PLAYBACK_FAILED, '音频文件不存在');
    }
    const size = FileUtil.sizeOf(path);
    hilog.info(DOMAIN, TAG, 'play file=%{public}s size=%{public}d', path, size);
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
    this.lastState = 'idle';
    this.lastError = '';

    let player: media.AVPlayer;
    try {
      player = await media.createAVPlayer();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'createAVPlayer failed code=%{public}d', e.code);
      await this.release();
      throw ApiError.local(ApiErrorCode.PLAYBACK_FAILED, '播放器创建失败');
    }
    this.player = player;

    // 单次播放的收尾标记：completed / error 只允许走一次
    let finished = false;
    const finish = (failed: boolean, detail: string): void => {
      if (finished) {
        return;
      }
      finished = true;
      this.playing = false;
      this.lastState = failed ? 'error' : 'completed';
      const callback = this.onCompleted;
      this.onCompleted = null;
      void this.release();
      if (callback !== null && !failed) {
        callback();
      }
    };

    player.on('stateChange', (state: string, reason: number) => {
      this.lastState = state;
      hilog.info(DOMAIN, TAG, 'state=%{public}s reason=%{public}d', state, reason);
      if (state === 'initialized') {
        // audioRendererInfo 必须在 prepare 之前设置；放在 initialized 里最稳（属性设置时机对齐官方示例）
        const rendererInfo: audio.AudioRendererInfo = {
          usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
          rendererFlags: 0
        };
        try {
          player.audioRendererInfo = rendererInfo;
        } catch (err) {
          const e = err as BusinessError;
          hilog.error(DOMAIN, TAG, 'set audioRendererInfo failed code=%{public}d', e.code);
        }
        player.prepare().catch((err: BusinessError) => {
          this.lastError = 'prepare failed ' + err.code.toString();
          hilog.error(DOMAIN, TAG, 'prepare failed code=%{public}d', err.code);
          finish(true, this.lastError);
        });
      } else if (state === 'prepared') {
        this.playing = true;
        player.play().catch((err: BusinessError) => {
          this.lastError = 'play failed ' + err.code.toString();
          hilog.error(DOMAIN, TAG, 'play failed code=%{public}d', err.code);
          finish(true, this.lastError);
        });
      } else if (state === 'completed') {
        hilog.info(DOMAIN, TAG, 'playback completed');
        finish(false, 'completed');
      }
    });
    player.on('error', (err: BusinessError) => {
      this.lastError = 'player error ' + err.code.toString();
      hilog.error(DOMAIN, TAG, 'player error code=%{public}d', err.code);
      finish(true, this.lastError);
    });

    try {
      player.url = 'fd://' + file.fd.toString();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'set url failed code=%{public}d', e.code);
      await this.release();
      throw ApiError.local(ApiErrorCode.PLAYBACK_FAILED, '音频地址设置失败');
    }
  }

  async stop(): Promise<void> {
    await this.release();
  }

  /** 释放 player 与 fd。重复调用安全。 */
  async release(): Promise<void> {
    this.playing = false;
    this.onCompleted = null;
    const player = this.player;
    this.player = null;
    if (player !== null) {
      try {
        player.off('stateChange');
      } catch (err) {
        // 忽略：未注册回调时 off 会抛
      }
      try {
        player.off('error');
      } catch (err) {
        // 同上
      }
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

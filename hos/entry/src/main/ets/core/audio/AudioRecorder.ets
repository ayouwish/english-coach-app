import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { AppRuntime } from '../config/AppRuntime';
import { ApiError, ApiErrorCode } from '../net/ApiError';
import { CacheService } from '../service/CacheService';
import { FileUtil } from '../util/FileUtil';

const DOMAIN: number = 0xEC00;
const TAG: string = 'Audio';

/** 录音结果（上传需要的全部信息）。 */
export class RecordingResult {
  path: string = '';
  durationMs: number = 0;
  sizeBytes: number = 0;
}

/**
 * 麦克风权限。
 *
 * 时机（docs/audio.md §2）：用户第一次点「开始说」时申请；每次录音前都检查
 * （用户可能在系统设置里撤销）。拒绝后不再重复弹系统框，改为引导到设置。
 *
 * 【待确认】`requestPermissionOnSetting` 自 API 12 提供；若本机 SDK 缺失，
 * 回退为提示用户手动前往「设置 → 隐私 → 权限管理 → 应用 → 家庭英语教练 → 麦克风」。
 */
export class MicPermission {
  static readonly PERMISSION: Permissions = 'ohos.permission.MICROPHONE';

  /** true = 已授权（已授权时系统不会弹窗，直接返回 0）。 */
  static async request(): Promise<boolean> {
    const ctx = AppRuntime.context();
    if (ctx === null) {
      return false;
    }
    const atManager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = [MicPermission.PERMISSION];
    try {
      const result = await atManager.requestPermissionsFromUser(ctx, permissions);
      const authResults = result.authResults;
      if (authResults.length === 0) {
        return false;
      }
      return authResults[0] === 0;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestPermissionsFromUser failed code=%{public}d', e.code);
      return false;
    }
  }

  /** 打开系统权限设置页；返回操作后是否已授权（失败时页面提示手动路径）。 */
  static async openSettings(): Promise<boolean> {
    const ctx = AppRuntime.context();
    if (ctx === null) {
      return false;
    }
    const atManager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = [MicPermission.PERMISSION];
    try {
      const statuses = await atManager.requestPermissionOnSetting(ctx, permissions);
      if (statuses.length === 0) {
        return false;
      }
      return statuses[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestPermissionOnSetting failed code=%{public}d', e.code);
      return false;
    }
  }
}

/**
 * AVRecorder 封装：m4a / AAC-LC / 16kHz / 单声道 / 65kbps（docs/audio.md §3）。
 *
 * 参数无回退分支：准备/启动失败只提示重试，不静默换码率（否则评分口径不一致）。
 * 文件落 `filesDir/recordings/`，上传前做大小/时长校验。
 *
 * 【待确认】API 20 的 `media.AVRecorderProfile` 字段名：`audioChannels`（不是 audioChannelCount）、
 * `audioSampleRate`、`audioBitrate`、`audioCodec`、`fileFormat`；`aacProfile` 属 API 22+，这里不设置。
 */
export class AudioRecorder {
  private recorder: media.AVRecorder | null = null;
  private file: fileIo.File | null = null;
  private path: string = '';
  private startedAt: number = 0;
  private recording: boolean = false;

  isRecording(): boolean {
    return this.recording;
  }

  currentPath(): string {
    return this.path;
  }

  async start(): Promise<void> {
    if (this.recording) {
      return;
    }
    const granted = await MicPermission.request();
    if (!granted) {
      throw ApiError.local(ApiErrorCode.MIC_DENIED, '麦克风未授权');
    }
    CacheService.ensureAll();
    const path = CacheService.recordingsDir() + '/rec_' + Date.now().toString() + '.m4a';
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    } catch (err) {
      throw ApiError.local(ApiErrorCode.RECORD_FAILED, '无法创建录音文件');
    }
    if (file === null) {
      throw ApiError.local(ApiErrorCode.RECORD_FAILED, '无法创建录音文件');
    }
    this.file = file;
    this.path = path;

    let recorder: media.AVRecorder;
    try {
      recorder = await media.createAVRecorder();
    } catch (err) {
      await this.release();
      throw ApiError.local(ApiErrorCode.RECORD_FAILED, '录音功能暂时不可用');
    }
    this.recorder = recorder;
    recorder.on('stateChange', (state: media.AVRecorderState) => {
      hilog.debug(DOMAIN, TAG, 'recorder state=%{public}s', state);
    });
    recorder.on('error', (err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'recorder error code=%{public}d', err.code);
      this.recording = false;
    });

    const profile: media.AVRecorderProfile = {
      audioBitrate: 65000,
      audioChannels: 1,
      audioCodec: media.CodecMimeType.AUDIO_AAC,
      audioSampleRate: 16000,
      fileFormat: media.ContainerFormatType.CFT_MPEG_4A
    };
    const config: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      profile: profile,
      url: 'fd://' + file.fd.toString()
    };
    try {
      await recorder.prepare(config);
      await recorder.start();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'prepare/start failed code=%{public}d', e.code);
      await this.release();
      throw ApiError.local(ApiErrorCode.MIC_UNAVAILABLE, '录音启动失败，请关闭其他录音应用后重试');
    }
    this.startedAt = Date.now();
    this.recording = true;
  }

  /** 停止并返回录音结果；过短/空文件在这里就拦掉，不提交评测。 */
  async stop(): Promise<RecordingResult> {
    const recorder = this.recorder;
    if (recorder === null || !this.recording) {
      await this.release();
      throw ApiError.local(ApiErrorCode.RECORD_FAILED, '当前没有在录音');
    }
    const durationMs = Math.max(0, Date.now() - this.startedAt);
    try {
      await recorder.stop();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'recorder.stop failed code=%{public}d', e.code);
    }
    const path = this.path;
    await this.release();

    const sizeBytes = FileUtil.sizeOf(path);
    if (sizeBytes <= 0) {
      FileUtil.remove(path);
      throw ApiError.local(ApiErrorCode.RECORD_FAILED, '录音文件为空，请重试');
    }
    if (durationMs < 600) {
      FileUtil.remove(path);
      throw ApiError.local(ApiErrorCode.RECORD_TOO_SHORT, '录音太短');
    }
    if (sizeBytes > 12 * 1024 * 1024) {
      FileUtil.remove(path);
      throw ApiError.local(ApiErrorCode.RECORD_TOO_LARGE, '录音超过 12MB');
    }
    const result = new RecordingResult();
    result.path = path;
    result.durationMs = durationMs;
    result.sizeBytes = sizeBytes;
    return result;
  }

  /** 取消：停止、删除文件、释放，不提交。 */
  async cancel(): Promise<void> {
    const path = this.path;
    if (this.recorder !== null && this.recording) {
      try {
        await this.recorder.stop();
      } catch (err) {
        // 已经停止/异常时忽略
      }
    }
    await this.release();
    if (path.length > 0) {
      FileUtil.remove(path);
    }
  }

  /** 释放 recorder 与 fd；任何路径都必须走到这里，避免 fd 泄漏。 */
  private async release(): Promise<void> {
    this.recording = false;
    const recorder = this.recorder;
    this.recorder = null;
    if (recorder !== null) {
      try {
        await recorder.release();
      } catch (err) {
        const e = err as BusinessError;
        hilog.warn(DOMAIN, TAG, 'recorder.release failed code=%{public}d', e.code);
      }
    }
    const file = this.file;
    this.file = null;
    if (file !== null) {
      try {
        fileIo.closeSync(file);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'close recorder fd failed');
      }
    }
  }
}

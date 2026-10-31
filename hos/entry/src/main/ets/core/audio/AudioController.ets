import { AudioPlayer } from './AudioPlayer';
import { AudioRecorder, RecordingResult } from './AudioRecorder';
import { ApiError, ApiErrorCode } from '../net/ApiError';

/** 音频子系统状态：任何时刻最多一个录音器、一个播放器。 */
export enum AudioMode {
  IDLE = 0,
  RECORDING = 1,
  PLAYING = 2
}

/**
 * 录音/播放协调器（docs/audio.md §5）。页面**不得**直接 createAVRecorder/createAVPlayer。
 *
 * 互斥规则：
 * - 录音时来播放请求 → 拒绝并提示「先说完这一句」（不偷偷停录音）；
 * - 播放时来录音请求 → 先停播放再开录（用户明确点了「开始说」）；
 * - 页面销毁/切后台 → stopAll()（录音丢弃）。
 */
export class AudioController {
  private static readonly player: AudioPlayer = new AudioPlayer();
  private static readonly recorder: AudioRecorder = new AudioRecorder();
  private static mode: AudioMode = AudioMode.IDLE;

  static currentMode(): AudioMode {
    return AudioController.mode;
  }

  static isRecording(): boolean {
    return AudioController.recorder.isRecording();
  }

  static isPlaying(): boolean {
    return AudioController.player.isPlaying();
  }

  static async startRecording(): Promise<void> {
    if (AudioController.recorder.isRecording()) {
      return;
    }
    // 录音前必须停播放：否则蓝牙会切到通话模式，录音发闷（验收清单 B 段）
    await AudioController.player.stop();
    await AudioController.recorder.start();
    AudioController.mode = AudioMode.RECORDING;
  }

  static async stopRecording(): Promise<RecordingResult> {
    const result = await AudioController.recorder.stop();
    AudioController.mode = AudioMode.IDLE;
    return result;
  }

  static async cancelRecording(): Promise<void> {
    await AudioController.recorder.cancel();
    AudioController.mode = AudioMode.IDLE;
  }

  static async play(path: string, onCompleted: (() => void) | null): Promise<void> {
    if (AudioController.recorder.isRecording()) {
      throw ApiError.local(ApiErrorCode.PLAYBACK_FAILED, '正在录音，先说完这一句');
    }
    await AudioController.player.play(path, onCompleted);
    AudioController.mode = AudioMode.PLAYING;
  }

  static async stopPlayback(): Promise<void> {
    await AudioController.player.stop();
    if (AudioController.mode === AudioMode.PLAYING) {
      AudioController.mode = AudioMode.IDLE;
    }
  }

  /** 页面销毁/切后台：丢弃录音、停止播放、释放 fd。 */
  static async stopAll(): Promise<void> {
    await AudioController.recorder.cancel();
    await AudioController.player.stop();
    AudioController.mode = AudioMode.IDLE;
  }
}

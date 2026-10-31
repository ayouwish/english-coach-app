import { ApiErrorCode } from '../core/net/ApiError';
import { ErrorMapper, UiError } from '../core/error/UiError';
import { AttemptResponseDto, FeedbackDto, FeedbackPointDto, PronounceResultDto, SentenceDto, ScoresDto } from '../core/net/Dtos';
import { PracticeService } from '../core/service/PracticeService';
import { SessionStore } from '../core/session/SessionStore';
import { AudioController } from '../core/audio/AudioController';
import { MicPermission, RecordingResult } from '../core/audio/AudioRecorder';
import { FileUtil } from '../core/util/FileUtil';

/** 记住「上一次失败的操作」，让错误条上的按钮能真正重试对应动作。 */
export enum PracticeAction {
  NONE = 0,
  DEMO = 1,
  FOLLOW = 2,
  RECORD = 3,
  RETRY_EVALUATE = 4
}

/**
 * 跟读页状态（一次一句话：示范 → 录音 → 上传 → 结果）。
 *
 * 设计要点：
 * - 可观察字段一律「扁平化 + 基本类型」，页面不处理 null DTO，儿童规则由页面用 EcScore 判定；
 * - 录音/播放全部经 AudioController（互斥 + fd 释放）；
 * - `/attempts` 是**非幂等**写操作：网络失败不自动重发（避免重复计费），degraded 才给「重试评测」。
 */
@Observed
export class PracticeVM {
  // ---- 选中句子（扁平化）
  hasSelection: boolean = false;
  text: string = '';
  translation: string = '';
  focusPhonemes: string[] = [];
  level: string = '';
  isChild: boolean = false;
  private sentenceId: string = '';

  // ---- 音频/提交状态
  ttsLoading: boolean = false;
  playing: boolean = false;
  preparing: boolean = false;
  recording: boolean = false;
  submitting: boolean = false;
  elapsedMs: number = 0;
  progressText: string = '';

  // ---- 错误
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');
  errorActionLabel: string = '';

  // ---- 结果（扁平化）
  hasResult: boolean = false;
  scorePron: number | null = null;
  scoreAccuracy: number | null = null;
  scoreFluency: number | null = null;
  scoreCompleteness: number | null = null;
  scoreProsody: number | null = null;
  recognizedText: string = '';
  noSpeech: boolean = false;
  lowSnr: boolean = false;
  feedbackSummary: string = '';
  feedbackPraise: string = '';
  feedbackClosing: string = '';
  pointTitles: string[] = [];
  pointHows: string[] = [];
  degraded: boolean = false;
  canRetryEvaluate: boolean = false;

  // ---- 内部
  private attemptId: string = '';
  private ttsPath: string = '';
  private timerId: number = -1;
  private progressTimerId: number = -1;
  private recordStartedAt: number = 0;
  private lastAction: PracticeAction = PracticeAction.NONE;

  setup(sentence: SentenceDto, level: string, isChild: boolean): void {
    this.sentenceId = sentence.id;
    this.text = sentence.text;
    const translation = sentence.translation_zh;
    this.translation = translation === undefined ? '' : translation;
    const focus = sentence.focus_phonemes;
    this.focusPhonemes = (focus === undefined || isChild) ? [] : focus;
    this.level = level;
    this.isChild = isChild;
    this.hasSelection = true;
    this.ttsPath = '';
    this.resetResult();
    this.clearError();
  }

  // ------------------------------------------------------------------ 播放示范

  /** 听示范；autoRecord=true 时播完自动开录（「跟我读」）。 */
  async playDemo(autoRecord: boolean): Promise<void> {
    if (!this.hasSelection || this.submitting) {
      return;
    }
    if (AudioController.isRecording()) {
      this.setError(new UiError('', '正在录音，先点「说完啦」再听示范', '', false, ApiErrorCode.RECORD_FAILED), '');
      return;
    }
    this.clearError();
    this.ttsLoading = true;
    this.playing = false;
    try {
      const path = await this.ensureTtsPath();
      this.ttsLoading = false;
      this.playing = true;
      await AudioController.play(path, () => {
        this.playing = false;
        if (autoRecord) {
          // 播完等 250ms 再开麦：让音频路由从播放切回麦克风，避免开头吞字
          setTimeout(() => {
            void this.startRecording();
          }, 250);
        }
      });
    } catch (err) {
      this.ttsLoading = false;
      this.playing = false;
      this.lastAction = autoRecord ? PracticeAction.FOLLOW : PracticeAction.DEMO;
      this.handleError(err as Error);
    }
  }

  async stopPlayback(): Promise<void> {
    await AudioController.stopPlayback();
    this.playing = false;
  }

  private async ensureTtsPath(): Promise<string> {
    if (this.ttsPath.length > 0 && FileUtil.exists(this.ttsPath)) {
      return this.ttsPath;
    }
    const rate = this.isChild ? 'slow' : 'normal';
    const path = await PracticeService.fetchTts(this.text, rate);
    this.ttsPath = path;
    return path;
  }

  // ------------------------------------------------------------------ 录音

  async startRecording(): Promise<void> {
    if (!this.hasSelection || this.recording || this.preparing || this.submitting) {
      return;
    }
    this.clearError();
    this.preparing = true;
    this.lastAction = PracticeAction.RECORD;
    try {
      await AudioController.startRecording();
      this.recording = true;
      this.recordStartedAt = Date.now();
      this.elapsedMs = 0;
      this.startTimer();
    } catch (err) {
      this.recording = false;
      this.handleError(err as Error);
    } finally {
      this.preparing = false;
    }
  }

  /** 说完啦：停止 → 本地校验 → 上传评测。 */
  async stopRecordingAndSubmit(): Promise<void> {
    if (!this.recording) {
      return;
    }
    this.recording = false;
    this.stopTimer();
    let recorded: RecordingResult | null = null;
    try {
      recorded = await AudioController.stopRecording();
    } catch (err) {
      this.handleError(err as Error);
      return;
    }
    if (recorded === null) {
      return;
    }
    await this.submit(recorded);
  }

  async cancelRecording(): Promise<void> {
    this.recording = false;
    this.stopTimer();
    this.elapsedMs = 0;
    await AudioController.cancelRecording();
  }

  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval(() => {
      this.elapsedMs = Date.now() - this.recordStartedAt;
      if (this.elapsedMs >= 60000) {
        // 60s 自动停止并提交（65kbps 下约 0.49MB，远小于 12MB 上限）
        void this.stopRecordingAndSubmit();
      }
    }, 200);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // ------------------------------------------------------------------ 提交

  private async submit(recorded: RecordingResult): Promise<void> {
    if (!this.hasSelection) {
      return;
    }
    this.submitting = true;
    this.hasError = false;
    this.hasResult = false;
    this.clearError();
    const startedAt = Date.now();
    this.progressText = '上传录音…';
    this.startProgressTimer(startedAt);
    try {
      const resp = await PracticeService.evaluate(recorded.path, this.sentenceId, this.text, recorded.durationMs);
      this.applyAttempt(resp);
      // 服务端已保存录音，本地副本可以删（失败也不阻塞）
      FileUtil.remove(recorded.path);
    } catch (err) {
      this.lastAction = PracticeAction.RECORD;
      this.handleError(err as Error);
    } finally {
      this.submitting = false;
      this.progressText = '';
      this.stopProgressTimer();
    }
  }

  /** degraded 时用已存录音重评（不重新上传、不重复计费）。 */
  async retryEvaluate(): Promise<void> {
    if (this.attemptId.length === 0 || this.submitting) {
      return;
    }
    this.submitting = true;
    this.clearError();
    const startedAt = Date.now();
    this.progressText = '重新评测…';
    this.startProgressTimer(startedAt);
    try {
      const resp = await PracticeService.retryAttempt(this.attemptId);
      this.applyAttempt(resp);
    } catch (err) {
      this.lastAction = PracticeAction.RETRY_EVALUATE;
      this.handleError(err as Error);
    } finally {
      this.submitting = false;
      this.progressText = '';
      this.stopProgressTimer();
    }
  }

  /** 进度文案按耗时切换，不显示假百分比。 */
  private startProgressTimer(startedAt: number): void {
    this.stopProgressTimer();
    this.progressTimerId = setInterval(() => {
      const elapsed = Date.now() - startedAt;
      if (elapsed > 20000) {
        this.progressText = '生成建议…';
      } else if (elapsed > 8000) {
        this.progressText = '评分中…';
      } else if (elapsed > 2000) {
        this.progressText = '识别中…';
      }
    }, 1000);
  }

  private stopProgressTimer(): void {
    if (this.progressTimerId >= 0) {
      clearInterval(this.progressTimerId);
      this.progressTimerId = -1;
    }
  }

  private applyAttempt(resp: AttemptResponseDto): void {
    this.attemptId = resp.attempt_id;
    this.degraded = resp.degraded === true;
    this.canRetryEvaluate = this.degraded && resp.retryable !== false;
    const usage = resp.usage;
    if (usage !== undefined) {
      SessionStore.updateUsage(usage);
    }
    const result = resp.result;
    if (result === undefined || result === null) {
      // 盲测 / 降级：没有分数。降级时给出「已保存，可重试评测」
      this.hasResult = false;
      if (this.degraded) {
        const message = this.isChild
          ? '录音先存好啦，等评分老师有空再打分'
          : (resp.message !== undefined && resp.message.length > 0
            ? resp.message
            : '评测服务暂时不可用，录音已保存，稍后可重试');
        this.setError(new UiError('', message, this.canRetryEvaluate ? '重试评测' : '', this.canRetryEvaluate,
          ApiErrorCode.PROVIDER_ERROR), this.canRetryEvaluate ? '重试评测' : '');
      }
      return;
    }
    this.hasResult = true;
    this.applyScores(result);
    const recognized = result.recognized_text;
    this.recognizedText = recognized === undefined ? '' : recognized;
    this.noSpeech = this.recognizedText.trim().length < 2;
    this.lowSnr = this.hasWarning(result, 'low_snr');
    this.applyFeedback(resp.feedback);
    if (this.degraded) {
      this.setError(new UiError('', '评分服务刚刚不稳定，这条结果是降级结果，可以点「重试评测」',
        '重试评测', true, ApiErrorCode.PROVIDER_ERROR), '重试评测');
    }
  }

  private applyScores(result: PronounceResultDto): void {
    const scores = result.scores;
    if (scores === undefined) {
      this.scorePron = null;
      this.scoreAccuracy = null;
      this.scoreFluency = null;
      this.scoreCompleteness = null;
      this.scoreProsody = null;
      return;
    }
    this.scorePron = PracticeVM.scoreOf(scores, 'pron');
    this.scoreAccuracy = PracticeVM.scoreOf(scores, 'accuracy');
    this.scoreFluency = PracticeVM.scoreOf(scores, 'fluency');
    this.scoreCompleteness = PracticeVM.scoreOf(scores, 'completeness');
    this.scoreProsody = PracticeVM.scoreOf(scores, 'prosody');
  }

  private static scoreOf(scores: ScoresDto, key: string): number | null {
    let value: number | null | undefined = null;
    if (key === 'pron') {
      value = scores.pron;
    } else if (key === 'accuracy') {
      value = scores.accuracy;
    } else if (key === 'fluency') {
      value = scores.fluency;
    } else if (key === 'completeness') {
      value = scores.completeness;
    } else if (key === 'prosody') {
      value = scores.prosody;
    }
    if (value === undefined || value === null) {
      return null;
    }
    return value;
  }

  private applyFeedback(feedback: FeedbackDto | null | undefined): void {
    this.feedbackSummary = '';
    this.feedbackPraise = '';
    this.feedbackClosing = '';
    this.pointTitles = [];
    this.pointHows = [];
    if (feedback === undefined || feedback === null) {
      return;
    }
    if (feedback.summary !== undefined) {
      this.feedbackSummary = feedback.summary;
    }
    if (feedback.praise !== undefined) {
      this.feedbackPraise = feedback.praise;
    }
    if (feedback.closing !== undefined) {
      this.feedbackClosing = feedback.closing;
    }
    const points = feedback.points;
    // 儿童：不展示纠错细节，只用 summary/praise 决定鼓励语气（服务端文案已儿童化）
    if (points === undefined || this.isChild) {
      return;
    }
    const titles: string[] = [];
    const hows: string[] = [];
    for (let i = 0; i < points.length && i < 2; i++) {
      const point: FeedbackPointDto = points[i];
      titles.push(point.title === undefined ? '' : point.title);
      hows.push(point.how === undefined ? '' : point.how);
    }
    this.pointTitles = titles;
    this.pointHows = hows;
  }

  private hasWarning(result: PronounceResultDto, key: string): boolean {
    const warnings = result.warnings;
    if (warnings === undefined) {
      return false;
    }
    return warnings.indexOf(key) >= 0;
  }

  // ------------------------------------------------------------------ 错误 / 生命周期

  /** 错误条上的动作：麦克风被拒 → 系统设置；其它按「上次操作」重试。 */
  async onErrorAction(): Promise<void> {
    if (this.errorActionLabel.length === 0) {
      return;
    }
    if (this.error.code === ApiErrorCode.MIC_DENIED) {
      const granted = await MicPermission.openSettings();
      if (granted) {
        this.clearError();
      }
      return;
    }
    const action = this.lastAction;
    this.clearError();
    if (action === PracticeAction.DEMO || action === PracticeAction.FOLLOW) {
      await this.playDemo(action === PracticeAction.FOLLOW);
    } else if (action === PracticeAction.RETRY_EVALUATE) {
      await this.retryEvaluate();
    }
  }

  clearError(): void {
    this.hasError = false;
    this.errorActionLabel = '';
  }

  private setError(error: UiError, actionLabel: string): void {
    this.error = error;
    this.hasError = true;
    this.errorActionLabel = actionLabel;
  }

  private handleError(err: Error): void {
    const ui = ErrorMapper.from(err, this.isChild);
    let actionLabel = '';
    if (ui.code === ApiErrorCode.MIC_DENIED) {
      actionLabel = '去设置';
    } else if (this.lastAction === PracticeAction.DEMO || this.lastAction === PracticeAction.FOLLOW) {
      actionLabel = this.isChild ? '再试一次' : '重试';
    } else if (this.canRetryEvaluate) {
      actionLabel = '重试评测';
    }
    this.setError(ui, actionLabel);
  }

  resetResult(): void {
    this.hasResult = false;
    this.scorePron = null;
    this.scoreAccuracy = null;
    this.scoreFluency = null;
    this.scoreCompleteness = null;
    this.scoreProsody = null;
    this.recognizedText = '';
    this.noSpeech = false;
    this.lowSnr = false;
    this.feedbackSummary = '';
    this.feedbackPraise = '';
    this.feedbackClosing = '';
    this.pointTitles = [];
    this.pointHows = [];
    this.degraded = false;
    this.canRetryEvaluate = false;
    this.attemptId = '';
  }

  /** 页面销毁/切后台：停计时、丢录音、停播放、释放 fd。 */
  dispose(): void {
    this.stopTimer();
    this.stopProgressTimer();
    this.recording = false;
    this.playing = false;
    void AudioController.stopAll();
  }
}

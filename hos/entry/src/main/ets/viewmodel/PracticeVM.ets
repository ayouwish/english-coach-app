import { ApiErrorCode } from '../core/net/ApiError';
import { UiError } from '../core/error/UiError';
import {
  AttemptItemDto,
  AttemptResponseDto,
  FeedbackDto,
  FeedbackPointDto,
  IntonationDto,
  IssueDto,
  PronounceResultDto,
  ScoresDto,
  SentenceDto,
  WordScoreDto
} from '../core/net/Dtos';
import { PracticeService } from '../core/service/PracticeService';
import { SessionStore } from '../core/session/SessionStore';
import { AudioController } from '../core/audio/AudioController';
import { MicPermission, RecordingResult } from '../core/audio/AudioRecorder';
import { CacheService } from '../core/service/CacheService';
import { FileUtil } from '../core/util/FileUtil';
import { BlindRuntime } from '../core/session/BlindRuntime';
import { StatsService } from '../core/service/StatsService';
import { PhonemeHint, PhonemeHints } from '../core/content/PhonemeHints';
import { AccountPrefs } from '../core/content/AccountPrefs';

/** 结果详情里的「需要纠正的地方」卡片。 */
export class ResultIssue {
  title: string = '';
  word: string = '';
  expected: string = '';
  actual: string = '';
  score: number = -1;
  why: string = '';
  how: string = '';
  words: string = '';
}

/** 记住「上一次失败的操作」，让错误条上的按钮能真正重试对应动作。 */
export enum PracticeAction {
  NONE = 0,
  DEMO = 1,
  FOLLOW = 2,
  RECORD = 3,
  RETRY_EVALUATE = 4,
  PLAY_RECORDING = 5
}

/**
 * 跟读页状态（卡片流：一次一句话，上下滑动切换）。
 *
 * 设计要点：
 * - 可观察字段一律扁平化 + 基本类型，页面不处理 null DTO；
 * - 结果区字段覆盖 web 结果页的 8 个区块（总分/子项/词级/音素/语调/纠错/反馈/历史）；
 * - `/attempts` 是非幂等写操作：网络失败不自动重发（避免重复计费），degraded 才给「重试评测」。
 */
@Observed
export class PracticeVM {
  // ---- 句子列表 / 当前句
  sentences: SentenceDto[] = [];
  index: number = 0;
  hasSelection: boolean = false;
  text: string = '';
  translation: string = '';
  focusPhonemes: string[] = [];
  level: string = 'A1';
  isChild: boolean = false;
  private sentenceId: string = '';

  // ---- 音频/提交状态
  ttsLoading: boolean = false;
  playing: boolean = false;
  playingRecording: boolean = false;
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
  scorePron: number = -1;
  scoreAccuracy: number = -1;
  scoreFluency: number = -1;
  scoreCompleteness: number = -1;
  scoreProsody: number = -1;
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

  // ---- 词级 / 音素 / 语调
  wordTexts: string[] = [];
  wordScores: number[] = [];
  wordErrors: string[] = [];
  /** 句子顺序的原始词明细（含音素），详情页「逐词得分/音素明细」用 */
  wordDetails: WordScoreDto[] = [];
  /** 需要练的词（按分数升序，最多 9 个） */
  worstWordTexts: string[] = [];
  worstWordScores: number[] = [];
  /** 音素明细 chips */
  phonemeChipLabels: string[] = [];
  phonemeChipScores: number[] = [];
  /** 这一句的问题（issues 的唯一音素 chips） */
  issueChipLabels: string[] = [];
  issueChipScores: number[] = [];
  issueCards: ResultIssue[] = [];
  /** 纠错要点的 why / practice words（与 pointTitles 对齐） */
  pointWhys: string[] = [];
  pointWords: string[] = [];
  issueTexts: string[] = [];
  intonationAvailable: boolean = false;
  intonationDistance: string = '';
  regionTexts: string[] = [];
  userF0: Array<Array<number | null>> = [];
  refF0: Array<Array<number | null>> = [];

  // ---- 结果元信息（Web 结果页底部那行）
  resultProvider: string = '';
  resultGranularity: string = '';
  durationText: string = '';
  refText: string = '';
  attemptIdText: string = '';

  // ---- 单句历史（进步曲线）
  historyScores: number[] = [];
  historyTimes: string[] = [];
  historyAttemptIds: string[] = [];
  historyLabels: string[] = [];
  historyFirst: number = -1;
  historyLast: number = -1;
  historyLoading: boolean = false;
  historyLoaded: boolean = false;
  /** 正在回放的历史录音 id（空 = 无） */
  playingHistoryId: string = '';

  // ---- 盲测模式（/blind-tests + /attempts 带 blind_test_id）
  blindActive: boolean = false;
  blindTotal: number = 0;
  blindSubmitted: number = 0;
  blindScored: number = 0;
  blindPending: number = 0;
  blindDone: boolean = false;
  blindNotice: string = '';

  // ---- 内部
  private attemptId: string = '';
  private ttsPath: string = '';
  private recordPath: string = '';
  private timerId: number = -1;
  private progressTimerId: number = -1;
  private blindTimerId: number = -1;
  private recordStartedAt: number = 0;
  private lastAction: PracticeAction = PracticeAction.NONE;

  /** 初始化卡片流（sentences 为空时退化为单句）。 */
  setup(sentences: SentenceDto[], index: number, level: string, isChild: boolean): void {
    this.sentences = sentences;
    this.level = level;
    this.isChild = isChild;
    this.index = index;
    // 普通练习默认退出盲测模式（盲测由 setupBlind 显式进入）
    this.blindActive = false;
    this.blindDone = false;
    this.blindNotice = '';
    this.stopBlindPoll();
    this.applyCurrent();
    this.warmupNeighbors();
  }

  /** 进入盲测模式：句子由 BlindRuntime.loadSentences() 提供，界面不显示任何分数。 */
  setupBlind(sentences: SentenceDto[]): void {
    this.setup(sentences, 0, this.level, this.isChild);
    this.blindActive = BlindRuntime.active;
    this.blindTotal = BlindRuntime.total;
    this.blindSubmitted = BlindRuntime.submitted;
    this.blindScored = BlindRuntime.scored;
    this.blindPending = BlindRuntime.pending;
    this.blindDone = this.blindSubmitted >= this.blindTotal && this.blindTotal > 0;
    this.blindNotice = '';
    this.startBlindPoll();
  }

  /** 盲测提交后的本地进度（不展示分数，只推进到下一句）。 */
  private afterBlindSubmit(): void {
    const allDone = BlindRuntime.markSubmitted();
    this.blindSubmitted = BlindRuntime.submitted;
    this.blindDone = allDone;
    this.hasResult = false;
    this.clearError();
    if (allDone) {
      this.blindNotice = '全部读完了。后台还在评分，可以先结束看报告（未评完的会显示为待评分）。';
      return;
    }
    this.blindNotice = '已提交第 ' + this.blindSubmitted.toString() + ' 句，正在排队评分…';
  }

  private startBlindPoll(): void {
    this.stopBlindPoll();
    this.blindTimerId = setInterval(() => {
      void this.pollBlind();
    }, 2000);
  }

  private stopBlindPoll(): void {
    if (this.blindTimerId >= 0) {
      clearInterval(this.blindTimerId);
      this.blindTimerId = -1;
    }
  }

  async pollBlind(): Promise<void> {
    if (!this.blindActive) {
      this.stopBlindPoll();
      return;
    }
    try {
      const dto = await StatsService.blindTests('');
      const inProgress = dto.in_progress;
      if (inProgress === null || inProgress === undefined) {
        // 批次已结束（可能是另一台设备结束的）
        this.blindActive = false;
        BlindRuntime.clear();
        this.stopBlindPoll();
        return;
      }
      const scored = inProgress.scored;
      const pending = inProgress.pending;
      this.blindScored = scored === undefined ? 0 : scored;
      this.blindPending = pending === undefined ? 0 : pending;
      BlindRuntime.scored = this.blindScored;
      BlindRuntime.pending = this.blindPending;
      if (this.blindDone && this.blindPending === 0) {
        this.blindNotice = '评分也完成了，可以去看报告了 ✅';
        this.stopBlindPoll();
      }
    } catch (err) {
      // 轮询失败静默，下一拍重试
    }
  }

  /** 退出盲测模式（结束后调用）。 */
  clearBlind(): void {
    this.blindActive = false;
    this.blindDone = false;
    this.blindNotice = '';
    this.stopBlindPoll();
  }

  /** Swiper 切页时调用。 */
  setIndex(index: number): void {
    if (index === this.index && this.hasSelection) {
      return;
    }
    this.index = index;
    this.applyCurrent();
  }

  private applyCurrent(): void {
    if (this.index < 0 || this.index >= this.sentences.length) {
      this.hasSelection = false;
      return;
    }
    const sentence = this.sentences[this.index];
    this.sentenceId = sentence.id;
    this.text = sentence.text;
    const translation = sentence.translation_zh;
    this.translation = translation === undefined ? '' : translation;
    const focus = sentence.focus_phonemes;
    this.focusPhonemes = (focus === undefined || this.isChild) ? [] : focus;
    this.hasSelection = true;
    this.ttsPath = '';
    this.recordPath = '';
    this.resetResult();
    this.clearError();
  }

  current(): SentenceDto | null {
    if (this.index < 0 || this.index >= this.sentences.length) {
      return null;
    }
    return this.sentences[this.index];
  }

  /** 预热当前句与后续 5 句的示范音（fire-and-forget）。 */
  private warmupNeighbors(): void {
    const texts: string[] = [];
    for (let i = this.index; i < this.sentences.length && texts.length < 6; i++) {
      texts.push(this.sentences[i].text);
    }
    PracticeService.warmup(texts, this.isChild ? 'slow' : 'normal');
  }

  // ------------------------------------------------------------------ 播放示范

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
    this.playingRecording = false;
  }

  private async ensureTtsPath(): Promise<string> {
    if (this.ttsPath.length > 0 && FileUtil.exists(this.ttsPath)) {
      return this.ttsPath;
    }
    // 示范音优先用账号偏好音色/语速（儿童仍默认 slow）
    await AccountPrefs.ensure();
    const rate = this.isChild ? 'slow' : AccountPrefs.rateOr('normal');
    this.ttsPath = await PracticeService.fetchTtsFile(this.text, rate, AccountPrefs.voice(), 'wav');
    return this.ttsPath;
  }

  /** 回放这次录音（GET /audio/:attemptId）。 */
  async playRecording(): Promise<void> {
    if (this.attemptId.length === 0) {
      return;
    }
    if (AudioController.isRecording()) {
      this.setError(new UiError('', '正在录音，先点「说完啦」再回放', '', false, ApiErrorCode.RECORD_FAILED), '');
      return;
    }
    this.clearError();
    this.lastAction = PracticeAction.PLAY_RECORDING;
    try {
      CacheService.ensureAll();
      const dest = CacheService.audioDir() + '/rec_' + this.attemptId + '.audio';
      if (!FileUtil.exists(dest)) {
        await PracticeService.downloadAudio(this.attemptId, dest);
      }
      this.playingRecording = true;
      await AudioController.play(dest, () => {
        this.playingRecording = false;
      });
    } catch (err) {
      this.playingRecording = false;
      this.handleError(err as Error);
    }
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
    this.recordPath = recorded.path;
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
      const blindTestId = this.blindActive ? BlindRuntime.testId : '';
      const resp = await PracticeService.evaluate(recorded.path, this.sentenceId, this.text,
        recorded.durationMs, blindTestId);
      if (this.blindActive) {
        this.afterBlindSubmit();
      } else {
        this.applyAttempt(resp);
        this.loadHistory();
      }
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
      this.loadHistory();
    } catch (err) {
      this.lastAction = PracticeAction.RETRY_EVALUATE;
      this.handleError(err as Error);
    } finally {
      this.submitting = false;
      this.progressText = '';
      this.stopProgressTimer();
    }
  }

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
    this.attemptIdText = this.attemptId;
    this.resultProvider = result.provider === undefined ? '' : result.provider;
    this.resultGranularity = result.granularity === undefined ? '' : result.granularity;
    const duration = result.duration_ms;
    if (duration !== undefined && duration !== null && duration > 0) {
      this.durationText = (Math.round(duration / 100) / 10).toString() + 's';
    } else {
      this.durationText = '';
    }
    const ref = result.reference_text;
    this.refText = (ref === undefined || ref.length === 0) ? this.text : ref;
    this.applyScores(result);
    const recognized = result.recognized_text;
    this.recognizedText = recognized === undefined ? '' : recognized;
    this.noSpeech = this.recognizedText.trim().length < 2;
    this.lowSnr = this.hasWarning(result, 'low_snr');
    this.applyFeedback(resp.feedback);
    this.applyWords(result);
    this.applyIssues(result.issues);
    this.applyIntonation(result.intonation, result.issues);
    if (this.degraded) {
      this.setError(new UiError('', '评分服务刚刚不稳定，这条结果是降级结果，可以点「重试评测」',
        '重试评测', true, ApiErrorCode.PROVIDER_ERROR), '重试评测');
    }
  }

  /** 从历史 attempt 打开详细结果（不重新录音）：用列表里已有的 scores/issues/intonation/feedback 还原。 */
  showAttemptDetail(item: AttemptItemDto): void {
    this.resetResult();
    this.attemptId = item.id;
    this.attemptIdText = item.id;
    this.sentenceId = item.sentence_id === undefined || item.sentence_id === null ? '' : item.sentence_id;
    this.text = item.reference_text === undefined ? '' : item.reference_text;
    this.refText = this.text;
    this.recognizedText = item.recognized_text === undefined ? '' : item.recognized_text;
    this.noSpeech = this.recognizedText.trim().length < 2;
    const duration = item.duration_ms;
    this.durationText = (duration === undefined || duration === null || duration <= 0)
      ? '' : ((Math.round(duration / 100) / 10).toString() + 's');
    this.resultProvider = '';
    this.resultGranularity = item.mode === undefined ? '' : item.mode;
    const scores = item.scores;
    if (scores !== undefined && scores !== null) {
      this.scorePron = PracticeVM.scoreOr(scores.pron);
      this.scoreAccuracy = PracticeVM.scoreOr(scores.accuracy);
      this.scoreFluency = PracticeVM.scoreOr(scores.fluency);
      this.scoreCompleteness = PracticeVM.scoreOr(scores.completeness);
      this.scoreProsody = PracticeVM.scoreOr(scores.prosody);
    }
    this.applyIssues(item.issues);
    this.applyIntonation(item.intonation, item.issues);
    this.applyFeedback(item.feedback);
    this.hasResult = true;
    this.canRetryEvaluate = false;
    void this.loadHistory();
  }

  /** 历史列表里点「详情」：从 /attempts 找到该条并还原结果。 */
  async openAttemptResult(attemptId: string): Promise<boolean> {
    if (attemptId.length === 0) {
      return false;
    }
    try {
      const list = await PracticeService.attempts(100);
      for (let i = 0; i < list.length; i++) {
        if (list[i].id === attemptId) {
          this.showAttemptDetail(list[i]);
          return true;
        }
      }
    } catch (err) {
      return false;
    }
    return false;
  }

  private static scoreOr(value: number | null | undefined): number {
    return (value === undefined || value === null) ? -1 : value;
  }

  private applyScores(result: PronounceResultDto): void {
    const scores = result.scores;
    if (scores === undefined) {
      this.scorePron = -1;
      this.scoreAccuracy = -1;
      this.scoreFluency = -1;
      this.scoreCompleteness = -1;
      this.scoreProsody = -1;
      return;
    }
    this.scorePron = PracticeVM.scoreOf(scores, 'pron');
    this.scoreAccuracy = PracticeVM.scoreOf(scores, 'accuracy');
    this.scoreFluency = PracticeVM.scoreOf(scores, 'fluency');
    this.scoreCompleteness = PracticeVM.scoreOf(scores, 'completeness');
    this.scoreProsody = PracticeVM.scoreOf(scores, 'prosody');
  }

  private static scoreOf(scores: ScoresDto, key: string): number {
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
      return -1;
    }
    return value;
  }

  /** 词级：句子顺序保留原始明细；另生成「需要练的词」（分数升序）与音素明细 chips。 */
  private applyWords(result: PronounceResultDto): void {
    this.wordTexts = [];
    this.wordScores = [];
    this.wordErrors = [];
    this.wordDetails = [];
    this.worstWordTexts = [];
    this.worstWordScores = [];
    this.phonemeChipLabels = [];
    this.phonemeChipScores = [];
    const words = result.words;
    if (words === undefined || words === null) {
      return;
    }
    const details: WordScoreDto[] = [];
    for (let i = 0; i < words.length; i++) {
      details.push(words[i]);
    }
    this.wordDetails = details;
    if (this.isChild) {
      return;
    }
    // 需要练的词：按分数升序（null 排最后）
    const sorted: WordScoreDto[] = [];
    for (let i = 0; i < details.length; i++) {
      sorted.push(details[i]);
    }
    sorted.sort((a: WordScoreDto, b: WordScoreDto) => {
      const sa = (a.score === undefined || a.score === null) ? 101 : a.score;
      const sb = (b.score === undefined || b.score === null) ? 101 : b.score;
      return sa - sb;
    });
    for (let i = 0; i < sorted.length && i < 12; i++) {
      const word = sorted[i];
      this.wordTexts.push(word.word);
      this.wordScores.push((word.score === undefined || word.score === null) ? -1 : (word.score as number));
      this.wordErrors.push(word.error_type === undefined || word.error_type === null ? '' : (word.error_type as string));
      if (i < 9) {
        this.worstWordTexts.push(word.word);
        this.worstWordScores.push((word.score === undefined || word.score === null) ? -1 : (word.score as number));
      }
    }
    // 音素明细 chips（按出现顺序，最多 40 个）
    for (let i = 0; i < details.length && this.phonemeChipLabels.length < 40; i++) {
      const word = details[i];
      const phonemes = word.phonemes;
      if (phonemes === undefined) {
        continue;
      }
      for (let j = 0; j < phonemes.length && this.phonemeChipLabels.length < 40; j++) {
        const phoneme = phonemes[j];
        if (phoneme.phoneme === undefined) {
          continue;
        }
        this.phonemeChipLabels.push(phoneme.phoneme);
        this.phonemeChipScores.push((phoneme.score === undefined || phoneme.score === null) ? -1 : (phoneme.score as number));
      }
    }
  }

  /** 问题音素 chips + 「需要纠正的地方」卡片（hint_key 文案在本地映射）。 */
  private applyIssues(issueList: IssueDto[] | null | undefined): void {
    this.issueChipLabels = [];
    this.issueChipScores = [];
    this.issueCards = [];
    const issues = issueList;
    if (issues === undefined || issues === null) {
      return;
    }
    const seen: string[] = [];
    for (let i = 0; i < issues.length; i++) {
      const issue = issues[i];
      const phoneme = issue.phoneme;
      const label = (phoneme === undefined || phoneme === null) ? '' : phoneme;
      if (label.length > 0 && seen.indexOf(label) < 0 && !this.isChild) {
        seen.push(label);
        this.issueChipLabels.push(label);
        this.issueChipScores.push((issue.score === undefined || issue.score === null) ? -1 : (issue.score as number));
      }
      if (this.isChild || this.issueCards.length >= 3) {
        continue;
      }
      const expected = issue.expected;
      const actual = issue.actual;
      const lookup = (expected === undefined || expected === null || expected.length === 0)
        ? label : expected;
      const hint: PhonemeHint = PhonemeHints.byPhoneme(lookup);
      const card = new ResultIssue();
      card.title = PhonemeHints.title(hint, false);
      card.word = issue.word === undefined ? '' : issue.word;
      card.expected = (expected === undefined || expected === null) ? '' : expected;
      card.actual = (actual === undefined || actual === null) ? '' : actual;
      card.score = (issue.score === undefined || issue.score === null) ? -1 : (issue.score as number);
      card.why = PhonemeHints.why(hint, false);
      card.how = PhonemeHints.how(hint, false);
      card.words = hint.words.join(' · ');
      this.issueCards.push(card);
    }
  }

  private applyIntonation(intonationDto: IntonationDto | null | undefined,
    issueList: IssueDto[] | null | undefined): void {
    this.intonationAvailable = false;
    this.intonationDistance = '';
    this.regionTexts = [];
    this.userF0 = [];
    this.refF0 = [];
    const intonation = intonationDto;
    if (intonation === undefined || intonation === null || intonation.available !== true) {
      return;
    }
    this.intonationAvailable = true;
    const distance = intonation.dtw_distance;
    if (distance !== undefined && distance !== null) {
      this.intonationDistance = (Math.round(distance * 100) / 100).toString();
    }
    const user = intonation.user_f0;
    const ref = intonation.reference_f0;
    this.userF0 = user === undefined ? [] : user;
    this.refF0 = ref === undefined ? [] : ref;
    const regions = intonation.worst_regions;
    const texts: string[] = [];
    if (regions !== undefined && !this.isChild) {
      for (let i = 0; i < regions.length && i < 2; i++) {
        const region = regions[i];
        const label = PracticeVM.regionLabel(region.issue);
        const text = region.text === undefined ? '' : region.text;
        texts.push(label + (text.length > 0 ? '（' + text + '）' : ''));
      }
    }
    this.regionTexts = texts;
    // 前 2 个 issue 转成人话
    const issues = issueList;
    const issueTexts: string[] = [];
    if (issues !== undefined && issues !== null && !this.isChild) {
      for (let i = 0; i < issues.length && i < 2; i++) {
        issueTexts.push(PracticeVM.issueLabel(issues[i]));
      }
    }
    this.issueTexts = issueTexts;
  }

  private static regionLabel(issue: string | undefined): string {
    if (issue === 'expected_rise_but_flat') {
      return '这里该升调却没升';
    }
    if (issue === 'expected_fall_but_flat') {
      return '这里该降调却没降';
    }
    if (issue === 'wrong_direction') {
      return '升降方向反了';
    }
    if (issue === 'stress_misplaced') {
      return '重音位置偏了';
    }
    if (issue === 'monotone_overall') {
      return '整体偏平';
    }
    if (issue === 'unexpected_pause') {
      return '不该停的地方停了';
    }
    return '语调可以更自然';
  }

  private static issueLabel(issue: IssueDto): string {
    const word = issue.word === undefined ? '' : issue.word;
    const expected = issue.expected === undefined || issue.expected === null ? '' : issue.expected;
    const actual = issue.actual === undefined || issue.actual === null ? '' : issue.actual;
    if (word.length === 0) {
      return issue.type === undefined ? '发音小问题' : issue.type;
    }
    if (expected.length > 0 && actual.length > 0) {
      return word + '：' + expected + ' 发成了 ' + actual;
    }
    return word + (issue.type === undefined ? ' 发音注意一下' : '：' + issue.type);
  }

  /** 单句历史：/attempts?limit=100 按 sentence_id 过滤，取最近 10 次（含 attempt id 可回放）。 */
  async loadHistory(): Promise<void> {
    if (this.sentenceId.length === 0 || this.historyLoading) {
      return;
    }
    this.historyLoading = true;
    try {
      const list = await PracticeService.attempts(100);
      const scores: number[] = [];
      const times: string[] = [];
      const ids: string[] = [];
      for (let i = 0; i < list.length; i++) {
        const item = list[i];
        if (item.sentence_id === undefined || item.sentence_id !== this.sentenceId) {
          continue;
        }
        if (item.pending === true || item.scores === undefined || item.scores === null) {
          continue;
        }
        const pron = item.scores.pron;
        if (pron === undefined || pron === null) {
          continue;
        }
        scores.push(pron);
        times.push(item.created_at === undefined ? '' : item.created_at);
        ids.push(item.id);
        if (scores.length >= 10) {
          break;
        }
      }
      // 服务端按时间倒序返回；折线图用「旧→新」
      const ordered: number[] = [];
      const orderedIds: string[] = [];
      const orderedLabels: string[] = [];
      for (let i = scores.length - 1; i >= 0; i--) {
        ordered.push(scores[i]);
        orderedIds.push(ids[i]);
        orderedLabels.push(PracticeVM.formatHistoryTime(times[i]));
      }
      this.historyScores = ordered;
      this.historyTimes = times;
      this.historyAttemptIds = orderedIds;
      this.historyLabels = orderedLabels;
      this.historyFirst = ordered.length > 0 ? ordered[0] : -1;
      this.historyLast = ordered.length > 0 ? ordered[ordered.length - 1] : -1;
      this.historyLoaded = true;
    } catch (err) {
      // 历史不影响主流程，失败静默
    } finally {
      this.historyLoading = false;
    }
  }

  /** ISO 时间 → `M/d HH:mm`（历史列表用）。 */
  private static formatHistoryTime(iso: string): string {
    if (iso.length < 16) {
      return iso;
    }
    const month = Number(iso.substring(5, 7));
    const day = Number(iso.substring(8, 10));
    const hour = iso.substring(11, 13);
    const minute = iso.substring(14, 16);
    return month.toString() + '/' + day.toString() + ' ' + hour + ':' + minute;
  }

  /** 回放某一条历史录音（GET /audio/:attemptId）。 */
  async playHistoryAudio(attemptId: string): Promise<void> {
    if (attemptId.length === 0 || AudioController.isRecording()) {
      return;
    }
    this.clearError();
    try {
      CacheService.ensureAll();
      const dest = CacheService.audioDir() + '/rec_' + attemptId + '.audio';
      if (!FileUtil.exists(dest)) {
        await PracticeService.downloadAudio(attemptId, dest);
      }
      this.playingHistoryId = attemptId;
      await AudioController.play(dest, () => {
        this.playingHistoryId = '';
      });
    } catch (err) {
      this.playingHistoryId = '';
      this.handleError(err as Error);
    }
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
    if (points === undefined || this.isChild) {
      return;
    }
    const titles: string[] = [];
    const hows: string[] = [];
    const whys: string[] = [];
    const words: string[] = [];
    for (let i = 0; i < points.length && i < 2; i++) {
      const point: FeedbackPointDto = points[i];
      titles.push(point.title === undefined ? '' : point.title);
      hows.push(point.how === undefined ? '' : point.how);
      whys.push(point.why === undefined ? '' : point.why);
      const practice = point.practice_words;
      words.push((practice === undefined || practice.length === 0) ? '' : practice.join(' · '));
    }
    this.pointTitles = titles;
    this.pointHows = hows;
    this.pointWhys = whys;
    this.pointWords = words;
  }

  private hasWarning(result: PronounceResultDto, key: string): boolean {
    const warnings = result.warnings;
    if (warnings === undefined) {
      return false;
    }
    return warnings.indexOf(key) >= 0;
  }

  // ------------------------------------------------------------------ 错误 / 生命周期

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
    } else if (action === PracticeAction.PLAY_RECORDING) {
      await this.playRecording();
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
    const ui = SessionStore.toUiError(err, this.isChild);
    let actionLabel = '';
    if (ui.code === ApiErrorCode.MIC_DENIED) {
      actionLabel = '去设置';
    } else if (this.lastAction === PracticeAction.DEMO || this.lastAction === PracticeAction.FOLLOW) {
      actionLabel = this.isChild ? '再试一次' : '重试';
    } else if (this.lastAction === PracticeAction.PLAY_RECORDING) {
      actionLabel = '重试';
    } else if (this.canRetryEvaluate) {
      actionLabel = '重试评测';
    }
    this.setError(ui, actionLabel);
  }

  resetResult(): void {
    this.hasResult = false;
    this.scorePron = -1;
    this.scoreAccuracy = -1;
    this.scoreFluency = -1;
    this.scoreCompleteness = -1;
    this.scoreProsody = -1;
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
    this.wordTexts = [];
    this.wordScores = [];
    this.wordErrors = [];
    this.wordDetails = [];
    this.worstWordTexts = [];
    this.worstWordScores = [];
    this.phonemeChipLabels = [];
    this.phonemeChipScores = [];
    this.issueChipLabels = [];
    this.issueChipScores = [];
    this.issueCards = [];
    this.pointWhys = [];
    this.pointWords = [];
    this.issueTexts = [];
    this.intonationAvailable = false;
    this.intonationDistance = '';
    this.regionTexts = [];
    this.userF0 = [];
    this.refF0 = [];
    this.historyScores = [];
    this.historyTimes = [];
    this.historyAttemptIds = [];
    this.historyLabels = [];
    this.historyFirst = -1;
    this.historyLast = -1;
    this.playingHistoryId = '';
    this.historyLoaded = false;
    this.attemptId = '';
    this.attemptIdText = '';
    this.resultProvider = '';
    this.resultGranularity = '';
    this.durationText = '';
    this.refText = '';
  }

  /** 页面销毁/切后台：停计时、丢录音、停播放、释放 fd。 */
  dispose(): void {
    this.stopTimer();
    this.stopProgressTimer();
    this.stopBlindPoll();
    this.recording = false;
    this.playing = false;
    this.playingRecording = false;
    void AudioController.stopAll();
  }
}

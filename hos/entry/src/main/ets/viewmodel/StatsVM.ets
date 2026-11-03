import { UiError } from '../core/error/UiError';
import {
  BlindFinishDto,
  BlindTestDto,
  BlindTrendDto,
  BlindTrendScoreDto,
  DiagnosisItemDto,
  ReviewCardDto,
  ReviewWeakPhonemeDto,
  ReviewWordErrorDto
} from '../core/net/StatsDtos';
import { StatsService } from '../core/service/StatsService';
import { SessionState, SessionStore } from '../core/session/SessionStore';

/**
 * 诊断 / 错音本 / 盲测 的页面状态。
 *
 * 三者都用「扁平字段 + 数组替换」表达，页面不处理 null DTO（与 PracticeVM 一致的风格）。
 * 儿童：所有数字分与 IPA 都由页面按 `isChild` 隐藏（服务端已剥离 phoneme，双保险）。
 */

// ===========================================================================
// 发音诊断（/diagnosis：recent 7 天 / all 累计）
// ===========================================================================

@Observed
export class DiagnosisVM {
  scope: string = 'recent';
  days: number = 7;
  isChild: boolean = false;

  items: DiagnosisItemDto[] = [];
  okItems: DiagnosisItemDto[] = [];
  summaryZh: string = '';
  minSamples: number = 2;
  countedPhonemes: number = 0;
  totalPhonemes: number = 0;
  weakCount: number = 0;
  watchCount: number = 0;
  okCount: number = 0;
  focusPhonemes: string[] = [];
  generatedAt: string = '';

  loading: boolean = false;
  loadedOnce: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');
  showOk: boolean = false;

  async init(isChild: boolean): Promise<void> {
    this.isChild = isChild;
    await this.load();
  }

  async switchScope(scope: string): Promise<void> {
    if (this.scope === scope) {
      return;
    }
    this.scope = scope;
    this.items = [];
    this.okItems = [];
    this.loadedOnce = false;
    this.showOk = false;
    await this.load();
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    try {
      const dto = await StatsService.diagnosis(this.scope, this.days, []);
      const all = dto.items === undefined ? [] : dto.items;
      const weakOrWatch: DiagnosisItemDto[] = [];
      const ok: DiagnosisItemDto[] = [];
      for (let i = 0; i < all.length; i++) {
        const status = all[i].status;
        if (status === 'ok') {
          ok.push(all[i]);
        } else {
          weakOrWatch.push(all[i]);
        }
      }
      this.items = weakOrWatch;
      this.okItems = ok;
      this.summaryZh = dto.summary_zh === undefined ? '' : dto.summary_zh;
      this.minSamples = dto.min_samples === undefined ? 2 : dto.min_samples;
      this.countedPhonemes = dto.counted_phonemes === undefined ? 0 : dto.counted_phonemes;
      this.totalPhonemes = dto.total_phonemes === undefined ? 0 : dto.total_phonemes;
      const counts = dto.counts;
      this.weakCount = (counts === undefined || counts.weak === undefined) ? 0 : counts.weak;
      this.watchCount = (counts === undefined || counts.watch === undefined) ? 0 : counts.watch;
      this.okCount = (counts === undefined || counts.ok === undefined) ? 0 : counts.ok;
      const focus = dto.focus_phonemes;
      this.focusPhonemes = focus === undefined ? [] : focus;
      this.generatedAt = dto.generated_at === undefined ? '' : dto.generated_at;
      this.loadedOnce = true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, this.isChild);
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  /** 统计口径小字（recent / all 两套文案）。 */
  metricText(): string {
    const weak = this.weakCount.toString();
    const watch = this.watchCount.toString();
    const ok = this.okCount.toString();
    if (this.scope === 'all') {
      return '统计口径：每个音素至少 ' + this.minSamples.toString() + ' 次记录才计入（共 ' +
        this.countedPhonemes.toString() + ' 个达标，薄弱 ' + weak + ' / 待巩固 ' + watch + ' / 已掌握 ' + ok + '）。';
    }
    return '统计口径：最近 ' + this.days.toString() + ' 天 · ' + this.countedPhonemes.toString() +
      ' 个音素计入（薄弱 ' + weak + ' / 待巩固 ' + watch + ' / 已掌握 ' + ok + '）。';
  }

  /** 主按钮文案（有薄弱项才给强化练习；跟读是首页 Tab，这里只负责返回首页）。 */
  actionLabel(): string {
    if (this.isChild) {
      return this.items.length > 0 ? '🎯 返回去练一练' : '返回首页';
    }
    const token = this.firstFocusToken();
    return token.length > 0 ? ('🚀 去跟读页练 /' + token + '/') : '返回首页';
  }

  firstFocusToken(): string {
    if (this.focusPhonemes.length > 0) {
      return this.focusPhonemes[0];
    }
    if (this.items.length > 0 && this.items[0].focus_token !== undefined) {
      return this.items[0].focus_token;
    }
    return '';
  }

  /** 音素行标题：成人 `/<ipa>/ · 咬舌的 th`，儿童只有 child_label。 */
  itemTitle(item: DiagnosisItemDto): string {
    const childLabel = item.child_label === undefined ? '' : item.child_label;
    if (this.isChild) {
      return childLabel.length > 0 ? childLabel : '这个音';
    }
    const phoneme = item.phoneme === undefined ? '' : item.phoneme;
    if (phoneme.length === 0) {
      return childLabel;
    }
    return childLabel.length > 0 ? ('/' + phoneme + '/ · ' + childLabel) : ('/' + phoneme + '/');
  }

  /** 趋势文案：近 3 次 ↗/↘/→。 */
  trendText(item: DiagnosisItemDto): string {
    const trend = item.trend;
    if (trend === undefined || trend === null || trend.direction === undefined) {
      return '';
    }
    const delta = trend.delta === undefined ? 0 : trend.delta;
    const abs = Math.abs(Math.round(delta));
    if (trend.direction === 'improving') {
      return '近 3 次 ↗ 在进步（+' + abs.toString() + '）';
    }
    if (trend.direction === 'declining') {
      return '近 3 次 ↘ 略有下滑（-' + abs.toString() + '）';
    }
    return '近 3 次 → 基本持平';
  }

  statusTone(status: string): string {
    if (status === 'weak') {
      return 'weak';
    }
    if (status === 'watch') {
      return 'watch';
    }
    return 'ok';
  }

  /** 儿童版趋势文案：不出现数字分。 */
  trendTextChild(item: DiagnosisItemDto): string {
    const trend = item.trend;
    if (trend === undefined || trend === null || trend.direction === undefined) {
      return '';
    }
    if (trend.direction === 'improving') {
      return '最近在进步 ↗';
    }
    if (trend.direction === 'declining') {
      return '最近有点下滑 ↘';
    }
    return '最近比较稳定 →';
  }
}

// ===========================================================================
// 错音本（/review，SRS）
// ===========================================================================

@Observed
export class ReviewVM {
  isChild: boolean = false;
  cards: ReviewCardDto[] = [];
  weakPhonemes: ReviewWeakPhonemeDto[] = [];
  wordErrors: ReviewWordErrorDto[] = [];

  totalCards: number = 0;
  dueCards: number = 0;
  phonemeRows: number = 0;
  phonemeLevel: boolean = true;
  voiceReachable: boolean = true;

  loading: boolean = false;
  loadedOnce: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');

  gradingCardId: string = '';
  gradeNotice: string = '';
  gradeError: string = '';

  async init(isChild: boolean): Promise<void> {
    this.isChild = isChild;
    await this.load();
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    try {
      const dto = await StatsService.review(20);
      this.cards = dto.due_cards === undefined ? [] : dto.due_cards;
      this.weakPhonemes = dto.weak_phonemes === undefined ? [] : dto.weak_phonemes;
      this.wordErrors = dto.word_level_errors === undefined ? [] : dto.word_level_errors;
      const stats = dto.stats;
      this.totalCards = (stats === undefined || stats.total_cards === undefined) ? 0 : stats.total_cards;
      this.dueCards = (stats === undefined || stats.due_cards === undefined) ? 0 : stats.due_cards;
      this.phonemeRows = (stats === undefined || stats.phoneme_rows === undefined) ? 0 : stats.phoneme_rows;
      this.phonemeLevel = !(stats !== undefined && stats.phoneme_level === false);
      this.voiceReachable = !(stats !== undefined && stats.voice_reachable === false);
      this.loadedOnce = true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, this.isChild);
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  /**
   * 提交一次复习评分。
   * 成功后**本地移除该卡并 due_cards-1**（规格 §6.2：不重新拉列表）。
   * 返回 true 表示成功（页面可据此刷新提示）。
   */
  async grade(cardId: string, grade: string): Promise<boolean> {
    if (this.gradingCardId.length > 0) {
      return false;
    }
    this.gradingCardId = cardId;
    this.gradeError = '';
    this.gradeNotice = '';
    try {
      const result = await StatsService.gradeReview(cardId, grade);
      const next: ReviewCardDto[] = [];
      for (let i = 0; i < this.cards.length; i++) {
        if (this.cards[i].id !== cardId) {
          next.push(this.cards[i]);
        }
      }
      this.cards = next;
      this.dueCards = this.dueCards > 0 ? this.dueCards - 1 : 0;
      this.gradeNotice = ReviewVM.nextDueText(result.interval_days, result.next_due_at);
      return true;
    } catch (err) {
      this.gradeError = SessionStore.toUiError(err as Error, this.isChild).message;
      return false;
    } finally {
      this.gradingCardId = '';
    }
  }

  static nextDueText(intervalDays: number | undefined | null, nextDueAt: string | undefined): string {
    const days = (intervalDays === undefined || intervalDays === null) ? 0 : intervalDays;
    if (days > 0) {
      return '下次复习：' + days.toString() + ' 天后 ✅';
    }
    if (nextDueAt !== undefined && nextDueAt.length > 0) {
      return '10 分钟后再来一次 🔁';
    }
    return '已记录 ✅';
  }

  /** 4 个评分按钮的文案（成人 / 儿童两套）。 */
  gradeLabel(grade: string): string {
    if (this.isChild) {
      if (grade === 'again') {
        return '😵 还没会';
      }
      if (grade === 'hard') {
        return '🤔 有点难';
      }
      if (grade === 'good') {
        return '😀 会了';
      }
      return '🤩 太简单';
    }
    if (grade === 'again') {
      return '再来一次';
    }
    if (grade === 'hard') {
      return '有点难';
    }
    if (grade === 'good') {
      return '记住了';
    }
    return '太简单';
  }

  /** 卡片标题：成人用 `/ipa/ · label`，儿童只用 label（服务端 phoneme 为空）。 */
  cardTitle(card: ReviewCardDto): string {
    const label = card.label === undefined ? '' : card.label;
    if (this.isChild) {
      return label.length > 0 ? label : '这一张';
    }
    const phoneme = card.phoneme;
    if (phoneme !== undefined && phoneme !== null && phoneme.length > 0) {
      return label.length > 0 ? label : ('/' + phoneme + '/');
    }
    return label;
  }

  /** 卡片音素徽标（仅成人且 is_phoneme 为 true 时显示）。 */
  badgeText(card: ReviewCardDto): string {
    if (this.isChild || card.is_phoneme !== true) {
      return '';
    }
    const phoneme = card.phoneme;
    if (phoneme === undefined || phoneme === null || phoneme.length === 0) {
      return '';
    }
    return '/' + phoneme + '/';
  }

  metaText(card: ReviewCardDto): string {
    const kind = card.kind === undefined ? 'phoneme' : card.kind;
    const reps = card.reps === undefined ? 0 : card.reps;
    const lapses = card.lapses === undefined ? 0 : card.lapses;
    const ease = card.ease === undefined ? 0 : card.ease;
    const easeText = (Math.round(ease * 100) / 100).toFixed(2);
    const last = (card.last_grade === undefined || card.last_grade === null) ? '未复习' : card.last_grade;
    return kind + ' · 已复习 ' + reps.toString() + ' 次 · 遗忘 ' + lapses.toString() +
      ' 次 · ease ' + easeText + ' · 上次：' + last;
  }

  weakPhonemeLabel(item: ReviewWeakPhonemeDto): string {
    const label = item.label === undefined ? '' : item.label;
    if (label.length > 0) {
      return label;
    }
    if (this.isChild) {
      return '这个音';
    }
    const phoneme = item.phoneme === undefined ? '' : item.phoneme;
    return phoneme.length > 0 ? ('/' + phoneme + '/') : '—';
  }

  /** 今日已练分钟数（保留 1 位小数）。 */
  static minutesText(session: SessionState): string {
    return (Math.round(session.minutesToday * 10) / 10).toString();
  }

  static minutesLeft(session: SessionState): string {
    return (Math.round(session.remainingMinutes * 10) / 10).toString();
  }

  static scoreText(score: number | null | undefined): string {
    if (score === undefined || score === null) {
      return '—';
    }
    return (Math.round(score * 10) / 10).toString();
  }

  /** 掌握度条宽度百分比（null/undefined → 2% 的可见底线，不把 null 当 0 画）。 */
  weakBarWidth(item: ReviewWeakPhonemeDto): string {
    const score = item.avg_score;
    if (score === undefined || score === null) {
      return '2%';
    }
    const width = Math.max(2, Math.round(score));
    return width.toString() + '%';
  }
}

// ===========================================================================
// 盲测（/blind-tests）
// ===========================================================================

@Observed
export class BlindTestVM {
  isChild: boolean = false;
  tests: BlindTestDto[] = [];
  inProgress: BlindTestDto | null = null;
  pendingTotal: number = 0;
  trend: BlindTrendDto | null = null;
  series: BlindTrendScoreDto[] = [];

  // 进行中批次的扁平字段（避免页面在 build 里做多层可选链）
  hasInProgress: boolean = false;
  inProgressId: string = '';
  inProgressTotal: number = 0;
  inProgressScored: number = 0;
  inProgressPending: number = 0;

  // 周报扁平字段（null = 暂无；儿童页面不展示数字）
  weeks: number = 0;
  currentPron: number | null = null;
  currentAccuracy: number | null = null;
  currentFluency: number | null = null;
  currentIntonation: number | null = null;
  previousPron: number | null = null;

  loading: boolean = false;
  loadedOnce: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');

  starting: boolean = false;
  startError: string = '';
  /** 开始盲测后服务端返回的抽题结果（供跟读页进入盲测模式） */
  startTestId: string = '';
  startSentenceIds: string[] = [];
  startTotal: number = 0;
  finishing: boolean = false;
  finishError: string = '';
  finishResult: BlindFinishDto | null = null;

  // 结束结果扁平字段（页面不做深层可选链）
  hasFinishResult: boolean = false;
  finishNotice: string = '';
  finishPron: number | null = null;
  finishAccuracy: number | null = null;
  finishFluency: number | null = null;
  finishIntonation: number | null = null;
  finishScored: number = 0;
  finishPending: number = 0;

  async init(isChild: boolean): Promise<void> {
    this.isChild = isChild;
    await this.load();
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    try {
      const dto = await StatsService.blindTests('');
      this.tests = dto.tests === undefined ? [] : dto.tests;
      this.inProgress = (dto.in_progress === undefined) ? null : dto.in_progress;
      this.pendingTotal = dto.pending_total === undefined ? 0 : dto.pending_total;
      this.trend = (dto.trend === undefined) ? null : dto.trend;
      this.series = dto.series === undefined ? [] : dto.series;
      this.applyDerived();
      this.loadedOnce = true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, this.isChild);
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  private applyDerived(): void {
    const inProgress = this.inProgress;
    this.hasInProgress = inProgress !== null;
    if (inProgress === null) {
      this.inProgressId = '';
      this.inProgressTotal = 0;
      this.inProgressScored = 0;
      this.inProgressPending = 0;
    } else {
      this.inProgressId = inProgress.id;
      this.inProgressTotal = inProgress.item_count === undefined ? 0 : inProgress.item_count;
      this.inProgressScored = inProgress.scored === undefined ? 0 : inProgress.scored;
      this.inProgressPending = inProgress.pending === undefined ? 0 : inProgress.pending;
    }
    const trend = this.trend;
    if (trend === null) {
      this.weeks = 0;
      this.currentPron = null;
      this.currentAccuracy = null;
      this.currentFluency = null;
      this.currentIntonation = null;
      this.previousPron = null;
      return;
    }
    this.weeks = trend.weeks === undefined ? 0 : trend.weeks;
    const current = trend.current;
    if (current === undefined || current === null) {
      this.currentPron = null;
      this.currentAccuracy = null;
      this.currentFluency = null;
      this.currentIntonation = null;
    } else {
      this.currentPron = current.avg_pron === undefined ? null : current.avg_pron;
      this.currentAccuracy = current.avg_accuracy === undefined ? null : current.avg_accuracy;
      this.currentFluency = current.avg_fluency === undefined ? null : current.avg_fluency;
      this.currentIntonation = current.avg_intonation_distance === undefined
        ? null : current.avg_intonation_distance;
    }
    const previous = trend.previous;
    if (previous === undefined || previous === null) {
      this.previousPron = null;
    } else {
      this.previousPron = previous.avg_pron === undefined ? null : previous.avg_pron;
    }
  }

  /** 开始（或恢复）一次盲测；成功后重新拉列表。返回 true = 成功。 */
  async start(): Promise<boolean> {
    if (this.starting) {
      return false;
    }
    this.starting = true;
    this.startError = '';
    try {
      const dto = await StatsService.startBlindTest();
      this.startTestId = dto.blind_test_id;
      const ids = dto.sentence_ids;
      this.startSentenceIds = ids === undefined ? [] : ids;
      this.startTotal = dto.total === undefined ? this.startSentenceIds.length : dto.total;
      await this.load();
      return true;
    } catch (err) {
      this.startError = SessionStore.toUiError(err as Error, this.isChild).message;
      return false;
    } finally {
      this.starting = false;
    }
  }

  /** 结束当前进行中的批次并拿到汇总（notice/pending 必须如实展示）。 */
  async finish(): Promise<boolean> {
    const inProgress = this.inProgress;
    if (inProgress === null) {
      return false;
    }
    if (this.finishing) {
      return false;
    }
    this.finishing = true;
    this.finishError = '';
    try {
      const dto = await StatsService.finishBlindTest(inProgress.id);
      this.finishResult = dto;
      this.hasFinishResult = true;
      this.finishNotice = (dto.notice === undefined || dto.notice === null) ? '' : dto.notice;
      this.finishPron = dto.avg_pron === undefined ? null : dto.avg_pron;
      this.finishAccuracy = dto.avg_accuracy === undefined ? null : dto.avg_accuracy;
      this.finishFluency = dto.avg_fluency === undefined ? null : dto.avg_fluency;
      this.finishIntonation = dto.avg_intonation_distance === undefined ? null : dto.avg_intonation_distance;
      this.finishScored = dto.scored === undefined ? 0 : dto.scored;
      this.finishPending = dto.pending === undefined ? 0 : dto.pending;
      await this.load();
      return true;
    } catch (err) {
      this.finishError = SessionStore.toUiError(err as Error, this.isChild).message;
      return false;
    } finally {
      this.finishing = false;
    }
  }

  /** 关掉「完成」卡（去看周报时调用）。 */
  clearFinish(): void {
    this.finishResult = null;
    this.hasFinishResult = false;
    this.finishNotice = '';
  }

  hasFinished(): boolean {
    return this.tests.length > 0;
  }

  /** 环比文案：▲ +4.4 / ▼ -2 / ＝ 0 / 首次（无对比）/ 还没有盲测数据。 */
  deltaText(): string {
    if (this.trend === null) {
      return '还没有盲测数据';
    }
    if (this.currentPron === null && this.weeks === 0) {
      return '还没有盲测数据';
    }
    const trend = this.trend;
    const delta = trend === null ? null : trend.delta_pron;
    if (delta === undefined || delta === null) {
      return '首次（无对比）';
    }
    if (delta > 0) {
      return '▲ +' + (Math.round(delta * 10) / 10).toString();
    }
    if (delta < 0) {
      return '▼ ' + (Math.round(delta * 10) / 10).toString();
    }
    return '＝ 0';
  }

  deltaColor(): ResourceColor {
    if (this.trend === null) {
      return $r('app.color.ec_muted');
    }
    const delta = this.trend.delta_pron;
    if (delta === undefined || delta === null) {
      return $r('app.color.ec_muted');
    }
    if (delta > 0) {
      return $r('app.color.ec_good_text');
    }
    if (delta < 0) {
      return $r('app.color.ec_bad_text');
    }
    return $r('app.color.ec_muted');
  }
}

// ===========================================================================
// 服务状态（GET /health 全字段：db / features / voice.capabilities）
// ===========================================================================

@Observed
export class HealthVM {
  loading: boolean = false;
  loaded: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');

  status: string = '';
  service: string = '';
  version: string = '';
  serverTime: string = '';

  dbOk: boolean = true;
  dbError: string = '';

  voiceReachable: boolean = false;
  voiceMode: string = '';
  voiceUrl: string = '';
  voiceHint: string = '';

  phonemeLevel: boolean = false;
  prosody: boolean = false;
  intonationCurve: boolean = false;
  nbestPhonemes: boolean = false;
  ssml: boolean = false;
  gpu: boolean = false;
  ocr: boolean = false;
  ocrProvider: string = '';
  heic: boolean = false;
  image: boolean = false;
  imageProvider: string = '';
  imageAvatar: boolean = false;
  avatarPresets: boolean = false;
  audioConcat: boolean = false;
  chatDoneTurnIndex: number = 0;
  voiceFeatures: string[] = [];

  /** features 6 个固定键（展示用：标签 + 值）。 */
  featureLabels: string[] = [];
  featureValues: boolean[] = [];
  capabilityLines: string[] = [];

  forced: boolean = false;

  async init(): Promise<void> {
    await this.load(false);
  }

  async load(force: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    try {
      const dto = await StatsService.healthFull(force);
      this.forced = force;
      this.status = dto.status === undefined ? '' : dto.status;
      this.service = dto.service === undefined ? '' : dto.service;
      this.version = dto.version === undefined ? '' : dto.version;
      this.serverTime = dto.time === undefined ? '' : dto.time;
      const db = dto.db;
      this.dbOk = !(db !== undefined && db.ok === false);
      this.dbError = (db === undefined || db.error === undefined || db.error === null) ? '' : db.error;

      const features = dto.features;
      this.featureLabels = [];
      this.featureValues = [];
      if (features !== undefined) {
        this.pushFeature('无限轮对话', features.chat_unlimited_turns);
        this.pushFeature('对话整段回放', features.chat_audio_replay);
        this.pushFeature('对话场景 audience', features.chat_scenarios_audience);
        this.pushFeature('预置形象库', features.avatar_presets);
        this.pushFeature('故事模式', features.story_mode);
        this.pushFeature('异步评分', features.async_scoring);
      }

      const voice = dto.voice;
      this.voiceReachable = voice !== undefined && voice.reachable === true;
      this.voiceMode = (voice === undefined || voice.mode === undefined) ? '' : voice.mode;
      this.voiceUrl = (voice === undefined || voice.url === undefined) ? '' : voice.url;
      this.voiceHint = (voice === undefined || voice.hint === undefined || voice.hint === null)
        ? '' : voice.hint;

      const caps = voice === undefined ? undefined : voice.capabilities;
      if (caps !== undefined) {
        this.phonemeLevel = caps.phoneme_level === true;
        this.prosody = caps.prosody === true;
        this.intonationCurve = caps.intonation_curve === true;
        this.nbestPhonemes = caps.nbest_phonemes === true;
        this.ssml = caps.ssml === true;
        this.gpu = caps.gpu === true;
        this.ocr = caps.ocr === true;
        this.ocrProvider = (caps.ocr_provider === undefined || caps.ocr_provider === null)
          ? '' : caps.ocr_provider;
        this.heic = caps.heic === true;
        this.image = caps.image === true;
        this.imageProvider = (caps.image_provider === undefined || caps.image_provider === null)
          ? '' : caps.image_provider;
        this.imageAvatar = caps.image_avatar === true;
        this.avatarPresets = caps.avatar_presets === true;
        this.audioConcat = caps.audio_concat === true;
        this.chatDoneTurnIndex = caps.chat_done_turn_index === undefined ? 0 : caps.chat_done_turn_index;
        this.voiceFeatures = caps.features === undefined ? [] : caps.features;
      } else {
        this.voiceFeatures = [];
      }
      this.buildCapabilityLines();
      this.loaded = true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, false);
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  private pushFeature(label: string, value: boolean | undefined): void {
    this.featureLabels.push(label);
    this.featureValues.push(value === true);
  }

  private buildCapabilityLines(): void {
    const lines: string[] = [];
    lines.push('音素级评分：' + HealthVM.support(this.phonemeLevel));
    lines.push('韵律分：' + HealthVM.support(this.prosody));
    lines.push('语调曲线：' + HealthVM.support(this.intonationCurve));
    lines.push('多候选音素：' + HealthVM.support(this.nbestPhonemes));
    lines.push('SSML：' + HealthVM.support(this.ssml));
    lines.push('GPU：' + HealthVM.support(this.gpu));
    lines.push('拍照 OCR：' + HealthVM.support(this.ocr) +
      (this.ocrProvider.length > 0 ? ('（' + this.ocrProvider + '）') : ''));
    lines.push('HEIC：' + HealthVM.support(this.heic));
    lines.push('插画生成：' + HealthVM.support(this.image) +
      (this.imageProvider.length > 0 ? ('（' + this.imageProvider + '）') : ''));
    lines.push('照片生成形象：' + (this.imageAvatar ? '可用' : '已关闭（隐私策略）'));
    lines.push('预置形象库：' + HealthVM.support(this.avatarPresets));
    lines.push('整段音频拼接：' + HealthVM.support(this.audioConcat));
    lines.push('对话结束轮次：' + (this.chatDoneTurnIndex === 0 ? '不限轮' : this.chatDoneTurnIndex.toString()));
    this.capabilityLines = lines;
  }

  /** bad（DB 异常）/ warn（voice 未就绪）/ ok。 */
  level(): string {
    if (this.status === 'degraded' || !this.dbOk) {
      return 'bad';
    }
    if (!this.voiceReachable) {
      return 'warn';
    }
    return 'ok';
  }

  levelTitle(): string {
    const level = this.level();
    if (level === 'bad') {
      return '服务异常';
    }
    if (level === 'warn') {
      return '语音服务未就绪';
    }
    return '服务正常';
  }

  levelDetail(): string {
    const level = this.level();
    if (level === 'bad') {
      return '数据库不可用，练习记录可能无法保存';
    }
    if (level === 'warn') {
      return this.voiceHint.length > 0 ? this.voiceHint : 'voice 未就绪：录音与文本仍会入库，评测稍后可重试';
    }
    return '数据库与语音服务均可用';
  }

  voiceSummary(): string {
    if (!this.voiceReachable) {
      return '语音服务：未就绪';
    }
    const mode = this.voiceMode.length > 0 ? this.voiceMode : 'unknown';
    return '语音服务：已就绪（mode=' + mode + '，音素级=' + HealthVM.support(this.phonemeLevel) +
      '，语调曲线=' + HealthVM.support(this.intonationCurve) + '）';
  }

  static support(value: boolean): string {
    return value ? '支持' : '不支持';
  }
}


import { UiError } from '../core/error/UiError';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  StoryCardItem,
  StoryGroup,
  StoryMaterialDto,
  StoryRetellDto,
  StoryRetellRecord,
  StoryRewriteDto,
  StorySentenceItem
} from '../core/net/StoryDtos';
import { AudioController } from '../core/audio/AudioController';
import { MicPermission, RecordingResult } from '../core/audio/AudioRecorder';
import { AccountPrefs } from '../core/content/AccountPrefs';
import { CapabilityCache } from '../core/content/CapabilityCache';
import { CacheService } from '../core/service/CacheService';
import { StoryService } from '../core/service/StoryService';
import { SessionStore } from '../core/session/SessionStore';
import { FileUtil } from '../core/util/FileUtil';

/**
 * 「本次会话」跨页共享的临时数据。
 *
 * 线上没有 /api/story/recordings（2026-11-03 实测 404），中文录音只能降级走 /api/asr，
 * 所以「我当时讲的原话」不可能跨会话保留：这里只在内存里留本次刚录的文件路径/原文，
 * 详情页必须标注「本次录音，仅本次可用」。
 */
export class StoryRuntime {
  /** key = userId#materialId（中文原文/原声/复述都只属于本人，切账号不串） */
  private static originals: Map<string, string> = new Map();
  private static originalTexts: Map<string, string> = new Map();
  private static retells: Map<string, StoryRetellRecord[]> = new Map();

  private static key(userId: string, materialId: string): string {
    return (userId.length === 0 ? 'anon' : userId) + '#' + materialId;
  }

  static setOriginal(userId: string, materialId: string, audioPath: string, textZh: string): void {
    if (materialId.length === 0 || audioPath.length === 0) {
      return;
    }
    const key = StoryRuntime.key(userId, materialId);
    StoryRuntime.originals.set(key, audioPath);
    StoryRuntime.originalTexts.set(key, textZh);
  }

  static originalAudio(userId: string, materialId: string): string {
    const path = StoryRuntime.originals.get(StoryRuntime.key(userId, materialId));
    return path === undefined ? '' : path;
  }

  static originalText(userId: string, materialId: string): string {
    const text = StoryRuntime.originalTexts.get(StoryRuntime.key(userId, materialId));
    return text === undefined ? '' : text;
  }

  static addRetell(userId: string, materialId: string, record: StoryRetellRecord): void {
    if (materialId.length === 0) {
      return;
    }
    const key = StoryRuntime.key(userId, materialId);
    let list = StoryRuntime.retells.get(key);
    if (list === undefined) {
      list = [];
      StoryRuntime.retells.set(key, list);
    }
    record.userId = userId;
    list.unshift(record);
    while (list.length > 5) {
      list.pop();
    }
    StoryRuntime.bump('storyRetellTick');
  }

  static retellsOf(userId: string, materialId: string): StoryRetellRecord[] {
    const list = StoryRuntime.retells.get(StoryRuntime.key(userId, materialId));
    // 返回副本：页面拿到新数组引用才会触发刷新
    return list === undefined ? [] : list.slice();
  }

  /** 保存新故事后通知故事集刷新（Tab 根页与详情页不在一条生命周期上）。 */
  static notifySaved(): void {
    StoryRuntime.bump('storyRefreshTick');
  }

  private static bump(key: string): void {
    const current = AppStorage.get<number>(key);
    const next = (current === undefined ? 0 : current) + 1;
    AppStorage.setOrCreate<number>(key, next);
  }
}

/** 本地日期工具：按设备时区分组「今天/昨天/更早」并计算连续天数。 */
export class StoryDates {
  static keyOf(date: Date): string {
    return date.getFullYear().toString() + '-' +
      StoryDates.pad2(date.getMonth() + 1) + '-' +
      StoryDates.pad2(date.getDate());
  }

  static keyFromIso(iso: string): string {
    if (iso.length === 0) {
      return '';
    }
    const date = new Date(iso);
    if (!(date.getTime() > 0)) {
      return '';
    }
    return StoryDates.keyOf(date);
  }

  static keyToDate(key: string): Date | null {
    const parts = key.split('-');
    if (parts.length !== 3) {
      return null;
    }
    const year = parseInt(parts[0], 10);
    const month = parseInt(parts[1], 10);
    const day = parseInt(parts[2], 10);
    if (!(year > 2000) || !(month >= 1) || !(day >= 1)) {
      return null;
    }
    return new Date(year, month - 1, day);
  }

  static shiftDays(date: Date, days: number): Date {
    const copy = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    copy.setDate(copy.getDate() + days);
    return copy;
  }

  static displayText(key: string): string {
    const parts = key.split('-');
    if (parts.length !== 3) {
      return '';
    }
    const month = parseInt(parts[1], 10);
    const day = parseInt(parts[2], 10);
    if (!(month >= 1) || !(day >= 1)) {
      return '';
    }
    return month.toString() + '月' + day.toString() + '日';
  }

  static labelOf(key: string, todayKey: string, yesterdayKey: string): string {
    if (key === todayKey) {
      return '今天';
    }
    if (key === yesterdayKey) {
      return '昨天';
    }
    return '更早';
  }

  static pad2(value: number): string {
    return value < 10 ? ('0' + value.toString()) : value.toString();
  }
}

// ---------------------------------------------------------------------------
// 故事集（Tab 根页）
// ---------------------------------------------------------------------------

@Observed
export class StoryHomeVM {
  loading: boolean = true;
  loadError: string = '';
  total: number = 0;
  filteredCount: number = 0;
  streakDays: number = 0;
  onlyMine: boolean = false;
  groups: StoryGroup[] = [];
  private allItems: StoryCardItem[] = [];
  private userId: string = '';
  private isChild: boolean = false;

  setUser(userId: string, isChild: boolean): void {
    this.userId = userId;
    this.isChild = isChild;
  }

  async load(): Promise<void> {
    this.loadError = '';
    if (this.allItems.length === 0) {
      this.loading = true;
    }
    try {
      const list = await StoryService.materials(50, 0);
      this.applyList(list);
    } catch (err) {
      const ui: UiError = SessionStore.toUiError(err as Error, this.isChild);
      this.loadError = ui.message;
    } finally {
      this.loading = false;
    }
  }

  setOnlyMine(value: boolean): void {
    if (this.onlyMine === value) {
      return;
    }
    this.onlyMine = value;
    this.rebuildGroups();
  }

  private applyList(list: StoryMaterialDto[]): void {
    const items: StoryCardItem[] = [];
    for (let i = 0; i < list.length; i++) {
      const material = list[i];
      const card = new StoryCardItem();
      card.id = material.id;
      const title = material.title;
      card.title = (title === undefined || title.trim().length === 0) ? '未命名故事' : title.trim();
      const level = material.level;
      card.level = (level === undefined || level === null) ? '' : level;
      card.sentenceCount = material.sentence_count === undefined ? 0 : material.sentence_count;
      card.authorName = material.created_by_name === undefined ? '' : material.created_by_name;
      card.authorId = (material.created_by === undefined || material.created_by === null)
        ? '' : material.created_by;
      card.hasImage = material.has_image === true;
      card.hasSourceZh = material.has_source_zh === true;
      card.createdAt = material.created_at === undefined ? '' : material.created_at;
      card.dateKey = StoryDates.keyFromIso(card.createdAt);
      card.dateText = StoryDates.displayText(card.dateKey);
      card.material = material;
      items.push(card);
    }
    this.allItems = items;
    this.total = items.length;
    this.streakDays = StoryHomeVM.computeStreak(items);
    this.rebuildGroups();
  }

  private rebuildGroups(): void {
    const today = new Date();
    const todayKey = StoryDates.keyOf(today);
    const yesterdayKey = StoryDates.keyOf(StoryDates.shiftDays(today, -1));
    const groups: StoryGroup[] = [];
    const labels: string[] = [];
    let count = 0;
    for (let i = 0; i < this.allItems.length; i++) {
      const item = this.allItems[i];
      if (this.onlyMine && item.authorId !== this.userId) {
        continue;
      }
      const label = item.dateKey.length === 0
        ? '更早'
        : StoryDates.labelOf(item.dateKey, todayKey, yesterdayKey);
      item.dateLabel = label;
      let index = -1;
      for (let g = 0; g < labels.length; g++) {
        if (labels[g] === label) {
          index = g;
          break;
        }
      }
      if (index < 0) {
        labels.push(label);
        const group = new StoryGroup();
        group.label = label;
        groups.push(group);
        index = groups.length - 1;
      }
      groups[index].items.push(item);
      count++;
    }
    this.groups = groups;
    this.filteredCount = count;
  }

  /** 连续天数：从今天（或昨天）往前数连续有故事的天数。 */
  private static computeStreak(items: StoryCardItem[]): number {
    const keys: string[] = [];
    for (let i = 0; i < items.length; i++) {
      const key = items[i].dateKey;
      if (key.length === 0) {
        continue;
      }
      if (keys.indexOf(key) < 0) {
        keys.push(key);
      }
    }
    if (keys.length === 0) {
      return 0;
    }
    keys.sort((a: string, b: string) => {
      if (a < b) {
        return -1;
      }
      return a > b ? 1 : 0;
    });
    const today = new Date();
    const todayKey = StoryDates.keyOf(today);
    const yesterdayKey = StoryDates.keyOf(StoryDates.shiftDays(today, -1));
    let startKey = '';
    if (keys.indexOf(todayKey) >= 0) {
      startKey = todayKey;
    } else if (keys.indexOf(yesterdayKey) >= 0) {
      startKey = yesterdayKey;
    }
    if (startKey.length === 0) {
      return 0;
    }
    let cursor = StoryDates.keyToDate(startKey);
    if (cursor === null) {
      return 0;
    }
    let count = 0;
    while (true) {
      const key = StoryDates.keyOf(cursor);
      if (keys.indexOf(key) < 0) {
        break;
      }
      count++;
      cursor = StoryDates.shiftDays(cursor, -1);
    }
    return count;
  }
}

// ---------------------------------------------------------------------------
// 讲故事（录音 → ASR → 可编辑中文 → 改写 → 预览 → 保存）
// ---------------------------------------------------------------------------

enum RecordAction {
  NONE = 0,
  ASR = 1,
  REWRITE = 2,
  SAVE = 3
}

@Observed
export class StoryRecordVM {
  textZh: string = '';
  level: string = 'A1';
  maxSentences: number = 5;
  levels: string[] = ['A1', 'A2', 'B1', 'B2', 'C1'];
  sentenceOptions: number[] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  isChild: boolean = false;

  preparing: boolean = false;
  recording: boolean = false;
  elapsedMs: number = 0;

  busy: boolean = false;
  busyText: string = '';
  /** 绿色提示（ASR 成功等） */
  notice: string = '';

  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');
  errorActionLabel: string = '';

  hasResult: boolean = false;
  title: string = '';
  sentences: StorySentenceItem[] = [];
  readabilityText: string = '';
  unknownWordsText: string = '';
  warningText: string = '';
  weakPhonemes: string[] = [];

  saving: boolean = false;

  /** 当前登录用户（原声/复述按人隔离） */
  userId: string = '';

  private originalPath: string = '';
  private originalTextZh: string = '';
  private recordStartedAt: number = 0;
  private timerId: number = -1;
  private lastAction: RecordAction = RecordAction.NONE;

  configure(isChild: boolean, cefrLevel: string, userId: string): void {
    this.isChild = isChild;
    this.level = StoryRecordVM.normalizeLevel(cefrLevel);
    this.maxSentences = isChild ? 5 : 8;
    this.userId = userId;
    void this.applyAccountPrefs();
  }

  /** 账号偏好里的故事句数（3–12）优先于角色默认 5/8。 */
  private async applyAccountPrefs(): Promise<void> {
    await AccountPrefs.ensure();
    const count = AccountPrefs.storySentences;
    if (count >= 3 && count <= 12) {
      this.maxSentences = count;
    }
  }

  setTextZh(value: string): void {
    this.textZh = value;
  }

  /** 改级别：已有结果时按规格自动重新生成。 */
  selectLevel(value: string): void {
    if (this.level === value) {
      return;
    }
    this.level = value;
    if (this.hasResult && !this.busy) {
      void this.rewrite();
    }
  }

  setMaxSentences(value: number): void {
    this.maxSentences = value;
  }

  adjustLevel(direction: number): void {
    const index = this.levels.indexOf(this.level);
    let next = index < 0 ? 0 : index + direction;
    if (next < 0) {
      next = 0;
    }
    if (next >= this.levels.length) {
      next = this.levels.length - 1;
    }
    this.selectLevel(this.levels[next]);
  }

  // ------------------------------------------------------------------ 录音 / ASR

  async startRecording(): Promise<void> {
    if (this.recording || this.preparing || this.busy) {
      return;
    }
    this.clearError();
    this.notice = '';
    this.preparing = true;
    try {
      await AudioController.startRecording();
      this.recording = true;
      this.recordStartedAt = Date.now();
      this.elapsedMs = 0;
      this.startTimer();
    } catch (err) {
      this.handleError(err as Error);
    } finally {
      this.preparing = false;
    }
  }

  async stopRecordingAndRecognize(): Promise<void> {
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
    this.originalPath = recorded.path;
    await this.recognize(recorded.path);
  }

  async cancelRecording(): Promise<void> {
    this.recording = false;
    this.stopTimer();
    this.elapsedMs = 0;
    await AudioController.cancelRecording();
  }

  /** 重新识别（录音已落盘，不用重录）——线上降级路径：/api/asr?language=zh-CN。 */
  async retryRecognize(): Promise<void> {
    if (this.originalPath.length === 0 || this.busy) {
      return;
    }
    await this.recognize(this.originalPath);
  }

  private async recognize(path: string): Promise<void> {
    this.busy = true;
    this.busyText = this.isChild ? '正在听懂你的话… ⏳' : '正在识别中文录音…';
    this.lastAction = RecordAction.ASR;
    try {
      const text = await StoryService.asr(path, 'zh-CN');
      const current = this.textZh.trim();
      this.textZh = current.length === 0 ? text : (current + '\n' + text);
      this.notice = '听到啦，已经写进上面的框里了 ✅';
      this.clearError();
    } catch (err) {
      this.handleError(err as Error);
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval(() => {
      this.elapsedMs = Date.now() - this.recordStartedAt;
      if (this.elapsedMs >= 120000) {
        void this.stopRecordingAndRecognize();
      }
    }, 200);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // ------------------------------------------------------------------ 改写

  async rewrite(): Promise<void> {
    if (this.busy) {
      return;
    }
    const text = this.textZh.trim();
    if (text.length === 0) {
      this.setLocalError(this.isChild ? '先讲讲你的故事吧 🙂' : '请先用中文讲讲你的故事（不能为空）');
      return;
    }
    if (text.length > 2000) {
      this.setLocalError('故事太长了（' + text.length.toString() + ' 字），最多 2000 字');
      return;
    }
    this.clearError();
    this.notice = '';
    // 先清掉旧预览：重新生成后 ForEach 才能用新文案重建（避免沿用旧句子控件）
    this.hasResult = false;
    this.sentences = [];
    this.busy = true;
    this.busyText = this.isChild ? '✍️ 正在把故事变成英文… 大约几秒' : '✍️ 正在把你的故事变成英文…';
    this.lastAction = RecordAction.REWRITE;
    try {
      const dto = await StoryService.rewrite(text, this.level, this.maxSentences);
      this.applyRewrite(dto);
      this.originalTextZh = text;
    } catch (err) {
      this.handleError(err as Error);
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  private applyRewrite(dto: StoryRewriteDto): void {
    this.hasResult = true;
    const title = dto.title_en;
    this.title = (title === undefined || title.trim().length === 0) ? 'My Story' : title.trim();
    const items: StorySentenceItem[] = [];
    const sentences = dto.sentences;
    if (sentences !== undefined && sentences.length > 0) {
      for (let i = 0; i < sentences.length; i++) {
        const text = sentences[i].trim();
        if (text.length === 0) {
          continue;
        }
        const item = new StorySentenceItem();
        item.index = items.length + 1;
        item.en = text;
        items.push(item);
      }
    } else {
      const textEn = dto.text_en === undefined ? '' : dto.text_en;
      const lines = StoryRecordVM.splitSentences(textEn);
      for (let i = 0; i < lines.length; i++) {
        const item = new StorySentenceItem();
        item.index = i + 1;
        item.en = lines[i];
        items.push(item);
      }
    }
    this.sentences = items;

    const readability = dto.readability;
    if (readability === undefined) {
      this.readabilityText = '';
      this.unknownWordsText = '';
    } else {
      const count = readability.sentence_count === undefined ? items.length : readability.sentence_count;
      const avg = readability.avg_words === undefined ? 0 : readability.avg_words;
      const max = readability.max_words === undefined ? 0 : readability.max_words;
      this.readabilityText = '可读性：' + count.toString() + ' 句 · 平均 ' +
        (Math.round(avg * 10) / 10).toString() + ' 词/句 · 最长 ' + max.toString() + ' 词';
      const unknown = readability.unknown_words;
      if (unknown === undefined || unknown.length === 0) {
        this.unknownWordsText = '';
      } else {
        this.unknownWordsText = '可能偏难的词：' + unknown.join('、');
      }
    }

    let warningText = '';
    const warnings = dto.warnings;
    if (warnings !== undefined) {
      if (warnings.indexOf('too_hard') >= 0) {
        warningText = '这段可能有点难，要不要点「再简单一点」？';
      }
      if (warnings.indexOf('too_many_sentences') >= 0) {
        warningText = '故事偏长（超过设定的句数），可以调高句子数，或删掉几句再保存';
      }
      if (warnings.indexOf('tense_mismatch') >= 0) {
        warningText = '时态可能和中文原意不一致（叙事一般用过去时），可以点「重新生成」再试一次';
      }
    }
    this.warningText = warningText;
    const weak = dto.weak_phonemes_used;
    this.weakPhonemes = weak === undefined ? [] : weak;
  }

  setSentenceEn(index: number, value: string): void {
    if (index < 0 || index >= this.sentences.length) {
      return;
    }
    this.sentences[index].en = value;
  }

  setTitle(value: string): void {
    this.title = value;
  }

  // ------------------------------------------------------------------ 保存

  /** 保存并返回 material_id（空串 = 失败）。成功后页面跳详情。 */
  async save(): Promise<string> {
    if (this.saving || this.busy || !this.hasResult) {
      return '';
    }
    const title = this.title.trim();
    if (title.length === 0) {
      this.setLocalError('给故事起个标题吧');
      return '';
    }
    const parts: string[] = [];
    for (let i = 0; i < this.sentences.length; i++) {
      const text = this.sentences[i].en.trim();
      if (text.length > 0) {
        parts.push(text);
      }
    }
    if (parts.length === 0) {
      this.setLocalError('英文故事不能为空，先点「重新生成」试试');
      return '';
    }
    const text = parts.join('\n');
    const sourceZh = this.originalTextZh.length > 0 ? this.originalTextZh : this.textZh.trim();
    this.saving = true;
    this.lastAction = RecordAction.SAVE;
    try {
      const created = await StoryService.createMaterial(title, text, sourceZh, this.level);
      if (this.originalPath.length > 0 && FileUtil.exists(this.originalPath)) {
        StoryRuntime.setOriginal(this.userId, created.id, this.originalPath, sourceZh);
      }
      StoryRuntime.notifySaved();
      // 账号偏好 auto_illustrate=开 时，保存后按 Web 行为自动画一张（失败静默，详情页可手动重画）
      if (AccountPrefs.autoIllustrate) {
        await CapabilityCache.ensure();
        if (CapabilityCache.image) {
          StoryService.illustrate(created.id, false).catch(() => {
          });
        }
      }
      this.clearError();
      return created.id;
    } catch (err) {
      this.handleError(err as Error);
      return '';
    } finally {
      this.saving = false;
    }
  }

  // ------------------------------------------------------------------ 错误 / 生命周期

  async onErrorAction(): Promise<void> {
    if (this.errorActionLabel.length === 0) {
      return;
    }
    if (this.error.code === 'mic_denied') {
      const granted = await MicPermission.openSettings();
      if (granted) {
        this.clearError();
      }
      return;
    }
    const action = this.lastAction;
    this.clearError();
    if (action === RecordAction.ASR) {
      await this.retryRecognize();
    } else if (action === RecordAction.REWRITE) {
      await this.rewrite();
    }
  }

  clearError(): void {
    this.hasError = false;
    this.errorActionLabel = '';
  }

  private setLocalError(message: string): void {
    this.setError(new UiError('', message, '', false, 'bad_request'), '');
  }

  private setError(error: UiError, actionLabel: string): void {
    this.error = error;
    this.hasError = true;
    this.errorActionLabel = actionLabel;
  }

  private handleError(err: Error): void {
    const ui: UiError = SessionStore.toUiError(err, this.isChild);
    let actionLabel = '';
    if (ui.code === 'mic_denied') {
      actionLabel = '去设置';
    } else if (this.lastAction === RecordAction.ASR) {
      actionLabel = this.isChild ? '再试一次' : '重新识别';
    } else if (this.lastAction === RecordAction.REWRITE) {
      actionLabel = this.isChild ? '再试一次' : '重试';
    }
    this.setError(ui, actionLabel);
  }

  dispose(): void {
    this.stopTimer();
    this.recording = false;
    this.preparing = false;
    void AudioController.stopAll();
  }

  // ------------------------------------------------------------------ 工具

  private static normalizeLevel(cefr: string): string {
    const upper = cefr.trim().toUpperCase();
    if (upper === 'A1' || upper === 'A2' || upper === 'B1' || upper === 'B2' || upper === 'C1') {
      return upper;
    }
    return 'A2';
  }

  /** 英文正文 → 句子数组（先按换行；只有一行时按句号再拆）。 */
  static splitSentences(text: string): string[] {
    const result: string[] = [];
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length > 0) {
        result.push(line);
      }
    }
    if (result.length > 1) {
      return result;
    }
    const single = result.length === 1 ? result[0] : text.trim();
    if (single.length === 0) {
      return result;
    }
    const pieces = single.split('. ');
    if (pieces.length <= 1) {
      return result;
    }
    const split: string[] = [];
    for (let i = 0; i < pieces.length; i++) {
      let piece = pieces[i].trim();
      if (piece.length === 0) {
        continue;
      }
      if (i < pieces.length - 1 && !piece.endsWith('.')) {
        piece = piece + '.';
      }
      split.push(piece);
    }
    return split;
  }
}

// ---------------------------------------------------------------------------
// 故事详情
// ---------------------------------------------------------------------------

enum DetailAction {
  NONE = 0,
  ILLUSTRATE = 1,
  AUDIO = 2,
  ORIGINAL = 3
}

@Observed
export class StoryDetailVM {
  loading: boolean = true;
  loadError: string = '';

  storyId: string = '';
  title: string = '';
  level: string = '';
  dateText: string = '';
  sentenceCount: number = 0;
  authorName: string = '';
  isChild: boolean = false;

  textEn: string = '';
  sentences: StorySentenceItem[] = [];
  sourceZh: string = '';
  hasSourceZh: boolean = false;
  showSource: boolean = false;

  imageLoading: boolean = false;
  imagePath: string = '';
  imageError: string = '';
  imagePrompt: string = '';
  hasImage: boolean = false;
  showPrompt: boolean = false;

  /** checking | building | ready | failed | no_audio */
  audioState: string = 'checking';
  audioStatusText: string = '';
  audioDurationText: string = '';
  audioLoading: boolean = false;
  audioPlaying: boolean = false;
  audioPath: string = '';
  audioError: string = '';

  originalPath: string = '';
  originalText: string = '';
  originalPlaying: boolean = false;

  retells: StoryRetellRecord[] = [];

  /** 当前登录用户（中文原文/原声/复述/朗读缓存都只属于本人） */
  userId: string = '';
  /** 故事创建者 id（隐私：中文原文仅创建者可见） */
  createdBy: string = '';

  private pollTimerId: number = -1;
  private pollCount: number = 0;
  private lastAction: DetailAction = DetailAction.NONE;

  configure(isChild: boolean, userId: string): void {
    this.isChild = isChild;
    this.userId = userId;
  }

  /** 中文原文是否可见：服务端只给创建者；客户端再兜一层（防旧服务端）。 */
  canSeeSource(): boolean {
    if (!this.hasSourceZh) {
      return false;
    }
    return this.createdBy.length === 0 || this.createdBy === this.userId;
  }

  async load(id: string): Promise<void> {
    this.storyId = id;
    this.loading = true;
    this.loadError = '';
    this.pollCount = 0;
    try {
      const dto: StoryMaterialDto = await StoryService.materialDetail(id);
      this.applyDetail(dto);
    } catch (err) {
      const ui: UiError = SessionStore.toUiError(err as Error, this.isChild);
      this.loadError = ui.message;
      this.loading = false;
      return;
    }
    this.loading = false;
    this.originalPath = StoryRuntime.originalAudio(this.userId, id);
    this.originalText = StoryRuntime.originalText(this.userId, id);
    this.retells = StoryRuntime.retellsOf(this.userId, id);
    if (this.hasImage) {
      this.imageLoading = true;
      try {
        await this.downloadImage();
      } finally {
        this.imageLoading = false;
      }
    }
    // 不在进入详情时自动画图：每张约 ¥0.1，必须由用户点「给我画一张」触发（与 Web 行为一致）
    void this.checkAudio(false);
  }

  private applyDetail(dto: StoryMaterialDto): void {
    const title = dto.title;
    this.title = (title === undefined || title.trim().length === 0) ? '未命名故事' : title.trim();
    const level = dto.level;
    this.level = (level === undefined || level === null) ? '' : level;
    this.dateText = StoryDates.displayText(StoryDates.keyFromIso(dto.created_at === undefined ? '' : dto.created_at));
    this.sentenceCount = dto.sentence_count === undefined ? 0 : dto.sentence_count;
    this.authorName = dto.created_by_name === undefined ? '' : dto.created_by_name;
    this.createdBy = (dto.created_by === undefined || dto.created_by === null) ? '' : dto.created_by;
    this.textEn = dto.text === undefined ? '' : dto.text;
    const source = dto.source_zh;
    this.hasSourceZh = source !== undefined && source !== null && source.trim().length > 0;
    this.sourceZh = (source === undefined || source === null) ? '' : source;
    const lines = StoryRecordVM.splitSentences(this.textEn);
    const items: StorySentenceItem[] = [];
    for (let i = 0; i < lines.length; i++) {
      const item = new StorySentenceItem();
      item.index = i + 1;
      item.en = lines[i];
      items.push(item);
    }
    this.sentences = items;
    this.hasImage = dto.has_image === true ||
      (dto.image_url !== undefined && dto.image_url !== null && dto.image_url.length > 0);
    const prompt = dto.image_prompt;
    this.imagePrompt = (prompt === undefined || prompt === null) ? '' : prompt;
  }

  toggleSource(): void {
    this.showSource = !this.showSource;
  }

  togglePrompt(): void {
    this.showPrompt = !this.showPrompt;
  }

  refreshRetells(): void {
    this.retells = StoryRuntime.retellsOf(this.userId, this.storyId);
  }

  reportImageError(): void {
    this.imagePath = '';
    this.imageError = '插画暂时显示不出来，点「重新加载」再试（不会重新生成）';
  }

  /** 仅重新下载已有插画（不触发生成、不扣费）。 */
  async reloadImage(): Promise<void> {
    if (this.imageLoading || !this.hasImage) {
      return;
    }
    this.imageLoading = true;
    this.imageError = '';
    try {
      await this.downloadImage();
    } finally {
      this.imageLoading = false;
    }
  }

  // ------------------------------------------------------------------ 插画

  async illustrate(force: boolean): Promise<void> {
    if (this.imageLoading || this.storyId.length === 0) {
      return;
    }
    if (!force && this.hasImage) {
      return;
    }
    this.imageLoading = true;
    this.imageError = '';
    this.lastAction = DetailAction.ILLUSTRATE;
    try {
      const dto = await StoryService.illustrate(this.storyId, force);
      const prompt = dto.prompt_used;
      if (prompt !== undefined) {
        this.imagePrompt = prompt;
      }
      const url = dto.image_url;
      if (url !== undefined && url !== null && url.length > 0) {
        const dest = CacheService.audioDir() + '/story_' + this.storyId + '_img.png';
        await StoryService.downloadImageUrl(url, dest);
        this.imagePath = dest;
        this.hasImage = true;
      } else {
        await this.downloadImage();
      }
    } catch (err) {
      const ui: UiError = SessionStore.toUiError(err as Error, this.isChild);
      this.imageError = ui.message;
    } finally {
      this.imageLoading = false;
    }
  }

  private async downloadImage(): Promise<void> {
    const dest = CacheService.audioDir() + '/story_' + this.storyId + '_img.png';
    if (FileUtil.exists(dest)) {
      this.imagePath = dest;
      this.imageError = '';
      return;
    }
    try {
      await StoryService.downloadMaterialImage(this.storyId, dest);
      this.imagePath = dest;
      this.imageError = '';
    } catch (err) {
      // 下载失败 ≠ 没有插画：保留 hasImage，页面给「重新加载」，不要引导去花 ¥0.1 重画
      this.imagePath = '';
      this.imageError = '插画暂时加载不出来，点「重新加载」再试（不会重新生成）';
    }
  }

  // ------------------------------------------------------------------ 整段朗读回放

  /** 只读 status；building 时每 2s 轮询（最多 30 次）。 */
  async checkAudio(reset: boolean): Promise<void> {
    this.clearPollTimer();
    if (reset) {
      this.pollCount = 0;
      this.audioState = 'checking';
      this.audioStatusText = '正在检查朗读录音…';
    }
    try {
      const dto = await StoryService.audioStatus(this.storyId);
      const status = dto.status === undefined ? 'building' : dto.status;
      if (status === 'ready') {
        const duration = dto.duration_ms;
        this.audioDurationText = duration === undefined ? ''
          : ('时长 ' + Math.round(duration / 1000).toString() + ' 秒');
        this.audioState = 'ready';
        this.audioStatusText = this.isChild ? '听一听我读的故事' : '整段朗读回放';
      } else if (status === 'building') {
        this.audioState = 'building';
        this.audioStatusText = '正在生成整段回放…（可以先看文字）';
        this.scheduleAudioPoll();
      } else if (status === 'failed') {
        const attempts = dto.attempt_count === undefined ? 0 : dto.attempt_count;
        if (attempts === 0) {
          // 服务端对「没有任何朗读录音」的故事也回 failed+error；
          // 这时根本没有可拼接的源，不要给「重新生成」（点了也只会得到 failed，还可能卡住）
          this.audioState = 'no_audio';
          this.audioStatusText = this.isChild
            ? '先读一遍这个故事，才能听整段朗读哦' : '这个故事还没有可回放的朗读录音，先读一遍再来听吧';
        } else {
          this.audioState = 'failed';
          const error = dto.error;
          this.audioStatusText = (error === undefined || error.length === 0)
            ? '整段朗读生成失败了，可以点「重新生成」' : error;
        }
      } else {
        this.audioState = 'no_audio';
        const error = dto.error;
        this.audioStatusText = (error === undefined || error.length === 0)
          ? '这个故事还没有可回放的朗读录音，先读一遍再来听吧' : error;
      }
    } catch (err) {
      this.audioState = 'failed';
      const ui: UiError = SessionStore.toUiError(err as Error, this.isChild);
      this.audioStatusText = ui.message;
    }
  }

  private scheduleAudioPoll(): void {
    if (this.pollCount >= 30) {
      this.audioState = 'failed';
      this.audioStatusText = '生成超时了，可以点「重新生成」再试';
      return;
    }
    this.pollCount++;
    this.pollTimerId = setTimeout(() => {
      void this.checkAudio(false);
    }, 2000);
  }

  async playAudio(): Promise<void> {
    if (this.audioLoading) {
      return;
    }
    if (AudioController.isRecording()) {
      this.audioError = '正在录音，先说完这一句';
      return;
    }
    this.audioError = '';
    this.audioLoading = true;
    this.lastAction = DetailAction.AUDIO;
    try {
      const dest = CacheService.audioDir() + '/story_' + this.storyId + '_read_' + (this.userId.length > 0 ? this.userId : 'anon') + '.wav';
      if (!FileUtil.exists(dest)) {
        const downloaded = await StoryService.downloadStoryAudio(this.storyId, dest, false);
        if (!downloaded) {
          this.audioState = 'building';
          this.audioStatusText = '正在生成整段回放…（可以先看文字）';
          this.scheduleAudioPoll();
          return;
        }
      }
      this.audioPath = dest;
      this.audioPlaying = true;
      await AudioController.play(dest, () => {
        this.audioPlaying = false;
      });
    } catch (err) {
      this.audioState = 'failed';
      const ui: UiError = SessionStore.toUiError(err as Error, this.isChild);
      this.audioStatusText = ui.message;
      this.audioError = ui.message;
    } finally {
      this.audioLoading = false;
    }
  }

  /** failed 时按规格先 `GET /story/:id/audio?force=1` 触发重建，再轮询 status。 */
  async retryAudio(): Promise<void> {
    if (this.storyId.length === 0) {
      return;
    }
    this.pollCount = 0;
    this.audioError = '';
    this.audioState = 'building';
    this.audioStatusText = '正在重新生成整段朗读…';
    try {
      const dest = CacheService.audioDir() + '/story_' + this.storyId + '_read_' + (this.userId.length > 0 ? this.userId : 'anon') + '.wav';
      FileUtil.remove(dest);
      const downloaded = await StoryService.downloadStoryAudio(this.storyId, dest, true);
      if (downloaded) {
        this.audioPath = dest;
        this.audioState = 'ready';
        this.audioStatusText = this.isChild ? '听一听我读的故事' : '整段朗读回放';
        return;
      }
    } catch (err) {
      // force 重建失败（404 no_audio / 500 audio_failed）→ 落到 status 展示可读提示
      const e = err as Error;
      hilog.warn(0xEC00, 'StoryVM', 'retryAudio force build failed: %{public}s', e.message);
    }
    try {
      await this.checkAudio(true);
    } catch (err) {
      this.audioState = 'failed';
      this.audioStatusText = '整段朗读暂时生成不了，可以稍后再试';
    }
  }

  /** 播放「我当时讲的原话」——只有本次会话刚录的音才有文件。 */
  async playOriginal(): Promise<void> {
    if (this.originalPath.length === 0) {
      return;
    }
    if (AudioController.isRecording()) {
      this.audioError = '正在录音，先说完这一句';
      return;
    }
    try {
      this.originalPlaying = true;
      await AudioController.play(this.originalPath, () => {
        this.originalPlaying = false;
      });
    } catch (err) {
      this.originalPlaying = false;
      const ui: UiError = SessionStore.toUiError(err as Error, this.isChild);
      this.audioError = ui.message;
    }
  }

  async stopPlayback(): Promise<void> {
    await AudioController.stopPlayback();
    this.audioPlaying = false;
    this.originalPlaying = false;
  }

  private clearPollTimer(): void {
    if (this.pollTimerId >= 0) {
      clearTimeout(this.pollTimerId);
      this.pollTimerId = -1;
    }
  }

  dispose(): void {
    this.clearPollTimer();
    this.audioPlaying = false;
    this.originalPlaying = false;
    void AudioController.stopAll();
  }
}

// ---------------------------------------------------------------------------
// 复述（录音/文本 → /api/story/retell）
// ---------------------------------------------------------------------------

enum ReviewAction {
  NONE = 0,
  ASR = 1,
  RETELL = 2
}

@Observed
export class StoryReviewVM {
  loading: boolean = true;
  loadError: string = '';
  storyId: string = '';
  storyTitle: string = '';
  level: string = 'A2';
  isChild: boolean = false;
  storySentences: string[] = [];

  textMode: boolean = false;
  typedText: string = '';
  transcript: string = '';

  preparing: boolean = false;
  recording: boolean = false;
  elapsedMs: number = 0;
  busy: boolean = false;
  busyText: string = '';

  hasResult: boolean = false;
  coveragePercent: number = -1;
  coveredCount: number = 0;
  coveredPoints: string[] = [];
  missingPoints: string[] = [];
  feedbackZh: string = '';
  feedbackEn: string = '';

  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');
  errorActionLabel: string = '';

  private recordPath: string = '';
  private recordStartedAt: number = 0;
  private timerId: number = -1;
  private lastAction: ReviewAction = ReviewAction.NONE;
  private lastTranscript: string = '';

  userId: string = '';

  async load(id: string, isChild: boolean, cefrLevel: string, userId: string): Promise<void> {
    this.storyId = id;
    this.isChild = isChild;
    this.userId = userId;
    this.level = StoryReviewVM.normalizeLevel(cefrLevel);
    this.loading = true;
    this.loadError = '';
    try {
      const dto: StoryMaterialDto = await StoryService.materialDetail(id);
      const title = dto.title;
      this.storyTitle = (title === undefined || title.trim().length === 0) ? '这个故事' : title.trim();
      const level = dto.level;
      if (level !== undefined && level !== null && level.length > 0) {
        this.level = level;
      }
      this.storySentences = StoryRecordVM.splitSentences(dto.text === undefined ? '' : dto.text);
    } catch (err) {
      const ui: UiError = SessionStore.toUiError(err as Error, isChild);
      this.loadError = ui.message;
    } finally {
      this.loading = false;
    }
  }

  setTextMode(value: boolean): void {
    this.textMode = value;
  }

  setTypedText(value: string): void {
    this.typedText = value;
  }

  // ------------------------------------------------------------------ 录音 → ASR(en-US) → retell

  async startRecording(): Promise<void> {
    if (this.recording || this.preparing || this.busy) {
      return;
    }
    this.clearError();
    this.preparing = true;
    try {
      await AudioController.startRecording();
      this.recording = true;
      this.recordStartedAt = Date.now();
      this.elapsedMs = 0;
      this.startTimer();
    } catch (err) {
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
    await this.recognizeAndSubmit(recorded.path);
  }

  async cancelRecording(): Promise<void> {
    this.recording = false;
    this.stopTimer();
    this.elapsedMs = 0;
    await AudioController.cancelRecording();
  }

  async retryRecognize(): Promise<void> {
    if (this.recordPath.length === 0 || this.busy) {
      return;
    }
    await this.recognizeAndSubmit(this.recordPath);
  }

  private async recognizeAndSubmit(path: string): Promise<void> {
    this.busy = true;
    this.busyText = '正在听懂你的复述… ⏳';
    this.lastAction = ReviewAction.ASR;
    let transcript = '';
    try {
      transcript = await StoryService.asr(path, 'en-US');
      this.transcript = transcript;
    } catch (err) {
      this.busy = false;
      this.busyText = '';
      this.handleError(err as Error);
      return;
    }
    this.busy = false;
    this.busyText = '';
    await this.submitTranscript(transcript);
  }

  async submitTyped(): Promise<void> {
    const text = this.typedText.trim();
    if (text.length === 0) {
      this.setLocalError(this.isChild ? '先写一句你想说的吧' : '请先输入你的复述');
      return;
    }
    await this.submitTranscript(text);
  }

  async submitTranscript(transcript: string): Promise<void> {
    if (this.busy) {
      return;
    }
    const text = transcript.trim();
    if (text.length === 0) {
      this.setLocalError('没有听到你的复述，再讲一次吧');
      return;
    }
    if (this.storySentences.length === 0) {
      this.setLocalError('缺少故事原文，返回详情页重新进入试试');
      return;
    }
    this.clearError();
    this.busy = true;
    this.busyText = '老师在看你讲得怎么样… ⏳';
    this.lastAction = ReviewAction.RETELL;
    this.lastTranscript = text;
    try {
      const dto: StoryRetellDto = await StoryService.retell(this.storyId, this.storySentences, text, this.level);
      this.applyRetell(dto, text);
    } catch (err) {
      this.handleError(err as Error);
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  private applyRetell(dto: StoryRetellDto, transcript: string): void {
    this.hasResult = true;
    const coverage = dto.coverage;
    this.coveragePercent = (coverage === undefined || coverage === null)
      ? -1 : Math.round(coverage * 100);
    const covered = dto.covered_points;
    this.coveredPoints = covered === undefined ? [] : covered;
    this.coveredCount = this.coveredPoints.length;
    const missing = dto.missing_points;
    this.missingPoints = missing === undefined ? [] : missing;
    const feedbackZh = dto.feedback_zh;
    this.feedbackZh = feedbackZh === undefined ? '' : feedbackZh;
    const feedbackEn = dto.feedback_en;
    this.feedbackEn = feedbackEn === undefined ? '' : feedbackEn;

    const record = new StoryRetellRecord();
    const now = new Date();
    record.createdAt = StoryDates.pad2(now.getHours()) + ':' + StoryDates.pad2(now.getMinutes());
    record.coverage = this.coveragePercent;
    record.coveredCount = this.coveredCount;
    record.coveredPoints = this.coveredPoints;
    record.missingPoints = this.missingPoints;
    record.feedbackZh = this.feedbackZh;
    record.feedbackEn = this.feedbackEn;
    record.transcript = transcript;
    StoryRuntime.addRetell(this.userId, this.storyId, record);
  }

  canPlayRecording(): boolean {
    return this.recordPath.length > 0;
  }

  async playRecording(): Promise<void> {
    if (this.recordPath.length === 0) {
      return;
    }
    try {
      await AudioController.play(this.recordPath, () => {
        // 播放结束无需额外状态
      });
    } catch (err) {
      const ui: UiError = SessionStore.toUiError(err as Error, this.isChild);
      this.setError(ui, '');
    }
  }

  // ------------------------------------------------------------------ 错误 / 生命周期

  async onErrorAction(): Promise<void> {
    if (this.errorActionLabel.length === 0) {
      return;
    }
    if (this.error.code === 'mic_denied') {
      const granted = await MicPermission.openSettings();
      if (granted) {
        this.clearError();
      }
      return;
    }
    const action = this.lastAction;
    this.clearError();
    if (action === ReviewAction.ASR) {
      await this.retryRecognize();
    } else if (action === ReviewAction.RETELL) {
      await this.submitTranscript(this.lastTranscript);
    }
  }

  clearError(): void {
    this.hasError = false;
    this.errorActionLabel = '';
  }

  private setLocalError(message: string): void {
    this.setError(new UiError('', message, '', false, 'bad_request'), '');
  }

  private setError(error: UiError, actionLabel: string): void {
    this.error = error;
    this.hasError = true;
    this.errorActionLabel = actionLabel;
  }

  private handleError(err: Error): void {
    const ui: UiError = SessionStore.toUiError(err, this.isChild);
    let actionLabel = '';
    if (ui.code === 'mic_denied') {
      actionLabel = '去设置';
    } else if (this.lastAction === ReviewAction.ASR) {
      actionLabel = '重新识别';
    } else if (this.lastAction === ReviewAction.RETELL) {
      actionLabel = this.isChild ? '再试一次' : '重试';
    }
    this.setError(ui, actionLabel);
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

  dispose(): void {
    this.stopTimer();
    this.recording = false;
    this.preparing = false;
    void AudioController.stopAll();
  }

  private static normalizeLevel(cefr: string): string {
    const upper = cefr.trim().toUpperCase();
    if (upper === 'A1' || upper === 'A2' || upper === 'B1' || upper === 'B2') {
      return upper;
    }
    return 'A2';
  }
}

import { ApiError, ApiErrorCode } from '../core/net/ApiError';
import { UiError } from '../core/error/UiError';
import { SessionStore } from '../core/session/SessionStore';
import { AudioController } from '../core/audio/AudioController';
import { MicPermission, RecordingResult } from '../core/audio/AudioRecorder';
import { CacheService } from '../core/service/CacheService';
import { FileUtil } from '../core/util/FileUtil';
import { AppConfig } from '../core/config/AppConfig';
import { PracticeService } from '../core/service/PracticeService';
import { ChatService } from '../core/service/ChatService';
import { ChatOpeningZh } from '../core/content/ChatOpeningZh';
import { NavState } from '../core/router/NavState';
import {
  ChatCorrectionDto,
  ChatMessageDto,
  ChatNav,
  ChatPronDto,
  ChatScenarioDto,
  ChatScenarioListDto,
  ChatSessionDetailDto,
  ChatSessionDto,
  ChatSessionListItemDto,
  ChatTurnDto,
  ChatWeakPhonemeDto
} from '../core/net/ChatDtos';

// ---------------------------------------------------------------------------
// 消息视图模型（页面只渲染这个，不直接碰 DTO）
// ---------------------------------------------------------------------------

/**
 * 一条气泡。
 *
 * 刷新策略：ForEach 的 key 用 `renderKey()`（id + rev）。任何可见字段变化后调用
 * `bump()` 并由 VM 重新赋值整个数组，就能只重建这一条气泡（ArkUI ForEach 按 key 差量）。
 */
export class ChatMsg {
  id: string = '';
  /** user | assistant */
  role: string = 'assistant';
  text: string = '';
  textZh: string = '';
  hasCorrection: boolean = false;
  better: string = '';
  explainZh: string = '';
  unsafeFiltered: boolean = false;
  hasPron: boolean = false;
  /** -1 = 不可得（不落 0） */
  pronScore: number = -1;
  weakLabels: string[] = [];
  wordTexts: string[] = [];
  wordScores: number[] = [];
  /** 用户录音的本地文件（刚录完还没下载时用它回放） */
  localAudioPath: string = '';
  /** 服务端录音地址 `/api/audio/cm_xxx` */
  audioUrl: string = '';
  /** 助手 TTS 本地缓存 */
  ttsPath: string = '';
  /** '' | loading | playing | failed */
  playState: string = '';
  rev: number = 0;

  bump(): void {
    this.rev = this.rev + 1;
  }

  renderKey(): string {
    return this.id + '#' + this.rev.toString();
  }
}

/** DTO → 气泡。`isChild` 只影响 pron 的弱音/逐词（儿童永不显示 IPA 与数字）。 */
export class ChatMsgFactory {
  static fromDto(dto: ChatMessageDto, isChild: boolean): ChatMsg {
    const msg = new ChatMsg();
    msg.id = dto.id;
    msg.role = typeof dto.role === 'string' ? dto.role : 'assistant';
    msg.text = typeof dto.text === 'string' ? dto.text : '';
    msg.textZh = typeof dto.text_zh === 'string' ? dto.text_zh : '';
    msg.unsafeFiltered = dto.flag === 'unsafe_filtered';
    msg.audioUrl = typeof dto.audio_url === 'string' ? dto.audio_url : '';
    ChatMsgFactory.applyCorrection(msg, dto.correction);
    ChatMsgFactory.applyPron(msg, dto.pron, isChild);
    return msg;
  }

  static applyCorrection(msg: ChatMsg, correction: ChatCorrectionDto | null | undefined): void {
    if (correction === undefined || correction === null || correction.has_error !== true) {
      msg.hasCorrection = false;
      msg.better = '';
      msg.explainZh = '';
      return;
    }
    msg.hasCorrection = true;
    msg.better = typeof correction.better === 'string' ? correction.better : '';
    msg.explainZh = typeof correction.explain_zh === 'string' ? correction.explain_zh : '';
  }

  static applyPron(msg: ChatMsg, pron: ChatPronDto | null | undefined, isChild: boolean): void {
    if (pron === undefined || pron === null) {
      msg.hasPron = false;
      return;
    }
    msg.hasPron = true;
    msg.pronScore = (pron.pron === undefined || pron.pron === null) ? -1 : pron.pron;
    const labels: string[] = [];
    const weak = pron.weak_phonemes;
    if (weak !== undefined && !isChild) {
      for (let i = 0; i < weak.length && i < 3; i++) {
        const label = ChatMsgFactory.weakLabel(weak[i]);
        if (label.length > 0) {
          labels.push(label);
        }
      }
    }
    msg.weakLabels = labels;
    const texts: string[] = [];
    const scores: number[] = [];
    const words = pron.words;
    if (words !== undefined && !isChild) {
      for (let i = 0; i < words.length && i < 24; i++) {
        const word = words[i];
        texts.push(typeof word.word === 'string' ? word.word : '');
        scores.push((word.score === undefined || word.score === null) ? -1 : (word.score as number));
      }
    }
    msg.wordTexts = texts;
    msg.wordScores = scores;
  }

  private static weakLabel(item: ChatWeakPhonemeDto): string {
    if (typeof item.label === 'string' && item.label.length > 0) {
      return item.label;
    }
    if (typeof item.ipa === 'string' && item.ipa.length > 0) {
      return item.ipa;
    }
    return '';
  }
}

/** 展示用格式化（成人/儿童共用，不含分数口径）。 */
export class ChatFormat {
  /** 分数文本：保留 1 位小数，-1 → — */
  static scoreText(value: number): string {
    if (value < 0) {
      return '—';
    }
    const rounded = Math.round(value * 10) / 10;
    return rounded.toString();
  }

  /** 毫秒 → 「48 秒」/「2 分 10 秒」 */
  static durationText(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const totalSec = Math.round(ms / 1000);
    if (totalSec < 60) {
      return totalSec.toString() + ' 秒';
    }
    const min = Math.floor(totalSec / 60);
    const sec = totalSec % 60;
    return min.toString() + ' 分 ' + sec.toString() + ' 秒';
  }

  /** ISO 时间 → 「11-02 17:00」；解析失败原样返回。 */
  static timeText(iso: string): string {
    if (iso.length === 0) {
      return '';
    }
    const date = new Date(iso);
    const time = date.getTime();
    if (time !== time) {
      return iso;
    }
    return ChatFormat.pad2(date.getMonth() + 1) + '-' + ChatFormat.pad2(date.getDate()) + ' ' +
      ChatFormat.pad2(date.getHours()) + ':' + ChatFormat.pad2(date.getMinutes());
  }

  static pad2(value: number): string {
    return value < 10 ? ('0' + value.toString()) : value.toString();
  }
}

// ---------------------------------------------------------------------------
// 对话会话 VM（实时会话 + 历史详情两种模式共用）
// ---------------------------------------------------------------------------

/**
 * 会话页 / 历史详情页共用。
 *
 * - `initLive`：刚从场景卡开出来的会话（可录音、可结束）
 * - `initHistory`：历史详情（只读，已结束，整段回放可能 ready/building/failed）
 *
 * 三步一轮（§7.3）：ASR → 乐观插入用户气泡 → turn（text+audio）→ 文字先渲染 →
 * 自己请求 TTS 播报 → 后台 4 次轮询 /messages 补 pron。
 */
@Observed
export class ChatVM {
  // ---- 头部信息
  sessionId: string = '';
  titleEn: string = '';
  titleZh: string = '';
  settingZh: string = '';
  level: string = '';
  isChild: boolean = false;
  /** true = 历史详情（只读） */
  readOnly: boolean = false;
  turnCount: number = 0;
  startedAt: string = '';
  endedAt: string = '';

  // ---- 消息
  messages: ChatMsg[] = [];

  // ---- 加载
  loading: boolean = true;
  loadError: string = '';

  // ---- 录音 / 提交
  busy: boolean = false;
  progressText: string = '';
  preparing: boolean = false;
  recording: boolean = false;
  elapsedMs: number = 0;

  // ---- 会话状态
  ending: boolean = false;
  ended: boolean = false;
  done: boolean = false;
  degradedLlm: boolean = false;
  degraded: boolean = false;
  quotaExceeded: boolean = false;
  quotaText: string = '';

  // ---- 建议应答 / 提示句
  suggestedReplies: string[] = [];
  hintText: string = '';

  // ---- 偏好
  autoRead: boolean = true;
  ttsRate: string = 'normal';
  ttsVoice: string = '';

  // ---- 错误
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');
  errorActionLabel: string = '';

  // ---- 整段回放
  /** idle | loading | building | ready | failed */
  replayStatus: string = 'idle';
  replayError: string = '';
  replayPath: string = '';
  replayPlaying: boolean = false;
  replayDurationMs: number = 0;

  // ---- 内部
  private pendingText: string = '';
  private pendingPath: string = '';
  private pendingUserMsg: ChatMsg | null = null;
  private lastFailedMsg: ChatMsg | null = null;
  private lastAction: string = '';
  private recordTimer: number = -1;
  private recordStartedAt: number = 0;
  private progressTimer: number = -1;
  private progressStartedAt: number = 0;
  private progressBase: string = '';
  private pronTimer: number = -1;
  private pronStep: number = 0;
  private pronTargetText: string = '';
  private replayTimer: number = -1;
  private replayTries: number = 0;
  private disposed: boolean = false;

  // ------------------------------------------------------------------ 初始化

  /** 实时会话：来自「点场景卡 → POST /sessions」的数据。 */
  async initLive(session: ChatSessionDto, scenario: ChatScenarioDto | null, isChild: boolean): Promise<void> {
    this.sessionId = session.session_id;
    this.isChild = isChild;
    this.readOnly = false;
    this.ended = false;
    this.done = false;
    this.turnCount = session.turn_count === undefined ? 0 : session.turn_count;

    let sc: ChatScenarioDto | null = scenario;
    if (sc === null && session.scenario !== undefined) {
      sc = session.scenario;
    }
    let opening = '';
    if (sc !== null) {
      this.titleEn = typeof sc.title === 'string' ? sc.title : '';
      this.titleZh = typeof sc.title_zh === 'string' ? sc.title_zh : '';
      this.settingZh = typeof sc.setting_zh === 'string' ? sc.setting_zh : '';
      this.level = typeof sc.level === 'string' ? sc.level : '';
      opening = typeof sc.opening_line === 'string' ? sc.opening_line : '';
    }
    // 开场白优先用会话消息（服务端会带 text_zh）；没有则用上面场景的 opening_line（无中文）
    let openingZh = '';
    const sessionMessages = session.messages;
    if (sessionMessages !== undefined && sessionMessages.length > 0) {
      const first = sessionMessages[0];
      if (typeof first.text === 'string' && first.text.length > 0) {
        opening = first.text;
        openingZh = typeof first.text_zh === 'string' ? first.text_zh : '';
      }
    }
    await this.loadPrefs();
    const list: ChatMsg[] = [];
    if (opening.length > 0) {
      const greeting = new ChatMsg();
      greeting.id = 'opening';
      greeting.role = 'assistant';
      greeting.text = opening;
      greeting.textZh = openingZh.length > 0 ? openingZh : ChatOpeningZh.lookup(opening);
      list.push(greeting);
    }
    this.messages = list;
    this.loading = false;
    if (opening.length > 0) {
      void this.autoPlay(this.messages[0]);
    }
  }

  /** 历史详情（只读）：meta + messages（含 pron）。 */
  async initHistory(sessionId: string, item: ChatSessionListItemDto | null, isChild: boolean): Promise<void> {
    this.sessionId = sessionId;
    this.isChild = isChild;
    this.readOnly = true;
    this.ended = true;
    this.done = false;
    this.loading = true;
    this.loadError = '';
    if (item !== null) {
      this.titleZh = typeof item.scenario_title_zh === 'string' ? item.scenario_title_zh : '';
      this.titleEn = typeof item.scenario_title === 'string' ? item.scenario_title : '';
      this.turnCount = item.turn_count === undefined ? 0 : item.turn_count;
      this.startedAt = item.started_at === undefined ? '' : item.started_at;
      this.endedAt = item.ended_at === undefined || item.ended_at === null ? '' : item.ended_at;
    }
    await this.loadPrefs();
    try {
      let detail: ChatSessionDetailDto | null = null;
      try {
        detail = await ChatService.sessionDetail(sessionId);
      } catch (err) {
        // 详情失败不阻塞消息列表
        detail = null;
      }
      if (detail !== null) {
        this.turnCount = detail.turn_count === undefined ? this.turnCount : detail.turn_count;
        this.startedAt = detail.started_at === undefined ? this.startedAt : detail.started_at;
        this.endedAt = detail.ended_at === undefined || detail.ended_at === null ? this.endedAt : detail.ended_at;
        if (this.titleZh.length === 0 && typeof detail.scenario_title_zh === 'string') {
          this.titleZh = detail.scenario_title_zh;
        }
        if (this.titleEn.length === 0 && typeof detail.scenario_title === 'string') {
          this.titleEn = detail.scenario_title;
        }
      }
      const list = await ChatService.messages(sessionId);
      const built: ChatMsg[] = [];
      for (let i = 0; i < list.length; i++) {
        built.push(ChatMsgFactory.fromDto(list[i], isChild));
      }
      this.messages = built;
      this.loading = false;
      void this.beginReplay();
    } catch (err) {
      this.loading = false;
      this.loadError = SessionStore.toUiError(err as Error, isChild).message;
    }
  }

  private async loadPrefs(): Promise<void> {
    const auto = await AppConfig.getString('chat_auto_read', '1');
    this.autoRead = auto === '1';
    const rate = await AppConfig.getString('chat_tts_rate', '');
    this.ttsRate = rate.length > 0 ? rate : (this.isChild ? 'slow' : 'normal');
    const voice = await AppConfig.getString('tts_voice', '');
    this.ttsVoice = voice;
  }

  // ------------------------------------------------------------------ 录音

  async startRecording(): Promise<void> {
    if (this.recording || this.preparing || this.busy || this.ended) {
      return;
    }
    this.clearError();
    this.preparing = true;
    this.lastAction = 'record';
    try {
      await AudioController.startRecording();
      this.recording = true;
      this.recordStartedAt = Date.now();
      this.elapsedMs = 0;
      this.startRecordTimer();
    } catch (err) {
      this.recording = false;
      this.handleError(err as Error, 'record');
    } finally {
      this.preparing = false;
    }
  }

  async stopAndSend(): Promise<void> {
    if (!this.recording) {
      return;
    }
    this.recording = false;
    this.stopRecordTimer();
    let recorded: RecordingResult | null = null;
    try {
      recorded = await AudioController.stopRecording();
    } catch (err) {
      this.handleError(err as Error, 'record');
      return;
    }
    if (recorded === null) {
      return;
    }
    await this.sendVoice(recorded);
  }

  async cancelRecording(): Promise<void> {
    if (!this.recording) {
      return;
    }
    this.recording = false;
    this.stopRecordTimer();
    this.elapsedMs = 0;
    await AudioController.cancelRecording();
  }

  private startRecordTimer(): void {
    this.stopRecordTimer();
    this.recordTimer = setInterval(() => {
      this.elapsedMs = Date.now() - this.recordStartedAt;
      if (this.elapsedMs >= 60000) {
        void this.stopAndSend();
      }
    }, 200);
  }

  private stopRecordTimer(): void {
    if (this.recordTimer >= 0) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
  }

  // ------------------------------------------------------------------ 一轮三步

  /** ① ASR → 乐观插用户气泡 → ② turn → ③ TTS。 */
  private async sendVoice(rec: RecordingResult): Promise<void> {
    this.busy = true;
    this.clearError();
    this.startProgress('识别中…');
    let text = '';
    try {
      text = await ChatService.asr(rec.path, 'en-US');
    } catch (err) {
      this.busy = false;
      this.stopProgress();
      this.handleError(err as Error, 'record');
      return;
    }
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      this.busy = false;
      this.stopProgress();
      this.setError(new UiError('', this.isChild ? '没听清，再说一次好吗' : '没听清，请再说一次', '重试', true,
        'asr_empty'), '');
      this.lastAction = 'record';
      return;
    }
    const userMsg = new ChatMsg();
    userMsg.id = 'u_' + Date.now().toString();
    userMsg.role = 'user';
    userMsg.text = trimmed;
    userMsg.localAudioPath = rec.path;
    this.pushMessage(userMsg);
    this.progressBase = '回复中…';
    this.progressText = '回复中…';
    this.progressStartedAt = Date.now();
    await this.sendTurn(trimmed, rec.path, userMsg);
  }

  private async sendTurn(text: string, audioPath: string, userMsg: ChatMsg): Promise<void> {
    this.busy = true;
    this.startProgress('回复中…');
    try {
      const turn = await ChatService.turn(this.sessionId, text, audioPath);
      this.applyTurn(turn, userMsg);
      this.pendingText = '';
      this.pendingPath = '';
      this.pendingUserMsg = null;
    } catch (err) {
      this.pendingText = text;
      this.pendingPath = audioPath;
      this.pendingUserMsg = userMsg;
      this.handleError(err as Error, 'turn');
    } finally {
      this.busy = false;
      this.stopProgress();
    }
  }

  private applyTurn(turn: ChatTurnDto, userMsg: ChatMsg): void {
    this.turnCount = turn.turn_index === undefined ? this.turnCount + 1 : turn.turn_index;
    this.degradedLlm = turn.degraded_llm === true;
    this.degraded = turn.degraded === true;
    const reply = typeof turn.reply === 'string' ? turn.reply : '';
    const bot = new ChatMsg();
    bot.id = (typeof turn.message_id === 'string' && turn.message_id.length > 0)
      ? turn.message_id : ('a_' + Date.now().toString());
    bot.role = 'assistant';
    bot.text = reply;
    bot.textZh = typeof turn.reply_zh === 'string' ? turn.reply_zh : '';
    bot.unsafeFiltered = turn.flag === 'unsafe_filtered';
    ChatMsgFactory.applyCorrection(bot, turn.correction);
    this.pushMessage(bot);
    const suggested = turn.suggested_replies;
    this.suggestedReplies = suggested === undefined ? [] : suggested.slice(0, 3);
    this.hintText = '';
    this.done = turn.done === true;
    if (this.done) {
      // 场景自然收尾：不显示录音区，直接汇总 + 整段回放
      this.ended = true;
      this.suggestedReplies = [];
      void this.endSession();
    } else if (reply.length > 0) {
      void this.autoPlay(bot);
      this.startPronPoll(userMsg.text);
    }
  }

  /** 手动点「结束对话」/ done=true 自然收尾：POST /end → 轮询整段回放。 */
  async endSession(): Promise<void> {
    if (this.ending || this.sessionId.length === 0) {
      return;
    }
    this.ending = true;
    this.clearError();
    this.recording = false;
    this.stopRecordTimer();
    try {
      await ChatService.end(this.sessionId);
    } catch (err) {
      this.ended = true;
      this.handleError(err as Error, 'end');
    } finally {
      this.ending = false;
      this.ended = true;
      this.suggestedReplies = [];
      this.hintText = '';
    }
    await AudioController.stopPlayback();
    this.resetMessagePlayStates();
    void this.beginReplay();
  }

  // ------------------------------------------------------------------ pron 轮询（4 次）

  private startPronPoll(text: string): void {
    this.stopPronPoll();
    this.pronTargetText = text;
    this.pronStep = 0;
    this.schedulePronStep();
  }

  private schedulePronStep(): void {
    if (this.disposed) {
      return;
    }
    const delays: number[] = [700, 1100, 1500, 1900];
    if (this.pronStep >= delays.length) {
      return;
    }
    const ms = delays[this.pronStep];
    this.pronTimer = setTimeout(() => {
      void this.pollPronOnce();
    }, ms);
  }

  private async pollPronOnce(): Promise<void> {
    if (this.disposed) {
      return;
    }
    try {
      const list = await ChatService.messages(this.sessionId);
      if (this.applyPronFromMessages(list)) {
        this.stopPronPoll();
        return;
      }
    } catch (err) {
      // 轮询失败静默：4 次都没拿到就显示「评分未完成」
    }
    this.pronStep = this.pronStep + 1;
    if (this.pronStep < 4) {
      this.schedulePronStep();
    }
  }

  private stopPronPoll(): void {
    if (this.pronTimer >= 0) {
      clearTimeout(this.pronTimer);
      this.pronTimer = -1;
    }
    this.pronStep = 0;
  }

  /**
   * 把 /messages 里的 pron / correction 补进当前气泡。
   * 返回 true = 目标用户消息已经拿到 pron（可以停止轮询）。
   */
  private applyPronFromMessages(list: ChatMessageDto[]): boolean {
    let matched = false;
    for (let i = list.length - 1; i >= 0; i--) {
      const dto = list[i];
      if (dto.role !== 'user' || dto.text !== this.pronTargetText) {
        continue;
      }
      const target = this.findMessageByIdOrText(dto.id, 'user', this.pronTargetText, true);
      if (target === null) {
        break;
      }
      if (dto.pron !== undefined && dto.pron !== null) {
        ChatMsgFactory.applyPron(target, dto.pron, this.isChild);
        target.bump();
        this.refreshMessages();
        matched = true;
      }
      break;
    }
    // 顺带补 assistant 的 correction（重进详情页也还在）
    for (let i = 0; i < list.length; i++) {
      const dto = list[i];
      if (dto.correction === undefined || dto.correction === null) {
        continue;
      }
      const text = typeof dto.text === 'string' ? dto.text : '';
      const target = this.findMessageByIdOrText(dto.id, 'assistant', text, false);
      if (target !== null && !target.hasCorrection) {
        ChatMsgFactory.applyCorrection(target, dto.correction);
        target.bump();
        this.refreshMessages();
      }
    }
    return matched;
  }

  private findMessageByIdOrText(id: string, role: string, text: string, last: boolean): ChatMsg | null {
    if (last) {
      for (let i = this.messages.length - 1; i >= 0; i--) {
        const msg = this.messages[i];
        if (msg.id === id || (msg.role === role && msg.text === text)) {
          return msg;
        }
      }
    } else {
      for (let i = 0; i < this.messages.length; i++) {
        const msg = this.messages[i];
        if (msg.id === id || (msg.role === role && msg.text === text)) {
          return msg;
        }
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ 播放

  /** 自动朗读：录音/播放中不抢麦。 */
  private async autoPlay(msg: ChatMsg): Promise<void> {
    if (!this.autoRead || this.recording || this.disposed) {
      return;
    }
    await this.playMessage(msg);
  }

  async playMessage(msg: ChatMsg): Promise<void> {
    if (this.recording) {
      return;
    }
    if (msg.role === 'assistant' && msg.text.trim().length === 0) {
      return;
    }
    if (msg.playState === 'playing') {
      await AudioController.stopPlayback();
      msg.playState = '';
      msg.bump();
      this.refreshMessages();
      return;
    }
    this.clearError();
    this.lastFailedMsg = null;
    this.resetMessagePlayStates();
    msg.playState = 'loading';
    msg.bump();
    this.refreshMessages();
    try {
      let path = '';
      if (msg.role === 'user') {
        path = await this.ensureUserAudio(msg);
      } else {
        path = await this.ensureTts(msg);
      }
      msg.playState = 'playing';
      msg.bump();
      this.refreshMessages();
      await AudioController.play(path, () => {
        msg.playState = '';
        msg.bump();
        this.refreshMessages();
      });
    } catch (err) {
      msg.playState = 'failed';
      msg.bump();
      this.refreshMessages();
      this.lastFailedMsg = msg;
      this.handleError(err as Error, 'tts');
    }
  }

  private async ensureUserAudio(msg: ChatMsg): Promise<string> {
    if (msg.localAudioPath.length > 0 && FileUtil.exists(msg.localAudioPath)) {
      return msg.localAudioPath;
    }
    if (msg.audioUrl.length > 0) {
      CacheService.ensureAll();
      const dest = CacheService.audioDir() + '/chatmsg_' + msg.id + '.m4a';
      if (!FileUtil.exists(dest)) {
        await ChatService.downloadMessageAudio(msg.audioUrl, dest);
      }
      return dest;
    }
    throw ApiError.local(ApiErrorCode.AUDIO_NOT_FOUND, '这条还没有录音回放');
  }

  private async ensureTts(msg: ChatMsg): Promise<string> {
    if (msg.ttsPath.length > 0 && FileUtil.exists(msg.ttsPath)) {
      return msg.ttsPath;
    }
    const path = await PracticeService.fetchTtsFile(msg.text, this.ttsRate, this.ttsVoice, 'mp3');
    msg.ttsPath = path;
    return path;
  }

  private resetMessagePlayStates(): void {
    for (let i = 0; i < this.messages.length; i++) {
      const msg = this.messages[i];
      if (msg.playState === 'loading' || msg.playState === 'playing') {
        msg.playState = '';
        msg.bump();
      }
    }
    this.refreshMessages();
  }

  // ------------------------------------------------------------------ 整段回放（§2.8）

  async beginReplay(): Promise<void> {
    if (this.sessionId.length === 0) {
      return;
    }
    this.stopReplayTimer();
    this.replayTries = 0;
    this.replayError = '';
    this.replayPath = '';
    this.replayStatus = 'loading';
    await this.checkReplay(true);
  }

  private async checkReplay(allowTrigger: boolean): Promise<void> {
    if (this.disposed || this.sessionId.length === 0) {
      return;
    }
    this.replayTries = this.replayTries + 1;
    try {
      const status = await ChatService.audioStatus(this.sessionId);
      if (status.status === 'ready') {
        this.replayStatus = 'loading';
        const result = await ChatService.audio(this.sessionId, false);
        if (result.state === 'ready') {
          this.replayPath = result.path;
          this.replayDurationMs = status.duration_ms === undefined ? 0 : status.duration_ms;
          this.replayStatus = 'ready';
          return;
        }
        if (result.state === 'building') {
          this.replayStatus = 'building';
          this.scheduleReplay();
          return;
        }
        this.replayStatus = 'failed';
        this.replayError = result.message;
        return;
      }
      if (status.status === 'failed') {
        this.replayStatus = 'failed';
        this.replayError = (typeof status.error === 'string' && status.error.length > 0)
          ? status.error
          : (this.isChild ? '回放还在准备，等一下再点这里试试' : '整段回放暂时生成不了，可以先看文字记录');
        return;
      }
      // building / pending：首次补发一次 GET audio 触发构建（老会话没有 sidecar）
      this.replayStatus = 'building';
      if (allowTrigger) {
        try {
          await ChatService.audio(this.sessionId, false);
        } catch (err) {
          // 202 走 ChatAudioResult，不抛；这里防御网络异常
        }
      }
      this.scheduleReplay();
    } catch (err) {
      this.replayStatus = 'failed';
      this.replayError = SessionStore.toUiError(err as Error, this.isChild).message;
    }
  }

  private scheduleReplay(): void {
    if (this.disposed) {
      return;
    }
    // 2s 一次，最多约 60s
    if (this.replayTries > 30) {
      this.replayStatus = 'failed';
      this.replayError = this.isChild ? '回放还没准备好，等一下再点这里试试' : '整段回放生成超时了，可以点「重新生成」';
      return;
    }
    this.stopReplayTimer();
    this.replayTimer = setTimeout(() => {
      void this.checkReplay(false);
    }, 2000);
  }

  private stopReplayTimer(): void {
    if (this.replayTimer >= 0) {
      clearTimeout(this.replayTimer);
      this.replayTimer = -1;
    }
  }

  /** 「🔄 重新生成」：GET audio?force=1 后再轮询（auto_retry=false 时只能用户点）。 */
  async regenerateReplay(): Promise<void> {
    if (this.sessionId.length === 0 || this.replayStatus === 'loading') {
      return;
    }
    this.stopReplayTimer();
    this.replayTries = 0;
    this.replayError = '';
    this.replayStatus = 'loading';
    this.replayPath = '';
    try {
      const result = await ChatService.audio(this.sessionId, true);
      if (result.state === 'ready') {
        this.replayPath = result.path;
        this.replayStatus = 'ready';
        return;
      }
    } catch (err) {
      this.replayStatus = 'failed';
      this.replayError = SessionStore.toUiError(err as Error, this.isChild).message;
      return;
    }
    this.replayStatus = 'building';
    this.scheduleReplay();
  }

  async playReplay(): Promise<void> {
    if (this.replayPath.length === 0) {
      return;
    }
    if (this.replayPlaying) {
      await AudioController.stopPlayback();
      this.replayPlaying = false;
      return;
    }
    this.resetMessagePlayStates();
    this.replayPlaying = true;
    try {
      await AudioController.play(this.replayPath, () => {
        this.replayPlaying = false;
      });
    } catch (err) {
      this.replayPlaying = false;
      this.handleError(err as Error, 'replay');
    }
  }

  // ------------------------------------------------------------------ 进度 / 错误

  private startProgress(text: string): void {
    this.stopProgressTimer();
    this.progressBase = text;
    this.progressText = text;
    this.progressStartedAt = Date.now();
    this.progressTimer = setInterval(() => {
      if (Date.now() - this.progressStartedAt > 8000) {
        this.progressText = this.progressBase + '（有点慢，再等一下）';
      }
    }, 1000);
  }

  private stopProgress(): void {
    this.stopProgressTimer();
    this.progressText = '';
  }

  private stopProgressTimer(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private setError(error: UiError, actionLabel: string): void {
    this.error = error;
    this.hasError = true;
    this.errorActionLabel = actionLabel;
  }

  clearError(): void {
    this.hasError = false;
    this.errorActionLabel = '';
  }

  /**
   * 统一错误处理（§1.2）：
   * - 429 = 额度业务态（横幅 + 禁用录音），不弹错误；
   * - 409 session_closed = 会话已结束（切结束态）；
   * - 其余展示可读 message + 可重试动作。
   */
  private handleError(err: Error, action: string): void {
    const apiErr: ApiError | null = (err instanceof ApiError) ? (err as ApiError) : null;
    const ui = SessionStore.toUiError(err, this.isChild);
    if (apiErr !== null && apiErr.status === 429) {
      this.quotaExceeded = true;
      this.quotaText = ui.message.length > 0 ? ui.message
        : (this.isChild ? '今天已经练得很棒啦，明天再来 🌙' : '今天的练习时间到了，明天再来');
      return;
    }
    if (apiErr !== null && (apiErr.code === 'session_closed' || apiErr.status === 409)) {
      this.ended = true;
      this.suggestedReplies = [];
    }
    let label = '';
    if (apiErr !== null && apiErr.code === ApiErrorCode.MIC_DENIED) {
      label = '去设置';
    } else if (action === 'end') {
      label = '';
    } else {
      label = this.isChild ? '再试一次' : '重试';
    }
    this.lastAction = action;
    this.setError(ui, label);
  }

  /** 错误条按钮：按 lastAction 真正重试对应动作。 */
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
    if (action === 'turn' && this.pendingText.length > 0 && this.pendingUserMsg !== null) {
      await this.sendTurn(this.pendingText, this.pendingPath, this.pendingUserMsg);
    } else if (action === 'tts' || action === 'replay') {
      if (this.lastFailedMsg !== null) {
        await this.playMessage(this.lastFailedMsg);
      }
    } else if (action === 'record') {
      await this.startRecording();
    }
  }

  // ------------------------------------------------------------------ 建议应答 / 提示句

  /** 点建议 = 设提示句（**不发送文本**，只提示用户照着说）。 */
  useSuggestion(text: string): void {
    this.hintText = text;
    void this.startRecording();
  }

  clearHint(): void {
    this.hintText = '';
  }

  // ------------------------------------------------------------------ 内部

  private pushMessage(msg: ChatMsg): void {
    const list: ChatMsg[] = this.messages.slice();
    list.push(msg);
    this.messages = list;
  }

  private refreshMessages(): void {
    this.messages = this.messages.slice();
  }

  /** 页面销毁：停所有计时器、丢弃录音、停止播放。 */
  dispose(): void {
    this.disposed = true;
    this.stopRecordTimer();
    this.stopProgressTimer();
    this.stopPronPoll();
    this.stopReplayTimer();
    this.recording = false;
    this.replayPlaying = false;
    void AudioController.stopAll();
  }
}

// ---------------------------------------------------------------------------
// 场景列表 VM
// ---------------------------------------------------------------------------

@Observed
export class ChatScenarioVM {
  loading: boolean = true;
  errorMessage: string = '';
  customItems: ChatScenarioDto[] = [];
  adultItems: ChatScenarioDto[] = [];
  childItems: ChatScenarioDto[] = [];
  isChild: boolean = false;
  includeChild: boolean = false;
  age: number = 0;
  audience: string = 'adult';
  customCount: number = 0;
  hiddenCount: number = 0;
  totalCount: number = 0;
  startingId: string = '';
  quotaExceeded: boolean = false;
  quotaText: string = '';

  async load(includeChild: boolean, isChild: boolean): Promise<void> {
    this.includeChild = includeChild;
    this.isChild = isChild;
    this.loading = true;
    this.errorMessage = '';
    this.quotaExceeded = false;
    try {
      const dto = await ChatService.scenarios(includeChild);
      this.apply(dto);
    } catch (err) {
      this.customItems = [];
      this.adultItems = [];
      this.childItems = [];
      this.errorMessage = SessionStore.toUiError(err as Error, isChild).message;
    } finally {
      this.loading = false;
    }
  }

  private apply(dto: ChatScenarioListDto): void {
    if (dto.is_child !== undefined) {
      this.isChild = dto.is_child;
    }
    this.age = dto.age === undefined ? 0 : dto.age;
    this.audience = dto.audience === undefined ? 'adult' : dto.audience;
    this.customCount = dto.custom_count === undefined ? 0 : dto.custom_count;
    this.hiddenCount = dto.hidden_count === undefined ? 0 : dto.hidden_count;
    const list = dto.scenarios === undefined ? [] : dto.scenarios;
    this.totalCount = list.length;
    const custom: ChatScenarioDto[] = [];
    const adult: ChatScenarioDto[] = [];
    const child: ChatScenarioDto[] = [];
    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      if (item.is_custom === true) {
        custom.push(item);
      } else if (item.audience === 'child') {
        child.push(item);
      } else {
        adult.push(item);
      }
    }
    this.customItems = custom;
    this.adultItems = adult;
    this.childItems = child;
  }

  /** 点场景卡：POST /sessions → 写 NavState/ChatNav → 页面负责 push。 */
  async start(scenario: ChatScenarioDto): Promise<boolean> {
    if (this.startingId.length > 0) {
      return false;
    }
    this.startingId = scenario.id;
    this.quotaExceeded = false;
    try {
      const session = await ChatService.createSession(scenario.id);
      ChatNav.session = session;
      NavState.setChat(scenario, this.includeChild);
      NavState.setSession(session.session_id);
      return true;
    } catch (err) {
      const ui = SessionStore.toUiError(err as Error, this.isChild);
      const apiErr: ApiError | null = (err instanceof ApiError) ? (err as ApiError) : null;
      if (apiErr !== null && apiErr.status === 429) {
        this.quotaExceeded = true;
        this.quotaText = ui.message;
      } else {
        this.errorMessage = ui.message;
      }
      return false;
    } finally {
      this.startingId = '';
    }
  }
}

// ---------------------------------------------------------------------------
// 历史列表 VM
// ---------------------------------------------------------------------------

@Observed
export class ChatHistoryVM {
  loading: boolean = true;
  errorMessage: string = '';
  items: ChatSessionListItemDto[] = [];
  isChild: boolean = false;

  async load(isChild: boolean): Promise<void> {
    this.isChild = isChild;
    this.loading = true;
    this.errorMessage = '';
    try {
      this.items = await ChatService.sessions();
    } catch (err) {
      this.items = [];
      this.errorMessage = SessionStore.toUiError(err as Error, isChild).message;
    } finally {
      this.loading = false;
    }
  }
}

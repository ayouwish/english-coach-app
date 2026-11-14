import { AccountService } from '../core/service/AccountService';
import { AccountPrefs } from '../core/content/AccountPrefs';
import { PracticeService } from '../core/service/PracticeService';
import { MediaService, VoiceOption } from '../core/service/MediaService';
import { AppConfig } from '../core/config/AppConfig';
import { CacheService } from '../core/service/CacheService';
import { SessionStore } from '../core/session/SessionStore';
import { TokenSession } from '../core/net/TokenSession';
import { ApiError, ApiErrorCode } from '../core/net/ApiError';
import { ErrorMapper, UiError } from '../core/error/UiError';
import {
  AccountUserDto,
  AvatarPresetCharacterDto,
  AvatarStateDto,
  AvatarStyleDto,
  FamilyCreateBodyDto,
  FamilyMemberDto,
  FamilyPatchBodyDto,
  ParentChildDto,
  ParentMemberDto,
  ParentBlindScoreDto,
  ParentPhonemeDto,
  ParentTrendPointDto,
  ParentWordDto,
  SettingsPatchBodyDto,
  SuggestionCreateBodyDto,
  SuggestionDto
} from '../core/net/AccountDtos';
import { UsageDto, UserDto } from '../core/net/Dtos';

/**
 * 账号类页面状态：设置 / 家庭成员 / 家长面板 / 建议箱 / 虚拟形象。
 *
 * 硬约束（`.specs/account-misc.md` §10.2）：
 * - 儿童 PATCH settings 不带 daily_limit_minutes / allow_free_chat；
 * - PATCH 成功后不用返回的瘦身 user 覆盖本地 gender/autoIllustrate/storySentences；
 * - 403 只提示「仅家长可用」，不跳登录。
 */

// ===========================================================================
// 设置页（/settings）
// ===========================================================================

@Observed
export class AccountSettingsVM {
  // 账号信息
  userId: string = '';
  email: string = '';
  role: string = 'child';
  cefrLevel: string = 'A1';
  isChild: boolean = false;
  avatarEmoji: string = '';

  // 偏好表单
  displayName: string = '';
  autoIllustrate: boolean = false;
  gender: string = '';
  /** -1 = null（恢复角色默认）；否则 3–12 */
  storySentences: number = -1;
  dailyLimit: number = 20;
  allowFreeChat: boolean = false;
  correctionLevel: string = 'gentle';
  /** '' = null（provider 默认音色） */
  ttsVoice: string = '';
  ttsRate: string = 'normal';
  /** 点单词显示音标（默认开；关闭后点词只提示去设置打开） */
  showWordIpa: boolean = true;

  // 用量
  usageMinutes: number = 0;
  usageLimit: number = 20;

  // 页面状态
  loading: boolean = false;
  loaded: boolean = false;
  saving: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');
  hasNotice: boolean = false;
  notice: string = '';

  // 服务器地址 / 健康检查 / 退出（保留原有能力）
  baseUrl: string = '';
  savedBaseUrl: string = '';
  serverStatus: string = '';
  checkingServer: boolean = false;
  savingAddress: boolean = false;
  loggingOut: boolean = false;

  async init(): Promise<void> {
    this.baseUrl = AppConfig.getBaseUrl();
    this.savedBaseUrl = this.baseUrl;
    await this.load();
    await this.checkServer();
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    try {
      const dto = await AccountService.settings();
      const user = dto.user;
      if (user !== undefined) {
        this.userId = user.id;
        this.email = user.email;
        this.role = user.role;
        this.cefrLevel = user.cefrLevel;
        this.isChild = user.role === 'child' || user.isChild === true;
        this.avatarEmoji = (user.avatar === undefined || user.avatar === null) ? '' : user.avatar;
        this.displayName = user.displayName;
        this.autoIllustrate = user.autoIllustrate === true;
        this.gender = (user.gender === undefined || user.gender === null) ? '' : user.gender;
        this.storySentences = (user.storySentences === undefined || user.storySentences === null)
          ? -1 : user.storySentences;
        this.dailyLimit = user.dailyLimitMinutes === undefined ? 20 : user.dailyLimitMinutes;
        this.allowFreeChat = user.allowFreeChat === true;
      }
      const prefs = dto.prefs;
      if (prefs !== undefined) {
        this.correctionLevel = (prefs.correctionLevel === undefined || prefs.correctionLevel.length === 0)
          ? 'gentle' : prefs.correctionLevel;
        this.ttsVoice = (prefs.ttsVoice === undefined || prefs.ttsVoice === null) ? '' : prefs.ttsVoice;
        this.ttsRate = (prefs.ttsRate === undefined || prefs.ttsRate.length === 0)
          ? (this.isChild ? 'slow' : 'normal') : prefs.ttsRate;
        this.showWordIpa = (prefs.showWordIpa === undefined || prefs.showWordIpa === null)
          ? true : prefs.showWordIpa;
      }
      const usage = dto.usage;
      if (usage !== undefined) {
        this.usageMinutes = usage.minutes;
        this.usageLimit = usage.limitMinutes;
      }
      this.syncSession(dto.user, dto.usage);
      this.loaded = true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, this.isChild);
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  /** 前端前置校验（服务端「先写 users 再校验 prefs」有缺陷，必须客户端兜住）。返回空串 = 通过。 */
  validate(): string {
    const name = this.displayName.trim();
    if (name.length < 1 || name.length > 30) {
      return '昵称需为 1–30 个字符';
    }
    if (!this.isChild) {
      if (this.dailyLimit < 5 || this.dailyLimit > 180) {
        return '每日时长上限需在 5–180 分钟之间';
      }
    }
    if (this.gender.length > 0 && !AccountSettingsVM.isGender(this.gender)) {
      return '性别取值不合法';
    }
    if (this.storySentences !== -1 && (this.storySentences < 3 || this.storySentences > 12)) {
      return '故事句子数需在 3–12 之间';
    }
    if (this.correctionLevel !== 'gentle' && this.correctionLevel !== 'standard'
      && this.correctionLevel !== 'none') {
      return '纠正强度取值不合法';
    }
    if (this.ttsRate !== 'slow' && this.ttsRate !== 'normal') {
      return '语速取值不合法';
    }
    if (this.ttsVoice.length > 0 && !MediaService.isKnownVoice(this.ttsVoice)) {
      return '音色不在可选范围内';
    }
    return '';
  }

  async save(): Promise<boolean> {
    if (this.saving) {
      return false;
    }
    this.hasError = false;
    this.hasNotice = false;
    const problem = this.validate();
    if (problem.length > 0) {
      this.setError(problem);
      return false;
    }
    this.saving = true;
    try {
      const dto = await AccountService.patchSettings(this.buildPatch());
      // 注意：PATCH 返回的 user 是瘦身版（没有 gender/autoIllustrate/storySentences），
      // 不能用它覆盖本地表单；只同步 prefs 与 usage。
      const prefs = dto.prefs;
      if (prefs !== undefined) {
        if (prefs.correctionLevel !== undefined) {
          this.correctionLevel = prefs.correctionLevel;
        }
        this.ttsVoice = (prefs.ttsVoice === undefined || prefs.ttsVoice === null) ? '' : prefs.ttsVoice;
        if (prefs.ttsRate !== undefined) {
          this.ttsRate = prefs.ttsRate;
        }
        this.showWordIpa = (prefs.showWordIpa === undefined || prefs.showWordIpa === null)
          ? true : prefs.showWordIpa;
      }
      const usage = dto.usage;
      if (usage !== undefined) {
        this.usageMinutes = usage.minutes;
        this.usageLimit = usage.limitMinutes;
        SessionStore.updateUsage(usage);
      }
      // 保存后刷新全局会话里的昵称/时长（PATCH 返回的瘦身 user 不含 gender 等字段，
      // 所以这里用本地表单值补全，而不是覆盖表单）。
      this.pushSession();
      void AccountPrefs.reload();
      this.notice = '已保存 ✅';
      this.hasNotice = true;
      return true;
    } catch (err) {
      const e = err as Error;
      if (e instanceof ApiError) {
        if (AccountSettingsVM.isPatchUnsupported(e)) {
          this.setError('该设置暂不可用（当前服务器不支持保存偏好）');
        } else if (e.status === 403) {
          this.setError(e.detail.length > 0 ? e.detail : '每日时长与自由话题由家长设置');
        } else {
          this.setError(SessionStore.toUiError(e as Error, this.isChild).message);
        }
        // 服务端可能「先落库再校验失败」：400 后重新拉一次同步真实状态
        if (e.status === 400) {
          await this.load();
        }
      } else {
        this.setError(SessionStore.toUiError(e, this.isChild).message);
      }
      return false;
    } finally {
      this.saving = false;
    }
  }

  private buildPatch(): SettingsPatchBodyDto {
    const body: SettingsPatchBodyDto = {};
    body.display_name = this.displayName.trim();
    body.auto_illustrate = this.autoIllustrate;
    body.gender = this.gender.length === 0 ? null : this.gender;
    body.story_sentences = this.storySentences < 0 ? null : this.storySentences;
    body.correction_level = this.correctionLevel;
    body.tts_voice = this.ttsVoice.length === 0 ? null : this.ttsVoice;
    body.tts_rate = this.ttsRate;
    body.show_word_ipa = this.showWordIpa;
    if (!this.isChild) {
      body.daily_limit_minutes = this.dailyLimit;
      body.allow_free_chat = this.allowFreeChat;
    }
    return body;
  }

  private syncSession(user: AccountUserDto | undefined,
    usage: UsageDto | undefined): void {
    if (user === undefined) {
      return;
    }
    const dto: UserDto = {
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      role: user.role,
      ageBand: user.ageBand,
      cefrLevel: user.cefrLevel,
      avatar: user.avatar,
      dailyLimitMinutes: user.dailyLimitMinutes,
      allowFreeChat: user.allowFreeChat,
      isChild: user.isChild,
      nativeLanguage: user.nativeLanguage
    };
    SessionStore.applyUser(dto, usage === undefined ? null : usage);
  }

  storyDefault(): number {
    return this.isChild ? 5 : 8;
  }

  /** 把本地表单值同步到全局会话（MePage 昵称/用量即时更新；不影响账号数据）。 */
  private pushSession(): void {
    const dto: UserDto = {
      id: this.userId,
      email: this.email,
      displayName: this.displayName.trim(),
      role: this.role,
      ageBand: this.isChild ? 'child' : 'adult',
      cefrLevel: this.cefrLevel,
      avatar: this.avatarEmoji,
      dailyLimitMinutes: this.dailyLimit,
      allowFreeChat: this.allowFreeChat,
      isChild: this.isChild,
      nativeLanguage: 'zh'
    };
    SessionStore.applyUser(dto, null);
    const usage: UsageDto = {
      minutes: this.usageMinutes,
      limitMinutes: this.usageLimit,
      remainingMinutes: Math.max(0, Math.round((this.usageLimit - this.usageMinutes) * 10) / 10),
      exceeded: this.usageMinutes >= this.usageLimit
    };
    SessionStore.updateUsage(usage);
  }

  applyStoryDefault(): void {
    this.storySentences = -1;
  }

  /**
   * 判断 PATCH 是否不被当前环境支持（ApiClient 用字符串方法名下发 PATCH，见其注释）。
   * 405/501 明确不支持；部分系统会在 http 层直接抛错（status=0 且错误信息含 method/patch）。
   */
  static isPatchUnsupported(e: ApiError): boolean {
    if (e.status === 405 || e.status === 501) {
      return true;
    }
    if (e.status === 0) {
      const detail = e.detail.toLowerCase();
      return detail.indexOf('patch') >= 0 || detail.indexOf('method') >= 0;
    }
    return false;
  }

  static isGender(value: string): boolean {
    return value === 'girl' || value === 'boy' || value === 'woman' || value === 'man' || value === 'other';
  }

  usageText(): string {
    const minutes = Math.round(this.usageMinutes * 10) / 10;
    return '今日已练 ' + minutes.toString() + ' / ' + this.usageLimit.toString() + ' 分钟';
  }

  roleText(): string {
    if (this.isChild) {
      return '小朋友';
    }
    return this.role === 'parent' ? '家长' : '学习者';
  }

  /** 当前音色的中文名（列表里存的是 id，展示用这个）。 */
  voiceLabel(): string {
    if (this.ttsVoice.length === 0) {
      return '默认音色（provider 决定）';
    }
    const option = MediaService.findVoice(this.ttsVoice);
    return option === null ? this.ttsVoice : option.labelZh;
  }

  // ---------------------------------------------------------------- 服务器地址

  async checkServer(): Promise<void> {
    if (this.checkingServer) {
      return;
    }
    this.checkingServer = true;
    this.serverStatus = '';
    try {
      const health = await PracticeService.health();
      const voice = health.voice;
      if (voice !== undefined && voice.reachable === false) {
        this.serverStatus = '已连接；语音服务未就绪（录音会先保存，可稍后重试评测）';
      } else {
        const db = health.db;
        this.serverStatus = (db !== undefined && db.ok === false) ? '已连接；数据库异常' : '已连接';
      }
    } catch (err) {
      this.serverStatus = SessionStore.toUiError(err as Error, false).message;
    } finally {
      this.checkingServer = false;
    }
  }

  async saveBaseUrl(): Promise<void> {
    if (this.savingAddress) {
      return;
    }
    this.hasError = false;
    this.hasNotice = false;
    const normalized = AppConfig.normalizeUrl(this.baseUrl);
    if (!AppConfig.isValidUrl(normalized)) {
      this.setError(ErrorMapper.messageFor(ApiErrorCode.BAD_BASE_URL, false));
      return;
    }
    this.savingAddress = true;
    try {
      this.savedBaseUrl = await AppConfig.setBaseUrl(normalized);
      this.baseUrl = this.savedBaseUrl;
      this.notice = AppConfig.isCleartext(this.savedBaseUrl)
        ? '已保存。注意：http 明文在部分网络下会被系统拦截，建议使用 https'
        : '服务器地址已保存';
      this.hasNotice = true;
      await this.checkServer();
    } catch (err) {
      this.setError(SessionStore.toUiError(err as Error, false).message);
    } finally {
      this.savingAddress = false;
    }
  }

  clearAudioCache(): void {
    this.hasError = false;
    CacheService.clearAudioCache();
    this.notice = '已清除示范音与回放缓存';
    this.hasNotice = true;
  }

  async logout(): Promise<void> {
    if (this.loggingOut) {
      return;
    }
    this.loggingOut = true;
    try {
      await SessionStore.logout();
    } finally {
      this.loggingOut = false;
    }
  }

  tokenStorageNote(): string {
    return TokenSession.isDegraded()
      ? '凭证保存在内存（本次运行有效）：系统安全存储当前不可用'
      : '凭证保存在系统安全存储（Asset Store）';
  }

  clearNotice(): void {
    this.hasNotice = false;
  }

  private setError(message: string): void {
    this.error = new UiError('', message, '', false, '');
    this.hasError = true;
  }
}

// ===========================================================================
// 家庭成员（/family/members）
// ===========================================================================

@Observed
export class FamilyVM {
  items: FamilyMemberDto[] = [];
  loading: boolean = false;
  loadedOnce: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');
  notice: string = '';

  // 新建表单
  showForm: boolean = false;
  displayName: string = '';
  login: string = '';
  password: string = '';
  role: string = 'parent';
  cefrLevel: string = 'A2';
  dailyLimit: number = 20;
  allowFreeChat: boolean = true;
  creating: boolean = false;
  formError: string = '';

  // 编辑
  editingId: string = '';
  editDisplayName: string = '';
  editCefrLevel: string = 'A2';
  editDailyLimit: number = 20;
  editAllowFreeChat: boolean = false;
  savingEdit: boolean = false;
  editError: string = '';

  // 重置密码
  resettingId: string = '';
  newPassword: string = '';
  resetting: boolean = false;
  resetError: string = '';

  async init(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    try {
      this.items = await AccountService.familyMembers();
      this.loadedOnce = true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, false);
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  toggleForm(): void {
    this.showForm = !this.showForm;
    this.formError = '';
    this.notice = '';
  }

  async create(): Promise<boolean> {
    if (this.creating) {
      return false;
    }
    this.formError = '';
    const name = this.displayName.trim();
    if (name.length < 1 || name.length > 20) {
      this.formError = '请填写昵称（最多 20 字）';
      return false;
    }
    if (this.login.trim().length === 0) {
      this.formError = '请填写登录名（可只写简称，例如 laoba）';
      return false;
    }
    if (this.password.length < 8) {
      this.formError = '密码至少 8 位';
      return false;
    }
    if (this.dailyLimit < 5 || this.dailyLimit > 180) {
      this.formError = '每日时长需要在 5–180 分钟之间';
      return false;
    }
    this.creating = true;
    try {
      const body: FamilyCreateBodyDto = {
        display_name: name,
        login: this.login.trim(),
        password: this.password,
        role: this.role,
        cefr_level: this.cefrLevel,
        daily_limit_minutes: this.dailyLimit,
        allow_free_chat: this.allowFreeChat
      };
      const result = await AccountService.createMember(body);
      const member = result.member;
      const memberName = (member === undefined || member.display_name === undefined) ? name : member.display_name;
      const memberEmail = (member === undefined || member.email === undefined) ? '' : member.email;
      this.notice = '已创建 ' + memberName + (memberEmail.length > 0 ? ('（登录名 ' + memberEmail + '）') : '');
      this.displayName = '';
      this.login = '';
      this.password = '';
      this.showForm = false;
      await this.load();
      return true;
    } catch (err) {
      const e = err as Error;
      if (e instanceof ApiError && e.status === 409) {
        this.formError = e.detail.length > 0 ? e.detail : '登录名已经有人用了，换一个吧';
      } else {
        this.formError = SessionStore.toUiError(e, false).message;
      }
      return false;
    } finally {
      this.creating = false;
    }
  }

  beginEdit(member: FamilyMemberDto): void {
    this.editingId = member.id;
    this.editDisplayName = member.display_name === undefined ? '' : member.display_name;
    this.editCefrLevel = member.cefr_level === undefined ? 'A2' : member.cefr_level;
    this.editDailyLimit = member.daily_limit_minutes === undefined ? 20 : member.daily_limit_minutes;
    this.editAllowFreeChat = member.allow_free_chat === true;
    this.editError = '';
    this.resettingId = '';
  }

  cancelEdit(): void {
    this.editingId = '';
    this.editError = '';
  }

  async saveEdit(): Promise<boolean> {
    if (this.savingEdit || this.editingId.length === 0) {
      return false;
    }
    const name = this.editDisplayName.trim();
    if (name.length < 1 || name.length > 20) {
      this.editError = '昵称需为 1–20 个字符';
      return false;
    }
    if (this.editDailyLimit < 5 || this.editDailyLimit > 180) {
      this.editError = '每日时长需要在 5–180 分钟之间';
      return false;
    }
    this.savingEdit = true;
    this.editError = '';
    try {
      const body: FamilyPatchBodyDto = {
        display_name: name,
        cefr_level: this.editCefrLevel,
        daily_limit_minutes: this.editDailyLimit,
        allow_free_chat: this.editAllowFreeChat
      };
      await AccountService.updateMember(this.editingId, body);
      this.editingId = '';
      this.notice = '已保存成员信息 ✅';
      await this.load();
      return true;
    } catch (err) {
      this.editError = SessionStore.toUiError(err as Error, false).message;
      return false;
    } finally {
      this.savingEdit = false;
    }
  }

  beginReset(member: FamilyMemberDto): void {
    this.resettingId = member.id;
    this.newPassword = '';
    this.resetError = '';
    this.editingId = '';
  }

  cancelReset(): void {
    this.resettingId = '';
    this.resetError = '';
  }

  async resetPassword(): Promise<boolean> {
    if (this.resetting || this.resettingId.length === 0) {
      return false;
    }
    if (this.newPassword.length < 8) {
      this.resetError = '密码至少 8 位';
      return false;
    }
    this.resetting = true;
    this.resetError = '';
    try {
      await AccountService.resetMemberPassword(this.resettingId, this.newPassword);
      this.resettingId = '';
      this.newPassword = '';
      this.notice = '密码已重置（旧密码已失效）';
      return true;
    } catch (err) {
      this.resetError = SessionStore.toUiError(err as Error, false).message;
      return false;
    } finally {
      this.resetting = false;
    }
  }

  memberTitle(member: FamilyMemberDto): string {
    const name = member.display_name === undefined ? '成员' : member.display_name;
    const isChild = member.role === 'child';
    const emoji = (member.avatar === undefined || member.avatar === null)
      ? (isChild ? '🧒' : '👤') : member.avatar;
    return emoji + ' ' + name;
  }

  memberBadge(member: FamilyMemberDto): string {
    const role = member.role === 'parent' ? '家长' : '孩子';
    const cefr = member.cefr_level === undefined ? '' : member.cefr_level;
    return role + (cefr.length > 0 ? (' · ' + cefr) : '');
  }

  memberSubText(member: FamilyMemberDto): string {
    const limit = member.daily_limit_minutes === undefined ? 20 : member.daily_limit_minutes;
    const stats = member.stats;
    const attempts = (stats === undefined || stats.attempts === undefined) ? 0 : stats.attempts;
    return limit.toString() + ' 分钟/天 · 练过 ' + attempts.toString() + ' 次';
  }

  memberEmail(member: FamilyMemberDto): string {
    return member.email === undefined ? '' : member.email;
  }
}

// ===========================================================================
// 家长面板（/parent/summary）
// ===========================================================================

@Observed
export class ParentVM {
  loading: boolean = false;
  loadedOnce: boolean = false;
  hasError: boolean = false;
  forbidden: boolean = false;
  error: UiError = new UiError('', '', '', false, '');

  familyMembers: number = 0;
  minutesToday: number = 0;
  minutes7d: number = 0;
  sentenceCount: number = 0;
  scenarioCount: number = 0;
  children: ParentChildDto[] = [];
  members: ParentMemberDto[] = [];

  // 家庭邀请码（多家庭；仅家长可见）
  inviteLoading: boolean = false;
  inviteRotating: boolean = false;
  inviteError: string = '';
  inviteFamilyName: string = '';
  inviteCode: string = '';
  inviteUsed: boolean = false;
  inviteParentsCount: number = 0;
  inviteParentsLimit: number = 3;

  async init(): Promise<void> {
    await this.load();
    if (!this.forbidden) {
      await this.loadInvite();
    }
  }

  /** GET /family/invite —— 邀请码 / 是否已用 / 家长人数与上限。 */
  async loadInvite(): Promise<void> {
    if (this.inviteLoading) {
      return;
    }
    this.inviteLoading = true;
    this.inviteError = '';
    try {
      const dto = await AccountService.familyInvite();
      this.inviteFamilyName = dto.family_name === undefined ? '' : dto.family_name;
      this.inviteCode = dto.invite_code === undefined ? '' : dto.invite_code;
      this.inviteUsed = dto.invite_used === true;
      this.inviteParentsCount = dto.parents_count === undefined ? 0 : dto.parents_count;
      this.inviteParentsLimit = dto.parents_limit === undefined ? 3 : dto.parents_limit;
    } catch (err) {
      this.inviteError = SessionStore.toUiError(err as Error, false).message;
    } finally {
      this.inviteLoading = false;
    }
  }

  /** POST /family/invite/rotate —— 旧码立即失效，生成新的一次性邀请码。 */
  async rotateInvite(): Promise<boolean> {
    if (this.inviteRotating) {
      return false;
    }
    this.inviteRotating = true;
    this.inviteError = '';
    try {
      const dto = await AccountService.rotateFamilyInvite();
      this.inviteFamilyName = dto.family_name === undefined ? this.inviteFamilyName : dto.family_name;
      this.inviteCode = dto.invite_code === undefined ? '' : dto.invite_code;
      this.inviteUsed = false;
      return true;
    } catch (err) {
      this.inviteError = SessionStore.toUiError(err as Error, false).message;
      return false;
    } finally {
      this.inviteRotating = false;
    }
  }

  inviteAtLimit(): boolean {
    return this.inviteParentsCount >= this.inviteParentsLimit;
  }

  inviteStatusText(): string {
    const count = this.inviteParentsCount.toString() + '/' + this.inviteParentsLimit.toString();
    if (this.inviteAtLimit()) {
      return '家长账号 ' + count + ' · 已满，不能再邀请新家长';
    }
    if (this.inviteUsed) {
      return '家长账号 ' + count + ' · 邀请码已被使用（一次性），点「重置」生成新码';
    }
    return '家长账号 ' + count + ' · 邀请码可用（一次性，用后失效）';
  }

  async loadSummaryOnly(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    this.forbidden = false;
    try {
      const dto = await AccountService.parentSummary();
      const family = dto.family;
      if (family !== undefined) {
        this.familyMembers = family.members === undefined ? 0 : family.members;
        this.minutesToday = family.minutes_today === undefined ? 0 : family.minutes_today;
        this.minutes7d = family.minutes_7d === undefined ? 0 : family.minutes_7d;
        this.sentenceCount = family.sentence_count === undefined ? 0 : family.sentence_count;
        this.scenarioCount = family.scenario_count === undefined ? 0 : family.scenario_count;
        this.children = family.children === undefined ? [] : family.children;
      }
      this.members = dto.members === undefined ? [] : dto.members;
      this.loadedOnce = true;
    } catch (err) {
      const e = err as Error;
      if (e instanceof ApiError && e.status === 403) {
        this.forbidden = true;
        this.error = new UiError('', e.detail.length > 0 ? e.detail : '家长面板仅对家长账号开放', '', false,
          ApiErrorCode.FORBIDDEN);
      } else {
        this.error = SessionStore.toUiError(e, false);
      }
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  familyText(): string {
    return '全家今天共练习 ' + ParentVM.minutes(this.minutesToday) + ' 分钟，近 7 天 ' +
      ParentVM.minutes(this.minutes7d) + ' 分钟 · 语料 ' + this.sentenceCount.toString() +
      ' 句 · 对话场景 ' + this.scenarioCount.toString() + ' 个';
  }

  static minutes(value: number): string {
    return (Math.round(value * 10) / 10).toString();
  }

  memberTitle(member: ParentMemberDto): string {
    const name = member.display_name === undefined ? '成员' : member.display_name;
    const avatar = (member.avatar === undefined || member.avatar === null) ? '🙂' : member.avatar;
    return avatar + ' ' + name;
  }

  memberBadge(member: ParentMemberDto): string {
    const role = member.role === 'child' ? '孩子' : '家长';
    const cefr = member.cefr_level === undefined ? '' : member.cefr_level;
    return role + (cefr.length > 0 ? (' · ' + cefr) : '');
  }

  /** 今日一行：`今日练习 X 分钟 + 盲测 Y 分钟 · 跟读 N 次 · 对话 M 轮 · 剩余 Z 分钟`。 */
  memberTodayText(member: ParentMemberDto): string {
    const today = member.today;
    if (today === undefined) {
      return '今日暂无练习';
    }
    const minutes = today.minutes === undefined ? 0 : today.minutes;
    const blind = today.blind_minutes === undefined ? 0 : today.blind_minutes;
    const attempts = today.attempt_count === undefined ? 0 : today.attempt_count;
    const turns = today.chat_turns === undefined ? 0 : today.chat_turns;
    let text = '今日练习 ' + ParentVM.minutes(minutes) + ' 分钟';
    if (blind > 0) {
      text = text + ' + 盲测 ' + ParentVM.minutes(blind) + ' 分钟';
    }
    text = text + ' · 跟读 ' + attempts.toString() + ' 次 · 对话 ' + turns.toString() + ' 轮';
    const remaining = today.remaining_minutes;
    if (remaining !== undefined && remaining !== null) {
      text = text + ' · 剩余 ' + ParentVM.minutes(remaining) + ' 分钟';
    }
    return text;
  }

  memberWeekText(member: ParentMemberDto): string {
    const week = member.week;
    const totals = member.totals;
    if (week === undefined && totals === undefined) {
      return '';
    }
    const minutes = (week === undefined || week.minutes === undefined) ? 0 : week.minutes;
    const attempts = (week === undefined || week.attempts === undefined) ? 0 : week.attempts;
    const avg = (week === undefined) ? null : week.avg_pron;
    const totalAttempts = (totals === undefined || totals.attempts === undefined) ? 0 : totals.attempts;
    const sessions = (totals === undefined || totals.chat_sessions === undefined) ? 0 : totals.chat_sessions;
    return '近 7 天时长 ' + ParentVM.minutes(minutes) + ' 分钟 · 近 7 天练习 ' + attempts.toString() +
      ' 次 · 近 7 天平均分 ' + ParentVM.scoreText(avg) + ' · 累计 ' + totalAttempts.toString() +
      ' 次跟读 / ' + sessions.toString() + ' 场对话';
  }

  static scoreText(score: number | null | undefined): string {
    if (score === undefined || score === null) {
      return '—';
    }
    return (Math.round(score * 10) / 10).toString();
  }

  blindScoreText(member: ParentMemberDto): string {
    const blind = member.blind;
    if (blind === undefined || blind.current === undefined || blind.current === null) {
      return '—';
    }
    return ParentVM.scoreText(blind.current.avg_pron);
  }

  blindDeltaText(member: ParentMemberDto): string {
    const blind = member.blind;
    if (blind === undefined || blind.current === undefined || blind.current === null) {
      return '还没有盲测数据';
    }
    const delta = blind.delta_pron;
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

  blindDeltaColor(member: ParentMemberDto): ResourceColor {
    const blind = member.blind;
    if (blind === undefined || blind.delta_pron === undefined || blind.delta_pron === null) {
      return $r('app.color.ec_muted');
    }
    if (blind.delta_pron > 0) {
      return $r('app.color.ec_good_text');
    }
    if (blind.delta_pron < 0) {
      return $r('app.color.ec_bad_text');
    }
    return $r('app.color.ec_muted');
  }

  blindWeeks(member: ParentMemberDto): number {
    const blind = member.blind;
    if (blind === undefined || blind.weeks === undefined) {
      return 0;
    }
    return blind.weeks;
  }

  phonemeLine(member: ParentMemberDto): string {
    const top = member.top_phonemes;
    if (top === undefined || top.length === 0) {
      return '';
    }
    const first = top[0];
    const phoneme = first.phoneme === undefined ? '' : first.phoneme;
    const title = first.title_zh === undefined ? '' : first.title_zh;
    const avg = ParentVM.scoreText(first.avg_score);
    const count = first.count === undefined ? 0 : first.count;
    const hard = first.hard_hits === undefined ? 0 : first.hard_hits;
    return phoneme + ' ' + title + ' · 均 ' + avg + ' · ' + count.toString() + ' 次 · 低于60 ' +
      hard.toString() + ' 次';
  }

  /** 成员的盲测柱状数据（无则空数组，页面不用做可选链）。 */
  blindSeries(member: ParentMemberDto): ParentBlindScoreDto[] {
    const blind = member.blind;
    if (blind === undefined || blind.series === undefined) {
      return [];
    }
    return blind.series;
  }

  blindCurrentPron(member: ParentMemberDto): number | null {
    const blind = member.blind;
    if (blind === undefined || blind.current === undefined || blind.current === null) {
      return null;
    }
    return blind.current.avg_pron === undefined ? null : blind.current.avg_pron;
  }

  blindAccuracy(member: ParentMemberDto): number | null {
    const blind = member.blind;
    if (blind === undefined || blind.current === undefined || blind.current === null) {
      return null;
    }
    return blind.current.avg_accuracy === undefined ? null : blind.current.avg_accuracy;
  }

  blindFluency(member: ParentMemberDto): number | null {
    const blind = member.blind;
    if (blind === undefined || blind.current === undefined || blind.current === null) {
      return null;
    }
    return blind.current.avg_fluency === undefined ? null : blind.current.avg_fluency;
  }

  blindIntonation(member: ParentMemberDto): number | null {
    const blind = member.blind;
    if (blind === undefined || blind.current === undefined || blind.current === null) {
      return null;
    }
    return blind.current.avg_intonation_distance === undefined
      ? null : blind.current.avg_intonation_distance;
  }

  topPhonemes(member: ParentMemberDto): ParentPhonemeDto[] {
    return member.top_phonemes === undefined ? [] : member.top_phonemes;
  }

  topWords(member: ParentMemberDto): ParentWordDto[] {
    return member.top_words === undefined ? [] : member.top_words;
  }

  trendPoints(member: ParentMemberDto): ParentTrendPointDto[] {
    return member.trend === undefined ? [] : member.trend;
  }

  /** 近 14 天趋势的最后 3 天文字。 */
  trendTail(member: ParentMemberDto): string {
    const points = this.trendPoints(member);
    if (points.length === 0) {
      return '暂无数据';
    }
    const start = points.length > 3 ? points.length - 3 : 0;
    const parts: string[] = [];
    for (let i = start; i < points.length; i++) {
      const date = points[i].date === undefined ? '' : points[i].date;
      const score = ParentVM.scoreText(points[i].avg_pron);
      parts.push(date + ': ' + score);
    }
    return parts.join(' · ');
  }

  phonemeText(item: ParentPhonemeDto): string {
    const phoneme = item.phoneme === undefined ? '' : item.phoneme;
    const title = item.title_zh === undefined ? '' : item.title_zh;
    return (phoneme + ' ' + title).trim();
  }

  phonemeMeta(item: ParentPhonemeDto): string {
    return '均 ' + ParentVM.scoreText(item.avg_score) + ' · ' +
      (item.count === undefined ? 0 : item.count).toString() + ' 次 · 低于60 ' +
      (item.hard_hits === undefined ? 0 : item.hard_hits).toString() + ' 次';
  }

  wordText(item: ParentWordDto): string {
    return (item.word === undefined ? '' : item.word) + ' × ' +
      (item.count === undefined ? 0 : item.count).toString() + '（均 ' +
      ParentVM.scoreText(item.avg_score) + '）';
  }

  /** 儿童剩余时长卡文案。 */
  childRemainingText(child: ParentChildDto): string {
    const remaining = child.remaining_minutes;
    const limit = child.limit_minutes;
    const remainingText = (remaining === undefined || remaining === null) ? '—'
      : ParentVM.minutes(remaining);
    const limitText = (limit === undefined || limit === null) ? '—' : limit.toString();
    return remainingText + ' / ' + limitText + ' 分钟';
  }
}

// ===========================================================================
// 建议箱（/suggestions）
// ===========================================================================

/** 建议分类（家长 5 类 / 儿童 3 类，文案两套）。 */
export class SuggestionCategory {
  key: string = '';
  adultLabel: string = '';
  childLabel: string = '';

  constructor(key: string, adultLabel: string, childLabel: string) {
    this.key = key;
    this.adultLabel = adultLabel;
    this.childLabel = childLabel;
  }
}

@Observed
export class SuggestionsVM {
  isChild: boolean = false;
  maxLength: number = 2000;

  // 提交（所有人）
  category: string = 'experience';
  content: string = '';
  submitting: boolean = false;
  createError: string = '';
  createNotice: string = '';

  // 列表（仅家长）
  items: SuggestionDto[] = [];
  total: number = 0;
  countOpen: number = 0;
  countRead: number = 0;
  countResolved: number = 0;
  filterStatus: string = '';
  listLoading: boolean = false;
  listLoadedOnce: boolean = false;
  listError: UiError = new UiError('', '', '', false, '');
  listHasError: boolean = false;
  markingId: string = '';
  markingError: string = '';

  // 导出（仅家长）
  exportText: string = '';
  exporting: boolean = false;
  exportError: string = '';
  exportNotice: string = '';

  init(isChild: boolean): void {
    this.isChild = isChild;
    this.category = 'experience';
    if (!isChild) {
      void this.loadList();
    }
  }

  categories(): SuggestionCategory[] {
    const all: SuggestionCategory[] = [
      new SuggestionCategory('experience', '体验问题', '用起来哪里不顺手'),
      new SuggestionCategory('content', '内容建议', '想读·想聊的内容'),
      new SuggestionCategory('feature', '新功能想法', '想要的新功能'),
      new SuggestionCategory('bug', '程序出错', '哪里出错了'),
      new SuggestionCategory('other', '其他', '其他想法')
    ];
    if (!this.isChild) {
      return all;
    }
    const childOnly: SuggestionCategory[] = [];
    for (let i = 0; i < all.length; i++) {
      const key = all[i].key;
      if (key === 'experience' || key === 'content' || key === 'other') {
        childOnly.push(all[i]);
      }
    }
    return childOnly;
  }

  adultLabel(key: string): string {
    const all = this.categories();
    for (let i = 0; i < all.length; i++) {
      if (all[i].key === key) {
        return all[i].adultLabel;
      }
    }
    return key;
  }

  categoryLabel(key: string): string {
    const labels: SuggestionCategory[] = [
      new SuggestionCategory('experience', '体验问题', '用起来哪里不顺手'),
      new SuggestionCategory('content', '内容建议', '想读·想聊的内容'),
      new SuggestionCategory('feature', '新功能想法', '想要的新功能'),
      new SuggestionCategory('bug', '程序出错', '哪里出错了'),
      new SuggestionCategory('other', '其他', '其他想法')
    ];
    for (let i = 0; i < labels.length; i++) {
      if (labels[i].key === key) {
        return this.isChild ? labels[i].childLabel : labels[i].adultLabel;
      }
    }
    return key;
  }

  statusLabel(status: string): string {
    if (status === 'open') {
      return '未读';
    }
    if (status === 'read') {
      return '已读';
    }
    if (status === 'resolved') {
      return '已解决';
    }
    return status;
  }

  roleLabel(role: string): string {
    if (role === 'child') {
      return '孩子';
    }
    if (role === 'parent') {
      return '家长';
    }
    return '未知';
  }

  title(): string {
    return this.isChild ? '💡 我想说点什么' : '💡 提建议';
  }

  subtitle(): string {
    return this.isChild
      ? '用起来哪里不顺手、想读什么故事、想加什么功能，都可以告诉我 🙂'
      : '哪里不好用、想要什么功能、内容有什么问题，都记在这里，家长可以统一查看和导出。';
  }

  async submit(): Promise<boolean> {
    if (this.submitting) {
      return false;
    }
    this.createError = '';
    this.createNotice = '';
    const text = this.content.trim();
    if (text.length === 0) {
      this.createError = this.isChild ? '先写一句想说的话吧' : '请先写点什么再提交';
      return false;
    }
    if (text.length > this.maxLength) {
      this.createError = '建议最多 ' + this.maxLength.toString() + ' 字（当前 ' + text.length.toString() + ' 字）';
      return false;
    }
    this.submitting = true;
    try {
      const page = '/settings';
      const body: SuggestionCreateBodyDto = {
        category: this.category,
        content: text,
        page: page
      };
      await AccountService.submitSuggestion(body);
      this.content = '';
      this.createNotice = this.isChild ? '收到啦，谢谢你！🌟' : '收到啦，谢谢！已记到建议列表里。';
      if (!this.isChild) {
        await this.loadList();
      }
      return true;
    } catch (err) {
      this.createError = SessionStore.toUiError(err as Error, this.isChild).message;
      return false;
    } finally {
      this.submitting = false;
    }
  }

  async setFilter(status: string): Promise<void> {
    if (this.filterStatus === status) {
      return;
    }
    this.filterStatus = status;
    this.listLoadedOnce = false;
    await this.loadList();
  }

  async loadList(): Promise<void> {
    if (this.listLoading || this.isChild) {
      return;
    }
    this.listLoading = true;
    this.listHasError = false;
    try {
      const dto = await AccountService.listSuggestions(this.filterStatus, 50, 0);
      this.items = dto.items === undefined ? [] : dto.items;
      this.total = dto.total === undefined ? 0 : dto.total;
      const counts = dto.counts;
      this.countOpen = (counts === undefined || counts.open === undefined) ? 0 : counts.open;
      this.countRead = (counts === undefined || counts.read === undefined) ? 0 : counts.read;
      this.countResolved = (counts === undefined || counts.resolved === undefined) ? 0 : counts.resolved;
      if (dto.max_length !== undefined) {
        this.maxLength = dto.max_length;
      }
      this.listLoadedOnce = true;
    } catch (err) {
      this.listError = SessionStore.toUiError(err as Error, false);
      this.listHasError = true;
    } finally {
      this.listLoading = false;
    }
  }

  async mark(suggestionId: string, status: string): Promise<boolean> {
    if (this.markingId.length > 0) {
      return false;
    }
    this.markingId = suggestionId;
    this.markingError = '';
    try {
      await AccountService.patchSuggestionStatus(suggestionId, status);
      await this.loadList();
      return true;
    } catch (err) {
      this.markingError = SessionStore.toUiError(err as Error, false).message;
      return false;
    } finally {
      this.markingId = '';
    }
  }

  async exportMarkdown(): Promise<boolean> {
    if (this.exporting || this.isChild) {
      return false;
    }
    this.exporting = true;
    this.exportError = '';
    this.exportNotice = '';
    try {
      this.exportText = await AccountService.exportSuggestionsMarkdown(this.filterStatus);
      this.exportNotice = '已生成 Markdown（可长按选中复制）';
      return true;
    } catch (err) {
      this.exportError = SessionStore.toUiError(err as Error, false).message;
      return false;
    } finally {
      this.exporting = false;
    }
  }
}

// ===========================================================================
// 虚拟形象（/avatar + /avatar/presets）
// ===========================================================================

@Observed
export class AvatarVM {
  loading: boolean = false;
  loadedOnce: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');
  notice: string = '';

  styles: AvatarStyleDto[] = [];
  characters: AvatarPresetCharacterDto[] = [];
  placeholder: boolean = false;

  selectedStyle: string = 'watercolor';
  audience: string = 'child';
  showAllGender: boolean = false;
  myGender: string = '';

  current: AvatarStateDto | null = null;
  saving: boolean = false;
  descDraft: string = '';
  savingDesc: boolean = false;

  async init(isChild: boolean): Promise<void> {
    this.audience = isChild ? 'child' : 'adult';
    await this.load();
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    try {
      const presets = await AccountService.avatarPresets();
      this.styles = presets.styles === undefined ? [] : presets.styles;
      this.characters = presets.characters === undefined ? [] : presets.characters;
      this.placeholder = presets.placeholder === true;
      if (this.styles.length > 0 && this.selectedStyle.length === 0) {
        this.selectedStyle = this.styles[0].id;
      }
      try {
        this.current = await AccountService.avatar();
        const style = this.current.style;
        if (style !== undefined && style !== null && style.length > 0) {
          this.selectedStyle = style;
        }
        const desc = this.current.character_desc;
        this.descDraft = (desc === undefined || desc === null) ? '' : desc;
      } catch (err) {
        this.current = null;
      }
      // 性别用于默认过滤（只影响展示，不是隐私数据）
      try {
        const settings = await AccountService.settings();
        const user = settings.user;
        if (user !== undefined) {
          const gender = user.gender;
          this.myGender = (gender === undefined || gender === null) ? '' : gender;
        }
      } catch (err) {
        this.myGender = '';
      }
      this.loadedOnce = true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, false);
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  /** 当前风格下该角色的站内绝对 URL（拼 baseUrl；静态图无需鉴权）。 */
  imageOf(character: AvatarPresetCharacterDto): string {
    const images = character.images;
    if (images === undefined) {
      return '';
    }
    const style = this.selectedStyle;
    let path = '';
    if (style === 'watercolor') {
      path = images.watercolor === undefined ? '' : images.watercolor;
    } else if (style === 'cartoon') {
      path = images.cartoon === undefined ? '' : images.cartoon;
    } else if (style === 'pixel') {
      path = images.pixel === undefined ? '' : images.pixel;
    } else if (style === 'papercut') {
      path = images.papercut === undefined ? '' : images.papercut;
    } else if (style === 'clay') {
      path = images.clay === undefined ? '' : images.clay;
    }
    return MediaService.publicUrl(path);
  }

  /** 当前形象图（只有预置静态图可公开加载；照片路径按隐私策略隐藏）。 */
  currentImageUrl(): string {
    const state = this.current;
    if (state === null) {
      return '';
    }
    const url = state.avatar_url;
    if (url === undefined || url === null || url.length === 0) {
      return '';
    }
    if (!MediaService.isPublicAvatarPath(url)) {
      return '';
    }
    return MediaService.publicUrl(url);
  }

  hasAvatar(): boolean {
    const state = this.current;
    if (state === null) {
      return false;
    }
    const url = state.avatar_url;
    return url !== undefined && url !== null && url.length > 0;
  }

  /** 当前形象描述（无则空串，页面不用做多层可选链）。 */
  currentDesc(): string {
    const state = this.current;
    if (state === null || state.character_desc === undefined || state.character_desc === null) {
      return '';
    }
    return state.character_desc;
  }

  currentPresetId(): string {
    const state = this.current;
    if (state === null || state.preset_id === undefined || state.preset_id === null) {
      return '';
    }
    return state.preset_id;
  }

  styleLabel(styleId: string): string {
    for (let i = 0; i < this.styles.length; i++) {
      if (this.styles[i].id === styleId) {
        const label = this.styles[i].label_zh;
        return label === undefined ? styleId : label;
      }
    }
    return styleId;
  }

  currentStyleLabel(): string {
    const state = this.current;
    if (state === null || state.style === undefined || state.style === null) {
      return '';
    }
    return this.styleLabel(state.style);
  }

  /** 按 audience + 性别过滤后的角色列表（性别未知时显示全部）。 */
  visibleCharacters(): AvatarPresetCharacterDto[] {
    const result: AvatarPresetCharacterDto[] = [];
    for (let i = 0; i < this.characters.length; i++) {
      const character = this.characters[i];
      if (character.audience !== undefined && character.audience !== this.audience) {
        continue;
      }
      if (!this.showAllGender && this.myGender.length > 0) {
        const gender = character.gender;
        const sameGender = gender !== undefined && gender === this.myGender;
        const other = gender !== undefined && gender === 'other';
        if (!sameGender && !other) {
          continue;
        }
      }
      result.push(character);
    }
    return result;
  }

  childCount(): number {
    let count = 0;
    for (let i = 0; i < this.characters.length; i++) {
      if (this.characters[i].audience === 'child') {
        count++;
      }
    }
    return count;
  }

  adultCount(): number {
    let count = 0;
    for (let i = 0; i < this.characters.length; i++) {
      if (this.characters[i].audience === 'adult') {
        count++;
      }
    }
    return count;
  }

  async selectPreset(characterId: string): Promise<boolean> {
    if (this.saving) {
      return false;
    }
    this.saving = true;
    this.hasError = false;
    this.notice = '';
    try {
      const state = await AccountService.selectAvatar(characterId, this.selectedStyle);
      this.current = state;
      this.notice = '就用这个！已立即生效 ✅';
      return true;
    } catch (err) {
      const e = err as Error;
      if (e instanceof ApiError && e.code === 'policy_disabled') {
        this.error = new UiError('', e.detail.length > 0 ? e.detail : '按隐私策略，照片生成形象已关闭', '', false,
          e.code);
      } else {
        this.error = SessionStore.toUiError(e, false);
      }
      this.hasError = true;
      return false;
    } finally {
      this.saving = false;
    }
  }

  async saveDescription(): Promise<boolean> {
    if (this.savingDesc) {
      return false;
    }
    const desc = this.descDraft.trim();
    if (desc.length === 0) {
      this.notice = '';
      this.error = new UiError('', '形象描述不能为空', '', false, ApiErrorCode.BAD_REQUEST);
      this.hasError = true;
      return false;
    }
    this.savingDesc = true;
    this.hasError = false;
    this.notice = '';
    try {
      const state = await AccountService.updateAvatarDescription(desc);
      this.current = state;
      this.notice = state.message === undefined ? '形象描述已更新' : state.message;
      return true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, false);
      this.hasError = true;
      return false;
    } finally {
      this.savingDesc = false;
    }
  }

  async clear(): Promise<boolean> {
    if (this.saving) {
      return false;
    }
    this.saving = true;
    this.hasError = false;
    this.notice = '';
    try {
      await AccountService.clearAvatar();
      this.current = null;
      this.descDraft = '';
      this.notice = '已清空虚拟形象';
      return true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, false);
      this.hasError = true;
      return false;
    } finally {
      this.saving = false;
    }
  }
}

// ===========================================================================
// 音色页（内置 9 音色 + 试听 + 保存到 settings.tts_voice）
// ===========================================================================

@Observed
export class VoicesVM {
  voices: VoiceOption[] = MediaService.voices();
  /** '' = 默认音色（provider 决定，null） */
  currentVoice: string = '';
  rate: string = 'normal';
  isChild: boolean = false;

  loading: boolean = false;
  loaded: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');

  previewingId: string = '';
  previewError: string = '';

  saving: boolean = false;
  notice: string = '';
  saveError: string = '';

  async init(isChild: boolean): Promise<void> {
    this.isChild = isChild;
    this.rate = isChild ? 'slow' : 'normal';
    await this.load();
  }

  /** 读当前偏好（tts_voice / tts_rate）用于高亮。 */
  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    try {
      const dto = await AccountService.settings();
      const prefs = dto.prefs;
      if (prefs !== undefined) {
        this.currentVoice = (prefs.ttsVoice === undefined || prefs.ttsVoice === null) ? '' : prefs.ttsVoice;
        if (prefs.ttsRate !== undefined && prefs.ttsRate.length > 0) {
          this.rate = prefs.ttsRate;
        }
      }
      this.loaded = true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, this.isChild);
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  /** 试听 / 再点一次停止。 */
  async togglePreview(voice: VoiceOption): Promise<void> {
    this.previewError = '';
    if (this.previewingId === voice.id) {
      this.previewingId = '';
      await MediaService.stopPreview();
      return;
    }
    this.previewingId = voice.id;
    try {
      await MediaService.preview(voice.id, voice.sample, this.rate, () => {
        this.previewingId = '';
      });
    } catch (err) {
      this.previewingId = '';
      this.previewError = SessionStore.toUiError(err as Error, this.isChild).message;
    }
  }

  /** 保存偏好（PATCH settings.tts_voice；'' 表示恢复默认）。 */
  async save(voiceId: string): Promise<boolean> {
    if (this.saving) {
      return false;
    }
    this.saving = true;
    this.saveError = '';
    this.notice = '';
    try {
      const body: SettingsPatchBodyDto = {};
      body.tts_voice = voiceId.length === 0 ? null : voiceId;
      await AccountService.patchSettings(body);
      this.currentVoice = voiceId;
      void AccountPrefs.reload();
      this.notice = '已保存音色偏好 ✅';
      return true;
    } catch (err) {
      const e = err as Error;
      if (e instanceof ApiError && AccountSettingsVM.isPatchUnsupported(e)) {
        this.saveError = '该设置暂不可用（当前服务器不支持保存偏好）';
      } else {
        this.saveError = SessionStore.toUiError(e, this.isChild).message;
      }
      return false;
    } finally {
      this.saving = false;
    }
  }

  labelOf(voiceId: string): string {
    if (voiceId.length === 0) {
      return '默认音色（provider 决定）';
    }
    const option = MediaService.findVoice(voiceId);
    return option === null ? voiceId : option.labelZh;
  }
}


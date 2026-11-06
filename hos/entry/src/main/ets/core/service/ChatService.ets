import { http } from '@kit.NetworkKit';
import { ApiClient, ApiRaw, ApiRequest } from '../net/ApiClient';
import { ApiError, ApiErrorCode } from '../net/ApiError';
import {
  ChatAsrDto,
  ChatAudioStatusDto,
  ChatMessageDto,
  ChatMessageListDto,
  ChatScenarioListDto,
  ChatScenarioMutationDto,
  ChatSessionDetailDto,
  ChatSessionDto,
  ChatSessionListDto,
  ChatSessionListItemDto,
  ChatTurnDto
} from '../net/ChatDtos';
import { CacheService } from './CacheService';
import { FileUtil } from '../util/FileUtil';

/**
 * `GET /:id/audio` 的结果（200/202/500 三种语义都收在这里，页面不解析 HTTP）。
 *
 * state: ready（已落盘）/ building（202，继续轮询 status）/ failed（500，带可读 message）。
 */
export class ChatAudioResult {
  state: string = 'building';
  path: string = '';
  message: string = '';
}

/**
 * 对话训练 API（§2）。
 *
 * 职责边界：只拼 URL / 转 DTO / 落盘；不持有页面状态、不弹 Toast。
 * 三步一轮（§2.5/§7.3）：
 *   ① POST /api/asr（multipart audio）→ text
 *   ② POST /api/chat/sessions/:id/turn（multipart text + audio）→ 助手文本（无音频）
 *   ③ PracticeService.fetchTtsFile(text, rate, voice, 'mp3') → 本地文件 → AudioController.play
 */
export class ChatService {
  private static readonly LIST_TIMEOUT_MS: number = 15000;
  private static readonly MUTATE_TIMEOUT_MS: number = 20000;
  private static readonly ASR_TIMEOUT_MS: number = 60000;
  /** LLM 单轮最长约 40s，给 90s */
  private static readonly TURN_TIMEOUT_MS: number = 90000;
  /** 整段回放可能几分钟（上限 900s），下载给 120s */
  private static readonly AUDIO_TIMEOUT_MS: number = 120000;
  private static readonly AUDIO_DOWNLOAD_TIMEOUT_MS: number = 60000;

  // ------------------------------------------------------------------ 场景

  /** GET /api/chat/scenarios[?include_child=1] */
  static async scenarios(includeChild: boolean): Promise<ChatScenarioListDto> {
    let query: Map<string, string> | null = null;
    if (includeChild) {
      query = new Map<string, string>();
      query.set('include_child', '1');
    }
    const raw = await ApiClient.getJson('/chat/scenarios', query, ChatService.LIST_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    const dto = ChatService.parseScenarioList(raw);
    return dto;
  }

  /**
   * 创建自定义场景（§2.3）。`audience` 为空表示交给服务端按账号定（儿童强制 child）。
   * 返回新场景 id。
   */
  static async createScenario(title: string, titleZh: string, settingZh: string, rolePrompt: string,
    openingLine: string, level: string, audience: string): Promise<string> {
    const body = ChatService.scenarioBody(title, titleZh, settingZh, rolePrompt, openingLine, level, audience);
    const raw = await ApiClient.postJson('/chat/scenarios', body, true, ChatService.MUTATE_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    const dto = ChatService.parseMutation(raw.text, raw.status);
    const id = dto.id === undefined ? '' : dto.id;
    if (id.length === 0) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '场景已提交，但没有拿到场景 ID');
    }
    return id;
  }

  /** 编辑自定义场景：rolePrompt 传空串表示「不修改」（未传字段服务端取原值）。 */
  static async updateScenario(id: string, title: string, titleZh: string, settingZh: string,
    rolePrompt: string, openingLine: string, level: string): Promise<void> {
    const body = ChatService.scenarioBody(title, titleZh, settingZh, rolePrompt, openingLine, level, '');
    const raw = await ApiClient.patchJson('/chat/scenarios/' + encodeURIComponent(id), body,
      ChatService.MUTATE_TIMEOUT_MS);
    ApiClient.requireOk(raw);
  }

  /** 删除自定义场景（仅 owner，他人 id 返回 404）。 */
  /** DELETE /chat/sessions/:id —— 删除自己的历史对话（含消息与录音缓存）。 */
  static async deleteSession(id: string): Promise<void> {
    const raw = await ApiClient.deleteJson('/chat/sessions/' + encodeURIComponent(id),
      ChatService.MUTATE_TIMEOUT_MS);
    ApiClient.requireOk(raw);
  }
  static async deleteScenario(id: string): Promise<void> {
    const raw = await ApiClient.deleteJson('/chat/scenarios/' + encodeURIComponent(id),
      ChatService.MUTATE_TIMEOUT_MS);
    ApiClient.requireOk(raw);
  }

  // ------------------------------------------------------------------ 会话

  /** POST /api/chat/sessions {scenario_id} */
  static async createSession(scenarioId: string): Promise<ChatSessionDto> {
    const body = '{"scenario_id":' + JSON.stringify(scenarioId) + '}';
    const raw = await ApiClient.postJson('/chat/sessions', body, true, ChatService.MUTATE_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    const dto = ChatService.parseSession(raw.text, raw.status);
    return dto;
  }

  /** POST /api/chat/sessions/:id/turn（multipart：text 必填 + audio 可选）。 */
  static async turn(sessionId: string, text: string, audioPath: string): Promise<ChatTurnDto> {
    const path = '/chat/sessions/' + encodeURIComponent(sessionId) + '/turn';
    let raw: ApiRaw;
    if (audioPath.length > 0) {
      const form: http.MultiFormData[] = [
        { name: 'text', contentType: 'text/plain', data: text }
      ];
      if (FileUtil.sizeOf(audioPath) > 0) {
        form.push({ name: 'audio', contentType: 'audio/mp4', filePath: audioPath, remoteFileName: 'recording.m4a' });
      }
      raw = await ApiClient.postMultipart(path, form, ChatService.TURN_TIMEOUT_MS);
    } else {
      raw = await ApiClient.postJson(path, '{"text":' + JSON.stringify(text) + '}', true,
        ChatService.TURN_TIMEOUT_MS);
    }
    ApiClient.requireOk(raw);
    const dto = ChatService.parseTurn(raw.text, raw.status);
    return dto;
  }

  /** GET /api/chat/sessions/:id/messages（唯一的 pron 来源）。 */
  static async messages(sessionId: string): Promise<ChatMessageDto[]> {
    const raw = await ApiClient.getJson('/chat/sessions/' + encodeURIComponent(sessionId) + '/messages', null,
      ChatService.LIST_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    const dto = ChatService.parseMessageList(raw.text, raw.status);
    const list = dto.messages;
    return list === undefined ? [] : list;
  }

  /** POST /api/chat/sessions/:id/end（幂等；第 4 个参数是空 body，所以用裸 request）。 */
  static async end(sessionId: string): Promise<void> {
    const req = new ApiRequest();
    req.method = http.RequestMethod.POST;
    req.path = '/chat/sessions/' + encodeURIComponent(sessionId) + '/end';
    req.timeoutMs = ChatService.MUTATE_TIMEOUT_MS;
    const raw = await ApiClient.request(req);
    ApiClient.requireOk(raw);
  }

  /** GET /api/chat/sessions/:id/audio/status（只读，绝不触发构建）。 */
  static async audioStatus(sessionId: string): Promise<ChatAudioStatusDto> {
    const raw = await ApiClient.getJson('/chat/sessions/' + encodeURIComponent(sessionId) + '/audio/status', null,
      ChatService.LIST_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    const dto = ChatService.parseAudioStatus(raw.text, raw.status);
    return dto;
  }

  /**
   * GET /api/chat/sessions/:id/audio[?force=1]：
   * 200 = 二进制 wav（落 cacheDir 后返回本地路径）；202 = 后台开始拼；500 = 失败带 message。
   */
  static async audio(sessionId: string, force: boolean): Promise<ChatAudioResult> {
    let query: Map<string, string> | null = null;
    if (force) {
      query = new Map<string, string>();
      query.set('force', '1');
    }
    const raw = await ApiClient.getBytes('/chat/sessions/' + encodeURIComponent(sessionId) + '/audio', query,
      ChatService.AUDIO_TIMEOUT_MS);
    const result = new ChatAudioResult();
    if (raw.status === 200) {
      const bytes = raw.bytes;
      if (bytes === null || bytes.length < 128) {
        throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '整段回放内容为空');
      }
      CacheService.ensureAll();
      const dest = CacheService.audioDir() + '/chat_session_' + ChatService.safeName(sessionId) + '.wav';
      FileUtil.writeBytesAtomic(dest, bytes);
      result.state = 'ready';
      result.path = dest;
      return result;
    }
    if (raw.status === 202) {
      result.state = 'building';
      return result;
    }
    const err = ApiClient.errorOf(raw);
    result.state = 'failed';
    result.message = err.detail.length > 0 ? err.detail : '整段回放暂时生成不了，可以先看文字记录';
    return result;
  }

  // ------------------------------------------------------------------ 历史

  /** GET /api/chat/sessions（最近 30 条，倒序）。 */
  static async sessions(): Promise<ChatSessionListItemDto[]> {
    const raw = await ApiClient.getJson('/chat/sessions', null, ChatService.LIST_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    const dto = ChatService.parseSessionList(raw.text, raw.status);
    const list = dto.sessions;
    return list === undefined ? [] : list;
  }

  /** GET /api/chat/sessions/:id（详情，无 pron；pron 走 /messages）。 */
  static async sessionDetail(sessionId: string): Promise<ChatSessionDetailDto> {
    const raw = await ApiClient.getJson('/chat/sessions/' + encodeURIComponent(sessionId), null,
      ChatService.LIST_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    const dto = ChatService.parseSessionDetail(raw.text, raw.status);
    return dto;
  }

  /**
   * 下载单条消息的录音（`audio_url` 形如 `/api/audio/cm_xxx`）。
   * 200 二进制；失败抛 ApiError。返回本地路径。
   */
  static async downloadMessageAudio(audioUrl: string, destPath: string): Promise<string> {
    const path = ChatService.stripApiPrefix(audioUrl);
    if (path.length === 0 || destPath.length === 0) {
      throw ApiError.local(ApiErrorCode.AUDIO_NOT_FOUND, '这条消息没有录音');
    }
    await ApiClient.download(path, destPath, ChatService.AUDIO_DOWNLOAD_TIMEOUT_MS);
    return destPath;
  }

  // ------------------------------------------------------------------ 解析

  private static parseScenarioList(raw: ApiRaw): ChatScenarioListDto {
    let dto: ChatScenarioListDto | null = null;
    try {
      dto = JSON.parse(raw.text) as ChatScenarioListDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '场景列表格式异常');
    }
    const list = dto.scenarios;
    const scenarios = list === undefined ? [] : list;
    dto.scenarios = scenarios;
    return dto;
  }

  private static parseMutation(text: string, status: number): ChatScenarioMutationDto {
    let dto: ChatScenarioMutationDto | null = null;
    try {
      dto = JSON.parse(text) as ChatScenarioMutationDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, status, '保存结果格式异常');
    }
    return dto;
  }

  private static parseSession(text: string, status: number): ChatSessionDto {
    let dto: ChatSessionDto | null = null;
    try {
      dto = JSON.parse(text) as ChatSessionDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null || typeof dto.session_id !== 'string' || dto.session_id.length === 0) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, status, '会话创建结果格式异常');
    }
    return dto;
  }

  private static parseTurn(text: string, status: number): ChatTurnDto {
    let dto: ChatTurnDto | null = null;
    try {
      dto = JSON.parse(text) as ChatTurnDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null || typeof dto.reply !== 'string') {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, status, '对话回复格式异常');
    }
    return dto;
  }

  private static parseMessageList(text: string, status: number): ChatMessageListDto {
    let dto: ChatMessageListDto | null = null;
    try {
      dto = JSON.parse(text) as ChatMessageListDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, status, '消息列表格式异常');
    }
    return dto;
  }

  private static parseAudioStatus(text: string, status: number): ChatAudioStatusDto {
    let dto: ChatAudioStatusDto | null = null;
    try {
      dto = JSON.parse(text) as ChatAudioStatusDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null || typeof dto.status !== 'string') {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, status, '回放状态格式异常');
    }
    return dto;
  }

  private static parseSessionList(text: string, status: number): ChatSessionListDto {
    let dto: ChatSessionListDto | null = null;
    try {
      dto = JSON.parse(text) as ChatSessionListDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, status, '历史列表格式异常');
    }
    return dto;
  }

  private static parseSessionDetail(text: string, status: number): ChatSessionDetailDto {
    let dto: ChatSessionDetailDto | null = null;
    try {
      dto = JSON.parse(text) as ChatSessionDetailDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, status, '会话详情格式异常');
    }
    return dto;
  }

  // ------------------------------------------------------------------ 内部工具

  /** ASR：`POST /api/asr`（multipart audio，`language` 可选）。返回文本（可能为空 = 没听清）。 */
  static async asr(filePath: string, language: string): Promise<string> {
    if (FileUtil.sizeOf(filePath) <= 0) {
      throw ApiError.local(ApiErrorCode.RECORD_FAILED, '录音文件为空，请重试');
    }
    let query: Map<string, string> | null = null;
    if (language.length > 0) {
      query = new Map<string, string>();
      query.set('language', language);
    }
    const form: http.MultiFormData[] = [
      { name: 'audio', contentType: 'audio/mp4', filePath: filePath, remoteFileName: 'recording.m4a' }
    ];
    const raw = await ApiClient.postMultipartWithQuery('/asr', query, form, ChatService.ASR_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    let dto: ChatAsrDto | null = null;
    try {
      dto = JSON.parse(raw.text) as ChatAsrDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '语音识别结果格式异常');
    }
    if (dto.text !== undefined) {
      return dto.text;
    }
    if (dto.transcript !== undefined) {
      return dto.transcript;
    }
    return '';
  }

  /** 创建/编辑场景的 JSON body：空字符串字段不出现在 body 里（PATCH = 未传取原值）。 */
  private static scenarioBody(title: string, titleZh: string, settingZh: string, rolePrompt: string,
    openingLine: string, level: string, audience: string): string {
    const parts: string[] = [];
    if (title.length > 0) {
      parts.push('"title":' + JSON.stringify(title));
    }
    if (titleZh.length > 0) {
      parts.push('"title_zh":' + JSON.stringify(titleZh));
    }
    if (settingZh.length > 0) {
      parts.push('"setting_zh":' + JSON.stringify(settingZh));
    }
    if (rolePrompt.length > 0) {
      parts.push('"role_prompt":' + JSON.stringify(rolePrompt));
    }
    if (openingLine.length > 0) {
      parts.push('"opening_line":' + JSON.stringify(openingLine));
    }
    if (level.length > 0) {
      parts.push('"level":' + JSON.stringify(level));
    }
    if (audience.length > 0) {
      parts.push('"audience":' + JSON.stringify(audience));
    }
    return '{' + parts.join(',') + '}';
  }

  private static stripApiPrefix(url: string): string {
    if (url.length === 0) {
      return '';
    }
    if (url.startsWith('/api/')) {
      return url.substring(4);
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      const idx = url.indexOf('/api/');
      if (idx >= 0) {
        return url.substring(idx + 4);
      }
      return '';
    }
    return url;
  }

  /** 会话 id 只含安全字符（cs_xxx）；仍做一次过滤，避免拼出奇怪的缓存文件名。 */
  private static safeName(id: string): string {
    let out = '';
    for (let i = 0; i < id.length && i < 64; i++) {
      const ch = id.charAt(i);
      if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') ||
        ch === '_' || ch === '-') {
        out = out + ch;
      }
    }
    return out.length === 0 ? 'session' : out;
  }
}

import { http } from '@kit.NetworkKit';
import { ApiClient, ApiRequest } from '../net/ApiClient';
import { ApiError, ApiErrorCode } from '../net/ApiError';
import { AttemptItemDto, AttemptListDto, AttemptResponseDto, HealthDto, SentenceDto, SentenceListDto } from '../net/Dtos';
import { CacheService } from './CacheService';
import { FileUtil } from '../util/FileUtil';

/**
 * 跟读相关 API：语料、TTS、评测、健康检查。
 * 职责边界：只拼 URL / 转 DTO / 落盘；不持有页面状态、不弹 Toast（docs/architecture.md §2）。
 */
export class PracticeService {
  private static readonly SENTENCES_TIMEOUT_MS: number = 15000;
  private static readonly TTS_TIMEOUT_MS: number = 30000;
  /** 同步评测最长约 100s（pronounce 60s + feedback 40s），客户端给 120s */
  private static readonly ATTEMPT_TIMEOUT_MS: number = 120000;
  private static readonly HEALTH_TIMEOUT_MS: number = 5000;

  /** GET /api/sentences?level=A1[&focus=<音素>] */
  static async sentences(level: string, focus: string = ''): Promise<SentenceDto[]> {
    const query = new Map<string, string>();
    if (level.length > 0) {
      query.set('level', level);
    }
    if (focus.length > 0) {
      query.set('focus', focus);
    }
    const raw = await ApiClient.getJson('/sentences', query, PracticeService.SENTENCES_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    let dto: SentenceListDto | null = null;
    try {
      dto = JSON.parse(raw.text) as SentenceListDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '语料返回格式异常');
    }
    const list = dto.sentences;
    return list === undefined ? [] : list;
  }

  /**
   * POST /api/tts → 二进制音频 → 落 cacheDir/tts。
   * 返回本地文件路径（交给 AVPlayer 用 `fd://` 播放）。
   *
   * 注意：失败时服务端返回的是 JSON 错误体而不是音频，所以这里必须
   * 「先看 HTTP 状态，再决定写文件」——不能无条件把字节落盘。
   */
  static async fetchTts(text: string, rate: string): Promise<string> {
    return PracticeService.fetchTtsFile(text, rate, '', 'wav');
  }

  /** 可指定音色/容器（对话用 mp3，音色试听用 voice）。 */
  static async fetchTtsFile(text: string, rate: string, voice: string, format: string): Promise<string> {
    let body = '{"text":' + JSON.stringify(text) + ',"rate":' + JSON.stringify(rate) +
      ',"format":' + JSON.stringify(format);
    if (voice.length > 0) {
      body = body + ',"voice":' + JSON.stringify(voice);
    }
    body = body + '}';
    const raw = await ApiClient.postJsonForBytes('/tts', body, PracticeService.TTS_TIMEOUT_MS);
    if (raw.status !== 200) {
      throw ApiClient.errorOf(raw);
    }
    const bytes = raw.bytes;
    if (bytes === null || bytes.length < 64) {
      throw new ApiError(ApiErrorCode.CACHE_CORRUPT, 0, '示范音内容为空');
    }
    CacheService.ensureAll();
    const ext = PracticeService.audioExtension(bytes);
    const path = CacheService.ttsDir() + '/tts_' + Date.now() + '_' +
      Math.floor(Math.random() * 1000000).toString() + '.' + ext;
    FileUtil.writeBytesAtomic(path, bytes);
    return path;
  }

  /** GET /api/attempts?limit=N —— 我的评测记录（单句历史/进步曲线的替代数据源）。 */
  static async attempts(limit: number): Promise<AttemptItemDto[]> {
    const query = new Map<string, string>();
    query.set('limit', limit.toString());
    const raw = await ApiClient.getJson('/attempts', query, PracticeService.SENTENCES_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    let dto: AttemptListDto | null = null;
    try {
      dto = JSON.parse(raw.text) as AttemptListDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '评测记录格式异常');
    }
    const list = dto.attempts;
    return list === undefined ? [] : list;
  }

  /** GET /api/audio/:id → 落盘，返回本地路径（录音回放）。 */
  static async downloadAudio(audioId: string, destPath: string): Promise<string> {
    await ApiClient.download('/audio/' + encodeURIComponent(audioId), destPath, PracticeService.TTS_TIMEOUT_MS);
    return destPath;
  }

  /** POST /api/warmup（fire-and-forget，失败不展示）。 */
  static warmup(texts: string[], rate: string): void {
    if (texts.length === 0) {
      return;
    }
    const parts: string[] = [];
    for (let i = 0; i < texts.length && i < 12; i++) {
      parts.push(JSON.stringify(texts[i]));
    }
    const body = '{"texts":[' + parts.join(',') + '],"rate":' + JSON.stringify(rate) + '}';
    const req = new ApiRequest();
    req.method = http.RequestMethod.POST;
    req.path = '/warmup';
    req.jsonBody = body;
    req.timeoutMs = 30000;
    ApiClient.request(req).catch(() => {
      // 预热失败静默
    });
  }

  /**
   * POST /api/attempts（multipart，同步）。
   * 字段名严格按契约：audio / sentence_id / reference_text / mode / duration_ms。
   */
  static async evaluate(filePath: string, sentenceId: string, referenceText: string,
    durationMs: number, blindTestId: string = ''): Promise<AttemptResponseDto> {
    const size = FileUtil.sizeOf(filePath);
    if (size <= 0) {
      throw new ApiError(ApiErrorCode.RECORD_FAILED, 0, '录音文件为空');
    }
    if (size > 12 * 1024 * 1024) {
      throw new ApiError(ApiErrorCode.RECORD_TOO_LARGE, 0, '录音超过 12MB');
    }
    const form: http.MultiFormData[] = [
      {
        name: 'audio',
        contentType: 'audio/mp4',
        filePath: filePath,
        remoteFileName: 'recording.m4a'
      },
      {
        name: 'sentence_id',
        contentType: 'text/plain',
        data: sentenceId
      },
      {
        name: 'reference_text',
        contentType: 'text/plain',
        data: referenceText
      },
      {
        name: 'mode',
        contentType: 'text/plain',
        data: 'scripted'
      },
      {
        name: 'duration_ms',
        contentType: 'text/plain',
        data: durationMs.toString()
      }
    ];
    if (blindTestId.length > 0) {
      form.push({ name: 'blind_test_id', contentType: 'text/plain', data: blindTestId });
    }
    const raw = await ApiClient.postMultipart('/attempts', form, PracticeService.ATTEMPT_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    return PracticeService.parseAttempt(raw.text, raw.status);
  }

  /** POST /api/attempts/:id/retry —— 用已存录音重评（degraded 时用，不重新上传）。 */
  static async retryAttempt(attemptId: string): Promise<AttemptResponseDto> {
    const req = new ApiRequest();
    req.method = http.RequestMethod.POST;
    req.path = '/attempts/' + encodeURIComponent(attemptId) + '/retry';
    req.timeoutMs = PracticeService.ATTEMPT_TIMEOUT_MS;
    const raw = await ApiClient.request(req);
    ApiClient.requireOk(raw);
    return PracticeService.parseAttempt(raw.text, raw.status);
  }

  /** GET /api/health（无需登录） */
  static async health(): Promise<HealthDto> {
    const req = new ApiRequest();
    req.method = http.RequestMethod.GET;
    req.path = '/health';
    req.auth = false;
    req.retryOn401 = false;
    req.timeoutMs = PracticeService.HEALTH_TIMEOUT_MS;
    const raw = await ApiClient.request(req);
    ApiClient.requireOk(raw);
    let dto: HealthDto | null = null;
    try {
      dto = JSON.parse(raw.text) as HealthDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '健康检查返回格式异常');
    }
    return dto;
  }

  private static parseAttempt(text: string, status: number): AttemptResponseDto {
    let dto: AttemptResponseDto | null = null;
    try {
      dto = JSON.parse(text) as AttemptResponseDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null || typeof dto.attempt_id !== 'string') {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, status, '评测结果格式异常');
    }
    return dto;
  }

  /** 按魔数判断容器（TTS 可能是 wav 或 mp3；不依赖响应头）。 */
  private static audioExtension(bytes: Uint8Array): string {
    if (bytes.length >= 4) {
      if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46) {
        return 'wav';
      }
      if (bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) {
        return 'mp3';
      }
      if (bytes[0] === 0xff && (bytes[1] === 0xfb || bytes[1] === 0xf3 || bytes[1] === 0xf2)) {
        return 'mp3';
      }
    }
    if (bytes.length >= 12) {
      if (bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70) {
        return 'm4a';
      }
    }
    return 'wav';
  }
}

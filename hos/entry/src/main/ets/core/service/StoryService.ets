import { http } from '@kit.NetworkKit';
import { ApiClient, ApiRequest } from '../net/ApiClient';
import { ApiError, ApiErrorCode } from '../net/ApiError';
import {
  StoryAsrDto,
  StoryAudioStatusDto,
  StoryIllustrateBodyDto,
  StoryIllustrationDto,
  StoryMaterialCreateDto,
  StoryMaterialCreatedDto,
  StoryMaterialDto,
  StoryMaterialListDto,
  StoryRetellBodyDto,
  StoryRetellDto,
  StoryRewriteBodyDto,
  StoryRewriteDto
} from '../net/StoryDtos';
import { FileUtil } from '../util/FileUtil';

/**
 * 故事模式 API（.specs/chat-story.md §3）。
 *
 * 职责边界：只拼 URL / 上传 / 解析 / 落盘，不持有页面状态、不弹 Toast。
 *
 * 线上降级（2026-11-03 实测）：
 * - `POST /api/story/recordings` 是 404，所以录音转写一律走 `POST /api/asr?language=zh-CN`；
 * - 复述 = 两步：先 `POST /api/asr?language=en-US` 拿 transcript，再 `POST /api/story/retell`。
 */
export class StoryService {
  private static readonly LIST_TIMEOUT_MS: number = 20000;
  private static readonly DETAIL_TIMEOUT_MS: number = 20000;
  /** ASR 可能 60s+；给 120s */
  private static readonly ASR_TIMEOUT_MS: number = 120000;
  private static readonly REWRITE_TIMEOUT_MS: number = 120000;
  private static readonly RETELL_TIMEOUT_MS: number = 120000;
  /** 生图很慢（10–30s），留足余量 */
  private static readonly ILLUSTRATE_TIMEOUT_MS: number = 180000;
  private static readonly SAVE_TIMEOUT_MS: number = 30000;
  private static readonly AUDIO_STATUS_TIMEOUT_MS: number = 15000;
  private static readonly AUDIO_TIMEOUT_MS: number = 120000;

  // ------------------------------------------------------------------ 故事集

  /** GET /api/materials?kind=story&limit=N&offset=M（家庭共享，服务端已排序） */
  static async materials(limit: number, offset: number): Promise<StoryMaterialDto[]> {
    const query = new Map<string, string>();
    query.set('kind', 'story');
    query.set('limit', limit.toString());
    query.set('offset', offset.toString());
    const raw = await ApiClient.getJson('/materials', query, StoryService.LIST_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    let dto: StoryMaterialListDto | null = null;
    try {
      dto = JSON.parse(raw.text) as StoryMaterialListDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '故事列表返回格式异常');
    }
    const items = dto.items;
    return items === undefined ? [] : items;
  }

  /** GET /api/materials/:id */
  static async materialDetail(id: string): Promise<StoryMaterialDto> {
    const raw = await ApiClient.getJson('/materials/' + encodeURIComponent(id), null,
      StoryService.DETAIL_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    let dto: StoryMaterialDto | null = null;
    try {
      dto = JSON.parse(raw.text) as StoryMaterialDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null || typeof dto.id !== 'string' || dto.id.length === 0) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '故事详情返回格式异常');
    }
    return dto;
  }

  /** POST /api/materials（kind=story） */
  static async createMaterial(title: string, text: string, sourceZh: string,
    level: string): Promise<StoryMaterialCreatedDto> {
    const body: StoryMaterialCreateDto = {
      title: title,
      text: text,
      kind: 'story',
      source_zh: sourceZh,
      level: level,
      source: 'text'
    };
    const raw = await ApiClient.postJson('/materials', JSON.stringify(body), true,
      StoryService.SAVE_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    let dto: StoryMaterialCreatedDto | null = null;
    try {
      dto = JSON.parse(raw.text) as StoryMaterialCreatedDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null || typeof dto.id !== 'string' || dto.id.length === 0) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '故事保存返回格式异常');
    }
    return dto;
  }

  /** PATCH /materials/:id —— 只改标题（故事集里常用；服务端校验只能改自己录入的）。 */
  static async renameMaterial(id: string, title: string): Promise<void> {
    const body = '{"title":' + JSON.stringify(title) + '}';
    const raw = await ApiClient.patchJson('/materials/' + encodeURIComponent(id), body,
      StoryService.SAVE_TIMEOUT_MS);
    ApiClient.requireOk(raw);
  }

  /** DELETE /materials/:id —— 删除故事（服务端校验只能删自己录入的）。 */
  static async deleteMaterial(id: string): Promise<void> {
    const raw = await ApiClient.deleteJson('/materials/' + encodeURIComponent(id),
      StoryService.SAVE_TIMEOUT_MS);
    ApiClient.requireOk(raw);
  }

  // ------------------------------------------------------------------ 转录 / 改写 / 复述

  /**
   * POST /api/asr?language=xx（multipart，字段名 audio）。
   * 故事录音降级路径：中文用 zh-CN，复述用 en-US。
   */
  static async asr(filePath: string, language: string): Promise<string> {
    const size = FileUtil.sizeOf(filePath);
    if (size <= 0) {
      throw ApiError.local(ApiErrorCode.RECORD_FAILED, '录音文件为空');
    }
    if (size > 25 * 1024 * 1024) {
      throw ApiError.local(ApiErrorCode.RECORD_TOO_LARGE, '录音超过 25MB');
    }
    const query = new Map<string, string>();
    query.set('language', language);
    const form: http.MultiFormData[] = [
      {
        name: 'audio',
        contentType: 'audio/mp4',
        filePath: filePath,
        remoteFileName: 'story.m4a'
      }
    ];
    const raw = await ApiClient.postMultipartWithQuery('/asr', query, form, StoryService.ASR_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    let dto: StoryAsrDto | null = null;
    try {
      dto = JSON.parse(raw.text) as StoryAsrDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '语音识别返回格式异常');
    }
    const text = dto.text === undefined ? '' : dto.text.trim();
    if (text.length === 0) {
      const providerError = dto.error;
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status,
        (providerError !== undefined && providerError !== null && providerError.length > 0)
          ? providerError
          : '没有听清，再说一次吧');
    }
    return text;
  }

  /** POST /api/story/rewrite（中文 → 分级英文） */
  static async rewrite(textZh: string, level: string, maxSentences: number): Promise<StoryRewriteDto> {
    const body: StoryRewriteBodyDto = {
      text_zh: textZh,
      level: level,
      max_sentences: maxSentences,
      use_weak_phonemes: false,
      tense: 'auto'
    };
    const raw = await ApiClient.postJson('/story/rewrite', JSON.stringify(body), true,
      StoryService.REWRITE_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    let dto: StoryRewriteDto | null = null;
    try {
      dto = JSON.parse(raw.text) as StoryRewriteDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '故事改写返回格式异常');
    }
    const sentences = dto.sentences;
    const textEn = dto.text_en;
    const hasSentences = sentences !== undefined && sentences.length > 0;
    const hasText = textEn !== undefined && textEn.trim().length > 0;
    if (!hasSentences && !hasText) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '故事改写结果为空，请重试');
    }
    return dto;
  }

  /** POST /api/story/retell（不评发音分） */
  static async retell(materialId: string, storySentences: string[], transcript: string,
    level: string): Promise<StoryRetellDto> {
    const body: StoryRetellBodyDto = {
      story_sentences: storySentences,
      transcript: transcript,
      level: level
    };
    if (materialId.length > 0) {
      body.material_id = materialId;
    }
    const raw = await ApiClient.postJson('/story/retell', JSON.stringify(body), true,
      StoryService.RETELL_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    let dto: StoryRetellDto | null = null;
    try {
      dto = JSON.parse(raw.text) as StoryRetellDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '复述结果返回格式异常');
    }
    return dto;
  }

  // ------------------------------------------------------------------ 插画

  /** POST /api/story/:id/illustrate[?force=1]（返回 prompt_used） */
  static async illustrate(id: string, force: boolean): Promise<StoryIllustrationDto> {
    const body: StoryIllustrateBodyDto = { force: force, style: 'watercolor' };
    const query = new Map<string, string>();
    if (force) {
      query.set('force', '1');
    }
    // ApiClient 没有「POST + query + JSON」的快捷方法，这里直接组装请求（不改 ApiClient）。
    const req = new ApiRequest();
    req.method = http.RequestMethod.POST;
    req.path = '/story/' + encodeURIComponent(id) + '/illustrate';
    req.query = query;
    req.jsonBody = JSON.stringify(body);
    req.timeoutMs = StoryService.ILLUSTRATE_TIMEOUT_MS;
    const raw = await ApiClient.request(req);
    ApiClient.requireOk(raw);
    let dto: StoryIllustrationDto | null = null;
    try {
      dto = JSON.parse(raw.text) as StoryIllustrationDto;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '插画返回格式异常');
    }
    return dto;
  }

  // ------------------------------------------------------------------ 整段朗读回放

  /**
   * GET /api/story/:id/audio/status（只读，绝不触发构建）。
   * 404（no_audio）不抛错，转成 `status:'no_audio'` 交给 UI 隐藏播放器。
   */
  static async audioStatus(id: string): Promise<StoryAudioStatusDto> {
    const raw = await ApiClient.getJson('/story/' + encodeURIComponent(id) + '/audio/status', null,
      StoryService.AUDIO_STATUS_TIMEOUT_MS);
    if (raw.status === 200) {
      let dto: StoryAudioStatusDto | null = null;
      try {
        dto = JSON.parse(raw.text) as StoryAudioStatusDto;
      } catch (err) {
        dto = null;
      }
      if (dto === null) {
        throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '整段回放状态返回格式异常');
      }
      const status = dto.status;
      if (status === undefined || status.length === 0) {
        dto.status = 'building';
      }
      return dto;
    }
    if (raw.status === 404) {
      const error = ApiClient.errorOf(raw);
      const dto: StoryAudioStatusDto = {
        status: 'no_audio',
        error: error.detail.length > 0 ? error.detail : '这个故事还没有可回放的朗读录音'
      };
      return dto;
    }
    throw ApiClient.errorOf(raw);
  }

  /**
   * GET /api/story/:id/audio[?force=1]。
   * 200 → 落盘返回 true；202 → 还在构建返回 false（交给页面继续轮询 status）。
   */
  static async downloadStoryAudio(id: string, destPath: string, force: boolean): Promise<boolean> {
    const query = new Map<string, string>();
    if (force) {
      query.set('force', '1');
    }
    const raw = await ApiClient.getBytes('/story/' + encodeURIComponent(id) + '/audio', query,
      StoryService.AUDIO_TIMEOUT_MS);
    if (raw.status === 202) {
      return false;
    }
    ApiClient.requireOk(raw);
    const bytes = raw.bytes;
    if (bytes === null || bytes.length < 64) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '整段朗读音频为空');
    }
    FileUtil.writeBytesAtomic(destPath, bytes);
    return true;
  }

  // ------------------------------------------------------------------ 图片下载

  /** 下载材料图片到本地（Image 组件只能加载本地/公开 URL，带 Bearer 的图片要先落盘）。 */
  static async downloadMaterialImage(materialId: string, destPath: string): Promise<void> {
    const raw = await ApiClient.getBytes('/materials/' + encodeURIComponent(materialId) + '/image', null,
      StoryService.DETAIL_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    const bytes = raw.bytes;
    if (bytes === null || bytes.length < 32) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '图片内容为空');
    }
    FileUtil.writeBytesAtomic(destPath, bytes);
  }

  /** 按服务端给的 image_url（形如 `/api/materials/:id/image`）下载；失败抛 ApiError。 */
  static async downloadImageUrl(imageUrl: string, destPath: string): Promise<void> {
    const path = StoryService.apiPath(imageUrl);
    const raw = await ApiClient.getBytes(path, null, StoryService.DETAIL_TIMEOUT_MS);
    ApiClient.requireOk(raw);
    const bytes = raw.bytes;
    if (bytes === null || bytes.length < 32) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, raw.status, '图片内容为空');
    }
    FileUtil.writeBytesAtomic(destPath, bytes);
  }

  /** 站内绝对路径（可能带 `/api` 前缀）→ ApiClient 需要的「不含 /api」路径。 */
  private static apiPath(url: string): string {
    const index = url.indexOf('/api/');
    if (index >= 0) {
      return url.substring(index + 4);
    }
    if (url.startsWith('/api')) {
      return url.substring(4);
    }
    return url;
  }
}

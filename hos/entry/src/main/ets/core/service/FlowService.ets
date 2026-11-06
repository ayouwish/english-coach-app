import { http } from '@kit.NetworkKit';
import { ApiClient, ApiRaw } from '../net/ApiClient';
import { ApiError, ApiErrorCode } from '../net/ApiError';
import {
  AsyncStatusDto,
  AsyncStatusItemDto,
  AsyncSubmitDto,
  MaterialDetailDto,
  MaterialDto,
  MaterialListDto,
  OcrResultDto
} from '../net/Dtos';
import { FlowDiagnosisDto } from '../net/FlowDtos';
import { FileUtil } from '../util/FileUtil';

/**
 * 连读模式（/flow）：书页材料、拍照识别、异步评分、轮询、批次诊断。
 *
 * 职责边界：只拼 URL / 转 DTO / 落盘；不持有页面状态、不弹 Toast。
 * 后端实况（2026-11-03 线上）：`/materials`、`/ocr`、`/attempts/async`、`/attempts/status` 存在；
 * `/practice/cursor` 与 `/sentences/:id/attempts` **不存在**，这里不调用。
 */
export class FlowService {
  /** 普通 JSON 请求（列表/详情/状态/诊断） */
  private static readonly SHORT: number = 15000;
  /** 上传录音（12MB）与提交异步评分 */
  private static readonly UPLOAD: number = 60000;
  /** OCR 首次识别可能 1–2s，给足 60s */
  private static readonly OCR_TIMEOUT: number = 60000;
  /** 诊断 batch 最多 20 个 id（服务端硬限制） */
  private static readonly BATCH_MAX: number = 20;

  /** GET /materials?kind=page —— 家庭共享的「我的书页」 */
  static async materialsPage(limit: number): Promise<MaterialDto[]> {
    const query = new Map<string, string>();
    query.set('kind', 'page');
    query.set('limit', limit.toString());
    const raw = await ApiClient.getJson('/materials', query, FlowService.SHORT);
    ApiClient.requireOk(raw);
    const dto = FlowService.parse<MaterialListDto>(raw.text, raw.status, '书页列表格式异常');
    const items = dto.items;
    return items === undefined ? [] : items;
  }

  /** GET /materials/:id —— 书页详情（含 text） */
  static async materialDetail(id: string): Promise<MaterialDetailDto> {
    const raw = await ApiClient.getJson('/materials/' + encodeURIComponent(id), null, FlowService.SHORT);
    ApiClient.requireOk(raw);
    return FlowService.parse<MaterialDetailDto>(raw.text, raw.status, '书页详情格式异常');
  }

  /**
   * POST /materials {title,text,kind:page,source:text} → 201 新建书页摘要。
   * 连读这里只存文字（OCR 的图片不落库；识别结果已在客户端转成文字）。
   */
  static async createPage(title: string, text: string): Promise<MaterialDto> {
    const body = '{"title":' + JSON.stringify(title) + ',"text":' + JSON.stringify(text) +
      ',"kind":"page","source":"text"}';
    const raw = await ApiClient.postJson('/materials', body, true, FlowService.SHORT);
    ApiClient.requireOk(raw);
    return FlowService.parse<MaterialDto>(raw.text, raw.status, '保存书页返回格式异常');
  }

  /** POST /materials 的兼容入口（旧调用方不关心返回的书页 id）。 */
  static async savePage(title: string, text: string): Promise<void> {
    await FlowService.createPage(title, text);
  }

  /** PATCH /materials/:id —— 重命名 / 改文本。 */
  static async updatePage(id: string, title: string, text: string): Promise<void> {
    const body = '{"title":' + JSON.stringify(title) + ',"text":' + JSON.stringify(text) + '}';
    const raw = await ApiClient.patchJson('/materials/' + encodeURIComponent(id), body, FlowService.SHORT);
    ApiClient.requireOk(raw);
  }

  /** DELETE /materials/:id —— 删除书页（服务端校验只能删自己录入的）。 */
  static async deletePage(id: string): Promise<void> {
    const raw = await ApiClient.deleteJson('/materials/' + encodeURIComponent(id), FlowService.SHORT);
    ApiClient.requireOk(raw);
  }

  /** POST /ocr（multipart image）→ 识别书页文字 */
  static async ocr(imagePath: string): Promise<OcrResultDto> {
    const size = FileUtil.sizeOf(imagePath);
    if (size <= 0) {
      throw ApiError.local(ApiErrorCode.BAD_REQUEST, '图片文件为空');
    }
    const contentType = FlowService.imageContentType(imagePath);
    const form: http.MultiFormData[] = [
      { name: 'image', contentType: contentType, filePath: imagePath, remoteFileName: FlowService.imageFileName(imagePath) }
    ];
    const raw = await ApiClient.postMultipart('/ocr', form, FlowService.OCR_TIMEOUT);
    ApiClient.requireOk(raw);
    return FlowService.parse<OcrResultDto>(raw.text, raw.status, '识别结果格式异常');
  }

  /**
   * POST /attempts/async —— 录完即走（multipart）。
   * 字段：audio / reference_text / mode=scripted / duration_ms / source / sentence_id? / material_id?
   */
  static async submitAsync(filePath: string, referenceText: string, sentenceId: string,
    source: string, materialId: string, durationMs: number): Promise<AsyncSubmitDto> {
    const size = FileUtil.sizeOf(filePath);
    if (size <= 0) {
      throw ApiError.local(ApiErrorCode.RECORD_FAILED, '录音文件为空');
    }
    if (size > 12 * 1024 * 1024) {
      throw ApiError.local(ApiErrorCode.RECORD_TOO_LARGE, '录音超过 12MB');
    }
    const form: http.MultiFormData[] = [
      { name: 'audio', contentType: 'audio/mp4', filePath: filePath, remoteFileName: 'recording.m4a' },
      { name: 'reference_text', contentType: 'text/plain', data: referenceText },
      { name: 'mode', contentType: 'text/plain', data: 'scripted' },
      { name: 'duration_ms', contentType: 'text/plain', data: durationMs.toString() },
      { name: 'source', contentType: 'text/plain', data: source }
    ];
    if (sentenceId.length > 0) {
      form.push({ name: 'sentence_id', contentType: 'text/plain', data: sentenceId });
    }
    if (materialId.length > 0) {
      form.push({ name: 'material_id', contentType: 'text/plain', data: materialId });
    }
    const raw = await ApiClient.postMultipart('/attempts/async', form, FlowService.UPLOAD);
    ApiClient.requireOk(raw);
    return FlowService.parse<AsyncSubmitDto>(raw.text, raw.status, '提交评分返回格式异常');
  }

  /** GET /attempts/status?ids=a,b,c —— 最多 50 个 id */
  static async status(ids: string[]): Promise<AsyncStatusItemDto[]> {
    if (ids.length === 0) {
      return [];
    }
    const limited: string[] = [];
    for (let i = 0; i < ids.length && i < 50; i++) {
      limited.push(ids[i]);
    }
    const query = new Map<string, string>();
    query.set('ids', limited.join(','));
    const raw = await ApiClient.getJson('/attempts/status', query, FlowService.SHORT);
    ApiClient.requireOk(raw);
    const dto = FlowService.parse<AsyncStatusDto>(raw.text, raw.status, '评分状态格式异常');
    const items = dto.items;
    return items === undefined ? [] : items;
  }

  /** GET /diagnosis?scope=batch&attempt_ids=... —— 连读汇总页「这一批的问题」（≤20） */
  static async diagnosisBatch(attemptIds: string[]): Promise<FlowDiagnosisDto> {
    const limited: string[] = [];
    for (let i = 0; i < attemptIds.length && i < FlowService.BATCH_MAX; i++) {
      limited.push(attemptIds[i]);
    }
    const query = new Map<string, string>();
    query.set('scope', 'batch');
    query.set('attempt_ids', limited.join(','));
    const raw = await ApiClient.getJson('/diagnosis', query, FlowService.SHORT);
    ApiClient.requireOk(raw);
    return FlowService.parse<FlowDiagnosisDto>(raw.text, raw.status, '诊断返回格式异常');
  }

  static parse<T>(text: string, status: number, message: string): T {
    let dto: T | null = null;
    try {
      dto = JSON.parse(text) as T;
    } catch (err) {
      dto = null;
    }
    if (dto === null) {
      throw new ApiError(ApiErrorCode.BAD_RESPONSE, status, message);
    }
    return dto;
  }

  /** 服务端按文件头二次校验，但仍显式给正确的 Content-Type（HEIC 由 health.capabilities.heic 决定能否解）。 */
  private static imageContentType(path: string): string {
    const lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.heic')) {
      return 'image/heic';
    }
    if (lower.endsWith('.heif')) {
      return 'image/heif';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  private static imageFileName(path: string): string {
    const lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'page.png';
    }
    if (lower.endsWith('.heic')) {
      return 'page.heic';
    }
    if (lower.endsWith('.heif')) {
      return 'page.heif';
    }
    if (lower.endsWith('.webp')) {
      return 'page.webp';
    }
    return 'page.jpg';
  }
}

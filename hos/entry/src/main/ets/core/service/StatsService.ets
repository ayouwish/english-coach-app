import { http } from '@kit.NetworkKit';
import { ApiClient, ApiRequest } from '../net/ApiClient';
import { ApiError, ApiErrorCode } from '../net/ApiError';
import {
  BlindFinishDto,
  BlindTestListDto,
  BlindTestStartDto,
  DiagnosisResponseDto,
  HealthFullDto,
  ReviewGradeBodyDto,
  ReviewGradeResultDto,
  ReviewResponseDto
} from '../net/StatsDtos';

/**
 * 统计类 API：发音诊断（4 个 scope）、错音本 SRS、盲测、健康检查全字段。
 *
 * 职责边界（docs/architecture.md §2）：只拼 URL / 转 DTO，不持有页面状态、不弹 Toast。
 * 证据来源：`.specs/practice-flow.md` §2.14–§2.16、`.specs/account-misc.md` §7。
 */
export class StatsService {
  private static readonly SHORT: number = 15000;
  private static readonly POST_TIMEOUT: number = 30000;
  private static readonly HEALTH_TIMEOUT: number = 5000;

  /**
   * GET /diagnosis。
   * - scope=recent 时需要 days（默认 7，上限 365）；
   * - scope=batch 时需要 attempt_ids（≤20，服务端超限会 400 invalid_scope）；
   * - scope=attempt 时需要 attempt_id（本页不用，但接口保留）。
   */
  static async diagnosis(scope: string, days: number, attemptIds: string[]): Promise<DiagnosisResponseDto> {
    const query = new Map<string, string>();
    query.set('scope', scope);
    if (scope === 'recent') {
      let window = Math.round(days);
      if (window < 1) {
        window = 7;
      }
      if (window > 365) {
        window = 365;
      }
      query.set('days', window.toString());
    }
    if (scope === 'batch') {
      const limited: string[] = [];
      for (let i = 0; i < attemptIds.length && i < 20; i++) {
        limited.push(attemptIds[i]);
      }
      if (limited.length === 0) {
        throw ApiError.local(ApiErrorCode.BAD_REQUEST, '缺少评测记录，无法做本批诊断');
      }
      query.set('attempt_ids', limited.join(','));
    }
    const raw = await ApiClient.getJson('/diagnosis', query, StatsService.SHORT);
    ApiClient.requireOk(raw);
    return StatsService.parse<DiagnosisResponseDto>(raw.text, raw.status, '诊断报告格式异常');
  }

  /** GET /review?limit=N（N 上限 50，默认 20）。 */
  static async review(limit: number): Promise<ReviewResponseDto> {
    let count = Math.round(limit);
    if (count < 1) {
      count = 20;
    }
    if (count > 50) {
      count = 50;
    }
    const query = new Map<string, string>();
    query.set('limit', count.toString());
    const raw = await ApiClient.getJson('/review', query, StatsService.SHORT);
    ApiClient.requireOk(raw);
    return StatsService.parse<ReviewResponseDto>(raw.text, raw.status, '错音本格式异常');
  }

  /** POST /review {card_id, grade} —— grade ∈ again | hard | good | easy。 */
  static async gradeReview(cardId: string, grade: string): Promise<ReviewGradeResultDto> {
    const body: ReviewGradeBodyDto = { card_id: cardId, grade: grade };
    const raw = await ApiClient.postJson('/review', JSON.stringify(body), true, StatsService.POST_TIMEOUT);
    ApiClient.requireOk(raw);
    return StatsService.parse<ReviewGradeResultDto>(raw.text, raw.status, '评分结果格式异常');
  }

  /** GET /blind-tests[?user_id=] —— 家长可看孩子；儿童带别人 id 会 403。 */
  static async blindTests(userId: string): Promise<BlindTestListDto> {
    let query: Map<string, string> | null = null;
    if (userId.length > 0) {
      query = new Map<string, string>();
      query.set('user_id', userId);
    }
    const raw = await ApiClient.getJson('/blind-tests', query, StatsService.SHORT);
    ApiClient.requireOk(raw);
    return StatsService.parse<BlindTestListDto>(raw.text, raw.status, '盲测列表格式异常');
  }

  /** POST /blind-tests（空 body；已有进行中的批次会直接返回它，resumed=true）。 */
  static async startBlindTest(): Promise<BlindTestStartDto> {
    const raw = await ApiClient.postJson('/blind-tests', '{}', true, StatsService.POST_TIMEOUT);
    ApiClient.requireOk(raw);
    return StatsService.parse<BlindTestStartDto>(raw.text, raw.status, '盲测创建返回格式异常');
  }

  /** POST /blind-tests/:id/finish（幂等）。 */
  static async finishBlindTest(blindTestId: string): Promise<BlindFinishDto> {
    const path = '/blind-tests/' + encodeURIComponent(blindTestId) + '/finish';
    const raw = await ApiClient.postJson(path, '{}', true, StatsService.POST_TIMEOUT);
    ApiClient.requireOk(raw);
    return StatsService.parse<BlindFinishDto>(raw.text, raw.status, '盲测报告格式异常');
  }

  /**
   * GET /health（无需登录）。force=true 时加 `?force=1` 跳过服务端 15s 缓存。
   * 返回全字段（features / capabilities / db / voice），健康页与降级判断都用它。
   * 本接口是公开的：不注入 Bearer、不参与 401 刷新（与 PracticeService.health 一致）。
   */
  static async healthFull(force: boolean): Promise<HealthFullDto> {
    const req = new ApiRequest();
    req.method = http.RequestMethod.GET;
    req.path = '/health';
    req.auth = false;
    req.retryOn401 = false;
    req.timeoutMs = StatsService.HEALTH_TIMEOUT;
    if (force) {
      const query = new Map<string, string>();
      query.set('force', '1');
      req.query = query;
    }
    const raw = await ApiClient.request(req);
    ApiClient.requireOk(raw);
    return StatsService.parse<HealthFullDto>(raw.text, raw.status, '健康检查返回格式异常');
  }

  private static parse<T>(text: string, status: number, message: string): T {
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
}

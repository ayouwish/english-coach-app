import { ApiClient, ApiRaw } from '../net/ApiClient';
import { ApiError, ApiErrorCode } from '../net/ApiError';
import {
  AvatarDescBodyDto,
  AvatarPresetsDto,
  AvatarSelectBodyDto,
  AvatarStateDto,
  FamilyCreateBodyDto,
  FamilyMemberDto,
  FamilyMemberListDto,
  FamilyMemberResponseDto,
  FamilyPatchBodyDto,
  ParentSummaryDto,
  ResetPasswordBodyDto,
  SettingsPatchBodyDto,
  SettingsResponseDto,
  SuggestionCreateBodyDto,
  SuggestionCreateResultDto,
  SuggestionListDto,
  SuggestionPatchBodyDto
} from '../net/AccountDtos';

/**
 * 账号类 API：设置偏好、家庭成员、家长面板、建议箱、虚拟形象。
 *
 * 关键约束（`.specs/account-misc.md` §10.2）：
 * - 儿童 PATCH /settings 绝不带 daily_limit_minutes / allow_free_chat（服务端 403）；
 * - PATCH /settings 返回的 user 是瘦身版，调用方不要用它覆盖 gender/autoIllustrate/storySentences；
 * - 判断权限只看 HTTP 状态码（儿童 403 不跳登录）；
 * - /avatar 的照片路径已按隐私策略关闭：multipart 会 403 policy_disabled，本服务不提供照片上传。
 */
export class AccountService {
  private static readonly SHORT: number = 15000;
  private static readonly WRITE_TIMEOUT: number = 30000;

  // ------------------------------------------------------------------ 设置

  /** GET /settings —— user（全量）+ prefs（camelCase）+ usage。 */
  static async settings(): Promise<SettingsResponseDto> {
    const raw = await ApiClient.getJson('/settings', null, AccountService.SHORT);
    ApiClient.requireOk(raw);
    return AccountService.parse<SettingsResponseDto>(raw.text, raw.status, '设置返回格式异常');
  }

  /** PATCH /settings —— 入参 snake_case；返回瘦身 user + 完整 prefs + 最新 usage。 */
  static async patchSettings(body: SettingsPatchBodyDto): Promise<SettingsResponseDto> {
    const raw = await ApiClient.patchJson('/settings', JSON.stringify(body), AccountService.WRITE_TIMEOUT);
    ApiClient.requireOk(raw);
    return AccountService.parse<SettingsResponseDto>(raw.text, raw.status, '保存设置返回格式异常');
  }

  // ------------------------------------------------------------------ 家庭成员

  /** GET /family/members —— 仅家长；items 是 snake_case。 */
  static async familyMembers(): Promise<FamilyMemberDto[]> {
    const raw = await ApiClient.getJson('/family/members', null, AccountService.SHORT);
    ApiClient.requireOk(raw);
    const dto = AccountService.parse<FamilyMemberListDto>(raw.text, raw.status, '成员列表格式异常');
    const items = dto.items;
    return items === undefined ? [] : items;
  }

  /** POST /family/members → 201。 */
  static async createMember(body: FamilyCreateBodyDto): Promise<FamilyMemberResponseDto> {
    const raw = await ApiClient.postJson('/family/members', JSON.stringify(body), true, AccountService.WRITE_TIMEOUT);
    AccountService.requireOk201(raw);
    return AccountService.parse<FamilyMemberResponseDto>(raw.text, raw.status, '创建成员返回格式异常');
  }

  /** PATCH /family/members/:id —— 可写昵称/水平/时长/自由聊/头像。 */
  static async updateMember(memberId: string, body: FamilyPatchBodyDto): Promise<FamilyMemberResponseDto> {
    const path = '/family/members/' + encodeURIComponent(memberId);
    const raw = await ApiClient.patchJson(path, JSON.stringify(body), AccountService.WRITE_TIMEOUT);
    ApiClient.requireOk(raw);
    return AccountService.parse<FamilyMemberResponseDto>(raw.text, raw.status, '保存成员返回格式异常');
  }

  /** POST /family/members/:id/password —— 不需要旧密码，可重置自己。 */
  static async resetMemberPassword(memberId: string, newPassword: string): Promise<void> {
    const path = '/family/members/' + encodeURIComponent(memberId) + '/password';
    const body: ResetPasswordBodyDto = { new_password: newPassword };
    const raw = await ApiClient.postJson(path, JSON.stringify(body), true, AccountService.WRITE_TIMEOUT);
    ApiClient.requireOk(raw);
  }

  // ------------------------------------------------------------------ 家长面板

  /** GET /parent/summary —— 仅家长；儿童 403（提示「家长专用」，不跳登录）。 */
  static async parentSummary(): Promise<ParentSummaryDto> {
    const raw = await ApiClient.getJson('/parent/summary', null, AccountService.SHORT);
    ApiClient.requireOk(raw);
    return AccountService.parse<ParentSummaryDto>(raw.text, raw.status, '家长面板返回格式异常');
  }

  // ------------------------------------------------------------------ 建议箱

  /** POST /suggestions —— 所有人（含儿童）都能提；不校验 user_id（服务端从会话取）。 */
  static async submitSuggestion(body: SuggestionCreateBodyDto): Promise<SuggestionCreateResultDto> {
    const raw = await ApiClient.postJson('/suggestions', JSON.stringify(body), true, AccountService.WRITE_TIMEOUT);
    ApiClient.requireOk(raw);
    return AccountService.parse<SuggestionCreateResultDto>(raw.text, raw.status, '建议提交返回格式异常');
  }

  /** GET /suggestions —— 仅家长；status 非法值服务端不过滤，这里只传空或三个合法值。 */
  static async listSuggestions(status: string, limit: number, offset: number): Promise<SuggestionListDto> {
    const query = new Map<string, string>();
    if (status.length > 0) {
      query.set('status', status);
    }
    query.set('limit', limit.toString());
    query.set('offset', offset.toString());
    const raw = await ApiClient.getJson('/suggestions', query, AccountService.SHORT);
    ApiClient.requireOk(raw);
    return AccountService.parse<SuggestionListDto>(raw.text, raw.status, '建议列表格式异常');
  }

  /** PATCH /suggestions/:id {status} —— open | read | resolved。 */
  static async patchSuggestionStatus(suggestionId: string, status: string): Promise<void> {
    const path = '/suggestions/' + encodeURIComponent(suggestionId);
    const body: SuggestionPatchBodyDto = { status: status };
    const raw = await ApiClient.patchJson(path, JSON.stringify(body), AccountService.WRITE_TIMEOUT);
    ApiClient.requireOk(raw);
  }

  /**
   * GET /suggestions/export?format=md[&status=] —— 响应体是 **Markdown 文本**（不是 JSON）。
   * 注意错误分支的 code 恒为 forbidden（看 HTTP 状态，不看 code）。
   */
  static async exportSuggestionsMarkdown(status: string): Promise<string> {
    const query = new Map<string, string>();
    query.set('format', 'md');
    if (status.length > 0) {
      query.set('status', status);
    }
    const raw = await ApiClient.getJson('/suggestions/export', query, AccountService.SHORT);
    ApiClient.requireOk(raw);
    return raw.text;
  }

  // ------------------------------------------------------------------ 虚拟形象

  /** GET /avatar/presets —— 12 角色 × 5 风格；images 是站内绝对路径。 */
  static async avatarPresets(): Promise<AvatarPresetsDto> {
    const raw = await ApiClient.getJson('/avatar/presets', null, AccountService.SHORT);
    ApiClient.requireOk(raw);
    return AccountService.parse<AvatarPresetsDto>(raw.text, raw.status, '预置形象库返回格式异常');
  }

  /** GET /avatar —— 未设置时字段为 null（styles 仍在）。 */
  static async avatar(): Promise<AvatarStateDto> {
    const raw = await ApiClient.getJson('/avatar', null, AccountService.SHORT);
    ApiClient.requireOk(raw);
    return AccountService.parse<AvatarStateDto>(raw.text, raw.status, '形象信息格式异常');
  }

  /** POST /avatar {preset_id, style} —— 立即生效，不生成图片。 */
  static async selectAvatar(presetId: string, style: string): Promise<AvatarStateDto> {
    const body: AvatarSelectBodyDto = { preset_id: presetId, style: style };
    const raw = await ApiClient.postJson('/avatar', JSON.stringify(body), true, AccountService.WRITE_TIMEOUT);
    ApiClient.requireOk(raw);
    return AccountService.parse<AvatarStateDto>(raw.text, raw.status, '保存形象返回格式异常');
  }

  /** PATCH /avatar {character_desc} —— 只允许改角色卡。 */
  static async updateAvatarDescription(desc: string): Promise<AvatarStateDto> {
    const body: AvatarDescBodyDto = { character_desc: desc };
    const raw = await ApiClient.patchJson('/avatar', JSON.stringify(body), AccountService.WRITE_TIMEOUT);
    ApiClient.requireOk(raw);
    return AccountService.parse<AvatarStateDto>(raw.text, raw.status, '保存形象描述返回格式异常');
  }

  /** DELETE /avatar —— 清空字段（预置静态图不删）。 */
  static async clearAvatar(): Promise<void> {
    const raw = await ApiClient.deleteJson('/avatar', AccountService.WRITE_TIMEOUT);
    ApiClient.requireOk(raw);
  }

  // ------------------------------------------------------------------ 内部

  private static requireOk201(raw: ApiRaw): void {
    if (raw.status === 200 || raw.status === 201) {
      return;
    }
    throw ApiClient.errorOf(raw);
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

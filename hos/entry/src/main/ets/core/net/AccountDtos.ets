import { UsageDto } from './Dtos';

/**
 * 账号 / 设置 / 家庭成员 / 家长面板 / 建议箱 / 虚拟形象 的 DTO。
 *
 * 事实来源：`.specs/account-misc.md` §3–§9、`.specs/chat-story.md` §4
 * （从 web 源码 route.ts / lib/*.ts 逐行读出，非抓包）。
 *
 * 约定：字段名保持服务端原样（该 snake_case 的一律 snake_case，`/settings` 的
 * `user`/`prefs` 是 camelCase 例外）；所有可能缺失的字段用 `?`，使用处必须兜底。
 */

// ---------------------------------------------------------------------------
// /api/settings
// ---------------------------------------------------------------------------

/** GET /settings 的 user（camelCase 全量 SessionUser；PATCH 返回的是瘦身版）。 */
export interface AccountUserDto {
  id: string;
  email: string;
  displayName: string;
  /** 'parent' | 'child' */
  role: string;
  /** 'child' | 'teen' | 'adult' */
  ageBand: string;
  cefrLevel: string;
  avatar?: string | null;
  birthYear?: number | null;
  avatarImagePath?: string | null;
  avatarImageUrl?: string | null;
  avatarStyle?: string | null;
  autoIllustrate?: boolean;
  /** girl | boy | woman | man | other | null */
  gender?: string | null;
  /** 3–12；null = 恢复角色默认（儿童 5 / 成人 8） */
  storySentences?: number | null;
  dailyLimitMinutes?: number;
  allowFreeChat?: boolean;
  nativeLanguage?: string;
  isChild?: boolean;
}

/** prefs 是 camelCase（PATCH 入参才是 snake_case）。 */
export interface PrefsDto {
  /** gentle | standard | none */
  correctionLevel?: string;
  /** 9 个音色 id 或 null（provider 默认） */
  ttsVoice?: string | null;
  /** slow | normal */
  ttsRate?: string;
  /** 点单词显示音标（null = 默认开） */
  showWordIpa?: boolean | null;
}

export interface SettingsResponseDto {
  user?: AccountUserDto;
  prefs?: PrefsDto;
  usage?: UsageDto;
}

/**
 * PATCH /settings 请求体（snake_case）。
 * 儿童**绝不能**带 `daily_limit_minutes` / `allow_free_chat`（服务端 403，整单失败）。
 */
export interface SettingsPatchBodyDto {
  display_name?: string;
  daily_limit_minutes?: number;
  allow_free_chat?: boolean;
  auto_illustrate?: boolean;
  gender?: string | null;
  story_sentences?: number | null;
  correction_level?: string;
  tts_rate?: string;
  tts_voice?: string | null;
  /** 点单词显示音标（null = 默认开） */
  show_word_ipa?: boolean | null;
}

// ---------------------------------------------------------------------------
// /api/family/members
// ---------------------------------------------------------------------------

export interface FamilyMemberStatsDto {
  attempts?: number;
  last_active_at?: string | null;
}

/** 注意：家庭成员列表是 snake_case，与 `/auth/me` 的 camelCase user 是两套 DTO。 */
export interface FamilyMemberDto {
  id: string;
  email?: string;
  display_name?: string;
  role?: string;
  age_band?: string;
  cefr_level?: string;
  avatar?: string | null;
  birth_year?: number | null;
  daily_limit_minutes?: number;
  allow_free_chat?: boolean;
  created_at?: string;
  stats?: FamilyMemberStatsDto;
}

export interface FamilyMemberListDto {
  items?: FamilyMemberDto[];
  count?: number;
}

export interface FamilyCreateBodyDto {
  display_name: string;
  /** 可只写简称，服务端自动补 @family.local */
  login: string;
  password: string;
  /** parent | child */
  role: string;
  /** A1 | A2 | B1 | B2 | C1 */
  cefr_level: string;
  birth_year?: number;
  avatar?: string;
  daily_limit_minutes?: number;
  allow_free_chat?: boolean;
}

/** PATCH /family/members/:id 可写字段；传 role 会 400。 */
export interface FamilyPatchBodyDto {
  display_name?: string;
  cefr_level?: string;
  daily_limit_minutes?: number;
  allow_free_chat?: boolean;
  avatar?: string;
}

export interface FamilyMemberResponseDto {
  ok?: boolean;
  member?: FamilyMemberDto;
}

export interface ResetPasswordBodyDto {
  new_password: string;
}

// ---------------------------------------------------------------------------
// /api/parent/summary
// ---------------------------------------------------------------------------

export interface ParentChildDto {
  id: string;
  display_name?: string;
  remaining_minutes?: number | null;
  limit_minutes?: number | null;
}

export interface ParentFamilyDto {
  members?: number;
  minutes_today?: number;
  minutes_7d?: number;
  sentence_count?: number;
  scenario_count?: number;
  children?: ParentChildDto[];
}

export interface ParentTodayDto {
  minutes?: number;
  blind_minutes?: number;
  total_minutes?: number;
  attempt_count?: number;
  chat_turns?: number;
  /** 仅 role==='child' 有值，家长为 null */
  remaining_minutes?: number | null;
  exceeded?: boolean;
}

export interface ParentWeekDto {
  minutes?: number;
  attempts?: number;
  avg_pron?: number | null;
}

export interface ParentTotalsDto {
  attempts?: number;
  chat_sessions?: number;
  phoneme_rows?: number;
  avg_pron?: number | null;
}

export interface ParentTrendPointDto {
  date?: string;
  attempts?: number;
  avg_pron?: number | null;
}

/** 盲测成绩块（current / previous / series / trend 共用）。 */
export interface ParentBlindScoreDto {
  blind_test_id?: string;
  ended_at?: string;
  avg_pron?: number | null;
  avg_accuracy?: number | null;
  avg_fluency?: number | null;
  avg_intonation_distance?: number | null;
  item_count?: number;
}

export interface ParentBlindDto {
  weeks?: number;
  current?: ParentBlindScoreDto | null;
  previous?: ParentBlindScoreDto | null;
  delta_pron?: number | null;
  series?: ParentBlindScoreDto[];
  in_progress_id?: string | null;
}

export interface ParentPhonemeDto {
  phoneme?: string;
  count?: number;
  avg_score?: number | null;
  hard_hits?: number;
  title_zh?: string;
}

export interface ParentWordDto {
  word?: string;
  count?: number;
  avg_score?: number | null;
  coarse?: boolean;
}

export interface ParentMemberDto {
  id: string;
  display_name?: string;
  avatar?: string | null;
  role?: string;
  age_band?: string;
  cefr_level?: string;
  birth_year?: number | null;
  daily_limit_minutes?: number;
  today?: ParentTodayDto;
  week?: ParentWeekDto;
  totals?: ParentTotalsDto;
  trend?: ParentTrendPointDto[];
  blind?: ParentBlindDto;
  top_phonemes?: ParentPhonemeDto[];
  top_words?: ParentWordDto[];
}

export interface ParentSummaryDto {
  generated_at?: string;
  family?: ParentFamilyDto;
  members?: ParentMemberDto[];
}

// ---------------------------------------------------------------------------
// /api/suggestions
// ---------------------------------------------------------------------------

export interface SuggestionViewportDto {
  w?: number | null;
  h?: number | null;
}

export interface SuggestionContextDto {
  ua?: string;
  app_version?: string;
  voice_mode?: string | null;
  viewport?: SuggestionViewportDto;
  story_id?: string;
  story_title?: string;
  style?: string;
  prompt?: string;
  kind?: string;
}

export interface SuggestionDto {
  id: string;
  /** child | parent */
  user_role?: string;
  page?: string;
  /** experience | content | feature | bug | other */
  category?: string;
  content?: string;
  /** open | read | resolved */
  status?: string;
  created_at?: string;
  handled_at?: string | null;
  context?: SuggestionContextDto | null;
}

export interface SuggestionCountsDto {
  open?: number;
  read?: number;
  resolved?: number;
}

export interface SuggestionListDto {
  items?: SuggestionDto[];
  counts?: SuggestionCountsDto;
  total?: number;
  generated_at?: string;
  max_length?: number;
}

export interface SuggestionCreateBodyDto {
  category: string;
  content: string;
  page?: string;
  context?: SuggestionContextDto;
}

export interface SuggestionCreateResultDto {
  ok?: boolean;
  id?: string;
  max_length?: number;
}

export interface SuggestionPatchBodyDto {
  status: string;
}

// ---------------------------------------------------------------------------
// /api/avatar + /api/avatar/presets
// ---------------------------------------------------------------------------

/** 5 种风格的中文名映射（`/avatar` 的 styles 字段，值是中文名而不是对象）。 */
export interface AvatarStyleLabelsDto {
  watercolor?: string;
  cartoon?: string;
  pixel?: string;
  papercut?: string;
  clay?: string;
}

export interface AvatarStyleDto {
  id: string;
  label_zh?: string;
}

/**
 * 角色图映射：键固定为 5 个风格 id，值是**站内绝对路径**（`/avatars/presets/...`）。
 * 移动端必须拼上 `AppConfig.getBaseUrl()` 才能用 Image 加载（静态图无需鉴权）。
 */
export interface AvatarImagesDto {
  watercolor?: string;
  cartoon?: string;
  pixel?: string;
  papercut?: string;
  clay?: string;
}

export interface AvatarPresetCharacterDto {
  id: string;
  label_zh?: string;
  desc_en?: string;
  /** girl | boy | woman | man | other */
  gender?: string;
  /** child | adult */
  audience?: string;
  images?: AvatarImagesDto;
}

export interface AvatarPresetsDto {
  count?: number;
  /** true = 服务端用的是占位图，UI 要提示「预览图」 */
  placeholder?: boolean;
  styles?: AvatarStyleDto[];
  characters?: AvatarPresetCharacterDto[];
}

/** GET/POST/PATCH /avatar 的返回（PATCH 多一个 message）。 */
export interface AvatarStateDto {
  ok?: boolean;
  /** 预置图 → 静态路径；自定义图 → /api/avatar/image?...（当前策略下不会出现） */
  avatar_url?: string | null;
  preset_id?: string | null;
  style?: string | null;
  character_desc?: string | null;
  prompt_used?: string | null;
  updated_at?: string | null;
  styles?: AvatarStyleLabelsDto;
  message?: string;
}

export interface AvatarSelectBodyDto {
  preset_id: string;
  style: string;
}

export interface AvatarDescBodyDto {
  character_desc: string;
}

/** GET /family/invite —— 家庭邀请码（仅家长；邀请码一次性 + 家长上限）。 */
export interface FamilyInviteDto {
  family_id?: string;
  family_name?: string;
  invite_code?: string;
  invite_used?: boolean;
  invite_used_by?: string | null;
  invite_used_at?: string | null;
  parents_count?: number;
  parents_limit?: number;
}
/** 新家庭邀请码（管理员家庭生成；一次性，消耗 1 个名额）。 */
export interface FamilyInviteCodeDto {
  code: string;
  created_at: string;
  used_at?: string | null;
  used_by_family_name?: string | null;
}

/** GET /family/family-invites —— 名额 + 最近 20 条新家庭邀请码。 */
export interface FamilyInvitesDto {
  is_admin?: boolean;
  quota_remaining?: number;
  quota_total_hint?: number;
  invites?: FamilyInviteCodeDto[];
}

/** POST /family/family-invites —— 新生成的新家庭邀请码。 */
export interface FamilyInviteCreateDto {
  ok?: boolean;
  code?: string;
  quota_remaining?: number;
}
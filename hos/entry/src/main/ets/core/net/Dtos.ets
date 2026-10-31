/**
 * 与服务端契约一一对应的 DTO（字段名保持服务端原样，不做驼峰转换）。
 *
 * 事实来源：
 * - `english-coach/docs/api-contract.md`（voice 契约）
 * - `english-coach/web/src/lib/types.ts`、`src/lib/auth.ts`、`src/lib/usage.ts`（web 包装形状）
 * - 本目录 `README.md` §2
 *
 * 字段一律按「服务端可能缺失」处理：数组/对象用 `?`，使用处必须兜底。
 * 服务端新增字段不会破坏客户端（只读自己声明的字段）。
 */

export interface ErrorBodyDto {
  code?: string;
  message?: string;
}

export interface ErrorEnvelopeDto {
  error?: ErrorBodyDto;
}

export interface UserDto {
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
  dailyLimitMinutes?: number;
  allowFreeChat?: boolean;
  isChild?: boolean;
  nativeLanguage?: string;
}

export interface UsageDto {
  minutes: number;
  limitMinutes: number;
  remainingMinutes: number;
  exceeded: boolean;
  attemptCount?: number;
  chatTurnCount?: number;
}

export interface TokenResponseDto {
  access_token: string;
  refresh_token: string;
  token_type?: string;
  /** access 有效期（秒），服务端 3600 */
  expires_in: number;
  /** refresh 有效期（秒），服务端 30 天 */
  refresh_expires_in?: number;
  user?: UserDto;
}

export interface MeResponseDto {
  user?: UserDto | null;
  usage?: UsageDto;
}

export interface SentenceDto {
  id: string;
  text: string;
  translation_zh?: string;
  level: string;
  /** 儿童账号服务端会返回空数组（服务端已剥离 IPA） */
  focus_phonemes?: string[];
  tags?: string[];
  source?: string;
  owner_user_id?: string | null;
  mine?: boolean;
  sort_order?: number;
}

export interface SentenceListDto {
  level?: string | null;
  count?: number;
  sentences?: SentenceDto[];
  user_level?: string;
  official_count?: number;
  custom_count?: number;
  mine_count?: number;
}

export interface ScoresDto {
  /** 综合分 0–100；不可得为 null（不是 0） */
  pron?: number | null;
  accuracy?: number | null;
  fluency?: number | null;
  completeness?: number | null;
  prosody?: number | null;
}

export interface WordScoreDto {
  word: string;
  score?: number | null;
  error_type?: string | null;
  start_ms?: number | null;
  end_ms?: number | null;
}

export interface IssueDto {
  type?: string;
  severity?: string;
  word?: string;
  phoneme?: string | null;
  expected?: string | null;
  actual?: string | null;
  score?: number | null;
  hint_key?: string | null;
}

export interface IntonationDto {
  available?: boolean;
  dtw_distance?: number | null;
  worst_regions?: IntonationRegionDto[];
}

export interface IntonationRegionDto {
  start_ms?: number;
  end_ms?: number;
  text?: string;
  issue?: string;
}

export interface PronounceResultDto {
  provider?: string;
  granularity?: string;
  mode?: string;
  reference_text?: string;
  recognized_text?: string;
  duration_ms?: number;
  scores?: ScoresDto;
  words?: WordScoreDto[];
  issues?: IssueDto[];
  intonation?: IntonationDto | null;
  warnings?: string[];
}

export interface FeedbackPointDto {
  title?: string;
  why?: string;
  how?: string;
  practice_words?: string[];
  demo_text?: string | null;
  severity?: string;
}

export interface FeedbackDto {
  provider?: string;
  summary?: string;
  praise?: string;
  points?: FeedbackPointDto[];
  closing?: string;
}

export interface BlindProgressDto {
  done?: number;
  total?: number;
}

/** POST /api/attempts 响应（web 自己的形状）。盲测时只有 attempt_id/blind/progress。 */
export interface AttemptResponseDto {
  attempt_id: string;
  blind?: boolean;
  degraded?: boolean;
  retryable?: boolean;
  message?: string;
  result?: PronounceResultDto | null;
  feedback?: FeedbackDto | null;
  usage?: UsageDto;
  progress?: BlindProgressDto;
}

export interface HealthVoiceDto {
  reachable?: boolean;
  mode?: string;
  capabilities?: HealthCapabilitiesDto;
  hint?: string | null;
}

export interface HealthCapabilitiesDto {
  phoneme_level?: boolean;
  prosody?: boolean;
  intonation_curve?: boolean;
  nbest_phonemes?: boolean;
  ssml?: boolean;
  ocr?: boolean;
}

export interface HealthDbDto {
  ok?: boolean;
  error?: string | null;
}

export interface HealthDto {
  status?: string;
  service?: string;
  version?: string;
  time?: string;
  db?: HealthDbDto;
  voice?: HealthVoiceDto;
}

export interface LoginBodyDto {
  email: string;
  password: string;
  user_agent?: string;
}

export interface RefreshBodyDto {
  refresh_token: string;
}

export interface RevokeBodyDto {
  refresh_token: string;
}

export interface TtsBodyDto {
  text: string;
  rate: string;
  format: string;
}

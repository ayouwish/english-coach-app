import { HealthDbDto } from './Dtos';

/**
 * 诊断 / 错音本 / 盲测 / 健康检查 的 DTO。
 *
 * 事实来源：`.specs/practice-flow.md` §2.14–§2.16、§6；`.specs/account-misc.md` §7
 * （web 源码级契约，非抓包）。字段名保持服务端原样。
 */

// ---------------------------------------------------------------------------
// GET /api/diagnosis（scope=all | recent | attempt | batch）
// ---------------------------------------------------------------------------

export interface DiagnosisCountsDto {
  weak?: number;
  watch?: number;
  ok?: number;
}

export interface DiagnosisTrendDto {
  /** improving | flat | declining */
  direction?: string;
  delta?: number;
  points?: number[];
}

export interface DiagnosisErrorWordDto {
  word?: string;
  score?: number | null;
}

export interface DiagnosisContrastDto {
  /** 儿童为空串 */
  phoneme?: string;
  /** 已跨音素全局去重并排序 */
  pair?: string[];
  note?: string;
}

/** 一个音素的诊断行。status: weak(avg<65) / watch(65–80) / ok(≥80)。 */
export interface DiagnosisItemDto {
  /** 儿童为空串（服务端已剥离 IPA，客户端也不显示） */
  phoneme?: string;
  child_label?: string;
  focus_token?: string;
  status?: string;
  attempts?: number;
  avg_score?: number | null;
  last_score?: number | null;
  best_score?: number | null;
  trend?: DiagnosisTrendDto | null;
  error_words?: DiagnosisErrorWordDto[];
  practice_count?: number;
  tip_zh?: string;
  tip_child_zh?: string;
  /** 儿童版不展示（服务端已剥离） */
  common_errors?: string[];
  examples?: string[];
  contrasts?: DiagnosisContrastDto[];
}

export interface DiagnosisRangeDto {
  scope?: string;
  attempt_count?: number;
  attempt_ids?: string[];
}

export interface DiagnosisResponseDto {
  generated_at?: string;
  min_samples?: number;
  total_phonemes?: number;
  counted_phonemes?: number;
  counts?: DiagnosisCountsDto;
  summary_zh?: string;
  focus_phonemes?: string[];
  items?: DiagnosisItemDto[];
  scope?: string;
  range?: DiagnosisRangeDto;
}

// ---------------------------------------------------------------------------
// GET/POST /api/review（错音本 SRS）
// ---------------------------------------------------------------------------

export interface ReviewStatsDto {
  total_cards?: number;
  due_cards?: number;
  phoneme_rows?: number;
  phoneme_level?: boolean;
  voice_reachable?: boolean;
}

export interface ReviewDisplayDto {
  text?: string;
}

/** 一张 SRS 卡片。儿童：phoneme=null、ref=""，只显示 label/why_zh/how_zh。 */
export interface ReviewCardDto {
  id: string;
  /** phoneme | word | sentence */
  kind?: string;
  ref?: string;
  due_at?: string;
  ease?: number;
  interval_days?: number;
  reps?: number;
  lapses?: number;
  last_grade?: string | null;
  is_phoneme?: boolean;
  phoneme?: string | null;
  hint_key?: string | null;
  label?: string;
  why_zh?: string;
  how_zh?: string;
  practice_words?: string[];
  demo_text?: string;
  display?: ReviewDisplayDto;
}

export interface ReviewWeakPhonemeTrendDto {
  t?: string;
  s?: number | null;
}

export interface ReviewWeakPhonemeDto {
  phoneme?: string;
  hint_key?: string | null;
  attempts?: number;
  avg_score?: number | null;
  best_score?: number | null;
  last_score?: number | null;
  trend?: ReviewWeakPhonemeTrendDto[];
  label?: string;
}

export interface ReviewWordErrorDto {
  word?: string;
  count?: number;
  avg_score?: number | null;
  coarse?: boolean;
}

export interface ReviewGradeDto {
  /** again | hard | good | easy */
  grade: string;
  label_zh?: string;
}

export interface ReviewResponseDto {
  now?: string;
  stats?: ReviewStatsDto;
  due_cards?: ReviewCardDto[];
  weak_phonemes?: ReviewWeakPhonemeDto[];
  word_level_errors?: ReviewWordErrorDto[];
  grades?: ReviewGradeDto[];
}

export interface ReviewGradeBodyDto {
  card_id: string;
  grade: string;
}

export interface ReviewGradeResultDto {
  card_id?: string;
  grade?: string;
  next_due_at?: string;
  interval_days?: number;
  ease?: number;
  reps?: number;
  lapses?: number;
}

// ---------------------------------------------------------------------------
// /api/blind-tests（盲测）
// ---------------------------------------------------------------------------

export interface BlindTestDto {
  id: string;
  user_id?: string;
  started_at?: string;
  ended_at?: string | null;
  item_count?: number;
  avg_pron?: number | null;
  avg_accuracy?: number | null;
  avg_fluency?: number | null;
  avg_intonation_distance?: number | null;
  sentence_ids?: string[];
  /** 异步评分进度（tests[] / in_progress 都额外带这两个字段） */
  scored?: number;
  pending?: number;
}

export interface BlindTestStartDto {
  blind_test_id: string;
  sentence_ids?: string[];
  total?: number;
  /** true = 复用了进行中的批次（HTTP 200）；false = 新建（201） */
  resumed?: boolean;
  started_at?: string;
}

export interface BlindTrendScoreDto {
  blind_test_id?: string;
  ended_at?: string;
  avg_pron?: number | null;
  avg_accuracy?: number | null;
  avg_fluency?: number | null;
  avg_intonation_distance?: number | null;
  item_count?: number;
}

export interface BlindTrendDto {
  current?: BlindTrendScoreDto | null;
  previous?: BlindTrendScoreDto | null;
  delta_pron?: number | null;
  delta_accuracy?: number | null;
  delta_fluency?: number | null;
  delta_intonation_distance?: number | null;
  /** 已完成批次数 */
  weeks?: number;
}

export interface BlindTestListDto {
  user_id?: string;
  tests?: BlindTestDto[];
  in_progress?: BlindTestDto | null;
  pending_total?: number;
  trend?: BlindTrendDto | null;
  /** 按时间正序（画柱状图用） */
  series?: BlindTrendScoreDto[];
}

export interface BlindFinishDto {
  blind_test_id?: string;
  user_id?: string;
  started_at?: string;
  ended_at?: string;
  item_count?: number;
  submitted?: number;
  scored?: number;
  pending?: number;
  /** 只有全评完才是 null；有值时必须展示黄条 */
  notice?: string | null;
  avg_pron?: number | null;
  avg_accuracy?: number | null;
  avg_fluency?: number | null;
  avg_intonation_distance?: number | null;
  previous?: BlindTrendScoreDto | null;
  delta_pron?: number | null;
  delta_accuracy?: number | null;
  delta_fluency?: number | null;
  delta_intonation_distance?: number | null;
}

// ---------------------------------------------------------------------------
// GET /api/health（全字段；Dtos.ets 里的 HealthDto 是早期简化版，这里补全）
// ---------------------------------------------------------------------------

export interface HealthFeaturesDto {
  chat_unlimited_turns?: boolean;
  chat_audio_replay?: boolean;
  chat_scenarios_audience?: boolean;
  avatar_presets?: boolean;
  story_mode?: boolean;
  async_scoring?: boolean;
}

export interface HealthCapabilitiesFullDto {
  phoneme_level?: boolean;
  prosody?: boolean;
  intonation_curve?: boolean;
  nbest_phonemes?: boolean;
  ssml?: boolean;
  gpu?: boolean;
  ocr?: boolean;
  ocr_provider?: string | null;
  heic?: boolean;
  image?: boolean;
  image_provider?: string | null;
  /** false = 照片生成形象已按隐私策略关闭（隐藏入口） */
  image_avatar?: boolean;
  avatar_presets?: boolean;
  audio_concat?: boolean;
  chat_done_turn_index?: number;
  /** voice 侧已实现的端点清单（排障用） */
  features?: string[];
}

export interface HealthVoiceFullDto {
  reachable?: boolean;
  /** hybrid | cloud | local | unreachable */
  mode?: string;
  /** 服务端容器内地址，不是客户端可用地址 */
  url?: string;
  capabilities?: HealthCapabilitiesFullDto;
  hint?: string | null;
}

export interface HealthFullDto {
  /** ok | degraded（只看 DB；voice 挂了仍是 ok） */
  status?: string;
  service?: string;
  version?: string;
  time?: string;
  db?: HealthDbDto;
  features?: HealthFeaturesDto;
  voice?: HealthVoiceFullDto;
}

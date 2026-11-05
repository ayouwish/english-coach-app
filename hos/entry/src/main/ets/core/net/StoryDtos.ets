/**
 * 故事模式 DTO / 展示模型。
 * 字段来源：.specs/chat-story.md §3（web 源码级契约，2026-11-03）。
 *
 * 约定：
 * - DTO 字段名保持服务端原样（snake_case），一律按「可能缺失」处理；
 * - 展示模型（*Item / *Group / *Record）是客户端自己的形状，页面只读这些；
 * - 线上没有 `/api/story/recordings`（404），中文录音一律降级走 `/api/asr?language=zh-CN`，
 *   因此「我当时讲的原话」只在本会话内存里保留（见 StoryRuntime）。
 */

// ---------------------------------------------------------------------------
// /api/materials（kind=story）
// ---------------------------------------------------------------------------

/** 故事/书页（材料）。列表项是 summary，详情多 text/source_zh/image_* 字段。 */
export interface StoryMaterialDto {
  id: string;
  title?: string;
  /** 英文正文（详情才有；句子以换行分隔） */
  text?: string;
  /** 中文原文（详情才有） */
  source_zh?: string | null;
  kind?: string;
  level?: string | null;
  sentence_count?: number;
  source?: string;
  has_image?: boolean;
  has_source_zh?: boolean;
  /** 详情：`/api/materials/:id/image`（需要 Bearer，不能直接给 Image 用） */
  image_url?: string | null;
  /** 详情：上次生成插画用的提示词 */
  image_prompt?: string | null;
  image_character_used?: boolean;
  created_by?: string | null;
  created_by_name?: string;
  created_by_avatar_url?: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface StoryMaterialListDto {
  count?: number;
  items?: StoryMaterialDto[];
}

/** POST /api/materials 请求体（kind=story）。 */
export interface StoryMaterialCreateDto {
  title: string;
  text: string;
  kind: string;
  source_zh?: string;
  level?: string;
  source?: string;
}

/** POST /api/materials 响应（201，summary + limits）。 */
export interface StoryMaterialCreatedDto {
  id: string;
  title?: string;
  created_by_name?: string;
  sentence_count?: number;
  has_image?: boolean;
  source?: string;
  kind?: string;
  level?: string | null;
  has_source_zh?: boolean;
  created_by?: string;
  created_at?: string;
  updated_at?: string;
}

// ---------------------------------------------------------------------------
// /api/asr（降级路径：中文 / 英文转录）
// ---------------------------------------------------------------------------

export interface StoryAsrDto {
  text?: string;
  language?: string;
  provider?: string;
  duration_ms?: number;
  error?: string | null;
}

// ---------------------------------------------------------------------------
// /api/story/rewrite
// ---------------------------------------------------------------------------

export interface StoryReadabilityDto {
  sentence_count?: number;
  avg_words?: number;
  max_words?: number;
  unknown_words?: string[];
  ok?: boolean;
}

export interface StoryRewriteBodyDto {
  text_zh: string;
  level: string;
  max_sentences?: number;
  weak_phonemes?: string[];
  use_weak_phonemes?: boolean;
  /** auto | past | present（叙事默认一般过去时，不符会自动重写一次） */
  tense?: string;
}

export interface StoryRewriteDto {
  title_en?: string;
  sentences?: string[];
  text_en?: string;
  level?: string;
  readability?: StoryReadabilityDto;
  warnings?: string[];
  provider?: string;
  weak_phonemes_used?: string[];
}

// ---------------------------------------------------------------------------
// /api/story/retell
// ---------------------------------------------------------------------------

export interface StoryRetellBodyDto {
  material_id?: string;
  story_sentences: string[];
  transcript: string;
  /** A1|A2|B1|B2|C1；非法值服务端静默回落 A2 */
  level: string;
}

export interface StoryRetellDto {
  id?: string;
  /** 0–1 的覆盖率（儿童端不显示百分比） */
  coverage?: number;
  covered_points?: string[];
  missing_points?: string[];
  feedback_zh?: string;
  feedback_en?: string;
  warnings?: string[];
  provider?: string;
}

// ---------------------------------------------------------------------------
// POST /api/story/:id/illustrate
// ---------------------------------------------------------------------------

export interface StoryIllustrateBodyDto {
  force?: boolean;
  style?: string;
}

export interface StoryIllustrationDto {
  ok?: boolean;
  image_url?: string | null;
  image_path?: string;
  mime?: string;
  provider?: string;
  model?: string;
  size?: string;
  elapsed_ms?: number;
  warnings?: string[];
  prompt_used?: string;
  character_used?: boolean;
  character_desc_used?: string;
  character_style_used?: string;
  force?: boolean;
}

// ---------------------------------------------------------------------------
// GET /api/story/:id/audio/status（整段朗读回放）
// ---------------------------------------------------------------------------

/**
 * 服务端状态：ready | building | failed。
 * 客户端补充两个：no_audio（404，没有任何朗读录音）、checking（本地占位）。
 */
export interface StoryAudioStatusDto {
  status?: string;
  attempt_count?: number;
  single?: boolean;
  duration_ms?: number;
  error?: string;
  error_code?: string;
  retry_after_ms?: number;
}

// ---------------------------------------------------------------------------
// 展示模型
// ---------------------------------------------------------------------------

/** 详情/预览里的一条句子（英文 + 对应中文，可编辑英文）。 */
export class StorySentenceItem {
  /** 1-based 序号（详情正文编号） */
  index: number = 0;
  en: string = '';
  zh: string = '';
}

/** 故事集列表项（已按「今天/昨天/更早」分好组后的卡片数据）。 */
export class StoryCardItem {
  id: string = '';
  title: string = '';
  level: string = '';
  sentenceCount: number = 0;
  authorName: string = '';
  authorId: string = '';
  hasImage: boolean = false;
  hasSourceZh: boolean = false;
  createdAt: string = '';
  /** 本地日期键：yyyy-mm-dd（用于分组/连续天数） */
  dateKey: string = '';
  /** 展示用日期：M月D日 */
  dateText: string = '';
  /** 今天 / 昨天 / 更早 */
  dateLabel: string = '';
  /** 列表直接带 summary，进详情先渲染再刷新 */
  material: StoryMaterialDto | null = null;
}

/** 故事集分组（今天/昨天/更早）。 */
export class StoryGroup {
  label: string = '';
  items: StoryCardItem[] = [];
}

/** 本次会话里的一次复述结果（服务端没有复述历史接口，只能内存保留）。 */
export class StoryRetellRecord {
  /** 复述者（本地内存按人隔离，切换账号不串） */
  userId: string = '';
  createdAt: string = '';
  coverage: number = -1;
  coveredCount: number = 0;
  coveredPoints: string[] = [];
  missingPoints: string[] = [];
  feedbackZh: string = '';
  feedbackEn: string = '';
  transcript: string = '';
}

/** 复用：故事里的一条提示（warning → 人话）。 */
export class StoryTextPair {
  key: string = '';
  text: string = '';
}

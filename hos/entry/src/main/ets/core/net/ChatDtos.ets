/**
 * 对话训练 DTO（服务端 web 层形状）。
 * 字段来源：.specs/chat-story.md §2（源码级契约），字段名保持服务端原样。
 *
 * 约定：字段一律按「服务端可能缺失」处理（`?`），使用处必须兜底。
 */

// ---------------------------------------------------------------------------
// §2.5 / §2.6 纠正与发音
// ---------------------------------------------------------------------------

/** 一轮里的「更自然」提示（§2.5 correction）。 */
export interface ChatCorrectionDto {
  has_error?: boolean;
  /** grammar | vocabulary | politeness | pronunciation | none */
  type?: string;
  original?: string;
  better?: string;
  explain_zh?: string;
  /** low | medium | high */
  severity?: string;
}

/** 最弱音：儿童账号 `ipa` 恒为 null，只留 label（§2.6）。 */
export interface ChatWeakPhonemeDto {
  ipa?: string | null;
  label?: string;
  score?: number | null;
}

export interface ChatWordScoreDto {
  word?: string;
  score?: number | null;
}

/** 发音评分：只在 `GET /:id/messages` 里出现（§2.6）。 */
export interface ChatPronDto {
  pron?: number | null;
  accuracy?: number | null;
  fluency?: number | null;
  completeness?: number | null;
  weak_phonemes?: ChatWeakPhonemeDto[];
  words?: ChatWordScoreDto[];
}

// ---------------------------------------------------------------------------
// 场景（§2.2 / §2.3 / §2.4）
// ---------------------------------------------------------------------------

/** 开会话时抽到的变体（§2.4）。 */
export interface ChatVariationDto {
  persona?: string;
  place?: string;
  detail?: string;
  goal?: string;
  opening_line?: string;
}

export interface ChatScenarioDto {
  id: string;
  /** child | adult */
  audience?: string;
  is_custom?: boolean;
  title?: string;
  title_zh?: string;
  setting_zh?: string;
  /** 开会话后这里是抽到的变体开场白（显示与朗读都用它） */
  opening_line?: string;
  level?: string;
  min_age?: number;
  tags?: string[];
  /** 仅自定义场景有效（0–5） */
  variation_count?: number;
  variation?: ChatVariationDto | null;
  /** 新版服务端可能带自定义场景角色设定（列表不保证有） */
  role_prompt?: string;
}

/** `GET /api/chat/scenarios[?include_child=1]` */
export interface ChatScenarioListDto {
  age?: number;
  is_child?: boolean;
  /** 当前账号该看哪一类 */
  audience?: string;
  include_child?: boolean;
  count?: number;
  custom_count?: number;
  hidden_count?: number;
  scenarios?: ChatScenarioDto[];
}

/** `POST /api/chat/scenarios` 201 / PATCH / DELETE 的响应。 */
export interface ChatScenarioMutationDto {
  ok?: boolean;
  id?: string;
  is_custom?: boolean;
  audience?: string;
  deleted?: string;
}

// ---------------------------------------------------------------------------
// 会话 / 消息（§2.4–§2.9）
// ---------------------------------------------------------------------------

export interface ChatMessageDto {
  id: string;
  /** user | assistant */
  role?: string;
  text?: string;
  text_zh?: string | null;
  created_at?: string;
  correction?: ChatCorrectionDto | null;
  pron?: ChatPronDto | null;
  audio_url?: string | null;
  /** ok | unsafe_filtered | off_topic */
  flag?: string | null;
}

export interface ChatMessageListDto {
  session_id?: string;
  messages?: ChatMessageDto[];
}

/** `POST /api/chat/sessions` 201（内置场景分支含 age/turn_count/messages；自定义分支更瘦）。 */
export interface ChatSessionDto {
  session_id: string;
  scenario?: ChatScenarioDto;
  age?: number;
  turn_count?: number;
  messages?: ChatMessageDto[];
  is_custom?: boolean;
}

/** `POST /api/chat/sessions/:id/turn` 200（不含 TTS 音频）。 */
export interface ChatTurnDto {
  session_id?: string;
  provider?: string;
  /** true = 本条是固定话术，不是大模型 */
  degraded_llm?: boolean;
  /** true = 调用失败降级到本地话术 */
  degraded?: boolean;
  capabilities?: ChatCapabilitiesDto;
  reply?: string;
  reply_zh?: string;
  correction?: ChatCorrectionDto | null;
  suggested_replies?: string[];
  target_words?: string[];
  /** ok | unsafe_filtered | off_topic */
  flag?: string;
  /** true = 本场景自然收尾 */
  done?: boolean;
  turn_index?: number;
  message_id?: string;
  user_message_id?: string;
  user_audio_url?: string | null;
}

export interface ChatCapabilitiesDto {
  phoneme_level?: boolean;
  prosody?: boolean;
  intonation_curve?: boolean;
  ssml?: boolean;
  ocr?: boolean;
  image?: boolean;
  audio_concat?: boolean;
  chat_done_turn_index?: number;
  features?: string[];
}

/** `POST /:id/end` 200（幂等）。 */
export interface ChatEndDto {
  ok?: boolean;
  session_id?: string;
  ended?: boolean;
}

/** `GET /:id/audio/status`（只读，绝不触发构建）。 */
export interface ChatAudioStatusDto {
  /** ready | building | failed */
  status?: string;
  turn_count?: number;
  auto_retry?: boolean;
  duration_ms?: number;
  error?: string | null;
  error_code?: string | null;
  attempts?: number;
}

/** `GET /:id/audio` 202（构建中）响应体。 */
export interface ChatAudioBuildingDto {
  status?: string;
  turn_count?: number;
  retry_after_ms?: number;
  forced?: boolean;
}

/** `GET /api/chat/sessions` 列表项（§2.9）。 */
export interface ChatSessionListItemDto {
  id: string;
  scenario_id?: string;
  scenario_title?: string;
  scenario_title_zh?: string;
  started_at?: string;
  ended_at?: string | null;
  turn_count?: number;
  last_message?: string | null;
}

export interface ChatSessionListDto {
  sessions?: ChatSessionListItemDto[];
}

/** `GET /api/chat/sessions/:id`（详情，**无 pron**）。 */
export interface ChatSessionDetailDto {
  session_id?: string;
  scenario_id?: string;
  scenario_title?: string;
  scenario_title_zh?: string;
  turn_count?: number;
  started_at?: string;
  ended_at?: string | null;
  messages?: ChatMessageDto[];
}

// ---------------------------------------------------------------------------
// ASR / TTS（§2.5 第 ① 步、§5.2）
// ---------------------------------------------------------------------------

/** `POST /api/asr` 响应：`{text}`（部分版本叫 transcript）。 */
export interface ChatAsrDto {
  text?: string;
  transcript?: string;
}

// ---------------------------------------------------------------------------
// 跨页面参数桥
// ---------------------------------------------------------------------------

/**
 * 对话模块跨页面的临时参数。
 *
 * 为什么不用 NavState：NavState 只有 `setChat/setSession` 两个入参口，且不属于本模块
 * （本模块不得修改它）。额外字段（刚创建的会话完整数据、历史列表项、正在编辑的场景）
 * 统一放在这里；push 之前由发起方设置，目标页在 `aboutToAppear` 读取一次。
 */
export class ChatNav {
  /** 刚创建的会话（含 scenario/opening_line），ChatSessionPage 用它立即渲染 */
  static session: ChatSessionDto | null = null;
  /** 历史列表点进来时带的列表项（补标题/时间/轮数） */
  static historyItem: ChatSessionListItemDto | null = null;
  /** 自定义场景页的编辑对象（null = 新建） */
  static editScenario: ChatScenarioDto | null = null;

  static resetSession(): void {
    ChatNav.session = null;
  }

  static resetHistory(): void {
    ChatNav.historyItem = null;
  }

  static resetEdit(): void {
    ChatNav.editScenario = null;
  }
}

/**
 * 连读模式（/flow）专用 DTO。
 *
 * 与 `Dtos.ets` 分开放的原因：`Dtos.ets` 是全模块共享契约，连读只用到其中
 * 的 `/attempts/async`、`/attempts/status`、`/materials`、`/ocr`；
 * 这里补的是连读汇总页要用的 `GET /diagnosis?scope=batch`（§2.14）。
 *
 * 字段名保持服务端原样，全部按「可能缺失」处理（`?`），使用处必须兜底。
 */

export interface FlowDiagnosisCountsDto {
  weak?: number;
  watch?: number;
  ok?: number;
}

export interface FlowDiagnosisTrendDto {
  /** improving | flat | declining */
  direction?: string;
  delta?: number;
  /** 最近 3 次的分数点（可能缺失） */
  points?: number[];
}

export interface FlowDiagnosisErrorWordDto {
  word?: string;
  score?: number | null;
}

export interface FlowDiagnosisContrastDto {
  /** 儿童账号服务端会返回空串 */
  phoneme?: string;
  /** 已排序的对比音素对，例如 ["θ","s"] */
  pair?: string[];
  note?: string;
}

export interface FlowDiagnosisItemDto {
  /** 儿童账号为空串（服务端已剥离 IPA） */
  phoneme?: string;
  /** 儿童可见的口语化名字；成人也有，可作补充 */
  child_label?: string;
  focus_token?: string;
  /** weak | watch | ok */
  status?: string;
  attempts?: number;
  avg_score?: number | null;
  last_score?: number | null;
  best_score?: number | null;
  trend?: FlowDiagnosisTrendDto | null;
  error_words?: FlowDiagnosisErrorWordDto[];
  practice_count?: number;
  tip_zh?: string;
  tip_child_zh?: string;
  common_errors?: string[];
  examples?: string[];
  contrasts?: FlowDiagnosisContrastDto[];
}

export interface FlowDiagnosisRangeDto {
  scope?: string;
  /** 本次参与统计的 attempt 数 */
  attempt_count?: number;
  attempt_ids?: string[];
}

/** GET /diagnosis?scope=batch&attempt_ids=a,b,c（≤20） */
export interface FlowDiagnosisDto {
  generated_at?: string;
  min_samples?: number;
  total_phonemes?: number;
  counted_phonemes?: number;
  counts?: FlowDiagnosisCountsDto;
  summary_zh?: string;
  focus_phonemes?: string[];
  items?: FlowDiagnosisItemDto[];
  /** batch */
  scope?: string;
  range?: FlowDiagnosisRangeDto;
}

import { ApiClient } from '../net/ApiClient';

/** 单词音标查询结果（task-87；浮层只显示 /音标/，不提供发音按钮）。 */
export class WordIpaResult {
  word: string = '';
  ipa: string = '';
  variants: string[] = [];
  /** 服务端返回「音标已关闭」（设置里关了） */
  disabled: boolean = false;
  /** 词典未收录 / 失败 → 显示「暂无音标」 */
  missing: boolean = false;
}

interface WordIpaDto {
  word?: string;
  ipa?: string | null;
  variants?: string[];
  syllables?: number | null;
  ipa_disabled?: boolean;
}

/**
 * `GET /api/words/:word`（v0.19）。
 *
 * - 401/403：未登录（调用方已在登录态，按“暂无音标”处理）
 * - 404：词典未收录（不报错，浮层显示「暂无音标」）
 * - 503：音标服务暂时不可用
 * 同一进程内做大小写不敏感缓存。
 */
export class DictionaryService {
  private static readonly TIMEOUT_MS: number = 8000;
  private static cache: Map<string, WordIpaResult> = new Map();

  static async wordIpa(word: string): Promise<WordIpaResult> {
    const trimmed = word.trim();
    const result = new WordIpaResult();
    result.word = trimmed;
    if (trimmed.length === 0) {
      result.missing = true;
      return result;
    }
    const key = trimmed.toLowerCase();
    const hit = DictionaryService.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    try {
      const raw = await ApiClient.getJson('/words/' + encodeURIComponent(trimmed), null,
        DictionaryService.TIMEOUT_MS);
      if (raw.status === 404) {
        result.missing = true;
      } else if (raw.status >= 200 && raw.status < 300) {
        let dto: WordIpaDto | null = null;
        try {
          dto = JSON.parse(raw.text) as WordIpaDto;
        } catch (err) {
          dto = null;
        }
        if (dto === null || dto.ipa === undefined || dto.ipa === null || dto.ipa.length === 0) {
          result.missing = true;
        } else {
          result.ipa = dto.ipa;
        }
        if (dto !== null && dto.ipa_disabled === true) {
          result.disabled = true;
          result.ipa = '';
          result.missing = false;
        }
        if (dto !== null && dto.variants !== undefined && dto.variants !== null) {
          result.variants = dto.variants;
        }
      } else {
        result.missing = true;
      }
    } catch (err) {
      result.missing = true;
    }
    DictionaryService.cache.set(key, result);
    return result;
  }
}

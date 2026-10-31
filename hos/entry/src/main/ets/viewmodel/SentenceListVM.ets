import { AppConfig } from '../core/config/AppConfig';
import { UiError } from '../core/error/UiError';
import { SessionStore } from '../core/session/SessionStore';
import { SentenceDto } from '../core/net/Dtos';
import { PracticeService } from '../core/service/PracticeService';

/**
 * 语料列表页状态。
 *
 * - 等级默认取账号 cefrLevel（C1 → B2 回退，服务端没有 C1 语料）；
 * - 空态/错误态/加载态都通过字段表达，页面不猜测；
 * - 儿童的 focus_phonemes 由服务端剥离，客户端也不渲染（双保险）。
 */
@Observed
export class SentenceListVM {
  levels: string[] = ['A1', 'A2', 'B1', 'B2'];
  level: string = 'A1';
  sentences: SentenceDto[] = [];
  isChild: boolean = false;

  loading: boolean = false;
  loadedOnce: boolean = false;
  hasError: boolean = false;
  error: UiError = new UiError('', '', '', false, '');

  async init(cefrLevel: string, isChild: boolean): Promise<void> {
    this.isChild = isChild;
    this.level = AppConfig.levelForCefr(cefrLevel);
    await this.load();
  }

  async selectLevel(level: string): Promise<void> {
    if (this.level === level) {
      return;
    }
    this.level = level;
    this.sentences = [];
    this.loadedOnce = false;
    await this.load();
  }

  async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.hasError = false;
    try {
      const list = await PracticeService.sentences(this.level);
      this.sentences = list;
      this.loadedOnce = true;
    } catch (err) {
      this.error = SessionStore.toUiError(err as Error, this.isChild);
      this.hasError = true;
    } finally {
      this.loading = false;
    }
  }

  isEmpty(): boolean {
    return this.loadedOnce && !this.loading && !this.hasError && this.sentences.length === 0;
  }
}

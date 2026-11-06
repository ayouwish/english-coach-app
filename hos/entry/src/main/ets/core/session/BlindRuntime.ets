import { SentenceDto } from '../net/Dtos';
import { PracticeService } from '../service/PracticeService';

/**
 * 盲测进行中的进程内状态（服务端是唯一事实来源，这里只做页面间传递与计数）。
 *
 * 流程：
 *   BlindTestPage「开始盲测」→ POST /blind-tests 拿到 sentence_ids
 *   → BlindRuntime.begin() → 回跟读 Tab（PracticePage 进入盲测模式：不显示分数）
 *   → 逐句 POST /attempts（带 blind_test_id）
 *   → 读完后回 BlindTestPage「结束并查看周报」→ finish → BlindRuntime.clear()
 */
export class BlindRuntime {
  static active: boolean = false;
  static testId: string = '';
  static sentenceIds: string[] = [];
  static total: number = 0;
  static submitted: number = 0;
  static scored: number = 0;
  static pending: number = 0;

  static begin(testId: string, sentenceIds: string[], total: number): void {
    BlindRuntime.active = true;
    BlindRuntime.testId = testId;
    BlindRuntime.sentenceIds = sentenceIds;
    BlindRuntime.total = total > 0 ? total : sentenceIds.length;
    BlindRuntime.submitted = 0;
    BlindRuntime.scored = 0;
    BlindRuntime.pending = 0;
    AppStorage.setOrCreate<boolean>('blind_active', true);
  }

  /** 记录一次已提交（返回是否全部读完）。 */
  static markSubmitted(): boolean {
    BlindRuntime.submitted = BlindRuntime.submitted + 1;
    if (BlindRuntime.submitted > BlindRuntime.total) {
      BlindRuntime.submitted = BlindRuntime.total;
    }
    return BlindRuntime.submitted >= BlindRuntime.total;
  }

  static clear(): void {
    BlindRuntime.active = false;
    BlindRuntime.testId = '';
    BlindRuntime.sentenceIds = [];
    BlindRuntime.total = 0;
    BlindRuntime.submitted = 0;
    BlindRuntime.scored = 0;
    BlindRuntime.pending = 0;
    AppStorage.setOrCreate<boolean>('blind_active', false);
  }

  /** 盲测抽题可能跨等级：把四个等级的语料合并后按 sentenceIds 顺序返回。 */
  static async loadSentences(): Promise<SentenceDto[]> {
    const levels: string[] = ['A1', 'A2', 'B1', 'B2'];
    const map = new Map<string, SentenceDto>();
    for (let i = 0; i < levels.length; i++) {
      try {
        const list = await PracticeService.sentences(levels[i]);
        for (let j = 0; j < list.length; j++) {
          map.set(list[j].id, list[j]);
        }
      } catch (err) {
        // 单个等级失败跳过（宁可少题也不阻塞）
      }
    }
    const ordered: SentenceDto[] = [];
    for (let i = 0; i < BlindRuntime.sentenceIds.length; i++) {
      const found = map.get(BlindRuntime.sentenceIds[i]);
      if (found !== undefined) {
        ordered.push(found);
      }
    }
    return ordered;
  }
}

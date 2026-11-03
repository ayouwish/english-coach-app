import { NavigationService } from '../router/NavigationService';
import { Routes } from '../router/Routes';
import { PracticeVM } from '../../viewmodel/PracticeVM';

/**
 * 跟读结果详情的跨页数据（push 一个全屏 NavDestination，而不是 bindContentCover）。
 *
 * 为什么不用 bindContentCover：真机上内容尺寸/安全区不稳定（标题被状态栏遮住、内容只占左上角），
 * 且弹层与 Swiper 状态互相影响；改成普通二级页后布局和返回行为都可控。
 */
export class PracticeResultStore {
  static vm: PracticeVM | null = null;
  static mode: string = 'result';
  /** 详情页点「再读一遍」→ 回到跟读页后自动开始录音 */
  static requestRecord: boolean = false;

  static open(vm: PracticeVM, mode: string): void {
    PracticeResultStore.vm = vm;
    PracticeResultStore.mode = mode;
    NavigationService.push(Routes.PRACTICE_RESULT);
  }

  static clear(): void {
    PracticeResultStore.vm = null;
  }

  static consumeRecordRequest(): boolean {
    const value = PracticeResultStore.requestRecord;
    PracticeResultStore.requestRecord = false;
    return value;
  }
}

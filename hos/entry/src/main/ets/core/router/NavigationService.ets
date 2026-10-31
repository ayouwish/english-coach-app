import { Routes } from './Routes';
import { SentenceDto } from '../net/Dtos';

/**
 * 唯一导航出口（entry 壳持有 NavPathStack，页面不直接操作栈）。
 *
 * M0 简化：跟读页的入参用「当前选中句子」的进程内单例传递，而不是 NavPathStack 的 param。
 * 原因：`navDestination` 的 @Builder 只接收 name，读 param 需要 NavDestinationContext，
 * 在单 HAP + 无 HAR 拆分的 M0 里不值得引入这层复杂度。
 * 待办：M1 拆 HAR 时改为 `pushPathByName(name, param)` + `onReady` 读取。
 */
/** 路由参数的占位类型：pushPathByName 的 param 需要 Object，不用字符串/null 以规避严格类型检查。 */
export class NavParam {
  name: string = '';

  constructor(name: string) {
    this.name = name;
  }
}

export class NavigationService {
  private static stack: NavPathStack | null = null;
  private static selectedSentence: SentenceDto | null = null;
  private static selectedLevel: string = 'A1';

  static bind(stack: NavPathStack): void {
    NavigationService.stack = stack;
  }

  static unbind(): void {
    NavigationService.stack = null;
  }

  static push(name: string): void {
    const stack = NavigationService.stack;
    if (stack === null) {
      return;
    }
    stack.pushPathByName(name, new NavParam(name));
  }

  static openPractice(sentence: SentenceDto, level: string): void {
    NavigationService.selectedSentence = sentence;
    NavigationService.selectedLevel = level;
    NavigationService.push(Routes.PRACTICE);
  }

  static practiceSentence(): SentenceDto | null {
    return NavigationService.selectedSentence;
  }

  static practiceLevel(): string {
    return NavigationService.selectedLevel;
  }

  static pop(): void {
    const stack = NavigationService.stack;
    if (stack === null) {
      return;
    }
    stack.pop();
  }

  static clear(): void {
    const stack = NavigationService.stack;
    if (stack === null) {
      return;
    }
    stack.clear();
  }

  static depth(): number {
    const stack = NavigationService.stack;
    if (stack === null) {
      return 0;
    }
    return stack.size();
  }
}

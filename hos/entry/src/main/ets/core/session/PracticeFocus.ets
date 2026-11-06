/**
 * 「专项练习」跨页参数：诊断页点「回跟读页练这几句」时，把 focus 音素写到 AppStorage，
 * 跟读 Tab 监听后按 `GET /sentences?focus=<token>` 重新加载语料。
 *
 * 为什么用 AppStorage 而不是 NavPathStack：跟读页是底部 Tab 根页，不是 push 出来的
 * NavDestination（见 pages/HomeTabs.ets）。
 */
export class PracticeFocus {
  static readonly KEY_TOKEN: string = 'practice_focus';
  static readonly KEY_VER: string = 'practice_focus_ver';

  static set(token: string): void {
    AppStorage.setOrCreate<string>(PracticeFocus.KEY_TOKEN, token);
    const current = AppStorage.get<number>(PracticeFocus.KEY_VER);
    const next = (current === undefined) ? 1 : current + 1;
    AppStorage.setOrCreate<number>(PracticeFocus.KEY_VER, next);
  }

  static clear(): void {
    PracticeFocus.set('');
  }

  static token(): string {
    const value = AppStorage.get<string>(PracticeFocus.KEY_TOKEN);
    return value === undefined ? '' : value;
  }
}

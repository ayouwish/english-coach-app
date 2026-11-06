/**
 * 「朗读这个故事」跨 Tab 请求：故事改写/详情页点朗读 → 连读 Tab 直接用这几句开始。
 *
 * 跟读/连读页都是底部 Tab 根页，不走 NavPathStack，故用 AppStorage 版本号触发。
 */
export class StoryReadRequest {
  static readonly KEY_VER: string = 'story_read_ver';
  static title: string = '';
  static materialId: string = '';
  static sentences: string[] = [];

  static set(title: string, materialId: string, sentences: string[]): void {
    StoryReadRequest.title = title;
    StoryReadRequest.materialId = materialId;
    StoryReadRequest.sentences = sentences;
    const current = AppStorage.get<number>(StoryReadRequest.KEY_VER);
    const next = (current === undefined) ? 1 : current + 1;
    AppStorage.setOrCreate<number>(StoryReadRequest.KEY_VER, next);
  }

  static clear(): void {
    StoryReadRequest.title = '';
    StoryReadRequest.materialId = '';
    StoryReadRequest.sentences = [];
  }

  static pending(): boolean {
    return StoryReadRequest.sentences.length > 0;
  }
}

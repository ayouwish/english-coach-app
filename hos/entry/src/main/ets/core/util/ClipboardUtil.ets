import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xEC00;
const TAG: string = 'Clipboard';

/** 复制纯文本到系统剪贴板（故事全文 / 建议导出等「只读文本」场景）。 */
export class ClipboardUtil {
  static async copy(text: string): Promise<boolean> {
    if (text.length === 0) {
      return false;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      return true;
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'copy failed: %{public}s', e.message);
      return false;
    }
  }
}

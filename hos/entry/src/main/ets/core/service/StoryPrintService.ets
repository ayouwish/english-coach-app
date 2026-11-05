import { image } from '@kit.ImageKit';
import { drawing } from '@kit.ArkGraphics2D';
import { print } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntime } from '../config/AppRuntime';
import { CacheService } from './CacheService';
import { FileUtil } from '../util/FileUtil';

const DOMAIN: number = 0xEC11;
const TAG: string = 'StoryPrint';

/** 打印用的故事内容（英文正文家庭可见；中文原文仅在创建者本人时传入）。 */
export class StoryPrintOptions {
  storyId: string = '';
  title: string = '';
  authorName: string = '';
  dateText: string = '';
  level: string = '';
  textEn: string = '';
  sourceZh: string = '';
}

/** 一行待排版的文本（先算好行，再按页切分）。 */
class PrintLine {
  text: string = '';
  size: number = 32;
  /** ARGB 颜色（不透明） */
  color: number = 0xFF222222;
  gapBefore: number = 0;
  height: number = 46;
}

/**
 * 故事打印：把故事渲染成 A4 比例的 PNG（每页一张），交给系统打印框架。
 *
 * 为什么用图片：`@ohos.print` 只接受 PDF / 图片；工程里没有 PDF 生成库，
 * 用 drawing 直接把文字画到 PixelMap 再编码 PNG 最稳（中英文都能显示）。
 */
export class StoryPrintService {
  private static readonly PAGE_W: number = 1240;
  private static readonly PAGE_H: number = 1754;
  private static readonly MARGIN: number = 90;
  private static readonly BODY_SIZE: number = 32;
  private static readonly BODY_LINE: number = 46;

  /** 生成打印页并调起系统打印。返回页数。 */
  static async printStory(opts: StoryPrintOptions): Promise<number> {
    const pages: string[] = await StoryPrintService.buildPages(opts);
    if (pages.length === 0) {
      throw new Error('没有可打印的内容');
    }
    const context = AppRuntime.requireContext();
    const task = await print.print(pages, context);
    task.on('succeed', () => {
      hilog.info(DOMAIN, TAG, 'print succeed');
    });
    task.on('fail', () => {
      hilog.warn(DOMAIN, TAG, 'print fail');
    });
    task.on('cancel', () => {
      hilog.info(DOMAIN, TAG, 'print cancel');
    });
    return pages.length;
  }

  /** 只生成图片（便于调试/后续分享）。 */
  static async buildPages(opts: StoryPrintOptions): Promise<string[]> {
    const lines: PrintLine[] = StoryPrintService.layoutLines(opts);
    if (lines.length === 0) {
      return [];
    }
    CacheService.ensureAll();
    const dir = CacheService.printDir();
    FileUtil.ensureDir(dir);
    const safeId = opts.storyId.length > 0 ? opts.storyId : 'story';
    const pages: string[] = [];
    let lineIndex = 0;
    let pageNo = 1;
    while (lineIndex < lines.length) {
      const pageLines: PrintLine[] = [];
      let y = StoryPrintService.MARGIN;
      const bottom = StoryPrintService.PAGE_H - StoryPrintService.MARGIN - 40;
      while (lineIndex < lines.length) {
        const line = lines[lineIndex];
        const need = line.gapBefore + line.height;
        if (pageLines.length > 0 && y + need > bottom) {
          break;
        }
        y += line.gapBefore;
        pageLines.push(line);
        y += line.height;
        lineIndex++;
      }
      const path = dir + '/story_' + safeId + '_p' + pageNo.toString() + '.png';
      await StoryPrintService.renderPage(pageLines, pageNo, path);
      pages.push(path);
      pageNo++;
      if (pageLines.length === 0) {
        break;
      }
    }
    return pages;
  }

  private static layoutLines(opts: StoryPrintOptions): PrintLine[] {
    const lines: PrintLine[] = [];
    const contentW = StoryPrintService.PAGE_W - StoryPrintService.MARGIN * 2;
    const titleFont = StoryPrintService.makeFont(46);
    const metaFont = StoryPrintService.makeFont(24);
    const bodyFont = StoryPrintService.makeFont(StoryPrintService.BODY_SIZE);
    const zhFont = StoryPrintService.makeFont(30);
    const headingFont = StoryPrintService.makeFont(32);

    lines.push(StoryPrintService.line(opts.title.length > 0 ? opts.title : '未命名故事',
      46, 0xFF1B1B2F, 0, 62));
    const meta: string[] = [];
    if (opts.authorName.length > 0) {
      meta.push('作者：' + opts.authorName);
    }
    if (opts.dateText.length > 0) {
      meta.push(opts.dateText);
    }
    if (opts.level.length > 0) {
      meta.push('等级 ' + opts.level);
    }
    if (meta.length > 0) {
      lines.push(StoryPrintService.line(meta.join(' · '), 24, 0xFF6B6B80, 4, 34));
    }
    lines.push(StoryPrintService.line('', 18, 0xFF6B6B80, 10, 18));

    const paragraphs = StoryPrintService.splitParagraphs(opts.textEn);
    for (let i = 0; i < paragraphs.length; i++) {
      const wrapped = StoryPrintService.wrap(paragraphs[i], bodyFont, contentW);
      for (let j = 0; j < wrapped.length; j++) {
        lines.push(StoryPrintService.line(wrapped[j], StoryPrintService.BODY_SIZE, 0xFF222222,
          j === 0 && i > 0 ? 14 : 0, StoryPrintService.BODY_LINE));
      }
    }

    if (opts.sourceZh.trim().length > 0) {
      lines.push(StoryPrintService.line('中文原文（仅自己可见）', 32, 0xFF5B4BD6, 26, 46));
      const zhParagraphs = StoryPrintService.splitParagraphs(opts.sourceZh);
      for (let i = 0; i < zhParagraphs.length; i++) {
        const wrapped = StoryPrintService.wrap(zhParagraphs[i], zhFont, contentW);
        for (let j = 0; j < wrapped.length; j++) {
          lines.push(StoryPrintService.line(wrapped[j], 30, 0xFF3A3A4A,
            j === 0 && i > 0 ? 12 : 0, 42));
        }
      }
    }
    // 标题字体只用于测量，避免未使用告警
    titleFont.measureText(opts.title, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    metaFont.measureText(meta.join(''), drawing.TextEncoding.TEXT_ENCODING_UTF8);
    headingFont.measureText('', drawing.TextEncoding.TEXT_ENCODING_UTF8);
    return lines;
  }

  private static line(text: string, size: number, color: number, gapBefore: number,
    height: number): PrintLine {
    const line = new PrintLine();
    line.text = text;
    line.size = size;
    line.color = color;
    line.gapBefore = gapBefore;
    line.height = height;
    return line;
  }

  private static splitParagraphs(text: string): string[] {
    const result: string[] = [];
    const normalized = text.replace(/\r\n/g, '\n');
    const parts = normalized.split('\n');
    for (let i = 0; i < parts.length; i++) {
      const trimmed = parts[i].trim();
      if (trimmed.length > 0) {
        result.push(trimmed);
      }
    }
    return result;
  }

  private static makeFont(size: number): drawing.Font {
    const font = new drawing.Font();
    font.setSize(size);
    return font;
  }

  /** 英文按单词换行；中文/超长单词按字符换行。 */
  private static wrap(text: string, font: drawing.Font, maxWidth: number): string[] {
    const lines: string[] = [];
    if (text.trim().length === 0) {
      return lines;
    }
    const hasCjk = /[\u4e00-\u9fa5]/.test(text);
    if (hasCjk) {
      let current = '';
      for (let i = 0; i < text.length; i++) {
        const ch = text.charAt(i);
        const candidate = current + ch;
        if (current.length > 0 && StoryPrintService.measure(font, candidate) > maxWidth) {
          lines.push(current);
          current = ch;
        } else {
          current = candidate;
        }
      }
      if (current.length > 0) {
        lines.push(current);
      }
      return lines;
    }
    const words = text.split(/\s+/);
    let current = '';
    for (let i = 0; i < words.length; i++) {
      const word = words[i];
      if (word.length === 0) {
        continue;
      }
      const candidate = current.length === 0 ? word : (current + ' ' + word);
      if (current.length > 0 && StoryPrintService.measure(font, candidate) > maxWidth) {
        lines.push(current);
        if (StoryPrintService.measure(font, word) > maxWidth) {
          // 超长单词：按字符拆
          let chunk = '';
          for (let k = 0; k < word.length; k++) {
            const ch = word.charAt(k);
            if (chunk.length > 0 && StoryPrintService.measure(font, chunk + ch) > maxWidth) {
              lines.push(chunk);
              chunk = ch;
            } else {
              chunk += ch;
            }
          }
          current = chunk;
        } else {
          current = word;
        }
      } else {
        current = candidate;
      }
    }
    if (current.length > 0) {
      lines.push(current);
    }
    return lines;
  }

  private static measure(font: drawing.Font, text: string): number {
    return font.measureText(text, drawing.TextEncoding.TEXT_ENCODING_UTF8);
  }

  private static async renderPage(lines: PrintLine[], pageNo: number, path: string): Promise<void> {
    const w = StoryPrintService.PAGE_W;
    const h = StoryPrintService.PAGE_H;
    const buffer = new ArrayBuffer(w * h * 4);
    const pixels = new Uint8Array(buffer);
    pixels.fill(255);
    const pm = await image.createPixelMap(buffer, {
      size: { width: w, height: h },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.OPAQUE,
      editable: true
    });
    try {
      const canvas = new drawing.Canvas(pm);
      const brush = new drawing.Brush();
      brush.setAntiAlias(true);
      canvas.attachBrush(brush);
      let y = StoryPrintService.MARGIN;
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        y += line.gapBefore;
        if (line.text.length > 0) {
          const font = StoryPrintService.makeFont(line.size);
          const blob = drawing.TextBlob.makeFromString(line.text, font,
            drawing.TextEncoding.TEXT_ENCODING_UTF8);
          brush.setColor(line.color);
          canvas.drawTextBlob(blob, StoryPrintService.MARGIN, y + line.size);
        }
        y += line.height;
      }
      // 页脚
      const footerFont = StoryPrintService.makeFont(22);
      const footer = 'english-coach · 第 ' + pageNo.toString() + ' 页';
      const footerBlob = drawing.TextBlob.makeFromString(footer, footerFont,
        drawing.TextEncoding.TEXT_ENCODING_UTF8);
      brush.setColor(0xFF9A9AAE);
      canvas.drawTextBlob(footerBlob, StoryPrintService.MARGIN, h - 54);
      canvas.detachBrush();
      const packer = image.createImagePacker();
      try {
        const encoded = await packer.packing(pm, { format: 'image/png', quality: 100 });
        FileUtil.writeBytesAtomic(path, new Uint8Array(encoded));
      } finally {
        packer.release();
      }
    } finally {
      pm.release();
    }
  }
}

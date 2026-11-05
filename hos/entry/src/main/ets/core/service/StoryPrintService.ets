import { image } from '@kit.ImageKit';
import { drawing } from '@kit.ArkGraphics2D';
import { print } from '@kit.BasicServicesKit';
import { fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
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

/** 打印结果：PDF 路径 + 页数。 */
export class StoryPrintResult {
  pdfPath: string = '';
  pageCount: number = 0;
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

/** 渲染好的一页：JPEG 字节用于嵌 PDF，也落一份图片便于排查。 */
class PrintPageAsset {
  jpeg: Uint8Array = new Uint8Array(0);
  imagePath: string = '';
}

/**
 * 故事打印。
 *
 * 实现要点：
 * - `@ohos.print` 对沙箱图片经常报「文件格式不支持」；
 * - 因此这里用 drawing 把故事画成 A4 页面（1240×1754），每页编码成 JPEG，
 *   再手工拼成**单文件 PDF**（JPEG 直接以 /DCTDecode 嵌入，无需压缩库）；
 * - 打印时只传这一个 PDF，兼容性最好；「另存为 PDF」也拿到同一个有效文件。
 */
export class StoryPrintService {
  private static readonly PAGE_W: number = 1240;
  private static readonly PAGE_H: number = 1754;
  private static readonly MARGIN: number = 90;
  private static readonly BODY_SIZE: number = 32;
  private static readonly BODY_LINE: number = 46;

  /** 生成 PDF 并调起系统打印。 */
  static async printStory(opts: StoryPrintOptions): Promise<StoryPrintResult> {
    const result = await StoryPrintService.buildPdf(opts);
    if (result.pdfPath.length === 0) {
      throw new Error('没有可打印的内容');
    }
    await StoryPrintService.printPdf(result.pdfPath);
    return result;
  }

  /** 调起系统打印（只传一个 PDF）。 */
  static async printPdf(pdfPath: string): Promise<void> {
    const context = AppRuntime.requireContext();
    const uris: string[] = [fileUri.getUriFromPath(pdfPath)];
    const task = await print.print(uris, context);
    task.on('succeed', () => {
      hilog.info(DOMAIN, TAG, 'print succeed');
    });
    task.on('fail', () => {
      hilog.warn(DOMAIN, TAG, 'print fail');
    });
    task.on('cancel', () => {
      hilog.info(DOMAIN, TAG, 'print cancel');
    });
  }

  /** 只生成 PDF（不调打印；导出/排查用）。 */
  static async buildPdf(opts: StoryPrintOptions): Promise<StoryPrintResult> {
    const result = new StoryPrintResult();
    const lines: PrintLine[] = StoryPrintService.layoutLines(opts);
    if (lines.length === 0) {
      return result;
    }
    CacheService.ensureAll();
    const dir = CacheService.printDir();
    FileUtil.ensureDir(dir);
    const safeId = opts.storyId.length > 0 ? opts.storyId : 'story';
    const assets: PrintPageAsset[] = [];
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
      const asset = await StoryPrintService.renderPage(pageLines, pageNo);
      asset.imagePath = dir + '/story_' + safeId + '_p' + pageNo.toString() + '.jpg';
      FileUtil.writeBytesAtomic(asset.imagePath, asset.jpeg);
      assets.push(asset);
      pageNo++;
      if (pageLines.length === 0) {
        break;
      }
    }
    if (assets.length === 0) {
      return result;
    }
    const pdfPath = dir + '/story_' + safeId + '.pdf';
    const pdfBytes = StoryPrintService.assemblePdf(assets);
    FileUtil.writeBytesAtomic(pdfPath, pdfBytes);
    result.pdfPath = pdfPath;
    result.pageCount = assets.length;
    return result;
  }

  private static layoutLines(opts: StoryPrintOptions): PrintLine[] {
    const lines: PrintLine[] = [];
    const contentW = StoryPrintService.PAGE_W - StoryPrintService.MARGIN * 2;
    const bodyFont = StoryPrintService.makeFont(StoryPrintService.BODY_SIZE);
    const zhFont = StoryPrintService.makeFont(30);

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

  private static async renderPage(lines: PrintLine[], pageNo: number): Promise<PrintPageAsset> {
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
    const asset = new PrintPageAsset();
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
      const footerFont = StoryPrintService.makeFont(22);
      const footer = 'english-coach · 第 ' + pageNo.toString() + ' 页';
      const footerBlob = drawing.TextBlob.makeFromString(footer, footerFont,
        drawing.TextEncoding.TEXT_ENCODING_UTF8);
      brush.setColor(0xFF9A9AAE);
      canvas.drawTextBlob(footerBlob, StoryPrintService.MARGIN, h - 54);
      canvas.detachBrush();
      const packer = image.createImagePacker();
      try {
        // PDF 里用 JPEG 最省事：/DCTDecode 可直接嵌入，无需 zlib
        const encoded = await packer.packing(pm, { format: 'image/jpeg', quality: 90 });
        asset.jpeg = new Uint8Array(encoded);
      } finally {
        packer.release();
      }
    } finally {
      pm.release();
    }
    return asset;
  }

  // ------------------------------------------------------------------ PDF 拼装

  private static assemblePdf(assets: PrintPageAsset[]): Uint8Array {
    const chunks: Uint8Array[] = [];
    let length = 0;
    const encoder = new util.TextEncoder();
    const pushText = (text: string): void => {
      const bytes = encoder.encodeInto(text);
      chunks.push(bytes);
      length += bytes.length;
    };
    const pushBytes = (bytes: Uint8Array): void => {
      chunks.push(bytes);
      length += bytes.length;
    };
    const offsets: number[] = [];
    const objectCount = 2 + assets.length * 3;
    const mark = (): void => {
      offsets.push(length);
    };

    pushText('%PDF-1.4\n%\u00E2\u00E3\u00CF\u00D3\n');

    // obj 1: catalog
    mark();
    pushText('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    // obj 2: pages
    mark();
    let kids = '';
    for (let i = 0; i < assets.length; i++) {
      kids += (3 + i * 3).toString() + ' 0 R ';
    }
    pushText('2 0 obj\n<< /Type /Pages /Kids [' + kids + '] /Count ' + assets.length.toString() +
      ' >>\nendobj\n');

    for (let i = 0; i < assets.length; i++) {
      const pageObj = 3 + i * 3;
      const imageObj = 4 + i * 3;
      const contentObj = 5 + i * 3;
      const content = 'q 595.28 0 0 841.89 0 0 cm /Im0 Do Q\n';
      // page
      mark();
      pushText(pageObj.toString() + ' 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] ' +
        '/Resources << /XObject << /Im0 ' + imageObj.toString() + ' 0 R >> >> /Contents ' +
        contentObj.toString() + ' 0 R >>\nendobj\n');
      // image xobject (JPEG)
      mark();
      const jpeg = assets[i].jpeg;
      pushText(imageObj.toString() + ' 0 obj\n<< /Type /XObject /Subtype /Image /Width ' +
        StoryPrintService.PAGE_W.toString() + ' /Height ' + StoryPrintService.PAGE_H.toString() +
        ' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ' +
        jpeg.length.toString() + ' >>\nstream\n');
      pushBytes(jpeg);
      pushText('\nendstream\nendobj\n');
      // content
      mark();
      pushText(contentObj.toString() + ' 0 obj\n<< /Length ' + content.length.toString() +
        ' >>\nstream\n' + content + 'endstream\nendobj\n');
    }

    const xrefOffset = length;
    let xref = 'xref\n0 ' + (objectCount + 1).toString() + '\n0000000000 65535 f \n';
    for (let i = 0; i < offsets.length; i++) {
      xref += StoryPrintService.pad10(offsets[i]) + ' 00000 n \n';
    }
    xref += 'trailer\n<< /Size ' + (objectCount + 1).toString() + ' /Root 1 0 R >>\nstartxref\n' +
      xrefOffset.toString() + '\n%%EOF\n';
    pushText(xref);
    return StoryPrintService.concat(chunks, length);
  }

  private static pad10(value: number): string {
    let text = value.toString();
    while (text.length < 10) {
      text = '0' + text;
    }
    return text;
  }

  private static concat(chunks: Uint8Array[], total: number): Uint8Array {
    const out = new Uint8Array(total);
    let offset = 0;
    for (let i = 0; i < chunks.length; i++) {
      out.set(chunks[i], offset);
      offset += chunks[i].length;
    }
    return out;
  }
}

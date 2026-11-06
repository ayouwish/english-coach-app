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
  /** 'full'（A4 整页）| 'card'（A5 打印卡片，带虚线裁切框/书写栏） */
  layout: string = 'full';
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

/** 页面版式：整页 A4 / 卡片 A5。 */
class PrintSpec {
  w: number = 1240;
  h: number = 1754;
  margin: number = 90;
  mediaW: number = 595.28;
  mediaH: number = 841.89;
  titleSize: number = 46;
  titleLine: number = 62;
  metaSize: number = 24;
  metaLine: number = 34;
  bodySize: number = 32;
  bodyLine: number = 46;
  zhSize: number = 30;
  zhLine: number = 42;
  footerSize: number = 22;
  footerOffset: number = 54;
  card: boolean = false;
}

/**
 * 故事打印。
 *
 * - 用 drawing 把故事画成页面（A4 整页 / A5 卡片），每页编码 JPEG；
 * - 手工拼成**单文件 PDF**（JPEG 以 /DCTDecode 嵌入），再交给系统打印；
 * - 只传一个 PDF，避免打印框架对沙箱图片报「文件格式不支持」。
 */
export class StoryPrintService {
  private static readonly FULL: PrintSpec = StoryPrintService.makeFullSpec();
  private static readonly CARD: PrintSpec = StoryPrintService.makeCardSpec();

  private static makeFullSpec(): PrintSpec {
    const spec = new PrintSpec();
    spec.w = 1240;
    spec.h = 1754;
    spec.margin = 90;
    spec.mediaW = 595.28;
    spec.mediaH = 841.89;
    spec.titleSize = 46;
    spec.titleLine = 62;
    spec.metaSize = 24;
    spec.metaLine = 34;
    spec.bodySize = 32;
    spec.bodyLine = 46;
    spec.zhSize = 30;
    spec.zhLine = 42;
    spec.footerSize = 22;
    spec.footerOffset = 54;
    spec.card = false;
    return spec;
  }

  /** A5 148×210mm @150dpi = 874×1240；带虚线裁切框与姓名/日期书写栏。 */
  private static makeCardSpec(): PrintSpec {
    const spec = new PrintSpec();
    spec.w = 874;
    spec.h = 1240;
    spec.margin = 64;
    spec.mediaW = 419.53;
    spec.mediaH = 595.28;
    spec.titleSize = 36;
    spec.titleLine = 48;
    spec.metaSize = 20;
    spec.metaLine = 28;
    spec.bodySize = 24;
    spec.bodyLine = 34;
    spec.zhSize = 18;
    spec.zhLine = 26;
    spec.footerSize = 18;
    spec.footerOffset = 36;
    spec.card = true;
    return spec;
  }

  private static specFor(layout: string): PrintSpec {
    return layout === 'card' ? StoryPrintService.CARD : StoryPrintService.FULL;
  }

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
    const spec = StoryPrintService.specFor(opts.layout);
    const lines: PrintLine[] = StoryPrintService.layoutLines(opts, spec);
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
      let y = spec.margin + (spec.card ? 24 : 0);
      const bottom = spec.h - spec.margin - (spec.card ? 54 : 40);
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
      const asset = await StoryPrintService.renderPage(pageLines, pageNo, spec);
      const suffix = spec.card ? '_card' : '';
      asset.imagePath = dir + '/story_' + safeId + suffix + '_p' + pageNo.toString() + '.jpg';
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
    const suffix = spec.card ? '_card' : '';
    const pdfPath = dir + '/story_' + safeId + suffix + '.pdf';
    const pdfBytes = StoryPrintService.assemblePdf(assets, spec);
    FileUtil.writeBytesAtomic(pdfPath, pdfBytes);
    result.pdfPath = pdfPath;
    result.pageCount = assets.length;
    return result;
  }

  private static layoutLines(opts: StoryPrintOptions, spec: PrintSpec): PrintLine[] {
    const lines: PrintLine[] = [];
    const contentW = spec.w - spec.margin * 2;
    const bodyFont = StoryPrintService.makeFont(spec.bodySize);
    const zhFont = StoryPrintService.makeFont(spec.zhSize);

    lines.push(StoryPrintService.line(opts.title.length > 0 ? opts.title : '未命名故事',
      spec.titleSize, 0xFF1B1B2F, 0, spec.titleLine));
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
      lines.push(StoryPrintService.line(meta.join(' · '), spec.metaSize, 0xFF6B6B80, 4, spec.metaLine));
    }
    lines.push(StoryPrintService.line('', spec.metaSize, 0xFF6B6B80, spec.card ? 8 : 10, 16));

    const paragraphs = StoryPrintService.splitParagraphs(opts.textEn);
    if (spec.card) {
      // 卡片：编号句子（方便孩子逐句读）
      for (let i = 0; i < paragraphs.length; i++) {
        const prefix = (i + 1).toString() + '. ';
        const wrapped = StoryPrintService.wrap(prefix + paragraphs[i], bodyFont, contentW);
        for (let j = 0; j < wrapped.length; j++) {
          lines.push(StoryPrintService.line(wrapped[j], spec.bodySize, 0xFF222222,
            j === 0 && i > 0 ? 8 : 0, spec.bodyLine));
        }
      }
    } else {
      for (let i = 0; i < paragraphs.length; i++) {
        const wrapped = StoryPrintService.wrap(paragraphs[i], bodyFont, contentW);
        for (let j = 0; j < wrapped.length; j++) {
          lines.push(StoryPrintService.line(wrapped[j], spec.bodySize, 0xFF222222,
            j === 0 && i > 0 ? 14 : 0, spec.bodyLine));
        }
      }
    }

    if (opts.sourceZh.trim().length > 0) {
      lines.push(StoryPrintService.line(spec.card ? '中文原文' : '中文原文（仅自己可见）',
        spec.card ? 22 : 32, 0xFF5B4BD6, spec.card ? 16 : 26, spec.card ? 30 : 46));
      const zhParagraphs = StoryPrintService.splitParagraphs(opts.sourceZh);
      for (let i = 0; i < zhParagraphs.length; i++) {
        const wrapped = StoryPrintService.wrap(zhParagraphs[i], zhFont, contentW);
        for (let j = 0; j < wrapped.length; j++) {
          lines.push(StoryPrintService.line(wrapped[j], spec.zhSize, 0xFF3A3A4A,
            j === 0 && i > 0 ? 10 : 0, spec.zhLine));
        }
      }
    }

    if (spec.card) {
      lines.push(StoryPrintService.line('', 18, 0xFF6B6B80, 22, 18));
      lines.push(StoryPrintService.line('姓名：________________    日期：________________',
        20, 0xFF6B6B80, 0, 30));
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

  private static async renderPage(lines: PrintLine[], pageNo: number,
    spec: PrintSpec): Promise<PrintPageAsset> {
    const w = spec.w;
    const h = spec.h;
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
      if (spec.card) {
        StoryPrintService.drawDashedFrame(canvas, spec);
      }
      const brush = new drawing.Brush();
      brush.setAntiAlias(true);
      canvas.attachBrush(brush);
      let y = spec.margin + (spec.card ? 24 : 0);
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        y += line.gapBefore;
        if (line.text.length > 0) {
          const font = StoryPrintService.makeFont(line.size);
          const blob = drawing.TextBlob.makeFromString(line.text, font,
            drawing.TextEncoding.TEXT_ENCODING_UTF8);
          brush.setColor(line.color);
          canvas.drawTextBlob(blob, spec.margin, y + line.size);
        }
        y += line.height;
      }
      const footerFont = StoryPrintService.makeFont(spec.footerSize);
      const footer = spec.card
        ? 'english-coach · 故事卡片 · 第 ' + pageNo.toString() + ' 页'
        : 'english-coach · 第 ' + pageNo.toString() + ' 页';
      const footerBlob = drawing.TextBlob.makeFromString(footer, footerFont,
        drawing.TextEncoding.TEXT_ENCODING_UTF8);
      brush.setColor(0xFF9A9AAE);
      canvas.drawTextBlob(footerBlob, spec.margin, h - spec.footerOffset);
      canvas.detachBrush();
      const packer = image.createImagePacker();
      try {
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

  /** 卡片外圈虚线裁切框（A5 卡片用）。 */
  private static drawDashedFrame(canvas: drawing.Canvas, spec: PrintSpec): void {
    const inset = 26;
    const left = inset;
    const top = inset;
    const right = spec.w - inset;
    const bottom = spec.h - inset;
    const pen = new drawing.Pen();
    pen.setAntiAlias(true);
    pen.setStrokeWidth(1.5);
    pen.setColor(0xFFB9B9CC);
    canvas.attachPen(pen);
    const dash = 12;
    const gap = 8;
    let x = left;
    while (x < right) {
      const x2 = Math.min(x + dash, right);
      canvas.drawLine(x, top, x2, top);
      canvas.drawLine(x, bottom, x2, bottom);
      x += dash + gap;
    }
    let y = top;
    while (y < bottom) {
      const y2 = Math.min(y + dash, bottom);
      canvas.drawLine(left, y, left, y2);
      canvas.drawLine(right, y, right, y2);
      y += dash + gap;
    }
    canvas.detachPen();
  }

  // ------------------------------------------------------------------ PDF 拼装

  private static assemblePdf(assets: PrintPageAsset[], spec: PrintSpec): Uint8Array {
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

    mark();
    pushText('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    mark();
    let kids = '';
    for (let i = 0; i < assets.length; i++) {
      kids += (3 + i * 3).toString() + ' 0 R ';
    }
    pushText('2 0 obj\n<< /Type /Pages /Kids [' + kids + '] /Count ' + assets.length.toString() +
      ' >>\nendobj\n');

    const mediaW = spec.mediaW.toString();
    const mediaH = spec.mediaH.toString();
    for (let i = 0; i < assets.length; i++) {
      const pageObj = 3 + i * 3;
      const imageObj = 4 + i * 3;
      const contentObj = 5 + i * 3;
      const content = 'q ' + mediaW + ' 0 0 ' + mediaH + ' 0 0 cm /Im0 Do Q\n';
      mark();
      pushText(pageObj.toString() + ' 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' +
        mediaW + ' ' + mediaH + '] /Resources << /XObject << /Im0 ' + imageObj.toString() +
        ' 0 R >> >> /Contents ' + contentObj.toString() + ' 0 R >>\nendobj\n');
      mark();
      const jpeg = assets[i].jpeg;
      pushText(imageObj.toString() + ' 0 obj\n<< /Type /XObject /Subtype /Image /Width ' +
        spec.w.toString() + ' /Height ' + spec.h.toString() +
        ' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ' +
        jpeg.length.toString() + ' >>\nstream\n');
      pushBytes(jpeg);
      pushText('\nendstream\nendobj\n');
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

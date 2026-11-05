import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcSpace } from '../design/DesignTokens';
import { NavState } from '../core/router/NavState';
import { NavigationService } from '../core/router/NavigationService';
import { StoryReadRequest } from '../core/session/StoryReadRequest';
import { Routes } from '../core/router/Routes';
import { SessionState, SessionStore } from '../core/session/SessionStore';
import { StoryRetellRecord, StorySentenceItem } from '../core/net/StoryDtos';
import { StoryDetailVM, StoryRuntime } from '../viewmodel/StoryVM';
import { StoryService } from '../core/service/StoryService';
import { StoryPrintOptions, StoryPrintService } from '../core/service/StoryPrintService';
import { ClipboardUtil } from '../core/util/ClipboardUtil';
import { fileIo, picker } from '@kit.CoreFileKit';
import { AppRuntime } from '../core/config/AppRuntime';
import { WordText } from '../components/WordText';
import { CapabilityCache } from '../core/content/CapabilityCache';

/**
 * 故事详情：英文全文 + 中文对照 + 插画（提示词可见）+ 整段朗读回放 + 复述入口。
 *
 * 两个线上限制已内置：
 * - 整段朗读回放来自「连读/跟读」的 attempts，没读过就是 no_audio（隐藏播放器，给可读提示）；
 * - 「我当时讲的原话」只有本次会话刚录的音（StoryRuntime 内存），UI 标注「本次可用」。
 */
@Component
export struct StoryDetailPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @StorageProp('storyRetellTick') @Watch('onRetellTick') retellTick: number = 0;
  @State vm: StoryDetailVM = new StoryDetailVM();
  @State renameShown: boolean = false;
  @State renameText: string = '';
  @State actionBusy: boolean = false;
  @State actionError: string = '';
  /** 打印：生成 A4 图片 + 调起系统打印 */
  @State printBusy: boolean = false;
  /** capabilities.image=false 时隐藏画图入口（README §2.4） */
  @State imageCapable: boolean = true;
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    this.vm.configure(this.session.isChild, this.session.userId);
    const id = NavState.story.storyId;
    if (id.length === 0) {
      this.vm.loading = false;
      this.vm.loadError = '没有找到这个故事，返回故事集重新打开试试';
      return;
    }
    void this.vm.load(id);
    void this.loadCapabilities();
  }

  onRetellTick(): void {
    if (this.started) {
      this.vm.refreshRetells();
    }
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  private async loadCapabilities(): Promise<void> {
    await CapabilityCache.ensure();
    this.imageCapable = CapabilityCache.image;
  }

  private openReview(): void {
    NavState.setStory(this.vm.storyId, null);
    NavigationService.push(Routes.STORY_REVIEW);
  }

  /** 朗读这个故事：把故事句子交给连读 Tab，一句一句读并自动评分。 */
  private readAloud(): void {
    const texts: string[] = [];
    for (let i = 0; i < this.vm.sentences.length; i++) {
      texts.push(this.vm.sentences[i].en);
    }
    if (texts.length === 0) {
      return;
    }
    StoryReadRequest.set(this.vm.title, this.vm.storyId, texts);
    AppStorage.setOrCreate<number>('tab_index', 1);
    NavigationService.clear();
  }

  // ------------------------------------------------------------------ 头部

  /** 改名/删除（服务端只允许改删自己录入的故事）。 */
  private async saveRename(): Promise<void> {
    const title = this.renameText.trim();
    if (title.length === 0) {
      this.actionError = '标题不能为空';
      return;
    }
    if (this.actionBusy) {
      return;
    }
    this.actionBusy = true;
    this.actionError = '';
    try {
      await StoryService.renameMaterial(this.vm.storyId, title);
      this.vm.title = title;
      this.renameShown = false;
      StoryRuntime.notifySaved();
    } catch (err) {
      this.actionError = SessionStore.toUiError(err as Error, this.session.isChild).message;
    } finally {
      this.actionBusy = false;
    }
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除这个故事？',
      message: '删除后全家都看不到这个故事了，无法恢复。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.ec_bad_text'),
        action: () => {
          void this.doDelete();
        }
      }
    });
  }

  private async doDelete(): Promise<void> {
    if (this.actionBusy) {
      return;
    }
    this.actionBusy = true;
    this.actionError = '';
    try {
      await StoryService.deleteMaterial(this.vm.storyId);
      StoryRuntime.notifySaved();
      NavigationService.pop();
    } catch (err) {
      this.actionError = SessionStore.toUiError(err as Error, this.session.isChild).message;
    } finally {
      this.actionBusy = false;
    }
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.vm.title)
          .fontSize(this.session.isChild ? EcFont.childH1 : EcFont.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        if (!this.session.isChild) {
          Text('改名')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .accessibilityText('重命名故事')
            .onClick(() => {
              this.renameText = this.vm.title;
              this.renameShown = true;
              this.actionError = '';
            })
          Text('删除')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_bad_text'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .accessibilityText('删除故事')
            .onClick(() => {
              this.confirmDelete();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.renameShown) {
        Row({ space: EcSpace.x2 }) {
          TextInput({ text: this.renameText, placeholder: '故事标题' })
            .layoutWeight(1)
            .height(40)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.sm)
            .onChange((value: string) => {
              this.renameText = value;
            })
          EcButton({
            label: this.actionBusy ? '保存中…' : '保存',
            kind: EcButtonKind.TONAL,
            btnWidth: '22%',
            loading: this.actionBusy,
            onTap: () => {
              void this.saveRename();
            }
          })
          Text('取消')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .onClick(() => {
              this.renameShown = false;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      if (this.actionError.length > 0) {
        Text(this.actionError)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }

      Row({ space: EcSpace.x1 }) {
        if (this.vm.level.length > 0) {
          Chip({ text: this.vm.level, tone: 'primary' })
        }
        if (this.vm.sentenceCount > 0) {
          Chip({ text: this.vm.sentenceCount.toString() + ' 句' })
        }
        if (this.vm.dateText.length > 0) {
          Text(this.vm.dateText)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        if (this.vm.authorName.length > 0) {
          Text('· ' + this.vm.authorName + ' 的故事')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ------------------------------------------------------------------ 英文全文

  /** 复制英文全文（手机端替代 Web 的打印/分享）。 */
  private async copyStory(): Promise<void> {
    const parts: string[] = [];
    for (let i = 0; i < this.vm.sentences.length; i++) {
      const text = this.vm.sentences[i].en.trim();
      if (text.length > 0) {
        parts.push(text);
      }
    }
    if (parts.length === 0) {
      return;
    }
    const ok = await ClipboardUtil.copy(parts.join('\n'));
    this.getUIContext().getPromptAction().showToast({ message: ok ? '已复制英文全文' : '复制失败，请重试' });
  }

  /** 打印这个故事：生成 PDF 后调起系统打印（中文原文仅创建者本人会带上）。 */
  private async printStory(): Promise<void> {
    if (this.printBusy || this.vm.textEn.trim().length === 0) {
      return;
    }
    this.printBusy = true;
    let pdfPath = '';
    let pageCount = 0;
    try {
      const opts = new StoryPrintOptions();
      opts.storyId = this.vm.storyId;
      opts.title = this.vm.title;
      opts.authorName = this.vm.authorName;
      opts.dateText = this.vm.dateText;
      opts.level = this.vm.level;
      opts.textEn = this.vm.textEn;
      opts.sourceZh = this.vm.canSeeSource() ? this.vm.sourceZh : '';
      const result = await StoryPrintService.buildPdf(opts);
      pdfPath = result.pdfPath;
      pageCount = result.pageCount;
      if (pageCount === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '这个故事还没有可打印的内容' });
        return;
      }
      await StoryPrintService.printPdf(pdfPath);
      this.getUIContext().getPromptAction().showToast({
        message: '已打开打印（' + pageCount.toString() + ' 页 PDF）'
      });
    } catch (err) {
      // 打印框架异常时仍保留已生成的 PDF：让用户导出后用 WPS/文件打印
      if (pdfPath.length > 0) {
        this.promptExport(pdfPath, pageCount);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '打印失败，请重试' });
      }
    } finally {
      this.printBusy = false;
    }
  }

  private promptExport(pdfPath: string, pageCount: number): void {
    this.getUIContext().showAlertDialog({
      title: '系统打印面板打不开',
      message: '已生成 ' + pageCount.toString() + ' 页 PDF，可以导出后用 WPS/文件里的打印功能打印。',
      buttons: [
        {
          value: '导出 PDF',
          action: () => {
            void this.exportPdf(pdfPath);
          }
        },
        {
          value: '取消',
          action: () => {
          }
        }
      ]
    });
  }

  /** 把 PDF 复制到用户选的位置（文档选择器，不需要额外权限）。 */
  private async exportPdf(pdfPath: string): Promise<void> {
    try {
      const context = AppRuntime.requireContext();
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSaveOptions();
      const safeTitle = this.vm.title.length > 0 ? this.vm.title : '故事';
      options.newFileNames = ['故事-' + safeTitle + '.pdf'];
      const uris = await documentPicker.save(options);
      if (uris === undefined || uris.length === 0) {
        return;
      }
      const src = fileIo.openSync(pdfPath, fileIo.OpenMode.READ_ONLY);
      try {
        const size = fileIo.statSync(pdfPath).size;
        const buffer = new ArrayBuffer(size);
        fileIo.readSync(src.fd, buffer);
        const dst = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(dst.fd, buffer);
        } finally {
          fileIo.closeSync(dst);
        }
      } finally {
        fileIo.closeSync(src);
      }
      this.getUIContext().getPromptAction().showToast({ message: '已导出 PDF' });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败，请重试' });
    }
  }

  @Builder
  englishCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.session.isChild ? '📖 故事正文' : '英文全文')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        if (!this.session.isChild) {
          Text('复制全文')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .accessibilityText('复制英文全文')
            .onClick(() => {
              void this.copyStory();
            })
        }
        Text(this.printBusy ? '🖨️ 生成中…' : '🖨️ 打印')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText('打印故事')
          .onClick(() => {
            void this.printStory();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Column({ space: EcSpace.x2 }) {
        ForEach(this.vm.sentences, (item: StorySentenceItem) => {
          Row({ space: EcSpace.x2 }) {
            Text(item.index.toString() + '.')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_primary'))
              .width(22)
              .textAlign(TextAlign.End)
              .margin({ top: 3 })
            WordText({
              text: item.en,
              fontSizeVp: this.session.isChild ? EcFont.childBody : EcFont.body,
              lineHeightVp: this.session.isChild ? 30 : 26
            })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (item: StorySentenceItem) => 'e_' + item.index.toString())
      }
      .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  sourceCard() {
    if (this.vm.canSeeSource()) {
      Column({ space: EcSpace.x2 }) {
        Row({ space: EcSpace.x1 }) {
          Text('🗒️ 看看你当时怎么讲的（中文）')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .layoutWeight(1)
          Text(this.vm.showSource ? '收起' : '展开')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.vm.toggleSource();
        })
        if (this.vm.showSource) {
          Text(this.vm.sourceZh)
            .fontSize(EcFont.body)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.md)
            .padding(EcSpace.x3)
        }
      }
      .width('100%')
      .padding(EcSpace.x4)
      .backgroundColor($r('app.color.ec_surface'))
      .borderRadius(EcRadius.lg)
      .alignItems(HorizontalAlign.Start)
    }
  }

  // ------------------------------------------------------------------ 插画

  @Builder
  imageCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.session.isChild ? '🎨 给我的故事画张画' : '🖼️ 故事插画')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
        Blank()
        if (this.vm.hasImage) {
          Text('✅ 已生成')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_good_text'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.imageLoading) {
        LoadingBlock({ text: '🎨 正在画插画… 大约 10–30 秒', subText: '可以先看文字或听朗读' })
      } else if (this.vm.imagePath.length > 0) {
        // 插画是 1:1（服务端 1280×1280）：用 Contain + 限高，避免 Cover 裁成一条横带
        Image('file://' + this.vm.imagePath)
          .width('100%')
          .height(340)
          .objectFit(ImageFit.Contain)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .onError(() => {
            this.vm.reportImageError();
          })
        if (this.vm.imagePrompt.length > 0) {
          Row({ space: EcSpace.x1 }) {
            Text('🖼️ 生成用的提示词')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_primary'))
            Text(this.vm.showPrompt ? '收起' : '展开')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.vm.togglePrompt();
          })
          if (this.vm.showPrompt) {
            Text(this.vm.imagePrompt)
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
              .backgroundColor($r('app.color.ec_surface_alt'))
              .borderRadius(EcRadius.sm)
              .padding(EcSpace.x2)
          }
        }
        if (this.imageCapable) {
          Row({ space: EcSpace.x2 }) {
            EcButton({
              label: this.vm.imageLoading ? '画中…' : '🖼️ 换一张',
              kind: EcButtonKind.TONAL,
              btnWidth: '52%',
              disabled: this.vm.imageLoading,
              onTap: () => {
                void this.vm.illustrate(true);
              }
            })
            Text('每张约 ¥0.1')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }

      if (this.vm.imageError.length > 0) {
        Text(this.vm.imageError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
        if (this.vm.hasImage) {
          EcButton({
            label: this.vm.imageLoading ? '加载中…' : '重新加载插画',
            kind: EcButtonKind.TONAL,
            btnWidth: '100%',
            disabled: this.vm.imageLoading,
            onTap: () => {
              void this.vm.reloadImage();
            }
          })
        } else if (this.imageCapable) {
          EcButton({
            label: '🖼️ 给我画一张',
            kind: EcButtonKind.TONAL,
            btnWidth: '100%',
            disabled: this.vm.imageLoading,
            onTap: () => {
              void this.vm.illustrate(true);
            }
          })
        }
      } else if (this.vm.imagePath.length === 0 && !this.vm.imageLoading && this.imageCapable) {
        EcButton({
          label: '🖼️ 给我画一张',
          kind: EcButtonKind.TONAL,
          btnWidth: '100%',
          onTap: () => {
            void this.vm.illustrate(false);
          }
        })
      } else if (!this.imageCapable && !this.vm.hasImage) {
        Text('插画服务暂未启用（服务端 capabilities.image=false），先读故事、听朗读吧。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  // ------------------------------------------------------------------ 整段朗读回放

  @Builder
  audioCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('🎧 ' + (this.session.isChild ? '听一听我读的故事' : '整段朗读回放'))
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
        Blank()
        if (this.vm.audioDurationText.length > 0 && this.vm.audioState === 'ready') {
          Text(this.vm.audioDurationText)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.audioState === 'checking') {
        LoadingBlock({ text: '正在检查朗读录音…' })
      } else {
        Row({ space: EcSpace.x2 }) {
          if (this.vm.audioState === 'building') {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('app.color.ec_primary'))
          }
          Text(this.vm.audioStatusText)
            .fontSize(EcFont.caption)
            .fontColor(this.vm.audioState === 'ready' || this.vm.audioState === 'building'
              ? $r('app.color.ec_muted') : $r('app.color.ec_warn_text'))
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      if (this.vm.audioState === 'ready') {
        EcButton({
          label: this.vm.audioPlaying ? '播放中…' : (this.vm.audioLoading ? '准备中…' : '▶ 播放整段朗读'),
          kind: EcButtonKind.PRIMARY,
          loading: this.vm.audioLoading,
          onTap: () => {
            void this.vm.playAudio();
          }
        })
      } else if (this.vm.audioState === 'failed') {
        EcButton({
          label: '🔄 重新生成整段朗读',
          kind: EcButtonKind.TONAL,
          onTap: () => {
            void this.vm.retryAudio();
          }
        })
      }
      if (this.vm.audioError.length > 0) {
        Text(this.vm.audioError)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
      Text('说明：整段朗读来自你的连读/跟读录音；没读过就是空的。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  // ------------------------------------------------------------------ 原声（仅本次会话）

  @Builder
  originalCard() {
    if (this.vm.originalPath.length > 0) {
      Column({ space: EcSpace.x2 }) {
        Row({ space: EcSpace.x2 }) {
          Text('🎙️ 我当时讲的原话')
            .fontSize(EcFont.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_ink'))
          Blank()
          Chip({ text: '本次录音 · 仅本次可用', tone: 'warn' })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        if (this.vm.originalText.length > 0) {
          Text(this.vm.originalText)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        EcButton({
          label: this.vm.originalPlaying ? '播放中…' : '▶ 听我讲的中文原声',
          kind: EcButtonKind.TONAL,
          onTap: () => {
            void this.vm.playOriginal();
          }
        })
        Text('线上暂时没有保存故事原始录音的接口，所以关掉 App 后这段就听不到了。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      .width('100%')
      .padding(EcSpace.x4)
      .backgroundColor($r('app.color.ec_surface'))
      .borderRadius(EcRadius.lg)
      .alignItems(HorizontalAlign.Start)
    }
  }

  // ------------------------------------------------------------------ 复述

  @Builder
  retellCard() {
    Column({ space: EcSpace.x3 }) {
      Row({ space: EcSpace.x2 }) {
        Column({ space: 2 }) {
          Text(this.session.isChild ? '📖 念念这个故事' : '📖 朗读这个故事')
            .fontSize(EcFont.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
          Text('一句一句读，读完自动出分并汇总（连读模式）')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        EcButton({
          label: this.session.isChild ? '开念' : '开始朗读',
          kind: EcButtonKind.TONAL,
          btnWidth: '112vp',
          onTap: () => {
            this.readAloud();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider().color($r('app.color.ec_border'))

      Row({ space: EcSpace.x2 }) {
        Column({ space: 2 }) {
          Text('🎤 讲给我听')
            .fontSize(EcFont.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
          Text('不看屏幕，用 2–3 句话把故事讲一遍 🙂')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        EcButton({
          label: this.vm.retells.length > 0 ? '再复述一次' : '去复述',
          kind: EcButtonKind.PRIMARY,
          btnWidth: '112vp',
          onTap: () => {
            this.openReview();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.retells.length > 0) {
        Text('这次会话的复述记录')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        ForEach(this.vm.retells, (record: StoryRetellRecord, index: number) => {
          Column({ space: EcSpace.x1 }) {
            Row({ space: EcSpace.x2 }) {
              if (this.session.isChild) {
                Text('你真棒！讲到了 ' + record.coveredCount.toString() + ' 个关键点')
                  .fontSize(EcFont.caption)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ec_good_text'))
              } else {
                Text('覆盖度 ' + (record.coverage < 0 ? '—' : record.coverage.toString() + '%') +
                  ' · 讲到了 ' + record.coveredCount.toString() + ' 个关键点')
                  .fontSize(EcFont.caption)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ec_ink'))
              }
              Blank()
              Text(record.createdAt)
                .fontSize(EcFont.micro)
                .fontColor($r('app.color.ec_muted'))
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            if (record.feedbackZh.length > 0) {
              Text(record.feedbackZh)
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_muted'))
                .width('100%')
            }
            if (record.missingPoints.length > 0) {
              Text('下一次可以试试：' + record.missingPoints.join('、'))
                .fontSize(EcFont.micro)
                .fontColor($r('app.color.ec_muted'))
                .width('100%')
            }
          }
          .width('100%')
          .padding(EcSpace.x3)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .alignItems(HorizontalAlign.Start)
        }, (record: StoryRetellRecord, index: number) => 'retell_' + index.toString())
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: EcSpace.x3 }) {
        if (this.vm.loading) {
          LoadingBlock({ text: '正在打开故事…' })
        } else if (this.vm.loadError.length > 0) {
          ErrorBanner({
            title: '故事没打开',
            message: this.vm.loadError,
            actionLabel: '重试',
            onAction: () => {
              if (this.vm.storyId.length > 0) {
                void this.vm.load(this.vm.storyId);
              }
            }
          })
        } else {
          this.headerCard()
          this.englishCard()
          this.sourceCard()
          this.imageCard()
          this.audioCard()
          this.originalCard()
          this.retellCard()
          Text('复述只看「讲清楚没有」，不计发音分。')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: EcSpace.x2, bottom: EcSpace.x6 })
        }
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor($r('app.color.ec_bg'))
  }
}

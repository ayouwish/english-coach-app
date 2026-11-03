import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcSpace } from '../design/DesignTokens';
import { NavState } from '../core/router/NavState';
import { NavigationService } from '../core/router/NavigationService';
import { StoryReadRequest } from '../core/session/StoryReadRequest';
import { Routes } from '../core/router/Routes';
import { SessionState } from '../core/session/SessionStore';
import { StorySentenceItem } from '../core/net/StoryDtos';
import { StoryRecordVM } from '../viewmodel/StoryVM';

/**
 * 讲故事：中文录音/输入 → 可编辑中文稿 → 改写 → 英文预览 → 保存。
 *
 * 录音降级（线上 /api/story/recordings 是 404）：
 *   AudioController 录 m4a → POST /api/asr?language=zh-CN（multipart audio）→ 文本写进输入框。
 * 原声只在本页 VM 里留路径，保存时交给 StoryRuntime（详情页标注「本次可用」）。
 */
@Component
export struct StoryRecordPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: StoryRecordVM = new StoryRecordVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    this.vm.configure(this.session.isChild, this.session.cefrLevel);
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  private async saveAndOpen(): Promise<void> {
    const id = await this.vm.save();
    if (id.length > 0) {
      NavState.setStory(id, null);
      NavigationService.push(Routes.STORY_DETAIL);
    }
  }

  /** 直接开讲：先保存拿到 material_id，再进复述页「讲给我听」（不经过详情页）。 */
  private async saveAndRetell(): Promise<void> {
    const id = await this.vm.save();
    if (id.length > 0) {
      NavState.setStory(id, null);
      NavigationService.push(Routes.STORY_REVIEW);
    }
  }

  private recordButtonLabel(): string {
    if (this.vm.recording) {
      return '⏹ 说完啦 ' + Math.floor(this.vm.elapsedMs / 1000).toString() + 's';
    }
    if (this.vm.preparing) {
      return '准备麦克风…';
    }
    return this.session.isChild ? '🎤 说中文（我听着）' : '🎤 说中文';
  }

  // ------------------------------------------------------------------ 输入区

  @Builder
  inputCard() {
    Column({ space: EcSpace.x3 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.session.isChild ? '先用中文讲讲吧' : '故事内容（中文）')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
        Blank()
        Text(this.vm.textZh.length.toString() + ' / 2000')
          .fontSize(EcFont.micro)
          .fontColor(this.vm.textZh.length > 2000 ? $r('app.color.ec_bad_text') : $r('app.color.ec_muted'))
      }
      .width('100%')

      TextArea({
        text: this.vm.textZh,
        placeholder: '例如：今天我和小明搭积木塔，被小华碰倒了，我很生气。'
      })
        .height(150)
        .fontSize(this.session.isChild ? EcFont.childBody : EcFont.body)
        .fontColor($r('app.color.ec_ink'))
        .placeholderColor($r('app.color.ec_muted'))
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.setTextZh(value);
        })

      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: this.recordButtonLabel(),
          kind: this.vm.recording ? EcButtonKind.DANGER : EcButtonKind.TONAL,
          btnWidth: this.vm.recording ? '58%' : '100%',
          disabled: this.vm.busy,
          onTap: () => {
            if (this.vm.recording) {
              void this.vm.stopRecordingAndRecognize();
            } else {
              void this.vm.startRecording();
            }
          }
        })
        if (this.vm.recording) {
          EcButton({
            label: '✖️ 不要了',
            kind: EcButtonKind.GHOST,
            btnWidth: '38%',
            onTap: () => {
              void this.vm.cancelRecording();
            }
          })
        }
      }
      .width('100%')

      if (this.vm.busy && this.vm.busyText.length > 0) {
        Row({ space: EcSpace.x2 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.ec_primary'))
          Text(this.vm.busyText)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      if (this.vm.notice.length > 0) {
        Text(this.vm.notice)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      }
      if (this.vm.hasError) {
        ErrorBanner({
          title: this.vm.error.title,
          message: this.vm.error.message,
          actionLabel: this.vm.errorActionLabel,
          onAction: () => {
            void this.vm.onErrorAction();
          }
        })
      }
      Text('说中文会被转成文字写进上面的框里；录音本身只在本次会话里可用。')
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

  // ------------------------------------------------------------------ 难度 / 句数

  @Builder
  levelRow() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('难度')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
        Blank()
        Text('⬇️ 再简单一点')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x1, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText('降低难度')
          .onClick(() => {
            this.vm.adjustLevel(-1);
          })
        Text('⬆️ 再难一点')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x1, right: EcSpace.x1, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText('提高难度')
          .onClick(() => {
            this.vm.adjustLevel(1);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.vm.levels, (item: string) => {
          Text(item)
            .fontSize(EcFont.caption)
            .fontWeight(this.vm.level === item ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.vm.level === item ? Color.White : $r('app.color.ec_muted'))
            .backgroundColor(this.vm.level === item ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
            .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x1, bottom: EcSpace.x1 })
            .borderRadius(EcRadius.pill)
            .margin(3)
            .accessibilityText('难度 ' + item)
            .onClick(() => {
              this.vm.selectLevel(item);
            })
        }, (item: string) => item)
      }
      .width('100%')

      Divider()
        .color($r('app.color.ec_border'))

      Row({ space: EcSpace.x2 }) {
        Text('句子数')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
        Blank()
        Text('儿童默认 5 句 / 成人默认 8 句')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.vm.sentenceOptions, (item: number) => {
          Text(item.toString())
            .fontSize(EcFont.micro)
            .fontWeight(this.vm.maxSentences === item ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.vm.maxSentences === item ? Color.White : $r('app.color.ec_muted'))
            .backgroundColor(this.vm.maxSentences === item ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
            .width(34)
            .height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(EcRadius.pill)
            .margin(3)
            .accessibilityText(item.toString() + ' 句')
            .onClick(() => {
              this.vm.setMaxSentences(item);
            })
        }, (item: number) => item.toString())
      }
      .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  // ------------------------------------------------------------------ 预览

  @Builder
  previewCard() {
    Column({ space: EcSpace.x3 }) {
      Row({ space: EcSpace.x2 }) {
        Text('英文故事预览')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
        Chip({ text: this.vm.level, tone: 'primary' })
        Blank()
        Text('可逐句修改')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      TextInput({ text: this.vm.title, placeholder: '给故事起个标题（英文）' })
        .height(48)
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_ink'))
        .placeholderColor($r('app.color.ec_muted'))
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.setTitle(value);
        })

      if (this.vm.readabilityText.length > 0) {
        Text(this.vm.readabilityText)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      if (this.vm.unknownWordsText.length > 0) {
        Text(this.vm.unknownWordsText)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      if (this.vm.warningText.length > 0) {
        Text(this.vm.warningText)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .backgroundColor($r('app.color.ec_warn_bg'))
          .borderRadius(EcRadius.md)
          .padding(EcSpace.x2)
          .width('100%')
      }
      if (this.vm.weakPhonemes.length > 0) {
        Row({ space: EcSpace.x1 }) {
          Text('练到这些音：')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
          ForEach(this.vm.weakPhonemes, (phoneme: string) => {
            Chip({ text: phoneme })
          }, (phoneme: string) => phoneme)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      Column({ space: EcSpace.x2 }) {
        ForEach(this.vm.sentences, (item: StorySentenceItem, index: number) => {
          Row({ space: EcSpace.x2 }) {
            Text(item.index.toString() + '.')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_muted'))
              .width(22)
              .textAlign(TextAlign.End)
              .margin({ top: EcSpace.x2 })
            TextArea({ text: item.en })
              .layoutWeight(1)
              .height(62)
              .fontSize(EcFont.body)
              .fontColor($r('app.color.ec_ink'))
              .backgroundColor($r('app.color.ec_surface_alt'))
              .borderRadius(EcRadius.md)
              .onChange((value: string) => {
                this.vm.setSentenceEn(index, value);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (item: StorySentenceItem) => 's_' + item.index.toString())
      }
      .width('100%')

      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: this.vm.saving ? '保存中…' : (this.session.isChild ? '💾 存下来，去读' : '💾 保存并开始读'),
          kind: EcButtonKind.PRIMARY,
          btnWidth: '62%',
          big: this.session.isChild,
          loading: this.vm.saving,
          disabled: this.vm.busy,
          onTap: () => {
            void this.saveAndOpen();
          }
        })
        EcButton({
          label: '🔄 重新生成',
          kind: EcButtonKind.GHOST,
          btnWidth: '34%',
          disabled: this.vm.busy || this.vm.saving,
          onTap: () => {
            void this.vm.rewrite();
          }
        })
      }
      .width('100%')

      // 生成英文后直接开读（不必先保存）：跳连读 Tab，用这些句子逐句朗读
      EcButton({
        label: this.session.isChild ? '🎤 现在就念一遍' : '🎤 朗读这个故事（连读）',
        kind: EcButtonKind.TONAL,
        big: this.session.isChild,
        btnWidth: '100%',
        disabled: this.vm.busy || this.vm.sentences.length === 0,
        onTap: () => {
          this.readAloud();
        }
      })

      // 生成后直接「讲给我听」：后台自动保存，再进复述页（不用先跳详情页）
      EcButton({
        label: this.vm.saving ? '保存中…' : (this.session.isChild ? '🎤 讲给我听听' : '🎤 直接讲给我听（复述这个故事）'),
        kind: EcButtonKind.GHOST,
        big: this.session.isChild,
        btnWidth: '100%',
        loading: this.vm.saving,
        disabled: this.vm.busy || this.vm.sentences.length === 0,
        onTap: () => {
          void this.saveAndRetell();
        }
      })
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  /** 生成后直接开读：连读 Tab 用这些句子开始（不强制先保存）。 */
  private readAloud(): void {
    const texts: string[] = [];
    for (let i = 0; i < this.vm.sentences.length; i++) {
      texts.push(this.vm.sentences[i].en);
    }
    if (texts.length === 0) {
      return;
    }
    StoryReadRequest.set(this.vm.title.length > 0 ? this.vm.title : '故事朗读', '', texts);
    AppStorage.setOrCreate<number>('tab_index', 1);
    NavigationService.clear();
  }

  build() {
    Scroll() {
      Column({ space: EcSpace.x3 }) {
        this.inputCard()
        this.levelRow()

        if (!this.vm.hasResult) {
          EcButton({
            label: this.vm.busy ? '生成中…' : '✨ 变成英文故事',
            kind: EcButtonKind.PRIMARY,
            big: this.session.isChild,
            loading: this.vm.busy,
            disabled: this.vm.textZh.trim().length === 0,
            onTap: () => {
              void this.vm.rewrite();
            }
          })
        }

        if (this.vm.hasResult) {
          this.previewCard()
        }

        Text('改写会按你的难度和句数生成；保存后可以插画、听整段朗读、做复述。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .padding({ top: EcSpace.x2, bottom: EcSpace.x6 })
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

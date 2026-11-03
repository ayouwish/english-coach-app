import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcSpace } from '../design/DesignTokens';
import { NavState } from '../core/router/NavState';
import { NavigationService } from '../core/router/NavigationService';
import { SessionState } from '../core/session/SessionStore';
import { StoryReviewVM } from '../viewmodel/StoryVM';

/**
 * 故事复述：录音（/api/asr?language=en-US）或文本 → POST /api/story/retell。
 *
 * 规则：复述**不评发音分**；儿童端只显示鼓励与「讲到了 N 个关键点」，不显示覆盖率百分比。
 */
@Component
export struct StoryReviewPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: StoryReviewVM = new StoryReviewVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    const id = NavState.story.storyId;
    if (id.length === 0) {
      this.vm.loading = false;
      this.vm.loadError = '没有找到这个故事，返回详情页重新进入试试';
      return;
    }
    void this.vm.load(id, this.session.isChild, this.session.cefrLevel);
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  private coverageText(): string {
    if (this.vm.coveragePercent < 0) {
      return '覆盖度 —';
    }
    return '覆盖度 ' + this.vm.coveragePercent.toString() + '%';
  }

  private recordLabel(): string {
    if (this.vm.recording) {
      return '⏹ 说完啦 ' + Math.floor(this.vm.elapsedMs / 1000).toString() + 's';
    }
    if (this.vm.preparing) {
      return '准备麦克风…';
    }
    return this.session.isChild ? '🎤 开始讲（我听着）' : '🎤 开始复述';
  }

  // ------------------------------------------------------------------ 页头

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('🎤 讲给我听')
          .fontSize(this.session.isChild ? EcFont.childH1 : EcFont.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
        Chip({ text: this.vm.level, tone: 'primary' })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(this.vm.storyTitle)
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('不看屏幕，用 2–3 句话把故事讲一遍 🙂')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  modeRow() {
    Row({ space: EcSpace.x2 }) {
      Text('🎤 说英文')
        .fontSize(EcFont.caption)
        .fontWeight(this.vm.textMode ? FontWeight.Normal : FontWeight.Medium)
        .fontColor(this.vm.textMode ? $r('app.color.ec_muted') : Color.White)
        .backgroundColor(this.vm.textMode ? $r('app.color.ec_surface_alt') : $r('app.color.ec_primary'))
        .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x1, bottom: EcSpace.x1 })
        .borderRadius(EcRadius.pill)
        .accessibilityText('录音复述')
        .onClick(() => {
          this.vm.setTextMode(false);
        })
      Text('✍️ 打字复述')
        .fontSize(EcFont.caption)
        .fontWeight(this.vm.textMode ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.vm.textMode ? Color.White : $r('app.color.ec_muted'))
        .backgroundColor(this.vm.textMode ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
        .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x1, bottom: EcSpace.x1 })
        .borderRadius(EcRadius.pill)
        .accessibilityText('打字复述')
        .onClick(() => {
          this.vm.setTextMode(true);
        })
      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ------------------------------------------------------------------ 输入

  @Builder
  inputCard() {
    Column({ space: EcSpace.x3 }) {
      this.modeRow()

      if (!this.vm.textMode) {
        EcButton({
          label: this.recordLabel(),
          kind: this.vm.recording ? EcButtonKind.DANGER : EcButtonKind.PRIMARY,
          big: this.session.isChild,
          disabled: this.vm.busy,
          onTap: () => {
            if (this.vm.recording) {
              void this.vm.stopRecordingAndSubmit();
            } else {
              void this.vm.startRecording();
            }
          }
        })
        if (this.vm.recording) {
          EcButton({
            label: '✖️ 不要了',
            kind: EcButtonKind.GHOST,
            onTap: () => {
              void this.vm.cancelRecording();
            }
          })
        }
        if (this.vm.transcript.length > 0) {
          Text('我听到的是：' + this.vm.transcript)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        if (this.vm.canPlayRecording()) {
          EcButton({
            label: '🔁 回放我刚才说的',
            kind: EcButtonKind.GHOST,
            onTap: () => {
              void this.vm.playRecording();
            }
          })
        }
      } else {
        TextArea({
          text: this.vm.typedText,
          placeholder: '用英文写 2–3 句复述，例如：I built a tower with Ming. Hua knocked it down. I was angry.'
        })
          .height(120)
          .fontSize(EcFont.body)
          .fontColor($r('app.color.ec_ink'))
          .placeholderColor($r('app.color.ec_muted'))
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .onChange((value: string) => {
            this.vm.setTypedText(value);
          })
        EcButton({
          label: this.vm.busy ? '提交中…' : '提交复述',
          kind: EcButtonKind.PRIMARY,
          loading: this.vm.busy,
          disabled: this.vm.typedText.trim().length === 0,
          onTap: () => {
            void this.vm.submitTyped();
          }
        })
      }

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
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  // ------------------------------------------------------------------ 结果

  @Builder
  resultCard() {
    Column({ space: EcSpace.x3 }) {
      if (this.session.isChild) {
        Text('🌟 你真棒！讲到了 ' + this.vm.coveredCount.toString() + ' 个关键点')
          .fontSize(EcFont.h3)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      } else {
        Row({ space: EcSpace.x2 }) {
          Text(this.coverageText())
            .fontSize(EcFont.h3)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_primary'))
          Text('讲到了 ' + this.vm.coveredCount.toString() + ' 个关键点')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      if (this.vm.coveredPoints.length > 0) {
        Column({ space: EcSpace.x1 }) {
          Text('讲到了：')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
          ForEach(this.vm.coveredPoints, (point: string, index: number) => {
            Text('· ' + point)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
              .width('100%')
          }, (point: string, index: number) => 'c_' + index.toString())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      if (this.vm.missingPoints.length > 0) {
        Column({ space: EcSpace.x1 }) {
          Text('下一次可以试试：')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
          ForEach(this.vm.missingPoints, (point: string, index: number) => {
            Text('· 把「' + point + '」也讲进去')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
              .width('100%')
          }, (point: string, index: number) => 'm_' + index.toString())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      if (this.vm.feedbackZh.length > 0) {
        Text(this.vm.feedbackZh)
          .fontSize(this.session.isChild ? EcFont.childBody : EcFont.body)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
          .backgroundColor($r('app.color.ec_good_bg'))
          .borderRadius(EcRadius.md)
          .padding(EcSpace.x3)
      }
      if (this.vm.feedbackEn.length > 0 && !this.session.isChild) {
        Text(this.vm.feedbackEn)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: '🎤 再讲一次',
          kind: EcButtonKind.TONAL,
          btnWidth: '48%',
          onTap: () => {
            this.vm.setTextMode(false);
            void this.vm.startRecording();
          }
        })
        EcButton({
          label: '回到故事',
          kind: EcButtonKind.GHOST,
          btnWidth: '48%',
          onTap: () => {
            NavigationService.pop();
          }
        })
      }
      .width('100%')
      Text('复述只看「讲清楚没有」，不计发音分。')
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

  // ------------------------------------------------------------------ 原文参考

  @Builder
  sentenceCard() {
    Column({ space: EcSpace.x1 }) {
      Text('故事原文（想不起来可以偷看）')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      ForEach(this.vm.storySentences, (sentence: string, index: number) => {
        Text((index + 1).toString() + '. ' + sentence)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
      }, (sentence: string, index: number) => 'ss_' + index.toString())
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
            title: '没打开故事',
            message: this.vm.loadError,
            actionLabel: '重试',
            onAction: () => {
              if (this.vm.storyId.length > 0) {
                void this.vm.load(this.vm.storyId, this.session.isChild, this.session.cefrLevel);
              }
            }
          })
        } else {
          this.headerCard()
          this.inputCard()
          if (this.vm.hasResult) {
            this.resultCard()
          }
          this.sentenceCard()
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

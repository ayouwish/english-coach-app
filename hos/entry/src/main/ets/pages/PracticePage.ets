import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { EmptyState } from '../components/EmptyState';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcButtonSize, EcFont, EcRadius, EcScore, EcShadow, EcSpace } from '../design/DesignTokens';
import { NavigationService } from '../core/router/NavigationService';
import { SessionState } from '../core/session/SessionStore';
import { PracticeVM } from '../viewmodel/PracticeVM';

/**
 * 跟读页：听示范 / 跟我读 / 录音 / 上传评测 / 看结果。
 *
 * 儿童规则（docs/screens.md §0）：
 * - 不显示 IPA（focus_phonemes）；
 * - 总分 <60 不显示数字、不用红色，只给鼓励 + 星星；
 * - 不展示纠错细节（VM 里已过滤 pointTitles）。
 *
 * 音频全部经 AudioController（互斥 + fd 释放）；离开页面 stopAll。
 */
@Component
export struct PracticePage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: PracticeVM = new PracticeVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    const sentence = NavigationService.practiceSentence();
    if (sentence !== null) {
      this.vm.setup(sentence, NavigationService.practiceLevel(), this.session.isChild);
    }
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  private timerText(): string {
    const totalSeconds = Math.floor(this.vm.elapsedMs / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const secondsText = seconds < 10 ? ('0' + seconds.toString()) : seconds.toString();
    return minutes.toString() + ':' + secondsText;
  }

  private recordSize(): number {
    if (this.session.isChild || this.vm.recording) {
      return EcButtonSize.recordChild;
    }
    return EcButtonSize.record;
  }

  private showScoreNumber(): boolean {
    return EcScore.showNumber(this.vm.scorePron, this.vm.isChild);
  }

  private scoreColor(): ResourceColor {
    return EcScore.colorByMode(this.vm.scorePron, this.vm.isChild);
  }

  private toggleRecording(): void {
    if (this.vm.recording) {
      void this.vm.stopRecordingAndSubmit();
      return;
    }
    void this.vm.startRecording();
  }

  @Builder
  sentenceCard() {
    Column({ space: EcSpace.x3 }) {
      Text(this.vm.text)
        .fontSize(this.vm.isChild ? (EcFont.sentence + 2) : EcFont.sentence)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .lineHeight(this.vm.isChild ? 34 : 32)
        .width('100%')
      if (this.vm.translation.length > 0) {
        Text(this.vm.translation)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      if (this.vm.focusPhonemes.length > 0) {
        Row({ space: EcSpace.x1 }) {
          ForEach(this.vm.focusPhonemes, (phoneme: string) => {
            Text(phoneme)
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_primary'))
              .backgroundColor($r('app.color.ec_primary_soft'))
              .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 2, bottom: 2 })
              .borderRadius(EcRadius.sm)
          }, (phoneme: string) => phoneme)
          Text('重点音')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(this.session.isChild ? EcSpace.x5 : EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  actionButtons() {
    Row({ space: EcSpace.x3 }) {
      EcButton({
        label: this.vm.ttsLoading ? '生成中…' : (this.vm.playing ? '播放中…' : '🔊 听示范'),
        kind: EcButtonKind.TONAL,
        btnWidth: '48%',
        loading: this.vm.ttsLoading,
        disabled: this.vm.submitting || this.vm.recording,
        onTap: () => {
          void this.vm.playDemo(false);
        }
      })
      EcButton({
        label: '🎧 跟我读',
        kind: EcButtonKind.GHOST,
        btnWidth: '48%',
        disabled: this.vm.submitting || this.vm.recording,
        onTap: () => {
          void this.vm.playDemo(true);
        }
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  recordSection() {
    Column({ space: EcSpace.x2 }) {
      if (this.vm.recording) {
        Text('🔴 ' + this.timerText())
          .fontSize(EcFont.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_bad_text'))
        Text('把这句话读完，再点「说完啦」')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
      } else if (this.vm.preparing) {
        Text('麦克风准备中…')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
      } else {
        Text(this.session.isChild ? '准备好就点一下 🎤' : '点一下开始录音，最长 60 秒')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
      }

      Column({ space: 2 }) {
        Text(this.vm.recording ? '■' : '🎤')
          .fontSize(26)
          .fontColor(Color.White)
        Text(this.vm.recording ? '说完啦' : (this.vm.preparing ? '准备中' : '开始说'))
          .fontSize(EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .width(this.recordSize())
      .height(this.recordSize())
      .borderRadius(EcRadius.pill)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.vm.recording ? $r('app.color.ec_bad') : $r('app.color.ec_primary'))
      .shadow(EcShadow.raised())
      .opacity((this.vm.submitting || this.vm.preparing) ? 0.5 : 1)
      .enabled(!(this.vm.submitting || this.vm.preparing))
      .accessibilityText(this.vm.recording ? '结束录音' : '开始录音')
      .onClick(() => {
        this.toggleRecording();
      })

      if (this.vm.recording) {
        Text('取消这次录音')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .padding(EcSpace.x1)
          .onClick(() => {
            void this.vm.cancelRecording();
          })
      }
    }
    .width('100%')
    .padding({ top: EcSpace.x2, bottom: EcSpace.x2 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  subScore(label: string, value: number | null) {
    Column({ space: EcSpace.x1 }) {
      Text(EcScore.numberText(value))
        .fontSize(EcFont.h3)
        .fontWeight(FontWeight.Medium)
        .fontColor(EcScore.colorByMode(value, this.vm.isChild))
      Text(label)
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  resultSection() {
    Column({ space: EcSpace.x3 }) {
      if (this.vm.noSpeech) {
        Column({ space: EcSpace.x1 }) {
          Text('😶')
            .fontSize(32)
          Text('没听到你的声音，再试一次吧')
            .fontSize(EcFont.body)
            .fontColor($r('app.color.ec_warn_text'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding(EcSpace.x3)
      } else {
        Row({ space: EcSpace.x3 }) {
          if (this.showScoreNumber()) {
            Text(EcScore.numberText(this.vm.scorePron))
              .fontSize(46)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.scoreColor())
          } else {
            Text(this.vm.isChild ? EcScore.stars(this.vm.scorePron) : '—')
              .fontSize(this.vm.isChild ? 28 : 40)
              .fontColor(this.scoreColor())
          }
          Column({ space: EcSpace.x1 }) {
            if (!this.vm.isChild) {
              Text('总分')
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_muted'))
            }
            Text(EcScore.encouragement(this.vm.scorePron, this.vm.isChild))
              .fontSize(this.vm.isChild ? EcFont.childBody : EcFont.body)
              .fontColor($r('app.color.ec_ink'))
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          this.subScore('准确', this.vm.scoreAccuracy)
          this.subScore('流利', this.vm.scoreFluency)
          this.subScore('完整', this.vm.scoreCompleteness)
          this.subScore('语调', this.vm.scoreProsody)
        }
        .width('100%')
      }

      if (this.vm.lowSnr) {
        Text('周围有点吵，找个安静的地方会读得更准')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
      }

      if (this.vm.feedbackSummary.length > 0) {
        Text(this.vm.feedbackSummary)
          .fontSize(this.vm.isChild ? EcFont.childBody : EcFont.body)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
      }
      if (this.vm.feedbackPraise.length > 0) {
        Text(this.vm.feedbackPraise)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      }

      if (this.vm.pointTitles.length > 0) {
        Column({ space: EcSpace.x2 }) {
          ForEach(this.vm.pointTitles, (title: string, index: number) => {
            Column({ space: EcSpace.x1 }) {
              Text(title)
                .fontSize(EcFont.body)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ec_ink'))
                .width('100%')
              if (index < this.vm.pointHows.length) {
                Text(this.vm.pointHows[index])
                  .fontSize(EcFont.caption)
                  .fontColor($r('app.color.ec_muted'))
                  .width('100%')
              }
            }
            .width('100%')
            .padding(EcSpace.x3)
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.md)
            .alignItems(HorizontalAlign.Start)
          }, (title: string, index: number) => index.toString() + title)
        }
        .width('100%')
      }

      if (!this.vm.isChild && this.vm.recognizedText.length > 0) {
        Text('识别到：' + this.vm.recognizedText)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      if (this.vm.feedbackClosing.length > 0) {
        Text(this.vm.feedbackClosing)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      Row({ space: EcSpace.x3 }) {
        EcButton({
          label: '再读一遍',
          kind: EcButtonKind.TONAL,
          btnWidth: '48%',
          disabled: this.vm.submitting,
          onTap: () => {
            void this.vm.startRecording();
          }
        })
        if (this.vm.canRetryEvaluate) {
          EcButton({
            label: '重试评测',
            kind: EcButtonKind.GHOST,
            btnWidth: '48%',
            loading: this.vm.submitting,
            onTap: () => {
              void this.vm.retryEvaluate();
            }
          })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if (!this.vm.hasSelection) {
        EmptyState({
          icon: '📄',
          message: '还没有选中句子，回列表选一句吧',
          actionLabel: '返回列表',
          onAction: () => {
            NavigationService.pop();
          }
        })
      } else {
        Scroll() {
          Column({ space: EcSpace.x4 }) {
            this.sentenceCard()
            this.actionButtons()
            this.recordSection()

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

            if (this.vm.submitting) {
              LoadingBlock({ text: this.vm.progressText.length > 0 ? this.vm.progressText : '评测中…', subText: '最长约 100 秒，请不要离开' })
            }

            if (this.vm.hasResult) {
              this.resultSection()
            }
          }
          .width('100%')
          .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x3, bottom: EcSpace.x8 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
  }
}

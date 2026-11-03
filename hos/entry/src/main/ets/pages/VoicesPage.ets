import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { MediaService, VoiceOption } from '../core/service/MediaService';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { SessionState } from '../core/session/SessionStore';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { VoicesVM } from '../viewmodel/AccountVM';

/**
 * 音色页：`GET /api/tts/voices` 线上 404，按规格使用**内置 9 个音色常量**（chat-story §5.1）。
 * 试听 = POST /api/tts（JSON {text,voice,rate,format:'mp3'} → 二进制）落盘后 AudioController 播放；
 * 选中后 PATCH /api/settings {tts_voice} 保存（null = provider 默认）。
 */
@Component
export struct VoicesPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: VoicesVM = new VoicesVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init(this.session.isChild);
  }

  aboutToDisappear(): void {
    void MediaService.stopPreview();
  }

  private isCurrent(voiceId: string): boolean {
    return this.vm.currentVoice === voiceId;
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Text('🔊 音色')
        .fontSize(EcFont.h2)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      Text('练习示范音、对话朗读、鼓励音都会用它。默认音色由语音服务决定。')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .lineHeight(22)
        .width('100%')
      Row({ space: EcSpace.x2 }) {
        Chip({ text: '当前：' + this.vm.labelOf(this.vm.currentVoice), tone: 'primary' })
        Chip({ text: '语速 ' + this.vm.rate, tone: 'muted' })
      }
      .alignItems(VerticalAlign.Center)

      if (this.vm.notice.length > 0) {
        Text(this.vm.notice)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      }
      if (this.vm.saveError.length > 0) {
        Text(this.vm.saveError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
      if (this.vm.previewError.length > 0) {
        Text(this.vm.previewError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  defaultRow() {
    Row({ space: EcSpace.x2 }) {
      Column({ space: EcSpace.x1 }) {
        Text('默认音色（provider 决定）')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
        Text('不指定 voice，由语音服务选择最合适的音色。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isCurrent('')) {
        Chip({ text: '使用中', tone: 'good' })
      } else {
        Text('使用')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
          .backgroundColor($r('app.color.ec_primary_soft'))
          .borderRadius(EcRadius.pill)
          .accessibilityText('使用默认音色')
          .onClick(() => {
            void this.vm.save('');
          })
      }
    }
    .width('100%')
    .padding(EcSpace.x3)
    .backgroundColor($r('app.color.ec_surface_alt'))
    .borderRadius(EcRadius.md)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  voiceRow(voice: VoiceOption) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Column({ space: EcSpace.x1 }) {
          Text(voice.labelZh)
            .fontSize(EcFont.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
          Text(voice.sample)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.isCurrent(voice.id)) {
          Chip({ text: '使用中', tone: 'good' })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: EcSpace.x2 }) {
        Text(this.vm.previewingId === voice.id ? '⏹ 停止' : '▶ 试听')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
          .backgroundColor($r('app.color.ec_primary_soft'))
          .borderRadius(EcRadius.pill)
          .accessibilityText('试听 ' + voice.labelZh)
          .onClick(() => {
            void this.vm.togglePreview(voice);
          })
        if (!this.isCurrent(voice.id)) {
          Text('使用这个音色')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.pill)
            .accessibilityText('使用 ' + voice.labelZh)
            .onClick(() => {
              void this.vm.save(voice.id);
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x3)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.md)
    .border({ width: 1, color: $r('app.color.ec_border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  listCard() {
    Column({ space: EcSpace.x2 }) {
      Text('英语音色')
        .fontSize(EcFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      ForEach(this.vm.voices, (voice: VoiceOption) => {
        if (voice.lang === 'en') {
          this.voiceRow(voice)
        }
      }, (voice: VoiceOption) => 'en-' + voice.id)

      Text('中文音色')
        .fontSize(EcFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
        .padding({ top: EcSpace.x2 })
      ForEach(this.vm.voices, (voice: VoiceOption) => {
        if (voice.lang === 'zh') {
          this.voiceRow(voice)
        }
      }, (voice: VoiceOption) => 'zh-' + voice.id)

      Text('共 ' + this.vm.voices.length.toString() + ' 个音色。试听需要网络与语音服务；试听失败不影响保存偏好。')
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

  build() {
    Scroll() {
      Column({ space: EcSpace.x3 }) {
        this.headerCard()

        if (this.vm.hasError) {
          ErrorBanner({
            title: this.vm.error.title,
            message: this.vm.error.message,
            actionLabel: this.vm.error.retryable ? '重试' : '',
            onAction: () => {
              void this.vm.load();
            }
          })
        }

        if (this.vm.loading && !this.vm.loaded) {
          LoadingBlock({ text: '正在读取音色偏好…' })
        } else {
          this.defaultRow()
          this.listCard()
        }

        Column({ space: EcSpace.x2 }) {
          EcButton({
            label: '⚙️ 去设置页调整语速与其它偏好',
            kind: EcButtonKind.GHOST,
            onTap: () => {
              void MediaService.stopPreview();
              NavigationService.push(Routes.SETTINGS);
            }
          })
        }
        .width('100%')
        .padding({ bottom: EcSpace.x8 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .scrollBar(BarState.Off)
  }
}

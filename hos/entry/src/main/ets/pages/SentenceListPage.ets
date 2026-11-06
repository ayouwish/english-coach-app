import { ErrorBanner } from '../components/ErrorBanner';
import { EmptyState } from '../components/EmptyState';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { SentenceDto } from '../core/net/Dtos';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { SessionState } from '../core/session/SessionStore';
import { SentenceListVM } from '../viewmodel/SentenceListVM';

/**
 * 语料列表（已登录首页 / 根内容）：按 cefrLevel 选等级 → 点一句进入跟读。
 *
 * 三态：loading（spinner + 文案）/ empty（一句人话 + 换等级）/ error（可见 + 重试）。
 */
@Component
export struct SentenceListPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: SentenceListVM = new SentenceListVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init(this.session.cefrLevel, this.session.isChild);
  }

  private usageText(): string {
    const minutes = Math.round(this.session.minutesToday * 10) / 10;
    if (minutes <= 0) {
      return '今天还没有开始练';
    }
    return '今天已练 ' + minutes.toString() + ' / ' + this.session.dailyLimitMinutes.toString() + ' 分钟';
  }

  private levelFg(level: string): ResourceColor {
    return this.vm.level === level ? Color.White : $r('app.color.ec_muted');
  }

  private levelBg(level: string): ResourceColor {
    return this.vm.level === level ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt');
  }

  @Builder
  header() {
    Row({ space: EcSpace.x3 }) {
      Column({ space: EcSpace.x1 }) {
        Text(this.session.displayName.length > 0 ? ('你好，' + this.session.displayName) : '你好')
          .fontSize(this.session.isChild ? EcFont.childH1 : EcFont.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
        Text(this.usageText())
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4, bottom: EcSpace.x3 })
  }

  @Builder
  levelTabs() {
    Row({ space: EcSpace.x2 }) {
      ForEach(this.vm.levels, (level: string) => {
        Text(level)
          .fontSize(this.session.isChild ? EcFont.body : EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.levelFg(level))
          .backgroundColor(this.levelBg(level))
          .padding({ left: EcSpace.x5, right: EcSpace.x5, top: EcSpace.x2, bottom: EcSpace.x2 })
          .borderRadius(EcRadius.pill)
          .accessibilityText('等级 ' + level)
          .onClick(() => {
            void this.vm.selectLevel(level);
          })
      }, (level: string) => level)
    }
    .width('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x3 })
  }

  @Builder
  sentenceCard(item: SentenceDto) {
    Column({ space: EcSpace.x2 }) {
      Text(item.text)
        .fontSize(this.vm.isChild ? EcFont.childBody : EcFont.sentence)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .lineHeight(this.vm.isChild ? 28 : 32)
        .width('100%')
      if (item.translation_zh !== undefined && item.translation_zh.length > 0) {
        Text(item.translation_zh)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      Row({ space: EcSpace.x1 }) {
        Text(item.level)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_primary'))
          .backgroundColor($r('app.color.ec_primary_soft'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 2, bottom: 2 })
          .borderRadius(EcRadius.sm)
        if (!this.vm.isChild && item.focus_phonemes !== undefined) {
          ForEach(item.focus_phonemes, (phoneme: string) => {
            Text(phoneme)
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .backgroundColor($r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 2, bottom: 2 })
              .borderRadius(EcRadius.sm)
          }, (phoneme: string) => item.id + phoneme)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      NavigationService.openPractice(item, this.vm.level);
    })
  }

  build() {
    Column() {
      this.header()
      this.levelTabs()

      if (this.vm.hasError) {
        Column() {
          ErrorBanner({
            title: this.vm.error.title,
            message: this.vm.error.message,
            actionLabel: this.vm.error.actionLabel.length > 0 ? this.vm.error.actionLabel : '重试',
            onAction: () => {
              void this.vm.load();
            }
          })
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x3 })
      }

      if (this.vm.loading && this.vm.sentences.length === 0) {
        LoadingBlock({ text: '正在取句子…' })
      } else if (this.vm.isEmpty()) {
        EmptyState({
          icon: '📚',
          message: this.vm.isChild ? '这个等级还没有句子，换一个等级看看吧' : '这个等级还没有句子，换一个等级试试',
          actionLabel: '换个等级',
          onAction: () => {
            void this.vm.selectLevel(this.vm.level === 'A1' ? 'A2' : 'A1');
          }
        })
      } else {
        List({ space: EcSpace.x3 }) {
          ForEach(this.vm.sentences, (item: SentenceDto) => {
            ListItem() {
              this.sentenceCard(item)
            }
          }, (item: SentenceDto) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
  }
}

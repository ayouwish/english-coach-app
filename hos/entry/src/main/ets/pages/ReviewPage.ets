import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { EmptyState } from '../components/EmptyState';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcScore, EcSpace } from '../design/DesignTokens';
import { ReviewCardDto, ReviewWeakPhonemeDto, ReviewWordErrorDto } from '../core/net/StatsDtos';
import { NavigationService } from '../core/router/NavigationService';
import { SessionState } from '../core/session/SessionStore';
import { ReviewVM } from '../viewmodel/StatsVM';

/**
 * 错音本（`GET/POST /api/review`，SM-2 简化版 SRS）。
 *
 * 成人：显示音素符号与均分；儿童：只显示 label/why/how 文案（服务端已剥离 phoneme）。
 * 评分成功后**本地移除该卡**并把 due_cards-1（规格 §6.2，不重新拉列表）。
 */
@Component
export struct ReviewPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: ReviewVM = new ReviewVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init(this.session.isChild);
  }

  private gradeKinds(): string[] {
    return ['again', 'hard', 'good', 'easy'];
  }

  private gradeFg(grade: string): ResourceColor {
    return grade === 'good' ? Color.White : $r('app.color.ec_primary');
  }

  private gradeBg(grade: string): ResourceColor {
    return grade === 'good' ? $r('app.color.ec_primary') : $r('app.color.ec_primary_soft');
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Text(this.session.isChild ? '📒 我的小错音本' : '📒 错音本 / SRS 复习')
        .fontSize(this.session.isChild ? EcFont.childH1 : EcFont.h2)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')

      Text('待复习 ' + this.vm.dueCards.toString() + ' 张 · 卡片总数 ' +
        this.vm.totalCards.toString() + ' 张 · 音素记录 ' + this.vm.phonemeRows.toString() + ' 条 · 今日 ' +
        ReviewVM.minutesText(this.session) + ' 分钟' +
        (this.session.isChild ? (' · 还剩 ' + ReviewVM.minutesLeft(this.session) + ' 分钟') : ''))
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Text('排期算法：SM-2 简化版（again/hard/good/easy）。' +
        (this.vm.phonemeLevel ? '' : '当前是单词级粗评（provider 不支持音素级）。'))
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      if (this.vm.gradeNotice.length > 0) {
        Text(this.vm.gradeNotice)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      }
      if (this.vm.gradeError.length > 0) {
        Text(this.vm.gradeError)
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
  gradeButton(card: ReviewCardDto, grade: string) {
    Text(this.vm.gradeLabel(grade))
      .fontSize(this.session.isChild ? EcFont.body : EcFont.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.gradeFg(grade))
      .backgroundColor(this.gradeBg(grade))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(this.session.isChild ? 48 : 40)
      .borderRadius(EcRadius.md)
      .accessibilityText(this.vm.gradeLabel(grade))
      .onClick(() => {
        void this.vm.grade(card.id, grade);
      })
  }

  @Builder
  cardView(card: ReviewCardDto) {
    Column({ space: EcSpace.x3 }) {
      Row({ space: EcSpace.x2 }) {
        if (this.vm.badgeText(card).length > 0) {
          Text(this.vm.badgeText(card))
            .fontSize(EcFont.h3)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_primary'))
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.ec_primary_soft'))
            .borderRadius(EcRadius.md)
        }
        Column({ space: EcSpace.x1 }) {
          Text(this.vm.cardTitle(card))
            .fontSize(EcFont.body)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
          Text(this.vm.metaText(card))
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (card.why_zh !== undefined && card.why_zh.length > 0) {
        Text(card.why_zh)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
      }
      if (card.how_zh !== undefined && card.how_zh.length > 0) {
        Text('怎么做：' + card.how_zh)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      if (card.practice_words !== undefined && card.practice_words.length > 0) {
        Text('练习词：' + card.practice_words.join(' · '))
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      Row({ space: EcSpace.x2 }) {
        ForEach(this.gradeKinds(), (grade: string) => {
          this.gradeButton(card, grade)
        }, (grade: string) => card.id + '-' + grade)
      }
      .width('100%')

      if (this.vm.gradingCardId === card.id) {
        Text('正在记录…')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .border({ width: 1, color: $r('app.color.ec_border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  weakPhonemeView(item: ReviewWeakPhonemeDto, index: number) {
    Column({ space: EcSpace.x1 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.vm.weakPhonemeLabel(item))
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        if (!this.session.isChild) {
          Text(ReviewVM.scoreText(item.avg_score) + ' 分')
            .fontSize(EcFont.caption)
            .fontColor(EcScore.color(item.avg_score))
        } else {
          Text('练过 ' + (item.attempts === undefined ? 0 : item.attempts).toString() + ' 次')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.session.isChild) {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(8)
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(4)
          if (item.avg_score !== undefined && item.avg_score !== null) {
            Row()
              .width(Math.max(2, Math.round(item.avg_score)).toString() + '%')
              .height(8)
              .backgroundColor(EcScore.color(item.avg_score))
              .borderRadius(4)
          }
        }
        .width('100%')
        .height(8)
      }
    }
    .width('100%')
    .padding({ top: EcSpace.x2, bottom: EcSpace.x2 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  weakSection() {
    Column({ space: EcSpace.x2 }) {
      Text(this.session.isChild ? '哪些音我常说不好' : '音素掌握度（最弱在前）')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      ForEach(this.vm.weakPhonemes, (item: ReviewWeakPhonemeDto, index: number) => {
        this.weakPhonemeView(item, index)
      }, (item: ReviewWeakPhonemeDto, index: number) => 'weak-' + index.toString())
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  wordErrorSection() {
    Column({ space: EcSpace.x2 }) {
      Text('高频错词（单词级粗评）')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.vm.wordErrors, (item: ReviewWordErrorDto, index: number) => {
          Text((item.word === undefined ? '' : item.word) + ' × ' +
            (item.count === undefined ? 0 : item.count).toString() + '（均 ' +
            ReviewVM.scoreText(item.avg_score) + '）')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_warn_text'))
            .backgroundColor($r('app.color.ec_warn_bg'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 3, bottom: 3 })
            .borderRadius(EcRadius.pill)
            .margin({ right: EcSpace.x2, bottom: EcSpace.x2 })
        }, (item: ReviewWordErrorDto, index: number) => 'word-' + index.toString())
      }
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

        if (this.vm.loading && !this.vm.loadedOnce) {
          LoadingBlock({ text: '正在取今天要复习的卡片…' })
        } else if (this.vm.cards.length === 0) {
          EmptyState({
            icon: '🎉',
            message: this.session.isChild
              ? '现在没有要做的小练习啦，去读几句就会有新的'
              : '现在没有到期的卡片。去「跟读练习」多读几句，新的错音会自动进来',
            actionLabel: '返回去跟读练习',
            onAction: () => {
              NavigationService.pop();
            }
          })
        } else {
          Text(this.session.isChild ? '今天要复习的小卡片' : '今天要复习的卡片')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
          ForEach(this.vm.cards, (card: ReviewCardDto) => {
            this.cardView(card)
          }, (card: ReviewCardDto) => card.id)
        }

        if (this.vm.weakPhonemes.length > 0) {
          this.weakSection()
        }

        if (!this.session.isChild && this.vm.wordErrors.length > 0) {
          this.wordErrorSection()
        }

        Column({ space: EcSpace.x2 }) {
          EcButton({
            label: '🎙 返回去跟读练习',
            kind: EcButtonKind.TONAL,
            onTap: () => {
              NavigationService.pop();
            }
          })
          Row({ space: EcSpace.x2 }) {
            Chip({ text: '待复习 ' + this.vm.dueCards.toString(), tone: 'warn' })
            Chip({ text: '共 ' + this.vm.totalCards.toString() + ' 张', tone: 'muted' })
            if (!this.vm.voiceReachable) {
              Chip({ text: '语音服务未就绪', tone: 'bad' })
            }
          }
          .alignItems(VerticalAlign.Center)
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

import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { EmptyState } from '../components/EmptyState';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcScore, EcShadow, EcSpace } from '../design/DesignTokens';
import { DiagnosisContrastDto, DiagnosisItemDto } from '../core/net/StatsDtos';
import { AttemptItemDto } from '../core/net/Dtos';
import { NavigationService } from '../core/router/NavigationService';
import { PracticeFocus } from '../core/session/PracticeFocus';
import { SessionState } from '../core/session/SessionStore';
import { DiagnosisVM } from '../viewmodel/StatsVM';

/**
 * 发音诊断（`GET /api/diagnosis`）：最近 7 天 / 全部累计两个 tab。
 *
 * 阈值配色由服务端 status 决定（weak<65 / watch 65–80 / ok≥80），客户端不重算；
 * 儿童：不显示 IPA、不显示数字分（服务端已剥离 phoneme，这是第二道保险）。
 */
@Component
export struct DiagnosisPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: DiagnosisVM = new DiagnosisVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init(this.session.isChild);
  }

  private toneFg(tone: string): ResourceColor {
    if (tone === 'weak') {
      return $r('app.color.ec_bad_text');
    }
    if (tone === 'watch') {
      return $r('app.color.ec_warn_text');
    }
    return $r('app.color.ec_good_text');
  }

  private toneBg(tone: string): ResourceColor {
    if (tone === 'weak') {
      return $r('app.color.ec_bad_bg');
    }
    if (tone === 'watch') {
      return $r('app.color.ec_warn_bg');
    }
    return $r('app.color.ec_good_bg');
  }

  private tabFg(scope: string): ResourceColor {
    return this.vm.scope === scope ? Color.White : $r('app.color.ec_muted');
  }

  private tabBg(scope: string): ResourceColor {
    return this.vm.scope === scope ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt');
  }

  private scoreLine(item: DiagnosisItemDto): string {
    const attempts = item.attempts === undefined ? 0 : item.attempts;
    if (this.vm.isChild) {
      return '练过 ' + attempts.toString() + ' 次';
    }
    const avg = item.avg_score === undefined ? null : item.avg_score;
    const avgText = (avg === null) ? '—' : (Math.round(avg * 10) / 10).toString();
    return avgText + ' 分 · ' + attempts.toString() + ' 次记录';
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x3 }) {
      Text(this.vm.isChild ? '🔍 我的发音报告' : '🔍 发音诊断报告')
        .fontSize(this.vm.isChild ? EcFont.childH1 : EcFont.h2)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')

      Row({ space: EcSpace.x2 }) {
        Text('最近 7 天')
          .fontSize(this.vm.isChild ? EcFont.body : EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tabFg('recent'))
          .backgroundColor(this.tabBg('recent'))
          .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x2, bottom: EcSpace.x2 })
          .borderRadius(EcRadius.pill)
          .accessibilityText('最近 7 天')
          .onClick(() => {
            void this.vm.switchScope('recent');
          })
        Text('全部累计')
          .fontSize(this.vm.isChild ? EcFont.body : EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tabFg('all'))
          .backgroundColor(this.tabBg('all'))
          .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x2, bottom: EcSpace.x2 })
          .borderRadius(EcRadius.pill)
          .accessibilityText('全部累计')
          .onClick(() => {
            void this.vm.switchScope('all');
          })
      }
      .width('100%')

      if (this.vm.summaryZh.length > 0) {
        Text(this.vm.summaryZh)
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .lineHeight(24)
          .width('100%')
      }
      if (this.vm.loadedOnce) {
        Text(this.vm.metricText())
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      if (this.vm.items.length > 0) {
        Row({ space: EcSpace.x2 }) {
          Text(this.vm.isChild ? '🎯 可以再练一练：' : '🎯 最近最需要练的：')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
          ForEach(this.vm.items.slice(0, 2), (item: DiagnosisItemDto, index: number) => {
            Chip({
              text: this.vm.itemTitle(item),
              tone: this.vm.statusTone(item.status === undefined ? '' : item.status)
            })
          }, (item: DiagnosisItemDto, index: number) => 'focus-' + index.toString())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      EcButton({
        label: this.vm.actionLabel(),
        kind: EcButtonKind.PRIMARY,
        big: this.vm.isChild,
        loading: this.vm.loading,
        onTap: () => {
          this.startFocusPractice(this.vm.firstFocusToken());
        }
      })
      Text('会跳回「跟读」Tab，只练这个音素的句子（GET /sentences?focus=…）。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  itemCard(item: DiagnosisItemDto) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.vm.itemTitle(item))
          .fontSize(EcFont.h3)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Chip({
          text: this.vm.statusTone(item.status === undefined ? '' : item.status) === 'weak'
            ? '需要练' : (this.vm.statusTone(item.status === undefined ? '' : item.status) === 'watch'
              ? '待巩固' : '已掌握'),
          tone: this.vm.statusTone(item.status === undefined ? '' : item.status)
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.scoreLine(item))
        .fontSize(EcFont.caption)
        .fontColor(this.toneFg(this.vm.statusTone(item.status === undefined ? '' : item.status)))
        .width('100%')

      if (!this.vm.isChild && this.vm.trendText(item).length > 0) {
        Text(this.vm.trendText(item))
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      if (this.vm.isChild && this.vm.trendTextChild(item).length > 0) {
        Text(this.vm.trendTextChild(item))
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      if (this.vm.isChild) {
        if (item.tip_child_zh !== undefined && item.tip_child_zh.length > 0) {
          Text('👄 ' + item.tip_child_zh)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
        }
      } else if (item.tip_zh !== undefined && item.tip_zh.length > 0) {
        Text('👄 口型要点：' + item.tip_zh)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
      }

      if (!this.vm.isChild && item.common_errors !== undefined && item.common_errors.length > 0) {
        Text('⚠️ 常见错误：' + item.common_errors.join(' · '))
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
      }

      if (!this.vm.isChild && item.contrasts !== undefined && item.contrasts.length > 0) {
        Column({ space: EcSpace.x1 }) {
          ForEach(item.contrasts.slice(0, 2), (contrast: DiagnosisContrastDto) => {
            Text('🔀 ' + (contrast.pair === undefined ? '' : contrast.pair.join(' → ')) + '：' +
              (contrast.note === undefined ? '' : contrast.note))
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
          }, (contrast: DiagnosisContrastDto, index: number) => 'contrast-' + index.toString())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      if (item.examples !== undefined && item.examples.length > 0) {
        Text('相关的词：' + item.examples.join(' · '))
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      Row({ space: EcSpace.x2 }) {
        if (item.practice_count !== undefined && item.practice_count > 0) {
          Row() {
            Text(this.vm.isChild ? '🎯 去练一练' : ('🎯 练这 ' + item.practice_count.toString() + ' 句'))
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_primary'))
              .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
              .backgroundColor($r('app.color.ec_primary_soft'))
              .borderRadius(EcRadius.pill)
              .accessibilityText('去练习')
              .onClick(() => {
                const token = (item.focus_token === undefined) ? '' : item.focus_token;
                this.startFocusPractice(token);
              })
          }
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .border({
      width: this.vm.statusTone(item.status === undefined ? '' : item.status) === 'weak' ? 2 : 0,
      color: $r('app.color.ec_warn')
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  okSection() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('已经掌握的音素（' + this.vm.okItems.length.toString() + '）')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .layoutWeight(1)
        Text(this.vm.showOk ? '收起' : '点击展开')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .onClick(() => {
            this.vm.showOk = !this.vm.showOk;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.showOk) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.vm.okItems, (item: DiagnosisItemDto, index: number) => {
            Row() {
              Chip({
                text: this.vm.itemTitle(item),
                tone: 'good'
              })
            }
            .margin({ right: EcSpace.x2, bottom: EcSpace.x2 })
          }, (item: DiagnosisItemDto, index: number) => 'ok-' + index.toString())
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  /** 跳回跟读 Tab 并进入「专项练习」（focus 音素过滤）。 */
  private startFocusPractice(token: string): void {
    if (token.length === 0) {
      NavigationService.pop();
      return;
    }
    PracticeFocus.set(token);
    AppStorage.setOrCreate<number>('tab_index', 0);
    NavigationService.clear();
  }

  /** 🧾 最近练习记录（20 条，可回放；对齐 Web /report 底部列表）。 */
  @Builder
  recentSection() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('🧾 最近练习记录')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Text('刷新')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .onClick(() => {
            void this.vm.loadRecent();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.recentLoading) {
        LoadingBlock({ text: '正在读最近记录…' })
      } else if (this.vm.recent.length === 0) {
        Text(this.vm.recentError.length > 0 ? this.vm.recentError : '还没有练习记录，先去跟读几句吧')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      } else {
        ForEach(this.vm.recent, (item: AttemptItemDto, index: number) => {
          Row({ space: EcSpace.x2 }) {
            Text(DiagnosisVM.recentTime(item.created_at === undefined ? '' : item.created_at))
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width(92)
            Text(this.session.isChild || DiagnosisVM.recentScore(item) < 0
              ? '—' : Math.round(DiagnosisVM.recentScore(item)).toString())
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(EcScore.colorByMode(this.session.isChild || DiagnosisVM.recentScore(item) < 0
                ? null : DiagnosisVM.recentScore(item), this.session.isChild))
              .width(36)
            Text(DiagnosisVM.recentText(item))
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.vm.playingAttemptId === item.id ? '播放中…' : '▶ 回放')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_primary'))
              .onClick(() => {
                void this.vm.playRecent(item.id);
              })
          }
          .width('100%')
          .padding(EcSpace.x2)
          .backgroundColor($r('app.color.ec_surface'))
          .borderRadius(EcRadius.sm)
          .alignItems(VerticalAlign.Center)
        }, (item: AttemptItemDto, index: number) => 'recent-' + item.id)
        if (this.vm.recentError.length > 0) {
          Text(this.vm.recentError)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_warn_text'))
            .width('100%')
        }
      }
    }
    .width('100%')
    .padding({ top: EcSpace.x2 })
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
          LoadingBlock({ text: '正在统计发音…' })
        } else if (this.vm.loadedOnce && this.vm.items.length === 0 && this.vm.okItems.length === 0) {
          EmptyState({
            icon: '📊',
            message: this.session.isChild
              ? '还没有够多的练习记录，多读几句就有报告啦'
              : '还没有足够的评测记录。每个音素至少 2 次评测才会统计，先去跟读几句吧',
            actionLabel: '返回去跟读练习',
            onAction: () => {
              NavigationService.pop();
            }
          })
        } else {
          ForEach(this.vm.items, (item: DiagnosisItemDto, index: number) => {
            this.itemCard(item)
          }, (item: DiagnosisItemDto, index: number) => 'diag-' + index.toString())

          if (this.vm.okItems.length > 0) {
            this.okSection()
          }
        }

        this.recentSection()

        if (this.vm.loadedOnce) {
          Text('诊断依据：每个音素的历次评测均分与最近 3 次趋势；' +
            (this.vm.minSamples < 2 ? '本口径 1 次的记录也参与。' : '1 次的记录不参与（噪声太大）。'))
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
            .padding({ bottom: EcSpace.x8 })
        }
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

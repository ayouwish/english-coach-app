import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { EmptyState } from '../components/EmptyState';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcScore, EcSpace } from '../design/DesignTokens';
import { BlindTestDto, BlindTrendScoreDto } from '../core/net/StatsDtos';
import { NavigationService } from '../core/router/NavigationService';
import { BlindRuntime } from '../core/session/BlindRuntime';import { SessionState } from '../core/session/SessionStore';
import { BlindTestVM } from '../viewmodel/StatsVM';

/**
 * 盲测（`/api/blind-tests`）：列表 + 创建/继续 + 结束 + 周报。
 *
 * 硬规则（practice-flow §6.3）：进行中**绝不显示任何分数**，只显示已评分/待评分条数；
 * 结束（finish）后才展示平均分，`notice` 非 null 必须显示黄条；`avg_*` 为 null 显示 —。
 * 录音提交在跟读/连读页完成（本页只做批次与周报）。
 */
@Component
export struct BlindTestPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: BlindTestVM = new BlindTestVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init(this.session.isChild);
  }

  private scoreText(value: number | null | undefined): string {
    if (value === undefined || value === null) {
      return '—';
    }
    return (Math.round(value * 10) / 10).toString();
  }

  private dateText(iso: string | null | undefined): string {
    if (iso === undefined || iso === null || iso.length === 0) {
      return '—';
    }
    const parsed = new Date(iso);
    const month = parsed.getMonth() + 1;
    const day = parsed.getDate();
    return month.toString() + '/' + day.toString();
  }

  private barHeight(score: number | null | undefined): number {
    if (score === undefined || score === null) {
      return 4;
    }
    const ratio = score / 100;
    const height = Math.round(ratio * 100);
    return height < 4 ? 4 : height;
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.session.isChild ? '🎯 小测验（不给分数哦）' : '🎯 盲测（Blind Test）')
          .fontSize(this.session.isChild ? EcFont.childH1 : EcFont.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Text('刷新')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
          .backgroundColor($r('app.color.ec_primary_soft'))
          .borderRadius(EcRadius.pill)
          .accessibilityText('刷新盲测列表')
          .onClick(() => {
            void this.vm.load();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.session.isChild
        ? '同一组句子、全程不给分数，做完才看得到结果 —— 这样才测得准 🙂'
        : '同一组句子、全程不给任何反馈，和上一次的成绩对比 —— 这是唯一能证明「真的进步了」的指标。')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .lineHeight(22)
        .width('100%')

      if (this.session.isChild) {
        Text('你好 ' + this.session.displayName + '！')
          .fontSize(EcFont.body)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
      }

      if (this.vm.pendingTotal > 0) {
        Text('⏳ 还有 ' + this.vm.pendingTotal.toString() +
          ' 条暂时显示为待评分（后台评分中…），报告里的平均分只基于已评完的记录')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
          .padding(EcSpace.x2)
          .backgroundColor($r('app.color.ec_warn_bg'))
          .borderRadius(EcRadius.sm)
      }

      if (this.vm.startError.length > 0) {
        Text(this.vm.startError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
      if (this.vm.finishError.length > 0) {
        Text(this.vm.finishError)
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
  inProgressCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('🎯 盲测进行中')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Chip({ text: '第 ' + (this.vm.inProgressScored + 1).toString() + ' / ' +
          this.vm.inProgressTotal.toString() + ' 句', tone: 'primary' })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('这一轮不会有任何分数和反馈，读完才看得到结果。')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Text('已评完 ' + this.vm.inProgressScored.toString() + ' 句 · 待评分 ' +
        this.vm.inProgressPending.toString() + ' 句')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')

      if (this.vm.inProgressPending > 0) {
        Text('还有 ' + this.vm.inProgressPending.toString() +
          ' 条在后台评分，现在结束的话报告里会显示为「待评分」，不影响已评完的平均分。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
          .padding(EcSpace.x2)
          .backgroundColor($r('app.color.ec_warn_bg'))
          .borderRadius(EcRadius.sm)
      }

      EcButton({
        label: this.vm.finishing ? '正在结束…' : '结束并查看周报',
        kind: EcButtonKind.PRIMARY,
        loading: this.vm.finishing,
        onTap: () => {
          void this.finishAndClear();
        }
      })
      EcButton({
        label: '返回去跟读练习（补读几句）',
        kind: EcButtonKind.GHOST,
        onTap: () => {
          NavigationService.pop();
        }
      })
      EcButton({
        label: '退出盲测，回普通跟读',
        kind: EcButtonKind.GHOST,
        onTap: () => {
          // 只退出本机盲测模式；服务端批次仍是进行中，下次进来可继续
          BlindRuntime.clear();
          AppStorage.setOrCreate<number>('tab_index', 0);
          NavigationService.clear();
        }
      })
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .border({ width: 1, color: $r('app.color.ec_primary') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  finishResultCard() {
    Column({ space: EcSpace.x2 }) {
      Text('🎉 盲测完成')
        .fontSize(EcFont.h3)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')

      if (this.vm.finishNotice.length > 0) {
        Text(this.vm.finishNotice)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
          .padding(EcSpace.x2)
          .backgroundColor($r('app.color.ec_warn_bg'))
          .borderRadius(EcRadius.sm)
      }

      if (!this.session.isChild) {
        Row({ space: EcSpace.x3 }) {
          Column({ space: EcSpace.x1 }) {
            Text(this.scoreText(this.vm.finishPron))
              .fontSize(40)
              .fontWeight(FontWeight.Bold)
              .fontColor(EcScore.color(this.vm.finishPron))
            Text('综合分')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          .alignItems(HorizontalAlign.Center)

          Column({ space: EcSpace.x1 }) {
            Text('准确度 ' + this.scoreText(this.vm.finishAccuracy))
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
            Text('流利度 ' + this.scoreText(this.vm.finishFluency))
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
            Text('语调差异 ' + this.scoreText(this.vm.finishIntonation))
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      Text('本次平均分基于 ' + this.vm.finishScored.toString() + ' 条已评分记录' +
        (this.vm.finishPending > 0
          ? ('（另有 ' + this.vm.finishPending.toString() + ' 条待评分，未计入）。') : '。'))
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      EcButton({
        label: '📈 去看周报',
        kind: EcButtonKind.TONAL,
        onTap: () => {
          this.vm.clearFinish();
        }
      })
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  reportCard() {
    Column({ space: EcSpace.x3 }) {
      Row({ space: EcSpace.x2 }) {
        Text('📈 盲测周报')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Text('已完成 ' + this.vm.weeks.toString() + ' 次')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.session.isChild) {
        Row({ space: EcSpace.x3 }) {
          Column({ space: EcSpace.x1 }) {
            Text(this.scoreText(this.vm.currentPron))
              .fontSize(44)
              .fontWeight(FontWeight.Bold)
              .fontColor(EcScore.color(this.vm.currentPron))
            Text('最近一次盲测综合分')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          .alignItems(HorizontalAlign.Center)

          Column({ space: EcSpace.x1 }) {
            Text('与上一次相比')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
            Text(this.vm.deltaText())
              .fontSize(EcFont.h3)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.vm.deltaColor())
            Text('上次：' + this.scoreText(this.vm.previousPron) + ' 分')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: EcSpace.x1 }) {
            Text('准确度 ' + this.scoreText(this.vm.currentAccuracy))
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
            Text('流利度 ' + this.scoreText(this.vm.currentFluency))
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
            Text('语调差异 ' + this.scoreText(this.vm.currentIntonation))
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Text('你做完 ' + this.vm.weeks.toString() + ' 次小测验啦，做得很好！')
          .fontSize(EcFont.body)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
      }

      if (this.vm.series.length > 0) {
        Text('历次盲测（柱越高越好）')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        Row({ space: EcSpace.x2 }) {
          ForEach(this.vm.series, (item: BlindTrendScoreDto, index: number) => {
            Column({ space: EcSpace.x1 }) {
              if (!this.session.isChild) {
                Text(this.scoreText(item.avg_pron))
                  .fontSize(EcFont.micro)
                  .fontColor($r('app.color.ec_muted'))
              }
              Row()
                .width(18)
                .height(this.barHeight(item.avg_pron))
                .backgroundColor(index === this.vm.series.length - 1
                  ? $r('app.color.ec_primary') : $r('app.color.ec_primary_soft'))
                .borderRadius(4)
              Text(this.dateText(item.ended_at))
                .fontSize(9)
                .fontColor($r('app.color.ec_muted'))
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.End)
            .height(120)
          }, (item: BlindTrendScoreDto, index: number) => 'bar-' + index.toString())
        }
        .width('100%')
        .height(120)
        .alignItems(VerticalAlign.Bottom)
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  historyCard() {
    Column({ space: EcSpace.x2 }) {
      Text('历史记录')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      ForEach(this.vm.tests, (test: BlindTestDto) => {
        Row({ space: EcSpace.x2 }) {
          Column({ space: EcSpace.x1 }) {
            Text(this.dateText(test.ended_at) + ' · ' +
              (test.item_count === undefined ? 0 : test.item_count).toString() + ' 句')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
              .width('100%')
            Text(this.session.isChild
              ? ((test.pending !== undefined && test.pending > 0) ? '还有待评分' : '已完成')
              : ('综合分 ' + this.scoreText(test.avg_pron) + ' · 准确 ' + this.scoreText(test.avg_accuracy) +
                ' · 流利 ' + this.scoreText(test.avg_fluency) + ' · 语调差异 ' +
                this.scoreText(test.avg_intonation_distance)))
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          if (test.pending !== undefined && test.pending > 0) {
            Chip({ text: '待评分 ' + test.pending.toString(), tone: 'warn' })
          }
        }
        .width('100%')
        .padding({ top: EcSpace.x2, bottom: EcSpace.x2 })
        .alignItems(VerticalAlign.Center)
      }, (test: BlindTestDto) => test.id)
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  /** 开始盲测：拿到抽题后回跟读 Tab 进入「不显示分数」的盲测模式。 */
  private async startAndGo(): Promise<void> {
    const ok = await this.vm.start();
    if (!ok) {
      return;
    }
    if (this.vm.startTestId.length > 0 && this.vm.startSentenceIds.length > 0) {
      BlindRuntime.begin(this.vm.startTestId, this.vm.startSentenceIds, this.vm.startTotal);
      AppStorage.setOrCreate<number>('tab_index', 0);
      NavigationService.clear();
    }
  }

  private async finishAndClear(): Promise<void> {
    const ok = await this.vm.finish();
    if (ok) {
      BlindRuntime.clear();
    }
  }

  @Builder
  startCard() {
    Column({ space: EcSpace.x2 }) {
      EcButton({
        label: this.vm.starting ? '正在开始…' : '开始盲测',
        kind: EcButtonKind.PRIMARY,
        big: this.session.isChild,
        loading: this.vm.starting,
        onTap: () => {
          void this.startAndGo();
        }
      })
      Text('抽题来自你练过的语料；同一用户每次得到同一组句子。没有练过的句子时服务端会提示先练习。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
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
          LoadingBlock({ text: '正在取盲测记录…' })
        } else {
          if (this.vm.tests.length === 0 && !this.vm.hasInProgress) {
            EmptyState({
              icon: '🎯',
              message: this.session.isChild
                ? '还没有做过小测验。先去读几句，再来试试'
                : '还没有完成过盲测。先做一次，下周再做一次，就能看到「到底有没有变好」了'
            })
          }

          if (this.vm.hasInProgress) {
            this.inProgressCard()
          } else {
            this.startCard()
          }

          if (this.vm.hasFinishResult) {
            this.finishResultCard()
          }

          if (this.vm.hasFinished()) {
            this.reportCard()
            this.historyCard()
          }
        }

        Column({ space: EcSpace.x2 }) {
          EcButton({
            label: '🎙 返回去跟读练习',
            kind: EcButtonKind.TONAL,
            onTap: () => {
              NavigationService.pop();
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

import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcScore, EcSpace } from '../design/DesignTokens';
import {
  ParentBlindScoreDto,
  ParentChildDto,
  ParentMemberDto,
  ParentPhonemeDto,
  ParentWordDto
} from '../core/net/AccountDtos';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { ParentVM } from '../viewmodel/AccountVM';

/**
 * 家长面板（`GET /api/parent/summary`，仅家长；儿童 403 只提示「家长专用」，不跳登录）。
 * 展示：全家汇总 / 儿童剩余时长 / 盲测周环比 / 成员今日·近 7 天·高频错音。
 */
@Component
export struct ParentPage {
  @State vm: ParentVM = new ParentVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init();
  }

  private barHeight(score: number | null | undefined): number {
    if (score === undefined || score === null) {
      return 4;
    }
    const height = Math.round((score / 100) * 90);
    return height < 4 ? 4 : height;
  }

  private dateText(iso: string | undefined): string {
    if (iso === undefined || iso.length === 0) {
      return '—';
    }
    const parsed = new Date(iso);
    return (parsed.getMonth() + 1).toString() + '/' + parsed.getDate().toString();
  }

  @Builder
  forbiddenView() {
    Column({ space: EcSpace.x3 }) {
      Text('👨‍👩‍👧')
        .fontSize(44)
      Text('家长面板仅对家长账号开放')
        .fontSize(EcFont.h3)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
      Text(this.vm.error.message)
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_muted'))
        .textAlign(TextAlign.Center)
      EcButton({
        label: '返回',
        kind: EcButtonKind.TONAL,
        btnWidth: '160vp',
        onTap: () => {
          NavigationService.pop();
        }
      })
    }
    .width('100%')
    .padding({ top: EcSpace.x10, left: EcSpace.x6, right: EcSpace.x6 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  summaryCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('👨‍👩‍👧 家长面板')
          .fontSize(EcFont.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Text('刷新')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
          .backgroundColor($r('app.color.ec_primary_soft'))
          .borderRadius(EcRadius.pill)
          .accessibilityText('刷新家长面板')
          .onClick(() => {
            void this.vm.load();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.vm.familyText())
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .lineHeight(22)
        .width('100%')

      if (this.vm.children.length > 0) {
        Row({ space: EcSpace.x2 }) {
          ForEach(this.vm.children, (child: ParentChildDto) => {
            Column({ space: EcSpace.x1 }) {
              Text((child.display_name === undefined ? '孩子' : child.display_name) + ' 今日剩余时长')
                .fontSize(EcFont.micro)
                .fontColor(Color.White)
              Text(this.vm.childRemainingText(child))
                .fontSize(EcFont.h3)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }
            .layoutWeight(1)
            .padding(EcSpace.x3)
            .backgroundColor($r('app.color.ec_primary'))
            .borderRadius(EcRadius.md)
            .alignItems(HorizontalAlign.Start)
          }, (child: ParentChildDto) => child.id)
        }
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
  blindPanel(member: ParentMemberDto) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.vm.memberTitle(member))
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        if (member.blind !== undefined && member.blind.in_progress_id !== undefined &&
          member.blind.in_progress_id !== null) {
          Chip({ text: '正在做盲测…', tone: 'warn' })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: EcSpace.x3 }) {
        Column({ space: EcSpace.x1 }) {
          Text(ParentVM.scoreText(this.vm.blindCurrentPron(member)))
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor(EcScore.color(this.vm.blindCurrentPron(member)))
          Text('最近一次盲测综合分')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        .alignItems(HorizontalAlign.Center)

        Column({ space: EcSpace.x1 }) {
          Text('本周 vs 上次')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
          Text(this.vm.blindDeltaText(member))
            .fontSize(EcFont.h3)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.vm.blindDeltaColor(member))
          Text('已完成盲测 ' + this.vm.blindWeeks(member).toString() + ' 次')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: EcSpace.x1 }) {
          Text('准确度 ' + ParentVM.scoreText(this.vm.blindAccuracy(member)))
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
          Text('流利度 ' + ParentVM.scoreText(this.vm.blindFluency(member)))
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
          Text('语调差异 ' + ParentVM.scoreText(this.vm.blindIntonation(member)))
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.blindSeries(member).length > 0) {
        Row({ space: EcSpace.x2 }) {
          ForEach(this.vm.blindSeries(member), (item: ParentBlindScoreDto, index: number) => {
            Column({ space: EcSpace.x1 }) {
              Text(ParentVM.scoreText(item.avg_pron))
                .fontSize(EcFont.micro)
                .fontColor($r('app.color.ec_muted'))
              Row()
                .width(18)
                .height(this.barHeight(item.avg_pron))
                .backgroundColor(index === this.vm.blindSeries(member).length - 1
                  ? $r('app.color.ec_primary') : $r('app.color.ec_primary_soft'))
                .borderRadius(4)
              Text(this.dateText(item.ended_at))
                .fontSize(9)
                .fontColor($r('app.color.ec_muted'))
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.End)
            .height(110)
          }, (item: ParentBlindScoreDto, index: number) => 'b-' + index.toString())
        }
        .width('100%')
        .height(110)
        .alignItems(VerticalAlign.Bottom)
      } else {
        Text('还没有完成的盲测。让孩子去「🎯 盲测周报」做一次（同一组句子、无反馈），下周再做一次就能看到环比。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .border({ width: 2, color: $r('app.color.ec_primary') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  memberCard(member: ParentMemberDto) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.vm.memberTitle(member))
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Chip({ text: this.vm.memberBadge(member), tone: 'muted' })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.vm.memberTodayText(member))
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')

      Text(this.vm.memberWeekText(member))
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Text('平均分趋势（近 14 天）：' + this.vm.trendTail(member))
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      if (this.vm.topPhonemes(member).length > 0) {
        Text('高频错音 TOP' + this.vm.topPhonemes(member).length.toString())
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        ForEach(this.vm.topPhonemes(member), (item: ParentPhonemeDto, index: number) => {
          Row({ space: EcSpace.x2 }) {
            Text(this.vm.phonemeText(item))
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
              .layoutWeight(1)
            Text(this.vm.phonemeMeta(item))
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          .width('100%')
          .padding({ top: 2, bottom: 2 })
        }, (item: ParentPhonemeDto, index: number) => 'p-' + index.toString())
      } else {
        Text('高频错音：暂无数据')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      if (this.vm.topWords(member).length > 0) {
        Text('高频错词（单词级粗评）')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.vm.topWords(member), (item: ParentWordDto, index: number) => {
            Text(this.vm.wordText(item))
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_warn_text'))
              .backgroundColor($r('app.color.ec_warn_bg'))
              .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 3, bottom: 3 })
              .borderRadius(EcRadius.pill)
              .margin({ right: EcSpace.x2, bottom: EcSpace.x2 })
          }, (item: ParentWordDto, index: number) => 'w-' + index.toString())
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

  build() {
    Scroll() {
      Column({ space: EcSpace.x3 }) {
        if (this.vm.forbidden) {
          this.forbiddenView()
        } else {
          this.summaryCard()

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
            LoadingBlock({ text: '正在汇总全家的练习数据…' })
          } else if (this.vm.loadedOnce) {
            Text('🎯 盲测周环比 · 判断「到底有没有变好」')
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
            Text('同一组句子、全程不给反馈。日常练习的分数会因为「看完反馈立刻重读」而虚高，只有盲测能证明真的进步了。')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')

            ForEach(this.vm.members, (member: ParentMemberDto) => {
              if (member.role === 'child') {
                this.blindPanel(member)
              }
            }, (member: ParentMemberDto) => 'blind-' + member.id)

            Text('成员明细')
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
              .padding({ top: EcSpace.x2 })

            ForEach(this.vm.members, (member: ParentMemberDto) => {
              this.memberCard(member)
            }, (member: ParentMemberDto) => 'member-' + member.id)

            Column({ space: EcSpace.x2 }) {
              EcButton({
                label: '👥 家庭成员管理',
                kind: EcButtonKind.TONAL,
                onTap: () => {
                  NavigationService.push(Routes.FAMILY);
                }
              })
              EcButton({
                label: '📈 查看盲测周报',
                kind: EcButtonKind.GHOST,
                onTap: () => {
                  NavigationService.push(Routes.BLIND_TEST);
                }
              })
            }
            .width('100%')
            .padding(EcSpace.x2)
          }
        }
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4, bottom: EcSpace.x8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .scrollBar(BarState.Off)
  }
}

import { Chip, TopBar } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { EmptyState } from '../components/EmptyState';
import { LoadingBlock } from '../components/LoadingBlock';
import { ScoreRing, SubScoreBar } from '../components/ScoreViews';
import { EcFont, EcRadius, EcScore, EcShadow, EcSpace } from '../design/DesignTokens';
import { FlowDiagnosisDto, FlowDiagnosisItemDto } from '../core/net/FlowDtos';
import { FlowService } from '../core/service/FlowService';
import { PracticeService } from '../core/service/PracticeService';
import { AudioController } from '../core/audio/AudioController';
import { NavigationService } from '../core/router/NavigationService';
import { NavState } from '../core/router/NavState';
import { Routes } from '../core/router/Routes';
import {
  FlowItem,
  FlowRunStore,
  FlowStatus,
  FlowSummaryData,
  FlowVM,
  FlowWorstItem
} from '../viewmodel/FlowVM';

/**
 * 连读汇总（push 出来的二级页）。
 *
 * 数据来自 `FlowRunStore`（同一进程内的 FlowVM 快照）；页面自己负责：
 * - 本地 6 档鼓励语（VM 已按本批 attempt id 确定性挑选）；
 * - `GET /diagnosis?scope=batch&attempt_ids=`（≤20）→「这一批的问题」；
 * - 逐条列表（可展开，失败行可「重录这句」回 running）。
 */
@Component
export struct FlowSummaryPage {
  @State data: FlowSummaryData = new FlowSummaryData();
  @State ready: boolean = false;
  @State isChild: boolean = false;
  @State items: FlowItem[] = [];
  @State expandedIndex: number = -1;
  @State diagLoading: boolean = false;
  @State diagError: string = '';
  @State diagSummary: string = '';
  @State diagLabels: string[] = [];
  @State diagTones: string[] = [];
  @State encPlaying: boolean = false;
  @State encError: string = '';
  private vm: FlowVM | null = null;

  aboutToAppear(): void {
    const run = FlowRunStore.current();
    this.vm = run;
    if (run === null) {
      this.ready = false;
      return;
    }
    this.isChild = run.isChild;
    this.data = run.buildSummary();
    this.items = this.data.items;
    this.ready = true;
    void this.loadDiagnosis();
  }

  private async loadDiagnosis(): Promise<void> {
    const ids = this.data.attemptIds;
    if (ids.length === 0) {
      return;
    }
    this.diagLoading = true;
    this.diagError = '';
    try {
      const dto: FlowDiagnosisDto = await FlowService.diagnosisBatch(ids);
      const summary = dto.summary_zh;
      this.diagSummary = summary === undefined ? '' : summary;
      const list = dto.items === undefined ? [] : dto.items;
      const labels: string[] = [];
      const tones: string[] = [];
      for (let i = 0; i < list.length && i < 5; i++) {
        const item = list[i];
        const label = this.diagnosisLabel(item);
        if (label.length > 0) {
          labels.push(label);
          tones.push(this.diagnosisTone(item.status));
        }
      }
      this.diagLabels = labels;
      this.diagTones = tones;
      if (labels.length === 0 && this.diagSummary.length === 0) {
        this.diagSummary = this.isChild ? '这一批读得不错，继续保持' : '这一批没有明显的薄弱音素，保持就好 👍';
      }
    } catch (err) {
      this.diagError = this.isChild
        ? '这一批的问题暂时没有读到，可以稍后再看'
        : '读取这一批的诊断失败，可以稍后再试';
    } finally {
      this.diagLoading = false;
    }
  }

  private diagnosisLabel(item: FlowDiagnosisItemDto): string {
    const phoneme = item.phoneme === undefined ? '' : item.phoneme;
    const childLabel = item.child_label === undefined ? '' : item.child_label;
    let label = '';
    if (this.isChild) {
      // 儿童绝不出现 IPA：只认 child_label（口语化名字），没有就整条不展示
      label = childLabel;
    } else if (phoneme.length > 0) {
      label = '/' + phoneme + '/';
      if (childLabel.length > 0) {
        label = label + ' ' + childLabel;
      }
    } else {
      label = childLabel;
    }
    const avg = item.avg_score === undefined || item.avg_score === null ? -1 : item.avg_score;
    // 儿童低分不显示数字（EcScore.showNumber 同一规则）
    if (avg >= 0 && EcScore.showNumber(avg, this.isChild)) {
      label = label + ' · ' + Math.round(avg).toString() + ' 分';
    }
    return label;
  }

  private diagnosisTone(status: string | undefined): string {
    if (status === 'weak') {
      return this.isChild ? 'warn' : 'bad';
    }
    if (status === 'watch') {
      return 'warn';
    }
    if (status === 'ok') {
      return 'good';
    }
    return 'muted';
  }

  private encouragementZh(): string {
    const enc = this.data.encouragement;
    if (enc.praise.length > 0) {
      return enc.zh + enc.praise;
    }
    return enc.zh;
  }

  private summaryLine(): string {
    let text = '共 ' + this.data.total.toString() + ' 句 · 已评分 ' + this.data.doneCount.toString() + ' 句';
    if (this.data.failedCount > 0) {
      text = text + ' · 失败 ' + this.data.failedCount.toString() + ' 句';
    }
    if (this.data.avgScore >= 0 && EcScore.showNumber(this.data.avgScore, this.isChild)) {
      text = text + ' · 平均 ' + this.data.avgScore.toString() + ' 分';
    }
    if (this.data.round > 1) {
      text = text + ' · 第 ' + this.data.round.toString() + ' 遍';
    }
    return text;
  }

  // ================================================================== 区块

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('🎉 ' + (this.isChild ? '读完啦！' : '连读完成'))
          .fontSize(EcFont.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        if (this.data.round > 1) {
          Chip({ text: '第 ' + this.data.round.toString() + ' 遍', tone: 'primary' })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(this.summaryLine())
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x5)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  encouragementCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('🎙')
          .fontSize(22)
        Text(this.isChild ? '听听夸奖' : '鼓励语')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .layoutWeight(1)
        Text(this.encPlaying ? '🔊 播放中…' : '🔊 听鼓励')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText('播放鼓励语')
          .onClick(() => {
            void this.playEncouragement();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(this.encouragementZh())
        .fontSize(this.isChild ? EcFont.childBody : EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      Text(this.data.encouragement.en)
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      if (this.encError.length > 0) {
        Text(this.encError)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_primary_soft'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  /** 中→英顺序播放鼓励语（与 Web 一致；语音不可用只提示，不影响文字）。 */
  private async playEncouragement(): Promise<void> {
    if (this.encPlaying) {
      return;
    }
    this.encPlaying = true;
    this.encError = '';
    try {
      const zh = this.encouragementZh();
      if (zh.length > 0) {
        const zhPath = await PracticeService.fetchTtsFile(zh, 'slow', 'zh-CN-XiaoxiaoNeural', 'mp3');
        await this.playAndWait(zhPath);
      }
      const en = this.data.encouragement.en;
      if (en.length > 0) {
        const enPath = await PracticeService.fetchTtsFile(en, 'normal', 'en-US-JennyNeural', 'mp3');
        await this.playAndWait(enPath);
      }
    } catch (err) {
      this.encError = '语音暂时不可用，文字照常看就行';
    } finally {
      this.encPlaying = false;
    }
  }

  private playAndWait(path: string): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      AudioController.play(path, () => {
        resolve();
      }).catch(() => {
        resolve();
      });
    });
  }

  @Builder
  diagnosisCard() {
    Column({ space: EcSpace.x2 }) {
      Text('这一批（' + this.data.doneCount.toString() + ' 句）的问题')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      if (this.diagLoading) {
        LoadingBlock({ text: '正在统计…' })
      } else if (this.diagError.length > 0) {
        Text(this.diagError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
      } else {
        if (this.diagSummary.length > 0) {
          Text(this.diagSummary)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
        }
        if (this.diagLabels.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.diagLabels, (label: string, index: number) => {
              Chip({
                text: label,
                tone: index < this.diagTones.length ? this.diagTones[index] : 'muted'
              })
            }, (label: string, index: number) => label + index.toString())
          }
          .width('100%')
        }
        if (this.data.doneCount === 0) {
          Text('这一批还没有评完的句子，暂时没有诊断')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  worstCard() {
    Column({ space: EcSpace.x1 }) {
      Text(this.isChild ? '这几句可以再读一遍' : '最需要再练的几句')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      if (this.data.worst.length === 0) {
        Text('这一批没有拿到分数，先不用纠结分数，读得开心最重要 🙂')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      } else {
        ForEach(this.data.worst, (row: FlowWorstItem) => {
          Text(this.worstLine(row))
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }, (row: FlowWorstItem) => 'worst' + row.index.toString())
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  private worstLine(row: FlowWorstItem): string {
    if (this.isChild) {
      return '· ' + row.text;
    }
    return '· ' + (row.score < 0 ? '—' : Math.round(row.score).toString()) + ' 分 · ' + row.text;
  }

  @Builder
  actionRow() {
    Column({ space: EcSpace.x2 }) {
      EcButton({
        label: this.isChild ? '🔁 再读一遍～' : '🔁 再读一遍',
        kind: EcButtonKind.PRIMARY,
        big: this.isChild,
        onTap: () => {
          const run = this.vm;
          if (run === null) {
            NavigationService.pop();
            return;
          }
          run.reread();
          NavigationService.pop();
        }
      })
      if (this.storyMaterialId().length > 0) {
        EcButton({
          label: this.isChild ? '📝 讲讲这个故事' : '📝 复述这个故事',
          kind: EcButtonKind.TONAL,
          onTap: () => {
            const id = this.storyMaterialId();
            if (id.length > 0) {
              NavState.setStory(id, null);
              NavigationService.push(Routes.STORY_REVIEW);
            }
          }
        })
      }
      EcButton({
        label: '再读一段',
        kind: EcButtonKind.GHOST,
        onTap: () => {
          const run = this.vm;
          if (run !== null) {
            run.backToSetup();
          }
          NavigationService.pop();
        }
      })
    }
    .width('100%')
  }

  /** 从故事进入的连读：summary 上给「复述」入口。 */
  private storyMaterialId(): string {
    const run = FlowRunStore.current();
    if (run === null) {
      return '';
    }
    return run.runMaterialId;
  }

  // ================================================================== 逐条列表

  @Builder
  itemRow(item: FlowItem) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text((item.index + 1).toString() + '. ' + item.text)
          .fontSize(this.isChild ? EcFont.body : EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Chip({ text: this.statusBadge(item), tone: this.statusTone(item) })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (item.status === FlowStatus.FAILED) {
        Row({ space: EcSpace.x2 }) {
          Text(item.error.length > 0 ? item.error : '评分没有成功')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_bad_text'))
            .maxLines(2)
            .layoutWeight(1)
          Text('重录这句')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_primary'))
            .onClick(() => {
              this.redo(item.index);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      if (this.expandedIndex === item.index && item.hasResult) {
        this.detailBlock(item)
      }
    }
    .width('100%')
    .padding(EcSpace.x3)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.md)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (item.hasResult || item.status === FlowStatus.FAILED) {
        this.expandedIndex = this.expandedIndex === item.index ? -1 : item.index;
        const copy: FlowItem[] = [];
        for (let i = 0; i < this.items.length; i++) {
          copy.push(this.items[i]);
        }
        this.items = copy;
      }
    })
  }

  private redo(index: number): void {
    const run = this.vm;
    if (run === null) {
      NavigationService.pop();
      return;
    }
    run.retryItem(index);
    NavigationService.pop();
  }

  private statusBadge(item: FlowItem): string {
    if (item.status === FlowStatus.DONE) {
      if (item.scorePron < 0) {
        return '已评分';
      }
      return EcScore.showNumber(item.scorePron, this.isChild)
        ? (Math.round(item.scorePron).toString() + ' 分') : '已评分';
    }
    if (item.status === FlowStatus.SCORING) {
      return '评分中…';
    }
    if (item.status === FlowStatus.PENDING) {
      return '待评分…';
    }
    if (item.status === FlowStatus.FAILED) {
      return '评分失败';
    }
    return '未读';
  }

  private statusTone(item: FlowItem): string {
    if (item.status === FlowStatus.DONE) {
      return 'good';
    }
    if (item.status === FlowStatus.FAILED) {
      return 'bad';
    }
    if (item.status === FlowStatus.SCORING || item.status === FlowStatus.PENDING) {
      return 'primary';
    }
    return 'muted';
  }

  @Builder
  detailBlock(item: FlowItem) {
    Column({ space: EcSpace.x2 }) {
      if (item.noSpeech) {
        Text('这次好像没有听到声音，可以回连读页再读一次')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
      } else if (this.isChild) {
        Text(EcScore.encouragement(item.scorePron, true))
          .fontSize(EcFont.body)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
      } else {
        Row({ space: EcSpace.x3 }) {
          ScoreRing({
            score: item.scorePron < 0 ? 0 : item.scorePron,
            label: '这一句',
            isChild: false,
            ringSize: 72
          })
          Column({ space: 2 }) {
            SubScoreBar({ label: '准确', score: item.scoreAccuracy, isChild: false })
            SubScoreBar({ label: '流利', score: item.scoreFluency, isChild: false })
            SubScoreBar({ label: '完整', score: item.scoreCompleteness, isChild: false })
            SubScoreBar({ label: '语调', score: item.scoreProsody, isChild: false })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      if (item.feedbackSummary.length > 0) {
        Text(item.feedbackSummary)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
      }
      if (item.feedbackPraise.length > 0) {
        Text('👍 ' + item.feedbackPraise)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      }
      if (item.wordTexts.length > 0 && !this.isChild) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(item.wordTexts, (word: string, index: number) => {
            Text(word + ' ' + (item.wordScores[index] < 0
              ? '—' : Math.round(item.wordScores[index]).toString()))
              .fontSize(EcFont.micro)
              .fontColor(EcScore.colorByMode(item.wordScores[index] < 0 ? null : item.wordScores[index], false))
              .backgroundColor($r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 2, bottom: 2 })
              .borderRadius(EcRadius.sm)
              .margin(2)
          }, (word: string, index: number) => item.index.toString() + 'w' + index.toString())
        }
        .width('100%')
      }
      if (item.issueTexts.length > 0) {
        ForEach(item.issueTexts, (text: string, index: number) => {
          Text('· ' + text)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_warn_text'))
            .width('100%')
        }, (text: string, index: number) => item.index.toString() + 'i' + index.toString())
      }
      if (item.feedbackClosing.length > 0) {
        Text(item.feedbackClosing)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ top: EcSpace.x2 })
    .alignItems(HorizontalAlign.Start)
  }

  // ================================================================== 页面

  build() {
    Column() {
      TopBar({
        title: this.isChild ? '读完啦' : '连读汇总',
        onBack: () => {
          NavigationService.pop();
        }
      })
      if (!this.ready) {
        EmptyState({
          icon: '🎉',
          message: '还没有读完一轮连读',
          actionLabel: '返回连读',
          onAction: () => {
            NavigationService.pop();
          }
        })
      } else {
        Scroll() {
          Column({ space: EcSpace.x3 }) {
            this.headerCard()
            this.encouragementCard()
            this.diagnosisCard()
            this.worstCard()
            this.actionRow()
            Text('逐条列表（点一行展开详情）')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
            ForEach(this.items, (item: FlowItem) => {
              this.itemRow(item)
            }, (item: FlowItem) => 'summary' + item.index.toString() + '_' + item.status + '_'
              + Math.round(item.scorePron).toString() + '_'
              + (this.expandedIndex === item.index ? 'e' : 'n'))
          }
          .width('100%')
          .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x8 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
  }
}

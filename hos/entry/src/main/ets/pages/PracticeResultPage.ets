import { EcButton, EcButtonKind } from '../components/EcButton';
import { LoadingBlock } from '../components/LoadingBlock';
import { PitchChart, RadarChart, SparkLine } from '../components/Charts';
import { EcFont, EcRadius, EcScore, EcSpace } from '../design/DesignTokens';
import { WordScoreDto } from '../core/net/Dtos';
import { SessionState } from '../core/session/SessionStore';
import { NavigationService } from '../core/router/NavigationService';
import { PracticeResultStore } from '../core/session/PracticeResultStore';
import { PracticeVM, ResultIssue } from '../viewmodel/PracticeVM';

/**
 * 跟读结果详情页（push 出来的全屏页）。
 *
 * 两种模式：
 * - `result`：本次评分的完整详情（问题音素/历史/评分/点评/雷达/逐词/F0/纠错）
 * - `history`：这一句的历史朗读（折线 + 首末对比 + 逐条回放），**不需要先录音**也能看
 */
@Component
export struct PracticeResultPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: PracticeVM = new PracticeVM();
  @State mode: string = 'result';
  @State playingId: string = '';
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    const source = PracticeResultStore.vm;
    if (source !== null && source !== undefined) {
      this.vm = source;
    }
    this.mode = PracticeResultStore.mode;
    if (this.mode === 'history') {
      void this.vm.loadHistory();
    }
  }

  aboutToDisappear(): void {
    PracticeResultStore.clear();
  }

  private playHistory(attemptId: string): void {
    this.playingId = attemptId;
    void this.vm.playHistoryAudio(attemptId);
    setTimeout(() => {
      if (this.playingId === attemptId) {
        this.playingId = '';
      }
    }, 20000);
  }

  /** 历史列表点「详情」：用这条 attempt 还原完整结果（不重新录音）。 */
  private async openAttempt(attemptId: string): Promise<void> {
    const ok = await this.vm.openAttemptResult(attemptId);
    if (ok) {
      this.mode = 'result';
    }
  }

  /** 低于 60 分的词数（用于提示文案；列表只展示一遍） */
  private needPracticeCount(): number {
    let count = 0;
    for (let i = 0; i < this.vm.wordDetails.length; i++) {
      const score = this.vm.wordDetails[i].score;
      if (score !== undefined && score !== null && score < 60) {
        count = count + 1;
      }
    }
    return count;
  }

  private weakestAxisText(): string {    let bestLabel = '';
    let bestValue = 101;
    const labels: string[] = ['准确', '流利', '完整', '节奏'];
    const values: number[] = [this.vm.scoreAccuracy, this.vm.scoreFluency,
      this.vm.scoreCompleteness, this.vm.scoreProsody];
    for (let i = 0; i < values.length; i++) {
      if (values[i] >= 0 && values[i] < bestValue) {
        bestValue = values[i];
        bestLabel = labels[i];
      }
    }
    if (bestLabel.length === 0) {
      return '—';
    }
    return bestLabel + ' ' + (Math.round(bestValue * 10) / 10).toString();
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(EcFont.body)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.ec_ink'))
      .width('100%')
      .padding({ top: EcSpace.x2 })
  }

  @Builder
  wordBar(word: string, score: number) {
    Row({ space: 6 }) {
      Text(word)
        .fontSize(EcFont.caption)
        .fontColor(score >= 0 && score < 60 ? $r('app.color.ec_bad_text') : $r('app.color.ec_ink'))
        .width(120)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(8)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(4)
        if (score > 0) {
          Row()
            .width(score.toString() + '%')
            .height(8)
            .backgroundColor(EcScore.color(score))
            .borderRadius(4)
        }
      }
      .layoutWeight(1)
      .height(8)
      Text(score < 0 ? '—' : Math.round(score).toString())
        .fontSize(EcFont.micro)
        .fontColor(score < 0 ? $r('app.color.ec_muted') : EcScore.color(score))
        .width(34)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(24)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  historyBody() {
    Column({ space: EcSpace.x3 }) {
      if (this.vm.historyLoading) {
        LoadingBlock({ text: '正在读这一句的历史…' })
      } else if (this.vm.historyScores.length === 0) {
        Text(this.session.isChild ? '这一句还没有读过，先读一遍吧 🙂' : '这一句还没有历史记录，先读一遍再来看进步曲线')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .padding({ top: EcSpace.x4 })
      } else {
        Text('共 ' + this.vm.historyScores.length.toString() + ' 次 · 这一句的进步曲线（旧→新）')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        SparkLine({ scores: this.vm.historyScores })
        if (this.vm.historyFirst >= 0 && this.vm.historyLast >= 0) {
          Row({ space: EcSpace.x2 }) {
            Text('首末对比：' + Math.round(this.vm.historyFirst).toString() + ' → ' +
              Math.round(this.vm.historyLast).toString())
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
            Text((this.vm.historyLast - this.vm.historyFirst >= 0 ? '+' : '') +
              (Math.round((this.vm.historyLast - this.vm.historyFirst) * 10) / 10).toString())
              .fontSize(EcFont.caption)
              .fontColor(this.vm.historyLast >= this.vm.historyFirst ? $r('app.color.ec_good_text') :
                $r('app.color.ec_bad_text'))
          }
          .width('100%')
        }
        Text('逐次记录（新→旧，可回放）')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        ForEach(this.vm.historyLabels, (label: string, index: number) => {
          Row({ space: EcSpace.x2 }) {
            Text(this.vm.historyLabels[this.vm.historyLabels.length - 1 - index])
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width(96)
            Text(Math.round(this.vm.historyScores[this.vm.historyScores.length - 1 - index]).toString())
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(EcScore.colorByMode(this.vm.historyScores[this.vm.historyScores.length - 1 - index],
                this.session.isChild))
              .width(40)
            Blank()
            if (this.vm.historyAttemptIds.length > index) {
              Text('详情')
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_ink'))
                .padding({ left: EcSpace.x2, right: EcSpace.x1, top: 3, bottom: 3 })
                .onClick(() => {
                  void this.openAttempt(this.vm.historyAttemptIds[this.vm.historyAttemptIds.length - 1 - index]);
                })
              Text(this.playingId ===
                this.vm.historyAttemptIds[this.vm.historyAttemptIds.length - 1 - index] ? '播放中…' : '▶ 回放')
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_primary'))
                .padding({ left: EcSpace.x1, right: EcSpace.x2, top: 3, bottom: 3 })
                .onClick(() => {
                  this.playHistory(this.vm.historyAttemptIds[this.vm.historyAttemptIds.length - 1 - index]);
                })
            }
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }, (label: string, index: number) => 'hh' + index.toString())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  resultBody() {
    Column({ space: EcSpace.x3 }) {
      // ---- 1. 这一句的问题
      if (this.vm.issueChipLabels.length > 0) {
        this.sectionTitle('这一句的问题')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.vm.issueChipLabels, (label: string, index: number) => {
            Text('/' + label + '/ ' + (this.vm.issueChipScores[index] < 0 ? '—' :
              Math.round(this.vm.issueChipScores[index]).toString()))
              .fontSize(EcFont.caption)
              .fontColor(EcScore.colorByMode(this.vm.issueChipScores[index] < 0 ? null : this.vm.issueChipScores[index],
                this.session.isChild))
              .backgroundColor($r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x3, right: EcSpace.x3, top: 4, bottom: 4 })
              .borderRadius(EcRadius.pill)
              .margin(3)
          }, (label: string, index: number) => 'ic' + index.toString())
        }
        .width('100%')
      }

      // ---- 2. 这一句的历史
      if (this.vm.historyScores.length > 0) {
        this.sectionTitle('这一句的历史（' + this.vm.historyScores.length.toString() + ' 次）')
        SparkLine({ scores: this.vm.historyScores })
        ForEach(this.vm.historyLabels, (label: string, index: number) => {
          Row({ space: EcSpace.x2 }) {
            Text(this.vm.historyLabels[this.vm.historyLabels.length - 1 - index])
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width(96)
            Text(Math.round(this.vm.historyScores[this.vm.historyScores.length - 1 - index]).toString())
              .fontSize(EcFont.caption)
              .fontColor(EcScore.colorByMode(this.vm.historyScores[this.vm.historyScores.length - 1 - index],
                this.session.isChild))
              .width(40)
            Blank()
            if (this.vm.historyAttemptIds.length > index) {
              Text(this.playingId ===
                this.vm.historyAttemptIds[this.vm.historyAttemptIds.length - 1 - index] ? '播放中…' : '▶ 回放')
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_primary'))
                .onClick(() => {
                  this.playHistory(this.vm.historyAttemptIds[this.vm.historyAttemptIds.length - 1 - index]);
                })
            }
          }
          .width('100%')
        }, (label: string, index: number) => 'hr' + index.toString())
      }

      // ---- 3. 本次评分
      this.sectionTitle('本次评分')
      Row({ space: EcSpace.x4 }) {
        Text(this.vm.scorePron < 0 ? '—' : (Math.round(this.vm.scorePron * 10) / 10).toString())
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
        Column({ space: EcSpace.x1 }) {
          this.wordBar('准确', this.vm.scoreAccuracy)
          this.wordBar('流利', this.vm.scoreFluency)
          this.wordBar('完整', this.vm.scoreCompleteness)
          this.wordBar('节奏', this.vm.scoreProsody)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (!this.session.isChild) {
        Text('综合分 = pron（契约口径，由 voice 计算）· 不可得项显示 —')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      if (this.vm.recognizedText.length > 0) {
        Text('识别结果：' + this.vm.recognizedText)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
      }
      if (this.vm.resultProvider.length > 0 || this.vm.attemptIdText.length > 0) {
        Text('provider: ' + (this.vm.resultProvider.length > 0 ? this.vm.resultProvider : '—') +
          ' · 粒度: ' + (this.vm.resultGranularity.length > 0 ? this.vm.resultGranularity : '—') +
          (this.vm.durationText.length > 0 ? ' · 时长: ' + this.vm.durationText : '') +
          (this.vm.attemptIdText.length > 0 ? ' · 记录: ' + this.vm.attemptIdText : ''))
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      // ---- 4. 整体点评
      if (this.vm.feedbackSummary.length > 0 || this.vm.pointTitles.length > 0) {
        this.sectionTitle('整体点评')
        Column({ space: EcSpace.x2 }) {
          if (this.vm.feedbackSummary.length > 0) {
            Text(this.vm.feedbackSummary)
              .fontSize(EcFont.body)
              .fontColor($r('app.color.ec_ink'))
              .width('100%')
          }
          if (this.vm.feedbackPraise.length > 0) {
            Text('👍 ' + this.vm.feedbackPraise)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_good_text'))
              .width('100%')
          }
          ForEach(this.vm.pointTitles, (title: string, index: number) => {
            Column({ space: 3 }) {
              Text('· ' + title)
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_ink'))
                .width('100%')
              if (index < this.vm.pointWhys.length && this.vm.pointWhys[index].length > 0) {
                Text('为什么：' + this.vm.pointWhys[index])
                  .fontSize(EcFont.micro)
                  .fontColor($r('app.color.ec_muted'))
                  .width('100%')
              }
              if (index < this.vm.pointHows.length && this.vm.pointHows[index].length > 0) {
                Text('怎么改：' + this.vm.pointHows[index])
                  .fontSize(EcFont.micro)
                  .fontColor($r('app.color.ec_muted'))
                  .width('100%')
              }
              if (index < this.vm.pointWords.length && this.vm.pointWords[index].length > 0) {
                Text('练习词：' + this.vm.pointWords[index])
                  .fontSize(EcFont.micro)
                  .fontColor($r('app.color.ec_primary'))
                  .width('100%')
              }
            }
            .width('100%')
            .padding(EcSpace.x2)
            .backgroundColor($r('app.color.ec_primary_soft'))
            .borderRadius(EcRadius.sm)
            .alignItems(HorizontalAlign.Start)
          }, (title: string, index: number) => 'pt' + index.toString())
          if (this.vm.feedbackClosing.length > 0) {
            Text(this.vm.feedbackClosing)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      // ---- 5. 能力多边形
      if (this.vm.scoreAccuracy >= 0 || this.vm.scoreFluency >= 0 ||
        this.vm.scoreCompleteness >= 0 || this.vm.scoreProsody >= 0) {
        this.sectionTitle('能力多边形')
        Row() {
          RadarChart({
            accuracy: this.vm.scoreAccuracy,
            fluency: this.vm.scoreFluency,
            completeness: this.vm.scoreCompleteness,
            prosody: this.vm.scoreProsody,
            isChild: this.session.isChild,
            chartSize: 300
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        Text('最需要练的是 ' + this.weakestAxisText())
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
      }

      // ---- 6. 逐词得分 + 音素明细（儿童也显示「每个词读得怎么样」，与 Web 一致；音素仅成人）
      if (this.vm.wordDetails.length > 0) {
        this.sectionTitle(this.session.isChild ? '🔤 每个词读得怎么样' : '逐词得分')
        // 只列一遍（句子顺序）；低于 60 分的词标红即可，不再单独重复一遍「需要练的词」
        Text(this.session.isChild
          ? '条越长读得越好；红色 = 低于 60 分，多练几遍就好'
          : '按句子顺序；红色 = 低于 60 分，需要重点练' +
            (this.needPracticeCount() > 0 ? '（这一句有 ' + this.needPracticeCount().toString() + ' 个）' : ''))
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        ForEach(this.vm.wordDetails, (word: WordScoreDto, index: number) => {
          this.wordBar(word.word, (word.score === undefined || word.score === null) ? -1 : (word.score as number))
        }, (word: WordScoreDto, index: number) => 'wd' + index.toString())
        if (!this.session.isChild && this.vm.phonemeChipLabels.length > 0) {
          Text('音素明细')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.vm.phonemeChipLabels, (label: string, index: number) => {
              Text(label + ' ' + (this.vm.phonemeChipScores[index] < 0 ? '—' :
                Math.round(this.vm.phonemeChipScores[index]).toString()))
                .fontSize(EcFont.micro)
                .fontColor(EcScore.colorByMode(this.vm.phonemeChipScores[index] < 0 ? null :
                  this.vm.phonemeChipScores[index], this.session.isChild))
                .backgroundColor($r('app.color.ec_surface_alt'))
                .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                .borderRadius(6)
                .margin(2)
            }, (label: string, index: number) => 'ph' + index.toString())
          }
          .width('100%')
        }
      }

      // ---- 7. 语调对比
      if (this.vm.intonationAvailable) {
        this.sectionTitle('语调对比（F0 双曲线）')
        Text('虚线是你的音高，灰线是示范音；蓝色实线是你的曲线；已按 DTW 对齐。' +
          (this.vm.intonationDistance.length > 0 ? ' 语调差异 ' + this.vm.intonationDistance + '（越小越接近）' : ''))
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        PitchChart({ user: this.vm.userF0, reference: this.vm.refF0, isChild: this.session.isChild })
        ForEach(this.vm.regionTexts, (text: string, index: number) => {
          Text('· ' + text)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_warn_text'))
            .width('100%')
        }, (text: string, index: number) => 'rg' + index.toString())
      }

      // ---- 8. 需要纠正的地方
      if (this.vm.issueCards.length > 0) {
        this.sectionTitle('需要纠正的地方')
        ForEach(this.vm.issueCards, (card: ResultIssue, index: number) => {
          Column({ space: 2 }) {
            Row({ space: EcSpace.x2 }) {
              Text(card.title)
                .fontSize(EcFont.caption)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ec_bad_text'))
                .layoutWeight(1)
              if (card.score >= 0) {
                Text(Math.round(card.score).toString() + ' 分')
                  .fontSize(EcFont.caption)
                  .fontColor(EcScore.color(card.score))
              }
            }
            .width('100%')
            if (card.word.length > 0) {
              Text('单词：' + card.word + (card.expected.length > 0 ? ' · 音素 ' + card.expected : '') +
                (card.actual.length > 0 ? ' → 实际读成 ' + card.actual : ''))
                .fontSize(EcFont.micro)
                .fontColor($r('app.color.ec_ink'))
                .width('100%')
            }
            if (card.why.length > 0) {
              Text('为什么：' + card.why)
                .fontSize(EcFont.micro)
                .fontColor($r('app.color.ec_muted'))
                .width('100%')
            }
            if (card.how.length > 0) {
              Text('怎么改：' + card.how)
                .fontSize(EcFont.micro)
                .fontColor($r('app.color.ec_muted'))
                .width('100%')
            }
            if (card.words.length > 0) {
              Text('练习词：' + card.words)
                .fontSize(EcFont.micro)
                .fontColor($r('app.color.ec_primary'))
                .width('100%')
            }
          }
          .width('100%')
          .padding(EcSpace.x3)
          .backgroundColor($r('app.color.ec_bad_bg'))
          .borderRadius(EcRadius.md)
          .alignItems(HorizontalAlign.Start)
        }, (card: ResultIssue, index: number) => 'iss' + index.toString())
      }

      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: '🔁 回放这次录音',
          kind: EcButtonKind.GHOST,
          btnWidth: '48%',
          onTap: () => {
            // 历史 attempt 没有本地录音文件：直接播服务端这条 attempt 的音频
            if (this.vm.wordDetails.length === 0 && this.vm.attemptIdText.length > 0) {
              this.playHistory(this.vm.attemptIdText);
            } else {
              void this.vm.playRecording();
            }
          }
        })
        EcButton({
          label: '再读一遍',
          kind: EcButtonKind.TONAL,
          btnWidth: '48%',
          onTap: () => {
            PracticeResultStore.requestRecord = true;
            NavigationService.pop();
          }
        })
      }
      .width('100%')
      .padding({ top: EcSpace.x3, bottom: EcSpace.x6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.mode === 'history' ? '📈 历史朗读' : '详细结果')
          .fontSize(EcFont.h3)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        if (this.mode === 'history') {
          this.historyBody()
        } else {
          this.resultBody()
        }
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x3 })
    .backgroundColor($r('app.color.ec_bg'))
  }
}

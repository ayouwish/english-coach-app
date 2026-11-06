import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { EmptyState } from '../components/EmptyState';
import { LoadingBlock } from '../components/LoadingBlock';
import { Chip } from '../components/EcBlocks';
import { F0Bars, ScoreRing, SubScoreBar } from '../components/ScoreViews';
import { PitchChart, RadarChart, SparkLine } from '../components/Charts';
import { WordText } from '../components/WordText';
import { EcFont, EcRadius, EcShadow, EcScore, EcSpace } from '../design/DesignTokens';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SentenceDto, WordScoreDto } from '../core/net/Dtos';
import { PracticeService } from '../core/service/PracticeService';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { AppConfig } from '../core/config/AppConfig';
import { PracticeResultStore } from '../core/session/PracticeResultStore';
import { SessionState } from '../core/session/SessionStore';
import { BlindRuntime } from '../core/session/BlindRuntime';
import { StatsService } from '../core/service/StatsService';
import { PracticeFocus } from '../core/session/PracticeFocus';
import { PracticeVM, ResultIssue } from '../viewmodel/PracticeVM';

/**
 * 跟读练习（Tab 1）：整页是**纵向卡片流**，上下滑动切换句子。
 *
 * 与 Web 的差异（用户 2026-11-03 要求）：练习改成卡片、滑动更自然；
 * 录音/结果都留在当前卡片里，不需要来回跳页。
 */
@Component
export struct PracticePage {
  @StorageLink('session') session: SessionState = new SessionState();
  @StorageLink('practice_focus') focusToken: string = '';
  @StorageLink('practice_focus_ver') @Watch('onFocusVerChanged') focusVer: number = 0;
  @State vm: PracticeVM = new PracticeVM();
  @State loading: boolean = true;
  @State loadError: string = '';
  @State level: string = 'A1';
  @State total: number = 0;
  /** 详细结果底部弹层（卡片本身不滚动，保证上下滑动切句手势） */
  @State detailShown: boolean = false;
  /** 全屏详情的内容：result = 本次详细结果；history = 这一句的历史朗读 */
  @State detailMode: string = 'result';
  /** 练习游标：上次读到第几句（0-based；-1 = 无） */
  @State resumeIndex: number = -1;
  private levels: string[] = ['A1', 'A2', 'B1', 'B2'];
  private swiper: SwiperController = new SwiperController();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    if (BlindRuntime.active) {
      void this.loadBlind();
    } else if (this.focusToken.length > 0) {
      void this.loadFocus();
    } else {
      void this.load(this.initialLevel());
    }
  }

  /** 诊断页「专项练习」：按焦点音素拉语料。 */
  private async loadFocus(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    const token = this.focusToken;
    try {
      const list = await PracticeService.sentences(this.initialLevel(), token);
      this.total = list.length;
      this.vm.setup(list, 0, this.initialLevel(), this.session.isChild);
      if (list.length > 0) {
        this.swiper.changeIndex(0);
      }
      if (list.length === 0) {
        this.loadError = '这个音素暂时没有专项句子，换一个音素或回普通练习吧';
      }
    } catch (err) {
      this.loadError = this.session.isChild ? '专项句子没取到，再试一次吧' : '专项练习语料加载失败，请重试';
      this.total = 0;
    } finally {
      this.loading = false;
    }
  }

  onFocusVerChanged(): void {
    if (BlindRuntime.active) {
      return;
    }
    if (this.focusToken.length > 0) {
      void this.loadFocus();
    } else {
      void this.load(this.initialLevel());
    }
  }

  /** 盲测模式：只加载这一批句子，界面不显示任何分数。 */
  private async loadBlind(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      const list = await BlindRuntime.loadSentences();
      this.total = list.length;
      this.vm.setupBlind(list);
      if (list.length > 0) {
        this.swiper.changeIndex(0);
      }
    } catch (err) {
      this.loadError = '盲测句子加载失败，请返回盲测页重试';
      this.total = 0;
    } finally {
      this.loading = false;
    }
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  /** 盲测提交：提交完自动滑到下一句（由页面驱动 Swiper，VM 不直接改渲染索引）。 */
  private async submitBlind(): Promise<void> {
    await this.vm.stopRecordingAndSubmit();
    if (this.vm.blindActive && !this.vm.blindDone && this.vm.index + 1 < this.total) {
      this.swiper.showNext();
    }
  }

  private initialLevel(): string {
    return AppConfig.levelForCefr(this.session.cefrLevel);
  }

  private async load(level: string): Promise<void> {
    this.loading = true;
    this.loadError = '';
    this.level = level;
    try {
      const list = await PracticeService.sentences(level);
      this.total = list.length;
      this.vm.setup(list, 0, level, this.session.isChild);
      this.resumeIndex = -1;
      if (list.length > 0) {
        // 练习游标（服务端 /practice/cursor 未部署，这里用本地偏好记「上次读到哪句」）
        const saved = await AppConfig.getString('practice_cursor_' + level, '');
        if (saved.length > 0) {
          for (let i = 0; i < list.length; i++) {
            if (list[i].id === saved) {
              // 与 Web 一致：先显示「上次练到第 N 句」横幅，由用户选继续/从头
              if (i > 0) {
                this.resumeIndex = i;
              }
              break;
            }
          }
        }
        // 只在确实需要重置时 changeIndex，避免初次加载触发 onChange 把游标覆盖成第 1 句
        if (this.vm.index !== 0) {
          this.swiper.changeIndex(0);
        }
        this.vm.setIndex(0);
      }
    } catch (err) {
      this.loadError = this.session.isChild ? '没取到句子，再试一次吧' : '取句子失败，请检查网络后重试';
      this.total = 0;
    } finally {
      this.loading = false;
    }
  }

  /** 退出盲测：先尝试服务端取消，失败也回普通跟读并提示。 */
  private async exitBlind(): Promise<void> {
    let cancelled = false;
    const testId = BlindRuntime.testId;
    if (testId.length > 0) {
      try {
        await StatsService.cancelBlindTest(testId);
        cancelled = true;
      } catch (err) {
        cancelled = false;
      }
    }
    BlindRuntime.clear();
    this.vm.clearBlind();
    await this.load(this.initialLevel());
    this.getUIContext().getPromptAction().showToast({
      message: cancelled ? '已取消这轮盲测' : '已退出盲测模式（服务端取消接口未发布，批次仍保留）'
    });
  }
  private async openHistory(): Promise<void> {
    PracticeResultStore.open(this.vm, 'history');
  }

  private usageText(): string {
    const minutes = Math.round(this.session.minutesToday * 10) / 10;
    if (minutes <= 0) {
      return '今天还没有开始练';
    }
    return '今天已练 ' + minutes.toString() + ' / ' + this.session.dailyLimitMinutes.toString() + ' 分钟';
  }

  private levelFg(level: string): ResourceColor {
    return this.level === level ? Color.White : $r('app.color.ec_muted');
  }

  private levelBg(level: string): ResourceColor {
    return this.level === level ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt');
  }

  // ------------------------------------------------------------------ 页头

  /** 练习游标横幅：上次练到第 N 句 → 继续上次 / 从头开始（与 Web 一致）。 */
  @Builder
  resumeBanner() {
    Row({ space: EcSpace.x2 }) {
      Text('上次练到第 ' + (this.resumeIndex + 1).toString() + ' 句（共 ' + this.total.toString() + ' 句）')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_ink'))
        .layoutWeight(1)
      Text('▶ 继续上次')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_primary'))
        .padding({ left: EcSpace.x1, right: EcSpace.x1, top: EcSpace.x1, bottom: EcSpace.x1 })
        .accessibilityText('继续上次练习')
        .onClick(() => {
          this.swiper.changeIndex(this.resumeIndex);
          this.vm.setIndex(this.resumeIndex);
          this.resumeIndex = -1;
        })
      Text('从头开始')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .padding({ left: EcSpace.x1, right: EcSpace.x1, top: EcSpace.x1, bottom: EcSpace.x1 })
        .onClick(() => {
          void AppConfig.putString('practice_cursor_' + this.level, '');
          this.resumeIndex = -1;
        })
    }
    .width('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x2, bottom: EcSpace.x2 })
    .backgroundColor($r('app.color.ec_primary_soft'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  blindBanner() {
    Column({ space: EcSpace.x1 }) {
      Row({ space: EcSpace.x2 }) {
        Text('🎯 盲测进行中')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
        Blank()
        Text('已读 ' + this.vm.blindSubmitted.toString() + ' / ' + this.vm.blindTotal.toString() + ' 句')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('这一轮不显示任何分数和反馈；读完这批句子再去盲测页看周报。已评完 ' +
        this.vm.blindScored.toString() + ' 句 · 待评分 ' + this.vm.blindPending.toString() + ' 句')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      if (this.vm.blindNotice.length > 0) {
        Text(this.vm.blindNotice)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
      }
      if (this.vm.blindDone) {
        EcButton({
          label: '结束盲测 · 去看周报',
          kind: EcButtonKind.PRIMARY,
          onTap: () => {
            NavigationService.push(Routes.BLIND_TEST);
          }
        })
        .margin({ top: EcSpace.x1 })
      }
      EcButton({
        label: '退出盲测，回普通跟读',
        kind: EcButtonKind.GHOST,
        onTap: () => {
          void this.exitBlind();
        }
      })
      .margin({ top: EcSpace.x1 })
    }
    .width('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x2 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  header() {
    Column({ space: EcSpace.x2 }) {
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

        if (!this.vm.blindActive) {
          Text('📈 历史')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .accessibilityText('查看这一句的历史朗读')
            .onClick(() => {
              void this.openHistory();
            })
        }
        Text(this.total > 0 ? ((this.vm.index + 1).toString() + ' / ' + this.total.toString()) : '')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.vm.blindActive && this.focusToken.length > 0) {
        Row({ space: EcSpace.x2 }) {
          Chip({ text: this.session.isChild ? '专项练习' : ('专项练习 · ' + this.focusToken), tone: 'primary' })
          Text('练这个音素的句子')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
          Blank()
          Text('退出专项')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .accessibilityText('退出专项练习')
            .onClick(() => {
              PracticeFocus.clear();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      if (!this.vm.blindActive) {
        Row({ space: EcSpace.x2 }) {
          ForEach(this.levels, (item: string) => {
            Text(item)
              .fontSize(this.session.isChild ? EcFont.body : EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.levelFg(item))
              .backgroundColor(this.levelBg(item))
              .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x2, bottom: EcSpace.x2 })
              .borderRadius(EcRadius.pill)
              .accessibilityText('等级 ' + item)
              .onClick(() => {
                if (this.level !== item) {
                  void this.load(item);
                }
              })
          }, (item: string) => item + '-' + this.level)
          Blank()
          Text('↻ 换一批')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x2, bottom: EcSpace.x2 })
            .accessibilityText('重新加载语料')
            .onClick(() => {
              void this.load(this.level);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4, bottom: EcSpace.x3 })
  }

  // ------------------------------------------------------------------ 卡片内容

  @Builder
  sentenceHead(item: SentenceDto) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Chip({ text: item.level, tone: 'primary' })
        if (!this.session.isChild && item.focus_phonemes !== undefined) {
          ForEach(item.focus_phonemes, (phoneme: string) => {
            Chip({ text: phoneme, tone: 'muted' })
          }, (phoneme: string) => item.id + phoneme)
        }
        Blank()
        if (this.vm.hasResult) {
          Chip({ text: '已评分', tone: 'good' })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      WordText({
        text: item.text,
        fontSizeVp: this.session.isChild ? 26 : EcFont.sentence,
        lineHeightVp: this.session.isChild ? 38 : 34
      })
      if (item.translation_zh !== undefined && item.translation_zh.length > 0) {
        Text(item.translation_zh)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  actionRow() {
    if (this.vm.recording) {
      // 录音中：说完啦（提交）+ 不要了（放弃这条录音，不提交）
      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: '⏹ 说完啦 ' + Math.floor(this.vm.elapsedMs / 1000).toString() + 's',
          kind: EcButtonKind.DANGER,
          big: this.session.isChild,
          btnWidth: '62%',
          disabled: this.vm.submitting,
          onTap: () => {
            if (this.vm.blindActive) {
              void this.submitBlind();
            } else {
              void this.vm.stopRecordingAndSubmit();
            }
          }
        })
        EcButton({
          label: '✖️ 不要了',
          kind: EcButtonKind.GHOST,
          btnWidth: '34%',
          disabled: this.vm.submitting,
          onTap: () => {
            void this.vm.cancelRecording();
          }
        })
      }
      .width('100%')
    } else if (this.vm.blindActive) {
      // 盲测不提供示范音（听了示范再读就测不出真实水平）
      Row() {
        EcButton({
          label: this.vm.preparing ? '准备…' : '🎤 开始说',
          kind: EcButtonKind.PRIMARY,
          big: true,
          btnWidth: '100%',
          disabled: this.vm.submitting || this.vm.blindDone,
          onTap: () => {
            void this.vm.startRecording();
          }
        })
      }
      .width('100%')
    } else {
      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: this.vm.ttsLoading ? '准备中…' : (this.vm.playing ? '播放中…' : '🔊 听示范'),
          kind: EcButtonKind.TONAL,
          btnWidth: '32%',
          loading: this.vm.ttsLoading,
          disabled: this.vm.recording || this.vm.submitting,
          onTap: () => {
            void this.vm.playDemo(false);
          }
        })
        EcButton({
          label: '🎧 跟我读',
          kind: EcButtonKind.TONAL,
          btnWidth: '30%',
          disabled: this.vm.recording || this.vm.submitting,
          onTap: () => {
            void this.vm.playDemo(true);
          }
        })
        EcButton({
          label: this.vm.preparing ? '准备…' : '🎤 开始说',
          kind: EcButtonKind.PRIMARY,
          btnWidth: '34%',
          disabled: this.vm.submitting,
          onTap: () => {
            void this.vm.startRecording();
          }
        })
      }
      .width('100%')
    }
  }

  @Builder
  statusLine() {
    if (this.vm.submitting) {
      Row({ space: EcSpace.x2 }) {
        LoadingProgress().width(16).height(16).color($r('app.color.ec_primary'))
        Text(this.vm.progressText.length > 0 ? this.vm.progressText : '提交中…')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
      }
      .width('100%')
    }
    if (this.vm.recording) {
      Text('正在听你说…读完点「说完啦」')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_warn_text'))
        .width('100%')
    }
  }

  @Builder
  errorBlock() {
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

  // ------------------------------------------------------------------ 结果区

  @Builder
  scoreBlock() {
    Row({ space: EcSpace.x4 }) {
      ScoreRing({
        score: this.vm.scorePron < 0 ? 0 : this.vm.scorePron,
        label: EcScore.showNumber(this.vm.scorePron, this.session.isChild) ? '总分' : '继续加油',
        isChild: this.session.isChild,
        ringSize: 104
      })
      Column({ space: EcSpace.x1 }) {
        SubScoreBar({ label: '准确', score: this.vm.scoreAccuracy, isChild: this.session.isChild })
        SubScoreBar({ label: '流利', score: this.vm.scoreFluency, isChild: this.session.isChild })
        SubScoreBar({ label: '完整', score: this.vm.scoreCompleteness, isChild: this.session.isChild })
        SubScoreBar({ label: '语调', score: this.vm.scoreProsody, isChild: this.session.isChild })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  feedbackBlock() {
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
    if (this.vm.feedbackClosing.length > 0) {
      Text(this.vm.feedbackClosing)
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
  }

  /** 纠错要点放详细弹层里，避免卡片过高挡手势。 */
  @Builder
  pointsBlock() {
    if (this.vm.pointTitles.length > 0) {
      Column({ space: EcSpace.x1 }) {
        Text('怎么练更好')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        ForEach(this.vm.pointTitles, (title: string, index: number) => {
          Column({ space: 2 }) {
            Text('· ' + title)
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ec_ink'))
              .width('100%')
            if (index < this.vm.pointHows.length && this.vm.pointHows[index].length > 0) {
              Text('  ' + this.vm.pointHows[index])
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_muted'))
                .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (title: string, index: number) => title + index.toString())
      }
      .width('100%')
    }
  }

  @Builder
  wordsBlock() {
    if (this.vm.wordTexts.length > 0 && !this.session.isChild) {
      Column({ space: EcSpace.x1 }) {
        Text('逐词评分')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.vm.wordTexts, (word: string, index: number) => {
            Text(word + ' ' + (this.vm.wordScores[index] < 0 ? '—' : Math.round(this.vm.wordScores[index]).toString()))
              .fontSize(EcFont.caption)
              .fontColor(EcScore.colorByMode(this.vm.wordScores[index] < 0 ? null : this.vm.wordScores[index],
                this.session.isChild))
              .backgroundColor($r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 3, bottom: 3 })
              .borderRadius(EcRadius.sm)
              .margin(3)
          }, (word: string, index: number) => word + index.toString())
        }
        .width('100%')
      }
      .width('100%')
    }
    if (this.vm.issueTexts.length > 0) {
      Column({ space: EcSpace.x1 }) {
        Text('这次的问题')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        ForEach(this.vm.issueTexts, (text: string, index: number) => {
          Text('· ' + text)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
        }, (text: string, index: number) => text + index.toString())
      }
      .width('100%')
    }
  }

  @Builder
  intonationBlock() {
    if (this.vm.intonationAvailable) {
      Column({ space: EcSpace.x1 }) {
        Row({ space: EcSpace.x2 }) {
          Text('语调曲线')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
          if (this.vm.intonationDistance.length > 0) {
            Text('差距 ' + this.vm.intonationDistance)
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
        }
        .width('100%')
        F0Bars({ user: this.vm.userF0, reference: this.vm.refF0 })
        ForEach(this.vm.regionTexts, (text: string, index: number) => {
          Text('· ' + text)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_warn_text'))
            .width('100%')
        }, (text: string, index: number) => text + index.toString())
      }
      .width('100%')
    }
  }

  @Builder
  historyBlock() {
    if (this.vm.historyScores.length > 0) {
      Column({ space: EcSpace.x1 }) {
        Text('这一句的进步（最近 ' + this.vm.historyScores.length.toString() + ' 次）')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        Row({ space: 6 }) {
          ForEach(this.vm.historyScores, (score: number, index: number) => {
            Column() {
              Text(Math.round(score).toString())
                .fontSize(EcFont.micro)
                .fontColor($r('app.color.ec_muted'))
              Column()
                .width(14)
                .height(Math.round(score * 0.5) + 6)
                .backgroundColor(EcScore.color(score))
                .borderRadius(4)
            }
            .alignItems(HorizontalAlign.Center)
          }, (score: number, index: number) => 'h' + index.toString())
        }
        .width('100%')
        .height(76)
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
    }
  }

  @Builder
  resultBlock() {
    if (this.vm.hasResult) {
      Column({ space: EcSpace.x3 }) {
        if (this.vm.noSpeech) {
          Column({ space: EcSpace.x1 }) {
            Text('没有听到你说话')
              .fontSize(EcFont.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ec_ink'))
              .width('100%')
            Text('可能是麦克风没收到声音，靠近一点再读一遍吧')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
          }
          .width('100%')
        } else {
          this.scoreBlock()
        }
        if (this.vm.recognizedText.length > 0 && !this.session.isChild) {
          Text('我听到的是：' + this.vm.recognizedText)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        this.feedbackBlock()
        Row({ space: EcSpace.x2 }) {
          EcButton({
            label: '详细结果',
            kind: EcButtonKind.GHOST,
            btnWidth: '32%',
            onTap: () => {
              hilog.info(0xEC00, 'PracticeDetail', 'open detail hasResult=%{public}s words=%{public}d idx=%{public}d',
                this.vm.hasResult ? 'true' : 'false', this.vm.wordDetails.length, this.vm.index);
              PracticeResultStore.open(this.vm, 'result');
            }
          })
          EcButton({
            label: this.vm.playingRecording ? '播放中…' : '🔁 回放',
            kind: EcButtonKind.TONAL,
            btnWidth: '32%',
            disabled: this.vm.recording,
            onTap: () => {
              void this.vm.playRecording();
            }
          })
          EcButton({
            label: '下一句 →',
            kind: EcButtonKind.PRIMARY,
            btnWidth: '32%',
            onTap: () => {
              this.swiper.showNext();
            }
          })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 详细结果弹层：逐词/音素问题/语调曲线/进步历史/重试评测。 */
  @Builder
  detailSheet() {
    Column({ space: EcSpace.x3 }) {
      Row({ space: EcSpace.x2 }) {
        Text('详细结果')
          .fontSize(EcFont.h3)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Text('关闭')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText('关闭详细结果')
          .onClick(() => {
            this.detailShown = false;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: EcSpace.x3 }) {
          this.pointsBlock()
          this.wordsBlock()
          this.intonationBlock()
          this.historyBlock()
          if (this.vm.canRetryEvaluate) {
            EcButton({
              label: '重试评测',
              kind: EcButtonKind.TONAL,
              loading: this.vm.submitting,
              onTap: () => {
                void this.vm.retryEvaluate();
              }
            })
          }
          if (this.vm.wordTexts.length === 0 && this.vm.issueTexts.length === 0 &&
            !this.vm.intonationAvailable && this.vm.historyScores.length === 0 && this.vm.pointTitles.length === 0) {
            Text(this.session.isChild ? '这次读得很好，没有需要特别练的地方 🌟' : '这次没有更细的问题，整体表现不错。')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
          }
        }
        .width('100%')
        .padding({ bottom: EcSpace.x6 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4, bottom: EcSpace.x2 })
    .backgroundColor($r('app.color.ec_bg'))
  }

  // ------------------------------------------------------------------ 全屏详细结果

  @Builder
  detailSectionTitle(text: string) {
    Row({ space: EcSpace.x2 }) {
      Text(text)
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
    }
    .width('100%')
    .padding({ top: EcSpace.x2 })
  }

  @Builder
  detailCard() {
    Column({ space: EcSpace.x3 }) {
      // ---- 1. 这一句的问题
      if (this.vm.issueChipLabels.length > 0) {
        this.detailSectionTitle('这一句的问题')
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
        if (this.vm.issueChipLabels.length > 0) {
          Text('这一句最需要练的是 /' + this.vm.issueChipLabels[0] + '/，先慢一点读。')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
      }

      // ---- 2. 这一句的历史
      if (this.vm.historyScores.length > 0) {
        this.detailSectionTitle('这一句的历史（' + this.vm.historyScores.length.toString() + ' 次）')
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
              Text(this.vm.playingHistoryId ===
                this.vm.historyAttemptIds[this.vm.historyAttemptIds.length - 1 - index] ? '播放中…' : '▶ 回放')
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_primary'))
                .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 3, bottom: 3 })
                .onClick(() => {
                  void this.vm.playHistoryAudio(
                    this.vm.historyAttemptIds[this.vm.historyAttemptIds.length - 1 - index]);
                })
            }
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }, (label: string, index: number) => 'hl' + index.toString())
      }

      // ---- 3. 本次评分
      this.detailSectionTitle('本次评分')
      Row({ space: EcSpace.x4 }) {
        ScoreRing({
          score: this.vm.scorePron < 0 ? 0 : this.vm.scorePron,
          label: '综合分',
          isChild: this.session.isChild,
          ringSize: 116
        })
        Column({ space: EcSpace.x1 }) {
          SubScoreBar({ label: '准确', score: this.vm.scoreAccuracy, isChild: this.session.isChild })
          SubScoreBar({ label: '流利', score: this.vm.scoreFluency, isChild: this.session.isChild })
          SubScoreBar({ label: '完整', score: this.vm.scoreCompleteness, isChild: this.session.isChild })
          SubScoreBar({ label: '节奏', score: this.vm.scoreProsody, isChild: this.session.isChild })
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
      if (this.vm.refText.length > 0 && this.vm.refText !== this.vm.recognizedText) {
        Text('参考文本：' + this.vm.refText)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
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
        this.detailSectionTitle('整体点评')
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
                .fontWeight(FontWeight.Medium)
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
        this.detailSectionTitle('能力多边形')
        RadarChart({
          accuracy: this.vm.scoreAccuracy,
          fluency: this.vm.scoreFluency,
          completeness: this.vm.scoreCompleteness,
          prosody: this.vm.scoreProsody,
          isChild: this.session.isChild,
          chartSize: 280
        })
        Text('最需要练的是 ' + this.weakestAxisText())
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
      }

      // ---- 6. 逐词得分 + 音素明细
      if (this.vm.wordDetails.length > 0 && !this.session.isChild) {
        this.detailSectionTitle('逐词得分')
        if (this.vm.worstWordTexts.length > 0) {
          Text('需要练的词（低于 60 分，按分数从低到高）')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_warn_text'))
            .width('100%')
          ForEach(this.vm.worstWordTexts, (word: string, index: number) => {
            this.wordBar(word, this.vm.worstWordScores[index])
          }, (word: string, index: number) => 'w' + index.toString())
        }
        Text('逐词得分（句子顺序，越长越好）')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        ForEach(this.vm.wordDetails, (word: WordScoreDto, index: number) => {
          this.wordBar(word.word, (word.score === undefined || word.score === null) ? -1 : (word.score as number))
        }, (word: WordScoreDto, index: number) => 'wd' + index.toString())
        if (this.vm.phonemeChipLabels.length > 0) {
          Text('音素明细')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.vm.phonemeChipLabels, (label: string, index: number) => {
              Text(label + ' ' + (this.vm.phonemeChipScores[index] < 0 ? '—' :
                Math.round(this.vm.phonemeChipScores[index]).toString()))
                .fontSize(EcFont.micro)
                .fontColor(EcScore.colorByMode(this.vm.phonemeChipScores[index] < 0 ? null : this.vm.phonemeChipScores[index],
                  this.session.isChild))
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
        this.detailSectionTitle('语调对比（F0 双曲线）')
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
        this.detailSectionTitle('需要纠正的地方')
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
                  .fontWeight(FontWeight.Medium)
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
          label: this.vm.playingRecording ? '播放中…' : '🔁 回放录音',
          kind: EcButtonKind.GHOST,
          btnWidth: '48%',
          disabled: this.vm.recording,
          onTap: () => {
            void this.vm.playRecording();
          }
        })
        if (this.vm.canRetryEvaluate) {
          EcButton({
            label: '重试评测',
            kind: EcButtonKind.TONAL,
            btnWidth: '48%',
            loading: this.vm.submitting,
            onTap: () => {
              void this.vm.retryEvaluate();
            }
          })
        } else {
          EcButton({
            label: '再读一遍',
            kind: EcButtonKind.TONAL,
            btnWidth: '48%',
            onTap: () => {
              this.detailShown = false;
              void this.vm.startRecording();
            }
          })
        }
      }
      .width('100%')
      .padding({ top: EcSpace.x3, bottom: EcSpace.x6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private weakestAxisText(): string {
    let bestLabel = '';
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
  wordBar(word: string, score: number) {
    Row({ space: 6 }) {
      Text(word)
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_ink'))
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

  /** 这一句的历史朗读（不依赖本次是否评分）：折线 + 首末对比 + 逐条回放。 */
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
              Text(this.vm.playingHistoryId ===
                this.vm.historyAttemptIds[this.vm.historyAttemptIds.length - 1 - index] ? '播放中…' : '▶ 回放')
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_primary'))
                .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 3, bottom: 3 })
                .onClick(() => {
                  void this.vm.playHistoryAudio(
                    this.vm.historyAttemptIds[this.vm.historyAttemptIds.length - 1 - index]);
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
  resultDetail() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.detailMode === 'history' ? '📈 历史朗读' : '详细结果')
          .fontSize(EcFont.h3)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Text('关闭')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText('关闭详细结果')
          .onClick(() => {
            this.detailShown = false;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        if (this.detailMode === 'history') {
          this.historyBody()
        } else {
          this.detailCard()
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

  @Builder
  card(item: SentenceDto) {
    Column({ space: EcSpace.x3 }) {
      this.sentenceHead(item)
      this.actionRow()
      this.statusLine()
      this.errorBlock()
      this.resultBlock()
    }
    .width('100%')
    .height('100%')
    .padding(EcSpace.x5)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.xl)
    .shadow(EcShadow.card())
  }

  // ------------------------------------------------------------------ 页面

  build() {
    Column({ space: EcSpace.x3 }) {
      this.header()
      if (this.vm.blindActive) {
        this.blindBanner()
      }

      if (this.loading) {
        LoadingBlock({ text: '正在取句子…' })
      } else if (this.loadError.length > 0) {
        Column({ space: EcSpace.x3 }) {
          ErrorBanner({
            message: this.loadError,
            actionLabel: '重试',
            onAction: () => {
              void this.load(this.level);
            }
          })
        }
        .width('100%')
        .padding(EcSpace.x4)
      } else if (this.total === 0) {
        EmptyState({
          icon: '📚',
          message: this.session.isChild ? '这个等级还没有句子，换一个等级看看吧' : '这个等级还没有句子，换一个等级试试',
          actionLabel: '换个等级',
          onAction: () => {
            void this.load(this.level === 'A1' ? 'A2' : 'A1');
          }
        })
      } else {
        if (this.resumeIndex > 0) {
          this.resumeBanner()
        }
        Swiper(this.swiper) {
          ForEach(this.vm.sentences, (item: SentenceDto) => {
            this.card(item)
          }, (item: SentenceDto) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .vertical(true)
        .loop(false)
        .indicator(false)
        .duration(240)
        .curve(Curve.EaseOut)
        .onChange((index: number) => {
          this.vm.setIndex(index);
          // 用户主动滑动后，横幅不再需要（按当前位置继续，并写入游标）
          if (this.resumeIndex > 0) {
            this.resumeIndex = -1;
          }
          // 记录练习游标（普通练习才记；盲测/专项不污染）
          if (!this.vm.blindActive && this.focusToken.length === 0) {
            const item = this.vm.current();
            if (item !== null) {
              void AppConfig.putString('practice_cursor_' + this.level, item.id);
            }
          }
        })
        .margin({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x4 })
      }

      Row({ space: EcSpace.x2 }) {
        Text('上滑 / 下滑切换句子')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
        Blank()
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x3 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, ratio: number) => {
      if (!isVisible || ratio <= 0) {
        return;
      }
      // 从别的 Tab 回来时同步盲测状态（开始/结束可能发生在别的页面）
      if (BlindRuntime.active && !this.vm.blindActive) {
        void this.loadBlind();
      } else if (!BlindRuntime.active && this.vm.blindActive) {
        this.vm.clearBlind();
        void this.load(this.initialLevel());
      }
      // 从结果详情页点「再读一遍」回来：自动开始录音
      if (PracticeResultStore.consumeRecordRequest()) {
        void this.vm.startRecording();
      }
    })
  }
}

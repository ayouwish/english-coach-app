import { EcButton, EcButtonKind } from '../components/EcButton';
import { Chip, TopBar } from '../components/EcBlocks';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcScore, EcSpace } from '../design/DesignTokens';
import { ChatSessionDto } from '../core/net/ChatDtos';
import { ChatNav } from '../core/net/ChatDtos';
import { NavState } from '../core/router/NavState';
import { NavigationService } from '../core/router/NavigationService';
import { SessionState } from '../core/session/SessionStore';
import { ChatFormat, ChatMsg, ChatVM } from '../viewmodel/ChatVM';

// ---------------------------------------------------------------------------
// 共享气泡（会话页 + 历史详情页共用）
// ---------------------------------------------------------------------------

/** 一条消息气泡：用户右侧（主题色）/ 助手左侧（白底）。儿童不显示分数与 IPA。 */
@Component
export struct ChatBubbleView {
  @Prop isUser: boolean = false;
  @Prop bodyText: string = '';
  @Prop bodyTextZh: string = '';
  @Prop hasCorrection: boolean = false;
  @Prop betterText: string = '';
  @Prop explainText: string = '';
  @Prop unsafeFlag: boolean = false;
  @Prop childMode: boolean = false;
  /** '' | loading | playing | failed */
  @Prop playState: string = '';
  @Prop hasAudio: boolean = true;
  @Prop pronLine: string = '';
  @Prop wordTexts: string[] = [];
  @Prop wordScores: number[] = [];
  @Prop wordsExpanded: boolean = false;
  onPlayTap: () => void = () => {
  };
  onWordsTap: () => void = () => {
  };

  private bubbleBg(): ResourceColor {
    return this.isUser ? $r('app.color.ec_primary_soft') : $r('app.color.ec_surface');
  }

  private playLabel(): string {
    if (this.playState === 'loading') {
      return this.isUser ? '⏳ 正在取录音…' : '⏳ 语音生成中…（通常几秒）';
    }
    if (this.playState === 'playing') {
      return this.isUser ? '⏸ 正在回放…' : '🔊 正在说话…（点一下停）';
    }
    if (this.playState === 'failed') {
      return this.isUser ? '▶ 录音没取到，点这里重试' : '⚠️ 语音没出来，点这里重试';
    }
    return this.isUser ? '🔁 回放我刚才说的话' : '🔊 再听一遍';
  }

  private toggleWordsLabel(): string {
    if (this.wordsExpanded) {
      return '收起逐词';
    }
    return '看逐词(' + this.wordTexts.length.toString() + ' 个词)';
  }

  private wordColor(score: number): ResourceColor {
    if (score < 0) {
      return $r('app.color.ec_muted');
    }
    return EcScore.color(score);
  }

  build() {
    Column({ space: EcSpace.x1 }) {
      Column({ space: EcSpace.x2 }) {
        Text(this.bodyText)
          .fontSize(this.childMode ? EcFont.childBody : EcFont.body)
          .fontColor($r('app.color.ec_ink'))
          .lineHeight(this.childMode ? 28 : 24)
          .width('100%')
        if (this.bodyTextZh.length > 0) {
          Text(this.bodyTextZh)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        if (this.hasCorrection) {
          Column({ space: 2 }) {
            Text('更自然：' + this.betterText)
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ec_warn_text'))
              .width('100%')
            if (this.explainText.length > 0) {
              Text(this.explainText)
                .fontSize(EcFont.micro)
                .fontColor($r('app.color.ec_warn_text'))
                .width('100%')
            }
          }
          .width('100%')
          .padding(EcSpace.x2)
          .backgroundColor($r('app.color.ec_warn_bg'))
          .borderRadius(EcRadius.sm)
          .alignItems(HorizontalAlign.Start)
        }
        if (this.unsafeFlag) {
          Text('（内容已按儿童安全规则替换）')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        if (this.hasAudio) {
          Text(this.playLabel())
            .fontSize(EcFont.caption)
            .fontColor(this.playState === 'failed' ? $r('app.color.ec_bad_text') : $r('app.color.ec_primary'))
            .padding({ top: 2, bottom: 2 })
            .accessibilityText(this.playLabel())
            .onClick(() => {
              this.onPlayTap();
            })
        }
        if (this.pronLine.length > 0) {
          Text(this.pronLine)
            .fontSize(EcFont.micro)
            .fontColor(this.isUser ? $r('app.color.ec_primary') : $r('app.color.ec_muted'))
            .width('100%')
        }
        if (this.wordTexts.length > 0) {
          Text(this.toggleWordsLabel())
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .accessibilityText(this.toggleWordsLabel())
            .onClick(() => {
              this.onWordsTap();
            })
          if (this.wordsExpanded) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.wordTexts, (word: string, index: number) => {
                Text(word + ' ' + (this.wordScores[index] < 0 ? '—' : Math.round(this.wordScores[index]).toString()))
                  .fontSize(EcFont.micro)
                  .fontColor(this.wordColor(this.wordScores[index]))
                  .backgroundColor($r('app.color.ec_surface_alt'))
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(EcRadius.sm)
                  .margin(2)
              }, (word: string, index: number) => word + index.toString())
            }
            .width('100%')
          }
        }
      }
      .width('100%')
      .padding(EcSpace.x3)
      .backgroundColor(this.bubbleBg())
      .borderRadius(EcRadius.lg)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ maxWidth: '88%' })
    .alignItems(this.isUser ? HorizontalAlign.End : HorizontalAlign.Start)
  }
}

// ---------------------------------------------------------------------------
// 共享整段回放组件（§2.8 / §6.1）
// ---------------------------------------------------------------------------

/** 整段回放：loading/building → ready（播放）→ failed（显示服务端 error + 重新生成）。 */
@Component
export struct ChatReplayCard {
  /** idle | loading | building | ready | failed */
  @Prop replayState: string = 'idle';
  @Prop errorText: string = '';
  @Prop childMode: boolean = false;
  @Prop playing: boolean = false;
  @Prop durationText: string = '';
  onPlayTap: () => void = () => {
  };
  onRegenerateTap: () => void = () => {
  };

  private titleText(): string {
    return this.childMode ? '🎧 听一听我们的对话' : '🎧 回放整段对话';
  }

  build() {
    Column({ space: EcSpace.x2 }) {
      if (this.replayState === 'loading' || this.replayState === 'building') {
        Row({ space: EcSpace.x2 }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.ec_primary'))
          Text('🎧 正在生成整段回放…（可以先看文字）')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .layoutWeight(1)
        }
        .width('100%')
        .padding(EcSpace.x3)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .alignItems(VerticalAlign.Center)
      } else if (this.replayState === 'ready') {
        Row({ space: EcSpace.x2 }) {
          Column({ space: 2 }) {
            Text(this.titleText())
              .fontSize(EcFont.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ec_ink'))
            Text(this.durationText.length > 0 ? ('总长约 ' + this.durationText) : '整段回放已经准备好啦')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          EcButton({
            label: this.playing ? '⏸ 暂停' : '▶ 播放',
            kind: EcButtonKind.TONAL,
            btnWidth: '96vp',
            onTap: () => {
              this.onPlayTap();
            }
          })
        }
        .width('100%')
        .padding(EcSpace.x3)
        .backgroundColor($r('app.color.ec_surface'))
        .borderRadius(EcRadius.md)
        .alignItems(VerticalAlign.Center)
      } else if (this.replayState === 'failed') {
        Column({ space: EcSpace.x2 }) {
          Text('🎧 整段回放还没好')
            .fontSize(EcFont.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
          Text(this.errorText)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_warn_text'))
            .width('100%')
          Row({ space: EcSpace.x2 }) {
            EcButton({
              label: '🔄 重新生成',
              kind: EcButtonKind.TONAL,
              btnWidth: '148vp',
              onTap: () => {
                this.onRegenerateTap();
              }
            })
            Text('可以先看文字记录')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding(EcSpace.x3)
        .backgroundColor($r('app.color.ec_warn_bg'))
        .borderRadius(EcRadius.md)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }
}

// ---------------------------------------------------------------------------
// 对话进行中
// ---------------------------------------------------------------------------

/**
 * 对话会话页（§2.5 / §6.1 / §7.3）。
 *
 * 一轮 = 三步：ASR → turn（text+audio）→ 自己请求 TTS 播放；文字先到、音频后到。
 * 页面**不直接**用 AVRecorder / AVPlayer，全部走 AudioController。
 */
@Component
export struct ChatSessionPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: ChatVM = new ChatVM();
  @State expandedMsgId: string = '';
  @State confirmEnd: boolean = false;
  private started: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.init();
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  private async init(): Promise<void> {
    const sessionId = NavState.session.sessionId;
    let sessionDto: ChatSessionDto | null = ChatNav.session;
    if (sessionDto !== null && sessionDto.session_id !== sessionId) {
      sessionDto = null;
    }
    if (sessionDto !== null) {
      // 优先用开会话响应里的 scenario（opening_line 是抽到的 variation）；缺失时才用列表项兜底
      const scenarioFallback = (sessionDto.scenario === undefined) ? NavState.chat.scenario : null;
      await this.vm.initLive(sessionDto, scenarioFallback, this.session.isChild);
      this.scrollToBottom();
      return;
    }
    if (sessionId.length > 0) {
      // 进程内没拿到开会话数据（热重载/异常）：退化成只读重看，避免空白页
      await this.vm.initHistory(sessionId, null, this.session.isChild);
      this.scrollToBottom();
      return;
    }
    this.vm.loading = false;
    this.vm.loadError = '会话信息不见了，返回重新选一个场景开始吧';
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 160);
  }

  private async onRecordTap(): Promise<void> {
    if (this.vm.recording) {
      await this.vm.stopAndSend();
      this.scrollToBottom();
    } else {
      await this.vm.startRecording();
    }
  }

  private async onEndTap(): Promise<void> {
    this.confirmEnd = false;
    await this.vm.endSession();
    this.scrollToBottom();
  }

  private onSuggestionTap(text: string): void {
    this.vm.useSuggestion(text);
  }

  /** 儿童：只给正向文案；成人：分数 + 最弱音；评分未完成不落 0。 */
  private pronLine(msg: ChatMsg): string {
    if (msg.role !== 'user') {
      return '';
    }
    if (this.vm.isChild) {
      return msg.hasPron ? '这次说得很清楚，继续说！🌟' : '这次的声音我听到啦';
    }
    if (!msg.hasPron) {
      return '发音 —（本轮评分未完成）';
    }
    let line = '发音 ' + ChatFormat.scoreText(msg.pronScore);
    if (msg.weakLabels.length > 0) {
      line = line + ' · 最弱 ' + msg.weakLabels.join('/');
    }
    return line;
  }

  private hasPlayableAudio(msg: ChatMsg): boolean {
    if (msg.role === 'assistant') {
      return true;
    }
    return msg.localAudioPath.length > 0 || msg.audioUrl.length > 0;
  }

  // ------------------------------------------------------------------ 气泡

  @Builder
  bubble(msg: ChatMsg) {
    ChatBubbleView({
      isUser: msg.role === 'user',
      bodyText: msg.text,
      bodyTextZh: msg.textZh,
      hasCorrection: msg.hasCorrection,
      betterText: msg.better,
      explainText: msg.explainZh,
      unsafeFlag: msg.unsafeFiltered,
      childMode: this.vm.isChild,
      playState: msg.playState,
      hasAudio: this.hasPlayableAudio(msg),
      pronLine: this.pronLine(msg),
      wordTexts: msg.wordTexts,
      wordScores: msg.wordScores,
      wordsExpanded: this.expandedMsgId === msg.id,
      onPlayTap: () => {
        void this.vm.playMessage(msg);
      },
      onWordsTap: () => {
        this.expandedMsgId = this.expandedMsgId === msg.id ? '' : msg.id;
      }
    })
  }

  @Builder
  replayBlock() {
    ChatReplayCard({
      replayState: this.vm.replayStatus,
      errorText: this.vm.replayError,
      childMode: this.vm.isChild,
      playing: this.vm.replayPlaying,
      durationText: ChatFormat.durationText(this.vm.replayDurationMs),
      onPlayTap: () => {
        void this.vm.playReplay();
      },
      onRegenerateTap: () => {
        void this.vm.regenerateReplay();
      }
    })
  }

  // ------------------------------------------------------------------ 头部 / 提示

  @Builder
  header() {
    Column({ space: 0 }) {
      TopBar({
        title: this.vm.titleZh.length > 0 ? this.vm.titleZh
          : (this.vm.titleEn.length > 0 ? this.vm.titleEn : '对话中'),
        actionLabel: (!this.vm.ended && !this.vm.readOnly) ? (this.vm.ending ? '结束中…' : '结束') : '',
        onBack: () => {
          NavigationService.pop();
        },
        onAction: () => {
          if (this.vm.ending) {
            return;
          }
          this.confirmEnd = true;
        }
      })
      if (this.vm.titleEn.length > 0) {
        Text(this.vm.titleEn)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x1 })
      }
    }
    .width('100%')
  }

  @Builder
  metaRow() {
    Row({ space: EcSpace.x2 }) {
      Chip({ text: '第 ' + (this.vm.turnCount + 1).toString() + ' 轮', tone: 'primary' })
      if (this.vm.level.length > 0) {
        Chip({ text: this.vm.level, tone: 'muted' })
      }
      Text('不限轮数，想聊多久都可以')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  amberBar(text: string) {
    Row({ space: EcSpace.x2 }) {
      Text('⚠️')
        .fontSize(16)
      Text(text)
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_warn_text'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding(EcSpace.x3)
    .backgroundColor($r('app.color.ec_warn_bg'))
    .borderRadius(EcRadius.md)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  doneCard() {
    Column({ space: EcSpace.x2 }) {
      Text('🌟')
        .fontSize(36)
      Text('这个场景练完啦，辛苦了！')
        .fontSize(EcFont.h3)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
      Text('换个场景继续，或者去「错音本」复习一下。')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(EcSpace.x5)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  suggestionChips() {
    if (this.vm.suggestedReplies.length > 0 && !this.vm.busy && !this.vm.recording && !this.vm.quotaExceeded) {
      Column({ space: EcSpace.x1 }) {
        Text('可以这样回：')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.vm.suggestedReplies, (item: string, index: number) => {
            Text(item)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_primary'))
              .backgroundColor($r('app.color.ec_primary_soft'))
              .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x1, bottom: EcSpace.x1 })
              .borderRadius(EcRadius.pill)
              .margin(3)
              .maxLines(2)
              .accessibilityText('照着说：' + item)
              .onClick(() => {
                this.onSuggestionTap(item);
              })
          }, (item: string, index: number) => item + index.toString())
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  hintCard() {
    if (this.vm.hintText.length > 0) {
      Column({ space: EcSpace.x1 }) {
        Text('照着这句说：')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        Text(this.vm.hintText)
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
        Text('提示句只给你参考，发出去的是你说的录音。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      .width('100%')
      .padding(EcSpace.x3)
      .backgroundColor($r('app.color.ec_primary_soft'))
      .borderRadius(EcRadius.md)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  endConfirm() {
    if (this.confirmEnd) {
      Column({ space: EcSpace.x2 }) {
        Text('结束这次对话？')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
        Text('结束后会生成整段回放，想聊多久都可以，随时可以结束。')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
        Row({ space: EcSpace.x2 }) {
          EcButton({
            label: '🏁 结束对话',
            kind: EcButtonKind.DANGER,
            btnWidth: '52%',
            onTap: () => {
              void this.onEndTap();
            }
          })
          EcButton({
            label: '再聊会儿',
            kind: EcButtonKind.TONAL,
            btnWidth: '44%',
            onTap: () => {
              this.confirmEnd = false;
            }
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding(EcSpace.x3)
      .backgroundColor($r('app.color.ec_surface'))
      .borderRadius(EcRadius.md)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  recordArea() {
    Column({ space: EcSpace.x2 }) {
      if (this.vm.busy) {
        Row({ space: EcSpace.x2 }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.ec_primary'))
          Text(this.vm.progressText.length > 0 ? this.vm.progressText : '识别 / 回复中…请稍候 ⏳')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      EcButton({
        label: this.vm.recording
          ? ('⏹ 说完啦 ' + Math.floor(this.vm.elapsedMs / 1000).toString() + 's')
          : (this.vm.preparing ? '正在打开麦克风…' : '🎤 开始录音'),
        kind: this.vm.recording ? EcButtonKind.DANGER : EcButtonKind.PRIMARY,
        big: true,
        loading: this.vm.preparing,
        disabled: this.vm.busy || this.vm.ending || this.vm.quotaExceeded,
        onTap: () => {
          void this.onRecordTap();
        }
      })
      if (this.vm.recording) {
        Row({ space: EcSpace.x2 }) {
          Text('正在听你说…说完点上面按钮')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_warn_text'))
            .layoutWeight(1)
          Text('✖️ 不要了')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_bad_text'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 2, bottom: 2 })
            .accessibilityText('取消这次录音')
            .onClick(() => {
              void this.vm.cancelRecording();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      Text('本页需要麦克风才能对话（没有输入框）')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
        .textAlign(TextAlign.Center)
      Row({ space: EcSpace.x2 }) {
        Text('🎤')
          .fontSize(14)
        Text('麦克风没反应？在「我的 → 设置」里检查权限，或点这里看排查步骤')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  // ------------------------------------------------------------------ 页面

  build() {
    Column({ space: EcSpace.x2 }) {
      this.header()

      if (this.vm.quotaExceeded) {
        Row({ space: EcSpace.x2 }) {
          Text('🌙')
            .fontSize(16)
          Text(this.vm.quotaText.length > 0 ? this.vm.quotaText : '今天的练习时间到啦，明天再来')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_warn_text'))
            .layoutWeight(1)
        }
        .width('100%')
        .padding(EcSpace.x3)
        .backgroundColor($r('app.color.ec_warn_bg'))
        .borderRadius(EcRadius.md)
        .alignItems(VerticalAlign.Center)
        .margin({ left: EcSpace.x4, right: EcSpace.x4 })
      }

      if (this.vm.degradedLlm) {
        Column() {
          this.amberBar('⚠️ 当前回复来自内置话术（还没接入大模型），先练着，不影响记录。')
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4 })
      }

      if (this.vm.degraded) {
        Column() {
          this.amberBar('对话服务暂时不可用，已切换到本地固定话术（数据仍然完整保存）。')
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4 })
      }

      Scroll(this.scroller) {
        Column({ space: EcSpace.x3 }) {
          this.metaRow()

          if (this.vm.loading) {
            LoadingBlock({ text: '正在打开对话…' })
          }
          if (this.vm.loadError.length > 0) {
            ErrorBanner({
              message: this.vm.loadError,
              actionLabel: '返回',
              onAction: () => {
                NavigationService.pop();
              }
            })
          }

          ForEach(this.vm.messages, (item: ChatMsg) => {
            this.bubble(item)
          }, (item: ChatMsg) => item.renderKey())

          if (this.vm.done) {
            this.doneCard()
          }

          if (this.vm.ended) {
            this.replayBlock()
            Text('这段对话已经结束啦，回放和文字记录都会保存下来。')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x1, bottom: EcSpace.x4 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      if (!this.vm.ended && !this.vm.readOnly) {
        Column({ space: EcSpace.x2 }) {
          this.suggestionChips()
          this.hintCard()
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
          this.endConfirm()
          this.recordArea()
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x3, bottom: EcSpace.x4 })
        .backgroundColor($r('app.color.ec_surface'))
        .borderRadius({ topLeft: EcRadius.xl, topRight: EcRadius.xl })
      } else if (this.vm.hasError) {
        Column() {
          ErrorBanner({
            title: this.vm.error.title,
            message: this.vm.error.message,
            actionLabel: this.vm.errorActionLabel,
            onAction: () => {
              void this.vm.onErrorAction();
            }
          })
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x4 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
  }
}

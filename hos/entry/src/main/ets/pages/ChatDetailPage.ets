import { Chip, TopBar } from '../components/EcBlocks';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { ChatNav } from '../core/net/ChatDtos';
import { NavState } from '../core/router/NavState';
import { NavigationService } from '../core/router/NavigationService';
import { SessionState } from '../core/session/SessionStore';
import { ChatFormat, ChatMsg, ChatVM } from '../viewmodel/ChatVM';
import { ChatBubbleView, ChatReplayCard } from './ChatSessionPage';

/**
 * 对话详情（历史，§2.9 / §6.2）。
 *
 * 数据：GET /sessions/:id（meta，无 pron）+ GET /sessions/:id/messages（含 pron/correction）。
 * 整段回放用与会话页相同的 status→200/202/500 流程（202/500 语义见 §2.8）。
 */
@Component
export struct ChatDetailPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: ChatVM = new ChatVM();
  @State expandedMsgId: string = '';

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
    if (sessionId.length === 0) {
      this.vm.loading = false;
      this.vm.loadError = '没有拿到这次对话的 ID，返回历史列表重新点一次吧';
      return;
    }
    const item = ChatNav.historyItem;
    await this.vm.initHistory(sessionId, item, this.session.isChild);
  }

  private statusText(): string {
    if (this.vm.endedAt.length > 0) {
      return '已结束';
    }
    return '还在进行';
  }

  private metaText(): string {
    const parts: string[] = [];
    const started = ChatFormat.timeText(this.vm.startedAt);
    if (started.length > 0) {
      parts.push(started);
    }
    parts.push(this.vm.turnCount.toString() + ' 轮');
    parts.push(this.statusText());
    return parts.join(' · ');
  }

  private hasPlayableAudio(msg: ChatMsg): boolean {
    if (msg.role === 'assistant') {
      return true;
    }
    return msg.audioUrl.length > 0;
  }

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
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Column({ space: 2 }) {
          Text(this.vm.titleZh.length > 0 ? this.vm.titleZh
            : (this.vm.titleEn.length > 0 ? this.vm.titleEn : '这次对话'))
            .fontSize(EcFont.h3)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
          if (this.vm.titleEn.length > 0 && this.vm.titleZh.length > 0) {
            Text(this.vm.titleEn)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
          }
          Text(this.metaText())
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Chip({ text: this.vm.isChild ? '儿童的对话' : '完整记录', tone: 'primary' })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 历史接口不返回 summary（后端缺口）：成人明确说明，不编造分数
      if (!this.vm.isChild) {
        Text('发音评价只在「结束对话」当时展示；历史记录保留完整对话、每条校正与录音。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      } else {
        Text('这次聊得很棒，慢慢看都可以 🌟')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_good_text'))
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

  build() {
    Column({ space: EcSpace.x2 }) {
      TopBar({
        title: '对话详情',
        onBack: () => {
          NavigationService.pop();
        }
      })

      Scroll(this.scroller) {
        Column({ space: EcSpace.x3 }) {
          this.headerCard()

          if (this.vm.loading) {
            LoadingBlock({ text: '正在取对话记录…' })
          }
          if (this.vm.loadError.length > 0) {
            ErrorBanner({
              message: this.vm.loadError,
              actionLabel: '重试',
              onAction: () => {
                void this.init();
              }
            })
          }

          if (this.vm.replayStatus !== 'idle') {
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

          ForEach(this.vm.messages, (item: ChatMsg) => {
            this.bubble(item)
          }, (item: ChatMsg) => item.renderKey())

          Text('历史记录按时间顺序保存，家长可回看每次对话的校正与评价。')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: EcSpace.x2, bottom: EcSpace.x6 })
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x1 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
  }
}

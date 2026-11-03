import { Chip, TopBar } from '../components/EcBlocks';
import { EmptyState } from '../components/EmptyState';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { ChatNav, ChatSessionListItemDto } from '../core/net/ChatDtos';
import { NavState } from '../core/router/NavState';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { SessionState } from '../core/session/SessionStore';
import { ChatFormat, ChatHistoryVM } from '../viewmodel/ChatVM';

/**
 * 对话历史列表（§2.9 / §6.2）。
 *
 * 移动端限制（规格已记录为后端缺口）：列表接口没有 summary 字段，
 * 因此列表只显示「时间 · 场景中文名 · N 轮」，不编造「平均发音 N」。
 */
@Component
export struct ChatHistoryPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: ChatHistoryVM = new ChatHistoryVM();

  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.load(this.session.isChild);
  }

  private openDetail(item: ChatSessionListItemDto): void {
    ChatNav.historyItem = item;
    NavState.setSession(item.id);
    NavigationService.push(Routes.CHAT_DETAIL);
  }

  private statusText(item: ChatSessionListItemDto): string {
    const ended = item.ended_at !== undefined && item.ended_at !== null && item.ended_at.length > 0;
    if (this.session.isChild) {
      return ended ? '聊完了' : '还在聊';
    }
    return ended ? '已结束' : '还在进行';
  }

  @Builder
  itemRow(item: ChatSessionListItemDto) {
    Row({ space: EcSpace.x3 }) {
      Text('💬')
        .fontSize(22)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
      Column({ space: 2 }) {
        Text(typeof item.scenario_title_zh === 'string' && item.scenario_title_zh.length > 0
          ? item.scenario_title_zh
          : (typeof item.scenario_title === 'string' ? item.scenario_title : '对话'))
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: EcSpace.x2 }) {
          Text(ChatFormat.timeText(item.started_at === undefined ? '' : item.started_at))
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
          Text((item.turn_count === undefined ? 0 : item.turn_count).toString() + ' 轮')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
          Chip({ text: this.statusText(item), tone: 'muted' })
        }
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(24)
        .fontColor($r('app.color.ec_muted'))
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(VerticalAlign.Center)
    .accessibilityText('查看这次对话的详情')
    .onClick(() => {
      this.openDetail(item);
    })
  }

  build() {
    Column({ space: EcSpace.x2 }) {
      TopBar({
        title: '对话历史',
        onBack: () => {
          NavigationService.pop();
        }
      })

      Scroll() {
        Column({ space: EcSpace.x2 }) {
          if (this.vm.loading) {
            LoadingBlock({ text: '正在取历史记录…' })
          } else if (this.vm.errorMessage.length > 0) {
            ErrorBanner({
              message: this.vm.errorMessage,
              actionLabel: '重试',
              onAction: () => {
                void this.vm.load(this.session.isChild);
              }
            })
          } else if (this.vm.items.length === 0) {
            EmptyState({
              icon: '🕘',
              message: '还没有对话记录，去「对话」选个场景开始吧',
              actionLabel: '去对话',
              onAction: () => {
                NavigationService.pop();
              }
            })
          } else {
            Text('最近 ' + this.vm.items.length.toString() + ' 次对话')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
              .padding({ top: EcSpace.x2, bottom: EcSpace.x1 })
            ForEach(this.vm.items, (item: ChatSessionListItemDto) => {
              this.itemRow(item)
            }, (item: ChatSessionListItemDto) => item.id)
            Text('历史记录按时间顺序保存，家长可回看每次对话的校正与评价。')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: EcSpace.x3, bottom: EcSpace.x6 })
          }
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x4 })
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

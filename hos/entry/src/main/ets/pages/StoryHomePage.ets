import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { EmptyState } from '../components/EmptyState';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { NavState } from '../core/router/NavState';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { SessionState } from '../core/session/SessionStore';
import { StoryCardItem, StoryGroup } from '../core/net/StoryDtos';
import { StoryHomeVM } from '../viewmodel/StoryVM';

/**
 * 故事模式（Tab 4）：故事集 + 「讲一个故事」入口 + 连续天数。
 *
 * 数据：GET /api/materials?kind=story&limit=50（家庭共享）。
 * 客户端只做展示分组（今天/昨天/更早）与连续天数，不重复过滤权限。
 * 保存新故事后由 StoryRuntime.notifySaved() 触发本页刷新（Tab 页没有 onPageShow）。
 */
@Component
export struct StoryHomePage {
  @StorageLink('session') session: SessionState = new SessionState();
  @StorageProp('storyRefreshTick') @Watch('onRefreshTick') refreshTick: number = 0;
  @State vm: StoryHomeVM = new StoryHomeVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    this.vm.setUser(this.session.userId, this.session.isChild);
    void this.vm.load();
  }

  onRefreshTick(): void {
    if (!this.started) {
      return;
    }
    this.vm.setUser(this.session.userId, this.session.isChild);
    void this.vm.load();
  }

  // ------------------------------------------------------------------ 页头

  @Builder
  header() {
    Column({ space: EcSpace.x1 }) {
      Text(this.session.isChild ? '📖 我的故事书' : '📖 我的故事')
        .fontSize(this.session.isChild ? EcFont.childH1 : EcFont.h1)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      Text(this.session.isChild
        ? '用中文讲讲今天发生的事，我帮你变英文故事'
        : '中文讲、中文写都可以；存下来就是家庭共享的英文故事书')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  heroCard() {
    Column({ space: EcSpace.x3 }) {
      Row({ space: EcSpace.x3 }) {
        Text('✨')
          .fontSize(30)
        Column({ space: 2 }) {
          Text(this.session.isChild ? '讲一个今天的故事' : '讲一个故事')
            .fontSize(EcFont.h3)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
          Text('说法子：今天发生了什么？和谁一起？你开心吗？')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      EcButton({
        label: this.session.isChild ? '🎤 我要讲故事' : '✨ 讲一个故事',
        kind: EcButtonKind.PRIMARY,
        big: this.session.isChild,
        onTap: () => {
          NavigationService.push(Routes.STORY_RECORD);
        }
      })
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statsRow() {
    Row({ space: EcSpace.x2 }) {
      if (this.vm.streakDays > 0) {
        Row({ space: 4 }) {
          Text('🔥')
            .fontSize(EcFont.caption)
          Text('连续 ' + this.vm.streakDays.toString() + ' 天')
            .fontSize(EcFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_warn_text'))
        }
        .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 3, bottom: 3 })
        .backgroundColor($r('app.color.ec_warn_bg'))
        .borderRadius(EcRadius.pill)
      }
      Text('共 ' + this.vm.total.toString() + ' 篇')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
      Blank()
      Text('↻ 刷新')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_primary'))
        .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
        .accessibilityText('刷新故事集')
        .onClick(() => {
          void this.vm.load();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  filterRow() {
    Row({ space: EcSpace.x2 }) {
      Text('全家')
        .fontSize(EcFont.caption)
        .fontWeight(this.vm.onlyMine ? FontWeight.Normal : FontWeight.Medium)
        .fontColor(this.vm.onlyMine ? $r('app.color.ec_muted') : Color.White)
        .backgroundColor(this.vm.onlyMine ? $r('app.color.ec_surface_alt') : $r('app.color.ec_primary'))
        .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x1, bottom: EcSpace.x1 })
        .borderRadius(EcRadius.pill)
        .accessibilityText('显示全家故事')
        .onClick(() => {
          this.vm.setOnlyMine(false);
        })
      Text('只看我的')
        .fontSize(EcFont.caption)
        .fontWeight(this.vm.onlyMine ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.vm.onlyMine ? Color.White : $r('app.color.ec_muted'))
        .backgroundColor(this.vm.onlyMine ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
        .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x1, bottom: EcSpace.x1 })
        .borderRadius(EcRadius.pill)
        .accessibilityText('只看我创建的故事')
        .onClick(() => {
          this.vm.setOnlyMine(true);
        })
      Blank()
      Text('今天 ' + this.vm.filteredCount.toString() + ' 篇')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ------------------------------------------------------------------ 列表

  @Builder
  storyRow(item: StoryCardItem) {
    Row({ space: EcSpace.x3 }) {
      Text(item.hasImage ? '🖼️' : '📖')
        .fontSize(22)
        .width(46)
        .height(46)
        .textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
      Column({ space: 3 }) {
        Text(item.title)
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: EcSpace.x1 }) {
          if (item.level.length > 0) {
            Chip({ text: item.level, tone: 'primary' })
          }
          Chip({ text: item.sentenceCount.toString() + ' 句' })
          if (item.dateText.length > 0) {
            Text(item.dateText)
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
          }
          if (item.authorName.length > 0) {
            Text('· ' + item.authorName)
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(22)
        .fontColor($r('app.color.ec_muted'))
    }
    .width('100%')
    .padding({ top: EcSpace.x3, bottom: EcSpace.x3 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(item.title)
    .onClick(() => {
      NavState.setStory(item.id, item.material);
      NavigationService.push(Routes.STORY_DETAIL);
    })
  }

  @Builder
  storyGroups() {
    Column({ space: EcSpace.x2 }) {
      ForEach(this.vm.groups, (group: StoryGroup) => {
        Column({ space: EcSpace.x1 }) {
          Text(group.label + ' · ' + group.items.length.toString() + ' 篇')
            .fontSize(EcFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
            .padding({ left: EcSpace.x2 })
          Column() {
            ForEach(group.items, (item: StoryCardItem, index: number) => {
              if (index > 0) {
                Divider()
                  .color($r('app.color.ec_border'))
              }
              this.storyRow(item)
            }, (item: StoryCardItem) => item.id)
          }
          .width('100%')
          .padding({ left: EcSpace.x4, right: EcSpace.x4 })
          .backgroundColor($r('app.color.ec_surface'))
          .borderRadius(EcRadius.lg)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (group: StoryGroup) => group.label)
    }
    .width('100%')
  }

  @Builder
  emptyBlock() {
    if (this.vm.total > 0 && this.vm.onlyMine) {
      EmptyState({
        icon: '🔍',
        message: '你还没有讲过故事，或者还没有「只看我的」。',
        actionLabel: '看全家故事',
        onAction: () => {
          this.vm.setOnlyMine(false);
        }
      })
    } else {
      EmptyState({
        icon: '📖',
        message: this.session.isChild
          ? '还没有故事。讲讲今天发生的事，存下来就是你的第一本英文故事书。'
          : '还没有故事。讲讲今天发生的事，存下来就是你的第一本英文故事书。',
        actionLabel: '讲一个故事',
        onAction: () => {
          NavigationService.push(Routes.STORY_RECORD);
        }
      })
    }
  }

  build() {
    Scroll() {
      Column({ space: EcSpace.x3 }) {
        this.header()
        this.heroCard()
        this.statsRow()
        if (!this.vm.loading && this.vm.loadError.length === 0 && this.vm.total > 0) {
          this.filterRow()
        }
        if (this.vm.loading) {
          LoadingBlock({ text: '正在打开故事书…' })
        } else if (this.vm.loadError.length > 0) {
          ErrorBanner({
            title: '故事集没打开',
            message: this.vm.loadError,
            actionLabel: '重试',
            onAction: () => {
              void this.vm.load();
            }
          })
        } else if (this.vm.filteredCount === 0) {
          this.emptyBlock()
        } else {
          this.storyGroups()
        }
        Text('故事保存在家庭共享的书架上，全家都能看到。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: EcSpace.x2, bottom: EcSpace.x6 })
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor($r('app.color.ec_bg'))
  }
}

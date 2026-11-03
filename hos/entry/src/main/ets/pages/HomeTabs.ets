import { EcFont, EcSpace } from '../design/DesignTokens';
import { PracticePage } from './PracticePage';
import { FlowPage } from './FlowPage';
import { ChatScenariosPage } from './ChatScenariosPage';
import { StoryHomePage } from './StoryHomePage';
import { MePage } from './MePage';

/** 已登录首页：5 个 Tab（跟读 / 连读 / 对话 / 故事 / 我的）。 */
@Component
export struct HomeTabs {
  @StorageLink('tab_index') @Watch('onTabIndexChanged') pendingTab: number = 0;
  /** voice.reachable=false 时显示琥珀降级提示条（README §2.4 / screens-matrix §8） */
  @StorageProp('voice_degraded') voiceDegraded: boolean = false;
  @State current: number = 0;
  private controller: TabsController = new TabsController();

  onTabIndexChanged(): void {
    if (this.pendingTab !== this.current) {
      this.current = this.pendingTab;
      this.controller.changeIndex(this.pendingTab);
    }
  }

  private labels: string[] = ['跟读', '连读', '对话', '故事', '我的'];
  private icons: string[] = ['🎤', '🔗', '💬', '📖', '🙂'];

  @Builder
  tabBar(index: number) {
    Column({ space: 2 }) {
      Text(this.icons[index])
        .fontSize(index === this.current ? 22 : 20)
      Text(this.labels[index])
        .fontSize(EcFont.micro)
        .fontWeight(index === this.current ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(index === this.current ? $r('app.color.ec_primary') : $r('app.color.ec_muted'))
    }
    .width('20%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(this.labels[index])
    .onClick(() => {
      this.current = index;
      this.controller.changeIndex(index);
    })
  }

  @Builder
  degradedBanner() {
    Row({ space: EcSpace.x2 }) {
      Text('⚠️')
        .fontSize(14)
      Text('语音服务暂时不可用：录音会先保存，稍后可在结果页重试评测')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_warn_text'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x2, bottom: EcSpace.x2 })
    .backgroundColor($r('app.color.ec_warn_bg'))
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      if (this.voiceDegraded) {
        this.degradedBanner()
      }
      Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
        TabContent() {
          PracticePage()
        }.tabBar(this.tabBar(0))

        TabContent() {
          FlowPage()
        }.tabBar(this.tabBar(1))

        TabContent() {
          ChatScenariosPage()
        }.tabBar(this.tabBar(2))

        TabContent() {
          StoryHomePage()
        }.tabBar(this.tabBar(3))

        TabContent() {
          MePage()
        }.tabBar(this.tabBar(4))
      }
      .layoutWeight(1)
      .width('100%')
      .barHeight(56)
      .barMode(BarMode.Fixed)
      .barBackgroundColor($r('app.color.ec_surface'))
      .scrollable(false)
      .onChange((index: number) => {
        this.current = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
  }
}

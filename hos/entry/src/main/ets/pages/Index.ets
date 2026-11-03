import { AppConfig } from '../core/config/AppConfig';
import { AppRuntime } from '../core/config/AppRuntime';
import { ErrorMapper, UiError } from '../core/error/UiError';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { CacheService } from '../core/service/CacheService';
import { PracticeService } from '../core/service/PracticeService';
import { SessionState, SessionStore } from '../core/session/SessionStore';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { EmptyState } from '../components/EmptyState';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcSpace } from '../design/DesignTokens';
import { LoginPage } from './LoginPage';
import { HomeTabs } from './HomeTabs';
import { SettingsPage } from './SettingsPage';
import { FlowSummaryPage } from './FlowSummaryPage';
import { ChatSessionPage } from './ChatSessionPage';
import { ChatHistoryPage } from './ChatHistoryPage';
import { ChatDetailPage } from './ChatDetailPage';
import { ChatCustomPage } from './ChatCustomPage';
import { StoryRecordPage } from './StoryRecordPage';
import { StoryDetailPage } from './StoryDetailPage';
import { StoryReviewPage } from './StoryReviewPage';
import { DiagnosisPage } from './DiagnosisPage';
import { ReviewPage } from './ReviewPage';
import { BlindTestPage } from './BlindTestPage';
import { ParentPage } from './ParentPage';
import { FamilyPage } from './FamilyPage';
import { SuggestionsPage } from './SuggestionsPage';
import { AvatarPage } from './AvatarPage';
import { VoicesPage } from './VoicesPage';
import { HealthPage } from './HealthPage';
import { PracticeResultPage } from './PracticeResultPage';

/**
 * 应用根：Navigation + 会话门禁。
 *
 * 启动 → 读 Asset token → GET /auth/me
 *   ├─ 成功 → 根内容 = HomeTabs（跟读/连读/对话/故事/我的）
 *   ├─ 需要登录 → 根内容 = 登录页
 *   └─ 网络失败 → 全屏错误 + 重试（不误清 token）
 *
 * 所有二级页面都是 NavDestination（覆盖 Tab 栏，带返回）。
 */
@Entry
@Component
struct Index {
  @StorageLink('session') @Watch('onSessionChanged') session: SessionState = new SessionState();
  @State booting: boolean = true;
  @State bootErrorTitle: string = '';
  @State bootError: string = '';
  private navStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    NavigationService.bind(this.navStack);
    void this.bootstrap();
  }

  aboutToDisappear(): void {
    NavigationService.unbind();
  }

  /** 登出 / 会话过期：清空 push 出来的页面，根内容自动切回登录页。 */
  onSessionChanged(): void {
    if (!this.session.loggedIn) {
      NavigationService.clear();
    }
  }

  private async bootstrap(): Promise<void> {
    this.booting = true;
    this.bootErrorTitle = '';
    this.bootError = '';
    try {
      const ctx = AppRuntime.context();
      if (ctx !== null && !AppConfig.isInitialized()) {
        await AppConfig.init(ctx);
      }
      CacheService.cleanupOnBoot();
      await SessionStore.restore();
      // 语音服务降级提示（voice.reachable=false 时首页顶部琥珀条）
      try {
        const health = await PracticeService.health();
        const voice = health.voice;
        AppStorage.setOrCreate<boolean>('voice_degraded', voice !== undefined && voice.reachable === false);
      } catch (err) {
        // 健康检查失败不影响进入 App
      }
    } catch (err) {
      const ui: UiError = ErrorMapper.from(err as Error, false);
      this.bootErrorTitle = ui.title;
      this.bootError = ui.message;
    } finally {
      this.booting = false;
    }
  }

  @Builder
  pageMap(name: string) {
    if (name === Routes.SETTINGS) {
      NavDestination() {
        SettingsPage()
      }.title('设置').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.PRACTICE_RESULT) {
      NavDestination() {
        PracticeResultPage()
      }.title('跟读结果').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.FLOW_SUMMARY) {
      NavDestination() {
        FlowSummaryPage()
      }.title('连读汇总').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.CHAT_SESSION) {
      NavDestination() {
        ChatSessionPage()
      }.title('对话中').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.CHAT_HISTORY) {
      NavDestination() {
        ChatHistoryPage()
      }.title('对话历史').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.CHAT_DETAIL) {
      NavDestination() {
        ChatDetailPage()
      }.title('对话详情').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.CHAT_CUSTOM) {
      NavDestination() {
        ChatCustomPage()
      }.title('自定义场景').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.STORY_RECORD) {
      NavDestination() {
        StoryRecordPage()
      }.title('讲故事').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.STORY_DETAIL) {
      NavDestination() {
        StoryDetailPage()
      }.title('故事').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.STORY_REVIEW) {
      NavDestination() {
        StoryReviewPage()
      }.title('复述故事').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.DIAGNOSIS) {
      NavDestination() {
        DiagnosisPage()
      }.title('发音诊断').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.REVIEW) {
      NavDestination() {
        ReviewPage()
      }.title('错音本').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.BLIND_TEST) {
      NavDestination() {
        BlindTestPage()
      }.title('盲测').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.PARENT) {
      NavDestination() {
        ParentPage()
      }.title('家长面板').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.FAMILY) {
      NavDestination() {
        FamilyPage()
      }.title('家庭成员').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.SUGGESTIONS) {
      NavDestination() {
        SuggestionsPage()
      }.title('建议箱').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.AVATAR) {
      NavDestination() {
        AvatarPage()
      }.title('我的形象').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.VOICES) {
      NavDestination() {
        VoicesPage()
      }.title('音色').backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.HEALTH) {
      NavDestination() {
        HealthPage()
      }.title('服务状态').backgroundColor($r('app.color.ec_bg'))
    } else {
      NavDestination() {
        EmptyState({
          icon: '🧭',
          message: '这个页面不存在',
          actionLabel: '返回',
          onAction: () => {
            NavigationService.pop();
          }
        })
      }.title('').backgroundColor($r('app.color.ec_bg'))
    }
  }

  @Builder
  launchView() {
    Column({ space: EcSpace.x3 }) {
      Text('English Coach')
        .fontSize(EcFont.h1)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
      Text('家庭英语口语教练')
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_muted'))
      LoadingBlock({ text: '正在连接家庭 NAS…', subText: '只在家庭 Wi-Fi / VPN 下可用' })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.ec_bg'))
  }

  @Builder
  bootErrorView() {
    Column({ space: EcSpace.x4 }) {
      Text('🏠')
        .fontSize(44)
      Text(this.bootErrorTitle.length > 0 ? this.bootErrorTitle : '连不上家庭 NAS')
        .fontSize(EcFont.h2)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
      Text(this.bootError)
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_muted'))
        .textAlign(TextAlign.Center)
      EcButton({
        label: '重试',
        kind: EcButtonKind.PRIMARY,
        btnWidth: '200vp',
        onTap: () => {
          void this.bootstrap();
        }
      })
      Text('如果一直连不上，可以在登录页修改服务器地址')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
    }
    .width('100%')
    .height('100%')
    .padding(EcSpace.x8)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.ec_bg'))
  }

  build() {
    Navigation(this.navStack) {
      Column() {
        if (this.booting) {
          this.launchView()
        } else if (this.bootError.length > 0) {
          this.bootErrorView()
        } else if (this.session.loggedIn) {
          HomeTabs()
        } else {
          LoginPage()
        }
      }
      .width('100%')
      .height('100%')
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.ec_bg'))
  }
}

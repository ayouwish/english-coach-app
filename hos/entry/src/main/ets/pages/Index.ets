import { AppConfig } from '../core/config/AppConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
  /** 诊断用：错误码 + 当前服务器地址（连不上时显示在错误页，便于定位） */
  @State bootErrorCode: string = '';
  /** 启动失败时直接在错误页改服务器地址（不用先到登录页） */
  @State editingAddress: boolean = false;
  @State addressInput: string = '';
  @State addressBusy: boolean = false;
  @State addressError: string = '';
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
      this.bootErrorCode = ui.code + ' · ' + AppConfig.getBaseUrl();
      hilog.error(0xEC00, 'Bootstrap', 'boot failed code=%{public}s err=%{public}s base=%{public}s',
        ui.code, (err as Error).message, AppConfig.getBaseUrl());
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
      }
      // 页面自带 TopBar，隐藏系统标题避免双标题/内容被顶出屏幕
      .hideTitleBar(true)
      .backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.CHAT_SESSION) {
      NavDestination() {
        ChatSessionPage()
      }
      // 页面自带 TopBar（返回 + 场景名 + 结束），再显示系统标题会重复占空间
      .hideTitleBar(true)
      .backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.CHAT_HISTORY) {
      NavDestination() {
        ChatHistoryPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.CHAT_DETAIL) {
      NavDestination() {
        ChatDetailPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.CHAT_CUSTOM) {
      NavDestination() {
        ChatCustomPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.ec_bg'))
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

  private beginEditAddress(): void {
    this.addressInput = AppConfig.getBaseUrl();
    this.addressError = '';
    this.editingAddress = true;
  }

  private async saveAddress(): Promise<void> {
    if (this.addressBusy) {
      return;
    }
    this.addressBusy = true;
    this.addressError = '';
    try {
      await AppConfig.setBaseUrl(this.addressInput);
      this.editingAddress = false;
      await this.bootstrap();
    } catch (err) {
      this.addressError = '地址格式不对，示例：https://english.dreamsearch.top';
    } finally {
      this.addressBusy = false;
    }
  }

  /** 不想改地址时，也可以先去登录页（那里有完整的地址编辑与健康检查）。 */
  private goLogin(): void {
    SessionStore.set(new SessionState());
    this.bootErrorTitle = '';
    this.bootError = '';
    this.bootErrorCode = '';
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
      if (this.bootErrorCode.length > 0) {
        Text('诊断：' + this.bootErrorCode)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .textAlign(TextAlign.Center)
      }
      if (this.editingAddress) {
        Column({ space: EcSpace.x2 }) {
          Text('服务器地址')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
            .textAlign(TextAlign.Center)
          TextInput({ text: this.addressInput, placeholder: 'https://english.dreamsearch.top' })
            .type(InputType.Normal)
            .height(48)
            .width('100%')
            .fontSize(EcFont.body)
            .fontColor($r('app.color.ec_ink'))
            .backgroundColor($r('app.color.ec_surface'))
            .borderRadius(12)
            .onChange((value: string) => {
              this.addressInput = value;
            })
          if (this.addressError.length > 0) {
            Text(this.addressError)
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_bad_text'))
              .textAlign(TextAlign.Center)
          }
          Row({ space: EcSpace.x2 }) {
            EcButton({
              label: this.addressBusy ? '保存中…' : '保存并重试',
              kind: EcButtonKind.PRIMARY,
              btnWidth: '48%',
              loading: this.addressBusy,
              onTap: () => {
                void this.saveAddress();
              }
            })
            EcButton({
              label: '取消',
              kind: EcButtonKind.GHOST,
              btnWidth: '48%',
              onTap: () => {
                this.editingAddress = false;
              }
            })
          }
          .width('60%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else {
        EcButton({
          label: '⚙️ 修改服务器地址',
          kind: EcButtonKind.GHOST,
          btnWidth: '200vp',
          onTap: () => {
            this.beginEditAddress();
          }
        })
      }
      EcButton({
        label: '重试',
        kind: EcButtonKind.PRIMARY,
        btnWidth: '200vp',
        onTap: () => {
          void this.bootstrap();
        }
      })
      Text('也可以先去登录页（那边有完整的地址编辑与网络检查）')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.goLogin();
        })
        .decoration({ type: TextDecorationType.Underline })
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

import { AppConfig } from '../core/config/AppConfig';
import { AppRuntime } from '../core/config/AppRuntime';
import { ErrorMapper, UiError } from '../core/error/UiError';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { CacheService } from '../core/service/CacheService';
import { SessionState, SessionStore } from '../core/session/SessionStore';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { EmptyState } from '../components/EmptyState';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcSpace } from '../design/DesignTokens';
import { LoginPage } from './LoginPage';
import { PracticePage } from './PracticePage';
import { SentenceListPage } from './SentenceListPage';
import { SettingsPage } from './SettingsPage';

/**
 * 应用根：Navigation + 会话门禁。
 *
 * 结构（docs/architecture.md §4.3）：
 *   启动 → 读 Asset token → GET /auth/me
 *     ├─ 成功 → 根内容 = 语料列表（已登录首页）
 *     ├─ 需要登录 → 根内容 = 登录页
 *     └─ 网络失败 → 全屏错误 + 重试（不误清 token）
 *
 * 只有「跟读」「设置」是 push 出来的 NavDestination，其余是根内容。
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
    if (name === Routes.PRACTICE) {
      NavDestination() {
        PracticePage()
      }
      .title('跟读练习')
      .backgroundColor($r('app.color.ec_bg'))
    } else if (name === Routes.SETTINGS) {
      NavDestination() {
        SettingsPage()
      }
      .title('设置')
      .backgroundColor($r('app.color.ec_bg'))
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
      }
      .title('')
      .backgroundColor($r('app.color.ec_bg'))
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
      // Navigation 的首页内容只放一个容器，内部按启动态切换，避免条件渲染作为 Navigation 直接子节点
      Column() {
        if (this.booting) {
          this.launchView()
        } else if (this.bootError.length > 0) {
          this.bootErrorView()
        } else if (this.session.loggedIn) {
          SentenceListPage()
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

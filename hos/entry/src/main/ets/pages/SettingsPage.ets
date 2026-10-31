import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { AppConfig } from '../core/config/AppConfig';
import { NavigationService } from '../core/router/NavigationService';
import { SessionState } from '../core/session/SessionStore';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { SettingsVM } from '../viewmodel/SettingsVM';

/**
 * 设置页：账号信息、服务器地址、清缓存、凭证存储说明、退出登录。
 *
 * M0 未做（见 README 待办）：朗读语速/纠正强度偏好、修改密码、隐私说明静态页、
 * release 包 address 只读、退出二次确认弹窗。
 */
@Component
export struct SettingsPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: SettingsVM = new SettingsVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init();
  }

  private roleText(): string {
    return this.session.role === 'parent' ? '家长' : '儿童';
  }

  private usageText(): string {
    const minutes = Math.round(this.session.minutesToday * 10) / 10;
    return '今日 ' + minutes.toString() + ' / ' + this.session.dailyLimitMinutes.toString() + ' 分钟';
  }

  private async onLogout(): Promise<void> {
    await this.vm.logout();
    NavigationService.clear();
  }

  @Builder
  accountCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.session.avatar.length > 0 ? this.session.avatar : '🙂')
          .fontSize(28)
        Column({ space: EcSpace.x1 }) {
          Text(this.session.displayName.length > 0 ? this.session.displayName : '家庭账号')
            .fontSize(EcFont.h3)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_ink'))
          Text(this.roleText() + ' · ' + this.session.cefrLevel + ' · ' + this.usageText())
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.vm.tokenStorageNote())
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  serverCard() {
    Column({ space: EcSpace.x2 }) {
      Text('服务器地址')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      TextInput({ text: this.vm.baseUrl, placeholder: AppConfig.DEFAULT_BASE_URL })
        .type(InputType.Normal)
        .height(48)
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_ink'))
        .placeholderColor($r('app.color.ec_muted'))
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.baseUrl = value;
        })
      Row({ space: EcSpace.x2 }) {
        Text(this.vm.checkingServer ? '正在检查…'
          : (this.vm.serverStatus.length > 0 ? this.vm.serverStatus : '未检查'))
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .maxLines(3)
          .layoutWeight(1)
        Text('检查')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .onClick(() => {
            void this.vm.checkServer();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      EcButton({
        label: this.vm.saving ? '保存中…' : '保存地址',
        kind: EcButtonKind.TONAL,
        loading: this.vm.saving,
        onTap: () => {
          void this.vm.saveBaseUrl();
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
  miscCard() {
    Column({ space: EcSpace.x3 }) {
      Row() {
        Column({ space: EcSpace.x1 }) {
          Text('示范音与回放缓存')
            .fontSize(EcFont.body)
            .fontColor($r('app.color.ec_ink'))
          Text('只清理本地音频文件，不影响账号数据')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('清除')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .onClick(() => {
            this.vm.clearCache();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('版本 ' + AppConfig.APP_VERSION + '（M0 垂直切片，未编译验证）')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Text('隐私说明：录音会经家庭 NAS 转发到云端做识别与评分，不是纯本地处理。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: EcSpace.x4 }) {
        this.accountCard()

        if (this.vm.hasNotice) {
          Row({ space: EcSpace.x2 }) {
            Text(this.vm.notice)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_good_text'))
              .layoutWeight(1)
            Text('知道了')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_primary'))
              .onClick(() => {
                this.vm.clearNotice();
              })
          }
          .width('100%')
          .padding(EcSpace.x3)
          .backgroundColor($r('app.color.ec_good_bg'))
          .borderRadius(EcRadius.md)
        }

        if (this.vm.hasError) {
          ErrorBanner({
            title: '',
            message: this.vm.error.message,
            actionLabel: '',
            onAction: () => {
            }
          })
        }

        this.serverCard()
        this.miscCard()

        EcButton({
          label: this.vm.loggingOut ? '退出中…' : '退出登录',
          kind: EcButtonKind.DANGER,
          loading: this.vm.loggingOut,
          big: true,
          onTap: () => {
            void this.onLogout();
          }
        })

        Text('退出后需要重新输入账号密码；本地录音与缓存会被清理。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .margin({ bottom: EcSpace.x6 })
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x3, bottom: EcSpace.x8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .scrollBar(BarState.Off)
  }
}

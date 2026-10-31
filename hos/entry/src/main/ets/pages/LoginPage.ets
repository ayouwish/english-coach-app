import { DemoAccount } from '../core/config/AppConfig';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { LoginVM } from '../viewmodel/LoginVM';

/**
 * 登录页（根内容，未登录时展示，不能返回）。
 *
 * 交互：邮箱/密码/服务器地址 + 演示账号一键填入 + 健康状态。
 * 成功后由 SessionStore 写 AppStorage('session')，Index 自动切到语料列表。
 */
@Component
export struct LoginPage {
  @State vm: LoginVM = new LoginVM();

  aboutToAppear(): void {
    void this.vm.init();
  }

  private serverStatusText(): string {
    if (this.vm.checkingServer) {
      return '正在检查服务器…';
    }
    if (this.vm.serverStatus.length === 0) {
      return '未检查';
    }
    return this.vm.serverStatus;
  }

  private serverColor(): ResourceColor {
    if (this.vm.checkingServer) {
      return $r('app.color.ec_muted');
    }
    if (this.vm.serverStatus.indexOf('已连接') >= 0) {
      return $r('app.color.ec_good_text');
    }
    if (this.vm.serverStatus.length === 0) {
      return $r('app.color.ec_muted');
    }
    return $r('app.color.ec_bad_text');
  }

  build() {
    Scroll() {
      Column({ space: EcSpace.x4 }) {
        Column({ space: EcSpace.x1 }) {
          Text('English Coach')
            .fontSize(EcFont.h1)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_ink'))
          Text('家庭英语口语教练')
            .fontSize(EcFont.body)
            .fontColor($r('app.color.ec_muted'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: EcSpace.x8, bottom: EcSpace.x2 })

        Column({ space: EcSpace.x2 }) {
          Text('服务器地址')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
          TextInput({ text: this.vm.baseUrl, placeholder: 'https://english.dreamsearch.top' })
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
            Text(this.serverStatusText())
              .fontSize(EcFont.caption)
              .fontColor(this.serverColor())
              .maxLines(2)
              .layoutWeight(1)
            Text('重试')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_primary'))
              .padding({ left: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
              .accessibilityText('重新检查服务器')
              .onClick(() => {
                void this.vm.checkServer();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(EcSpace.x4)
        .backgroundColor($r('app.color.ec_surface'))
        .borderRadius(EcRadius.lg)
        .shadow(EcShadow.card())
        .alignItems(HorizontalAlign.Start)

        Column({ space: EcSpace.x3 }) {
          TextInput({ text: this.vm.email, placeholder: '邮箱（如 dad@example.com）' })
            .type(InputType.Email)
            .height(48)
            .fontSize(EcFont.body)
            .fontColor($r('app.color.ec_ink'))
            .placeholderColor($r('app.color.ec_muted'))
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.md)
            .onChange((value: string) => {
              this.vm.email = value;
            })
          TextInput({ text: this.vm.password, placeholder: '密码' })
            .type(InputType.Password)
            .showPasswordIcon(true)
            .height(48)
            .fontSize(EcFont.body)
            .fontColor($r('app.color.ec_ink'))
            .placeholderColor($r('app.color.ec_muted'))
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.md)
            .onChange((value: string) => {
              this.vm.password = value;
            })
        }
        .width('100%')

        if (this.vm.hasError) {
          ErrorBanner({
            title: this.vm.error.title,
            message: this.vm.error.message,
            actionLabel: '',
            onAction: () => {
            }
          })
        }

        EcButton({
          label: this.vm.loading ? '登录中…' : '登 录',
          kind: EcButtonKind.PRIMARY,
          loading: this.vm.loading,
          big: true,
          onTap: () => {
            void this.vm.login();
          }
        })

        Column({ space: EcSpace.x2 }) {
          Text('演示账号（后端种子数据，可用环境变量修改）')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
          Row({ space: EcSpace.x2 }) {
            ForEach(this.vm.demos, (item: DemoAccount) => {
              EcButton({
                label: item.label,
                kind: EcButtonKind.GHOST,
                btnWidth: '48%',
                onTap: () => {
                  this.vm.fillDemo(item);
                }
              })
            }, (item: DemoAccount) => item.email)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')

        Text('忘记密码？让家长在家长面板重置。账号由家长创建，不提供自助注册。')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .margin({ top: EcSpace.x2 })
      }
      .width('100%')
      .padding({ left: EcSpace.x5, right: EcSpace.x5, top: EcSpace.x4, bottom: EcSpace.x8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .scrollBar(BarState.Off)
  }
}

import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { TopBar } from '../components/EcBlocks';
import { EcFont, EcRadius, EcSpace } from '../design/DesignTokens';
import { NavigationService } from '../core/router/NavigationService';
import { RegisterVM } from '../viewmodel/RegisterVM';

/**
 * 注册页（多家庭两级邀请）：
 * - 🔑 受邀加入家庭：用「共同家长邀请码」加入现有家庭；
 * - 🏠 受邀创建新家庭：用管理员生成的「新家庭邀请码」创建全新家庭；
 * - 🆕 创建家庭：仅当服务端 self_signup=true 时显示（默认关闭）。
 * 孩子账号仍由家长在「家长面板 → 家庭成员」里创建。
 */
@Component
export struct RegisterPage {
  @State vm: RegisterVM = new RegisterVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init();
  }

  private async submit(): Promise<void> {
    const ok = await this.vm.submit();
    if (ok) {
      NavigationService.clear();
    }
  }

  private submitLabel(): string {
    if (this.vm.loading) {
      return '正在提交…';
    }
    if (this.vm.mode === 'newfamily') {
      return '创建新家庭并开始';
    }
    if (this.vm.mode === 'create') {
      return '创建家庭并开始';
    }
    return '加入家庭并开始';
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(EcFont.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.ec_ink'))
      .width('100%')
  }

  @Builder
  modeChipView(label: string, active: boolean, mode: string) {
    Text(label)
      .fontSize(EcFont.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor(active ? Color.White : $r('app.color.ec_muted'))
      .backgroundColor(active ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
      .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
      .borderRadius(EcRadius.pill)
      .margin({ right: EcSpace.x2, bottom: EcSpace.x2 })
      .onClick(() => {
        this.vm.setMode(mode);
      })
  }

  build() {
    Column({ space: EcSpace.x2 }) {
      TopBar({
        title: '注册 / 加入家庭',
        onBack: () => {
          NavigationService.pop();
        }
      })

      Scroll() {
        Column({ space: EcSpace.x3 }) {
          Text('开始使用 English Coach')
            .fontSize(EcFont.h2)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
          Text('每个家庭独立使用、互相看不到数据。凭家长或管理员分享的邀请码加入/创建家庭。')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap }) {
            this.modeChipView('🔑 受邀加入家庭', this.vm.mode === 'join', 'join')
            this.modeChipView('🏠 受邀创建新家庭', this.vm.mode === 'newfamily', 'newfamily')
            if (this.vm.allowSelfSignup) {
              this.modeChipView('🆕 创建家庭', this.vm.mode === 'create', 'create')
            }
          }
          .width('100%')

          if (!this.vm.allowSelfSignup && this.vm.featureChecked) {
            Text('公开注册已关闭。请用家长分享的邀请码加入家庭，或用管理员分享的新家庭邀请码创建新家庭。')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_warn_text'))
              .width('100%')
              .padding(EcSpace.x2)
              .backgroundColor($r('app.color.ec_warn_bg'))
              .borderRadius(EcRadius.sm)
          }

          if (this.vm.mode !== 'join') {
            this.fieldLabel('家庭名称')
            TextInput({
              text: this.vm.familyName,
              placeholder: this.vm.mode === 'newfamily' ? '你的新家庭名称（例如：李家）' : '例如：王家'
            })
              .type(InputType.Normal)
              .height(48)
              .fontSize(EcFont.body)
              .backgroundColor($r('app.color.ec_surface_alt'))
              .borderRadius(EcRadius.md)
              .onChange((value: string) => {
                this.vm.familyName = value;
              })
          }

          if (this.vm.mode === 'join') {
            this.fieldLabel('邀请码')
            TextInput({ text: this.vm.inviteCode, placeholder: '8 位邀请码（一次性）' })
              .type(InputType.Normal)
              .height(48)
              .fontSize(EcFont.body)
              .backgroundColor($r('app.color.ec_surface_alt'))
              .borderRadius(EcRadius.md)
              .onChange((value: string) => {
                this.vm.inviteCode = value.toUpperCase();
              })
          } else if (this.vm.mode === 'newfamily') {
            this.fieldLabel('新家庭邀请码')
            TextInput({ text: this.vm.newFamilyCode, placeholder: '8 位新家庭邀请码（一次性）' })
              .type(InputType.Normal)
              .height(48)
              .fontSize(EcFont.body)
              .backgroundColor($r('app.color.ec_surface_alt'))
              .borderRadius(EcRadius.md)
              .onChange((value: string) => {
                this.vm.newFamilyCode = value.toUpperCase();
              })
          }

          this.fieldLabel('你的昵称')
          TextInput({ text: this.vm.displayName, placeholder: '例如：爸爸' })
            .type(InputType.Normal)
            .height(48)
            .fontSize(EcFont.body)
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.md)
            .onChange((value: string) => {
              this.vm.displayName = value;
            })

          this.fieldLabel('邮箱')
          TextInput({ text: this.vm.email, placeholder: 'you@example.com' })
            .type(InputType.Email)
            .height(48)
            .fontSize(EcFont.body)
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.md)
            .onChange((value: string) => {
              this.vm.email = value;
            })

          this.fieldLabel('密码（至少 8 位）')
          TextInput({ text: this.vm.password, placeholder: '至少 8 位' })
            .type(InputType.Password)
            .height(48)
            .fontSize(EcFont.body)
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.md)
            .onChange((value: string) => {
              this.vm.password = value;
            })

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
            label: this.submitLabel(),
            kind: EcButtonKind.PRIMARY,
            loading: this.vm.loading,
            big: true,
            onTap: () => {
              void this.submit();
            }
          })

          Text('孩子账号由家长在「家长面板 → 家庭成员」里创建。邀请码一次性使用，家长可在面板重置。')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
          Text('已有账号？去登录')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .onClick(() => {
              NavigationService.pop();
            })
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4, bottom: EcSpace.x8 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
  }
}

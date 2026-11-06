import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { FamilyMemberDto } from '../core/net/AccountDtos';
import { SessionState } from '../core/session/SessionStore';
import { FamilyVM } from '../viewmodel/AccountVM';

/**
 * 家庭成员（`/api/family/members`，仅家长）：列表 + 新建 + 编辑 + 重置密码。
 * 列表是"全部 users"且字段为 snake_case；儿童调用全部 403。
 */
@Component
export struct FamilyPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: FamilyVM = new FamilyVM();
  private started: boolean = false;
  private cefrOptions: string[] = ['A1', 'A2', 'B1', 'B2', 'C1'];
  private roleKeys: string[] = ['parent', 'child'];
  private roleLabels: string[] = ['家长', '孩子'];

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init();
  }

  private chipFg(selected: boolean): ResourceColor {
    return selected ? Color.White : $r('app.color.ec_muted');
  }

  private chipBg(selected: boolean): ResourceColor {
    return selected ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt');
  }

  @Builder
  smallChoice(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(EcFont.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.chipFg(selected))
      .backgroundColor(this.chipBg(selected))
      .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
      .borderRadius(EcRadius.pill)
      .margin({ right: EcSpace.x2, bottom: EcSpace.x2 })
      .accessibilityText(label)
      .onClick(onTap)
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(EcFont.micro)
      .fontColor($r('app.color.ec_muted'))
      .width('100%')
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Column({ space: EcSpace.x1 }) {
          Text('👨‍👩‍👧 家庭成员')
            .fontSize(EcFont.h2)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
          Text('给家里人各建一个账号（不同英语水平）。登录名可以只写简称，会自动补 @family.local。')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.vm.showForm ? '收起' : '＋ 添加成员')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText('添加成员')
          .onClick(() => {
            this.vm.toggleForm();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  createForm() {
    Column({ space: EcSpace.x2 }) {
      this.fieldLabel('昵称')
      TextInput({ text: this.vm.displayName, placeholder: '比如：爸爸 / 奶奶' })
        .height(46)
        .fontSize(EcFont.body)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.displayName = value.length > 20 ? value.substring(0, 20) : value;
        })

      this.fieldLabel('登录名（可只写简称）')
      TextInput({ text: this.vm.login, placeholder: '比如：dad2' })
        .height(46)
        .fontSize(EcFont.body)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.login = value;
        })

      this.fieldLabel('初始密码（至少 8 位）')
      TextInput({ text: this.vm.password, placeholder: '至少 8 位' })
        .type(InputType.Password)
        .height(46)
        .fontSize(EcFont.body)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.password = value;
        })

      this.fieldLabel('角色')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.roleLabels, (label: string, index: number) => {
          this.smallChoice(label, this.vm.role === this.roleKeys[index], () => {
            this.vm.role = this.roleKeys[index];
          })
        }, (label: string, index: number) => 'role-' + index.toString() + '-' + this.vm.role)
      }
      .width('100%')

      this.fieldLabel('英语水平')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.cefrOptions, (level: string) => {
          this.smallChoice(level, this.vm.cefrLevel === level, () => {
            this.vm.cefrLevel = level;
          })
        }, (level: string) => 'cefr-' + level + '-' + this.vm.cefrLevel)
      }
      .width('100%')

      Row({ space: EcSpace.x2 }) {
        Text('每日时长（分钟）：' + this.vm.dailyLimit.toString())
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
      }
      .width('100%')
      Slider({ value: this.vm.dailyLimit, min: 5, max: 180, step: 5 })
        .width('100%')
        .selectedColor($r('app.color.ec_primary'))
        .onChange((value: number, mode: SliderChangeMode) => {
          this.vm.dailyLimit = Math.round(value);
        })

      Row({ space: EcSpace.x2 }) {
        Text('允许自由对话（不按剧本）')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.vm.allowFreeChat })
          .selectedColor($r('app.color.ec_primary'))
          .onChange((isOn: boolean) => {
            this.vm.allowFreeChat = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.formError.length > 0) {
        Text(this.vm.formError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }

      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: this.vm.creating ? '创建中…' : '创建账号',
          kind: EcButtonKind.PRIMARY,
          loading: this.vm.creating,
          btnWidth: '48%',
          onTap: () => {
            void this.vm.create();
          }
        })
        EcButton({
          label: '取消',
          kind: EcButtonKind.GHOST,
          btnWidth: '48%',
          onTap: () => {
            this.vm.toggleForm();
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .border({ width: 1, color: $r('app.color.ec_border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  editForm(member: FamilyMemberDto) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('编辑 ' + this.vm.memberTitle(member))
          .fontSize(EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Text('取消')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .onClick(() => {
            this.vm.cancelEdit();
          })
      }
      .width('100%')

      this.fieldLabel('昵称')
      TextInput({ text: this.vm.editDisplayName, placeholder: '昵称' })
        .height(44)
        .fontSize(EcFont.body)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.editDisplayName = value.length > 20 ? value.substring(0, 20) : value;
        })

      this.fieldLabel('英语水平')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.cefrOptions, (level: string) => {
          this.smallChoice(level, this.vm.editCefrLevel === level, () => {
            this.vm.editCefrLevel = level;
          })
        }, (level: string) => 'edit-cefr-' + level + '-' + this.vm.editCefrLevel)
      }
      .width('100%')

      Row({ space: EcSpace.x2 }) {
        Text('每日时长：' + this.vm.editDailyLimit.toString() + ' 分钟')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
      }
      Slider({ value: this.vm.editDailyLimit, min: 5, max: 180, step: 5 })
        .width('100%')
        .selectedColor($r('app.color.ec_primary'))
        .onChange((value: number, mode: SliderChangeMode) => {
          this.vm.editDailyLimit = Math.round(value);
        })

      Row({ space: EcSpace.x2 }) {
        Text('允许自由对话')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.vm.editAllowFreeChat })
          .selectedColor($r('app.color.ec_primary'))
          .onChange((isOn: boolean) => {
            this.vm.editAllowFreeChat = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.editError.length > 0) {
        Text(this.vm.editError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }

      EcButton({
        label: this.vm.savingEdit ? '保存中…' : '保存',
        kind: EcButtonKind.TONAL,
        loading: this.vm.savingEdit,
        onTap: () => {
          void this.vm.saveEdit();
        }
      })
    }
    .width('100%')
    .padding(EcSpace.x3)
    .backgroundColor($r('app.color.ec_surface_alt'))
    .borderRadius(EcRadius.md)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  resetForm(member: FamilyMemberDto) {
    Column({ space: EcSpace.x2 }) {
      Text('重置密码：' + this.vm.memberTitle(member))
        .fontSize(EcFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_warn_text'))
        .width('100%')
      TextInput({ text: this.vm.newPassword, placeholder: '新密码（至少 8 位）' })
        .type(InputType.Password)
        .height(44)
        .fontSize(EcFont.body)
        .backgroundColor($r('app.color.ec_surface'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.newPassword = value;
        })
      if (this.vm.resetError.length > 0) {
        Text(this.vm.resetError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: this.vm.resetting ? '重置中…' : '确认重置',
          kind: EcButtonKind.DANGER,
          loading: this.vm.resetting,
          btnWidth: '48%',
          onTap: () => {
            void this.vm.resetPassword();
          }
        })
        EcButton({
          label: '取消',
          kind: EcButtonKind.GHOST,
          btnWidth: '48%',
          onTap: () => {
            this.vm.cancelReset();
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x3)
    .backgroundColor($r('app.color.ec_warn_bg'))
    .borderRadius(EcRadius.md)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  memberRow(member: FamilyMemberDto) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Column({ space: EcSpace.x1 }) {
          Row({ space: EcSpace.x2 }) {
            Text(this.vm.memberTitle(member))
              .fontSize(EcFont.body)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ec_ink'))
            Chip({ text: this.vm.memberBadge(member), tone: 'muted' })
            if (member.id === this.session.userId) {
              Chip({ text: '你自己', tone: 'primary' })
            }
          }
          .alignItems(VerticalAlign.Center)
          Text(this.vm.memberSubText(member))
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
          Text('登录名：' + this.vm.memberEmail(member))
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: EcSpace.x2 }) {
          Text('编辑')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .onClick(() => {
              this.vm.beginEdit(member);
            })
          Text('重置密码')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_warn_text'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .onClick(() => {
              this.vm.beginReset(member);
            })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.vm.editingId === member.id) {
        this.editForm(member)
      }
      if (this.vm.resettingId === member.id) {
        this.resetForm(member)
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: EcSpace.x3 }) {
        this.headerCard()

        if (this.vm.notice.length > 0) {
          Text(this.vm.notice)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_good_text'))
            .width('100%')
            .padding(EcSpace.x3)
            .backgroundColor($r('app.color.ec_good_bg'))
            .borderRadius(EcRadius.md)
        }

        if (this.vm.hasError) {
          ErrorBanner({
            title: this.vm.error.title,
            message: this.vm.error.message,
            actionLabel: this.vm.error.retryable ? '重试' : '',
            onAction: () => {
              void this.vm.load();
            }
          })
        }

        if (this.vm.showForm) {
          this.createForm()
        }

        if (this.vm.loading && !this.vm.loadedOnce) {
          LoadingBlock({ text: '正在取家庭成员…' })
        } else if (this.vm.items.length === 0) {
          Text('还没有其他成员，点右上角「＋ 添加成员」建一个吧。')
            .fontSize(EcFont.body)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: EcSpace.x8, bottom: EcSpace.x8 })
        } else {
          ForEach(this.vm.items, (member: FamilyMemberDto) => {
            this.memberRow(member)
          }, (member: FamilyMemberDto) => member.id)
        }
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4, bottom: EcSpace.x8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .scrollBar(BarState.Off)
  }
}

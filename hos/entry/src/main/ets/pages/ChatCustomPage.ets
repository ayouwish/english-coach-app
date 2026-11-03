import { EcButton, EcButtonKind } from '../components/EcButton';
import { TopBar } from '../components/EcBlocks';
import { ErrorBanner } from '../components/ErrorBanner';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { ChatNav, ChatScenarioDto } from '../core/net/ChatDtos';
import { ChatService } from '../core/service/ChatService';
import { NavigationService } from '../core/router/NavigationService';
import { SessionState, SessionStore } from '../core/session/SessionStore';

/**
 * 自定义场景（创建 / 编辑 / 删除，§2.3）。
 *
 * 校验文案照抄服务端逐字段口径：
 * 「英文标题需为 1–40 个字符」「角色设定需为 20–1500 个字符」「开场白需为 5–200 个字符」。
 * 注入词拦截（400）由服务端返回，整页顶部展示 message；儿童强制 audience=child。
 */
@Component
export struct ChatCustomPage {
  @StorageLink('session') session: SessionState = new SessionState();

  @State isEdit: boolean = false;
  @State editId: string = '';
  @State title: string = '';
  @State titleZh: string = '';
  @State settingZh: string = '';
  @State rolePrompt: string = '';
  @State openingLine: string = '';
  @State level: string = 'A2';
  @State audience: string = 'adult';
  @State busy: boolean = false;
  @State errorMessage: string = '';
  @State confirmDelete: boolean = false;

  @State titleError: string = '';
  @State titleZhError: string = '';
  @State settingZhError: string = '';
  @State rolePromptError: string = '';
  @State openingLineError: string = '';

  private levels: string[] = ['A1', 'A2', 'B1', 'B2', 'C1'];
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    const edit: ChatScenarioDto | null = ChatNav.editScenario;
    if (edit !== null) {
      this.isEdit = true;
      this.editId = edit.id;
      this.title = typeof edit.title === 'string' ? edit.title : '';
      this.titleZh = typeof edit.title_zh === 'string' ? edit.title_zh : '';
      this.settingZh = typeof edit.setting_zh === 'string' ? edit.setting_zh : '';
      this.openingLine = typeof edit.opening_line === 'string' ? edit.opening_line : '';
      this.level = (typeof edit.level === 'string' && edit.level.length > 0) ? edit.level : 'A2';
      this.audience = edit.audience === 'child' ? 'child' : 'adult';
      // 列表接口不返回 role_prompt：留空 = 服务端保持原值
      this.rolePrompt = '';
    } else {
      this.isEdit = false;
      this.editId = '';
      this.level = this.defaultLevel();
      this.audience = this.session.isChild ? 'child' : 'adult';
    }
  }

  private defaultLevel(): string {
    const cefr = this.session.cefrLevel.trim().toUpperCase();
    if (cefr === 'A1' || cefr === 'A2' || cefr === 'B1' || cefr === 'B2' || cefr === 'C1') {
      return cefr === 'B2' && !this.session.isChild ? 'B1' : cefr;
    }
    return 'A2';
  }

  private bumpScenariosRev(): void {
    const current = AppStorage.get<number>('chat_scenarios_rev');
    const next = (current === undefined ? 0 : current) + 1;
    AppStorage.setOrCreate<number>('chat_scenarios_rev', next);
  }

  private validate(): boolean {
    this.titleError = '';
    this.titleZhError = '';
    this.settingZhError = '';
    this.rolePromptError = '';
    this.openingLineError = '';
    let ok = true;

    const title = this.title.trim();
    if (title.length < 1 || title.length > 40) {
      this.titleError = '英文标题需为 1–40 个字符';
      ok = false;
    }
    const titleZh = this.titleZh.trim();
    if (titleZh.length < 1 || titleZh.length > 40) {
      this.titleZhError = '中文标题需为 1–40 个字符';
      ok = false;
    }
    const setting = this.settingZh.trim();
    if (setting.length < 1 || setting.length > 200) {
      this.settingZhError = '场景说明需为 1–200 个字符';
      ok = false;
    }
    // 编辑时留空 = 不修改角色设定（列表接口不返回 role_prompt）
    if (!this.isEdit || this.rolePrompt.trim().length > 0) {
      const role = this.rolePrompt.trim();
      if (role.length < 20 || role.length > 1500) {
        this.rolePromptError = '角色设定需为 20–1500 个字符';
        ok = false;
      }
    }
    const opening = this.openingLine.trim();
    if (opening.length < 5 || opening.length > 200) {
      this.openingLineError = '开场白需为 5–200 个字符';
      ok = false;
    }
    return ok;
  }

  private async save(): Promise<void> {
    if (this.busy || !this.validate()) {
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    try {
      const title = this.title.trim();
      const titleZh = this.titleZh.trim();
      const setting = this.settingZh.trim();
      const role = this.rolePrompt.trim();
      const opening = this.openingLine.trim();
      if (this.isEdit) {
        await ChatService.updateScenario(this.editId, title, titleZh, setting, role, opening, this.level);
      } else {
        const audience = this.session.isChild ? 'child' : this.audience;
        await ChatService.createScenario(title, titleZh, setting, role, opening, this.level, audience);
      }
      this.bumpScenariosRev();
      this.busy = false;
      NavigationService.pop();
    } catch (err) {
      this.busy = false;
      this.errorMessage = SessionStore.toUiError(err as Error, this.session.isChild).message;
    }
  }

  private async remove(): Promise<void> {
    if (this.busy || this.editId.length === 0) {
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    try {
      await ChatService.deleteScenario(this.editId);
      this.bumpScenariosRev();
      this.busy = false;
      NavigationService.pop();
    } catch (err) {
      this.busy = false;
      this.errorMessage = SessionStore.toUiError(err as Error, this.session.isChild).message;
    }
  }

  // ------------------------------------------------------------------ 小构件

  @Builder
  fieldLabel(text: string, hint: string) {
    Row({ space: EcSpace.x2 }) {
      Text(text)
        .fontSize(EcFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
      if (hint.length > 0) {
        Text(hint)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  fieldError(message: string) {
    if (message.length > 0) {
      Text(message)
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_bad_text'))
        .width('100%')
    }
  }

  @Builder
  formCard() {
    Column({ space: EcSpace.x3 }) {
      Column({ space: EcSpace.x1 }) {
        this.fieldLabel('英文标题', '1–40 个字符')
        TextInput({ text: this.title, placeholder: '例如 My weekend plan' })
          .fontSize(EcFont.body)
          .height(44)
          .padding({ left: EcSpace.x3, right: EcSpace.x3 })
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .maxLength(40)
          .onChange((value: string) => {
            this.title = value;
          })
        this.fieldError(this.titleError)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: EcSpace.x1 }) {
        this.fieldLabel('中文标题', '1–40 个字符')
        TextInput({ text: this.titleZh, placeholder: '例如 我的周末计划' })
          .fontSize(EcFont.body)
          .height(44)
          .padding({ left: EcSpace.x3, right: EcSpace.x3 })
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .maxLength(40)
          .onChange((value: string) => {
            this.titleZh = value;
          })
        this.fieldError(this.titleZhError)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: EcSpace.x1 }) {
        this.fieldLabel('场景说明', '1–200 个字符，中文')
        TextArea({ text: this.settingZh, placeholder: '例如 你和朋友在聊周末安排' })
          .fontSize(EcFont.caption)
          .height(72)
          .padding(EcSpace.x3)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .maxLength(200)
          .onChange((value: string) => {
            this.settingZh = value;
          })
        this.fieldError(this.settingZhError)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: EcSpace.x1 }) {
        this.fieldLabel('角色设定', this.isEdit ? '留空 = 不修改（20–1500 个字符）' : '20–1500 个字符，英文')
        TextArea({
          text: this.rolePrompt,
          placeholder: 'You are a friendly friend. Keep each reply under 15 words. Ask one question at a time.'
        })
          .fontSize(EcFont.caption)
          .height(96)
          .padding(EcSpace.x3)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .maxLength(1500)
          .onChange((value: string) => {
            this.rolePrompt = value;
          })
        this.fieldError(this.rolePromptError)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: EcSpace.x1 }) {
        this.fieldLabel('开场白', '5–200 个字符，英文')
        TextArea({ text: this.openingLine, placeholder: 'Hey! Any plans for the weekend?' })
          .fontSize(EcFont.caption)
          .height(64)
          .padding(EcSpace.x3)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .maxLength(200)
          .onChange((value: string) => {
            this.openingLine = value;
          })
        this.fieldError(this.openingLineError)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: EcSpace.x1 }) {
        this.fieldLabel('难度', '')
        Row({ space: EcSpace.x2 }) {
          ForEach(this.levels, (item: string) => {
            Text(item)
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.level === item ? Color.White : $r('app.color.ec_muted'))
              .backgroundColor(this.level === item ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x1, bottom: EcSpace.x1 })
              .borderRadius(EcRadius.pill)
              .accessibilityText('难度 ' + item)
              .onClick(() => {
                this.level = item;
              })
          }, (item: string) => 'lv_' + item)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: EcSpace.x1 }) {
        this.fieldLabel('场景类型', '')
        if (this.session.isChild) {
          Text('小朋友场景（儿童账号只能创建「小朋友」场景）')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .width('100%')
        } else {
          Row({ space: EcSpace.x2 }) {
            Text('成人场景')
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.audience === 'adult' ? Color.White : $r('app.color.ec_muted'))
              .backgroundColor(this.audience === 'adult' ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x1, bottom: EcSpace.x1 })
              .borderRadius(EcRadius.pill)
              .accessibilityText('创建成人场景')
              .onClick(() => {
                this.audience = 'adult';
              })
            Text('小朋友的场景')
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.audience === 'child' ? Color.White : $r('app.color.ec_muted'))
              .backgroundColor(this.audience === 'child' ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x1, bottom: EcSpace.x1 })
              .borderRadius(EcRadius.pill)
              .accessibilityText('创建小朋友的场景')
              .onClick(() => {
                this.audience = 'child';
              })
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buttons() {
    Column({ space: EcSpace.x2 }) {
      EcButton({
        label: this.isEdit ? '保存修改' : '保存场景',
        kind: EcButtonKind.PRIMARY,
        big: this.session.isChild,
        loading: this.busy,
        onTap: () => {
          void this.save();
        }
      })
      EcButton({
        label: '取消',
        kind: EcButtonKind.GHOST,
        disabled: this.busy,
        onTap: () => {
          NavigationService.pop();
        }
      })
      if (this.isEdit) {
        if (this.confirmDelete) {
          Column({ space: EcSpace.x1 }) {
            Text('删除后就找不回来了，确定吗？')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_bad_text'))
              .width('100%')
            Row({ space: EcSpace.x2 }) {
              EcButton({
                label: '确认删除',
                kind: EcButtonKind.DANGER,
                btnWidth: '52%',
                disabled: this.busy,
                onTap: () => {
                  void this.remove();
                }
              })
              EcButton({
                label: '先不删',
                kind: EcButtonKind.GHOST,
                btnWidth: '44%',
                onTap: () => {
                  this.confirmDelete = false;
                }
              })
            }
            .width('100%')
          }
          .width('100%')
          .padding(EcSpace.x3)
          .backgroundColor($r('app.color.ec_bad_bg'))
          .borderRadius(EcRadius.md)
          .alignItems(HorizontalAlign.Start)
        } else {
          Text('删除这个场景')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_bad_text'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(EcSpace.x2)
            .accessibilityText('删除这个场景')
            .onClick(() => {
              this.confirmDelete = true;
            })
        }
      }
    }
    .width('100%')
  }

  build() {
    Column({ space: EcSpace.x2 }) {
      TopBar({
        title: this.isEdit ? '编辑自定义场景' : '自定义场景',
        onBack: () => {
          NavigationService.pop();
        }
      })

      Scroll() {
        Column({ space: EcSpace.x3 }) {
          Text(this.isEdit
            ? '改完点「保存修改」；角色设定留空则保持原来的设定。'
            : '写一个你想练的场景：角色设定和开场白都用英文，说出你自己的话。')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')

          if (this.errorMessage.length > 0) {
            ErrorBanner({ message: this.errorMessage })
          }

          this.formCard()
          this.buttons()
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x8 })
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

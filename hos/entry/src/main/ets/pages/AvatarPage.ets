import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { AvatarPresetCharacterDto, AvatarStyleDto } from '../core/net/AccountDtos';
import { SessionState } from '../core/session/SessionStore';
import { AvatarVM } from '../viewmodel/AccountVM';

/**
 * 我的虚拟形象（`/api/avatar/presets` + GET/POST/PATCH/DELETE `/api/avatar`）。
 *
 * 硬性约束（chat-story §4.7）：**不出现任何「拍照/上传」按钮**；照片路径已按隐私策略关闭
 * （403 policy_disabled），只做预置形象选择题。预置图是站内静态路径，需拼 baseUrl 且无需鉴权。
 */
@Component
export struct AvatarPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: AvatarVM = new AvatarVM();
  @State selectedCharacterId: string = '';
  @State showAllGender: boolean = false;
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init(this.session.isChild);
    this.showAllGender = false;
  }

  private styleFg(styleId: string): ResourceColor {
    return this.vm.selectedStyle === styleId ? Color.White : $r('app.color.ec_muted');
  }

  private styleBg(styleId: string): ResourceColor {
    return this.vm.selectedStyle === styleId
      ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt');
  }

  private audienceFg(audience: string): ResourceColor {
    return this.vm.audience === audience ? Color.White : $r('app.color.ec_muted');
  }

  private audienceBg(audience: string): ResourceColor {
    return this.vm.audience === audience
      ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt');
  }

  private isSelected(characterId: string): boolean {
    return this.selectedCharacterId === characterId;
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Text('🎨 我的虚拟形象')
        .fontSize(EcFont.h2)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      Row({ space: EcSpace.x2 }) {
        Text('🛡️')
          .fontSize(EcFont.body)
        Text('不用上传照片，选一个就好')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.vm.placeholder) {
        Text('预览图（未生成真实插画）：当前展示的是占位图，真实插画生成后会替换。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
          .padding(EcSpace.x2)
          .backgroundColor($r('app.color.ec_warn_bg'))
          .borderRadius(EcRadius.sm)
      }
      if (this.vm.notice.length > 0) {
        Text(this.vm.notice)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  currentCard() {
    Column({ space: EcSpace.x2 }) {
      Text('当前形象')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      if (this.vm.hasAvatar() && this.vm.currentImageUrl().length > 0) {
        Stack() {
          Text('🙂').fontSize(40)
          Image(this.vm.currentImageUrl())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
        .width(120)
        .height(120)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .clip(true)
      } else if (this.vm.hasAvatar()) {
        Text('当前形象已设置，但图片按隐私策略不可在此展示。')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      if (this.vm.currentStyleLabel().length > 0) {
        Row({ space: EcSpace.x2 }) {
          Chip({ text: '风格：' + this.vm.currentStyleLabel(), tone: 'primary' })
          if (this.vm.currentPresetId().length > 0) {
            Chip({ text: '预置 ' + this.vm.currentPresetId(), tone: 'muted' })
          }
        }
        .alignItems(VerticalAlign.Center)
      }

      if (this.vm.currentDesc().length > 0) {
        Text('形象描述：' + this.vm.currentDesc())
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      if (this.vm.hasAvatar()) {
        Text('把描述改成更像我的')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
        TextArea({ text: this.vm.descDraft, placeholder: '例如：a girl with glasses and a red hoodie' })
          .width('100%')
          .height(88)
          .fontSize(EcFont.caption)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .maxLength(500)
          .onChange((value: string) => {
            this.vm.descDraft = value;
          })
        Row({ space: EcSpace.x2 }) {
          Text(this.vm.descDraft.length.toString() + ' / 500')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .layoutWeight(1)
        }
        Row({ space: EcSpace.x2 }) {
          EcButton({
            label: this.vm.savingDesc ? '保存中…' : '保存描述',
            kind: EcButtonKind.TONAL,
            loading: this.vm.savingDesc,
            btnWidth: '48%',
            onTap: () => {
              void this.vm.saveDescription();
            }
          })
          EcButton({
            label: this.vm.saving ? '清空中…' : '清空',
            kind: EcButtonKind.DANGER,
            loading: this.vm.saving,
            btnWidth: '48%',
            onTap: () => {
              void this.vm.clear();
            }
          })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  characterCard(character: AvatarPresetCharacterDto) {
    Column({ space: EcSpace.x1 }) {
      Stack() {
        Text('🙂').fontSize(30)
        Image(this.vm.imageOf(character))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
      .width('100%')
      .aspectRatio(1)
      .backgroundColor($r('app.color.ec_surface_alt'))
      .borderRadius(EcRadius.md)
      .clip(true)
      .border({
        width: this.isSelected(character.id) ? 3 : 0,
        color: $r('app.color.ec_primary')
      })

      Text(character.label_zh === undefined ? character.id : character.label_zh)
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_ink'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('48%')
    .padding(4)
    .margin({ bottom: EcSpace.x2 })
    .borderRadius(EcRadius.md)
    .accessibilityText(character.label_zh === undefined ? character.id : character.label_zh)
    .onClick(() => {
      this.selectedCharacterId = character.id;
    })
  }

  @Builder
  selectorCard() {
    Column({ space: EcSpace.x2 }) {
      Text('第 1 步：选风格')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.vm.styles, (style: AvatarStyleDto) => {
          Text(style.label_zh === undefined ? style.id : style.label_zh)
            .fontSize(EcFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.styleFg(style.id))
            .backgroundColor(this.styleBg(style.id))
            .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
            .borderRadius(EcRadius.pill)
            .margin({ right: EcSpace.x2, bottom: EcSpace.x2 })
            .accessibilityText(style.label_zh)
            .onClick(() => {
              this.vm.selectedStyle = style.id;
            })
        }, (style: AvatarStyleDto) => 'style-' + style.id)
      }
      .width('100%')

      if (this.vm.myGender.length > 0) {
        Row({ space: EcSpace.x2 }) {
          Text('按我的性别显示')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showAllGender })
            .selectedColor($r('app.color.ec_primary'))
            .onChange((isOn: boolean) => {
              this.showAllGender = isOn;
              this.vm.showAllGender = isOn;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text('打开后显示全部形象（默认按性别筛选，可随时切换）。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      Text('第 2 步：选角色')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      Row({ space: EcSpace.x2 }) {
        Text('🧒 给小朋友的（' + this.vm.childCount().toString() + '）')
          .fontSize(EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.audienceFg('child'))
          .backgroundColor(this.audienceBg('child'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
          .borderRadius(EcRadius.pill)
          .onClick(() => {
            this.vm.audience = 'child';
          })
        Text('🧑 给爸爸妈妈的（' + this.vm.adultCount().toString() + '）')
          .fontSize(EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.audienceFg('adult'))
          .backgroundColor(this.audienceBg('adult'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
          .borderRadius(EcRadius.pill)
          .onClick(() => {
            this.vm.audience = 'adult';
          })
      }
      .width('100%')

      if (this.vm.visibleCharacters().length === 0) {
        Text('这个分类下暂时没有可选形象。')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.vm.visibleCharacters(), (character: AvatarPresetCharacterDto) => {
            this.characterCard(character)
          }, (character: AvatarPresetCharacterDto) => 'char-' + character.id)
        }
        .width('100%')
      }

      EcButton({
        label: this.vm.saving ? '保存中…' : '就用这个',
        kind: EcButtonKind.PRIMARY,
        big: this.session.isChild,
        disabled: this.selectedCharacterId.length === 0,
        loading: this.vm.saving,
        onTap: () => {
          if (this.selectedCharacterId.length > 0) {
            void this.vm.selectPreset(this.selectedCharacterId);
          }
        }
      })
      Text('点一下立即生效，不需要等待生成。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
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

        if (this.vm.loading && !this.vm.loadedOnce) {
          LoadingBlock({ text: '正在取预置形象库…' })
        } else {
          if (this.vm.hasAvatar()) {
            this.currentCard()
          }
          this.selectorCard()
        }

        Column()
          .height(EcSpace.x8)
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .scrollBar(BarState.Off)
  }
}

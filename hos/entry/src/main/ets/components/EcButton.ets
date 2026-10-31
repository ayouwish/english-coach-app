import { EcButtonSize, EcFont, EcRadius, EcSpace } from '../design/DesignTokens';

/** 按钮层级（docs/design-system.md §4）：一屏最多一个 Primary 实心按钮。 */
export enum EcButtonKind {
  PRIMARY = 0,
  TONAL = 1,
  GHOST = 2,
  DANGER = 3,
  TEXT = 4
}

/**
 * 统一按钮：loading / disabled / 尺寸 / 圆角都在这里，页面不再写按钮样式。
 *
 * 尺寸：md = 48vp（默认）、big = 60vp（主 CTA / 儿童）、圆角 14vp（docs 真实值）。
 * 无障碍：最小点击区 48vp；文字 + 背景双通道表达状态。
 */
@Component
export struct EcButton {
  @Prop label: string = '';
  @Prop kind: EcButtonKind = EcButtonKind.PRIMARY;
  @Prop loading: boolean = false;
  @Prop disabled: boolean = false;
  /** 主 CTA / 儿童：60vp 高、19fp 字 */
  @Prop big: boolean = false;
  /** 宽度用带单位的字符串（'100%' / '48%' / '168vp'）；普通成员，不需要响应式 */
  btnWidth: string = '100%';
  onTap: () => void = () => {
  };

  private buttonHeight(): number {
    return this.big ? EcButtonSize.child : EcButtonSize.md;
  }

  private bgColor(): ResourceColor {
    if (this.kind === EcButtonKind.PRIMARY) {
      return $r('app.color.ec_primary');
    }
    if (this.kind === EcButtonKind.TONAL) {
      return $r('app.color.ec_primary_soft');
    }
    if (this.kind === EcButtonKind.GHOST) {
      return $r('app.color.ec_surface');
    }
    if (this.kind === EcButtonKind.DANGER) {
      return $r('app.color.ec_bad_bg');
    }
    return Color.Transparent;
  }

  private fgColor(): ResourceColor {
    if (this.kind === EcButtonKind.PRIMARY) {
      return Color.White;
    }
    if (this.kind === EcButtonKind.DANGER) {
      return $r('app.color.ec_bad_text');
    }
    if (this.kind === EcButtonKind.GHOST) {
      return $r('app.color.ec_ink');
    }
    return $r('app.color.ec_primary');
  }

  private borderWidth(): number {
    return this.kind === EcButtonKind.GHOST ? 1 : 0;
  }

  build() {
    Row({ space: EcSpace.x2 }) {
      if (this.loading) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.fgColor())
      }
      Text(this.label)
        .fontSize(this.big ? EcFont.childButton : EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.fgColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .justifyContent(FlexAlign.Center)
    .width(this.btnWidth)
    .height(this.buttonHeight())
    .padding({ left: EcSpace.x4, right: EcSpace.x4 })
    .backgroundColor(this.bgColor())
    .borderRadius(this.big ? EcRadius.lg : EcRadius.md)
    .border({ width: this.borderWidth(), color: $r('app.color.ec_border') })
    .opacity((this.disabled || this.loading) ? 0.45 : 1)
    .enabled(!(this.disabled || this.loading))
    .accessibilityText(this.label)
    .onClick(() => {
      if (this.disabled || this.loading) {
        return;
      }
      this.onTap();
    })
  }
}

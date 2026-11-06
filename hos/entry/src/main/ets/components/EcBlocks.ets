import { EcFont, EcRadius, EcSpace } from '../design/DesignTokens';

/** 通用分区卡片：白底 + 圆角 + 可选标题。页面不再各自拼卡片样式。 */
@Component
export struct SectionCard {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    Column({ space: EcSpace.x2 }) {
      if (this.title.length > 0) {
        Row({ space: EcSpace.x2 }) {
          Text(this.title)
            .fontSize(EcFont.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_ink'))
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_muted'))
          }
        }
        .width('100%')
      }
      this.content()
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }
}

/** 小标签（等级、音素、状态）。 */
@Component
export struct Chip {
  @Prop text: string = '';
  @Prop tone: string = 'muted';
  @Prop small: boolean = true;

  private bg(): ResourceColor {
    if (this.tone === 'primary') {
      return $r('app.color.ec_primary_soft');
    }
    if (this.tone === 'good') {
      return $r('app.color.ec_good_bg');
    }
    if (this.tone === 'warn') {
      return $r('app.color.ec_warn_bg');
    }
    if (this.tone === 'bad') {
      return $r('app.color.ec_bad_bg');
    }
    return $r('app.color.ec_surface_alt');
  }

  private fg(): ResourceColor {
    if (this.tone === 'primary') {
      return $r('app.color.ec_primary');
    }
    if (this.tone === 'good') {
      return $r('app.color.ec_good_text');
    }
    if (this.tone === 'warn') {
      return $r('app.color.ec_warn_text');
    }
    if (this.tone === 'bad') {
      return $r('app.color.ec_bad_text');
    }
    return $r('app.color.ec_muted');
  }

  build() {
    Text(this.text)
      .fontSize(this.small ? EcFont.micro : EcFont.caption)
      .fontColor(this.fg())
      .backgroundColor(this.bg())
      .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 2, bottom: 2 })
      .borderRadius(EcRadius.sm)
  }
}

/** 简单页头：返回 + 标题 + 右侧动作（动作文字可为空）。 */
@Component
export struct TopBar {
  @Prop title: string = '';
  @Prop actionLabel: string = '';
  onBack: () => void = () => {
  };
  onAction: () => void = () => {
  };

  build() {
    Row({ space: EcSpace.x2 }) {
      Text('‹')
        .fontSize(30)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .accessibilityText('返回')
        .onClick(() => {
          this.onBack();
        })
      Text(this.title)
        .fontSize(EcFont.h3)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.actionLabel.length > 0) {
        Text(this.actionLabel)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText(this.actionLabel)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: EcSpace.x2, right: EcSpace.x4 })
    .alignItems(VerticalAlign.Center)
  }
}

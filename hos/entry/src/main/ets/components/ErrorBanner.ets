import { EcFont, EcRadius, EcSpace } from '../design/DesignTokens';

/**
 * 页内错误条：浅红底 + 标题 + 可执行动作（重试/去设置）。
 * 不用全屏 Dialog（docs/architecture.md §6.3）：错误要「可见 + 可操作」，不遮挡主内容。
 */
@Component
export struct ErrorBanner {
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop actionLabel: string = '';
  onAction: () => void = () => {
  };

  build() {
    Column() {
      if (this.message.length > 0) {
        Row({ space: EcSpace.x2 }) {
          Text('!')
            .fontSize(EcFont.body)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_bad_text'))
          Column({ space: EcSpace.x1 }) {
            if (this.title.length > 0) {
              Text(this.title)
                .fontSize(EcFont.body)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ec_bad_text'))
                .width('100%')
            }
            Text(this.message)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_bad_text'))
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.actionLabel.length > 0) {
            Text(this.actionLabel)
              .fontSize(EcFont.caption)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ec_primary'))
              .padding({ left: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
              .accessibilityText(this.actionLabel)
              .onClick(() => {
                this.onAction();
              })
          }
        }
        .width('100%')
        .padding(EcSpace.x3)
        .backgroundColor($r('app.color.ec_bad_bg'))
        .borderRadius(EcRadius.md)
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
  }
}

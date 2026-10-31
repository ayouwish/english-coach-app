import { EcFont, EcSpace } from '../design/DesignTokens';

/** 加载态：小 spinner + 一句进度文案（不用全屏 blank / 假百分比）。 */
@Component
export struct LoadingBlock {
  @Prop text: string = '加载中…';
  @Prop subText: string = '';

  build() {
    Column({ space: EcSpace.x2 }) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color($r('app.color.ec_primary'))
      Text(this.text)
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_muted'))
      if (this.subText.length > 0) {
        Text(this.subText)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
      }
    }
    .width('100%')
    .padding({ top: EcSpace.x10, bottom: EcSpace.x10 })
    .alignItems(HorizontalAlign.Center)
  }
}

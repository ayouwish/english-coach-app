import { EcButton, EcButtonKind } from './EcButton';
import { EcFont, EcSpace } from '../design/DesignTokens';

/** 空态：图标 + 一句人话 + 一个可执行动作（docs/screens.md 全局规则）。 */
@Component
export struct EmptyState {
  @Prop icon: string = '🌱';
  @Prop message: string = '';
  @Prop actionLabel: string = '';
  onAction: () => void = () => {
  };

  build() {
    Column({ space: EcSpace.x3 }) {
      Text(this.icon)
        .fontSize(40)
      Text(this.message)
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_muted'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.actionLabel.length > 0) {
        EcButton({
          label: this.actionLabel,
          kind: EcButtonKind.TONAL,
          btnWidth: '168vp',
          onTap: () => {
            this.onAction();
          }
        })
      }
    }
    .width('100%')
    .padding({ top: EcSpace.x10, bottom: EcSpace.x10, left: EcSpace.x4, right: EcSpace.x4 })
    .alignItems(HorizontalAlign.Center)
  }
}

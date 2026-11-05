/**
 * 左划露出「删除」按钮的行容器。
 *
 * 用法：
 * ```
 * SwipeDeleteRow({ onDelete: () => this.confirmDelete(item) }) {
 *   this.storyRow(item)
 * }
 * ```
 *
 * 交互对齐 Web（ec16140）：
 * - 横向拖动超过 1/3 按钮宽度吸附打开；否则回弹；
 * - 打开状态点内容区先收起（不直接进详情）；
 * - 删除按钮点击由页面做二次确认，确认后页面移除数据，行随之销毁。
 */
@Component
export struct SwipeDeleteRow {
  /** 删除按钮宽度（vp） */
  @Prop buttonWidth: number = 92;
  /** 行标识（页面可用来只允许一行打开；当前实现不强依赖） */
  @Prop rowKey: string = '';
  onDelete: () => void = () => {
  };
  @BuilderParam content: () => void = this.emptyContent;
  @State offsetX: number = 0;
  private startOffset: number = 0;

  @Builder
  emptyContent() {
  }

  private close(): void {
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.offsetX = 0;
    });
  }

  private open(): void {
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.offsetX = -this.buttonWidth;
    });
  }

  build() {
    Stack({ alignContent: Alignment.End }) {
      Row() {
        Text('删除')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .width(this.buttonWidth)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.ec_bad'))
      .onClick(() => {
        this.onDelete();
      })

      Column() {
        this.content()
      }
      .width('100%')
      .translate({ x: this.offsetX })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 6 })
          .onActionStart(() => {
            this.startOffset = this.offsetX;
          })
          .onActionUpdate((event: GestureEvent) => {
            let next = this.startOffset + event.offsetX;
            if (next > 0) {
              next = 0;
            }
            const maxOpen = -this.buttonWidth * 1.5;
            if (next < maxOpen) {
              next = maxOpen;
            }
            this.offsetX = next;
          })
          .onActionEnd(() => {
            if (this.offsetX < -this.buttonWidth / 3) {
              this.open();
            } else {
              this.close();
            }
          })
      )
      .onClick(() => {
        // 打开时点内容区先收起，避免误进详情
        if (this.offsetX < 0) {
          this.close();
        }
      })
    }
    .width('100%')
    .clip(true)
  }
}

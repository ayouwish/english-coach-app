import { EcFont, EcScore } from '../design/DesignTokens';

/** 分数圆环：Progress(Ring) + 中间数字/星星；儿童 <60 不显示数字。 */
@Component
export struct ScoreRing {
  @Prop score: number = 0;
  @Prop label: string = '总分';
  @Prop isChild: boolean = false;
  @Prop ringSize: number = 96;

  private ringColor(): ResourceColor {
    return EcScore.colorByMode(this.score, this.isChild);
  }

  build() {
    Stack() {
      Progress({ value: this.score, total: 100, type: ProgressType.Ring })
        .width(this.ringSize)
        .height(this.ringSize)
        .color(this.ringColor())
        .backgroundColor($r('app.color.ec_surface_alt'))
        .style({ strokeWidth: 9 })
      Column({ space: 0 }) {
        Text(this.isChild && this.score < 60 ? '🌱' : EcScore.numberText(this.score))
          .fontSize(this.isChild ? EcFont.h2 : EcFont.h1)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.ringColor())
        Text(this.label)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.ringSize)
    .height(this.ringSize)
  }
}

/** 横向子项分数条（准确/流利/完整/语调），null 显示 — 且不落 0。 */
@Component
export struct SubScoreBar {
  @Prop label: string = '';
  @Prop score: number = -1;
  @Prop isChild: boolean = false;

  private valid(): boolean {
    return this.score >= 0;
  }

  private color(): ResourceColor {
    return EcScore.colorByMode(this.score, this.isChild);
  }

  build() {
    Row({ space: 8 }) {
      Text(this.label)
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width(52)
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(8)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(4)
        if (this.valid()) {
          Row()
            .width(this.score.toString() + '%')
            .height(8)
            .backgroundColor(this.color())
            .borderRadius(4)
        }
      }
      .layoutWeight(1)
      .height(8)
      Text(this.valid() ? EcScore.numberText(this.score) : '—')
        .fontSize(EcFont.caption)
        .fontColor(this.valid() ? this.color() : $r('app.color.ec_muted'))
        .width(32)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(24)
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 语调曲线（简化版）：把 F0 序列降采样成竖条，用户蓝 / 示范灰并排。
 * 只用布局组件，避免 Canvas 重绘与大量孤立 API。
 */
@Component
export struct F0Bars {
  /** 每项 = [time_ms, f0|null] */
  @Prop user: Array<Array<number | null>> = [];
  @Prop reference: Array<Array<number | null>> = [];
  @Prop barCount: number = 60;

  private sampleValues(source: Array<Array<number | null>>): number[] {
    const values: number[] = [];
    if (source.length === 0) {
      return values;
    }
    const step = Math.max(1, Math.floor(source.length / this.barCount));
    let max = 0;
    for (let i = 0; i < source.length; i += step) {
      const point = source[i];
      const value = point.length > 1 ? point[1] : null;
      const hz = (value === null || value === undefined) ? 0 : value as number;
      values.push(hz);
      if (hz > max) {
        max = hz;
      }
    }
    const normalized: number[] = [];
    for (let i = 0; i < values.length; i++) {
      normalized.push(max > 0 ? values[i] / max : 0);
    }
    return normalized;
  }

  private barHeight(ratio: number): number {
    const h = Math.round(ratio * 56);
    return h < 2 ? 2 : h;
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 1 }) {
        ForEach(this.sampleValues(this.reference), (ratio: number, index: number) => {
          Column()
            .width(3)
            .height(this.barHeight(ratio))
            .backgroundColor($r('app.color.ec_border'))
            .borderRadius(2)
            .alignSelf(ItemAlign.End)
        }, (ratio: number, index: number) => 'ref' + index.toString())
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Bottom)
      Row({ space: 1 }) {
        ForEach(this.sampleValues(this.user), (ratio: number, index: number) => {
          Column()
            .width(3)
            .height(this.barHeight(ratio))
            .backgroundColor($r('app.color.ec_primary'))
            .borderRadius(2)
            .alignSelf(ItemAlign.End)
        }, (ratio: number, index: number) => 'user' + index.toString())
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Bottom)
      Row({ space: 8 }) {
        Text('蓝：你')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_primary'))
        Text('灰：示范')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
      }
      .width('100%')
    }
    .width('100%')
  }
}

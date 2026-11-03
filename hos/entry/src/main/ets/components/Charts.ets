import { EcFont, EcScore } from '../design/DesignTokens';

/**
 * 结果详情用的三个纯图形组件（不引第三方库）：
 * - RadarChart：能力多边形（4 轴；null 轴不参与多边形，标 —）
 * - PitchChart：F0 双曲线（用户实线 / 示范虚线）
 * - SparkLine：历次总分走势
 *
 * 坐标用 vp 计算，宽度通过 onAreaChange 获取，避免写死屏幕宽度。
 */

function fmt(v: number): string {
  return (Math.round(v * 10) / 10).toString();
}

@Component
export struct RadarChart {
  @Prop accuracy: number = -1;
  @Prop fluency: number = -1;
  @Prop completeness: number = -1;
  @Prop prosody: number = -1;
  @Prop isChild: boolean = false;
  @Prop chartSize: number = 260;

  private labels: string[] = ['准确', '流利', '完整', '节奏'];
  private childLabels: string[] = ['说得准', '说得顺', '没漏词', '节奏'];

  private scoreOf(index: number): number {
    if (index === 0) {
      return this.accuracy;
    }
    if (index === 1) {
      return this.fluency;
    }
    if (index === 2) {
      return this.completeness;
    }
    return this.prosody;
  }

  private cx(): number {
    return this.chartSize / 2;
  }

  private cy(): number {
    return this.chartSize / 2;
  }

  private maxR(): number {
    return this.chartSize * 0.30;
  }

  private px(index: number, radius: number): number {
    const angle = (-90 + index * 90) * Math.PI / 180;
    return this.cx() + Math.cos(angle) * radius;
  }

  private py(index: number, radius: number): number {
    const angle = (-90 + index * 90) * Math.PI / 180;
    return this.cy() + Math.sin(angle) * radius;
  }

  private ringCommands(ratio: number): string {
    const radius = this.maxR() * ratio;
    let cmd = 'M ' + fmt(this.px(0, radius)) + ' ' + fmt(this.py(0, radius));
    for (let i = 1; i < 4; i++) {
      cmd = cmd + ' L ' + fmt(this.px(i, radius)) + ' ' + fmt(this.py(i, radius));
    }
    return cmd + ' Z';
  }

  private axisCommands(index: number): string {
    return 'M ' + fmt(this.cx()) + ' ' + fmt(this.cy()) + ' L ' +
      fmt(this.px(index, this.maxR())) + ' ' + fmt(this.py(index, this.maxR()));
  }

  private hasValue(index: number): boolean {
    return this.scoreOf(index) >= 0;
  }

  private scoreCommands(): string {
    let count = 0;
    for (let i = 0; i < 4; i++) {
      if (this.hasValue(i)) {
        count = count + 1;
      }
    }
    if (count < 2) {
      return '';
    }
    let cmd = '';
    let first = true;
    for (let i = 0; i < 4; i++) {
      if (!this.hasValue(i)) {
        continue;
      }
      const ratio = Math.max(0, Math.min(100, this.scoreOf(i))) / 100;
      const x = fmt(this.px(i, this.maxR() * ratio));
      const y = fmt(this.py(i, this.maxR() * ratio));
      cmd = cmd + (first ? 'M ' : ' L ') + x + ' ' + y;
      first = false;
    }
    return cmd + ' Z';
  }

  private labelX(index: number): number {
    return this.px(index, this.maxR() + 30) - 40;
  }

  private labelY(index: number): number {
    return this.py(index, this.maxR() + 30) - 14;
  }

  private axisLabel(index: number): string {
    return this.isChild ? this.childLabels[index] : this.labels[index];
  }

  private axisValue(index: number): string {
    const value = this.scoreOf(index);
    if (value < 0) {
      return '—';
    }
    return this.isChild ? Math.round(value).toString() : fmt(value);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Path({ commands: this.ringCommands(1) })
        .width(this.chartSize)
        .height(this.chartSize)
        .stroke($r('app.color.ec_border'))
        .strokeWidth(1)
        .fill($r('app.color.ec_primary'))
        .fillOpacity(0.03)
      Path({ commands: this.ringCommands(0.75) })
        .width(this.chartSize)
        .height(this.chartSize)
        .stroke($r('app.color.ec_border'))
        .strokeWidth(1)
        .fillOpacity(0)
      Path({ commands: this.ringCommands(0.5) })
        .width(this.chartSize)
        .height(this.chartSize)
        .stroke($r('app.color.ec_border'))
        .strokeWidth(1)
        .fillOpacity(0)
      Path({ commands: this.ringCommands(0.25) })
        .width(this.chartSize)
        .height(this.chartSize)
        .stroke($r('app.color.ec_border'))
        .strokeWidth(1)
        .fillOpacity(0)
      ForEach([0, 1, 2, 3], (i: number) => {
        Path({ commands: this.axisCommands(i) })
          .width(this.chartSize)
          .height(this.chartSize)
          .stroke($r('app.color.ec_border'))
          .strokeWidth(1)
          .fillOpacity(0)
      }, (i: number) => 'axis' + i.toString())
      if (this.scoreCommands().length > 0) {
        Path({ commands: this.scoreCommands() })
          .width(this.chartSize)
          .height(this.chartSize)
          .stroke($r('app.color.ec_primary'))
          .strokeWidth(2)
          .fill($r('app.color.ec_primary'))
          .fillOpacity(0.20)
      }
      ForEach([0, 1, 2, 3], (i: number) => {
        Column({ space: 0 }) {
          Text(this.axisLabel(i))
            .fontSize(this.isChild ? EcFont.caption : EcFont.micro)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_ink'))
          Text(this.axisValue(i))
            .fontSize(EcFont.micro)
            .fontColor(this.hasValue(i) ? $r('app.color.ec_primary') : $r('app.color.ec_muted'))
        }
        .width(80)
        .alignItems(HorizontalAlign.Center)
        .position({ x: this.labelX(i), y: this.labelY(i) })
      }, (i: number) => 'label' + i.toString())
    }
    .width(this.chartSize)
    .height(this.chartSize)
  }
}

@Component
export struct PitchChart {
  /** 每项 [time_ms, f0|null] */
  @Prop user: Array<Array<number | null>> = [];
  @Prop reference: Array<Array<number | null>> = [];
  @Prop isChild: boolean = false;
  @Prop chartHeight: number = 170;
  @State private chartWidth: number = 320;

  private maxTime(): number {
    let max = 0;
    for (let i = 0; i < this.user.length; i++) {
      const point = this.user[i];
      const t = point.length > 0 ? point[0] : null;
      if (t !== null && t !== undefined && t > max) {
        max = t;
      }
    }
    for (let i = 0; i < this.reference.length; i++) {
      const point = this.reference[i];
      const t = point.length > 0 ? point[0] : null;
      if (t !== null && t !== undefined && t > max) {
        max = t;
      }
    }
    return max <= 0 ? 1 : max;
  }

  private minHz(): number {
    let min = 0;
    let started = false;
    const visit = (source: Array<Array<number | null>>): void => {
      for (let i = 0; i < source.length; i++) {
        const point = source[i];
        const hz = point.length > 1 ? point[1] : null;
        if (hz === null || hz === undefined || hz <= 0) {
          continue;
        }
        if (!started || hz < min) {
          min = hz;
        }
        started = true;
      }
    };
    visit(this.user);
    visit(this.reference);
    return started ? min : 0;
  }

  private maxHz(): number {
    let max = 0;
    const visit = (source: Array<Array<number | null>>): void => {
      for (let i = 0; i < source.length; i++) {
        const point = source[i];
        const hz = point.length > 1 ? point[1] : null;
        if (hz !== null && hz !== undefined && hz > max) {
          max = hz;
        }
      }
    };
    visit(this.user);
    visit(this.reference);
    return max;
  }

  private commands(source: Array<Array<number | null>>): string {
    const min = this.minHz();
    const max = this.maxHz();
    const maxT = this.maxTime();
    if (max <= min) {
      return '';
    }
    const left = 34;
    const right = 6;
    const top = 8;
    const bottom = 20;
    const width = this.chartWidth - left - right;
    const height = this.chartHeight - top - bottom;
    let cmd = '';
    let penDown = false;
    for (let i = 0; i < source.length; i++) {
      const point = source[i];
      const t = point.length > 0 ? point[0] : null;
      const hz = point.length > 1 ? point[1] : null;
      if (t === null || t === undefined || hz === null || hz === undefined || hz <= 0) {
        penDown = false;
        continue;
      }
      const x = left + (t / maxT) * width;
      const y = top + height - ((hz - min) / (max - min)) * height;
      cmd = cmd + (penDown ? ' L ' : ' M ') + fmt(x) + ' ' + fmt(y);
      penDown = true;
    }
    return cmd;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 空命令的 Path 在部分机型会渲染异常：没数据就不挂 Path
      if (this.commands(this.reference).length > 0) {
        Path({ commands: this.commands(this.reference) })
          .width(this.chartWidth)
          .height(this.chartHeight)
          .stroke($r('app.color.ec_muted'))
          .strokeWidth(1.5)
          .strokeDashArray([4, 4])
          .fillOpacity(0)
      }
      if (this.commands(this.user).length > 0) {
        Path({ commands: this.commands(this.user) })
          .width(this.chartWidth)
          .height(this.chartHeight)
          .stroke($r('app.color.ec_primary'))
          .strokeWidth(2)
          .fillOpacity(0)
      }
      Text(this.maxHz() > 0 ? (Math.round(this.maxHz()).toString() + 'Hz') : '')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .position({ x: 0, y: 0 })
      Text(this.minHz() > 0 ? (Math.round(this.minHz()).toString() + 'Hz') : '')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .position({ x: 0, y: this.chartHeight - 34 })
      Row({ space: 10 }) {
        Text('你的音调')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_primary'))
        Text('示范音调')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
      }
      .position({ x: 34, y: this.chartHeight - 20 })
    }
    .width('100%')
    .height(this.chartHeight)
    .backgroundColor($r('app.color.ec_surface_alt'))
    .borderRadius(10)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      // Area.width 可能是 string（如 '1408.00px'）或 number；直接 as number 会变 NaN，
      // 导致 chartWidth 永远停在默认 320，曲线只画一小段（真机已验证过这个坑）
      const rawWidth: Length = newValue.width;
      const w: number = typeof rawWidth === 'number' ? rawWidth : Number.parseFloat(rawWidth as string);
      if (Number.isFinite(w) && w > 0 && Math.abs(w - this.chartWidth) > 1) {
        this.chartWidth = w;
      }
    })
  }
}

@Component
export struct SparkLine {
  @Prop scores: number[] = [];
  @Prop lineHeight: number = 64;
  @State private chartWidth: number = 320;

  private commands(): string {
    if (this.scores.length === 0) {
      return '';
    }
    const width = this.chartWidth - 8;
    const height = this.lineHeight - 10;
    const step = this.scores.length > 1 ? width / (this.scores.length - 1) : 0;
    let cmd = '';
    for (let i = 0; i < this.scores.length; i++) {
      const score = Math.max(0, Math.min(100, this.scores[i]));
      const x = 4 + step * i;
      const y = 4 + height - (score / 100) * height;
      cmd = cmd + (i === 0 ? 'M ' : ' L ') + fmt(x) + ' ' + fmt(y);
    }
    return cmd;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.commands().length > 0) {
        Path({ commands: this.commands() })
          .width(this.chartWidth)
          .height(this.lineHeight)
          .stroke($r('app.color.ec_primary'))
          .strokeWidth(2)
          .fillOpacity(0)
      }
    }
    .width('100%')
    .height(this.lineHeight)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      // Area.width 可能是 string（如 '1408.00px'）或 number；直接 as number 会变 NaN，
      // 导致 chartWidth 永远停在默认 320，曲线只画一小段（真机已验证过这个坑）
      const rawWidth: Length = newValue.width;
      const w: number = typeof rawWidth === 'number' ? rawWidth : Number.parseFloat(rawWidth as string);
      if (Number.isFinite(w) && w > 0 && Math.abs(w - this.chartWidth) > 1) {
        this.chartWidth = w;
      }
    })
  }
}

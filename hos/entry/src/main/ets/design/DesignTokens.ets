/**
 * Design tokens · 唯一来源（对应 docs/design-system.md 与仓库根 docs/design-tokens.md）。
 *
 * - 颜色：真实值同时写在 `resources/base/element/color.json`，页面用 `$r('app.color.ec_*')`；
 *   需要**按分数动态选色**的地方用本文件的 `EcScore.color*()`（返回同一个资源）。
 * - 尺寸/字号/圆角：数字 token（vp/fp），避免在页面散落魔法值。
 *
 * 真实值（与 Web 对齐）：背景 #F5F7FF、主色 #5B5BD6、卡片 20vp、弹层 28vp、按钮 14vp。
 */
export class EcSpace {
  static readonly x1: number = 4;
  static readonly x2: number = 8;
  static readonly x3: number = 12;
  static readonly x4: number = 16;
  static readonly x5: number = 20;
  static readonly x6: number = 24;
  static readonly x8: number = 32;
  static readonly x10: number = 40;
  static readonly x12: number = 48;
}

export class EcRadius {
  static readonly sm: number = 8;
  /** 按钮 / 输入框（Web 0.9rem） */
  static readonly md: number = 14;
  /** 卡片（Web 1.25rem） */
  static readonly lg: number = 20;
  /** 大容器 / 弹层（Web 1.75rem） */
  static readonly xl: number = 28;
  static readonly pill: number = 999;
}

export class EcFont {
  static readonly display: number = 32;
  static readonly h1: number = 28;
  static readonly h2: number = 24;
  static readonly h3: number = 20;
  static readonly body: number = 16;
  static readonly caption: number = 13;
  static readonly micro: number = 11;
  static readonly childBody: number = 19;
  static readonly childH1: number = 30;
  static readonly childButton: number = 19;
  /** 句子卡英文正文 */
  static readonly sentence: number = 22;
}

export class EcButtonSize {
  static readonly sm: number = 36;
  static readonly md: number = 48;
  static readonly lg: number = 56;
  /** 儿童所有可点按钮 */
  static readonly child: number = 60;
  /** 录音主按钮 */
  static readonly record: number = 72;
  static readonly recordChild: number = 88;
}

export class EcShadow {
  static card(): ShadowOptions {
    return { radius: 24, color: 'rgba(27,31,59,0.06)', offsetX: 0, offsetY: 8 };
  }

  static raised(): ShadowOptions {
    return { radius: 16, color: 'rgba(91,91,214,0.28)', offsetX: 0, offsetY: 6 };
  }
}

/**
 * 分数展示规则（docs/screens.md §0、docs/design-system.md §1.2）。
 *
 * 成人：0–100 数字 + 语义色（≥85 good / 70–84 info / 60–69 warn / <60 bad）。
 * 儿童：<60 **不显示数字、不用红色**，只给鼓励语 + 星星。
 */
export class EcScore {
  static color(score: number | null | undefined): ResourceColor {
    if (score === null || score === undefined) {
      return $r('app.color.ec_muted');
    }
    if (score >= 85) {
      return $r('app.color.ec_good');
    }
    if (score >= 70) {
      return $r('app.color.ec_info');
    }
    if (score >= 60) {
      return $r('app.color.ec_warn');
    }
    return $r('app.color.ec_bad');
  }

  /** 儿童的分数颜色：低分用 warn（不刺眼），不出现红色。 */
  static colorForChild(score: number | null | undefined): ResourceColor {
    if (score === null || score === undefined) {
      return $r('app.color.ec_muted');
    }
    if (score >= 85) {
      return $r('app.color.ec_good');
    }
    if (score >= 60) {
      return $r('app.color.ec_info');
    }
    return $r('app.color.ec_warn');
  }

  static colorByMode(score: number | null | undefined, isChild: boolean): ResourceColor {
    return isChild ? EcScore.colorForChild(score) : EcScore.color(score);
  }

  /** 儿童 <60 不展示数字；null（不可得）一律不展示。 */
  static showNumber(score: number | null | undefined, isChild: boolean): boolean {
    if (score === null || score === undefined) {
      return false;
    }
    if (!isChild) {
      return true;
    }
    return score >= 60;
  }

  static numberText(score: number | null | undefined): string {
    if (score === null || score === undefined) {
      return '—';
    }
    return Math.round(score).toString();
  }

  /** 总分一句话（成人/儿童两套语气，儿童不出现否定词）。 */
  static encouragement(score: number | null | undefined, isChild: boolean): string {
    if (score === null || score === undefined) {
      return isChild ? '录好啦，等下再看分数' : '本次没有拿到分数，可稍后重试评测';
    }
    if (score >= 90) {
      return isChild ? '太棒啦，读得非常清楚 🌟' : '很稳，几乎和示范一样清楚';
    }
    if (score >= 80) {
      return isChild ? '读得真好，继续加油 ⭐' : '整体很好，个别词再注意一下';
    }
    if (score >= 70) {
      return isChild ? '不错哦，再读一遍会更顺 💪' : '不错，节奏和重音还能更自然';
    }
    if (score >= 60) {
      return isChild ? '有进步，再试一次吧 🌱' : '基本能听懂，慢一点会更清楚';
    }
    return isChild ? '再来一次会更好 💪' : '这句话有点难，放慢速度再读一遍，注意加粗的词';
  }

  static stars(score: number | null | undefined): string {
    if (score === null || score === undefined) {
      return '⭐';
    }
    if (score >= 85) {
      return '⭐⭐⭐';
    }
    if (score >= 70) {
      return '⭐⭐';
    }
    return '⭐';
  }

  /** 子项中文名（儿童版不出现「准确度/流利度」这类术语口径统一在文案层处理）。 */
  static subScoreLabel(key: string): string {
    if (key === 'accuracy') {
      return '准确度';
    }
    if (key === 'fluency') {
      return '流利度';
    }
    if (key === 'completeness') {
      return '完整度';
    }
    if (key === 'prosody') {
      return '语调';
    }
    return key;
  }
}

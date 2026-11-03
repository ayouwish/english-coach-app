import { EcFont } from '../design/DesignTokens';
import { DictionaryService, WordIpaResult } from '../core/service/DictionaryService';
import { AccountPrefs } from '../core/content/AccountPrefs';

/** 单词 / 非单词切分结果（保留标点与空格，渲染后与原文一致）。 */
class WordTok {
  text: string = '';
  isWord: boolean = false;
}

/**
 * 可点单词正文（task-87 / task-88）：点一下浮层**只显示音标**（无发音按钮）。
 *
 * - 保留标点与空格；单词用 `Flex` 逐个渲染（长词不拆行）
 * - 浮层内容：单词 + `/ipa/`（多变体小字）+ 关闭提示
 * - 无音标 → 「暂无音标」（不报错）
 * - 设置关闭（showWordIpa=false）→ 「音标已关闭」提示去设置打开
 */
@Component
export struct WordText {
  @Prop @Watch('rebuild') text: string = '';
  /** 字号（正文用 EcFont.body / childBody 的数值） */
  @Prop fontSizeVp: number = 16;
  @Prop lineHeightVp: number = 26;
  @Prop inkColor: ResourceColor = $r('app.color.ec_ink');
  @State tokens: WordTok[] = [];
  @State openWord: string = '';
  @State ipa: string = '';
  @State variants: string[] = [];
  @State loading: boolean = false;
  @State missing: boolean = false;
  @State disabled: boolean = false;
  @State popupShown: boolean = false;

  aboutToAppear(): void {
    this.rebuild();
  }

  rebuild(): void {
    this.tokens = WordText.tokenize(this.text);
  }

  /** 按字母/撇号/连字符切词，其余字符（空格、标点）原样保留。 */
  private static tokenize(value: string): WordTok[] {
    const out: WordTok[] = [];
    let buffer = '';
    let wordBuffer = '';
    for (let i = 0; i < value.length; i++) {
      const ch = value.charAt(i);
      const code = value.charCodeAt(i);
      const isLetter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
      const isJoiner = ch === '\'' || ch === '’' || ch === '-';
      if (isLetter || (isJoiner && wordBuffer.length > 0 && buffer.length === 0)) {
        if (buffer.length > 0) {
          const plain = new WordTok();
          plain.text = buffer;
          plain.isWord = false;
          out.push(plain);
          buffer = '';
        }
        wordBuffer += ch;
      } else {
        if (wordBuffer.length > 0) {
          const word = new WordTok();
          word.text = wordBuffer;
          word.isWord = true;
          out.push(word);
          wordBuffer = '';
        }
        buffer += ch;
      }
    }
    if (wordBuffer.length > 0) {
      const word = new WordTok();
      word.text = wordBuffer;
      word.isWord = true;
      out.push(word);
    }
    if (buffer.length > 0) {
      const plain = new WordTok();
      plain.text = buffer;
      plain.isWord = false;
      out.push(plain);
    }
    return out;
  }

  private async tapWord(word: string): Promise<void> {
    if (this.openWord === word && this.popupShown) {
      this.popupShown = false;
      this.openWord = '';
      return;
    }
    this.openWord = word;
    this.ipa = '';
    this.variants = [];
    this.missing = false;
    this.disabled = false;
    this.loading = true;
    this.popupShown = true;
    if (!AccountPrefs.showWordIpa) {
      await AccountPrefs.ensure();
    }
    if (!AccountPrefs.showWordIpa) {
      this.loading = false;
      this.disabled = true;
      return;
    }
    const result: WordIpaResult = await DictionaryService.wordIpa(word);
    if (this.openWord !== word) {
      return;
    }
    this.loading = false;
    this.disabled = result.disabled;
    this.missing = result.missing;
    this.ipa = result.ipa;
    this.variants = result.variants;
  }

  @Builder
  ipaPopup() {
    Column({ space: 4 }) {
      Text(this.openWord)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      if (this.loading) {
        Text('音标…')
          .fontSize(12)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      } else if (this.disabled) {
        Text('音标已关闭；可在「设置 → 单词显示音标」里打开')
          .fontSize(12)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      } else if (this.ipa.length > 0) {
        Text('/' + this.ipa + '/')
          .fontSize(15)
          .fontColor($r('app.color.ec_ink'))
          .fontFamily('monospace')
          .width('100%')
        if (this.variants.length > 1) {
          Text('其它读音：' + this.variants.slice(1).map((v: string) => '/' + v + '/').join(' '))
            .fontSize(11)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
      } else {
        Text('暂无音标')
          .fontSize(12)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
    }
    .padding(14)
    .width(200)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(14)
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.tokens, (token: WordTok, index: number) => {
        if (token.isWord) {
          Text(token.text)
            .fontSize(this.fontSizeVp)
            .fontColor(this.inkColor)
            .lineHeight(this.lineHeightVp)
            .decoration({ type: TextDecorationType.Underline, color: $r('app.color.ec_border') })
            .onClick(() => {
              void this.tapWord(token.text);
            })
        } else {
          Text(token.text)
            .fontSize(this.fontSizeVp)
            .fontColor(this.inkColor)
            .lineHeight(this.lineHeightVp)
        }
      }, (token: WordTok, index: number) => token.text + '_' + index.toString())
    }
    .width('100%')
    .bindPopup($$this.popupShown, {
      builder: this.ipaPopup(),
      placement: Placement.Bottom,
      enableArrow: true,
      autoCancel: true,
      onStateChange: (event: PopupStateChangeParam) => {
        if (!event.isVisible) {
          this.popupShown = false;
          this.openWord = '';
        }
      }
    })
  }
}

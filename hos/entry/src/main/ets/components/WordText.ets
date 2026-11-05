import { DictionaryService, WordIpaResult } from '../core/service/DictionaryService';
import { AccountPrefs } from '../core/content/AccountPrefs';

/** 单词 / 非单词切分结果（保留标点与空格，渲染后与原文一致）。 */
class WordTok {
  text: string = '';
  isWord: boolean = false;
}

/**
 * 可点单词正文（task-87 / task-88）：点一下**只显示音标**（无发音按钮）。
 *
 * - 保留标点与空格；单词用 `Flex` 逐个渲染（长词不拆行）
 * - 浮层用系统 AlertDialog 实现（跨机型最稳）：标题=单词，正文=`/ipa/`；
 *   多变体追加「其它读音」；无音标 → 「暂无音标」；设置关闭 → 「音标已关闭」提示
 * - 不提供发音按钮、不调 TTS
 */
@Component
export struct WordText {
  @Prop @Watch('rebuild') text: string = '';
  /** 字号（正文用 EcFont.body / childBody 的数值） */
  @Prop fontSizeVp: number = 16;
  @Prop lineHeightVp: number = 26;
  @Prop inkColor: ResourceColor = $r('app.color.ec_ink');
  @State tokens: WordTok[] = [];

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

  private showIpaDialog(word: string, message: string): void {
    this.getUIContext().showAlertDialog({
      title: word,
      message: message,
      primaryButton: {
        value: '知道了',
        action: () => {
        }
      }
    });
  }

  private async tapWord(word: string): Promise<void> {
    await AccountPrefs.ensure();
    if (!AccountPrefs.showWordIpa) {
      this.showIpaDialog(word, '音标已关闭；可在「设置 → 单词显示音标」里打开');
      return;
    }
    const result: WordIpaResult = await DictionaryService.wordIpa(word);
    if (result.disabled) {
      this.showIpaDialog(word, '音标已关闭；可在「设置 → 单词显示音标」里打开');
      return;
    }
    if (result.missing || result.ipa.length === 0) {
      this.showIpaDialog(word, '暂无音标');
      return;
    }
    let message = '/' + result.ipa + '/';
    if (result.variants.length > 1) {
      message += '　其它读音：' + result.variants.slice(1).map((v: string) => '/' + v + '/').join(' ');
    }
    this.showIpaDialog(word, message);
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
            .gesture(
              LongPressGesture({ repeat: false, duration: 450 })
                .onAction(() => {
                  void this.tapWord(token.text);
                })
            )
        } else {
          Text(token.text)
            .fontSize(this.fontSizeVp)
            .fontColor(this.inkColor)
            .lineHeight(this.lineHeightVp)
        }
      }, (token: WordTok, index: number) => token.text + '_' + index.toString())
    }
    .width('100%')
  }
}

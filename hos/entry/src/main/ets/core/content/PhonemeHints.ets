/**
 * 音素教学提示（hint_key → 中文 why/how/练习词）。
 *
 * 与 Web 端 `web/src/lib/hints.ts` 对齐（canonical-v1，18 个合法键 + GENERIC 兜底）。
 * 儿童文案不出现 IPA（单独写 why_child/how_child，缺失时用成人版剥掉 IPA 的方式不可靠，
 * 因此这里只为需要差异的键提供儿童版，其余沿用成人版文字）。
 */
export class PhonemeHint {
  key: string = '';
  titleZh: string = '';
  titleChild: string = '';
  whyZh: string = '';
  whyChild: string = '';
  howZh: string = '';
  howChild: string = '';
  words: string[] = [];
  demoText: string = '';
}

const PHONEME_TO_KEY: Map<string, string> = new Map([
  ['θ', 'th_voiceless'], ['ð', 'th_voiced'], ['r', 'r_l_v'], ['l', 'r_l_v'],
  ['v', 'v_w'], ['w', 'v_w'], ['s', 's_sh'], ['ʃ', 's_sh'],
  ['n', 'n_ng'], ['ŋ', 'n_ng'], ['i', 'short_i_long_i'], ['ɪ', 'short_i_long_i'],
  ['e', 'ae_e'], ['æ', 'ae_e'], ['ə', 'schwa'], ['ɜ', 'schwa'],
  ['tʃ', 'consonant_cluster'], ['dʒ', 'consonant_cluster']
]);

export class PhonemeHints {
  static of(key: string, titleZh: string, titleChild: string, whyZh: string, whyChild: string,
    howZh: string, howChild: string, words: string[], demo: string): PhonemeHint {
    const hint = new PhonemeHint();
    hint.key = key;
    hint.titleZh = titleZh;
    hint.titleChild = titleChild;
    hint.whyZh = whyZh;
    hint.whyChild = whyChild;
    hint.howZh = howZh;
    hint.howChild = howChild;
    hint.words = words;
    hint.demoText = demo;
    return hint;
  }

  static byKey(key: string): PhonemeHint {
    const found = PhonemeHints.table().get(key);
    return found === undefined ? PhonemeHints.generic() : found;
  }

  /** 音素符号 → hint_key → 提示；没有映射时返回 GENERIC。 */
  static byPhoneme(phoneme: string): PhonemeHint {
    const key = PHONEME_TO_KEY.get(phoneme);
    return key === undefined ? PhonemeHints.generic() : PhonemeHints.byKey(key);
  }

  static title(hint: PhonemeHint, isChild: boolean): string {
    return isChild ? hint.titleChild : hint.titleZh;
  }

  static why(hint: PhonemeHint, isChild: boolean): string {
    return isChild ? hint.whyChild : hint.whyZh;
  }

  static how(hint: PhonemeHint, isChild: boolean): string {
    return isChild ? hint.howChild : hint.howZh;
  }

  private static cached: Map<string, PhonemeHint> | null = null;
  private static genericHint: PhonemeHint | null = null;

  private static generic(): PhonemeHint {
    const existing = PhonemeHints.genericHint;
    if (existing !== null) {
      return existing;
    }
    const hint = PhonemeHints.of('generic', '这个词可以再清楚一点', '这个词再说清楚一点点',
      '发音清晰度还可以提高。', '发音清晰度还可以提高。',
      '放慢速度，把每个音都说完整，再录一遍试试。', '放慢速度，把每个音都说完整，再录一遍试试。', [], '');
    PhonemeHints.genericHint = hint;
    return hint;
  }

  private static table(): Map<string, PhonemeHint> {
    const existing = PhonemeHints.cached;
    if (existing !== null) {
      return existing;
    }
    const map: Map<string, PhonemeHint> = new Map();
    map.set('th_voiceless', PhonemeHints.of('th_voiceless',
      'th 的 /θ/ 音（如 think）', 'think 里开头的那个「咬舌音」',
      '舌尖没有伸出来，气流从牙龈缝隙出去了，听起来像 /s/。',
      '舌尖没有伸出来，气从牙缝里跑掉了，听起来有点像 s。',
      '舌尖轻轻伸到上下齿之间，让气流从缝里摩擦出来，声带不要振动。',
      '舌尖轻轻伸到上下牙齿之间，让气从缝里出来，嗓子不要振动。',
      ['think', 'thank', 'three', 'thick'], 'think, thank, three'));
    map.set('th_voiced', PhonemeHints.of('th_voiced',
      'th 的 /ð/ 音（如 this）', 'this 里那个「带声音的咬舌音」',
      '舌尖位置不对，/ð/ 被读成了 /d/ 或 /z/。',
      '舌尖的位置不太对，这个音听起来像 d 或者 z。',
      '舌尖放在上下齿之间，这次要让声带振动，喉咙有嗡嗡的震感。',
      '舌尖放在上下牙齿中间，这次要让嗓子嗡嗡地振动起来。',
      ['this', 'that', 'mother', 'weather'], 'this, that, mother'));
    map.set('r_l_v', PhonemeHints.of('r_l_v',
      '/r/ 与 /l/ 混淆', 'r 和 l 两个音要分开',
      '舌尖卷起与顶住上齿龈的动作没有区分开。',
      'r 和 l 的舌头动作没有分开，听起来会混。',
      '/r/ 舌尖悬空向后卷，不碰上颚；/l/ 舌尖要顶住上齿龈。',
      'r 的舌尖要悬空向后卷、不碰上颚；l 的舌尖要顶住上齿龈。',
      ['right', 'light', 'really', 'little'], 'right, light, really'));
    map.set('v_w', PhonemeHints.of('v_w',
      '/v/ 与 /w/ 混淆', 'v 要咬嘴唇，w 要圆嘴巴',
      '/v/ 缺少上齿咬下唇的摩擦，听起来像 /w/。',
      '上齿没有咬住下唇，这个音听起来像 w。',
      '上齿轻咬下唇送气＝/v/；双唇收圆不碰牙齿＝/w/。',
      '上齿轻轻咬住下唇送气就是 v；双唇收圆、不碰牙齿就是 w。',
      ['very', 'west', 'voice', 'water'], 'very, west, voice'));
    map.set('short_i_long_i', PhonemeHints.of('short_i_long_i',
      '短 /ɪ/ 与长 /i/（canonical-v1）', '短音和长音要拉长一点',
      '长短元音没有区分，ship 听成了 sheep。',
      '长音和短音没有分开，ship 听起来像 sheep。',
      '/i/ 嘴角往两边拉开并保持久一点；/ɪ/ 短促、嘴角放松。',
      '长音要把嘴角往两边拉开、保持久一点；短音要短促、嘴角放松。',
      ['ship', 'sheep', 'sit', 'seat'], 'ship, sheep, sit, seat'));
    map.set('ae_e', PhonemeHints.of('ae_e',
      '/æ/ 与 /e/', '嘴巴要张大一点',
      '/æ/ 开口不够大，听起来像 /e/。', '嘴巴张得不够大，这个音听起来像 e。',
      '下巴放低，嘴角略向两边，像说「啊」又像「哎」。',
      '下巴放低，嘴角往两边一点，像说「啊」又像「哎」。',
      ['cat', 'bed', 'apple', 'pen'], 'cat, bed, apple'));
    map.set('s_sh', PhonemeHints.of('s_sh',
      '/s/ 与 /ʃ/', 'sh 要把嘴唇收圆',
      '舌位太靠前，/ʃ/ 被读成 /s/。', '舌头太靠前了，sh 这个音听起来像 s。',
      '舌面抬高靠近硬腭，双唇稍微收圆前突。',
      '舌头抬高靠近上颚，嘴唇稍微收圆往前。',
      ['she', 'sea', 'shoe', 'sure'], 'she, sea, shoe'));
    map.set('n_ng', PhonemeHints.of('n_ng',
      '词尾 /n/ 与 /ŋ/', '结尾的 ng 要从鼻子里出来',
      '词尾鼻音区分不清，sin 与 sing 一样。', '结尾的鼻音区分不清，sin 和 sing 听起来一样。',
      '/ŋ/ 舌根抬起顶住软腭，气流从鼻腔出来，舌尖不要碰齿龈。',
      '发结尾的 ng 时，舌根抬起来顶住软腭，气从鼻子出来，舌尖不要碰上齿龈。',
      ['sing', 'sin', 'thing', 'thin'], 'sing, thing, long'));
    map.set('l_dark', PhonemeHints.of('l_dark',
      '词尾暗 /l/', '结尾的 l 舌头要抬起来',
      '词尾 /l/ 被吞掉或读成元音。', '结尾的 l 被吞掉了。',
      '舌尖顶住上齿龈并保持住，再收尾。',
      '结尾的 l 要把舌尖顶住上齿龈，保持一下再收。',
      ['milk', 'school', 'little', 'apple'], 'milk, school, little'));
    map.set('schwa', PhonemeHints.of('schwa',
      '非重读弱元音 /ə/', '不重要的音节要读得又轻又短',
      '每个音节都读得太重，节奏听起来很硬。', '每个音节都读得太重，听起来有点硬。',
      '非重读音节放松成轻轻的「呃」，重音只放在一个音节上。',
      '不重要的音节轻轻带过，只有重音的音节读得响一点。',
      ['banana', 'about', 'teacher', 'today'], 'banana, about, teacher'));
    map.set('final_consonant', PhonemeHints.of('final_consonant',
      '词尾辅音丢失', '最后一个音也要说完整',
      '词尾辅音没有发出来，look 听成了 loo。', '最后一个音没有说出来，look 听起来像 loo。',
      '句子结束时也要把最后的辅音轻轻收住，不要吞掉。',
      '最后一个音也要轻轻收住，不要说一半。',
      ['book', 'good', 'cat', 'stop'], 'book, good, cat'));
    map.set('consonant_cluster', PhonemeHints.of('consonant_cluster',
      '辅音连缀', '两个辅音要连在一起说',
      '连缀中间被插入了元音，strike 读成 sutrike。', '两个辅音中间多了一个音。',
      '把两个辅音紧挨着快速说出，中间不要加「呃」。',
      '两个辅音紧挨着快速说出来，中间不要加别的音。',
      ['street', 'spring', 'desk', 'asked'], 'street, spring, desk'));
    map.set('stress_wrong', PhonemeHints.of('stress_wrong',
      '单词重音位置', '有一个音节要读得更响',
      '重音位置不对，单词听起来不自然。', '重音的位置不太对。',
      '重读音节读得更长、更响、更高，其余音节弱化。',
      '有一个音节读得更长、更响、更高，其它音节轻轻带过。',
      ['record', 'present', 'banana', 'photograph'], 'banana, present, photograph'));
    map.set('monotone', PhonemeHints.of('monotone',
      '语调太平', '声音要有高有低才像在说话',
      '整句音高几乎没有起伏。', '整句的高低变化太少了。',
      '陈述句结尾轻轻下降，疑问句结尾明显上扬。',
      '说句子的时候声音要有高有低，结尾可以降一点或升一点。',
      ['Really?', 'Is it?', 'Nice to meet you.'], 'Is it? Yes, it is.'));
    map.set('pause_wrong', PhonemeHints.of('pause_wrong',
      '停顿位置不当', '在词组之间换气，不要在词中间停',
      '在意群中间断开，影响理解。', '在词中间停下来了，听起来会断。',
      '按意群（短语）停顿，一次说完一个词组。',
      '把词组连着说完，在词组之间再换气。',
      ['in the morning', 'at school', 'with my friend'], 'in the morning, at school'));
    map.set('omission', PhonemeHints.of('omission',
      '漏词', '有个词忘记说了',
      '参考句里的单词没有读出来。', '有一个词没有读出来。',
      '放慢速度，一个词一个词看清楚再连起来读。',
      '慢一点，一个词一个词看清楚再连起来读。',
      [], ''));
    map.set('insertion', PhonemeHints.of('insertion',
      '多词', '多说了词',
      '读出了参考句以外的内容。', '多读了一些内容。',
      '先默读一遍参考句，再开口录音。',
      '先在心里读一遍句子，再开口录音。',
      [], ''));
    PhonemeHints.cached = map;
    return map;
  }
}

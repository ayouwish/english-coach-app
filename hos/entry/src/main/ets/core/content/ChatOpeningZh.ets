/**
 * 内置对话场景「开场白」的中文对照。
 *
 * 服务端 `POST /chat/sessions` 返回的 greeting `text_zh` 目前是 null（web 也一样），
 * 而场景列表只有英文 opening_line；这里内置 19 个内置场景的中文翻译，保证第一句有中文。
 * 自定义场景/未来变体查不到时返回空串（页面保持只显示英文，不报错）。
 */
export class ChatOpeningZh {
  private static cache: Map<string, string> | null = null;

  private static build(): Map<string, string> {
    const m = new Map<string, string>();
    // ---- 儿童场景 ----
    m.set('hi! i\'m sam. what\'s your name?', '嗨！我是 Sam。你叫什么名字？');
    m.set('welcome! what would you like to eat today?', '欢迎！你今天想吃什么？');
    m.set('hi! what class do you have today?', '嗨！你今天有什么课？');
    m.set('look! do you see the big elephant?', '看！你看到那头大象了吗？');
    m.set('my birthday is on saturday! do you like cake?', '我的生日在星期六！你喜欢蛋糕吗？');
    m.set('hi there! what can i get for you today?', '你好呀！今天想要点什么？');
    m.set('hello! can i help you find something?', '你好！需要我帮你找点什么吗？');
    m.set('what a lovely day! do you like sunny weather?', '天气真好！你喜欢晴天吗？');
    m.set('hello! how are you feeling today?', '你好！你今天感觉怎么样？');
    m.set('i love drawing. what do you like to do for fun?', '我喜欢画画。你平时喜欢玩什么？');
    m.set('good morning! may i see your ticket, please?', '早上好！可以看一下你的机票吗？');
    // ---- 成人场景 ----
    m.set('good morning! what can i get for you today?', '早上好！今天想喝点什么？');
    m.set('good afternoon, how can i help you with your reservation?',
      '下午好，请问您的预订需要什么帮助？');
    m.set('thanks for joining. could you give me a quick update on this week?',
      '谢谢参加。能简单说说这周的进展吗？');
    m.set('any plans for the weekend?', '周末有什么安排吗？');
    m.set('hi, you look a bit lost — need a hand?', '嗨，你看起来有点迷路——需要帮忙吗？');
    m.set('hi, you look a bit lost - need a hand?', '嗨，你看起来有点迷路——需要帮忙吗？');
    m.set('hello, what seems to be the problem today?', '你好，今天哪里不舒服？');
    m.set('hi there, are you looking for something in particular?', '你好，在找什么特别的东西吗？');
    m.set('welcome! today we\'re making a simple pasta. ready to start?',
      '欢迎！今天我们做简单的意面。准备好了吗？');
    return m;
  }

  private static map(): Map<string, string> {
    if (ChatOpeningZh.cache === null) {
      ChatOpeningZh.cache = ChatOpeningZh.build();
    }
    return ChatOpeningZh.cache;
  }

  static lookup(english: string): string {
    const key = english.trim().toLowerCase().replace(/\s+/g, ' ');
    const hit = ChatOpeningZh.map().get(key);
    return hit === undefined ? '' : hit;
  }
}

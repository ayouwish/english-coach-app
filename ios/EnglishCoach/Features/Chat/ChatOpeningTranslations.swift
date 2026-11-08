import Foundation

/// 内置场景开场白的中文兜底翻译（按英文原文匹配）。
///
/// 背景：`POST /chat/sessions` 存的是**随机变体开场白**，而服务端 `opening-zh.ts` 只按
/// scenario id 覆盖了少数固定开场白，线上 `text_zh` 常为 null（成人场景全缺、儿童变体也对不上）。
/// 在服务端补齐之前，客户端按英文原文兜底，保证第一句也有中文；未知/自定义开场白返回 nil，
/// 页面按“没有翻译”处理，不编造内容。
enum ChatOpeningTranslations {
    private static let table: [String: String] = [
        "Hi! I'm Sam. What's your name?": "嗨！我是 Sam。你叫什么名字？",
        "Hi! I'm Sam. Is that a new kite? It looks so cool!": "嗨！我是 Sam。那是新风筝吗？好酷啊！",
        "Um, hi… I'm Lily. Do you want to play tag with me?": "呃，你好……我是 Lily。你想和我一起玩抓人吗？",
        "Hey! I'm Max. I just had my first swim class — do you swim too?": "嘿！我是 Max。我刚上完第一节游泳课——你也游泳吗？",
        "Welcome! What would you like to eat today?": "欢迎！你今天想吃点什么？",
        "Hello! Today's special is tomato pasta. What would you like?": "你好！今天的特餐是番茄意面。你想来点什么？",
        "Welcome in! Our beef noodles are the most popular — want to try?": "欢迎光临！我们的牛肉面最受欢迎——要不要试试？",
        "Come in! I'm making dumplings right now. Do you want to watch and try some?": "进来吧！我正在包饺子。你想看看、再尝几个吗？",
        "Hi! What class do you have today?": "嗨！你今天上什么课？",
        "Morning! Did you see the new science project? I'm so excited.": "早上好！你看到新的科学项目了吗？我好期待。",
        "Hello! It's reading time — which book would you like to borrow today?": "你好！现在是阅读时间——你今天想借哪本书？",
        "Hey, wait! I can't find my pencil case. Have you seen it anywhere?": "嘿，等等！我找不到我的铅笔盒了。你看到它了吗？",
        "Look! Do you see the big elephant?": "看！你看到那头大象了吗？",
        "Look over there — we just had a baby monkey! Do you want to see it closer?": "看那边——我们刚有了猴宝宝！你想靠近看看吗？",
        "Come quick! The elephants are having a bath. Have you ever seen that?": "快过来！大象们在洗澡呢。你见过吗？",
        "I can't decide between the panda and the tiger. Which animal do you like best?": "我在熊猫和老虎之间选不出来。你最喜欢哪个动物？",
        "My birthday is on Saturday! Do you like cake?": "我的生日在星期六！你喜欢蛋糕吗？",
        "You came! The cake is almost ready — wait until you see it!": "你来了！蛋糕快好了——等你看到就知道了！",
        "Psst! There's a treasure hunt behind the tree. Want to join my team?": "嘘！树后面有寻宝游戏。想加入我的队伍吗？",
        "Hi! It's so loud in here — I'm Mia, what's your name?": "嗨！这里好吵——我是 Mia，你叫什么名字？",
        "Hi there! What can I get for you today?": "你好！今天想喝点什么？",
        "Hi there! We've got a new iced matcha today — what can I get you?": "你好！我们今天有新出的冰抹茶——想喝点什么？",
        "Morning! Just so you know, the croissants are gone — what else can I get you?": "早上好！跟你说一声，牛角包卖完了——还想来点什么？",
        "Sorry about the noise! The machine is a bit loud today. Coffee to go?": "抱歉有点吵！今天机器声音大。咖啡带走吗？",
        "Hello! Can I help you find something?": "你好！需要我帮你找点什么吗？",
        "Welcome! That blue jacket is half price today — want to try it on?": "欢迎！那件蓝色外套今天半价——想试穿吗？",
        "Hi! Our new running shoes just arrived — are you looking for something light?": "你好！我们的新跑鞋刚到——你在找轻便的鞋吗？",
        "What do you think of this red dress? Be honest — should I get it?": "你觉得这条红裙子怎么样？说实话——我该买吗？",
        "What a lovely day! Do you like sunny weather?": "天气真好啊！你喜欢晴天吗？",
        "Oh dear, it's pouring! I forgot my umbrella — do you have one?": "哎呀，下大雨了！我忘带伞了——你有伞吗？",
        "Whoa! My hat! The wind is crazy today — can you help me catch it?": "哇！我的帽子！今天风好大——能帮我抓住它吗？",
        "It's so hot today and the bus is late again. Do you take this bus often?": "今天好热，公交又晚点了。你常坐这趟车吗？",
        "Hello! How are you feeling today?": "你好！你今天感觉怎么样？",
        "Hello, come in. What seems to be the problem today?": "你好，请进。今天哪里不舒服？",
        "Hi! You're next for your check-up — are you feeling nervous?": "你好！轮到你体检了——你紧张吗？",
        "Let's see how tall you are now! Have you been eating your vegetables?": "我们看看你现在多高了！你平时有好好吃蔬菜吗？",
        "I love drawing. What do you like to do for fun?": "我很喜欢画画。你平时喜欢做什么？",
        "Look at this dragon I'm painting! What do you like to do after school?": "看我画的这条龙！你放学后喜欢做什么？",
        "I'm learning the piano! Do you want to try playing a few notes?": "我在学钢琴！你想试着弹几个音吗？",
        "Hey! I'm practising free throws — want to try one?": "嘿！我在练罚球——想试一个吗？",
        "Good morning! May I see your ticket, please?": "早上好！可以给我看一下你的机票吗？",
        "Good morning! Your flight is delayed by an hour. Do you need help with the gate?": "早上好！你的航班延误了一小时。需要我帮你找登机口吗？",
        "Please take out your laptop — anything else in your bag?": "请把笔记本电脑拿出来——包里还有别的东西吗？",
        "Gate 12, right? I'm flying to see my grandma. Where are you going?": "12 号登机口，对吧？我要飞去看我奶奶。你要去哪里？",
        "Good morning! What can I get for you today?": "早上好！今天想来点什么？",
        "Morning! Our honey oat latte is new — can I get you one?": "早上好！我们的蜂蜜燕麦拿铁是新品——要来一杯吗？",
        "Heads up — the machine is being repaired. Filter coffee only today, is that OK?": "提前说一下——咖啡机在维修，今天只有滤泡咖啡，可以吗？",
        "Two-for-one until noon! Getting something for your colleagues too?": "中午前第二杯半价！要不要也给同事带点？",
        "Good afternoon, how can I help you with your reservation?": "下午好，请问有什么可以帮您办理预订？",
        "Good evening — checking in for business? We still have late check-out available.": "晚上好——是出差入住吗？我们还有延迟退房服务。",
        "Welcome! Our airport shuttle is free for guests. How many nights?": "欢迎！我们的机场班车对住客免费。您要住几晚？",
        "Hello! Breakfast is on the rooftop — would you like a quiet room?": "您好！早餐在顶楼——您想要安静一点的房间吗？",
        "Thanks for joining. Could you give me a quick update on this week?": "谢谢你参加。能简单说说这周的进展吗？",
        "Thanks for joining. The project is a bit behind — can you walk me through where we are?": "谢谢你参加。项目有点落后——能带我过一下目前的情况吗？",
        "Quick one-on-one: the client asked for a change. How should we handle it?": "快速一对一：客户提了个改动需求。我们该怎么处理？",
        "Heads up, everyone: the deadline moved to Friday. Could you summarise your plan?": "各位注意：截止日期改到周五了。能概括一下你的计划吗？",
        "Any plans for the weekend?": "周末有什么安排吗？",
        "Finally Friday! I'm thinking of hiking this weekend — any plans?": "终于周五了！我在想去徒步——你有什么计划吗？",
        "I'm trying that new noodle place on Saturday. Want to come along?": "我周六想去试试那家新面馆。要一起来吗？",
        "My friend gave me concert tickets for Sunday — do you like live music?": "朋友给了我周日的演唱会票——你喜欢现场音乐吗？",
        "Hi, you look a bit lost — need a hand?": "嗨，你看起来有点迷路——需要帮忙吗？",
        "You look lost — looking for the metro? It's just behind the bank.": "你好像迷路了——在找地铁吗？就在银行后面。",
        "The museum? Two blocks down, then turn left — you can't miss it.": "博物馆？往前走两个街区，然后左转——不会找不到的。",
        "Station? There's a shortcut through the park — want me to point it out?": "车站？穿过公园有条近路——要我给你指一下吗？",
        "Hello, what seems to be the problem today?": "你好，今天哪里不舒服？",
        "Hello, take a seat. How long have you had these headaches?": "你好，请坐。这些头痛有多久了？",
        "Your blood test results came in — would you like to go through them now?": "你的验血结果出来了——想现在一起看看吗？",
        "You're here for a refill? Which medication are you currently taking?": "你是来续药的吧？目前在吃哪种药？",
        "Hi there, are you looking for something in particular?": "你好，在找什么特别的东西吗？",
        "Hi! Apples are on special today — are you looking for anything else?": "你好！苹果今天特价——还要找点别的吗？",
        "Sorry for the wait, the card reader is slow today. Do you have another payment method?": "抱歉让你久等，今天刷卡机有点慢。你有别的付款方式吗？",
        "Looking for milk? The delivery is late today — have you tried the second shelf?": "在找牛奶吗？今天的货送晚了——你去第二层货架看过了吗？",
        "Welcome! Today we're making a simple pasta. Ready to start?": "欢迎！今天我们做一道简单的意面。准备好了吗？",
        "Welcome! Today it's mushroom risotto. Ready to start with the onions?": "欢迎！今天做蘑菇烩饭。准备好切洋葱了吗？",
        "We're making dumplings today! Would you like to try folding one?": "今天我们包饺子！你想试试捏一个吗？",
        "The dough needs an hour to rest — shall we prepare the topping while we wait?": "面团要醒一个小时——我们趁这段时间准备配料好吗？",
    ]

    /// 规范化：去掉首尾空白、把连续空白压成一个空格、统一弯引号。
    private static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
    }

    private static let normalizedTable: [String: String] = {
        var result: [String: String] = [:]
        for (key, value) in table {
            result[normalize(key)] = value
        }
        return result
    }()

    /// 英文开场白 → 中文；查不到返回 nil。
    static func zh(for english: String) -> String? {
        let key = normalize(english)
        guard !key.isEmpty else { return nil }
        return normalizedTable[key]
    }
}

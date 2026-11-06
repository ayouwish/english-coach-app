# 页面 × 接口 × 双端对齐矩阵

图例：✅ 客户端必须实现 · 🔒 仅家长 · 🧒 儿童模式差异 · 🆕 依赖【待后端新增】

## 1. 登录与账号

| 页面 | 接口 | 说明 | 儿童差异 |
|---|---|---|---|
| 登录 | `POST /api/auth/token`（Bearer）、`GET /api/auth/me` | 邮箱+密码 → access(1h)+refresh(30d)；网络层单飞刷新；退出调 `/api/auth/revoke`；页面有「创建家庭 / 邀请码加入」入口 | 用**演示账号快捷按钮**（只填邮箱，不猜密码）|
| **注册 / 加入家庭** | `POST /api/auth/register` | 两种模式：「🆕 创建家庭」（受 `ALLOW_SELF_SIGNUP` 控制）与「🔑 用邀请码加入」；注册即登录 | 儿童不开放自助注册 |
| 退出 | `POST /api/auth/revoke`（+ 清本地 token） | 吊销 refresh；清 Keychain/Asset Store 与缓存 | — |
| 改密码：家长重置 | `POST /api/family/members/:id/password`（**含自己**）| **已可用**：`/parent` → 家庭成员 → 「重置密码」，不需要旧密码 | 儿童页面无此入口（家长代改）|
| 改密码：自助修改（可选增强）| `POST /api/auth/password`（**待实现**）| 需当前密码；改后当前会话保持、其他会话失效；不阻塞其他功能 | 文案口语化 |
| 我的偏好 | `GET/PATCH /api/settings` | `auto_illustrate`（默认关）/`gender`/`tts_voice`/`story_sentences`/每日时长/自由聊 | 同左（儿童页口语化）|
| 家庭成员 🔒 | `GET/POST /api/family/members`、`PATCH`、`POST .../password` | 建账号/改水平（A1–C1）/重置密码；**仅本家庭**（跨家庭 404）| 儿童不可见 |
| **家庭邀请码 🔒** | `GET /api/family/invite`、`POST .../rotate` | 一次性邀请码（用后失效）；每家庭家长 ≤3；面板显示「家长账号 N/3」 | 儿童不可见 |

## 2. 跟读练习

| 页面 | 接口 | 要点 | 儿童差异 |
|---|---|---|---|
| 语料列表 | `GET /api/sentences?level=` | 600 句，A1/A2/B1/B2 | 默认自己账号的 level |
| 练习详情 | `GET /api/sentences/:id` | 文本 + 翻译 + 焦点音素 | 不显示 IPA |
| 录音评测 | `POST /api/attempts`（multipart）| 同步；返回音素/词/语调/反馈 | 不显示低分，改用鼓励 |
| 重试评测 | `POST /api/attempts/:id/retry` | 不重录 | — |
| 示范音 | `POST /api/tts` | `rate=slow/normal`，`format=wav` | 默认 slow |
| 录音回放 | `GET /api/audio/:id` | — | — |
| **练习游标** | `GET/PUT /api/practice/cursor?scope=` | 按当前筛选（`level:A2` / `focus:th` / `all`）记录位置；进入时有记录 → 「上次练到第 N 句」+「▶ 继续上次 / 从头开始」；**每练完一句自动保存**（提交即存，不等评分）| 「接着上次的继续？」|
| **单句历史 + 曲线** | `GET /api/sentences/:id/attempts?limit=20` | 只看本人的 attempts；结果区「📈 这一句的历史（N 次）」：SVG 折线（≥2 次）+ 首末对比「41 → 78（+37）」+ 每次日期/分数/▶ 回放；列表卡片可点「📈 历史」| 不显示数字分，只显示鼓励；零 IPA |
| **示范音音色** | `GET /api/tts/voices`、`POST /api/tts` | 9 种音色；不带 `voice` 时回落账号偏好；`rate=slow/normal` | 默认 slow |

## 3. 连读模式

| 页面 | 接口 | 要点 |
|---|---|---|
| 选来源 | `GET /api/sentences`、`GET /api/materials?kind=page`、`POST /api/ocr`（拍照）| 语料 / 我的书页 / 自己输入 / 拍照；**无参数进入默认「语料」**；`?material=<id>` 才自动载入材料 |
| 逐句提交 | `POST /api/attempts/async` | 立即返回，不阻塞 |
| 轮询进度 | `GET /api/attempts/status?ids=` | 1–2s，显示 待评分→评分中→分数 |
| 汇总 | 本地聚合 | 平均分、最差 2–3 句、鼓励语 |
| **再读一遍** | 无新接口（复用同一批句子重新提交 `/api/attempts/async`）| 汇总页主按钮「🔁 再读一遍 / 再读这个故事」+「第 N 遍」；**不刷新不跳转**，索引归零、清空本轮结果，两轮都入库 | 「再读一遍～」|

## 4. 对话训练

| 页面 | 接口 | 要点 | 儿童差异 |
|---|---|---|---|
| 场景列表 | `GET /api/chat/scenarios[?include_child=1]` | 内置 + **自定义场景**（`is_custom:true`）；成人默认只看 adult，儿童只 child；成人可开「再看小朋友的场景」| 大卡片，无该开关 |
| 自定义场景 | `POST /api/chat/scenarios`、`PATCH/DELETE /[id]` | 标题/场景说明/角色提示词/开场白/难度/受众；**仅 owner**（他人 404）；儿童强制 child；注入词 400 | 表单简化 |
| 场景随机变体 | 包含在 `POST /api/chat/sessions` 响应与 turn 请求的 `scenario.variation` | 每次开会话**随机抽一组**（人设/地点/细节/目标/开场白）；历史回看用当时那组 | — |
| 开始会话 | `POST /api/chat/sessions` | 返回 `session_id` + 随机开场白；**不限轮数**（`CHAT_MAX_TURNS=0`）；随时可点「🏁 结束对话」→ `POST /api/chat/sessions/:id/end` | — |
| 一轮对话 | ① `POST /api/asr` ② `POST /api/chat/sessions/:id/turn`（multipart：text 必填 + audio）③ `POST /api/tts` | 后端**没有**一体化接口，必须三步；turn 只返回助手文本 | — |
| 会话历史 | `GET /api/chat/sessions`（列表）、`/:id`（详情）、**`/:id/messages`** | 列表含轮数/场景/平均发音；messages 返回 `pron`（后台评分轮询补齐）与 **`correction`（"更自然"提示）**；家长看分数，儿童只看鼓励 | 不显示分数 |
| **整段对话回放** | `GET /api/chat/sessions/:id/audio/status`、`/audio[?force=1]` | 对话结束时**异步预生成**；ready→200 wav、building→202；UI 轮询后自动出现播放器 + 下载 | 「听一听我们的对话」|

## 5. 故事模式

| 页面 | 接口 | 要点 | 儿童差异 |
|---|---|---|---|
| 中文输入 | `POST /api/asr?language=zh-CN[&provider=zhipu]` | 🎤 说中文；也可文字；中文默认走智谱 GLM-ASR（长音频自动切段）| 大输入框 |
| **原始录音留存** | `POST /api/story/recordings`、`POST /:id/transcribe`、`GET /`、`GET /:id/audio` | **先落盘再转录**；转录失败仍 201（录音不丢）+ 可重试；「🎙️ 我的录音」列表 | 同左 |
| 句子数 | `POST /api/story/rewrite` 的 `max_sentences` | **3–12**；默认取账号（儿童 5 / 家长 8），本次可改 | 「想听几句？」 |
| 生成英文 | `POST /api/story/rewrite` | `level` 取账号 CEFR（A1–C1）；返回 readability | 文案口语化 |
| 保存 | `POST /api/materials`（`kind=story`）| — | — |
| 故事集 | `GET /api/materials?kind=story` | 按日期分组、连续天数、只看我的 | 不显示分数 |
| 故事详情 | `GET /api/materials/:id` | 英文全文（家庭可见）+ **「🗣️ 我当时讲的原话」**（**仅创建者**：中文原文 + 原声 + 转录状态）+ 朗读录音回放 + 复述记录 | 分数仅家长 |
| **整段朗读回放** | `GET /api/story/:id/audio/status`、`/audio[?force=1]` | 异步预生成；ready→200、building→202；单条录音直接返回 | 「听一听我读的故事」|
| **打印（单篇·整页）** | 页面 `/story/[id]/print[?zh=1&lines=1]` | A4 整页练习纸：大字编号句子、可选中文/书写线、白底黑字、`window.print()` | 「🖨️ 打印出来读」|
| **打印（单篇·卡片）** | 页面 `/story/[id]/print?layout=card[&zh=1&lines=1]` | **A5 卡片**（148×210mm）居中 + 虚线裁切框 + 标题/级别/日期 + 编号句子 12pt + 姓名/日期栏；工具栏可切换整页/卡片 | 「🖨️ 打印卡片出来读」|
| **打印（多选故事集）** | 页面 `/story/print?ids=a,b,c[&zh=1&lines=1]` | 列表「☑️ 选择」多选（≤30 篇）→ **封面独占第一页（`break-after: page`）**，之后**故事内容连续拼接**（可一页多篇、长故事自然跨页）；句子/书写线 `break-inside: avoid`；越权 id 忽略 | 大勾选框 |
| 复述 | `POST /api/story/retell` | 覆盖度，不评发音分 | 只看鼓励 |
| 插画 | `POST /api/story/:id/illustrate` | 每天一张；**自动带用户的 `character_desc` + `avatar_style`**；失败可见；插画下方显示 `prompt_used` + 「这个提示词有问题」反馈（预填提建议）| 「给我画一张画」|
| 虚拟形象（M4+）| `GET/POST/PATCH/DELETE /api/avatar`、`GET /api/avatar/image` | 拍照/上传 + 5 风格（水彩/卡通/像素/剪纸/黏土）+ 角色卡可编辑 + 提示词可见；`capabilities.image_avatar=false` 时隐藏入口 | 「给我画一个我」|

### 5.1 故事数据可见范围（隐私模型）

| 数据 | 可见范围 |
|---|---|
| **英文正文**（最终故事） | **家庭可见**（所有成员可读、可打印） |
| 中文原文 `source_zh` | **仅创建者**（详情页 + 打印页 `?zh=1`；其他人即使带参数也不显示） |
| 原始录音（原声） | 仅本人 |
| 朗读记录 / 趋势 / 单条回放 | 仅朗读者本人（家长看孩子故事显示的是"你自己读过 N 次"） |
| 整段拼接朗读回放 | 仅朗读者本人（缓存按用户隔离 `story-audio/<userId>/<materialId>.wav`） |
| 复述记录 | 仅复述者本人 |
| 插画 / 提示词 | 家庭可见 |

---

### 5.2 插画总开关（成本控制）

`users.auto_illustrate` = **插画功能总开关**（默认关）：
- 关：保存不自动画；故事详情**无生成按钮**（显示「插画功能已关闭 + 去设置」）；API 403 `policy_disabled`
- 开：手动可画 + 保存后自动画
- 图片服务未配置：按钮 disabled + 提示

---

## 6. 盲测 / 诊断 / 复习

| 页面 | 接口 | 要点 | 儿童差异 |
|---|---|---|---|
| 盲测 | `POST /api/blind-tests`、`POST /api/attempts/async`（带 blind_test_id）、`POST /api/blind-tests/:id/finish`、**`DELETE /api/blind-tests/:id`**（取消）| 异步、不显示分数；**取消后该轮作废**（in_progress 消失、不进周报、下次为全新一轮）；周报「进行中」卡片有「取消这轮盲测」（二次确认）| 「不想测了就取消～」|
| 盲测周报 | `GET /api/blind-tests` | 只统计已评分，显示待评分条数 | 分数仅家长 |
| 发音诊断 | `GET /api/diagnosis` | 最弱音素、掌握度、建议 | 不显示 IPA |
| 错音本 | `GET /api/review` | SRS 卡片 | — |

## 7. 家长面板 / 设置

| 页面 | 接口 | 要点 |
|---|---|---|
| 家长汇总 🔒 | `GET /api/parent/summary` | 使用时长、趋势、掌握度（**仅本家庭**）|
| **家庭成本 🔒** | `GET /api/cost/summary?month=` | 「💰 本月成本」：总金额 + LLM/图片/TTS/ASR 分项 + 成员明细 + 近 7 天；单价可配置 |
| 提建议 | `POST /api/suggestions`（所有人）；`GET /api/suggestions` 🔒 | 家长集中查看 + 导出 Markdown |
| 设置 | `GET/PATCH /api/settings` | **卡通插画自动生成开关（默认关）**、**性别**、**音色（9 种+试听）**、**故事句子数（3–12 / 角色默认）**、**单词显示音标（成人开/儿童关）**、语速、每日时长、免费聊开关 |
| 健康检查 | `GET /api/health` | 显示「服务降级」提示（`voice.capabilities`、`degraded`）|

## 9. 点单词显示音标（全页面）

| 页面 | 可点位置 | 接口 | 儿童差异 |
|---|---|---|---|
| 跟读练习 | 句子题目、列表、词级反馈 `WordBars` 的每个词 | `GET /api/words/:word`（LRU）、批量 `GET /api/words?words=` | 同成人（也能看音标）|
| 连读模式 | 当前大字句 | 同上 | 同上 |
| 对话训练 | 助手/用户消息（实时 + 历史详情 SSR）| 同上 | 同上 |
| 故事模式 | 详情英文全文（SSR）、改写预览 | 同上 | 同上 |
| 发音诊断 | `error_words` 最差单词 | 同上 | 同上 |

**交互**：点词 → 下方浮层（PC 自动上下避让 / 窄屏底部 sheet）：**`think  /θɪŋk/  ✕`（只显示音标，没有发音按钮）**；
多变体显示小字「其它读音」；无音标 → 「暂无音标」；同一时刻只开一个；Esc/滚屏/点空白关闭。
**儿童策略**：儿童也能看音标（API 同样返回 IPA）；设置「单词显示音标」默认开（所有人），关闭后浮层提示「音标已关闭」；
**SSR 始终零 IPA**（音标只在点击后经 API 下发）。

---

## 8. 全局状态（每屏都要处理）

| 状态 | 处理 |
|---|---|
| loading | 骨架/转圈 + 文案（「生成中… 约 10 秒」）|
| empty | 人话 + 主操作（「还没有故事，讲一个吧」）|
| error | 可读文案 + 重试 |
| degraded | 琥珀提示条（「语音服务暂时不可用」）|
| offline | 顶部提示「网络不可用，已显示缓存」|
| 401 | 跳登录（保留原页面意图，登录后返回）|

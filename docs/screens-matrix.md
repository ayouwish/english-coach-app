# 页面 × 接口 × 双端对齐矩阵

图例：✅ 客户端必须实现 · 🔒 仅家长 · 🧒 儿童模式差异 · 🆕 依赖【待后端新增】

## 1. 登录与账号

| 页面 | 接口 | 说明 | 儿童差异 |
|---|---|---|---|
| 登录 | `POST /api/auth/token`（Bearer）、`GET /api/auth/me` | 邮箱+密码 → access(1h)+refresh(30d)；网络层单飞刷新；退出调 `/api/auth/revoke` | 用**演示账号快捷按钮**（只填邮箱，不猜密码）|
| 退出 | `POST /api/auth/revoke`（+ 清本地 token） | 吊销 refresh；清 Keychain/Asset Store 与缓存 | — |
| 修改我的密码（🆕 web 侧已排 task-59）| `POST /api/auth/password` | 需当前密码 | 文案口语化 |
| 家庭成员 🔒 | `GET/POST /api/family/members`、`PATCH`、`POST .../password` | 建账号/改水平（A1–C1）/重置密码 | 儿童不可见 |

## 2. 跟读练习

| 页面 | 接口 | 要点 | 儿童差异 |
|---|---|---|---|
| 语料列表 | `GET /api/sentences?level=` | 600 句，A1/A2/B1/B2 | 默认自己账号的 level |
| 练习详情 | `GET /api/sentences/:id` | 文本 + 翻译 + 焦点音素 | 不显示 IPA |
| 录音评测 | `POST /api/attempts`（multipart）| 同步；返回音素/词/语调/反馈 | 不显示低分，改用鼓励 |
| 重试评测 | `POST /api/attempts/:id/retry` | 不重录 | — |
| 示范音 | `POST /api/tts` | `rate=slow/normal`，`format=wav` | 默认 slow |
| 录音回放 | `GET /api/audio/:id` | — | — |

## 3. 连读模式

| 页面 | 接口 | 要点 |
|---|---|---|
| 选来源 | `GET /api/sentences`、`GET /api/materials?kind=page`、`POST /api/ocr`（拍照）| 语料 / 我的书页 / 自己输入 / 拍照 |
| 逐句提交 | `POST /api/attempts/async` | 立即返回，不阻塞 |
| 轮询进度 | `GET /api/attempts/status?ids=` | 1–2s，显示 待评分→评分中→分数 |
| 汇总 | 本地聚合 | 平均分、最差 2–3 句、鼓励语 |

## 4. 对话训练

| 页面 | 接口 | 要点 | 儿童差异 |
|---|---|---|---|
| 场景列表 | `GET /api/chat/scenarios` | — | 大卡片 |
| 开始会话 | `POST /api/chat/sessions` | — | — |
| 一轮对话 | ① `POST /api/asr` ② `POST /api/chat/sessions/:id/turn`（multipart：text 必填 + audio）③ `POST /api/tts` | 后端**没有**一体化接口，必须三步；turn 只返回助手文本 | — |
| 会话历史 | `GET /api/chat/sessions`、`GET /api/chat/sessions/:id`、**`GET /api/chat/sessions/:id/messages`** | `pron` 由 **messages** 接口返回（后台评分，轮询补齐）；家长看分数，儿童只看鼓励 | 不显示分数 |

## 5. 故事模式

| 页面 | 接口 | 要点 | 儿童差异 |
|---|---|---|---|
| 中文输入 | `POST /api/asr?language=zh-CN` | 🎤 说中文；也可文字 | 大输入框 |
| 生成英文 | `POST /api/story/rewrite` | `level` 取账号 CEFR（A1–C1）；返回 readability | 文案口语化 |
| 保存 | `POST /api/materials`（`kind=story`）| — | — |
| 故事集 | `GET /api/materials?kind=story` | 按日期分组、连续天数、只看我的 | 不显示分数 |
| 故事详情 | `GET /api/materials/:id` | 英文全文 + 录音回放 + 复述记录 | 分数仅家长 |
| 复述 | `POST /api/story/retell` | 覆盖度，不评发音分 | 只看鼓励 |
| 插画 | `POST /api/story/:id/illustrate` | 每天一张；**自动带用户的 `character_desc` + `avatar_style`**；失败可见；插画下方显示 `prompt_used` + 「这个提示词有问题」反馈（预填提建议）| 「给我画一张画」|
| 虚拟形象（M4+）| `GET/POST/PATCH/DELETE /api/avatar`、`GET /api/avatar/image` | 拍照/上传 + 5 风格（水彩/卡通/像素/剪纸/黏土）+ 角色卡可编辑 + 提示词可见；`capabilities.image_avatar=false` 时隐藏入口 | 「给我画一个我」|

## 6. 盲测 / 诊断 / 复习

| 页面 | 接口 | 要点 | 儿童差异 |
|---|---|---|---|
| 盲测 | `POST /api/blind-tests`、`POST /api/attempts/async`（带 blind_test_id）、`POST /api/blind-tests/:id/finish` | 异步、不显示分数 | — |
| 盲测周报 | `GET /api/blind-tests` | 只统计已评分，显示待评分条数 | 分数仅家长 |
| 发音诊断 | `GET /api/diagnosis` | 最弱音素、掌握度、建议 | 不显示 IPA |
| 错音本 | `GET /api/review` | SRS 卡片 | — |

## 7. 家长面板 / 设置

| 页面 | 接口 | 要点 |
|---|---|---|
| 家长汇总 🔒 | `GET /api/parent/summary` | 使用时长、趋势、掌握度 |
| 提建议 | `POST /api/suggestions`（所有人）；`GET /api/suggestions` 🔒 | 家长集中查看 + 导出 Markdown |
| 设置 | `GET/PATCH /api/settings` | TTS 音色/语速、每日时长、免费聊开关 |
| 健康检查 | `GET /api/health` | 显示「服务降级」提示（`voice.capabilities`、`degraded`）|

## 8. 全局状态（每屏都要处理）

| 状态 | 处理 |
|---|---|
| loading | 骨架/转圈 + 文案（「生成中… 约 10 秒」）|
| empty | 人话 + 主操作（「还没有故事，讲一个吧」）|
| error | 可读文案 + 重试 |
| degraded | 琥珀提示条（「语音服务暂时不可用」）|
| offline | 顶部提示「网络不可用，已显示缓存」|
| 401 | 跳登录（保留原页面意图，登录后返回）|

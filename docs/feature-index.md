# 功能索引（Feature Index）· 功能 → 接口 → 页面 → 文档

> **用途**：客户端开发时按功能查"要调哪些接口、对应哪个页面、文档在哪"。
> **维护规则**：后端每上线一个新功能/端点，**必须在同一次变更里更新本文件 + 相关文档**（见 `README.md` §0 的同步规则）。
> **按批次回溯/验收** 见 [`release-notes.md`](release-notes.md)。
> 最后更新：2026-11-04

图例：✅ 已实现（后端/Web 可用） · 🔄 进行中 · 📋 设计就绪未实现 · 📱 移动端 M0 已写代码（未编译）

---

## 1. 账号与登录

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| Bearer Token 登录 | `POST /api/auth/token` | ✅ | README §6.1、`adr/0002-bearer-token.md` |
| Token 刷新（一次性轮换） | `POST /api/auth/refresh` | ✅ | 同上（**客户端必须单飞刷新**）|
| 退出/吊销 | `POST /api/auth/revoke` | ✅ | 同上 |
| 当前用户 | `GET /api/auth/me` | ✅ | 同上 |
| 改密码（家长重置，含自己） | `POST /api/family/members/:id/password` | ✅ | `screens-matrix.md` §1 |
| 改密码（自助，需旧密码） | `POST /api/auth/password` | 📋 可选增强 | `screens-matrix.md` §1 |
| 多账号/家庭成员 | `GET/POST /api/family/members`、`PATCH` | ✅ | `screens-matrix.md` §1 |
| 账号偏好 | `GET/PATCH /api/settings` | ✅ | README §6.1、§3.3（`auto_illustrate`/`gender`/`tts_voice`/`story_sentences`）|

## 2. 跟读练习

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 语料列表（600 句 A1–B2） | `GET /api/sentences?level=` | ✅ | README §6.2 |
| 句子详情 | `GET /api/sentences/:id` | ✅ | 同上 |
| 同步评测（音素/词/语调） | `POST /api/attempts` | ✅ | README §6.2、`acceptance-checklist.md` §C |
| 重试评分 | `POST /api/attempts/:id/retry` | ✅ | 同上 |
| 录音回放 | `GET /api/audio/:id` | ✅ | 同上 |
| 示范音 | `POST /api/tts`、`GET /api/tts/voices` | ✅ | README §6.6 |
| **练习游标（继续上次）** | `GET/PUT /api/practice/cursor`、页面 `/practice` | ✅ | `design-overview.md` §5.1 |
| **单句历史 + 进步曲线** | `GET /api/sentences/:id/attempts`、页面 `/practice` 结果区 | ✅ | `design-overview.md` §5.1 |
| **点单词看音标（全页面，仅音标无发音）** | `GET /api/words/:word`、`GET /api/words?words=`（web 代理 voice `/v1/words/ipa`）| ✅ | README §6.7、`design-overview.md` §5.8b、`screens-matrix.md` §9 |

## 3. 连读模式

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 异步提交 | `POST /api/attempts/async` | ✅ | README §6.2 |
| 轮询进度 | `GET /api/attempts/status?ids=` | ✅ | 同上 |
| 汇总 + 鼓励语 | 本地聚合 | ✅ | `design-overview.md` §5.2 |
| **再读一遍（汇总页）** | 页面 `/flow` 主按钮 `flow-reread` | ✅ | README §6.2、`design-overview.md` §5.2 |
| 拍照识别书页 | `POST /api/ocr` → `POST /api/materials?kind=page` | ✅ | README §6.6 |

## 4. 对话训练

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 场景列表（内置 + 自定义） | `GET /api/chat/scenarios[?include_child=1]` | ✅ | README §6.3、`screens-matrix.md` §4 |
| 自定义场景 CRUD | `POST /api/chat/scenarios`、`PATCH/DELETE /:id` | ✅ | 同上 |
| 场景随机变体（variation） | `POST /api/chat/sessions` 随机抽 + turn 带 `scenario.variation` | ✅ | 同上、`screens-matrix.md` §4 |
| 开始/结束会话 | `POST /api/chat/sessions`、`POST /:id/end` | ✅ | README §6.3 |
| 一轮对话（三步） | `/api/asr` → `POST /:id/turn` → `POST /api/tts` | ✅ | README §6.3、`design-overview.md` §5.3 |
| 消息（校正 + 发音） | `GET /api/chat/sessions/:id/messages` | ✅ | 同上 |
| 不限轮数 | `CHAT_MAX_TURNS=0` | ✅ | `screens-matrix.md` §4 |
| **整段对话回放** | `GET /:id/audio/status`、`GET /:id/audio[?force=1]` | ✅ | README §6.3、`design-overview.md` §5.3 |
| 历史会话列表/详情 | `GET /api/chat/sessions`、`/:id` | ✅ | `screens-matrix.md` §4 |
| 家长/儿童场景分离 + 「再看小朋友的场景」开关 | `?include_child=1`（仅成人生效） | ✅ | `screens-matrix.md` §4 |

## 5. 故事模式

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 中文语音转文字 | `POST /api/asr?language=zh-CN[&provider=]`（默认智谱 GLM-ASR） | ✅ | README §6.4、§3.3 |
| **原始录音留存（先落盘再转录）** | `POST /api/story/recordings`、`POST /:id/transcribe`、`GET /`、`GET /:id/audio` | ✅ | README §6.4、`design-overview.md` §5.4 |
| 中文 → 分级英文改写 | `POST /api/story/rewrite`（`level` A1–C1、`max_sentences` 3–12、`tense` auto/past/present） | ✅ | README §6.4、§3.3 |
| **叙事时态（默认过去时）** | `POST /api/story/rewrite` 的 `tense` + `warnings:["tense_mismatch"]` | ✅ | 同上 |
| 人性化句子数默认 | 页面 `/story` + `/api/settings.story_sentences` | ✅ | 同上 |
| 保存故事（回填 recording_id） | `POST /api/materials`（`kind=story`） | ✅ | README §6.4 |
| 故事集列表/筛选 | `GET /api/materials?kind=story` | ✅ | 同上 |
| **原声回顾（我当时讲的原话）** | 页面 `/story/[id]`、`GET /api/materials/:id` | ✅ | `design-overview.md` §5.4 |
| **整段朗读回放** | `GET /api/story/:id/audio/status`、`/audio` | ✅ | 同上 |
| 复述评估（覆盖度，不评发音分） | `POST /api/story/retell` | ✅ | README §6.4 |
| 插画（默认关，可在设置开自动） | `POST /api/story/:id/illustrate`、`/api/settings.auto_illustrate` | ✅ | README §6.4、§1.3 |
| 提示词可见 + 反馈 | 页面 `/story/[id]`（`prompt_used` + 提建议） | ✅ | `design-overview.md` §5.5 |
| **打印（单篇·整页）** | 页面 `/story/[id]/print[?zh=1&lines=1]` | ✅ | README §6.4、`design-overview.md` §5.7 |
| **打印（单篇·A5 卡片）** | 页面 `/story/[id]/print?layout=card[&zh=1&lines=1]` | ✅ | 同上 |
| **打印（多选故事集）** | 页面 `/story/print?ids=…[&zh=1&lines=1]` | ✅ | 同上 |

## 6. 虚拟形象 / 音色

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 预置形象库（12 角色 × 5 风格） | `GET /api/avatar/presets` | ✅ | README §6.6、`design-overview.md` §5.5 |
| 选择/编辑/清空形象 | `GET/POST/PATCH/DELETE /api/avatar` | ✅ | 同上 |
| 形象图片 | `GET /api/avatar/image` | ✅ | 同上 |
| 性别与形象推荐 | `PATCH /api/settings {gender}` | ✅ | `screens-matrix.md` §7 |
| 音色（9 种，含试听） | `GET /api/tts/voices`、`POST /api/tts` | ✅ | README §6.6 |
| **单词音标开关**（成人默认开/儿童默认关）| `PATCH /api/settings {show_word_ipa}` | ✅ | `screens-matrix.md` §7 |
| 照片生成形象（隐私策略关闭） | `POST /api/avatar`（照片）→ 403 `policy_disabled` | ✅ | README §1.4 |

## 7. 诊断 / 盲测 / 复习

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 分层诊断（单句/批次/最近/全部） | `GET /api/diagnosis?scope=…` | ✅ | README §6.5、`design-overview.md` §5.6 |
| 对子去重（a→b / b→a 合并） | 同上（`contrasts` 已去重） | ✅ | 同上 |
| 错音本（SRS） | `GET /api/review` | ✅ | README §6.5 |
| 盲测（异步） | `POST /api/blind-tests`、`/api/attempts/async`、`POST /:id/finish` | ✅ | README §6.5 |

## 8. 家长 / 运维

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 家长汇总 | `GET /api/parent/summary` | ✅ | README §6.6 |
| 提建议 / 导出 | `POST /api/suggestions`、`GET /api/suggestions`、`/export` | ✅ | 同上 |
| 部署自查 | `GET /api/health`（features）、`GET /v1/health`（capabilities） | ✅ | README §2.4、§3 |
| 清理某账号测试数据 | `web/scripts/cleanup-user-data.mjs` | ✅ | `english-coach/docs/deployment.md` §6.5 |

---

## 9. 变更同步清单（每次新功能必须过一遍）

新增/修改功能时，按顺序检查：

1. **接口**：`english-coach/docs/api-contract.md`（voice/契约）+ 若涉及 web 层，更新本仓库 `README.md` §6 与本文件
2. **页面/交互**：`docs/screens-matrix.md`（页面 × 接口 × 儿童差异）
3. **流程说明**：`docs/design-overview.md` §5（若新增业务流）
4. **迁移**：`english-coach/web/migrations/`（幂等；更新 README §3.2 迁移清单）
5. **配置**：`english-coach/deploy/.env.example` + 本仓库 README §3.3 变量表
6. **验收**：`english-coach/web/scripts/check-*.mjs` 加断言；必要时更新 `docs/acceptance-checklist.md`
7. **两端提示**：若影响移动端，更新 `ios/docs/*`、`hos/docs/*` 中对应页面/接口章节
8. **本文件**：把新功能登记到对应分组（状态 ✅/🔄/📋）

---

## 10. Android 端（Kotlin/Compose）实现状态

> **Android 版本以 [`android-feature-list.md`](android-feature-list.md) 为详细清单**（页面级功能点、接口总表、文档↔实现偏差、M1/M2 范围与页面级验收）。
> 本章只是"功能 → Android 页面 → 状态"的速查；页面范围与签名以 [`../android/CONTRACT.md`](../android/CONTRACT.md) §5 为准。
> 状态口径：**✅ 已实现**（代码在工作区且行为与鸿蒙一致）· **🚧 进行中**（已排期/已开工，尚未完成）· **⏭️ 延后**（本版不做）。
> 快照时间：2026-11-04（Android 侧基础设施/组件/导航已落地，页面 UI 正在实现中）。

### 10.1 基础设施与全局能力

| 功能 | 对应 Android 页面/模块 | 状态 | 章节 |
|---|---|---|---|
| Bearer Token 登录 / 单飞刷新 / 吊销 | `core/net/ApiClient.kt`、`core/session/TokenStore.kt` | ✅ 已实现 | §1.1 |
| 记住密码 + 冷启动自动登录 | `core/session/CredentialStore.kt` | ✅ 已实现 | §2.1 |
| 会话/角色/儿童模式（`LocalIsChild`） | `core/session/SessionStore.kt`、`ui/design/EcTheme.kt` | ✅ 已实现 | §1.2 |
| 错误码映射（成人/儿童两套文案） | `core/error/UiError.kt` | ✅ 已实现 | §1.6 |
| 录音（m4a/16k/mono/65kbps）与播放互斥 | `core/audio/`（`MicPermission`、`Voices` 已落地；`AudioController` 待补） | 🚧 进行中 | §1.4、§1.5 |
| 内置 9 音色常量 | `core/audio/Voices.kt` | ✅ 已实现 | §2.13 |
| 点单词看音标 | `ui/component/WordText.kt`、`core/service/DictionaryService.kt` | ✅ 已实现 | §1.8 |
| 能力开关缓存（image/ocr/avatar_presets） | 由 `AppGraph` + `/health` 服务层承接（页面接入中） | 🚧 进行中 | §1.7 |
| 今日用量与限额（含前置禁用） | `SessionStore` + 各页面 | 🚧 进行中 | §1.3 |
| 离线语料缓存 / TTS LRU / 提交队列 | — | ⏭️ 延后（鸿蒙亦未实现） | §1.9、§5.2 |
| 打印 / 导出文件下载 | 移动端改为"复制全文 / 复制 Markdown" | ⏭️ 延后 | §2.5、§2.11 |

### 10.2 页面

| 功能（页面） | 对应 Android 页面 | 状态 | 章节 |
|---|---|---|---|
| 登录（含服务器地址/健康检查/演示账号） | `ui/page/auth/LoginScreen.kt` | 🚧 进行中 | §2.1 |
| 跟读（卡片流/示范音/评测/结果区） | `ui/page/practice/PracticeScreen.kt` | 🚧 进行中 | §2.2 |
| 跟读详细结果（全屏） | 契约未列 → 建议页内 sheet 或补 `PRACTICE_RESULT` 路由 | 🚧 待定（见 §2.2 备注） | §2.2 |
| 连读 setup/running | `ui/page/flow/FlowScreen.kt` | 🚧 进行中 | §2.3 |
| 连读汇总（再读一遍/鼓励语/本批复述入口） | `ui/page/flow/FlowSummaryScreen.kt` | 🚧 进行中 | §2.3 |
| 对话场景列表（含自定义入口/受众开关） | `ui/page/chat/ChatScenariosScreen.kt` | 🚧 进行中 | §2.4 |
| 对话会话（纯语音三步/整段回放） | `ui/page/chat/ChatSessionScreen.kt` | 🚧 进行中 | §2.4 |
| 对话历史 / 详情 / 自定义场景 | `ChatHistoryScreen.kt`、`ChatDetailScreen.kt`、`ChatCustomScreen.kt` | 🚧 进行中 | §2.4 |
| 故事列表 / 讲故事 / 详情 / 复述 | `StoryHomeScreen.kt`、`StoryRecordScreen.kt`、`StoryDetailScreen.kt`、`StoryReviewScreen.kt` | 🚧 进行中 | §2.5 |
| 故事原声回放 + 复述记录持久化 | 同上（线上无接口，仅内存态） | ⏭️ 延后 | §2.5、§4 D-08/D-09 |
| 盲测（开始/进行/结束/周报） | `ui/page/stats/BlindTestScreen.kt` | 🚧 进行中 | §2.6 |
| 发音诊断（recent/all + 强化练习跳转） | `ui/page/stats/DiagnosisScreen.kt` | 🚧 进行中 | §2.7 |
| 错音本（4 档评分） | `ui/page/stats/ReviewScreen.kt` | 🚧 进行中 | §2.8 |
| 家长面板（403 兜底/盲测环比/剩余时长） | `ui/page/account/ParentScreen.kt` | 🚧 进行中 | §2.9 |
| 家庭成员（CRUD + 重置密码） | `ui/page/account/FamilyScreen.kt` | 🚧 进行中 | §2.10、§2.16 |
| 建议箱（5/3 分类 + 导出复制） | `ui/page/account/SuggestionsScreen.kt` | 🚧 进行中 | §2.11 |
| 虚拟形象（预置库/风格/性别筛选） | `ui/page/account/AvatarScreen.kt` | 🚧 进行中 | §2.12 |
| 音色（9 内置 + 试听 + 保存） | `ui/page/account/VoicesScreen.kt` | 🚧 进行中 | §2.13 |
| 设置（偏好/地址/清缓存/退出） | `ui/page/account/SettingsScreen.kt` | 🚧 进行中 | §2.14 |
| 服务状态（features/capabilities/force） | `ui/page/account/HealthScreen.kt` | 🚧 进行中 | §2.15 |
| 独立"修改密码"页 | —（并入家庭成员页） | ⏭️ 延后 | §2.16 |
| 句子列表页 | 契约 §5 有 `Routes.SENTENCES`；鸿蒙已弃用（改为卡片滑动） | ⏭️ 延后（建议不做） | §2.0、§2.2 |
| 应用壳（启动三态 / 5 Tab / 跨 Tab 跳转） | `ui/AppRoot.kt`、`ui/HomeScreen.kt`、`ui/nav/AppNavHost.kt`、`ui/nav/Routes.kt` | 🚧 进行中 | §2.0 |

### 10.3 数据层（DTO / Service）

| 功能 | 对应 Android 模块 | 状态 | 章节 |
|---|---|---|---|
| 8 个 Service（Auth/Practice/Flow/Chat/Story/Account/Stats/Dictionary） | `core/service/*.kt` | ✅ 已实现 | §3 |
| 6 组 DTO（Dtos/Flow/Chat/Story/Stats/Account） | `core/net/dto/*.kt` | ✅ 已实现 | §3 |
| 线上不存在的接口规避（cursor / 单句 attempts / tts voices / story recordings） | 已按鸿蒙方案移植（本地游标 / `/attempts?limit` / 常量 / 直接 `/asr`） | ✅ 已实现（服务层） | §3.6、§4 D-01/02/08/10 |
| 盲测同步提交 + 无分数 | `PracticeService.evaluate(..., blindTestId)` | ✅ 已实现（服务层） | §4 D-06 |

> 变更规则同 §9：Android 侧新增/改变行为时，先改 `android-feature-list.md`，再回填本表状态。


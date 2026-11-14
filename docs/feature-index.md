# 功能索引（Feature Index）· 功能 → 接口 → 页面 → 文档

> **用途**：客户端开发时按功能查"要调哪些接口、对应哪个页面、文档在哪"。
> **维护规则**：后端每上线一个新功能/端点，**必须在同一次变更里更新本文件 + 相关文档**（见 `README.md` §0 的同步规则）。
> **按批次回溯/验收** 见 [`release-notes.md`](release-notes.md)。
> 最后更新：2026-11-05（ROUND2：Android 补齐雷达/全屏结果/滑动切句/历史回放、VoicePrefs/CapabilityCache 统一、离线失败队列 + 待补评分页、故事分组与持久化、账号页缺口）
>
> 图例：✅ 已实现（后端/Web 可用） · 🔄 进行中 · 📋 设计就绪未实现 · 📱 移动端（Android 代码已落地，状态见 §10；本机无 Android SDK，未编译验证）

---

## 1. 账号与登录

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| Bearer Token 登录 | `POST /api/auth/token` | ✅ | README §6.1、`adr/0002-bearer-token.md` |
| Token 刷新（一次性轮换） | `POST /api/auth/refresh` | ✅ | 同上（**客户端必须单飞刷新**）|
| 退出/吊销 | `POST /api/auth/revoke` | ✅ | 同上 |
| 当前用户 | `GET /api/auth/me` | ✅ | 同上 |
| 改密码（家长重置，含自己） | `POST /api/family/members/:id/password` | ✅ | `screens-matrix.md` §1 |
| 改密码（自助，需旧密码） | `POST /api/auth/password` | ✅ | `screens-matrix.md` §1 |
| 多账号/家庭成员 | `GET/POST /api/family/members`、`PATCH` | ✅ | `screens-matrix.md` §1 |
| **多家庭（邀请制）** | `POST /api/auth/register`（`invite_code` 加入 / `new_family_code` 建新家庭）；`GET/POST /api/family/family-invites`（管理员名额制）| ✅ | README §6.1b、`screens-matrix.md` §1 |
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
| **开场白中文** | `scenario.opening_zh` / `messages[0].text_zh`（76 条文本映射 + 自定义场景可填）；回填脚本 `backfill:opening-zh` | ✅ | 同上 |
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
| **原声回顾（我当时讲的原话）** | 页面 `/story/[id]`、`GET /api/materials/:id` | ✅（**仅创建者可见**） | `design-overview.md` §5.4 |
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
| **盲测取消（软取消）** | `DELETE /api/blind-tests/:id`（三态；幂等；他人 404；已结束 409）| ✅ | `screens-matrix.md` §6 |

## 8. 家长 / 运维

| 功能 | 接口 / 页面 | 状态 | 文档 |
|---|---|---|---|
| 家长汇总 | `GET /api/parent/summary` | ✅ | README §6.6 |
| **家庭成本台账** | `GET /api/cost/summary?month=`、`/parent` 成本卡（LLM/图片/TTS/ASR，按家庭）| ✅ | README §6.1b、§3.3 |
| **后台管理员** | `/admin/login`、`/admin`（独立 `ADMIN_PASSWORD` 登录）；成本看板 + 邀请码管理 | ✅ | `screens-matrix.md` §7、README §3.3 |
| **管理员成本看板（跨家庭）** | `GET /api/admin/costs`（独立管理员会话；LLM tokens/图片/金额/按家庭/按天/明细）| ✅ | 同上 |
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
> 状态口径：**✅ 已实现**（代码在工作区且已按 Android 实际落地；与鸿蒙的有意取舍见 `android-feature-list.md` §4.1）· **🚧 部分实现**（主体可用，但缺项已写清）· **⏭️ 延后**（本版不做）。
> 快照时间：**2026-11-05（ROUND2 最终）**——`android/CONTRACT.md` §5 的全部页面 + ROUND2 §4 补齐能力已落地；本表按 `android/app/src/main/java/top/dreamsearch/englishcoach/ui/**`、`core/**` 逐项复核（逐条证据见 `android/QA_ROUND2.md`）。

### 10.1 基础设施与全局能力

| 功能 | 对应 Android 页面/模块 | 状态 | 章节 |
|---|---|---|---|
| Bearer Token 登录 / 单飞刷新 / 重放一次 / 吊销 | `core/net/ApiClient.kt`、`core/service/AuthService.kt`、`core/session/TokenStore.kt` | ✅ 已实现 | §1.1 |
| 启动恢复 / 登录门禁 / 三态 | `ui/AppRoot.kt`（loading / 全屏错误+重试+改服务器地址 / 登录页；自动登录也在这一层） | ✅ 已实现 | §1.1、§2.0 |
| 记住密码 + 冷启动自动登录（加密） | `core/session/CredentialStore.kt`、`core/config/AppConfig.kt`；**默认关**（A-06，文案待统一） | ✅ 已实现 | §2.1 |
| 会话/角色/儿童模式（`LocalIsChild`） | `core/session/SessionStore.kt`、`ui/design/EcTheme.kt` | ✅ 已实现 | §1.2 |
| 错误码映射（成人/儿童两套文案） | `core/error/UiError.kt` | ✅ 已实现 | §1.6 |
| 录音（m4a/16k/mono/64kbps）与播放互斥 | `core/audio/AudioController.kt`（+ `MicPermission.kt`） | ✅ 已实现 | §1.4、§1.5 |
| 内置 9 音色常量 | `core/audio/Voices.kt` | ✅ 已实现 | §2.13 |
| 点单词看音标 | `ui/component/WordText.kt`、`core/service/DictionaryService.kt` | ✅ 已实现 | §1.8 |
| 能力开关（image/ocr/avatar_presets/audio_concat/word_ipa） | `core/content/CapabilityCache.kt`（5 分钟 TTL、并发单飞、失败不抛、缺省 true），接线：OCR 入口/故事插画与自动插图/「我的」与设置页形象入口 | ✅ 已实现（ROUND2） | §1.7 |
| 今日用量与限额（前置禁用） | `SessionStore` + 跟读/连读/对话/盲测/故事/复述各 VM | ✅ 已实现（比鸿蒙更严，D-12） | §1.3 |
| TTS 先落盘再播放 / 播放互斥 | `AudioController.playBytes/playFile`、`CacheStore.ttsFile/audioFile` | ✅ 已实现 | §1.5 |
| 示范音语速/音色偏好 | `core/audio/VoicePrefs.kt` 本机镜像；跟读/连读示范音、听鼓励、对话朗读统一 `voicePrefs.resolve(isChild)` | ✅ 已实现（ROUND2） | §1.5 |
| 手写 DI + ViewModel 工厂（无 Hilt/Retrofit/Coil） | `core/di/AppGraph.kt`、`core/di/VmFactory.kt` | ✅ 已实现（A-05） | §1 |
| 设计 token / 主题 / 组件库 | `ui/design/*`、`ui/component/*`（ROUND2 新增 `EcRadarChart`） | ✅ 已实现 | §0.4 |
| 离线能力：TTS/回放 LRU、失败录音队列、待补评分页 | `CacheStore`（trimTtsCache 200MB / trimAudioCache 300MB / 最近结果 50 条）、`core/offline/PendingUploadQueue.kt`、`ui/page/offline/PendingUploadsScreen.kt` + `Routes.PENDING_UPLOADS` | ✅ 已实现（ROUND2；语料全量 JSON 缓存仍 ⏭️） | §1.9、§5.2 |
| 打印 / 导出文件下载 | 移动端改为「弹层展示 + 复制」；故事详情复制全文已补（ROUND2）；打印/文件下载 ⏭️ | 🚧 部分（平台限制） | §2.5、§2.11 |

### 10.2 页面

| 功能（页面） | 对应 Android 页面 | 状态 | 章节 |
|---|---|---|---|
| 登录（含服务器地址/健康检查/演示账号） | `ui/page/auth/LoginScreen.kt` + `LoginViewModel.kt`（demo 填邮箱+密码 A-07；记住密码默认关 A-06） | ✅ 已实现 | §2.1 |
| 跟读（卡片流/示范音/评测/**页内结果 + 全屏 overlay**） | `ui/page/practice/PracticeScreen.kt` + `PracticeViewModel.kt` + `PracticeModels.kt`（**ROUND2**：能力雷达 `EcRadarChart`、全屏结果 overlay、历史逐条回放 `audioByUrl`、`HorizontalPager` 滑动切句、`VoicePrefs`、失败入队） | ✅ 已实现 | §2.2 |
| 跟读详细结果（全屏） | 页内 **overlay**（不新增 `PRACTICE_RESULT` 路由）：总分/子项/雷达/逐词/纠错/语调/单句历史 + 关闭/重试评测/下一句/BackHandler | ✅ 已实现（ROUND2） | §2.2、A-01 |
| 句子列表页（高亮本地游标当前句） | `ui/page/practice/SentenceListScreen.kt` + `SentenceListViewModel.kt`（`Routes.SENTENCES` 已接线） | ✅ 已实现（A-12） | §2.0、§2.2 |
| 连读 setup/running | `ui/page/flow/FlowScreen.kt` + `FlowViewModel.kt` + `FlowModels.kt`（OCR 走 `CapabilityCache`；失败句入待补评分队列） | ✅ 已实现 | §2.3 |
| 连读汇总（再读一遍/鼓励语/批次诊断/**复述入口**） | `ui/page/flow/FlowSummaryScreen.kt` + `FlowSummaryViewModel.kt`（**ROUND2**：故事来源时「📝 复述这个故事」→ `onOpenReview(materialId)`；「待补评分 N 条」入口；`VoicePrefs`） | ✅ 已实现 | §2.3 |
| 对话场景列表（含自定义入口/受众开关） | `ui/page/chat/ChatScenariosScreen.kt` + `ChatScenariosViewModel.kt` | ✅ 已实现 | §2.4 |
| 对话会话（纯语音三步/整段回放） | `ui/page/chat/ChatSessionScreen.kt` + `ChatSessionViewModel.kt` + `ChatModels.kt` | ✅ 已实现（建议 chips 只朗读不发送，A-14 / §2.4） | §2.4 |
| 对话历史 / 详情 / 自定义场景 | `ChatHistoryScreen.kt`、`ChatDetailScreen.kt`、`ChatCustomScreen.kt`（+ 各自 VM） | ✅ 已实现 | §2.4 |
| 故事列表 / 讲故事 / 详情 / 复述 | `StoryHomeScreen.kt`、`StoryRecordScreen.kt`、`StoryDetailScreen.kt`、`StoryReviewScreen.kt`（+ 4 个 VM + `StoryRuntime.kt`/`StoryUi.kt`）。**ROUND2**：今天/昨天/更早分组 + 连续天数、auto_illustrate 自动插图、保存后跳详情、详情复制全文 | ✅ 已实现 | §2.5 |
| 故事原声回放 + 复述记录（**本机持久化**） | `ui/page/story/StoryRuntime.kt`（原声路径 + `source_zh` + 最近一次复述落 `CacheStore` JSON；杀进程后可回看，文件失效只隐藏回放） | ✅ 已实现（ROUND2，D-08/D-09 的本地化方案） | §2.5 |
| **待补评分录音页（离线）** | `ui/page/offline/PendingUploadsScreen.kt` + `PendingUploadsViewModel.kt`；`Routes.PENDING_UPLOADS`；首页横幅 + 「我的」入口；列表/试听/删除/全部重试/空态 | ✅ 已实现（ROUND2） | §1.9、§2.0 |
| 盲测（开始/进行/结束/周报） | `ui/page/stats/BlindTestScreen.kt` + `BlindTestViewModel.kt`（**一页闭环**，A-02） | ✅ 已实现 | §2.6 |
| 发音诊断（recent/all/attempt/batch + 强化练习跳转） | `ui/page/stats/DiagnosisScreen.kt` + `DiagnosisViewModel.kt`（batch 优先 `NavParams.diagnosisAttemptIds`，缺参回落最近 20 条） | ✅ 已实现 | §2.7 |
| 错音本（4 档评分） | `ui/page/stats/ReviewScreen.kt` + `ReviewViewModel.kt` | ✅ 已实现 | §2.8 |
| 家长面板（403 兜底/盲测环比/剩余时长/**盲测周报入口**） | `ui/page/account/ParentScreen.kt` + `ParentViewModel.kt`（ROUND2 接 `onOpenBlindTest`） | ✅ 已实现 | §2.9 |
| 家庭成员（CRUD + 重置密码） | `ui/page/account/FamilyScreen.kt` + `FamilyViewModel.kt` + `AccountFamilyModels.kt` | ✅ 已实现（无删除成员：服务端无接口） | §2.10、§2.16 |
| 建议箱（5/3 分类 + 导出复制） | `ui/page/account/SuggestionsScreen.kt` + `SuggestionsViewModel.kt` | ✅ 已实现（导出=弹层展示+复制，无文件下载） | §2.11 |
| 虚拟形象（预置库/风格/性别筛选） | `ui/page/account/AvatarScreen.kt` + `AvatarViewModel.kt` | ✅ 已实现（无照片上传入口；`avatar_presets` 入口在 Me/Settings 置灰） | §2.12 |
| 音色（9 内置 + 试听 + 保存 + **去设置**） | `ui/page/account/VoicesScreen.kt` + `VoicesViewModel.kt`（ROUND2 接 `onOpenSettings`；保存后 `voicePrefs.syncFromAccount`） | ✅ 已实现 | §2.13 |
| 设置（偏好/地址/清缓存/退出/**本人改密弹层**） | `ui/page/account/SettingsScreen.kt` + `SettingsViewModel.kt`（ROUND2：保存后同步 `VoicePrefs`；形象入口按 `avatar_presets` 置灰） | ✅ 已实现（本人改密 A-08） | §2.14、§2.16 |
| 服务状态（features/capabilities/**force 刷新**） | `ui/page/account/HealthScreen.kt` + `HealthViewModel.kt`（ROUND2：`practice.health(force)` + `stats.healthFull(force)` 并行 + features 区块） | ✅ 已实现 | §2.15 |
| 独立「修改密码」页 | —（能力并入家庭成员页 + 设置页本人改密弹层） | ⏭️ 延后（A-08） | §2.16 |
| 应用壳（启动三态 / 5 Tab / 跨 Tab 跳转 / 待补评分横幅） | `ui/AppRoot.kt`、`ui/HomeScreen.kt`、`ui/nav/AppNavHost.kt`、`ui/nav/Routes.kt`（20 条二级路由） | ✅ 已实现 | §2.0 |

### 10.3 数据层（DTO / Service）

| 功能 | 对应 Android 模块 | 状态 | 章节 |
|---|---|---|---|
| 9 个 Service（Auth/Practice/Flow/Chat/Story/Account/Stats/Dictionary + 全局 ApiClient） | `core/service/*.kt`（`AccountService` 无 deleteMember：服务端无接口） | ✅ 已实现 | §3 |
| 6 组 DTO（Dtos/Flow/Chat/Story/Stats/Account） | `core/net/dto/*.kt`（全部 `@Serializable`、字段默认值） | ✅ 已实现 | §3 |
| 线上不存在的接口规避（cursor / 单句 attempts / tts voices / story recordings） | 已按鸿蒙方案移植（本地游标 / `/attempts?limit` / 常量 / 直接 `/asr`） | ✅ 已实现（服务层） | §3.6、§4 D-01/02/08/10 |
| 盲测同步提交 + 无分数 | `PracticeService.evaluate(..., blindTestId)`（盲测页调用） | ✅ 已实现（服务层） | §4 D-06 |
| 能力开关统一缓存（ROUND2） | `core/content/CapabilityCache.kt`（5 分钟 TTL / 单飞 / 失败不抛 / 缺省 true）；OCR、插画、自动插图、形象入口、设置页接线 | ✅ 已实现 | §1.1、§1.7 |
| 语音偏好本机镜像（ROUND2） | `core/audio/VoicePrefs.kt`（儿童强 slow + 内置 Ana；成人读账号偏好；设置/音色页保存后同步） | ✅ 已实现 | §1.2、§1.5 |
| 离线失败录音队列 + 待补评分页（ROUND2） | `core/offline/PendingUploadQueue.kt`（`enqueue/list/count/remove/clear/retryAll`，`queue.json` + 录音同目录）、`ui/page/offline/PendingUploads*`、`Routes.PENDING_UPLOADS` | ✅ 已实现 | §1.3、§1.9 |
| 缓存 LRU / 最近结果（ROUND2） | `CacheStore.trimTtsCache(200MB)`、`trimAudioCache(300MB)`、`readRecentResult/writeRecentResult/clearRecentResults`、`cleanupOnBoot` 调用 | ✅ 已实现 | §1.4 |
| 健康检查两套形状 + force | `PracticeService.health(force)`（简化版，登录/首页/设置/连读用）+ `StatsService.healthFull(force)`（全字段）；健康页两路并行 + 「强制刷新」+ features 区块 | ✅ 已实现（ROUND2 关闭 A-09） | §1.7、§2.15 |

> 变更规则同 §9：Android 侧新增/改变行为时，先改 `android-feature-list.md`，再回填本表状态。

## 11. iOS 端（SwiftUI）实现状态

> **详细清单与页面级签名以 [`../ios/docs/port-contract.md`](../ios/docs/port-contract.md) §3/§4 为准**；实现现状与验收清单见 [`../ios/README.md`](../ios/README.md) §0。
> 状态口径：**✅ 已实现（代码层）** · **⚠️ 静态校验通过但未编译/未真机** · **⏭️ 延后**
> 快照时间：**2026-11-05**——`ios/EnglishCoach/` 146 个 Swift 文件 / 约 2.79 万行；`python ios/tools/check_ios.py` → `errors=0 warnings=0`。
> **全仓 iOS 代码都处于「未编译、未真机」状态**（本机无 macOS/Xcode），下表 ✅ 只表示代码已按契约落地。

| 能力 | 对应 iOS 模块 | 状态 | 备注 |
|---|---|---|---|
| Bearer 登录 / 单飞刷新 / 重放 / 吊销 / Keychain | `Core/Session/*`、`Core/Networking/*` | ✅⚠️ | 记住登录默认关；不自动登录（共享设备安全） |
| 启动三态 / 会话过期 / 5 Tab / 22 路由 | `App/{AppRoot,RootTabView,AppEnvironment}.swift` | ✅⚠️ | 家长入口在「我的」网格，未采用角色化 Tab |
| 跟读（列表/卡片流/示范音/评测/页内结果） | `Features/Practice/*` | ✅⚠️ | 语料 24h 快照 + 离线兜底 |
| 跟读详细结果（雷达/音高/单句历史/进步曲线/点词音标） | `Features/Practice/{PracticeResultView,Components}` | ✅⚠️ | 逐词得分只显示一遍、<60 标红仅成人 |
| 连读（setup/running/汇总） | `Features/Flow/*` | ✅⚠️ | 异步提交 + 轮询 + 批次诊断 |
| 对话（场景/纯语音会话三步链路/pron 轮询/整段回放/历史/自定义） | `Features/Chat/*` | ✅⚠️ | 会话页无文本输入（产品约束） |
| 故事（列表/讲述/OCR/改写/详情/复述/插画/导出复制） | `Features/Story/*` | ✅⚠️ | 原始录音无服务端接口 → 本地 `RecordingCache` 副本 |
| 盲测 / 诊断 / 成长 / 错音本 | `Features/{BlindTest,Report}/*` | ✅⚠️ | 诊断 attempt/batch 无路由载荷，缺参兜底 |
| 我的 / 设置 / 家长 / 家庭 / 建议箱 / 形象 / 音色 / 服务状态 | `Features/{Home,Settings,Parent}/*` | ✅⚠️ | 「恢复默认」发 `null`；儿童不可达家长页 |
| 音频（录音 16k/mono/AAC 65k、播放互斥、中断/路由） | `Core/Audio/*` | ✅⚠️ | 真机音频矩阵未验 |
| 缓存（TTS 200MB / 图 100MB / 录音 300MB-7d / 语料 24h） | `Core/Storage/*` | ✅⚠️ | LRU + 用户级清理 |
| 设计系统（令牌 + 10 组件文件 + Swift Charts） | `Core/DesignSystem/*`、`Features/Shared/*` | ✅⚠️ | 深色模式/Dynamic Type 未做 |
| 媒体采集（相机/相册/HEIC→JPEG ≤5MB） | `Core/Media/*` | ✅⚠️ | 相册走 `PhotosPicker`，不申请读权限 |
| 静态校验工具 | `ios/tools/check_ios.py` | ✅ | 8 类校验 + 16 个负向自测用例 |
| 锁屏控制 / iPad 分栏 / 深色 / 推送 / Widget / 离线补交 | — | ⏭️ | 见 `ios/docs/roadmap.md` M4 |

> iOS 侧变更规则：先改 `ios/docs/port-contract.md`（接口/签名冻结），再改代码，最后回填本表与 `ios/README.md` §0。


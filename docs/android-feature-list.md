# Android 端功能总清单（验收依据）

> **用途**：Android（Kotlin / Jetpack Compose）开发与验收的唯一功能清单。
> **事实来源优先级**：① `hos/entry/src/main/ets/**`（鸿蒙实现，真机已验证，比文档新）→ ② `hos/docs/**` → ③ `docs/**` → ④ `README.md`。
> **与契约的关系**：页面范围与签名以 [`android/CONTRACT.md`](../android/CONTRACT.md) §5 为准；本文只描述"要做什么行为"。
> **最后更新**：2026-11-04（对齐鸿蒙 `631c110`，跟读结果详情改为独立全屏页）

---

## 0. 概览

### 0.1 产品定位

家庭 3–5 口人共用的英语口语教练：孩子跟读 / 连读 / 对话 / 讲故事，家长看诊断、周报与家庭成员。服务端跑在家庭 NAS 上，客户端只在家庭局域网（或 VPN）可达，**不面向公网**（`README.md` §2、`docs/design-overview.md` §2.1）。

### 0.2 鸿蒙实现的真实规模（本次清点）

| 项 | 数量 | 说明 |
|---|---|---|
| 页面文件 `hos/entry/src/main/ets/pages/*.ets` | **28** | 应用根 `Index` + 登录 `LoginPage` + 5 个 Tab 根页 + 壳 `HomeTabs` + 19 个 `NavDestination` 二级页 + 1 个**未接线**的 `SentenceListPage` |
| 可导航界面 | **26** | 5 Tab + 19 二级 + 登录 + 根（门禁/启动态） |
| ViewModel `viewmodel/*.ets` | **9** | `PracticeVM`/`FlowVM`/`ChatVM`（含 ChatScenarioVM/HistoryVM）/`StoryVM`（含 StoryHomeVM/RecordVM/DetailVM/ReviewVM）/`AccountVM`（含 Settings/Family/Parent/Suggestions/Avatar/Voices）/`StatsVM`（含 Diagnosis/Review/BlindTest/Health）/`LoginVM`；另有 `SettingsVM`、`SentenceListVM` **未被引用** |
| Service `core/service/*.ets` | **10** | Auth / Practice / Flow / Chat / Story / Account / Stats / Dictionary / Media / Cache |
| 路由常量 `core/router/Routes.ets` | 25 | 实际用于 `NavDestination` 的 19 个；其余是 Tab 根/登录等非 push 路由 |
| DTO `core/net/*Dtos.ets` | 6 | Dtos / FlowDtos / ChatDtos / StoryDtos / StatsDtos / AccountDtos |
| 构建与真机 | V1–V3 通过 | `hos/docs/build-verification.md`；V3 已真机跑通全部 5 Tab + 10 个二级页（2026-11-03/04） |

> 注：任务书里"34 个页面/10 个 VM"与实际目录不符，以本表为准（`hos/entry/src/main/ets/pages` 实测 28 个 `.ets`，`viewmodel` 实测 9 个）。

### 0.3 一级导航：5 个 Tab

| Tab | 页面 | 一句话 | 出处 |
|---|---|---|---|
| 0 跟读 | `PracticePage` | 一句一句跟读、同步评分、上下滑换句 | `pages/HomeTabs.ets` L31-32 |
| 1 连读 | `FlowPage` | 5/10/15 句连续读，异步评分，读完出汇总 | 同上 |
| 2 对话 | `ChatScenariosPage` | 选场景 → 纯语音多轮对话 | 同上 |
| 3 故事 | `StoryHomePage` | 中文讲故事 → 分级英文 → 朗读/复述/插画 | 同上 |
| 4 我的 | `MePage` | 学习报告入口、偏好、家长区、服务状态、退出 | `pages/MePage.ets` |

**重要**：鸿蒙实现对**儿童与成人使用同一套 5 Tab**；家长面板 / 家庭成员 / 建议箱收在「我的 → 家长」分组，儿童只看到「我想说」（`MePage.ets` L130-152）。这与 `docs/screens.md` §0（儿童 4 Tab）、`hos/docs/architecture.md` §4.3（家长 5 Tab + 家长面板）不同，见 §4 偏差表 D-03。

### 0.4 跨端一致性要求（Android 必须照抄的"硬规则"）

1. **行为照抄，架构换惯用法**：不自行"优化"交互（`android/CONTRACT.md` 开头）。
2. **三态齐全**：每页 loading / error / empty；错误必须有可执行动作（重试 / 去设置 / 换等级 / 回首页）。
3. **禁止静默失败**：任何异常都要落到 `UiError` 并显示（`hos/docs/architecture.md` §6）。
4. **录音前停播放**（蓝牙 HFP 会"声音发闷"），录音中不允许播放（`core/audio/AudioController.ets` L37-64）。
5. **儿童红线**：不显示音素符号、不显示 <60 的数字、低分不用红色、按钮更大、文案更短。
6. **不宣称"录音不出户"**：当前 `PROVIDER_MODE=hybrid`，音频→Azure、文本→DeepSeek、书页图/插画提示→DeepSeek/智谱（`hos/docs/permissions-and-privacy.md` §5.2、§6）。

### 0.5 文档与代码的"时间差"

| 材料 | 声称 | 实际 |
|---|---|---|
| `README.md` §9 里程碑 | M0「代码已写，待编译/真机验证」 | 已过时：V1 编译通过、V2 装机、V3 全功能真机（`hos/docs/build-verification.md`） |
| `docs/feature-index.md` | 多个接口"✅ 已实现" | `GET /practice/cursor`、`GET /sentences/:id/attempts`、`GET /tts/voices`、`POST /story/recordings` **线上不存在**（`build-verification.md` L419 实测） |
| `docs/screens.md` §1 | 首页有用量环 + 四张功能卡 | 实现是 5 Tab，用量为 Tab 头部一行文字 |
| `docs/feature-index.md` 更新日期 | 2026-11-03 | 本次更新为 2026-11-04（见 §10 Android 实现状态） |

---

## 1. 全局能力（每个页面共用）

### 1.1 认证与单飞刷新

- [ ] `POST /auth/token`（email/password）→ `access_token / refresh_token / expires_in / user`；access 1h、refresh 30d（`README.md` §2.1）。
- [ ] 每个请求注入 `Authorization: Bearer <access>`；`/auth/token`、`/auth/refresh`、`/auth/revoke`、`/health` **不注入、不参与 401 重试**（`core/net/ApiClient.ets` L24-27、L49）。
- [ ] **单飞刷新**：并发 401 只发一次 `/auth/refresh`，其余等同一个 Promise 后重放（`ApiClient.ets` L177-191）。
- [ ] 每个请求**最多重放一次**；重放仍 401 → 清 token → 抛 `unauthorized`（L163-175）。
- [ ] refresh 返回 400/401（被吊销/轮换失效）→ 清 token；**网络失败/5xx → 不清 token**（避免断网即登出，L254-261）。
- [ ] 退出登录：先 `POST /auth/revoke`（失败也继续）→ 清 token → 清缓存 → 清全局会话（`core/session/SessionStore.ets` L94-105）。
- [ ] 会话失效后：`Index` 的 `@StorageLink('session') @Watch` 清空导航栈并回登录页（`pages/Index.ets` L64-68、L240-255）。
- [ ] token 存系统安全存储（鸿蒙 Asset Store / Android 用 `EncryptedSharedPreferences`，见 CONTRACT §2.1）；安全存储降级时**不落明文**，登录页显示黄色提示（`viewmodel/LoginVM.ets` L56-73）。

### 1.2 会话 / 角色 / 儿童模式

- [ ] 全局会话字段：`loggedIn/userId/displayName/email/role/cefrLevel/ageBand/isChild/avatar/dailyLimitMinutes/minutesToday/remainingMinutes`（`SessionStore.ets` L16-32）。
- [ ] 儿童判定：`role === 'child' || user.isChild === true`（L161）。**渲染层必须自己判断**，不能依赖服务端剥 IPA。
- [ ] 儿童渲染规则（`design/DesignTokens.ets` L70-159、各页面）：
  - [ ] 分数 <60 不显示数字、不用红色（`EcScore.showNumber` / `colorForChild`）；
  - [ ] 不显示焦点音素 chips（`PracticeVM.ets` L279）、词级/音素明细（L630、L690）、语调曲线区（L732-748）；
  - [ ] 诊断页不显示 IPA / 对比音素，用 `child_label`（`pages/DiagnosisPage.ets` L183-220）；
  - [ ] 错音本卡片不显示 `/ipa/`、按钮文案换成"还没会 / 有点难 / 会了 / 太简单"（`StatsVM.ets` L297-345）；
  - [ ] 正文字号 19 / 标题 30、录音按钮 88vp、主要按钮 `big`（`DesignTokens.ets` L41-56）；
  - [ ] 文案短、口语、不出现"错误/失败/权限"（`core/error/UiError.ets` L84-166）。
- [ ] 家长专属入口只在 `role === 'parent' && !isChild` 时渲染（`MePage.ets` L130）。
- [ ] 家长接口儿童访问 → 403 显示"家长面板仅对家长开放"页，**不跳登录**（`AccountService.ets` L88 注释、`pages/ParentPage.ets` L319-320）。

### 1.3 今日用量与限额

- [ ] 用量来源：`GET /auth/me` 的 `usage`；每次评测成功用响应里的 `usage` 覆盖（`PracticeVM.ets` L530-533）。
- [ ] 展示：跟读/对话 Tab 头部"今天已练 X / Y 分钟"（`PracticePage.ets` L169-175、`ChatScenariosPage.ets` L94-101）、"我的"卡片"今日 X 分钟"。
- [ ] 429 / `daily_limit_reached`：
  - [ ] 对话：置 `quotaExceeded` → 顶部横幅 + **禁用录音与建议 chips**（`ChatVM.ets` L935-939、`ChatSessionPage.ets` L503、L623、L671）；
  - [ ] 连读：置 `limitReached` → 提示"今天的练习时间到啦"并禁止再录（`FlowVM.ets` L875-878、L965-968）；
  - [ ] 跟读/故事：仅在提交流程里把错误文案显示出来（`UiError.ets` L106-108）。
- [ ] ⚠️ 与 CONTRACT §6.4 的差：契约要求 `session.exceeded` 时**主动**禁用录音并提示，鸿蒙实现只在**碰到 429 之后**才禁用（见 §4 偏差 D-12）——Android 建议按契约做前置判断。

### 1.4 音频：录音

- [ ] 格式固定 **m4a / AAC-LC / 16 kHz / 单声道 / 65 kbps**，无回退分支（`core/audio/AudioRecorder.ets` L139-145、`docs/design-overview.md` §4.1）。
- [ ] 录音前**先停播放**（`AudioController.ets` L41-43）；录音中请求播放直接失败并提示"正在录音，先说完这一句"（L58-61）。
- [ ] 最短 0.6s、最大 12MB，超限本地拦截并提示，**不发请求**（`AudioRecorder.ets` L181-193）。
- [ ] 时长上限：跟读/连读/对话/复述录音 **60s** 自动停止并提交（`PracticeVM.ets` L430-438、`FlowVM.ets` L1032-1039、`ChatVM.ets` L431-439、`StoryVM.ets` L1430-1437）；**讲故事中文录音 120s**（`StoryVM.ets` L487-495）。
- [ ] 权限：每次录音前都重新申请（用户可能已撤销）；拒绝 → `mic_denied` → 错误条按钮"去设置"打开系统权限页（`AudioRecorder.ets` L30-75、`PracticeVM.ets` L928-934）。
- [ ] 录音中 UI：`⏹ 说完啦 Ns` + `✖️ 不要了`（取消 = 删文件 + 不提交）（`PracticePage.ets` L386-414）。
- [ ] 页面销毁/切后台：停计时、丢录音、停播放、释放 fd（各 `dispose()`）。

### 1.5 音频：TTS 与回放

- [ ] TTS 一律**先下载到本地再播放**（`docs/audio.md` §4.1；`PracticeService.ets` L50-76），按魔数判断 wav/mp3 扩展名（L219-237）。
- [ ] 示范音语速：儿童固定 `slow`，成人用账号偏好 `tts_rate`，默认 `normal`；音色用账号偏好 `tts_voice`（`PracticeVM.ets` L342-351、`core/content/AccountPrefs.ets`）。
- [ ] `POST /tts` 失败分支返回 JSON 而非音频 → 先判 HTTP 状态再落盘，内容 <64 字节视为损坏（`PracticeService.ets` L62-69）。
- [ ] 对话助手回复用 `format=mp3`、音色/语速读本地偏好缓存（`ChatVM.ets` L370-377、L737-744）。
- [ ] 整段回放：`GET /chat/sessions/:id/audio/status` 只读；`/audio` **200=ready / 202=building / 500=failed**（`ChatService.ets` L159-192）。
- [ ] 故事整段朗读同理，404 转 `no_audio` 不抛错（`StoryService.ets` L258-290）。
- [ ] 所有播放互斥：新播放先停旧播放（`ChatVM.playMessage` 先 `resetMessagePlayStates`）。

### 1.6 错误码映射（成人 / 儿童两套文案）

- [ ] 统一 `ApiError(code, status, detail)`；`status === 0` 表示本地错误（`core/net/ApiError.ets` L9-50）。
- [ ] `retryable` 判定：network_unreachable / timeout / 5xx internal / provider_error / provider_timeout / 502-504（L30-50）。
- [ ] 文案优先级：**服务端 `error.message` 优先**（已是中文），缺失或网络类错误才用本地兜底表（`UiError.ets` L43-54）。
- [ ] 两套兜底表覆盖：bad_request / unauthorized / forbidden / not_found / audio_not_found / audio_gone / payload_too_large / daily_limit_reached / too_many_requests / content_unsafe / internal_error / provider_* / network / timeout / cleartext / mic_denied / mic_unavailable / record_failed / record_too_short / record_too_large / playback_failed / cache_corrupt / bad_response / bad_base_url（L84-166）。
- [ ] 标题单独映射：连不上 NAS / 请求超时 / 登录已过期 / 需要麦克风权限 / 评测服务暂不可用（L64-81），儿童版全部改写。
- [ ] 无静默失败：每条错误都带 `actionLabel`（重试 / 再试一次 / 去设置 / 重试评测），由页面按钮真正重放上一次动作（`PracticeVM.ets` L924-970）。

### 1.7 能力开关（`GET /api/health`）

- [ ] 启动时调 `/health`（5s 超时、无需登录、不参与 401 重试）判断 `voice.reachable`，false → 5 Tab 顶部琥珀条"语音服务暂时不可用：录音会先保存，稍后可在结果页重试评测"（`pages/Index.ets` L81-88、`HomeTabs.ets` L54-68）。
- [ ] 进程内缓存一次 `voice.capabilities`：`image / ocr / avatar_presets / phoneme_level / prosody / intonation_curve`；**缺省 true**（宁可口子开、服务端 503 给可读提示）（`core/content/CapabilityCache.ets`）。
- [ ] 用途：`image=false` 藏"给我画一张"并提示"插画服务暂未启用"（`StoryDetailPage.ets` L446-465）；`ocr=false` 藏拍照识别（`FlowPage.ets` L147）；`avatar_presets=false` 形象库提示不可用。
- [ ] 服务状态页展示 `features` / `capabilities` / voice 端点清单（`pages/HealthPage.ets`）。
- [ ] 客户端**不对 `/health` 做高于每 30 秒一次的轮询**（`HealthPage.ets` L314 文案即承诺）。

### 1.8 点单词看音标（全页面）

- [ ] 所有英文正文用可点单词组件（`components/WordText.ets`）：跟读句子、连读大字句、对话消息、故事全文、诊断错词。
- [ ] 切词规则：ASCII 字母 + `'`/`’`/`-` 连写，其余（空格、标点）原样保留，渲染结果与原文一致（L36-78）。
- [ ] 点击 → `GET /api/words/:word` → 弹窗显示 `/ipa/`（**只有音标，没有发音按钮**）；多变体追加"其它读音：/…/"；未收录 404 → "暂无音标"（L92-112）。
- [ ] 设置 `show_word_ipa` 关闭 → 点击提示"音标已关闭；可在「设置 → 单词显示音标」里打开"（L94-97）。
- [ ] 结果按进程内缓存（大小写不敏感），超时 8s，401/403/503 一律按"暂无音标"降级（`core/service/DictionaryService.ets` L30-80）。
- [ ] 儿童**同样可以点词看音标**（`screens-matrix.md` §9）；但正文字号更大、单词有虚线下划线。

### 1.9 缓存与离线

- [ ] 目录：`filesDir/recordings`（录音）、`cacheDir/tts`（示范音）、`cacheDir/audio`（回放）（`core/service/CacheService.ets` L13-30）。
- [ ] 启动清理 `.part` 残留；登出清录音 + 音频缓存；**切换账号必须清缓存**（`SessionStore.ets` L88-89）。
- [ ] 设置页"清除"只清 TTS/回放音频，不动账号数据（`SettingsPage.ets` L389-411）。
- [ ] ⚠️ **未实现**（文档承诺过的）：语料 JSON 全量离线缓存、TTS LRU 200MB、评测结果缓存 50 条、失败提交队列（`CacheService.ets` L11 明写"M0 不做 LRU 与过期淘汰"；`docs/design-overview.md` §7 为设计目标）。见偏差 D-14。

### 1.10 权限与隐私

- [ ] 权限只申请 `INTERNET` + `MICROPHONE`；拍照识别走系统相册选择器（`PhotoViewPicker`），**不申请 CAMERA / 媒体库权限**（`FlowVM.ets` L613-641、`hos/docs/permissions-and-privacy.md` §1）。
- [ ] 隐私文案必须如实：录音经家庭 NAS 转发云端做识别/评分/合成，**不是纯本地处理**（`SettingsPage.ets` L425；`permissions-and-privacy.md` §5.3、§6"不能承诺"）。
- [ ] 客户端可以承诺：不接入广告/统计/推送/崩溃 SDK、不后台录音、只与自家 NAS 域名通信、录音只写应用沙箱、退出清 token 与缓存（`permissions-and-privacy.md` §6）。
- [ ] token / 记住的密码只放安全存储，不写日志；日志只打 path/status/耗时（`ApiClient.ets` L328-335）。
- [ ] 儿童：账号由家长创建、不自行注册；建议内容家长可见（`SuggestionsPage.ets` L144）。

### 1.11 全局交互约定

- [ ] 每个 build 级请求都有 `loading` 态且按钮禁用防重复（评测/对话/改写/插画/保存/登录）。
- [ ] 轮询只在页面可见时跑：页面不可见 / `aboutToDisappear` 一律 `dispose()` 停表（`FlowPage.ets` L75、各 VM `dispose()`）。
- [ ] 返回行为：跟读已提交可直接返回；录音中返回要确认；连读进行中确认"还有 N 句没读"；盲测进行中确认；故事生成中允许返回（`docs/screens.md` §14）。
- [ ] 所有页面中文文案、emoji 与鸿蒙一致（🌱⭐💪🎤🔊📈🌙 等）。

---

## 2. 页面详细清单

> 每页固定结构：路由/入口 → 目标用户 → 功能点（勾选式）→ 依赖接口 → 状态 → 儿童差异 → Android 首版状态。
> Android 状态口径：**✅ 实现** = CONTRACT §5 已列且首版必做；**🚧 部分** = 首版做但范围缩减/依赖线上降级；**⏭️ 延后** = 首版不做。

### 2.0 应用壳与「我的」Tab（补充，非 16 页之一）

- **路由/入口**：`Index`（应用根，`@Entry`）+ `HomeTabs`（5 Tab）+ `MePage`（Tab 4）
- **目标用户**：已登录全家
- **功能点**
  - [ ] 启动三态：加载"正在连接家庭 NAS…（只在家庭 Wi-Fi / VPN 下可用）" → 全屏错误 + 重试 → 登录页 / 首页（`Index.ets` L190-238）
  - [ ] 启动流程：`AppConfig.init`（读 baseUrl）→ `CacheService.cleanupOnBoot` → `SessionStore.restore()` → `/health` 判降级（L70-96）
  - [ ] Tab 栏 5 项、图标+文字、当前 Tab 高亮、`barPosition.End`、不可滑动（`HomeTabs.ets` L34-104）
  - [ ] 故事详情"开始朗读"跨 Tab 跳转：`tab_index` 置 1，`HomeTabs` 重建时按它初始化（L17-29）
  - [ ] 「我的」用户卡：首字母头像、昵称、角色+等级、今日分钟 chip、儿童模式 chip（`MePage.ets` L70-102）
  - [ ] 学习分组：发音诊断 / 错音本 / 盲测周报（L104-115）
  - [ ] 偏好分组：设置 / 音色 / 我的形象（L117-128）
  - [ ] 家长分组：家长面板 / 家庭成员 / 建议箱（仅家长）；儿童只有"我想说"（L130-152）
  - [ ] 服务分组：服务状态（L154-161）
  - [ ] 底部：版本号 + baseUrl、退出登录（L163-177）
- **依赖接口**：`GET /auth/me`、`GET /health`
- **状态**：启动 loading / 启动 error（可重试）/ 登录页；我的页无 empty
- **儿童 vs 成人**：同一壳；儿童隐藏家长三个入口
- **Android 首版**：✅（`ui/AppRoot.kt`、`ui/HomeScreen.kt`、`MeScreen.kt` 已在契约内）

### 2.1 登录

- **路由/入口**：`Index` 根内容（未登录时直接显示，非路由、不可返回）——`pages/LoginPage.ets`
- **目标用户**：未登录
- **功能点**
  - [ ] 品牌区："English Coach" + "家庭英语口语教练"
  - [ ] 服务器地址输入框：默认 `https://english.dreamsearch.top`；自动补 `https://`、去掉尾部 `/` 与误填的 `/api`（`LoginVM.ets` L149-153、`AppConfig.ets` L75-91）
  - [ ] 地址下方"检查/重试"：`GET /health` → 显示"家庭 NAS 已连接" / "服务器已连接，但语音服务未就绪…" / "服务器已连接，但数据库异常" / 网络错误文案（`LoginVM.ets` L101-123、L196-206）
  - [ ] 邮箱输入（Email 键盘）+ 密码输入（可切换可见）
  - [ ] "记住密码"开关**默认开**，副文案"下次打开自动登录（密码存在系统安全存储）"（L124-150）
  - [ ] 点登录先本地校验：邮箱/密码非空 → baseUrl 合法 → 保存 baseUrl（L140-158）
  - [ ] 提交：按钮 `登录中…` + loading + 不可重复点（`LoginPage.ets` L182-190）
  - [ ] 成功：`POST /auth/token` → 存 token → `GET /auth/me` 补 usage → 清缓存 → 写全局会话 → 切首页（`AuthService.ets` L25-72、`SessionStore.ets` L82-91）
  - [ ] 冷启动自动登录两步：有 refresh token 直接进首页；没有才用记住的账号静默登录一次，界面显示"正在用记住的账号自动登录…"（`LoginVM.ets` L74-85、`LoginPage.ets` L154-162）
  - [ ] 主动退出后本次进程内不再自动登录（`CredentialStore.markLoggedOut`），但保留记住的密码（`SessionStore.ets` L94-96）
  - [ ] 自动登录遇到密码失效（401/400）→ 清掉记住的密码并停在预填表单（`LoginVM.ets` L162-169）
  - [ ] 安全存储不可用 → 黄字"本机安全存储不可用：登录状态与密码无法持久保存…"（可带错误码）；仍把**邮箱**记普通偏好（L54-73、L175-189）
  - [ ] 演示账号按钮**只填邮箱**、不猜密码（`LoginVM.ets` L126-129、`LoginPage.ets` L192-212）
  - [ ] 底部说明"忘记密码？让家长在家长面板重置。账号由家长创建，不提供自助注册。"
- **依赖接口**：`POST /auth/token`、`GET /auth/me`、`GET /health`
- **状态**：loading（按钮内 + "正在检查服务器…"）/ error（表单上方 `ErrorBanner`，保留输入）/ 无 empty / 存储降级提示
- **儿童 vs 成人**：同一页；儿童走"演示账号"由家长代填
- **Android 首版**：✅（`LoginScreen.kt`；注意 Android 用 `EncryptedSharedPreferences` 等价实现记住密码）

### 2.2 跟读练习（Tab 0）

- **路由/入口**：Tab 0——`pages/PracticePage.ets`；结果详情二级页 `PRACTICE_RESULT` → `PracticeResultPage`
- **目标用户**：所有（儿童/成人差异主要在结果展示）
- **功能点**

  **列表与游标**
  - [ ] 头部问候"你好，{昵称}" + "今天已练 X / Y 分钟" + 当前 `第 N / 总数`
  - [ ] 等级 chips `A1 A2 B1 B2` + `↻ 换一批`；C1 账号回退 B2（`AppConfig.ets` L151-158）
  - [ ] 卡片流一次一句，**上/下滑切换**（`Swiper(vertical)`），底部提示"上滑 / 下滑切换句子"（`PracticePage.ets` L1380-1406）
  - [ ] 专项练习：诊断页带 `focus` token 进入 → 顶部 chip"专项练习 · /θ/" + "退出专项"（L295-313）；进入时用 `GET /sentences?focus=` 拉语料（L63-83）
  - [ ] 练习游标横幅："上次练到第 N 句（共 M 句）" + `▶ 继续上次` / `从头开始`；游标存本地 `practice_cursor_<level>`，**切换句子时写入**（L141-153、L1377-1401、L209-212）；盲测/专项不写游标（L1394-1400）
  - [ ] 空态："这个等级还没有句子，换一个等级试试" + `换个等级`（L1367-1375）
  - [ ] 加载失败：`ErrorBanner` + `重试`
  - [ ] 卡片头：等级 chip + 焦点音素 chips（**儿童不显示**）+ "已评分" chip

  **示范音 / 录音 / 提交**
  - [ ] `🔊 听示范`：下载 wav → 播放；按钮变"播放中…"；重复点先停再播（`PracticeVM.ets` L305-334）
  - [ ] `🎧 跟我读`：播放示范 → 播完 250ms 后自动开录（L320-327）
  - [ ] 录音中：`⏹ 说完啦 Ns` + `✖️ 不要了`；60s 自动停（L430-438）；录音中禁止听示范/回放（L309-312、L358-361）
  - [ ] 提交前本地校验：空文件 / >12MB 直接报错不发请求（`PracticeService.ets` L129-135）
  - [ ] 提交进度文案按耗时切换：`上传录音…` → 2s`识别中…` → 8s`评分中…` → 20s`生成建议…`（`PracticeVM.ets` L505-517）
  - [ ] 成功：总分圆环 + 四项子分（准确/流利/完整/语调）+ "怎么练更好" + "这次的问题" + 逐词评分 + 语调曲线（`PracticePage.ets` L490-640）
  - [ ] 没听到声音（`recognized_text` <2 字）：显示"没有听到你说话 / 可能是麦克风没收到声音…"，**不显示 0 分热力图**（`PracticeVM.ets` L561-564、`PracticePage.ets` L681-686）
  - [ ] `degraded=true`：显示"评分服务刚刚不稳定，这条结果是降级结果，可以点「重试评测」" + `重试评测`（`PracticeVM.ets` L569-572）；无 result 时提示"评测服务暂时不可用，录音已保存，稍后可重试"（L537-546）
  - [ ] `重试评测`：`POST /attempts/:id/retry`，不重录、不重复上传（L482-503）
  - [ ] `下一句 →`：按列表顺序；到末尾提示"这一组读完啦"
  - [ ] `📈 历史`：进入结果详情页（history 模式）

  **结果详情（全屏二级页）**
  - [ ] 8 个区块：这一句的问题 / 这一句的历史 / 本次评分 / 整体点评 / 能力多边形（雷达）/ 逐词得分 / 语调对比（F0 双曲线）/ 需要纠正的地方（`build-verification.md` L331-346、`PracticeResultPage.ets`）
  - [ ] 单句历史：`GET /attempts?limit=100` 本地按 `sentence_id` 过滤取最近 10 次（**线上没有 `/sentences/:id/attempts`**）；折线按旧→新、列表按新→旧；首末对比 `80.3 → 82.4 (+2.1)`；每条可回放 `GET /audio/:attemptId`（`PracticeVM.ets` L787-872）
  - [ ] 历史为空："这一句还没有读过，先读一遍吧 🙂"
  - [ ] 儿童：无雷达图数值、无音素 chips、无 F0 曲线；低分不显示数字

  **盲测模式（复用本页）**
  - [ ] 盲测横幅："🎯 盲测进行中 / 已读 n/N 句 / 这一轮不显示任何分数和反馈"；**不提供示范音**；提交后自动滑下一句（`PracticePage.ets` L119-125、L220-260、L416-420）
  - [ ] 全部读完显示 `结束盲测 · 去看周报`
  - [ ] 盲测中不显示"重试评测"（服务端 409）
  - [ ] 每 2s 轮询 `GET /blind-tests` 只更新"已评完/待评分"计数，**绝不显示分数**（`PracticeVM.ets` L207-249）

- **依赖接口**：`GET /sentences?level=&focus=`、`GET /attempts?limit=`、`POST /tts`、`POST /attempts`（multipart，可带 `blind_test_id`）、`POST /attempts/:id/retry`、`GET /audio/:id`、`POST /warmup`（静默预热后 6 句）、`GET /blind-tests`、`GET /words/:word`
- **状态**：列表 loading（"正在取句子…"）/ error+重试 / empty+换等级 / 额度 429（错误文案）/ degraded / 无语音
- **儿童 vs 成人**：焦点音素、子项术语、逐词、音素、语调、详细结果入口（成人）/ 不显示低分数字、鼓励语优先、按钮更大
- **Android 首版**：✅ 主体；🚧 结果详情页（CONTRACT 未给 `PRACTICE_RESULT` 路由，需 Lead 决定：新增路由 or 页内底部 sheet）
- **附**：`ResumeBanner`/`PRACTICE_RESULT`/`PracticeResultStore` 均为跨页/跨 Tab 传参，Android 用 `NavParams`（契约 §2.7）替代鸿蒙的静态类 + AppStorage 版本号

### 2.3 连读模式（Tab 1）

- **路由/入口**：Tab 1——`pages/FlowPage.ets`；汇总二级页 `FLOW_SUMMARY` → `FlowSummaryPage`
- **目标用户**：所有
- **功能点**

  **Setup**
  - [ ] 三个来源 Tab：语料 / 我的书页 / 自己输入（OCR 入口在"自己输入"里，`capabilities.ocr=false` 时隐藏）
  - [ ] 语料：等级 chips（`ALL` 也支持，聚合 A1–B2 四级别）+ 起点"从第 N 句开始"（可手输）+ 数量 `5 / 10 / 15` + `🎲 随机` / `🔀 换一批`（`FlowVM.ets` L353-481、`FlowPage.ets` L296-408）
  - [ ] 预览列表：显示选中的 N 句原文
  - [ ] 主按钮 `🎤 开始连读（N 句）`（预览为空时提示"这个位置没有句子"）
  - [ ] 我的书页：`GET /materials?kind=page&limit=50`，每行"打开 →"；空态提示；`刷新`
  - [ ] 自己输入：文本框 + `✂️ 切句`（按 `. ! ? 。！？` 切，丢弃无字母碎片，`FlowVM.ets` L137-184）+ 逐句可编辑
  - [ ] 拍照识别：系统相册选择 → `POST /ocr` → 结果追加到文本框，提示"已识别 N 行 · provider · 耗时ms"；照片用完删除，**不保存原图**（`FlowPage.ets` L153、`FlowVM.ets` L613-688）
  - [ ] 识别为空 / 失败：可读提示 + 建议改用"自己输入"（L651-661）
  - [ ] 保存为书页：`POST /materials`（`kind=page`，仅文字）；编辑态走 `PATCH /materials/:id`（L732-777）
  - [ ] 故事入口：故事详情/预览页"朗读这个故事" → 直接进入 running，标题显示"📖 故事名"，逐句是故事句子（`FlowVM.startStoryRead` L792-808）

  **Running**
  - [ ] 顶部进度条 + `第 N / 总数 句`；大字句 + 中文翻译
  - [ ] `🔊 听示范`（成人无"跟我读"，连读只单句示范）
  - [ ] 录音 → `POST /attempts/async`（multipart：audio/reference_text/mode=scripted/duration_ms/source/sentence_id?/material_id?）→ 立即下一句，**不等评分**（`FlowService.ets` L97-126、`FlowVM.ets` L932-977）
  - [ ] 提交成功 400ms 后自动跳到下一句；关闭自动跳时显示 `下一句 →`（L986-996）
  - [ ] 每句状态：`未读 / 待评分… / 评分中… / N 分（儿童仅"已评分"）/ 评分失败`（`statusBadge` L1323-1340）
  - [ ] 轮询 `GET /attempts/status?ids=` **每 1200ms**，只传 pending/scoring 的 id（上限 50），全部 settled 自动停表（L1054-1127）
  - [ ] 单句失败：显示原因 + `重录这句`（重置该条并跳回）；不重复提交成功句（L1378-1395）
  - [ ] 录音中 `⏹ 说完啦` / `✖️ 不要了`；60s 自动停
  - [ ] 全部提交后："全部读完啦，正在后台评分… / 评分完成后会自动跳到汇总页"
  - [ ] 顶部可展开"实时评分（点一行展开详情）"，行内可看子分；`📊 查看本轮汇总`
  - [ ] 429：`limitReached` → 停止录音并提示
  - [ ] 页面不可见：停轮询、丢录音、停播放；回来若仍有 pending 立刻补拉一次（L290-302、L319-326）

  **Summary**
  - [ ] 完成句数、平均分（成人数字 / 儿童鼓励）、失败列表、`重录这句`
  - [ ] 最差 2–3 句
  - [ ] 鼓励语 6 档（S/A/B/C/incomplete/no_speech）× 5 条中英双语，**确定性哈希选取**（同一批结果永远同一条），并为"读得最好的词（≥85）"生成一句具体表扬（`FlowVM.ets` L1521-1603）
  - [ ] `🔊 听鼓励`：中文慢速 → 英文正常顺序播放；语音不可用只提示文字照看（`FlowSummaryPage.ets` L189-199）
  - [ ] 主按钮 `🔁 再读一遍`（同一批句子、`第 N 遍`、不刷新不跳转、两轮都入库）+ `再读一段`（回 setup）（`FlowVM.reread` L1397-1418）
  - [ ] 来自故事时显示 `📝 复述这个故事` → 跳故事复述页（`build-verification.md` L327-328）
  - [ ] 汇总页诊断：`GET /diagnosis?scope=batch&attempt_ids=`（≤20），无评完提示"这一批还没有评完的句子"
- **依赖接口**：`GET /sentences`、`GET /materials?kind=page`、`GET /materials/:id`、`POST /materials`、`PATCH/DELETE /materials/:id`、`POST /ocr`、`POST /attempts/async`、`GET /attempts/status`、`POST /tts`、`GET /diagnosis?scope=batch`
- **状态**：setup loading/empty/error；running 单句失败不影响其它句；summary 空（无分数时"这一批没有拿到分数…读得开心最重要"）
- **儿童 vs 成人**：措辞"正在听…"而非"评分中"、无数字分、无音素明细（连读详情本来就不含音素/语调图，见 `FlowPage.ets` L1029）
- **Android 首版**：✅（Tab + 汇总页都在 CONTRACT §5）

### 2.4 对话训练（Tab 2 + 4 个二级页）

- **路由/入口**：Tab 2 `ChatScenariosPage` → `CHAT_SESSION` / `CHAT_HISTORY` → `CHAT_DETAIL` / `CHAT_CUSTOM`
- **目标用户**：所有（儿童受场景受众与 `allow_free_chat` 限制）
- **功能点**

  **场景列表**
  - [ ] 顶部："💬 对话训练"（儿童"和我聊聊天吧！"）+ 今日已练/剩余分钟
  - [ ] 快捷开关：`🔊 自动朗读`（默认开）、语速 `🐢 慢速 / 🐇 正常`（儿童默认慢速）；本地持久化（`ChatScenariosPage.ets` L52-80）
  - [ ] `🕘 历史` 入口
  - [ ] 分组：我的场景（`is_custom=true`）/ 成人场景 / 儿童场景；卡片显示标题（英/中）、setting_zh、等级、min_age、"我的场景" chip、`开场白变体 N`（L284-395）
  - [ ] 点卡片：`POST /chat/sessions` → 存会话 → 进会话页；开始时该卡片显示 loading（`ChatVM.ets` L1089-1114）
  - [ ] 429：顶部额度横幅 + 不允许开始
  - [ ] 成人"再看小朋友的场景"开关（持久化；儿童无此开关）（L517）
  - [ ] `＋ 自定义场景` → `CHAT_CUSTOM`；空态提示可自定义
  - [ ] 说明文案"点场景卡就开始了；对话里只有语音输入，没有文字输入框。"

  **自定义场景**
  - [ ] 表单：英文标题 / 中文标题 / 场景说明 / 角色提示词（占位示例）/ 开场白 / 难度（A1–C1）；受众：儿童账号只能建"小朋友场景"，成人可选（`ChatCustomPage.ets` L199-327）
  - [ ] 保存：`POST /chat/scenarios`（新建）/ `PATCH /chat/scenarios/:id`（编辑）；未填字段不传
  - [ ] 删除：二次确认 → `DELETE /chat/scenarios/:id`
  - [ ] 注入词/越权：服务端 400/404，页面显示可读错误

  **会话（纯语音）**
  - [ ] 头部：场景中文标题、`第 N 轮`、等级 chip、"不限轮数，想聊多久都可以"（`ChatSessionPage.ets` L447-461）
  - [ ] 开场白立即显示，自动朗读（开关关则不播）；每条助手消息可 `🔊 再听`（`ChatVM.ets` L315-317、L678-720）
  - [ ] 一轮三步：录音 → `POST /asr?language=en-US` → 乐观插入用户气泡 → `POST /chat/sessions/:id/turn`（multipart：text 必填 + audio）→ 文字先渲染 → `POST /tts`（mp3）自动朗读（L450-503）
  - [ ] ASR 空结果："没听清，请再说一次"（重试按钮），**不发送空 turn**（L464-472）
  - [ ] 进度文案 `识别中… / 回复中…`，8s 后追加"（有点慢，再等一下）"（L891-901）
  - [ ] turn 失败：保留 `pendingText/pendingAudio`，"重试"真的重发同一轮，不重复插入消息（L494-503、L971-976）
  - [ ] 纠错卡：`correction`（"更自然"提示）；`flag=unsafe_filtered` 显示"（内容已按儿童安全规则替换）"
  - [ ] 建议应答 chips（最多 3 条）：点击 = **设为提示句并立刻开始录音**，不发文本；页面显示"照着这句说：… / 提示句只给你参考，发出去的是你说的录音。"（L503-556、`ChatVM.useSuggestion` L985-988）
  - [ ] 发音分补充：每轮后 `GET /chat/sessions/:id/messages` 轮询 **4 次，延迟 700/1100/1500/1900ms**；成人显示 pron 与弱音素，儿童只用于鼓励；拿不到不报错（L559-607）
  - [ ] `🏁 结束对话`：二次确认（"结束后会生成整段回放…"）→ `POST /:id/end` → 结束态（L430-445、L558-597、`ChatVM.endSession` L535-557）
  - [ ] `done=true` 自然收尾：直接进结束态并触发回放生成
  - [ ] 整段回放：`GET /:id/audio/status` → ready 下载播放；building 每 2s 轮询、最多 30 次（≈60s）；超时提示 + `🔄 重新生成`（`?force=1`）（`ChatVM.ets` L759-866）
  - [ ] 错误/额度：429 → `quotaExceeded` 横幅并禁用录音；409/`session_closed` → 切结束态（L932-955）
  - [ ] 无麦克风：本页必须麦克风才能对话，提供"去设置检查权限"入口

  **历史 / 详情**
  - [ ] 历史列表：`GET /chat/sessions`（最近 30 条），显示场景、时间、轮数、"›"进入详情（`ChatHistoryPage.ets`）
  - [ ] 详情（只读）：`GET /chat/sessions/:id` + `/messages`；显示完整对话、每条录音回放、correction、整段回放；顶部说明"发音评价只在「结束对话」当时展示；历史记录保留完整对话、每条校正与录音。"（`ChatDetailPage.ets` L149、`ChatVM.initHistory`）
  - [ ] 空态：无历史 → "去对话"
- **依赖接口**：`GET/POST /chat/scenarios`、`PATCH/DELETE /chat/scenarios/:id`、`POST /chat/sessions`、`GET /chat/sessions`、`GET /chat/sessions/:id`、`GET /chat/sessions/:id/messages`、`POST /asr`、`POST /chat/sessions/:id/turn`、`POST /chat/sessions/:id/end`、`GET /chat/sessions/:id/audio/status`、`GET /chat/sessions/:id/audio?force=`、`POST /tts`、`GET /api/audio/:id`
- **状态**：场景 loading/error/empty；会话首条"正在准备场景…"；turn 失败可重试；TTS 失败文字照常 + "再读一遍"；回放 building/failed
- **儿童 vs 成人**：场景只显示 child 受众；建议 3 条也可能不给；纠错更温和；不显示分数/IPA；无"再看小朋友的场景"
- **Android 首版**：✅ 全部 5 个页面（CONTRACT §5 已列 `CHAT_SESSION/HISTORY/DETAIL/CUSTOM`）

### 2.5 故事模式（Tab 3 + 3 个二级页）

- **路由/入口**：Tab 3 `StoryHomePage` → `STORY_RECORD` / `STORY_DETAIL` / `STORY_REVIEW`
- **目标用户**：所有
- **功能点**

  **故事集**
  - [ ] 头部："📖 我的故事"（儿童"我的故事书"）+ 副文案"说法子：今天发生了什么？和谁一起？你开心吗？"
  - [ ] `＋ 讲一个故事`（儿童"🎤 我要讲故事"）
  - [ ] 连续天数 chip `🔥 连续 N 天`（按有故事的日期从今天/昨天往前数，`StoryHomeVM.computeStreak`）
  - [ ] 筛选：`全家` / `只看我的`（**客户端按 `created_by` 过滤**，后端无 `mine` 参数）+ `↻ 刷新`
  - [ ] 按日期分组（今天/昨天/更早 + 具体日期），卡片显示封面（`has_image` → 鉴权下载后本地显示）、标题、等级、句数、作者、中文原文标记
  - [ ] 空态："还没有故事，讲一个吧" + 主按钮；"只看我的"为空 → 引导看全家
  - [ ] 底部说明"故事保存在家庭共享的书架上，全家都能看到。"

  **新建故事（讲故事）**
  - [ ] 中文输入框（≤2000 字），placeholder 给例子；`🎤` 录音说中文 → `POST /asr?language=zh-CN` → 追加到文本框；识别失败可"重新识别"（不重录）（`StoryVM.ets` L414-485）
  - [ ] 录音上限 120s 自动停；录音中 `✖️ 不要了`
  - [ ] 难度：`⬇️ 再简单一点 / ⬆️ 再难一点` + `A1 A2 B1 B2 C1` chips；已生成时改难度**自动重新生成**（L385-394）
  - [ ] 句子数：3–12，默认账号偏好，没有则儿童 5 / 成人 8（`StoryVM.ets` L365-379）
  - [ ] 生成：`POST /story/rewrite`（`text_zh/level/max_sentences/use_weak_phonemes=false/tense=auto`）；按钮 loading + 文案"✍️ 正在把故事变成英文…"（L506-537）
  - [ ] 结果预览：英文标题（可改）+ 逐句可编辑 + 可读性（N 句 / 平均 X 词 / 最长 Y 词）+ 可能偏难的词 + 时态警告 `tense_mismatch`→"时态可能和中文原意不一致（叙事一般用过去时），可以点「重新生成」再试一次"（L539-602）
  - [ ] `🔄 重新生成`
  - [ ] 保存：`POST /materials`（`kind=story`、`source_zh`、`level`）→ 跳详情；`auto_illustrate=true` 且 `capabilities.image` 时保存后**静默**画一张（失败不影响）（L618-663）
  - [ ] 生成后直接 `🎤 讲给我听`：先保存拿 id 再进复述页（不必经详情页）——`StoryRecordPage.ets` L47-52、L381-390
  - [ ] 朗读这个故事：`StoryReadRequest` 写句子 → 切到连读 Tab 直接 running（L410-412）
  - [ ] 儿童：隐藏可读性/弱音素等技术细节（文案层面儿童化）

  **故事详情 / 复述**
  - [ ] `PATCH /materials/:id`（改名，行内输入 + 保存/取消）、`DELETE /materials/:id`（二次确认后返回列表）；**仅成人与创建者/家长**（儿童不显示，服务端 403 兜底）（`StoryDetailPage.ets` L160-204、`build-verification.md` L295-300）
  - [ ] 英文全文按句编号渲染，句子内单词可点看音标；`复制全文`（剪贴板替代 Web 打印）（L275-279）
  - [ ] 🗣️ "看看你当时怎么讲的（中文）"：显示 `source_zh`；**原声回放仅当本次会话刚录过**才有文件，并明确写"线上暂时没有保存故事原始录音的接口，所以关掉 App 后这段就听不到了。"（L321、L561-585）
  - [ ] 插画卡：有图 → 带 Authorization 下载后显示（`Contain`，不裁成横条）；无图 → `🖼️ 给我画一张`（约 ¥0.1 提示）；`capabilities.image=false` 时隐藏按钮并提示"插画服务暂未启用…"（L364-465）
  - [ ] 插画提示词可见（折叠 `🖼️ 生成用的提示词`）；下载失败给"重新加载"（**不重复生成**）（`StoryVM.ets` L903-968）
  - [ ] 整段朗读回放：`GET /story/:id/audio/status` → ready 播放 / building 每 2s 轮询最多 30 次 / failed 显示"重新生成"；**`failed && attempt_count===0` 视为 no_audio**，显示"先读一遍这个故事，才能听整段朗读哦"且不给重生成（`StoryVM.ets` L973-1099、`build-verification.md` L218-228）
  - [ ] `📖 阅读这个故事 / 开始朗读` → 连读 Tab
  - [ ] `🎤 讲给我听` → 复述页
  - [ ] 本次会话的复述记录（覆盖率/讲到了/可补充）在详情页回显——**仅进程内**，重启丢失（`StoryRuntime.addRetell`，见偏差 D-09）
  - [ ] 复述页：语音 → `POST /asr?language=en-US` → `POST /story/retell`；**也支持打字复述**；显示"讲到了 / 下一次可以试试"；**不评发音分**；可回放刚才的复述；`🎤 再讲一次`
- **依赖接口**：`GET /materials?kind=story&limit=&offset=`、`GET /materials/:id`、`GET /materials/:id/image`、`POST /materials`、`PATCH/DELETE /materials/:id`、`POST /asr?language=zh-CN|en-US`、`POST /story/rewrite`、`POST /story/retell`、`POST /story/:id/illustrate?force=`、`GET /story/:id/audio/status`、`GET /story/:id/audio?force=`、`POST /tts`
- **状态**：列表 loading/error/empty；详情加载失败可重试；插画/朗读失败互不影响阅读；复述失败保留录音
- **儿童 vs 成人**：无改名/删除入口、无低分/百分比、文案口语化、大按钮
- **Android 首版**：✅ 主体（3 Tab/3 二级页都在契约）；🚧 原声回放 + 复述记录持久化（线上无接口，见 D-08/D-09）

### 2.6 盲测（`BLIND_TEST`）

- **路由/入口**：我的 → 盲测周报；跟读页盲测横幅"结束盲测 · 去看周报"
- **目标用户**：所有（分数仅家长可见）
- **功能点**
  - [ ] Intro：说明"同一组句子、全程不给反馈"；`POST /blind-tests` 返回 `blind_test_id + sentence_ids[10] + total + resumed`；**有进行中的批次直接恢复同一个**（`StatsService.ets` L96-101、`StatsVM.ets` L524-545）
  - [ ] 开始后：把抽题写入进程内 `BlindRuntime` → 清导航栈 → 切回跟读 Tab 进入盲测模式（`build-verification.md` L379-387）
  - [ ] 进行中：显示"🎯 盲测进行中 / 已读 n/N / 这一轮不会有任何分数和反馈"；`返回去跟读练习（补读几句）`
  - [ ] 进度：`GET /blind-tests` 的 `in_progress.scored/pending`，只更新计数
  - [ ] 结束：`POST /blind-tests/:id/finish` → 显示 `notice`、平均分（仅已评分）、准确/流利/语调差异；`scored/pending` 如实展示（"还有 N 条在后台评分，平均分只含已评完的"）
  - [ ] 周报：最近一次综合分、与上次相比 `▲ +4.4 / ▼ -2 / ＝0 / 首次（无对比）`、历次柱状图、历史记录列表、`📈 去看周报`
  - [ ] 空态："还没有练过的句子" → 去跟读；错误 `no_practiced_sentences` / `no_attempts` 文案可执行
  - [ ] 防作弊：不提供"重试评测"；盲测录音服务端 409
  - [ ] 儿童：全程不显示分数；结束后只说"完成啦/下次再来"
- **依赖接口**：`POST /blind-tests`、`GET /blind-tests`、`POST /blind-tests/:id/finish`、`POST /attempts`（带 `blind_test_id`）
- **状态**：loading（开始按钮）/ error（含 409 进行中）/ empty / pending>0 说明
- **Android 首版**：✅

### 2.7 发音诊断（`DIAGNOSIS`）

- **路由/入口**：我的 → 发音诊断；跟读页可跳（文档 §1 提到）
- **目标用户**：所有（儿童用 child 文案）
- **功能点**
  - [ ] 两个 scope Tab：`最近 7 天`（`scope=recent&days=7`）/ `全部累计`（`scope=all`）；切换即重载（`DiagnosisPage.ets` L81-101、`StatsVM.ets` L55-66）
  - [ ] 摘要：`summary_zh`、`counts{weak,watch,ok}`、`focus_phonemes`
  - [ ] 顶部主行动："🎯 最近最需要练的：/θ/ /ð/" + `去练一练` → 写 `PracticeFocus` + 切跟读 Tab（`GET /sentences?focus=<token>`）（L123-146）
  - [ ] 音素卡：儿童用 `child_label`（如"咬舌音"），成人用 `/ipa/`；`avg_score`、`trend`、`error_words`、`practice_count`、`tip_zh`、`contrasts`（**对子去重**，a→b / b→a 合并）、`common_errors`
  - [ ] 每卡行动 `🎯 练这 N 句`
  - [ ] 样本不足：`counted_phonemes=0` → "每个音至少要有 2 次记录，先去跟读几句吧" + 返回跟读
  - [ ] 儿童：无 IPA、无对比音素、低分不显示数字、口型/例词保留
- **依赖接口**：`GET /diagnosis?scope=recent&days=7`、`GET /diagnosis?scope=all`、`GET /sentences?focus=`
- **状态**：loading（摘要骨架）/ error+重试 / empty（样本不足）
- **Android 首版**：✅

### 2.8 错音本（`REVIEW`）

- **路由/入口**：我的 → 错音本
- **目标用户**：所有
- **功能点**
  - [ ] `GET /review?limit=20`（服务端上限 50）：`stats{total_cards,due_cards,phoneme_rows,phoneme_level,voice_reachable}`、`due_cards[]`、弱音素条、高频错词
  - [ ] 卡片：标题（成人 `/ipa/ · label`，儿童只用 label）、`why_zh / how_zh`、meta（kind / 已复习 n 次 / 遗忘 n 次 / ease / 上次评分）
  - [ ] 四个评分按钮 `again / hard / good / easy`（儿童：😵 还没会 / 🤔 有点难 / 😀 会了 / 🤩 太简单）→ `POST /review {card_id, grade}`；成功后**本地移除该卡**并 `due_cards-1`，提示"下次复习：N 天后 ✅"或"10 分钟后再来一次 🔁"（`StatsVM.ets` L258-294）
  - [ ] 评分按钮期间禁用防重复
  - [ ] 底部说明"排期算法：SM-2 简化版"
  - [ ] 空态："还没有要复习的，去跟读几句吧" + 返回按钮
  - [ ] 儿童：无 IPA、无低分数字、文案温和
- **依赖接口**：`GET /review`、`POST /review`
- **状态**：loading / error+重试 / empty
- **Android 首版**：✅

### 2.9 家长面板（`PARENT`，仅家长）

- **路由/入口**：我的 → 家长面板
- **目标用户**：**仅 parent**（儿童 403）
- **功能点**
  - [ ] 403 → 专用页"家长面板仅对家长账号开放" + 返回（不跳登录）（`ParentPage.ets` L51-64、L319-320）
  - [ ] 全家汇总：`family{members, minutes_today, minutes_7d, sentence_count, scenario_count}` + 说明文案
  - [ ] 每个孩子"今日剩余时长"卡片（`childRemainingText`）
  - [ ] 盲测周环比（每人一张）：最近一次综合分（大数字 + 语义色）、`本周 vs 上次`（▲/▼/＝/首次）、已完成盲测次数、准确/流利/语调差异、历次柱状图；无数据 → "还没有完成的盲测…下周再做一次就能看到环比"；进行中 → "正在做盲测…" chip
  - [ ] 高频错音 / 高频错词（单词级粗评）列表；无数据 → "暂无数据"
  - [ ] 成员明细：昵称、角色、剩余时长、本周分钟
  - [ ] `👥 家庭成员管理`、`📈 查看盲测周报`、`刷新`
  - [ ] 说明文案"盲测周环比 · 判断「到底有没有变好」"（解释为什么日常分虚高）
- **依赖接口**：`GET /parent/summary`（snake_case）
- **状态**：loading（骨架）/ error+重试 / empty（无孩子 → "先添加一个孩子"）/ forbidden
- **儿童 vs 成人**：儿童不可见；深链进入即 403 页
- **Android 首版**：✅

### 2.10 家庭成员（`FAMILY`，仅家长）

- **路由/入口**：我的 → 家庭成员；家长面板 → 家庭成员管理
- **目标用户**：仅 parent
- **功能点**
  - [ ] 说明"给家里人各建一个账号（不同英语水平）。登录名可以只写简称，会自动补 @family.local。"
  - [ ] `GET /family/members` 列表：emoji + 昵称、角色+等级徽标、"N 分钟/天 · 练过 N 次"、邮箱；行内 `编辑` / `重置密码`（L384-391）
  - [ ] 新建（折叠表单）：昵称（≤20）、登录名、密码（≥8）、角色（家长/孩子）、等级 A1–C1、每日时长（5–180）、允许自由对话开关 → `POST /family/members` → 201 → 提示"已创建 昵称（登录名 …）"
  - [ ] 校验顺序与文案：昵称 1–20 / 登录名必填 / 密码 ≥8 / 时长 5–180；409 → "登录名已经有人用了，换一个吧"（`AccountVM.ets` L504-559）
  - [ ] 编辑：昵称、等级、每日时长、自由对话（**不能改角色**）→ `PATCH /family/members/:id`
  - [ ] 重置密码：新密码 ≥8 → `POST /family/members/:id/password` → "密码已重置（旧密码已失效）"（**无旧密码校验**，是家长管理员重置）
  - [ ] 空态："还没有其他成员，点右上角「＋ 添加成员」建一个吧。"
- **依赖接口**：`GET/POST /family/members`、`PATCH /family/members/:id`、`POST /family/members/:id/password`
- **状态**：loading / error / empty / 表单内联错误
- **Android 首版**：✅（含"修改密码"能力，见 2.16）

### 2.11 建议箱（`SUGGESTIONS`）

- **路由/入口**：我的 → 建议箱（家长）/ 我想说（儿童）；家长面板入口
- **目标用户**：所有可提交；列表/导出仅家长
- **功能点**
  - [ ] 提交（全体）：分类 chips —— 成人 5 类（体验问题/内容建议/新功能想法/程序出错/其他），**儿童 3 类**（体验/内容/其他，`SuggestionsVM.categories`）；正文 ≤ `maxLength`（默认 2000，服务端可下发）；自动带 `page`（固定 `/settings`）
  - [ ] 提交按钮 loading；成功"收到啦，谢谢！已记到建议列表里。"（儿童"收到啦，谢谢你！🌟"）；失败保留正文
  - [ ] 家长列表：筛选（全部/未读/已读/已解决）+ counts；每条显示分类、页面、时间、内容、角色；`👁 标记已读` / `✅ 标记已解决` → `PATCH /suggestions/:id`
  - [ ] 导出：`GET /suggestions/export?format=md` → 页面显示 Markdown 文本框 + `一键复制` + `清空`（**替代 Web 的下载**）（`SuggestionsPage.ets` L248-287）
  - [ ] 空态："这里还没有建议。家人用的时候可以在这里随手留言。"
  - [ ] 儿童只看提交区（不加载列表、不显示筛选/导出）
- **依赖接口**：`POST /suggestions`、`GET /suggestions?status=&limit=&offset=`、`PATCH /suggestions/:id`、`GET /suggestions/export?format=md`
- **状态**：提交 loading / error；列表 loading / error / empty；导出 loading
- **Android 首版**：✅（导出用"显示 + 复制"；文件下载 ⏭️）

### 2.12 虚拟形象（`AVATAR`）

- **路由/入口**：我的 → 我的形象
- **目标用户**：所有
- **功能点**
  - [ ] `GET /avatar` + `GET /avatar/presets`（12 角色 × 5 风格，`characters[].images{style→站内路径}`）
  - [ ] 当前形象卡：图片（**预置静态图 `/avatars/...` 可直接 `Image(url)`，无需鉴权**）、风格 chip、角色卡描述（可编辑"把描述改成更像我的"→ `PATCH /avatar {character_desc}`）、`清空形象` → `DELETE /avatar`
  - [ ] 第 1 步选风格（`styles[]`），第 2 步选角色（`presets.characters[]`）；点一下立即生效 `POST /avatar {preset_id, style}`，提示"点一下立即生效，不需要等待生成。"
  - [ ] "按我的性别显示"开关：默认按 `settings.gender` 过滤角色，可切"显示全部"（`AvatarPage.ets` L253-263）
  - [ ] **不做照片上传**：照片生成形象已按隐私策略关闭（`403 policy_disabled`），页面不提供入口（`AccountService.ets` L30、`MediaService.ets` L120-126）
  - [ ] 占位提示"预览图（未生成真实插画）：当前展示的是占位图…"；`capabilities.avatar_presets=false` 时提示不可用
  - [ ] 隐私说明"不用上传照片，选一个就好 / 只影响插画形象"
- **依赖接口**：`GET /avatar`、`GET /avatar/presets`、`POST /avatar`、`PATCH /avatar`、`DELETE /avatar`
- **状态**：loading / error+重试 / empty（该分类无形象）
- **Android 首版**：✅

### 2.13 音色（`VOICES`）

- **路由/入口**：我的 → 音色；设置页"去试听选择"
- **目标用户**：所有
- **功能点**
  - [ ] 列表 = **内置 9 个音色常量**（`GET /tts/voices` 线上 404）：5 个英语（Jenny/Aria/Ana/Guy/Michelle）+ 4 个中文（晓晓/晓伊/云希/云健），每个显示中文名 + 语言分组（`MediaService.ets` L30-53、`VoicesPage.ets` L185-196）
  - [ ] 首项"默认音色（provider 决定）"= 不指定 voice
  - [ ] 点 `🔊 试听`：`POST /tts {text:sample, voice, rate, format:'mp3'}` → 播放；再点停止；试听中按钮态；失败提示（`MediaService.preview`）
  - [ ] `使用这个音色` / `使用默认音色`：`PATCH /settings {tts_voice}` → "已保存音色偏好 ✅" → `AccountPrefs.reload()` 立即生效
  - [ ] PATCH 不被支持时提示"该设置暂不可用（当前服务器不支持保存偏好）"
  - [ ] 底部 `⚙️ 去设置页调整语速与其它偏好`
- **依赖接口**：`GET /settings`、`PATCH /settings`、`POST /tts`
- **状态**：loading / error+重试 / 试听失败内联
- **Android 首版**：✅（内置常量放 `core/audio/Voices.kt`）

### 2.14 设置（`SETTINGS`）

- **路由/入口**：我的 → 设置；跟读页右上"设置"
- **目标用户**：所有（儿童看到的可改项更少）
- **功能点**
  - [ ] 头卡：邮箱 · 角色 · 等级 · 今日已练/上限
  - [ ] 加载：`GET /settings` → `user`（全量）+ `prefs`（camelCase）+ `usage`；loading 骨架"正在读取账号设置…"
  - [ ] 昵称（1–30）
  - [ ] 每日练习时长滑杆（5–180，step 5）+ "允许自由话题"开关：**儿童不渲染**，改为说明"由家长设置（服务端会拒绝儿童自行修改）"
  - [ ] 🎨 卡通插画自动生成开关 + "每张约 ¥0.1；关闭后保存故事不会自动画…"
  - [ ] 性别 chips：不设置/女孩/男孩/成年女性/成年男性/其它（`girl/boy/woman/man/other`）；说明"只用于插画提示词与形象筛选"
  - [ ] 故事句子数 chips 3–12 + `恢复默认`（角色默认：儿童 5 / 成人 8）
  - [ ] 纠正强度：`gentle / standard / none`（附中文解释）
  - [ ] 音色：显示当前音色名 + "去试听选择" → 音色页
  - [ ] 朗读语速：`🐢 慢速 / 🐇 正常`；儿童附"慢速更清楚，但合成耗时约为正常语速的 2.3 倍"
  - [ ] 🔤 单词显示音标开关（默认开）+ 说明
  - [ ] `保存设置`：本地校验（昵称 1–30 / 时长 5–180 / 性别枚举 / 句数 3–12 / 纠正强度 / 语速 / 音色在 9 个之内）→ `PATCH /settings`（**儿童不带 `daily_limit_minutes`/`allow_free_chat`**）→ "已保存 ✅"；400 后重新 `GET /settings` 同步服务端真实状态；403 → "每日时长与自由话题由家长设置"（`AccountVM.ets` L146-255）
  - [ ] 服务器地址卡：输入 + `检查` + `保存地址`（复用 `/health`）
  - [ ] 杂项卡：`清除`（只清音频缓存）、token 存储说明、版本号、隐私说明"录音会经家庭 NAS 转发到云端做识别与评分，不是纯本地处理。"
  - [ ] `退出登录`（DANGER + loading）+ 说明"退出后需要重新输入账号密码；本地录音与缓存会被清理。"
- **依赖接口**：`GET /settings`、`PATCH /settings`、`GET /health`、`POST /auth/revoke`
- **状态**：loading / error+重试 / 保存失败保留输入 / PATCH 不支持提示
- **儿童 vs 成人**：儿童没有时长/自由话题；其余文案口语化、按钮更大
- **Android 首版**：✅（`SettingsScreen.kt`）

### 2.15 服务状态（`HEALTH`）

- **路由/入口**：我的 → 服务状态；设置页可跳
- **目标用户**：家长 / 排障
- **功能点**
  - [ ] 说明"家庭 NAS / 语音能力自查。此接口无需登录，可用来判断服务是否在线。"
  - [ ] 总状态卡（`level/levelTitle/levelDetail`）+ `强制刷新`（`GET /health?force=1` 跳过服务端缓存）
  - [ ] 数据库状态（`db.ok`）
  - [ ] 语音服务卡：`已就绪/未就绪` chip、`voice.reachable`、`voice.url`（注明是容器内地址）、未就绪时提示"voice 未就绪时录音与文本仍会入库，可稍后重试评测"
  - [ ] 构建特性（`features`）：逐项"支持/不支持"；缺字段 → "未返回 features 字段"
  - [ ] 语音能力（`voice.capabilities`）：逐行列出；`voice.features[]` 端点 chips；缺字段 → "未返回 capabilities 字段"
  - [ ] 兜底说明"客户端不对 /api/health 做超过每 30 秒一次的轮询；voice 探测有 3 秒超时 + 15 秒缓存。"
- **依赖接口**：`GET /health`（含 `?force=1`）
- **状态**：loading / error+重试 / 字段缺失提示
- **Android 首版**：✅

### 2.16 修改密码（无独立页面）

- **路由/入口**：**没有独立路由**。鸿蒙把"重置密码"放在家庭成员页行内弹层（`FamilyPage.ets` L312-338、`AccountVM.ets` L611-645）；`docs/screens.md` §12 设计的 `change_password?memberId=` 独立页**未实现**。
- **目标用户**：家长（给自己/成员重置）；儿童只读引导
- **功能点**
  - [ ] 家庭成员行 → `重置密码` → 新密码输入（占位"新密码（至少 8 位）"）+ `保存` / `取消`
  - [ ] 校验：本地只拦 ≥8 位（`AccountVM.ets` L627-630）；文档写 8–128 位（`docs/screens.md` §12），上限由服务端 400 回显
  - [ ] 成功提示"密码已重置（旧密码已失效）"
  - [ ] 安全提示：服务端只更新 `password_hash`，**不会吊销现有 refresh token**（`docs/screens.md` §12、`hos/docs/open-questions.md` Q7）→ 文案建议"建议在旧设备退出登录"
  - [ ] 儿童：无入口（家长代改）；`POST /auth/password`（本人改密，需旧密码）**后端未实现**
- **依赖接口**：`POST /family/members/:id/password`；`POST /auth/password`（⏭️ 待后端）
- **状态**：按钮 loading / 400 内联错误 / 无 empty
- **Android 首版**：✅（并入 `FamilyScreen.kt`）；独立页与自助改密 ⏭️ 延后

---

## 3. 接口总表

> 备注列说明"线上是否存在 / 替代方案"，依据 `hos/docs/build-verification.md` L389-419 的真实接口核对 + 各 Service 实现。
> 全部路径由 ApiClient 自动拼 `{baseUrl}/api`（`ApiClient.ets` L341-351）。

### 3.1 认证与账号

| 接口 | 用途 | 对应页面 | 备注 |
|---|---|---|---|
| `POST /auth/token` | 登录，拿 access(1h)+refresh(30d)+user | 登录 | 线上存在；`user` 只有 7 个字段（无 `isChild`/`dailyLimitMinutes`），儿童靠 `role/ageBand` 判定 |
| `POST /auth/refresh` | 轮换刷新（一次性） | 全局（网络层） | 必须单飞；旧 refresh 立即失效 |
| `POST /auth/revoke` | 退出吊销 | 设置/我的 | 失败也继续本地退出 |
| `GET /auth/me` | 当前用户 + usage | 启动、登录、我的 | `user` 可能为 null（旧行为）→ 先刷新再取一次 |
| `GET /settings` | 用户全量 + prefs + usage | 设置/音色/精力 | prefs 为 camelCase（`ttsVoice/ttsRate/showWordIpa/correctionLevel`） |
| `PATCH /settings` | 保存偏好 | 设置/音色/形象 | 返回的 user 是**瘦身版**，不能覆盖表单；鸿蒙用字符串方法名发 PATCH，真机已通过 |
| `GET/POST /family/members` | 成员列表/新建 | 家庭成员 | 仅家长；items snake_case |
| `PATCH /family/members/:id` | 改昵称/等级/时长/自由聊 | 家庭成员 | 不能改角色 |
| `POST /family/members/:id/password` | 重置密码（含自己） | 家庭成员 | 无旧密码；不吊销旧 refresh |
| `POST /suggestions` | 提交建议 | 建议箱 | 所有人；`user_id/role` 由服务端取 |
| `GET /suggestions` | 家长收件箱 | 建议箱 | 仅家长；counts/total/max_length |
| `PATCH /suggestions/:id` | 标记 read/resolved | 建议箱 | 仅家长 |
| `GET /suggestions/export?format=md` | 导出 Markdown 文本 | 建议箱 | 响应是**纯文本**不是 JSON；移动端显示+复制 |
| `GET /avatar`、`POST/PATCH/DELETE /avatar` | 形象查询/选择/改描述/清空 | 形象 | `POST` 只认 `preset_id+style`，照片路径 403 |
| `GET /avatar/presets` | 12 角色 × 5 风格 | 形象 | images 是站内路径 `/avatars/...`（无需鉴权） |
| `GET /parent/summary` | 家长汇总 | 家长面板 | 仅家长；snake_case |

### 3.2 跟读 / 连读

| 接口 | 用途 | 对应页面 | 备注 |
|---|---|---|---|
| `GET /sentences?level=&focus=` | 语料（A1–B2，可带音素筛选） | 跟读/连读/诊断 | 返回 `{level,focus,count,sentences[]}`；`focus_phonemes` 儿童为空数组 |
| `GET /sentences/:id` | 单句详情 | — | 鸿蒙未使用（列表已含全部字段） |
| `POST /tts` | 示范音/对话朗读/试听 | 跟读/连读/对话/故事/音色 | 200 是音频（wav/mp3），错误分支才是 JSON；带 `x-audio-duration-ms` |
| `POST /attempts`（multipart） | 同步评测（也可带 `blind_test_id`） | 跟读/盲测 | 字段 `audio/sentence_id/reference_text/mode/duration_ms[/blind_test_id]`；超时 120s |
| `POST /attempts/:id/retry` | 用已存录音重评 | 跟读 | degraded 时用；盲测下会被 409 |
| `GET /audio/:id` | 录音回放 | 跟读/对话 | 二进制，需 Bearer |
| `GET /attempts?limit=N` | 我的评测记录 | 跟读（单句历史） | **替代** `GET /sentences/:id/attempts`（线上不存在）：拉 100 条本地过滤 |
| `POST /warmup` | 预热示范音（fire-and-forget） | 跟读 | 失败静默；最多 12 条文本 |
| `POST /attempts/async`（multipart） | 异步提交 | 连读 | 立即返回 attempt id，不含分数 |
| `GET /attempts/status?ids=` | 批量状态（≤50） | 连读 | 每 1200ms 轮询；done 时带 result |
| `GET /materials?kind=page` | 我的书页 | 连读 | 家庭共享 |
| `GET /materials/:id` | 书页/故事详情 | 连读/故事 | — |
| `POST /materials` | 新建书页/故事 | 连读/故事 | 故事返回**扁平对象** `{id,title,...}` |
| `PATCH /materials/:id` | 改名/改文本 | 连读/故事 | 只能改自己录入的 |
| `DELETE /materials/:id` | 删除书页/故事 | 连读/故事 | 同上 |
| `POST /ocr`（multipart image） | 拍照识别书页 | 连读 | 支持 HEIC；超时 60s |
| `GET /diagnosis?scope=batch&attempt_ids=` | 本批诊断 | 连读汇总 | ≤20 个 id |

### 3.3 对话

| 接口 | 用途 | 对应页面 | 备注 |
|---|---|---|---|
| `GET /chat/scenarios[?include_child=1]` | 场景列表 | 对话列表 | 成人默认只看成人；`is_custom`/`variation_count` 均有 |
| `POST /chat/scenarios`、`PATCH/DELETE /:id` | 自定义场景 CRUD | 自定义场景 | 仅 owner；儿童强制 child |
| `POST /chat/sessions` | 开会话（随机 variation） | 对话列表 | 返回是 `session_id`（不是 `id`） |
| `POST /asr?language=en-US`（multipart） | 一轮第 ① 步识别 | 对话会话 | 三步链路的必要条件 |
| `POST /chat/sessions/:id/turn`（multipart text+audio） | 一轮第 ② 步 | 对话会话 | **不返回 TTS 音频、不返回发音分**；返回 reply/reply_zh/correction/suggested_replies/done/turn_index |
| `GET /chat/sessions/:id/messages` | 消息 + `pron` + `correction` | 对话会话/详情 | **唯一 pron 来源**（`/sessions/:id` 不含） |
| `POST /chat/sessions/:id/end` | 结束会话（触发整段回放预生成） | 对话会话 | 幂等 |
| `GET /chat/sessions/:id/audio/status` | 回放状态（只读） | 对话会话/详情 | ready/building/failed |
| `GET /chat/sessions/:id/audio[?force=1]` | 整段回放 | 对话会话/详情 | 200 wav / 202 building / 500 failed |
| `GET /chat/sessions`、`/:id` | 历史列表/详情 | 历史/详情 | 列表含轮数、场景、平均发音 |

### 3.4 故事

| 接口 | 用途 | 对应页面 | 备注 |
|---|---|---|---|
| `POST /asr?language=zh-CN` | 中文语音转文字 | 新建故事 | **替代** `POST /story/recordings`（线上 404） |
| `POST /asr?language=en-US` | 复述语音转文字 | 复述 | 同上 |
| `POST /story/rewrite` | 中文 → 分级英文 | 新建故事 | `tense=auto`（默认过去时）；`warnings[]` 含 `tense_mismatch/too_hard/too_many_sentences` |
| `POST /story/retell` | 复述覆盖度（不评发音分） | 复述 | 两步：先 ASR 再 retell |
| `POST /story/:id/illustrate[?force=1]` | 生成插画（¥0.1/张） | 故事详情 | 需要 `capabilities.image`；返回 `prompt_used` |
| `GET /story/:id/audio/status` / `/audio` | 整段朗读回放 | 故事详情 | failed+`attempt_count=0` → 按 no_audio 处理 |
| `GET /materials?kind=story&limit=&offset=` | 故事集 | 故事列表 | 家庭共享；`has_image/has_recording/source` 等 |
| `GET /materials/:id/image` | 封面/插画图 | 故事列表/详情 | 需 Bearer，先下载再显示 |

### 3.5 诊断 / 盲测 / 错音本 / 词音标 / 健康

| 接口 | 用途 | 对应页面 | 备注 |
|---|---|---|---|
| `GET /diagnosis?scope=recent&days=` / `scope=all` | 分层诊断 | 诊断/家族 | days 1–365（默认 7） |
| `GET /review?limit=` | 错音本 | 错音本 | 上限 50，默认 20 |
| `POST /review {card_id, grade}` | SRS 评分 | 错音本 | again/hard/good/easy |
| `POST /blind-tests` | 开始/恢复盲测 | 盲测 | 返回 `blind_test_id + sentence_ids[10] + resumed` |
| `GET /blind-tests[?user_id=]` | 周报/进度 | 盲测/跟读盲测 | 儿童带别人 id 会 403 |
| `POST /blind-tests/:id/finish` | 结束并出报告 | 盲测 | 幂等；`scored/pending` 如实展示 |
| `GET /words/:word` | 单词音标 | 全页面 | 404 → "暂无音标"；`ipa_disabled` → "音标已关闭" |
| `GET /health[?force=1]` | 健康/能力开关 | 服务状态/启动/设置 | 无需登录；features + voice.capabilities |

### 3.6 线上**不存在**、已被替代的接口（不要在 Android 端调用）

| 文档里的接口 | 实际 | 鸿蒙替代 | 出处 |
|---|---|---|---|
| `GET /api/practice/cursor`、`PUT /api/practice/cursor` | 线上缺（404/404） | 本地 Preferences `practice_cursor_<level>` 记 sentence id | `build-verification.md` L419、`PracticePage.ets` L141-153 |
| `GET /api/sentences/:id/attempts` | 线上缺 | `GET /attempts?limit=100` 本地按 `sentence_id` 过滤 | 同上、`PracticeVM.ets` L787-838 |
| `GET /api/tts/voices` | 线上缺 | 内置 9 音色常量 | `MediaService.ets` L30-53 |
| `POST /api/story/recordings`（及 `/:id/transcribe`、`GET /`、`/:id/audio`） | 线上缺 | 直接 `POST /asr`；原始录音仅本次会话内存可用 | `StoryService.ets` L25-28、`StoryDetailPage.ets` L585 |
| `GET/POST /api/health` vs `/v1/health` | 客户端只调 web `/api/health`（含 voice 摘要） | 不需要直接调 `/v1/*` | `README.md` §2.4 |
| `POST /api/auth/password`（本人改密） | 后端未实现 | 只做家长重置 | `docs/screens-matrix.md` §1、`open-questions.md` Q7 |
| `POST /api/version`、`Idempotency-Key`、推送 | 后端未实现 | 不调用；启动版本校验不做 | `docs/backend-contract.md` §2/§5/§6 |

---

## 4. 文档与实现偏差表（重要）

> 结论：**以代码 + `hos/docs/build-verification.md` 为准**，下表凡"文档说 ✅/设计如此"但线上或实现不是这样的，Android 端一律照"实现事实"列做。

| # | 文档说法（出处） | 实现事实（出处） | 对 Android 的影响 |
|---|---|---|---|
| D-01 | 练习游标 `GET/PUT /practice/cursor` ✅（`docs/feature-index.md` §2、`README.md` §6.2） | 线上不存在；本地 Preferences 记 `practice_cursor_<level>`，**切换句子时写入**，横幅"上次练到第 N 句 / ▶继续上次 / 从头开始"（`build-verification.md` L325、L419；`PracticePage.ets` L141-153、L1377-1401） | 用 `AppPrefs` 实现，不要新增接口；按 level 分别记 |
| D-02 | 单句历史 `GET /sentences/:id/attempts?limit=20` ✅（同上） | 线上不存在；用 `GET /attempts?limit=100` + 本地过滤，取最近 10 次，折线旧→新、列表新→旧（`PracticeVM.ets` L787-872） | 同上；注意 `pending=true` 或 `scores=null` 的记录要跳过 |
| D-03 | 儿童 4 Tab / 家长 5 Tab + 家长面板（`hos/docs/architecture.md` §4.3、`docs/screens.md` §0） | 统一 5 Tab（跟读/连读/对话/故事/我的）；家长入口在"我的→家长"（`HomeTabs.ets` L31-32、`MePage.ets` L130-152） | 照 5 Tab；不要另做家长 Tab |
| D-04 | 首页壳：用量进度环 + 四张功能卡 + 错音本/诊断/设置入口（`docs/screens.md` §1） | 没有独立首页；用量是各 Tab 头部一行文字，功能入口在 Tab/我的（`PracticePage.ets` L262-293、`HomeTabs.ets`） | 不做首页；Tab 根页自带头部 |
| D-05 | "可选记住邮箱（默认关）；**绝不记住密码**"（`docs/screens.md` §2 L116） | **默认记住密码**（开关默认开），密码存系统安全存储；冷启动可静默登录；主动退出后本次进程不再自动登录（`build-verification.md` L192-199；`LoginVM.ets` L36-99） | Android 用 `EncryptedSharedPreferences`；必须保留"存储不可用→不落明文+黄字提示" |
| D-06 | 盲测提交用 `POST /attempts/async` 带 `blind_test_id`（`docs/screens.md` §7、`docs/feature-index.md` §7） | 用**同步** `POST /attempts` 带 `blind_test_id`；响应只有 `{attempt_id, blind, progress}` 无分数；提交后 400ms 自动下一句，2000ms 轮询 `GET /blind-tests` 只看计数（`PracticeService.ets` L127-170、`PracticeVM.ets` L449-479、L207-249） | 照同步接口；**绝不渲染盲测分数**，结束后才看 `finish` |
| D-07 | 对话发音分"每 2s 轮询 3–5 次"（`docs/screens.md` §5.2 L337） | 固定 **4 次**，延迟 700/1100/1500/1900ms；失败静默不报错（`ChatVM.ets` L559-607） | Android 可照抄 4 次；不要弹错 |
| D-08 | 故事"先落盘再转录"、原声回顾可回放（`docs/design-overview.md` §5.4、`README.md` §6.4） | `POST /story/recordings` 线上 404；录音只临时保存，**关 App 即失效**，详情页明确告知"线上暂时没有保存故事原始录音的接口"（`StoryService.ets` L25-28、`StoryDetailPage.ets` L561-585） | 原声回放只能在本次会话内做；不要承诺持久化 |
| D-09 | 故事详情显示"复述记录"（`docs/screens.md` §6.3） | 复述结果只写进程内 `StoryRuntime`（重启丢失），无服务端接口（`StoryVM.ets` L36-70、`StoryDetailPage.ets` L658） | 同 D-08：内存态展示，或 M2 再补本地持久化 |
| D-10 | `GET /tts/voices` ✅（`docs/feature-index.md` §6） | 线上 404；内置 9 个音色常量（5 英 4 中）（`MediaService.ets` L30-53、`build-verification.md` L419） | Android 同样写常量（CONTRACT §4.1 `Voices.kt`） |
| D-11 | 修改密码是独立页 `change_password?memberId=`（`docs/screens.md` §12、`architecture.md` §4.2） | 无独立路由/页面，能力放在家庭成员页行内"重置密码"（`FamilyPage.ets` L312-338） | 并入家庭成员页；独立页 ⏭️ |
| D-12 | 额度用尽 `session.exceeded` 时**主动**禁用录音并提示（`android/CONTRACT.md` §6.4、`docs/screens.md` §3 状态） | 只在**收到 429 后**才禁用/提示（对话 `quotaExceeded`、连读 `limitReached`）；跟读/故事无前置禁用（`ChatVM.ets` L932-940、`FlowVM.ets` L963-968） | Android **按契约做前置禁用**（更严格，属改进而非照抄） |
| D-13 | 对话"建议回复 chips 点击**只朗读**，不发文本"（`docs/screens.md` §5.2 约束） | 点击 = 设为提示句 + **立刻开始录音**，不朗读；页面提示"提示句只给你参考，发出去的是你说的录音"（`ChatVM.useSuggestion` L985-988、`ChatSessionPage.ets` L532-556） | 照实现做（"照着说"体验更好） |
| D-14 | 离线缓存：语料全量、TTS LRU 200MB、结果缓存 50 条、失败提交队列（`docs/design-overview.md` §7） | **均未实现**：只做目录、启动清 `.part`、登出清缓存；代码注释明写"M0 不做 LRU 与过期淘汰"（`CacheService.ets` L11） | 首版不做；M2 再补（Android 用 Room/DataStore 更自然） |
| D-15 | 打印 / 导出 Markdown 下载（`docs/design-overview.md` §5.7、`README.md` §6.4） | Web 专属；移动端用"复制全文 / 一键复制 Markdown"（`StoryDetailPage.ets` L275-279、`SuggestionsPage.ets` L248-261） | ⏭️ 不做打印；复制必须做 |
| D-16 | 复述是语音流程（`docs/screens.md` §6.3） | 复述页额外支持**打字复述**（`StoryReviewPage.ets` L101-166、`StoryVM.ets` L1296-1303） | 照实现做（无麦/静音环境的兜底） |
| D-17 | 语料"600 句 A1–B2"（`docs/screens.md` §3） | 真机实测 A2 列表为 **200 句**（"跟读 1/200"，`build-verification.md` L276）；各等级条数文档未写死 | **待确认**：Android 不要在前端硬编码总数 |
| D-18 | 故事详情"无图进详情自动画一张"（早期实现） | 已移除：必须用户点"给我画一张"（避免打开即扣 ¥0.1）（`build-verification.md` L206-208、`StoryVM.ets` L855） | 照实现：只在保存后（`auto_illustrate`）或用户点击时生成 |
| D-19 | 点词音标浮层为底部 sheet/浮层避让（`docs/screens-matrix.md` §9、`design-overview.md` §5.8b） | 改为**系统 AlertDialog**（跨机型最稳），标题=单词、正文=`/ipa/`、可带"其它读音"（`WordText.ets` L10-16、`build-verification.md` L559c98a） | Android 用 Compose Dialog 即可，语义一致 |
| D-20 | 连读轮询"1–2s"（`design-overview.md` §5.2） | 固定 **1200ms**；自动下一句延迟 400ms；盲测轮询 2000ms；故事/对话整段回放 2000ms×30（`FlowVM.ets` L1064、L987，`StoryVM.ets` L1020-1030，`ChatVM.ets` L819-833） | Android 照抄这些间隔，避免压垮 NAS |
| D-21 | 服务器地址 release 只读、debug 可改（`docs/screens.md` §11） | 所有构建都能改（登录页 + 设置页）（`LoginVM.ets` L149-157、`SettingsPage.ets` L336-387） | 照实现（家庭自部署场景需要） |
| D-22 | 健康检查能力开关应按 `phoneme_level/prosody/intonation_curve` 自适应渲染（`design-overview.md` §5.1） | `CapabilityCache` 读了这三个字段，但页面实际只把 `image/ocr/avatar_presets` 用于藏入口；音素/语调主要靠"字段缺失兜底显示"（`CapabilityCache.ets` L14-37） | Android 首版同鸿蒙；M2 再做粒度自适应 |
| D-23 | 「我的」应有"修改密码"入口（`docs/screens.md` §11） | 设置页没有修改密码项；只在家庭成员页重置（`SettingsPage.ets`、`FamilyPage.ets`） | 照实现 |
| D-24 | 首页 Tab 数/入口由角色决定（`architecture.md` §4.3） | `MePage` 用 `role==='parent' && !isChild` 判断（两者都看），比文档更严（`MePage.ets` L130） | 照实现 |
| D-25 | 文档说 M0「待编译/待真机」（`README.md` §9） | 已编译 + 装机 + 全功能真机（`build-verification.md` V1/V2/V3） | 不要把 README §9 当验收基线 |
| D-26 | 批量 OCR 多选图片逐张识别（`docs/screens.md` §4 setup） | 只支持**单张**（`maxSelectNumber=1`）（`FlowVM.ets` L626-633） | 首版单张；多张 ⏭️ |

---

## 5. Android 端实现范围与里程碑

> 依据 `android/CONTRACT.md` §5 的页面清单 + 本文 §4 的偏差修正。原则：**先照抄行为，不追求"更聪明"**。

### 5.1 M1（首版必须，= CONTRACT §5 全量页面）

**基础设施（已完成/在途）**：ApiClient（单飞刷新）、TokenStore/CredentialStore、SessionStore、ErrorMapper 两套文案、DesignTokens/EcTheme（`LocalIsChild`）、AudioController + `Voices` 9 常量、CacheStore、Routes/NavParams/AppNavHost、组件库（EcButton/PageScaffold/ErrorBanner/EmptyState/ScoreViews/WordText/Charts/RecordButton/RemoteImage）。

| 里程碑块 | 页面 | 必须带的细节 |
|---|---|---|
| A 登录 | `LoginScreen` | baseUrl 校验/健康检查/记住密码（加密）/自动登录两步/存储降级提示/演示账号只填邮箱 |
| B 跟读 | `PracticeTab` + 结果详情 | 等级 chips、上下滑卡、游标横幅（AppPrefs）、听示范/跟我读、60s 自动停、进度文案、degraded 重试、单句历史、无语音提示、`📈历史` |
| C 连读 | `FlowTab` + `FlowSummaryScreen` | 三来源、5/10/15、随机、OCR 单张、切句可编辑、async 1200ms 轮询、重录单句、六档鼓励语+中英播放、再读一遍 |
| D 对话 | `ChatScenariosTab`/`CHAT_SESSION`/`HISTORY`/`DETAIL`/`CUSTOM` | 纯语音三步、建议 chip=提示句、pron 4 次轮询、结束确认、整段回放 2s×30、429 横幅、自定义场景 CRUD |
| E 故事 | `StoryHomeTab`/`RECORD`/`DETAIL`/`REVIEW` | 中文 ASR 追加、难度/句数、tense 警告、保存后跳详情、插画能力开关+空态 no_audio、复制全文、复述（语音+打字）、原声仅内存 |
| F 报告 | `DIAGNOSIS`/`REVIEW`/`BLIND_TEST` | 诊断 recent/all、错音本 4 档评分本地移除、盲测全程无分数 + finish 报告 |
| G 账号 | `PARENT`/`FAMILY`/`SUGGESTIONS`/`AVATAR`/`VOICES`/`SETTINGS`/`HEALTH` | 家长 403 页、成员 CRUD + 重置密码、建议 5/3 分类 + 导出复制、形象性别筛选、9 音色 + 试听、设置全项 + 儿童不带家长字段、健康页字段缺失兜底 |
| H 壳 | `AppRoot`/`HomeScreen`/`MeScreen` | 启动三态、5 Tab、故事→连读跨 Tab、降级琥珀条、退出清缓存 |

**M1 明确不做**：打印页、照片生成形象、批量 OCR、多设备推送、离线写队列、深色模式、平板双栏、无障碍字号极限档（CONTRACT §0 只要求手机竖屏为主）。

### 5.2 M2（后续）

1. 离线能力：语料 JSON 缓存（Room/DataStore）、TTS LRU、失败提交队列 + 幂等重试（D-14）。
2. 故事原声与复述记录的**本地持久化**（D-08/D-09），并在 UI 明确"仅本机"。
3. 打印替代方案打磨：故事集多选 → 分享/生成 PDF（若产品需要，需后端无依赖，纯客户端）。
4. 能力开关粒度自适应（音素级/语调曲线/韵律）按 `capabilities` 渲染（D-22）。
5. 平板适配（`widthIn` 约束、双栏）、深色模式、无障碍（大字号/对比度/朗读）。
6. 前置额度禁用（D-12）与"今日剩余时长"更醒目的展示。
7. 自助改密 `POST /auth/password` + 注销全部设备（依赖后端，⏭️）。

### 5.3 验收前置条件

- [ ] 有一个可登录的家庭账号（线上 `dad@example.com` 可能被 `BOOTSTRAP_*` 改密，`build-verification.md` L426-428）。
- [ ] Android 端 PATCH 无鸿蒙的枚举缺失问题（OkHttp 原生支持），但仍要处理 405/501 → "该设置暂不可用"。
- [ ] 服务端 `PROVIDER_MODE=hybrid` 时录音会出网，隐私文案必须如实。

---

## 6. 验收清单（页面级）

### 6.1 全局

- [ ] 冷启动 → 有 token 直接进首页；无 token 进登录页；网络失败显示"连不上家庭 NAS"+重试，**不清 token**。
- [ ] access 过期：并发 3 个请求同时 401 → 只发 1 次 refresh，三个都重放成功；refresh 被拒 → 回登录页。
- [ ] 杀进程重开仍登录；退出登录后 token 失效（`/auth/revoke`）。
- [ ] 所有页面有 loading / error / empty 三态，错误都有可执行动作。
- [ ] 录音前自动停播放；录音中不能播放；页面切走停轮询/停播放/丢录音。
- [ ] 儿童账号：全局看不到 IPA/音素/低分数字/红色低分；按钮更大；文案无"错误/失败"。
- [ ] 429：对话与连读明确禁用录音并给出剩余时长；跟读/故事至少给出可读提示。
- [ ] 健康检查 `voice.reachable=false` 时 5 Tab 顶部出现琥珀降级条。
- [ ] 所有英文正文可点词看音标；关闭开关后提示"音标已关闭"；无收录提示"暂无音标"。

### 6.2 登录

- [ ] 错误密码 → "邮箱或密码不正确"；保留输入；按钮 loading 不可重复点。
- [ ] 换服务器地址后"检查"能反映新地址；非法地址提示示例。
- [ ] 记住密码关掉后不再自动登录；自动登录失败（密码失效）清掉记住的密码。
- [ ] 安全存储不可用 → 黄字提示且不落明文；邮箱仍预填。

### 6.3 跟读

- [ ] 等级切换/换一批不打断当前录音；C1 账号落到 B2。
- [ ] 游标横幅出现、"继续上次"跳到对应句、"从头开始"清游标。
- [ ] 60s 自动停并提交；0.6s 以下本地拦截（"录音太短"）且不发请求。
- [ ] 进度文案按 2s/8s/20s 递进，无假百分比。
- [ ] `degraded=true` 显示降级提示 + "重试评测"，重试不重新上传。
- [ ] 没听到声音时不显示 0 分热力图，给出"再试一次"。
- [ ] 单句历史折线（≥2 次才画）、首末对比、每条可回放、列表新→旧。
- [ ] 盲测模式下无示范音、无分数、无重试评测，读完可"结束盲测·去看周报"。

### 6.4 连读

- [ ] 5/10/15 句可选；随机/换一批可用；起点可改；`全部`等级聚合不因单级别失败而整体失败。
- [ ] 提交后 400ms 自动下一句，不等评分；轮询 1200ms 只查 pending。
- [ ] 单句失败可"重录这句"且不重复提交已成功句。
- [ ] 汇总页平均分/最差 3 句/鼓励语（同一批结果稳定）+ 中英播放 + "再读一遍"第 N 遍。
- [ ] 来自故事时汇总页有"复述这个故事"。
- [ ] 页面切走停轮询；回来仍 pending 会立刻补拉。

### 6.5 对话

- [ ] 无文字输入框；建议 chip 点击后只填提示句并开始录音（不发送文本）。
- [ ] 一轮：ASR → 气泡 → turn → 文字先出 → TTS 播放；ASR 空不发 turn。
- [ ] turn 失败"重试"重发同一轮，不产生重复消息。
- [ ] pron 4 次轮询补齐；拿不到不报错、不阻塞下一轮。
- [ ] 结束确认 → 结束态 → 整段回放 building 轮询≤30 次 → ready 可播 / failed 可"重新生成"。
- [ ] 历史详情只读、消息含 correction、录音可回放、整段回放可用。

### 6.6 故事

- [ ] 中文语音追加进文本框；120s 上限；识别失败可"重新识别"。
- [ ] 句数 3–12（默认 5/8 或账号偏好）；难度可升降；已生成时改难度自动重生成。
- [ ] `tense_mismatch` 有可读提示；可读性/偏难词展示（儿童隐藏）。
- [ ] 保存后进详情；`auto_illustrate` 开且 image 可用时保存后静默画一张。
- [ ] 详情：改名/删除仅成人；复制全文；中文原文可看；原声只在本次会话可播且文案如实。
- [ ] 插画：能力关时隐藏并提示；有图显示不裁切；下载失败"重新加载"不重生图；提示词可见。
- [ ] 整段朗读：ready 可播、building 轮询、failed 可重生成、`attempt_count=0` 显示"先读一遍…"且无重生成按钮。
- [ ] 复述：语音与打字都能出覆盖度；不显示发音分；可回放复述录音；"再讲一次"。

### 6.7 盲测 / 诊断 / 错音本

- [ ] 盲测进行中任何页面都无分数（抓包 + UI 走查）；`pending>0` 有说明。
- [ ] 盲测结束显示平均分与环比；`resumed` 能恢复同一批次。
- [ ] 诊断 recent/all 切换、最需练的音素置顶、每卡"练这 N 句"能带 focus 进跟读；样本不足有引导。
- [ ] 错音本 4 档评分后卡片移除并提示下次复习时间；儿童文案温和、无 IPA。

### 6.8 家长 / 家庭成员 / 建议箱

- [ ] 儿童进家长面板显示 403 页（深链同样）；家长能看到剩余时长、盲测环比、错词错音。
- [ ] 新建成员校验（昵称/登录名/密码≥8/时长 5–180）；409 登录名占用提示；编辑不能改角色；重置密码提示"旧密码已失效"。
- [ ] 建议：成人 5 类、儿童 3 类；超长拦截；家长能筛选/标记/导出并复制。

### 6.9 形象 / 音色 / 设置 / 服务状态 / 修改密码

- [ ] 形象：风格+角色两步、性别筛选开关、点击立即生效、改描述、清空；无照片入口。
- [ ] 音色：9 个内置 + 默认项；试听可停止；保存后立刻用于示范音（无需重启）。
- [ ] 设置：儿童不渲染时长/自由话题且 PATCH 不带这两个字段；保存成功"已保存 ✅"；PATCH 不支持时提示；地址可改可检查。
- [ ] 服务状态：features/capabilities 缺失有兜底文案；force 刷新有效；不高于 30s 轮询。
- [ ] 家庭成员能重置密码（≥8 位），成功提示；无独立修改密码页。

---

## 7. 出处索引（快速对照）

| 主题 | 文件 |
|---|---|
| 页面实现 | `hos/entry/src/main/ets/pages/*.ets`（28 个） |
| 业务逻辑/轮询/阈值 | `hos/entry/src/main/ets/viewmodel/*.ets`（9 个） |
| 接口封装 | `hos/entry/src/main/ets/core/service/*.ets`（10 个） |
| 网络/认证/错误 | `core/net/ApiClient.ets`、`ApiError.ets`、`core/error/UiError.ets`、`core/session/SessionStore.ets`、`core/net/TokenSession.ets`、`core/session/CredentialStore.ets` |
| 音频 | `core/audio/*.ets`、`hos/docs/audio.md` |
| 设计令牌/儿童规则 | `hos/entry/src/main/ets/design/DesignTokens.ets`、`hos/docs/design-system.md`、`docs/screens.md` §0 |
| 接口真实状态 | `hos/docs/build-verification.md`（V3「真实接口核对」L389-419） |
| 隐私边界 | `hos/docs/permissions-and-privacy.md` §5/§6 |
| 页面设计基线 | `hos/docs/screens.md`（12 页 + 13 提建议 + 14 跳转 + 15 验收） |
| 功能→接口→页面矩阵 | `docs/screens-matrix.md`、`docs/feature-index.md`、`docs/design-overview.md` |
| Android 页面/签名 | `android/CONTRACT.md` §5 |

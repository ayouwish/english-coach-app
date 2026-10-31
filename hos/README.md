# English Coach · HarmonyOS 客户端设计

> 状态：**设计稿 v0.2（2026-10-31 修订）**
> 范围：只包含设计文档 + DevEco Studio 工程目录骨架，**不包含可编译的 App 代码**。
> 后端：`english-coach/web`（Next.js :3000）+ `english-coach/voice`（FastAPI :8100）已存在并跑通。
> **本目录不修改后端**；凡是需要后端配合的地方，统一标注为【待后端新增】或【待后端确认】。
> v0.2 修订：认证改为 Bearer Token、最低 API 提升到 20、录音统一 16kHz/单声道/65kbps，并按真实代码修正对话链路、发音分字段与隐私边界。

---

## 0. 一分钟结论

| 决策点 | 结论 | 依据 / 备注 |
|---|---|---|
| 系统与语言 | HarmonyOS NEXT，ArkTS + ArkUI，**最低 API 20**（HarmonyOS 6.0.0） | 只面向 NEXT，不做 Android 兼容层；API 20 以下不安装 |
| 工程形态 | **单 HAP（entry）+ 多个 HAR（features/commons）** | 先保证可维护，不引入 HSP 的运行时共享复杂度 |
| 服务端入口 | 只访问 `https://english.dreamsearch.top/api/*` | **绝不直连 voice :8100**；AI 能力全部在服务端 |
| 认证 | **Bearer Token**：access 1h / refresh 30d，网络层单飞刷新；两个 token 存 Asset Store Kit（`@ohos.security.asset`） | Web 端继续用 Cookie，**双模式并存**；`/auth/token`、`/auth/refresh`、`/auth/revoke` 为【待后端新增·P0】 |
| 录音 | AVRecorder → **m4a / AAC、单声道、16kHz、65kbps** | 统一参数，不设低带宽分支；整段上传、不切片；上限 12MB |
| 播放 | 先下载到 `cacheDir`，再 `AVPlayer` 用 `fd://` 播放 | `/api/audio/:id` 返回 `accept-ranges: none`，不适合边下边播；且需要 `Authorization` |
| TTS | 跟读示范用 `wav`（命中缓存快），对话用 `mp3` | 客户端只负责取字节、落盘、播放 |
| 分发 | iOS 用 **TestFlight**；鸿蒙建议内部签名/企业内部分发或应用市场内测，**【待用户确认】** | 见 [docs/open-questions.md](docs/open-questions.md) Q3 |
| 第三方依赖 | **运行时零三方**，只用 `@kit.*` 系统能力 | 不引入 axios、图片库、统计 SDK、WebView |
| 儿童模式 | 不显示 IPA、不显示低分、大按钮、慢速默认 | 服务端只保证剥离 IPA；**低分隐藏是客户端策略** |
| 深色模式 | MVP 不做，M4 再用资源限定符补齐 | 先把颜色 token 化，禁止硬编码 |

### 标注约定

全文使用以下四种标签，出现即代表该事项的真实状态：

- **【已实现·后端现有】**：已在 `english-coach` 仓库代码中存在，客户端可直接调用。
- **【待后端新增】**：当前后端没有该接口/字段，需要先改后端，客户端才能做。
- **【客户端自行实现】**：纯客户端逻辑，不需要后端改动。
- **【待真机验证】**：依赖 HarmonyOS 设备/系统版本行为，文档不做“已验证可用”的承诺。

---

## 1. 文档索引

| 文档 | 内容 |
|---|---|
| [docs/architecture.md](docs/architecture.md) | ArkTS/ArkUI 分层、状态管理、路由、HTTP/Token 认证、单飞刷新、错误映射、离线缓存 |
| [docs/audio.md](docs/audio.md) | AVRecorder 参数（16kHz/单声道/65kbps）、麦克风权限、AVPlayer 播放、录放互斥、后台/锁屏 |
| [docs/screens.md](docs/screens.md) | 13 个界面（含首页/错音本）的结构、交互、API、loading/error/empty、儿童差异 |
| [docs/design-system.md](docs/design-system.md) | 颜色/字号/间距/圆角/阴影/按钮层级、组件清单、深色模式取舍 |
| [docs/permissions-and-privacy.md](docs/permissions-and-privacy.md) | 权限声明、数据流、NAS/云端边界、隐私文案、合规注意 |
| [docs/roadmap.md](docs/roadmap.md) | M0–M4 范围、验收标准、风险 |
| [docs/open-questions.md](docs/open-questions.md) | 需要拍板的问题（分发、平板、账号安全等） |
| [docs/adr/](docs/adr/) | 架构决策记录（ADR-0001 已被取代、ADR-0002 现行：Bearer Token） |

---

## 2. 事实基线：移动端可用的 web API

> 以下以 `english-coach/web/src/app/api/**` 代码为准（2026-10-30 核对）。
> 统一错误格式：`{ "error": { "code": string, "message": string, "detail"?: object } }`。
> 所有路径都相对 `baseUrl`，即 `${baseUrl}/api/...`。

### 2.1 认证与账号

| 方法 | 路径 | 说明 | 状态 |
|---|---|---|---|
| POST | `/auth/token` | `{email,password}` → `{access_token, refresh_token, token_type:"Bearer", expires_in:3600, user}` | 【待后端新增·P0】 |
| POST | `/auth/refresh` | `{refresh_token}` → 新的一对 token（**一次性轮换**，旧 refresh 立即失效） | 【待后端新增·P0】 |
| POST | `/auth/revoke` | `{refresh_token}` → 204；退出登录时调用 | 【待后端新增·P0】 |
| POST | `/auth/login` | Web 用的 Cookie 登录；**移动端不使用** | 【已实现·后端现有】 |
| POST | `/auth/logout` | Web 用的会话登出；移动端改用 `/auth/revoke` | 【已实现·后端现有】 |
| GET | `/auth/me` | 已登录 → `{user, usage}`；Cookie 未登录返回 200 + `{user:null}`（Web 行为） | 【已实现·后端现有】 |
| GET/PATCH | `/settings` | 偏好 + 今日用量；儿童不能改时长/自由话题 | 【已实现·后端现有】 |
| POST | `/family/members/:id/password` | 家长重置成员密码；**没有本人改密接口** | 【已实现·后端现有】 |
| POST | `/auth/password` | 本人改密（旧密码校验） | 【待后端新增】 |

关键事实：

- 所有现有接口同时接受 `Authorization: Bearer <access_token>` 与 Cookie；**Web 端继续用 Cookie**，两套身份解析必须落到同一个 `userId`。
- 三个 Token 端点后端**正在实现（P0）**；联调前客户端用 Fake 网络层，不阻塞 UI/VM 开发。
- access 有效期 **1h**，refresh **30 天且一次性轮换**：每次 refresh 都返回新 refresh，客户端必须原子替换旧值；旧 refresh 不可重放。
- 退出登录：`POST /auth/revoke {refresh_token}` → 204，然后清本地 token 与缓存；revoke 失败也继续清本地。
- 刷新失败（401/400/refresh 已失效）→ 清两个 token → 跳登录；网络失败不要误清 token，提示重试。
- 登录失败：400 `bad_request`（缺字段）或 401 `unauthorized`（邮箱或密码不正确）；错误码细节以最终后端实现为准【待后端确认】。
- 【待后端确认】带无效/过期 Bearer 调用 `/auth/me` 时返回 401 还是 200 + `{user:null}`；客户端两种都要处理（401 走刷新，200+null 直接跳登录）。
- 儿童账号的每日时长上限、自由话题开关由家长设置；客户端隐藏入口只是体验，服务端会 403。

### 2.2 语料与评测

| 方法 | 路径 | 说明 | 状态 |
|---|---|---|---|
| GET | `/sentences?level=A1` | 语料列表；字段含 `id/text/translation_zh/level/tags/focus_phonemes`；儿童 `focus_phonemes` 为空 | 【已实现·后端现有】 |
| POST | `/attempts` | multipart：`audio/sentence_id/reference_text/mode/duration_ms` → **同步**评测结果 | 【已实现·后端现有】 |
| POST | `/attempts/async` | multipart 同上 → `{id,status:"pending"}`（201），后台评分 | 【已实现·后端现有】 |
| GET | `/attempts/status?ids=a,b,c` | 轮询：`{items:[{id,status,error,scored_at,result}]}`；最多 50 个 id | 【已实现·后端现有】 |
| POST | `/attempts/:id/retry` | 用已存录音重新评测，不重新上传 | 【已实现·后端现有】 |
| GET | `/attempts?limit=20` | 最近评测记录 | 【已实现·后端现有】 |
| GET | `/audio/:id` | 录音回放；id 可以是 attempt id 或 chat message id；**无 Range** | 【已实现·后端现有】 |
| POST | `/warmup` | 参考音静默预热（1–12 条），永远 200 | 【已实现·后端现有】 |

评测约束：

- 上传上限 **12MB**；服务端用 PyAV 解码，支持 webm/opus、wav、mp3、**m4a/aac**。
- 同步 `/attempts` 最长可能等 ~100s（pronounce 60s + feedback 40s），客户端超时给到 **120s**，并提示“稍后可重试”；**不要自动重发**（会重复计费）。
- 服务端在 voice 失败时仍保存录音和文本，返回 `degraded:true, retryable:true`，录音不会丢。
- 儿童载荷由服务端剥离 IPA，但**不隐藏低分**；低分展示策略必须客户端做。

### 2.3 ASR / TTS / 对话

| 方法 | 路径 | 说明 | 状态 |
|---|---|---|---|
| POST | `/asr` | multipart `audio` + `language=en / zh-CN` → `{text,provider,duration_ms,language}` | 【已实现·后端现有】 |
| POST/GET | `/tts` | `{text,rate,voice?,format?}` → 二进制音频；默认 wav，对话建议 mp3 | 【已实现·后端现有】 |
| GET | `/chat/scenarios` | 按年龄过滤的场景列表 | 【已实现·后端现有】 |
| POST | `/chat/sessions` | `{scenario_id}` → 新会话 + 开场白 | 【已实现·后端现有】 |
| GET | `/chat/sessions` | 最近 30 个会话 | 【已实现·后端现有】 |
| GET | `/chat/sessions/:id` | 会话详情；**不含 `messages[].pron`** | 【已实现·后端现有】 |
| GET | `/chat/sessions/:id/messages` | 消息列表；助手轮次带 `pron`（后台异步评分，需轮询） | 【已实现·后端现有】 |
| POST | `/chat/sessions/:id/turn` | 一轮对话；multipart `audio` + **必填 `text`**；**只返回助手文本** | 【已实现·后端现有】 |

> **重要核对结论（与“内部 ASR→LLM→TTS”的说法不同）**
> 现有 `/turn` 路由**不替客户端做 ASR**：它要求 `text` 非空，`audio` 只用于在 `after()` 里做后台发音评估；响应也**不返回 TTS 音频字节**。
> 因此“只有语音输入”的移动端一轮对话需要三步：
> 1) `POST /asr` 得到 `text`；
> 2) `POST /chat/sessions/:id/turn`（multipart，带同一份 `audio` + `text`）→ 助手文本；
> 3) `POST /tts` 朗读 `reply`。
> 发音分**不在 turn 响应里**，也不在 `/sessions/:id` 里：turn 之后轮询 `GET /chat/sessions/:id/messages`，读助手消息的 `pron` 字段（`pron/accuracy/fluency/completeness/weak_phonemes/words`）。页面可以先展示文字，评分到了再补；儿童端只用它决定鼓励/提示，不显示数字。
> 若希望后端在 `/turn` 内部完成 ASR 并直接返回 TTS，需要【待后端新增】。已列入 `open-questions.md` Q2（不阻塞 M1）。

### 2.4 材料 / 故事 / OCR

| 方法 | 路径 | 说明 | 状态 |
|---|---|---|---|
| GET | `/materials?kind=page`、`kind=story` | 家庭共享材料列表 | 【已实现·后端现有】 |
| POST | `/materials` | `{title,text,image_b64?,kind?,source?,source_zh?,level?}` | 【已实现·后端现有】 |
| GET/PATCH/DELETE | `/materials/:id` | 详情 / 改名改文 / 删除（创建者或家长） | 【已实现·后端现有】 |
| GET | `/materials/:id/image` | 图片；**需要 `Authorization`**，不能直接用 `Image(url)` | 【已实现·后端现有】 |
| POST | `/ocr` | multipart `image`，≤10MB；`return_image=1` 时返回 `image_jpeg_b64` | 【已实现·后端现有】 |
| POST | `/story/rewrite` | `{text_zh,level,max_sentences,use_weak_phonemes?}` → 英文句子 | 【已实现·后端现有】 |
| POST | `/story/retell` | `{material_id,story_sentences,transcript,level}` → 覆盖度/反馈，**不评发音分** | 【已实现·后端现有】 |
| POST | `/story/:id/illustrate` | `{force?,style?}` → 生成/替换插画 | 【已实现·后端现有】 |

能力开关以 `GET /health` 的 `voice.capabilities` 为准：

- `ocr=false` → “拍照识别”置灰，并给可操作提示；
- `heic=false` → 上传前拦截 HEIC，提示改用拍照/JPEG；
- `phoneme_level=false` → 只显示单词级粗评，不显示 IPA；
- `image` 缺失/未配置 → 插画入口置灰。

### 2.5 诊断 / 复习 / 盲测 / 家庭 / 建议

| 方法 | 路径 | 说明 | 状态 |
|---|---|---|---|
| GET | `/diagnosis` | 薄弱音素诊断；儿童无 IPA | 【已实现·后端现有】 |
| GET/POST | `/review` | 错音本 + SRS 评分 `again/hard/good/easy` | 【已实现·后端现有】 |
| GET/POST | `/blind-tests` | 历史/周环比；开始或恢复盲测 | 【已实现·后端现有】 |
| POST | `/blind-tests/:id/finish` | 结束盲测，之后才可读分数 | 【已实现·后端现有】 |
| GET | `/parent/summary` | 仅家长；全家汇总 + 成员明细 + 盲测周报 | 【已实现·后端现有】 |
| GET/POST | `/family/members` | 仅家长；成员列表 / 新建 | 【已实现·后端现有】 |
| PATCH | `/family/members/:id` | 仅家长；昵称/水平/时长/自由聊/头像 | 【已实现·后端现有】 |
| GET/POST | `/suggestions` | POST 所有人可提；GET 仅家长 | 【已实现·后端现有】 |
| PATCH | `/suggestions/:id` | 仅家长；open/read/resolved | 【已实现·后端现有】 |
| GET | `/health` | web 自身 + voice 可达性/能力，**无需登录** | 【已实现·后端现有】 |

### 2.6 错误码（服务端实际会出现的）

| HTTP | code | 含义 | 客户端处理 |
|---|---|---|---|
| 400 | `bad_request` | 参数/表单不合法 | 优先展示服务端 `message`；不要重试 |
| 400 | `content_unsafe` | 插画内容审核不通过 | 提示换说法，不重试 |
| 401 | `unauthorized` | 未登录/会话过期 | 清 token，回登录页 |
| 403 | `forbidden` | 角色/归属不允许 | 提示“仅家长可用”或“无权访问” |
| 404 | `not_found` / `audio_not_found` | 资源不存在 | 刷新列表或返回 |
| 409 | `conflict` / `session_closed` / `blind_test_closed` / `no_practiced_sentences` / `no_attempts` / `no_audio` / `blind_attempt_no_retry` | 状态冲突 | 按 code 给具体文案；不要盲目重试 |
| 410 | `audio_gone` | 录音文件已不存在 | 重新录，不重试评测 |
| 413 | `payload_too_large` | 录音 >12MB / 图片 >10MB / 文本超限 | 本地先拦；服务端兜底 |
| 429 | `daily_limit_reached` | 儿童达到每日上限 | 展示 `detail` 用量，停止提交 |
| 500 | `internal_error` | 服务端异常 | 可重试一次 |
| 502 | `provider_error` | voice/上游失败 | 录音已存则提示“稍后重试评测” |
| 503 | `provider_unavailable` / `ocr_unavailable` / `story_unavailable` / `retell_unavailable` / `illustration_unavailable` | 能力未启用/依赖缺失 | 置灰入口 + 可操作提示 |
| 504 | `provider_timeout` | 上游超时 | 可重试；提示“这次比较慢” |

客户端还要自己产生几类错误：`network_unreachable`、`timeout`、`mic_denied`、`mic_unavailable`、`record_too_short`、`record_too_large`、`playback_failed`、`cache_corrupt`。

---

## 3. DevEco Studio 工程结构

### 3.1 顶层目录

```text
hos/
├── AppScope/                         # 应用级配置（M0 创建）
│   ├── app.json5                     # bundleName / versionCode / icon / label
│   └── resources/
├── build-profile.json5               # 产品、签名、SDK 版本（M0 创建）
├── hvigorfile.ts
├── oh-package.json5                  # 运行时依赖：空
├── entry/                            # HAP：应用壳、导航、登录门禁、全局状态
│   ├── build-profile.json5
│   ├── hvigorfile.ts
│   ├── oh-package.json5
│   └── src/main/
│       ├── module.json5              # abilities / requestPermissions
│       ├── ets/
│       │   ├── entryability/
│       │   │   └── EntryAbility.ets
│       │   ├── pages/                # 只放壳页面：Index / Launch / NotFound
│       │   ├── components/           # 壳级组件：AppShell / BottomNav / ChildFrame
│       │   ├── viewmodel/            # AppVM / SessionVM / UsageVM
│       │   ├── service/              # NavigationService / BootstrapService
│       │   └── utils/                # 仅 entry 用的小工具
│       └── resources/
│           ├── base/element/         # color.json / string.json / float.json
│           ├── dark/element/         # M4 深色 token
│           └── rawfile/
├── features/                         # HAR：按业务域拆，入口只做路由装配
│   ├── auth/                         # 登录、登出、修改密码
│   ├── practice/                     # 跟读练习
│   ├── flow/                         # 连读
│   ├── chat/                         # 对话
│   ├── story/                        # 故事、材料、插画、复述
│   ├── blindtest/                    # 盲测
│   ├── diagnosis/                    # 发音诊断 + 错音本
│   ├── parent/                       # 家长面板 + 成员管理
│   └── settings/                     # 设置 + 提建议
└── commons/                          # HAR：跨业务复用，禁止反向依赖
    ├── net/                          # HttpClient / TokenSession / ApiError / DTO
    ├── audio/                        # Recorder / Player / AudioCoordinator
    ├── storage/                      # AssetStore / Preferences / FileCache
    ├── design/                       # DesignTokens / 通用组件 / 图表
    ├── model/                        # 共享领域模型（User/Sentence/Attempt...）
    └── util/                         # 时间/格式化/重试/日志脱敏
```

### 3.2 feature 模块标准布局

每个 feature 都是一个 HAR，结构统一：

```text
features/practice/
├── Index.ets                         # 对外唯一导出：页面构建器/路由表
├── oh-package.json5
├── build-profile.json5
├── hvigorfile.ts
└── src/main/
    ├── module.json5
    ├── ets/
    │   ├── pages/                    # PracticePage.ets
    │   ├── components/               # SentenceList / ScorePanel / WordBars...
    │   └── viewmodel/                # PracticeVM.ets
    └── resources/
        └── base/element/
```

**依赖规则（强约束）**：

```text
entry ──► features/<x> ──► commons/*
  │            │
  └────────────┴──► commons/model, commons/design, commons/net
features/a  ──✗──► features/b        # 业务模块之间不直接依赖
commons/*   ──✗──► features/*, entry # commons 必须可独立复用
```

- 跨 feature 跳转只通过 `NavigationService` + 路由常量，不 import 对方页面。
- 共享 DTO 放 `commons/model`，共享 HTTP 放 `commons/net`，共享录音/播放放 `commons/audio`。
- `entry` 只做：启动、登录门禁、底部导航、全局错误横幅、把 feature 的 `NavDestination` 注册进 `NavPathStack`。

### 3.3 `entry/src/main/ets/` 模块划分

| 目录 | 放什么 | 不放什么 |
|---|---|---|
| `pages/` | `Index.ets`（Navigation 根）、`LaunchPage.ets`、`NotFoundPage.ets` | 具体业务页面（在 features 里） |
| `components/` | `AppShell`、`BottomNav`、`GlobalErrorBanner`、`ChildModeFrame`、`LoadingOverlay` | 业务结果卡片（在 features 里） |
| `viewmodel/` | `AppVM`（启动态/健康检查）、`SessionVM`（当前用户/角色/儿童模式）、`UsageVM`（今日用量） | 单页业务状态 |
| `service/` | `NavigationService`、`BootstrapService`（冷启动恢复会话）、`DeeplinkService` | HTTP 底层实现（在 commons/net） |
| `utils/` | 仅 entry 用的常量、路由参数解析 | 通用工具（放 commons/util） |

### 3.4 模块职责与“不做什么”

| 模块 | 职责 | 明确不做 |
|---|---|---|
| `commons/net` | 唯一 HTTP 出口；Bearer 认证与单飞刷新；multipart；下载；错误归一化；取消 | 不拼业务 URL 语义、不做页面跳转 |
| `commons/audio` | 录音/播放状态机；权限；文件生命周期；互斥 | 不做上传、不做评分 UI |
| `commons/storage` | Asset 中的 access/refresh token、Preferences 非敏感配置、文件缓存/LRU | 不存明文密码、不存录音长期副本 |
| `commons/design` | token、基础组件、图表、儿童尺寸 | 不依赖业务 DTO |
| `features/*` | 页面 + VM + 业务组件 | 不直接 `http.createHttp()` |
| `entry` | 壳、路由、会话门禁、全局错误 | 不承载具体业务 |

---

## 4. 最低 API 与兼容策略

| 项 | 值 | 说明 |
|---|---|---|
| SDK 基线 | **API 20**（HarmonyOS 6.0.0） | 最低、编译、目标三处都取 20；不面向更低版本的旧设备 |
| `compileSdkVersion` | **20** | 以 DevEco Studio 6.0.0 安装的 SDK 为准；`@kit.*` 聚合导入稳定 |
| `compatibleSdkVersion` | **20** | 低于 20 不安装（节省兼容分支） |
| `targetSdkVersion` | **20** | 首个版本不追 API 21+ |
| 语言 | ArkTS（严格子集） | 不使用 `any`、动态属性、原型改写、`eval` |
| 状态管理 | V1：`@State/@Prop/@Link/@Observed/@ObjectLink` + AppStorage | V2（`@ObservedV2/@Trace`）暂不使用 |
| 路由 | `Navigation` + `NavPathStack` | 不使用 `router.pushUrl` 作为主路由 |
| 媒体 | `@kit.MediaKit` 的 AVRecorder/AVPlayer | 不引入 FFmpeg/第三方播放器 |
| 网络 | `@kit.NetworkKit` 的 `http` + `Authorization` | 不引入 axios/okhttp 风格库 |
| 安全存储 | `@ohos.security.asset` / `@kit.AssetStoreKit` | access/refresh 两个 token；不写 Preferences |

**兼容策略（API 20 基线）**：

- 只使用 API 20 及以下已公开的能力；API 21+ 的能力即使更方便，也不作为首版依赖。
- 认证改 Token 后，**不再需要 Cookie 自动管理**；`http` 的 `enableAutoCookie` 官方 d.ts 标注 `@since 26.0.0`，API 20 不可用（以本机 SDK 的 `@ohos.net.http.d.ts` 为准【待确认】），本方案不依赖它。
- 所有 `@kit.*`、Asset Store、AVRecorder 的实际行为仍以 DevEco 编译 + 真机为准；本文不做“已验证”的承诺。

> 【待真机验证】以上 API 在目标机型/系统版本上的实际可用性，以 DevEco Studio 编译 + 真机安装为准；本文不做“已验证”的承诺。

---

## 5. 构建与运行

### 5.1 环境

- DevEco Studio 6.0.0 Release 或更高（随 SDK API 20）；以实际安装的 SDK 为准。
- HarmonyOS NEXT 真机（API 20 / HarmonyOS 6.0.0 及以上；录音/播放/权限必须真机验证，模拟器不作为验收依据）。
- Node.js 版本按 DevEco 自带工具链，不额外安装全局包。

### 5.2 首次创建工程

1. DevEco Studio → Create Project → **Empty Ability**，语言 ArkTS，设备 Phone。
2. `bundleName` 建议 `com.family.englishcoach`（**待拍板**，见 open-questions）。
3. `compileSdkVersion = 20`、`compatibleSdkVersion = 20`、`targetSdkVersion = 20`。
4. 按第 3 节创建 `features/*`、`commons/*` 的 HAR 模块，并在 `entry/oh-package.json5` 中通过本地路径依赖。
5. 把本文档的目录骨架作为占位；M0 再填实现。

### 5.3 服务端地址配置

```text
// commons/model/src/main/ets/config/AppConfig.ets（示意）
export class AppConfig {
  static readonly API_BASE_RELEASE: string = 'https://english.dreamsearch.top';
  static readonly API_BASE_DEBUG: string = 'https://english.dreamsearch.top';
  static baseUrl(): string { /* BuildProfile.DEBUG 分支，可在设置页覆盖 */ }
}
```

- 生产/家庭使用固定 `https://english.dreamsearch.top`；该域名只在家庭网络/VPN 内可达。
- 调试可切到 `http://192.168.x.x:3000`，但 **release 包禁止明文 HTTP**；若系统拦截明文，需在工程网络配置中显式放行（【待真机验证】具体配置项）。
- 设置页提供“服务器地址”只对 debug 包可见，避免儿童误改。
- 启动时先 `GET /api/health`（无需登录）判断“NAS 是否可达”，再决定是否恢复会话。

### 5.4 构建与安装（示意命令）

```bash
# 在 hos/ 根目录
./hvigorw clean
./hvigorw assembleHap --mode module -p product=default -p buildMode=debug

# 安装到已连接真机
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap

# 启动（bundleName 以实际为准）
hdc shell aa start -a EntryAbility -b com.family.englishcoach
```

> 签名：debug 用 DevEco 自动签名；release 用家庭自有证书/Profile。**证书、密钥、密码不入库**。

### 5.5 验收环境

| 场景 | 要求 |
|---|---|
| 家庭 Wi-Fi | 域名可解析到 NAS，HTTPS 证书有效 |
| 4G/公网 | 预期不可达；App 要显示“请连接家庭 Wi-Fi”，而不是笼统“网络错误” |
| 儿童账号 | 无 IPA、无低分数字、按钮 ≥56vp、TTS 默认 slow |
| 家长账号 | 可见家长面板、成员管理、建议收件箱 |
| 弱网 | 录音上传失败可重试；轮询可恢复；不重复计费 |

---

## 6. 依赖策略

**运行时零三方依赖**。只使用系统 Kit：

- `@kit.NetworkKit`（http）
- `@kit.MediaKit`（AVRecorder/AVPlayer）
- `@kit.AudioKit`（音频焦点/打断事件，按需）
- `@kit.CoreFileKit`（fileIo、picker）
- `@kit.CameraKit`（cameraPicker，系统拍照，无需 CAMERA 权限）
- `@kit.ImageKit`（图片解码为 PixelMap）
- `@kit.ArkUI` / `@kit.AbilityKit` / `@kit.BasicServicesKit`
- `@kit.AssetStoreKit` / `@ohos.security.asset`（access/refresh token）
- `@kit.ArkData`（preferences；如使用 relationalStore 也在其中）
- `@kit.PerformanceAnalysisKit`（hilog，仅调试）

允许的开发期依赖：DevEco 自带构建工具、官方 Hypium 测试框架（可选）。

禁止：

- 任何统计/推送/广告/崩溃上报 SDK（隐私与“零外联”要求）。
- WebView 承载业务页面（认证/权限/隐私都不可控）。
- 第三方音频转码库（服务端已解码）。
- 第三方图标字体/图片加载库（用系统 SymbolGlyph + ImageSource）。

---

## 7. 编码与工程约定

### 7.1 ArkTS 严格模式边界

HarmonyOS NEXT 的 ArkTS 是 TypeScript 的**严格子集**，不是“带类型的 JS”。本项目按以下约束写：

- 禁止 `any` / `unknown` 泛滥；JSON 解析后立即转 DTO 并校验，不用动态属性访问。
- 禁止结构化类型“鸭子类型”；接口/类显式声明，跨模块用 `interface`。
- 禁止 `eval`、`Function` 构造、原型改写、`with`、动态 `import()`。
- 对象字面量必须有明确类型；不用 `as object` 绕过检查。
- 不使用 `@ObservedV2/@Trace`（状态管理 V2）；统一 V1。
- 以 API 20 为基线，不使用 API 21+ 的新能力；认证不依赖 Cookie 自动管理。
- 装饰器只用于 ArkUI/状态管理；不在普通类上自定义装饰器。
- 所有 `Promise` 都要 `await` 或显式 `void`；不允许“发出去就不管”的写操作。

> 是否启用更严格的 lint/编译选项，见 [docs/open-questions.md](docs/open-questions.md) Q6。

### 7.2 命名与文案

- 命名：页面 `XxxPage.ets`，组件 `XxxCard.ets`，VM `XxxVM.ets`，服务 `XxxService.ets`。
- 每个 feature 只暴露 `Index.ets`；内部实现不跨模块导出。
- 所有用户可见文案走 `resources/base/element/string.json`；儿童版文案单独 key（`child_` 前缀），不要在代码里三元表达式堆文案。
- 所有颜色/字号/圆角走 token（`$r('app.color.ec_*')` / `$r('app.float.ec_*')`），禁止 `#hex` 散落页面。
- 日志脱敏：不打印 access/refresh token、邮箱、录音路径、识别文本；只打印 `requestId/status/code/耗时`。
- 网络层不得吞错：统一抛 `ApiError`，由 VM 决定展示；页面不得直接解析 `error.code`。
- 所有异步操作可取消：页面 `aboutToDisappear` 取消轮询/下载/播放；HTTP 请求调用 `destroy()`。

---

## 8. 安全基线

- 只与 `https://english.dreamsearch.top` 通信；release 禁止明文 HTTP。
- 依赖系统默认 CA 校验；不做“忽略证书错误”的开关。是否加证书 pinning 留到 M4（见 open-questions）。
- access/refresh token 存 **Asset Store Kit**（`@ohos.security.asset`，别名 `ec_access_token`/`ec_refresh_token`），不写 Preferences、不写日志、不进备份。
- 刷新只在 `commons/net` 内做，单飞 + 一次性轮换；只有 refresh 被拒（401/400）才清 token 跳登录，网络失败保留 token 并提示重试。
- 客户端不缓存密码；登录页“记住邮箱”只存邮箱（可选，默认关）。
- 录音/图片只落 `cacheDir`，上传成功后按策略清理；退出登录清空。
- 儿童账号不显示 IPA、不显示低分；不上传通讯录/位置/设备标识。
- 所有 AI 能力在服务端；客户端不内置模型、不直连 voice。

> 隐私边界的关键提醒：当前部署是 `PROVIDER_MODE=hybrid`，**录音/文本/图片会离开家庭网络**——音频由 NAS 发往 Azure（ASR/发音评测/TTS），文本发往 DeepSeek（对话/改写/复述），书页图片与插画提示发往 DeepSeek/智谱。客户端不能承诺录音不离开家庭网络。要做到完全本地，需要服务端切到 `local` 模式并备好本地模型，**当前未部署**。详见 [docs/permissions-and-privacy.md](docs/permissions-and-privacy.md) 与 open-questions Q1。

---

## 9. 交付边界与后续

本目录当前交付：

- 8 份核心设计文档（本 README + `docs/` 下 7 份）+ 2 份 ADR（0001 已被取代、0002 现行）；
- 目录骨架：`entry/`、`features/*`、`commons/*`，以及 `.gitkeep` 占位；
- **没有** `module.json5`、`app.json5`、`oh-package.json5` 等可编译配置，避免留下“看起来能跑其实跑不起来”的半成品。

M0 开始时按 [docs/roadmap.md](docs/roadmap.md) 创建工程文件，并以本 README 的结构为准。

---

## 10. 参考（外部资料，均为“待真机验证”的 API 依据）

- AVRecorder 录音指导：<https://github.com/openharmony/docs/blob/master/en/application-dev/media/media/using-avrecorder-for-recording.md>
- AVPlayer 播放指导：<https://github.com/openharmony/docs/blob/master/en/application-dev/media/media/using-avplayer-for-playback.md>
- Media Kit 支持格式（wav/mp3/m4a 等）：<https://github.com/openharmony/docs/blob/master/en/application-dev/media/media/media-kit-intro.md>
- `@ohos.net.http`（`multiFormDataList`、`maxLimit`、请求头）：<https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-network-kit/js-apis-http.md>
- 申请用户授权（MICROPHONE）：<https://github.com/openharmony/docs/blob/master/en/application-dev/security/AccessToken/request-user-authorization.md>
- Asset Store Kit 新增资产：<https://github.com/openharmony/docs/blob/master/en/application-dev/security/AssetStoreKit/asset-js-add.md>
- HarmonyOS 6.0.0(20) 版本说明（API 20 基线）：<https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/overview-600>
- CameraPicker（无需 CAMERA 权限）：<https://github.com/openharmony/docs/blob/master/en/application-dev/media/camera/camera-picker.md>

# English Coach iOS 客户端

> 状态：**M0 垂直切片代码已落地（未编译验证）**。Swift/SwiftUI 源码在 `EnglishCoach/`，工程用 XcodeGen 生成。
> **本仓库没有 macOS/Xcode 环境：所有 Swift 代码均未编译、未在真机运行。** 必须由维护者在 Xcode 26 中构建验证。
> 后端（Next.js `web` + FastAPI `voice`）已在家庭 NAS 上跑通，iOS 端所有能力都通过 `web` 的 `/api/*` 调用。

---

## 0. M0 代码现状（必读）

### 0.1 已实现（代码层，未验证）

| 模块 | 文件 | 说明 |
| --- | --- | --- |
| 工程 | `project.yml` | XcodeGen：iOS 26.0、Swift 6、SwiftUI 生命周期，仅 app target，无 SwiftPM 依赖 |
| App | `App/EnglishCoachApp.swift`、`App/AppEnvironment.swift` | `@main`、根切换（启动/登录/已登录）、依赖装配、自动登录、退出 |
| 配置/会话 | `Core/AppConfig.swift`、`Core/Session/TokenStore.swift`、`Core/Session/TokenRefresher.swift` | baseURL 存 UserDefaults；token 存 Keychain；actor 单飞刷新 |
| 网络 | `Core/Networking/*` | async/await、Bearer 注入、401→单飞刷新→重放一次、错误中文映射（成人/儿童）、multipart、TTS 字节 |
| 音频 | `Core/Audio/AudioRecorder.swift`、`AudioPlayer.swift` | m4a/AAC 16kHz 单声道 65kbps、权限三态、60s/500ms/静音/12MB 校验、录音前停播、电平；播放完成轮询 |
| 设计系统 | `Core/DesignSystem/*` | 颜色/间距/圆角/字体令牌；primary/ghost/text/destructive 按钮；卡片、空态、错误、权限卡 |
| 登录 | `Features/Auth/*` | 邮箱+密码+基地址、演示账号邮箱快捷填充、测试连接、错误内联、自动登录 |
| 练习 | `Features/Practice/*` | 按 CEFR 列表 → 句子详情 → 播放示范/跟我读 → 录音 → 上传评分 → 词级进度条/星级 → 下一句；loading/empty/error/权限态 |
| 资源 | `Resources/Info.plist`、`Resources/PrivacyInfo.xcprivacy` | 麦克风/本地网络文案；ATS 默认无例外；隐私清单（音频/邮箱/UserDefaults） |

与后端实际实现对齐的关键点（读 `english-coach/web` 源码确认，**未运行时验证**）：

- `GET /api/auth/me` 返回 `{ user, usage }`，且 Bearer 失效时是 **200 + `user:null`**，不是 401。因此冷启动在已有 refresh 时**主动刷新一次**，不依赖 401 触发。
- `POST /api/attempts` 的响应是 `{ attempt_id, degraded, retryable, message, result, feedback, usage }`；分数/词/issue 在 `result` 下，`feedback` 是对象（`summary/praise/points/closing`）。
- “儿童”判定是 **`ageBand == "child"`**（不只是 `role`）；客户端两者都看。
- 登录失败返回 401 + `code=bad_request`；连续失败 5 次返回 429 `too_many_requests`；儿童超时返回 429 `daily_limit_reached`。
- 录音上传字段与顺序：`audio` → `sentence_id` → `reference_text` → `mode=scripted` → `duration_ms`。

### 0.2 生成并运行工程（在 Mac 上）

```bash
cd ios
brew install xcodegen     # 只需一次
xcodegen generate         # 生成 EnglishCoach.xcodeproj（不提交，已加入 .gitignore）
open EnglishCoach.xcodeproj
```

1. Xcode 里选择 app target → Signing & Capabilities → 选自己的付费 Team；Bundle ID 默认 `top.dreamsearch.englishcoach`。
2. 选择 iOS 26 真机/模拟器，Run。**真机是验收基准**，模拟器的麦克风/路由不可信。
3. 没有 Assets.xcassets：预计仍可构建（**未验证**），但会缺 App 图标（M1 补），Xcode 可能给资源警告。

为什么用 XcodeGen 而不是“Xcode 新建 App 再拖源码”：本仓库无法生成/校验 `pbxproj`，手写或让用户拖文件容易产生“文件没进 target”的隐性错误；`project.yml` 是文本，review 得到，且 `xcodegen generate` 可重复生成。代价是用户首次需要安装 xcodegen（`brew` 一行）。

### 0.3 填基地址 / 登录

- 首次启动 → 登录页 → “服务器地址”填 `https://english.dreamsearch.top/api`（只填主机名会自动补 `/api`）。
- 地址存 `UserDefaults`；**token 与服务器绑定**：改地址后登录会先清旧 token。
- `POST /api/auth/token` → token 写 Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）；重启后自动用 refresh 换 access，再 `GET /auth/me`。
- 退出：确认后 `POST /api/auth/revoke` → 清 Keychain → 回登录页；离线时失败也清本地（已知限制：服务端 refresh 最长 30 天仍有效）。
- 演示账号（种子数据，非生产承诺）：孩子 `girl@example.com` / 密码 `Girl12345!`（A1）；家长 `dad@example.com` / 密码 `Dad12345!`（B1）。登录页“填入演示邮箱”**只填邮箱**（共享文档要求不猜密码，也避免把密码编译进 App），密码需手动输入；若 NAS 用 `BOOTSTRAP_*` 覆盖过种子，以实际部署为准。

### 0.4 明确未验证（不要在验收前当作已完成）

- **能否编译**：未执行 `xcodebuild`，Swift 6 严格并发/API 可用性均可能报错。仅用 tree-sitter 做过**语法解析**（无 ERROR 节点），这不等于类型检查或编译通过。
- **XcodeGen 产物**：`project.yml` 的 target/scheme/Info.plist 排除规则未实际生成验证。
- **Keychain**：写入/读取/卸载重装/换机行为未在真机验证。
- **单飞刷新**：并发 401 只刷新一次、一次性轮换的竞态未写单测、未实测；**退出登录与“在飞刷新”并发时，刷新结果理论上可能把 token 写回 Keychain**（M0 未加会话代际保护）。
- **录音**：16kHz/单声道/65kbps 的实际文件参数、`AVAudioFile` 读时长、服务端解码均未真机验证；静音阈值 `-45dB` 未调。
- **音频路由**：蓝牙 HFP、拔耳机、来电/闹钟中断、锁屏后台播放**未实现/未验证**（M1）。
- **接口运行时形状**：响应结构来自后端源码阅读，没有用真实 token 跑通；字段缺失/类型变化可能仍导致 `decoding`。
- **证书**：NAS 若是自签/内网 CA，iOS 会直接拒绝；需在设备上安装并信任证书，本项目**不提供 ATS 例外**。
- **UI**：未在小屏、Dynamic Type AX 字号、横屏（本期锁定竖屏）验证；自定义字号未用 `relativeTo` 缩放。
- **打包/TestFlight**：没有 Assets.xcassets/App Icon，也没有签名 Team 配置；Archive/TestFlight 上传前必须补图标并设置 Team。

### 0.5 待办（M1 及以后，代码中未留 TODO 占位）

- 语料快照/TTS 磁盘 LRU 缓存、离线三态横幅与自动重试；`GET /api/audio/:id` 服务端录音回放。
- 录音中断/路由变化监听、后台播放与锁屏控制、蓝牙专项。
- GET 自动重试策略（当前失败后用显式“重试”按钮）、并发上传限制。
- 单元测试目标（ErrorMapper、Multipart、ScorePresenter、TokenRefresher 并发 401）与 UI 测试。
- `UIBackgroundModes=audio` 已声明但 M0 没有锁屏控制逻辑；若不需要后台播放可先移除。
- 登录页“记住邮箱”、设置页、家长面板、连读、对话、故事、盲测、诊断。
- **分层偏差（M0 有意简化）**：`Features/Auth`、`Features/Practice` 的 ViewModel 直接持有 `AppEnvironment`，严格来说违反“App → Features → Core”的单向依赖；M1 抽 `SessionStore` / API 协议后注入，避免 Feature 依赖 App。

### 0.6 M0 验收清单（在 Mac/真机上逐条勾）

- [ ] `xcodegen generate` 成功，Xcode 无编译错误（Swift 6）。
- [ ] 新装 → 填地址 → 演示账号 → 登录成功；杀进程重开**无需重登**。
- [ ] access 过期/失效后业务请求自动刷新并重放一次，用户无感；refresh 被拒才回登录页。
- [ ] 语料列表按账号 CEFR 加载；下拉刷新；空/错误/loading 三态可见。
- [ ] 选中 A1 句子 → 播放示范 → 录音 → 看到分数与词级结果；端到端 ≤8s（局域网）。
- [ ] 播放中开始录音，示范音立即停止，无叠音。
- [ ] 拒绝麦克风 → 引导卡 → 去设置开启 → 返回后可直接录音。
- [ ] 60s 自动停止并提交；<500ms 拦截；无声音提示；12MB 预检。
- [ ] 断网提交：可见错误 + 重试；不把网络错误误报成“登录过期”。
- [ ] 孩子账号：无 IPA、无数字分、无红色低分，按钮高度 ≥56pt。
- [ ] 退出登录调用 revoke 并回登录页；旧 refresh 再用返回 401。
- [ ] 真机 `afinfo` 确认录音为 16kHz mono AAC（m4a）。
- [ ] 自签证书/NAS 网络：Safari 能打开同一地址；App 能连。

---

## 1. 文档目的与范围

| 项 | 说明 |
| --- | --- |
| 目标 | 为 `English Coach` 提供一份可直接排期、直接开工的 iOS 客户端设计文档 |
| 范围内 | 分层架构、网络与认证、音频方案、页面结构、设计令牌、里程碑、待决问题、**M0 垂直切片源码** |
| 范围外 | 后端改动、M1+ 功能实现、测试数据构造、分发素材（图标/截图/TestFlight 测试说明） |
| 读者 | iOS 实现者、后端维护者、产品决策者 |
| 基准 | 本文档事实来自「已跑通的后端 + 任务给定的接口清单」；未经验证的部分统一标 `【待确认】` |

### 1.1 状态标注约定（全文强制）

| 标注 | 含义 |
| --- | --- |
| **【已实现·后端现有】** | 后端已经存在、客户端直接调用的能力 |
| **【待后端新增】** | 需要后端配合改动，客户端不能单方面完成 |
| **【客户端自行实现】** | 纯客户端逻辑，不需要后端参与 |
| **【待确认】** | 契约/行为尚不明确，需实测或产品拍板，见 `docs/open-questions.md` |

---

## 2. 系统上下文

### 2.1 拓扑

```
┌──────────────┐   HTTPS（NAS 内网可达，公网不可达）
│  iOS App     │ ─────────────────────────────┐
└──────────────┘                              │
                                              ▼
                             ┌────────────────────────────────┐
                             │ english.dreamsearch.top        │
                             │  web (Next.js, :3000)          │
                             │  · 账号/会话/SQLite/业务 API    │
                             │  · /api/* 反向代理 voice        │
                             └──────────────┬─────────────────┘
                                            │ 内网 HTTP
                                            ▼
                             ┌────────────────────────────────┐
                             │  voice (FastAPI, :8100)        │
                             │  ASR / PA 评测 / TTS / LLM     │
                             │  OCR / 文生图                  │
                             └────────────────────────────────┘
```

**硬性约束：App 不直连 `voice:8100`。** 客户端只认识 `https://english.dreamsearch.top/api`，voice 的地址、鉴权、重试全部属于 web 的职责。任何“客户端直接调 8100 提速”的想法都不在本文档范围内（会绕过鉴权、绑定内网端口、破坏后续上云）。

### 2.2 影响客户端设计的后端事实

| 事实 | 对客户端的影响 |
| --- | --- |
| 服务在家庭 NAS，**公网不可达** | 只能在局域网使用；必须提供可配置 base URL + 明确的“连不上服务器”引导；App 不能假设随时在线 |
| 认证：**Web 用 Cookie；移动端用 Bearer Token**【待后端新增·P0】 | 登录走 `POST /auth/token`，access 1h / refresh 30d；网络层必须**单飞刷新**，token 存 Keychain，见 ADR-0003 |
| 录音上传上限 **12MB**，PyAV 解码支持 webm/opus、wav、mp3、m4a/aac | iOS 用 AVAudioRecorder 出 **m4a/AAC**，统一 **16kHz 单声道 65kbps**，体积远低于上限 |
| 对话**不是** turn 内部 ASR→TTS，而是三步：`POST /asr` → `POST /chat/sessions/:id/turn`（multipart，**text 必填** + audio）→ `POST /tts` | Chat 页要自己编排三次调用；turn 只返回助手文本，不返回音频 |
| 对话发音评分在 `GET /chat/sessions/:id/messages` 的 `pron` 字段（后台异步） | 每轮结束后要**轮询** messages 补评分；`GET /chat/sessions/:id` 不含 `pron` |
| ASR 曾修复“停顿只识别前半句”→ 服务端改为**连续识别** | 客户端**绝不允许把一句话切成多段上传**；一段录音 = 一次请求 |
| TTS 首次合成 1–3s，命中缓存 <50ms | 播放要能容忍首帧延迟；缓存键必须与请求参数严格一致，否则缓存命中率失真 |
| 连读模式用 `/attempts/async` + 轮询 | 录完即进入下一句，UI 永不阻塞在评分上 |
| 评分、ASR、TTS、OCR、改写、生图**全在服务端** | 客户端只做：录音 → 上传 → 播放 → 展示；**离线无法评分** |
| 错误统一 `{error:{code,message}}` | 网络层必须集中映射为本地化文案 + 可操作动作，见 `docs/architecture.md` §5 |
| 孩子账号 `role=child` | 不显示 IPA、不显示低分、大按钮；这是**产品规则**，要在设计系统层实现，而不是散落在页面里 |

---

## 3. 技术选型

| 维度 | 选型 | 理由 |
| --- | --- | --- |
| UI | SwiftUI（纯 SwiftUI，无 UIKit 页面） | 与单兵开发成本匹配；`PhotosPicker`/`AVAudioSession` 均有 SwiftUI 侧封装 |
| 状态 | Observation（`@Observable`）+ `@MainActor` Store | iOS 17 起可用；最低版本 26，无兼容分支，见 ADR-0002 |
| 并发 | async/await + Swift 6 语言模式（严格并发检查） | 网络/轮询/录音状态天然异步；刷新用 actor 单飞 |
| 网络 | `URLSession` + Bearer 注入 + Keychain（零第三方） | 认证见 ADR-0003；不读写 Cookie |
| 音频 | AVFoundation：`AVAudioSession` / `AVAudioRecorder` / `AVAudioPlayer` | 系统能力足够：录音、播放、路由切换、后台播放 |
| 图表 | Swift Charts（系统框架） | 语调曲线、掌握度趋势，零依赖 |
| 本地存储 | 文件（JSON/二进制）+ `UserDefaults` + Keychain | token 只进 Keychain；业务数据量小（600 句语料、TTS 缓存），不引入数据库 |
| 图片选择 | `PhotosPicker`（PhotosUI）+ 相机 `UIImagePickerController` 包装 | 不申请相册读权限；HEIC 由服务端解码 |
| 测试 | XCTest + XCUITest + `URLProtocol` 桩 | 零第三方；刷新竞态用桩覆盖 |
| 依赖策略 | **默认零第三方依赖**，见 §8 | 减少审计面、构建时间与供应链风险 |
| 最低系统 | **iOS 26.0** | 用户拍板（设备可控、长期维护），`@Observable` 等 API 无兼容分支，见 ADR-0002 |
| Xcode | 26.0 及以上（Swift 6 工具链） | iOS 26 SDK 与 Observation、Swift Charts 均可用 |

> 分发方式：**TestFlight 内部测试**（最多 100 名内部测试员，无需 Beta App Review；构建 90 天过期），见 §6.6。

---

## 4. 模块划分

依赖方向单向：`App → Features → Core`。Core 内部：`Session` 依赖 `Networking`，`Storage` 依赖 `Crypto`，`App` 负责把 `Audio`/`Storage`/`Networking` 组装进 `Features`；**`DesignSystem` 不依赖 Networking/Audio/Storage**（组件只接收已格式化的数据）。

| 模块 | 职责 | 不做什么 |
| --- | --- | --- |
| `App/` | `@main`、依赖容器、根导航、角色分流、主题注入 | 不含业务逻辑 |
| `Features/Auth` | 登录、会话恢复、401 处理、麦克风权限引导 | 不直接拼 URL |
| `Features/Practice` | 单句跟读：选句 → 录音 → 同步评测 → 结果展示 | 不做异步队列（属于 Flow） |
| `Features/Flow` | 连读模式：批量句子、边录边评、轮询、汇总 | 不重复实现录音/上传 |
| `Features/Chat` | 场景选择、会话建立、逐轮语音对话、打断与重播 | 不做文字输入（产品约束） |
| `Features/Story` | 拍照/选图 → OCR 校对 → 改写 → 插画 → 复述评测 → 作品集 | 不做语音对话 |
| `Features/BlindTest` | 盲听选择 + 盲跟读，揭晓前隐藏文本 | 不做评分算法 |
| `Features/Report` | 发音诊断、错音本、成长数据、趋势图 | 不做练习入口逻辑 |
| `Features/Parent` | 家长汇总、成员管理、重置密码、建议箱 | 孩子角色不可达 |
| `Features/Settings` | 账户、服务器地址、音频偏好、缓存、退出、改密、提建议 | 不存放全局状态 |
| `Core/Networking` | `APIClient`、端点定义、Multipart、解码、错误映射、重试、Bearer 注入 | 不含业务规则 |
| `Core/Audio` | 录音、播放、会话配置、路由/中断、电平表、互斥协调 | 不知道 API 存在 |
| `Core/Session` | 当前用户、角色能力、单飞刷新协调、Keychain | 不含页面状态 |
| `Core/DesignSystem` | 设计令牌、按钮/卡片/图表/空态等组件、儿童模式修饰器 | 不发请求 |
| `Core/Crypto` | SHA-256 缓存键、请求幂等键、文件完整性校验 | 不做端到端加密（后端无此能力） |
| `Core/Storage` | 语料仓库、TTS/图片/录音缓存、LRU 淘汰、账户隔离清理 | 不做网络请求 |

每个 Feature 目录固定四件套：`XxxView.swift` / `XxxStore.swift`（`@MainActor @Observable`）/ `XxxModels.swift`（页面态 DTO，非网络 DTO）/ `Components/`。**网络 DTO 统一放 `Core/Networking/DTO`**，避免各 Feature 重复定义 `Sentence`。

---

## 5. 目录结构

> **M0 实际源码根是 `ios/EnglishCoach/`**（下表中的 `App/`、`Core/`、`Features/`、`Resources/` 均在其下）。
> `ios/` 顶层的 `App/`、`Core/`、`Features/`、`Resources/`、`Config/` 是设计阶段留下的空目录占位（只有 `.gitkeep`），
> 不参与 XcodeGen 构建；保留是为了不破坏早期文档引用。

```
ios/
├── project.yml                       # XcodeGen 工程描述（M0）
├── EnglishCoach/
│   ├── App/
│   │   ├── EnglishCoachApp.swift
│   │   └── AppEnvironment.swift      # 依赖装配 + 全局会话状态（M0 的 AppDependencies/SessionStore 合并）
│   ├── Core/                         # Networking / Session / Audio / Crypto / DesignSystem
│   ├── Features/                     # Auth / Practice（M0）；其余目录仍为空
│   └── Resources/                    # Info.plist / PrivacyInfo.xcprivacy
├── docs/
└── README.md
```

下面是设计阶段规划的完整目录（M1+ 按此扩展，`AppRoot`/`RootTabView`/`Config/*.xcconfig` 尚未实现）：

```
ios/
├── App/
│   ├── EnglishCoachApp.swift
│   ├── AppRoot.swift                 # 启动 → 会话恢复 → 登录/主界面
│   ├── RootTabView.swift             # 角色化 Tab
│   ├── AppDependencies.swift         # 依赖容器（构造注入，便于测试）
│   └── Navigation/
│       └── AppRoute.swift            # 路由枚举 + 深链预留
├── Config/
│   ├── Debug.xcconfig                # API_BASE_URL 等
│   ├── Release.xcconfig
│   └── Info.plist                    # 权限文案 / ATS / 后台模式
├── Features/
│   ├── Auth/                         # 登录、会话恢复、权限引导
│   ├── Practice/
│   ├── Flow/
│   ├── Chat/
│   ├── Story/
│   ├── BlindTest/
│   ├── Report/
│   ├── Parent/
│   └── Settings/
├── Core/
│   ├── Networking/
│   │   ├── APIClient.swift
│   │   ├── Endpoint.swift
│   │   ├── MultipartBody.swift
│   │   ├── APIError.swift
│   │   ├── ErrorMapper.swift
│   │   ├── RetryPolicy.swift
│   │   ├── AuthToken.swift            # Keychain token 存取 + 单飞刷新
│   │   └── DTO/
│   ├── Audio/
│   │   ├── AudioSessionController.swift
│   │   ├── VoiceRecorder.swift
│   │   ├── AudioPlayer.swift
│   │   ├── MeterStream.swift
│   │   └── AudioCoordinator.swift
│   ├── Session/
│   │   ├── SessionStore.swift
│   │   ├── UserProfile.swift
│   │   ├── RoleCapabilities.swift
│   │   └── KeychainStore.swift
│   ├── DesignSystem/
│   │   ├── Theme.swift / Tokens.swift / Typography.swift
│   │   ├── Components/
│   │   └── Modifiers/                 # CardStyle / ChildModeStyle / Shimmer
│   ├── Crypto/
│   │   └── Hashing.swift
│   └── Storage/
│       ├── DiskCache.swift
│       ├── CorpusRepository.swift
│       ├── AudioCache.swift
│       └── ImageCache.swift
├── Tests/
│   ├── UnitTests/                    # 错误映射、Multipart、重试、缓存键、轮询状态机
│   └── UITests/                      # 登录→跟读→结果 主链路
├── Resources/
│   ├── Assets.xcassets               # 颜色/图标/吉祥物
│   └── Localizable.xcstrings
└── docs/
    ├── architecture.md
    ├── audio.md
    ├── screens.md
    ├── design-system.md
    ├── roadmap.md
    ├── open-questions.md
    └── adr/
        ├── 0001-cookie-session-vs-bearer-token.md      # Superseded（历史）
        ├── 0002-min-ios-version-and-observation.md
        └── 0003-bearer-token.md
```

> 骨架目录已创建（含 `.gitkeep`），空目录用于锁定结构；实现时按上表落文件即可。

---

## 6. 构建与运行

### 6.1 环境

| 项 | 要求 |
| --- | --- |
| macOS | 支持 Xcode 26 的版本（按本机 Xcode 要求为准） |
| Xcode | 26.0+；`SWIFT_VERSION = 6.0`，`STRICT_CONCURRENCY = complete` |
| 最低部署目标 | iOS 26.0（见 ADR-0002） |
| 设备 | 真机（iPhone）为验收基准，且必须已升级到 iOS 26；模拟器可开发，但**麦克风/路由/中断行为必须在真机验证** |
| 网络 | 与 NAS 同一局域网，能解析 `english.dreamsearch.top` |
| 签名 | 付费 Apple Developer Program 账号 + App Store Connect 记录（TestFlight 前提，见 §6.6） |

### 6.2 首次运行

1. 生成并打开工程：`cd ios && xcodegen generate && open EnglishCoach.xcodeproj`（见 §0.2）。
2. Signing：`Team = 付费开发者 Team`，Bundle ID 建议 `top.dreamsearch.englishcoach`（**【待确认】**；TestFlight 要求 App Store Connect 内唯一，一经创建不要随意更换）。
3. base URL **不再走 xcconfig**：M0 在登录页填写，存 `UserDefaults`（`app.baseURL`）；默认空、必填。设计阶段的 `Config/Debug.xcconfig` + `API_BASE_URL` 方案未实现。
4. 真机运行前，手机与 NAS 必须在同一网络；若路由器做了 AP 隔离会连不上。
5. M0 没有“设置 → 服务器体检”页；登录页的“测试连接”会调 `GET /health`（只判断 2xx，不解析 `db`/`voice.reachable` 明细）。

### 6.3 base URL 可配置

- 默认值：**空**（必填）。登录页填写后存 `UserDefaults`（`app.baseURL`）；只填主机名会自动补 `/api`。
- 设计上允许 `http://192.168.x.x:3000/api` 形式用于排障，但注意：**M0 的 Info.plist 没有 ATS 例外**，系统会直接拒绝 http 连接；要排障需自行在 Debug 加临时例外，且 **token 在 http 下是明文传输**，Release 不得打开；
  - 直连局域网 IP 会触发 iOS **本地网络隐私弹窗**，需要 `NSLocalNetworkUsageDescription`（Info.plist 已提供）。
- token 与服务器绑定：切换 base URL 后**清 Keychain 里的 token 并重新登录**（M0 在登录时清；旧服务器的 token 不能用于新地址）。
- 当前后端默认 `PROVIDER_MODE=hybrid`（音频→Azure、文本→DeepSeek、图片→DeepSeek/智谱），所以**音频会离开家庭网络**；登录页已如实提示，不能宣称“录音不出户”（见 §7 与 `docs/audio.md` §2.1）。

### 6.4 联调前的接口自检（在能访问 NAS 的机器上执行，非本仓库自动执行）

```bash
BASE=https://english.dreamsearch.top/api
curl -i  $BASE/health

# 1) 换 token（web 已实现；本仓库未运行时验证，先按此自检）
curl -s -X POST $BASE/auth/token \
     -H 'Content-Type: application/json' \
     -d '{"email":"...","password":"..."}' > /tmp/token.json
# → {access_token, refresh_token, token_type:"Bearer", expires_in:3600, user}

ACCESS=$(python3 -c 'import json;print(json.load(open("/tmp/token.json"))["access_token"])')
REFRESH=$(python3 -c 'import json;print(json.load(open("/tmp/token.json"))["refresh_token"])')

curl -i -H "Authorization: Bearer $ACCESS" $BASE/auth/me
curl -i -H "Authorization: Bearer $ACCESS" "$BASE/sentences?level=A1"

# 2) 刷新（一次性轮换：旧 refresh 立即失效）
curl -i -X POST $BASE/auth/refresh -H 'Content-Type: application/json' \
     -d "{\"refresh_token\":\"$REFRESH\"}"

# 3) 吊销（204）
curl -i -X POST $BASE/auth/revoke -H 'Content-Type: application/json' \
     -d "{\"refresh_token\":\"$REFRESH\"}"
```

**重点确认三件事**（请在 NAS 环境逐条实测）：① `token_type` 是否为 `Bearer`、`expires_in` 是否为 3600；② **refresh 是否真的一次性轮换**（同一个 refresh 第二次使用必须 401）；③ `/revoke` 之后旧 refresh 是否立即失效。任何一条不成立都需要回到 [ADR-0003](docs/adr/0003-bearer-token.md) 修正客户端实现假设。见开放问题 B17。

> 自检产生的 token 不要贴进聊天、issue 或提交记录；`/tmp/token.json` 用完即删。

### 6.5 常见问题

| 现象 | 可能原因 | 处理 |
| --- | --- | --- |
| 登录 200 但 `/auth/me` 立刻 401 | Authorization 头没带上 / token 已被 `/revoke` / 后端双模式中间件未就绪 | 抓包确认请求头；确认后端 token 端点已部署；见 ADR-0003 |
| 重启 App 后掉登录 | Keychain 写入失败（错误码被吞）/ refresh 已被轮换或吊销 | 查 `OSLog` 的 Keychain 错误码；确认单飞刷新没有并发重复 refresh；见 ADR-0003 §2 |
| 使用中突然回登录页 | refresh 返回 401（过期/被吊销/已被别人轮换） | 预期行为；若同时多请求 401 导致，检查是否漏了单飞刷新 |
| 真机连不上服务器 | 不同网段 / AP 隔离 / DNS 不解析私有域名 | 先用 Safari 打开同一 URL 验证 |
| 录音上传 415 `unsupported_audio` | 文件名/`Content-Type` 与内容不符（如 `.m4a` 配 `audio/wav`） | Multipart 里 `filename=xxx.m4a`、`Content-Type: audio/mp4` 保持一致 |
| 录音上传 413 `payload_too_large` | 单段超过 12MB 或误把多段拼接 | 客户端 60s 硬上限 + 提交前体积预检（16kHz/65kbps 下 60s 仅约 0.49MB） |
| TestFlight 提示“构建已过期” | Beta 构建有效期 **90 天** | 重新归档上传并分发给同一批内部测试员，见 §6.6 |

### 6.6 分发：TestFlight（内部测试）

**分发方式已定：只走 TestFlight 内部测试**，不上 App Store、不做免费账号自签。原因：家庭自用、测试员固定；免费自签 7 天过期对家长是持续负担；App Store 上架需要解释“服务器仅家庭内网可达”，收益为零。

| 项 | 结论 |
| --- | --- |
| 账号 | 付费 **Apple Developer Program**（TestFlight 前提） |
| 测试范围 | **内部测试员最多 100 名**（App Store Connect 用户），**无需 Beta App Review**，构建处理完成后即可分发 |
| 外部测试 | 本期**不使用**（最多 10,000 人，但需要 Beta App Review + 测试信息） |
| Beta 有效期 | **构建上传后 90 天过期**；到期后测试员无法再安装/打开，必须重新上传一个新构建并分发 |
| Bundle ID | `top.dreamsearch.englishcoach`（**【待确认】**，App Store Connect 内唯一；创建后不要随意改，否则测试员要重装） |
| 最低系统 | iOS 26（测试员设备必须已升级） |
| 审核 | 内部测试**不需要**审核；不要把“无需审核”误解为“无需签名/隐私清单” |

#### 构建与上传

1. **签名**：Xcode 自动签名（`Automatically manage signing`）+ 付费 Team；TestFlight 使用 **App Store 分发证书与描述文件**（不是 Development）。证书私钥只保存在本机/受控钥匙串，不提交仓库。
2. **归档**：`Product → Archive`，或命令行
   ```bash
   xcodebuild -project ios/EnglishCoach.xcodeproj -scheme EnglishCoach \
     -configuration Release -destination 'generic/platform=iOS' \
     -archivePath build/EnglishCoach.xcarchive archive
   ```
3. **上传**（三选一，推荐前两种）：
   - **Xcode Cloud**：接 App Store Connect，推送即构建，产物直接进 TestFlight（适合长期运维，构建环境稳定）；
   - **`xcodebuild -exportArchive` + `ExportOptions.plist`**（`method = app-store-connect`、`destination = upload`），由 Xcode 直接上传；
   - **Transporter.app** 手动上传 `.ipa`（图形界面，最省心的一次性方案）。
   - 历史命令 `xcrun altool --upload-app` 已被 Apple 逐步弃用，仅作排障参考；**`notarytool` 是 macOS 公证工具，与 iOS/TestFlight 无关，不要用在 iOS 构建上**。
4. **App Store Connect**：创建 App 记录 → 填 Bundle ID → 上传构建 → 等待处理（几分钟到半小时）→ 添加内部测试员/测试组 → 分发。
5. **每次上传前**：递增 `CFBundleShortVersionString` / `CFBundleVersion`；确认 `ITSAppUsesNonExemptEncryption = false`（无自定义加密）；确认 `PrivacyInfo.xcprivacy` 已打进 App bundle。

#### 隐私清单 `PrivacyInfo.xcprivacy`

TestFlight 构建也应提供隐私清单：Apple 要求上传到 App Store Connect 的构建声明 Required Reason API 与收集的数据；缺失可能收到警告，并影响将来任何上架动作。最小内容：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key><false/>
  <key>NSPrivacyTrackingDomains</key><array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array>
    <!-- 音频会上传服务器并转发 Azure 评测；是否按“收集”声明取决于服务端留存策略【待确认】 -->
    <dict>
      <key>NSPrivacyCollectedDataType</key><string>NSPrivacyCollectedDataTypeAudioData</string>
      <key>NSPrivacyCollectedDataTypeLinked</key><true/>
      <key>NSPrivacyCollectedDataTypeTracking</key><false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
    </dict>
    <!-- 账号邮箱/显示名，用于登录与家长面板 -->
    <dict>
      <key>NSPrivacyCollectedDataType</key><string>NSPrivacyCollectedDataTypeEmailAddress</string>
      <key>NSPrivacyCollectedDataTypeLinked</key><true/>
      <key>NSPrivacyCollectedDataTypeTracking</key><false/>
      <key>NSPrivacyCollectedDataTypePurposes</key>
      <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
    </dict>
  </array>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <!-- UserDefaults（baseURL、偏好） -->
    <dict>
      <key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string></array>
    </dict>
    <!-- 缓存淘汰读文件时间戳；磁盘空间检查 -->
    <dict>
      <key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>C617.1</string></array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryDiskSpace</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>E174.1</string></array>
    </dict>
  </array>
</dict>
</plist>
```

注意：

- **Required Reason API 的 reason code 必须以 Apple 官方列表核对**（上表是当前设计假设，未在 Xcode 校验工具中验证）；只声明实际用到的类别，不要照抄模板。
- `NSPrivacyCollectedDataTypes` 是否包含音频，取决于“音频是否被服务端/Azure 留存”。当前 hybrid 模式音频会发给 Azure，**按保守口径声明为收集**；若后端确认零留存且符合 Apple 的“不视为收集”条件，再调整并记录依据。
- 隐私清单只解决“声明”，不替代 App 内的隐私说明文案。

#### 90 天运维节奏（必须写进值班/运维说明）

- **到期前 2 周**检查当前 Beta 构建的上传日期；到期前重新归档上传（即使代码没变），版本号递增，分发给同一内部测试组。
- 测试员侧表现：构建过期后 App 无法启动/安装，TestFlight 会提示更新；家长不会自己处理，需要维护者主动重传。
- 每次重传记录：构建号、上传日期、下次到期日、变更摘要（放 `docs/roadmap.md` 的发布记录或仓库 issue）。
- 更换证书/Team、修改 Bundle ID 都会导致测试员需要重装，非必要不做。

---

## 7. 权限与 Info.plist 清单

| Key | 是否必需 | 文案要点（中文，孩子/家长都读得懂） |
| --- | --- | --- |
| `NSMicrophoneUsageDescription` | **必需** | “需要使用麦克风录制你的朗读。录音会上传到家里的学习服务器，并转发给云端语音服务用于识别和发音评分。” |
| `NSCameraUsageDescription` | 故事模式需要拍照时必需 | “拍下书页或绘本，用来生成英文小故事。” |
| `NSPhotoLibraryUsageDescription` | 用 `PhotosPicker` 时**不需要**；仅“保存插画到相册”时需要 `NSPhotoLibraryAddUsageDescription` | “把生成的故事插画保存到相册。” |
| `NSLocalNetworkUsageDescription` | 仅当允许填写局域网 IP 时 | “用于连接家庭内网的学习服务器。” |
| `UIBackgroundModes = audio` | TTS/故事音频后台播放需要 | 只用于播放，**不用于后台录音**（审核与隐私风险） |
| `ITSAppUsesNonExemptEncryption` | TestFlight 上传时声明 | 无自定义加密，`false`（仅系统 HTTPS/Keychain） |
| `PrivacyInfo.xcprivacy` | **必需** | 隐私清单文件（不是 Info.plist 键），内容与 reason code 见 §6.6 |

**麦克风文案必须如实**：当前后端 `PROVIDER_MODE=hybrid`，音频会经家里服务器转发给 **Azure** 做 ASR/发音评测/TTS，**会离开家庭网络**。因此权限说明与隐私页**不得**写“录音只留在家里/不出户”。若要求完全本地，需要 `PROVIDER_MODE=local` + 本地模型（当前**未部署**），届时要同步改写文案与本表。

ATS：默认不开放例外。如果 NAS 使用自签证书或内网 CA，iOS 会直接拒绝连接；即使只走 TestFlight，也必须让测试设备信任该证书（在 NAS 侧换受信任证书，或在设备上安装并信任描述文件）。`NSExceptionDomains` 不是推荐路径，仅排障期临时使用并二次确认（见开放问题 C8）。

---

## 8. 依赖策略

**默认零第三方依赖。** 理由：单客户端维护、功能可由系统框架覆盖（网络/音频/图表/图片选择/存储）、避免“为一个按钮引入一套 UI 库”。

| 需求 | 系统方案 | 是否允许第三方 |
| --- | --- | --- |
| HTTP | `URLSession` | 否 |
| 状态 | `Observation` | 否 |
| 图表 | Swift Charts | 否 |
| 图片选择/缓存 | PhotosUI + 自写 `ImageCache` | 否（Kingfisher 可省） |
| 音频 | AVFoundation | 否 |
| 日志 | `OSLog` | 否 |
| 快照测试 | — | 允许 dev-only：`pointfreeco/swift-snapshot-testing`（仅 Test target） |
| 崩溃收集 | — | TestFlight 内置崩溃日志足够；引入 Sentry/Firebase 需 ADR |

引入任何运行时依赖必须：① 提交 ADR；② 说明替代的系统方案为何不足；③ 通过 SwiftPM 锁定版本（不用 `branch`/`from` 浮动版本）。

---

## 9. 工程规范

- **命名**：类型 `UpperCamelCase`，文件与类型同名；一个文件一个主类型；协议以能力命名（`AudioPlaying`、`SentenceProviding`）。
- **分层硬规则**：`Features` 不出现 `URLSession`/`URLRequest`；`Core/Audio` 不 import 任何 `Features`；`DesignSystem` 不 import `Networking`。
- **错误文案集中**：所有用户可见错误来自 `ErrorMapper`（`docs/architecture.md` §5 的表），页面禁止自造网络错误文案。
- **儿童模式**：通过 `RoleCapabilities`（`canSeeIPA`、`showsNumericScore`、`minTapTarget` 等）注入 Environment，**禁止**在页面里写 `if user.role == .child` 散点判断。
- **本地化**：基准 `zh-Hans`，`Localizable.xcstrings`（String Catalog）；英文 UI 不在本期范围（见开放问题 Q5）。
- **日志**：`OSLog(subsystem: "top.dreamsearch.englishcoach")`；**禁止**打印 access/refresh token、Cookie、密码、邮箱、音频内容；请求日志只留 method/path/status/duration。
- **提交**：一个 Feature 一个 PR；PR 必须附 `docs/screens.md` 对应小节的勾选清单。

---

## 10. 文档索引

| 文档 | 内容 |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | 分层、状态管理、网络层、错误映射、Actor 隔离、缓存与离线、测试策略 |
| [docs/audio.md](docs/audio.md) | 权限、`AVAudioSession` 配置、录音参数、上传、播放、互斥、失败处理 |
| [docs/screens.md](docs/screens.md) | 每个页面的结构/交互/API/状态；孩子与成人差异 |
| [docs/design-system.md](docs/design-system.md) | 颜色/字体/间距/圆角/按钮层级/组件清单/无障碍 |
| [docs/roadmap.md](docs/roadmap.md) | M0–M4 范围与验收标准 |
| [docs/open-questions.md](docs/open-questions.md) | 待产品/后端决策的问题清单 |
| [docs/adr/0001](docs/adr/0001-cookie-session-vs-bearer-token.md) | 会话认证：Cookie 方案（**Superseded**，历史记录） |
| [docs/adr/0002](docs/adr/0002-min-ios-version-and-observation.md) | 最低 iOS 26 与状态管理选型 |
| [docs/adr/0003](docs/adr/0003-bearer-token.md) | Bearer Token、Keychain、单飞刷新、吊销 |

---

## 11. 本次交付

- 本 README + 6 篇设计文档 + 3 篇 ADR（UTF-8 Markdown）。
- **M0 垂直切片源码**：`project.yml`、`EnglishCoach/App`、`EnglishCoach/Core`、`EnglishCoach/Features/{Auth,Practice}`、`EnglishCoach/Resources`（详见 §0）。
- `App/`、`Features/*`、`Core/*`、`Tests/*`、`Config/`、`Resources/` 顶层目录骨架（`.gitkeep` 占位，不参与构建）。
- **未包含**：`.xcodeproj`（用 XcodeGen 生成）、App 图标/图片资源、测试目标、TestFlight 配置。
- **未验证**：代码未编译、未真机运行；清单见 §0.4，不在正文中伪装成结论。

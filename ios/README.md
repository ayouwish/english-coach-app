# English Coach iOS 客户端 · 设计文档与工程骨架

> 状态：**设计阶段（M0 之前）**。本目录当前只包含设计文档与空目录骨架，**没有可编译的 App 代码**。
> 后端（Next.js `web` + FastAPI `voice`）已在家庭 NAS 上跑通，iOS 端所有能力都通过 `web` 的 `/api/*` 调用。

---

## 1. 文档目的与范围

| 项 | 说明 |
| --- | --- |
| 目标 | 为 `English Coach` 提供一份可直接排期、直接开工的 iOS 客户端设计文档 |
| 范围内 | 分层架构、网络与认证、音频方案、页面结构、设计令牌、里程碑、待决问题 |
| 范围外 | Swift 源码、后端改动、测试数据构造、App Store 素材 |
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
| 认证是 **Cookie 会话**（`httpOnly`, `sameSite=lax`, 可选 `Secure`） | 用 `URLSession` 的 `HTTPCookieStorage` 即可零改动接入，见 ADR-0001 |
| 录音上传上限 **12MB**，PyAV 解码支持 webm/opus、wav、mp3、m4a/aac | iOS 用 AVAudioRecorder 出 **m4a/AAC**，16kHz 单声道 64kbps 足够，体积远低于上限 |
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
| 状态 | Observation（`@Observable`）+ `@MainActor` Store | iOS 17+ 可用，避免 `ObservableObject` + `@Published` 的样板代码 |
| 并发 | async/await + Swift 6 语言模式（严格并发检查） | 网络/轮询/录音状态天然异步 |
| 网络 | `URLSession` + `HTTPCookieStorage`（零第三方） | Cookie 会话零后端改动，见 ADR-0001 |
| 音频 | AVFoundation：`AVAudioSession` / `AVAudioRecorder` / `AVAudioPlayer` | 系统能力足够：录音、播放、路由切换、后台播放 |
| 图表 | Swift Charts（系统框架） | 语调曲线、掌握度趋势，零依赖 |
| 本地存储 | 文件（JSON/二进制）+ `UserDefaults` + Keychain | 数据量小（600 句语料、TTS 缓存），不引入数据库 |
| 图片选择 | `PhotosPicker`（PhotosUI）+ 相机 `UIImagePickerController` 包装 | 不申请相册读权限；HEIC 由服务端解码 |
| 测试 | XCTest + XCUITest + `URLProtocol` 桩 | 零第三方 |
| 依赖策略 | **默认零第三方依赖**，见 §8 | 减少审计面、构建时间与供应链风险 |
| 最低系统 | **iOS 17.0**（推荐）；若必须覆盖 iOS 16 见 ADR-0002 | `@Observable`、`ContentUnavailableView`、`onChange(of:)` 新签名等 |
| Xcode | 16.0 及以上（Swift 6 工具链） | `Observation`、Swift Charts 成熟；不含具体新版承诺 |

> 最低版本 17 与 16 的取舍是一个**需要产品拍板**的问题（影响 iPhone X 及更老设备的覆盖），见 `docs/adr/0002-min-ios-version-and-observation.md` 与开放问题 Q2。

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
| `Core/Networking` | `APIClient`、端点定义、Multipart、解码、错误映射、重试、Cookie | 不含业务规则 |
| `Core/Audio` | 录音、播放、会话配置、路由/中断、电平表、互斥协调 | 不知道 API 存在 |
| `Core/Session` | 当前用户、角色能力、Cookie 桥接、Keychain | 不含页面状态 |
| `Core/DesignSystem` | 设计令牌、按钮/卡片/图表/空态等组件、儿童模式修饰器 | 不发请求 |
| `Core/Crypto` | SHA-256 缓存键、请求幂等键、文件完整性校验 | 不做端到端加密（后端无此能力） |
| `Core/Storage` | 语料仓库、TTS/图片/录音缓存、LRU 淘汰、账户隔离清理 | 不做网络请求 |

每个 Feature 目录固定四件套：`XxxView.swift` / `XxxStore.swift`（`@MainActor @Observable`）/ `XxxModels.swift`（页面态 DTO，非网络 DTO）/ `Components/`。**网络 DTO 统一放 `Core/Networking/DTO`**，避免各 Feature 重复定义 `Sentence`。

---

## 5. 目录结构

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
│   │   ├── CookieSession.swift
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
        ├── 0001-cookie-session-vs-bearer-token.md
        └── 0002-min-ios-version-and-observation.md
```

> 骨架目录已创建（含 `.gitkeep`），空目录用于锁定结构；实现时按上表落文件即可。

---

## 6. 构建与运行

### 6.1 环境

| 项 | 要求 |
| --- | --- |
| macOS | 支持 Xcode 16 的版本（Sonoma 14.5+ 起，按本机 Xcode 要求为准） |
| Xcode | 16.0+；`SWIFT_VERSION = 6.0`，`STRICT_CONCURRENCY = complete` |
| 最低部署目标 | iOS 17.0（见 ADR-0002） |
| 设备 | 真机（iPhone）为验收基准；模拟器可开发，但**麦克风/路由/中断行为必须在真机验证** |
| 网络 | 与 NAS 同一局域网，能解析 `english.dreamsearch.top` |

### 6.2 首次运行

1. `open ios/EnglishCoach.xcodeproj`（工程文件尚未创建，M0 第一步生成）。
2. Signing：`Team = 个人开发者 Team`，Bundle ID 建议 `top.dreamsearch.englishcoach`（**【待确认】**，若走 TestFlight 需唯一）。
3. 确认 `Config/Debug.xcconfig` 中 `API_BASE_URL = https:/$()/english.dreamsearch.top/api`（xcconfig 里 `//` 会被当注释，必须用 `https:/$()/` 转义）。
4. 真机运行前，手机与 NAS 必须在同一网络；若路由器做了 AP 隔离会连不上。
5. 启动后先走「设置 → 服务器体检」（`GET /health`），确认 `db` 与 `voice.reachable` 正常。

### 6.3 base URL 可配置

- 默认值来自 `Info.plist`（由 xcconfig 注入），`Settings` 允许改写到 `UserDefaults`（`app.baseURL`）。
- 允许 `http://192.168.x.x:3000/api` 形式用于排障，但注意两点：
  - 服务端 Cookie 若带 `Secure`，**http 下不会被回传**，表现为“登录成功但立刻 401”——必须写进设置页的提示文案；
  - 直连局域网 IP 会触发 iOS **本地网络隐私弹窗**，需要 `NSLocalNetworkUsageDescription`。
- 切换 base URL 后 Cookie 按域隔离，**必然需要重新登录**。

### 6.4 联调前的接口自检（在能访问 NAS 的机器上执行，非本仓库自动执行）

```bash
BASE=https://english.dreamsearch.top/api
curl -i  $BASE/health
curl -i  -c /tmp/c.txt -X POST $BASE/auth/login \
     -H 'Content-Type: application/json' \
     -d '{"email":"...","password":"..."}'
grep -i 'set-cookie' /tmp/c.txt        # 关注 HttpOnly / Secure / SameSite / Max-Age
curl -i  -b /tmp/c.txt $BASE/auth/me
curl -i  -b /tmp/c.txt "$BASE/sentences?level=A1"
```

**重点确认 `Set-Cookie` 是否带 `Max-Age`/`Expires`**：不带就是“会话 Cookie”，iOS 重启 App 后大概率丢失（`URLSession` 只持久化持久 Cookie），这直接决定 ADR-0001 的结论是否成立。见开放问题 Q1。

### 6.5 常见问题

| 现象 | 可能原因 | 处理 |
| --- | --- | --- |
| 登录 200 但 `/auth/me` 立刻 401 | `Secure` Cookie + http base URL；或 App 重建了 `URLSessionConfiguration` 导致 cookieStorage 不同 | 统一用 https；全局单例 `URLSession`；见 ADR-0001 |
| 重启 App 后掉登录 | 服务端会话 Cookie 无 `Max-Age` | 【待后端新增】给会话 Cookie 加 `Max-Age`（推荐 30 天）；或客户端做 Cookie 备份（见 ADR-0001 备选） |
| 真机连不上服务器 | 不同网段 / AP 隔离 / DNS 不解析私有域名 | 先用 Safari 打开同一 URL 验证 |
| 录音上传 415 `unsupported_audio` | 文件名/`Content-Type` 与内容不符（如 `.m4a` 配 `audio/wav`） | Multipart 里 `filename=xxx.m4a`、`Content-Type: audio/mp4` 保持一致 |
| 录音上传 413 `payload_too_large` | 单段超过 12MB 或误把多段拼接 | 客户端 60s 硬上限 + 提交前体积预检 |

---

## 7. 权限与 Info.plist 清单

| Key | 是否必需 | 文案要点（中文，孩子/家长都读得懂） |
| --- | --- | --- |
| `NSMicrophoneUsageDescription` | **必需** | “需要使用麦克风录制你的朗读，音频只上传到家里的学习服务器用于评分。” |
| `NSCameraUsageDescription` | 故事模式需要拍照时必需 | “拍下书页或绘本，用来生成英文小故事。” |
| `NSPhotoLibraryUsageDescription` | 用 `PhotosPicker` 时**不需要**；仅“保存插画到相册”时需要 `NSPhotoLibraryAddUsageDescription` | “把生成的故事插画保存到相册。” |
| `NSLocalNetworkUsageDescription` | 仅当允许填写局域网 IP 时 | “用于连接家庭内网的学习服务器。” |
| `UIBackgroundModes = audio` | TTS/故事音频后台播放需要 | 只用于播放，**不用于后台录音**（审核与隐私风险） |
| `ITSAppUsesNonExemptEncryption` | 若上架需声明 | 无自定义加密，`false`（仅系统 HTTPS/Keychain） |

ATS：默认不开放例外。如果 NAS 使用自签证书，`NSExceptionDomains` 会显著增加上架阻力，**建议在 NAS 侧换成受信任证书或内网 CA 并在设备上安装描述文件**（见开放问题）。

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
| 崩溃收集 | — | 若上架再议（Sentry/Firebase 需 ADR） |

引入任何运行时依赖必须：① 提交 ADR；② 说明替代的系统方案为何不足；③ 通过 SwiftPM 锁定版本（不用 `branch`/`from` 浮动版本）。

---

## 9. 工程规范

- **命名**：类型 `UpperCamelCase`，文件与类型同名；一个文件一个主类型；协议以能力命名（`AudioPlaying`、`SentenceProviding`）。
- **分层硬规则**：`Features` 不出现 `URLSession`/`URLRequest`；`Core/Audio` 不 import 任何 `Features`；`DesignSystem` 不 import `Networking`。
- **错误文案集中**：所有用户可见错误来自 `ErrorMapper`（`docs/architecture.md` §5 的表），页面禁止自造网络错误文案。
- **儿童模式**：通过 `RoleCapabilities`（`canSeeIPA`、`showsNumericScore`、`minTapTarget` 等）注入 Environment，**禁止**在页面里写 `if user.role == .child` 散点判断。
- **本地化**：基准 `zh-Hans`，`Localizable.xcstrings`（String Catalog）；英文 UI 不在本期范围（见开放问题 Q5）。
- **日志**：`OSLog(subsystem: "top.dreamsearch.englishcoach")`；**禁止**打印 Cookie、邮箱、音频内容；请求日志只留 method/path/status/duration。
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
| [docs/adr/0001](docs/adr/0001-cookie-session-vs-bearer-token.md) | Cookie 会话 vs Bearer Token |
| [docs/adr/0002](docs/adr/0002-min-ios-version-and-observation.md) | 最低 iOS 版本与状态管理选型 |

---

## 11. 本次交付

- 本 README + 6 篇设计文档 + 2 篇 ADR（UTF-8 Markdown）。
- `App/`、`Features/*`、`Core/*`、`Tests/*`、`Config/`、`Resources/` 目录骨架（`.gitkeep` 占位）。
- **未包含**：Xcode 工程文件、任何 Swift 源码、资源图片。M0 第一件事是建工程并把 `AppShell` 跑起来。
- 未验证项已集中记录，不在正文中伪装成结论。

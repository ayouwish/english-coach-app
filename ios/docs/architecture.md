# 架构设计 · English Coach iOS

> 对应代码骨架：`App/`、`Features/`、`Core/`。本文只描述结构与契约，不包含完整的生产代码。
> 标注沿用 README：**【已实现·后端现有】**/【待后端新增】/【客户端自行实现】/【待确认】。

---

## 1. 分层与依赖规则

```
┌───────────────────────────────────────────────────────────────┐
│ App 层                                                         │
│  EnglishCoachApp · AppRoot · RootTabView · AppDependencies      │
│  职责：装配依赖、主题、语言、根 NavigationStack、角色分流         │
└───────────────▲───────────────────────────────────────────────┘
                │ 只能向下依赖
┌───────────────┴───────────────────────────────────────────────┐
│ Features 层（每个页面一个 Store + 若干 View）                    │
│  Auth · Practice · Flow · Chat · Story · BlindTest · Report     │
│  · Parent · Settings                                           │
│  职责：页面状态机、用户意图、把 Core 能力组合成一次业务动作       │
└───────────────▲───────────────────────────────────────────────┘
                │
┌───────────────┴───────────────────────────────────────────────┐
│ Core 层                                                        │
│  Networking │ Audio │ Session │ Storage │ DesignSystem │ Crypto  │
│  职责：可复用能力；不知道任何具体页面                            │
└───────────────────────────────────────────────────────────────┘
```

**可自动检查的硬规则**（用 `swiftlint` 之外的简单脚本或 CI grep 即可）：

| 规则 | 检查方式 |
| --- | --- |
| `Features/**` 不得出现 `URLSession`、`URLRequest` | `grep -r "URLSession\|URLRequest" Features/` 必须为空 |
| `Core/Audio/**` 不得 import `Features` | `grep -r "import.*Features" Core/Audio/` 为空 |
| `Core/DesignSystem/**` 不得 import `Networking` | 同上 |
| 页面不得硬编码错误文案 | 只允许通过 `ErrorMapper.message(for:)` |

### 1.1 为什么不引入 Coordinator / VIPER / TCA

- 页面数量 < 15，SwiftUI 原生导航（`NavigationStack` + `navigationDestination`）足够；
- `@Observable` Store 已经承担了状态机与副作用编排；
- TCA 会带来“每个 API 调用三重样板”，单人维护成本不划算。

**结论**：MV +（页面级 Store）+ 依赖注入，不上架构框架。

---

## 2. App Shell 与导航

### 2.1 启动流程

```
启动
 └─ AppRoot
     ├─ 读取 Keychain：access_token / refresh_token / 上次登录标识（仅用于预填）
     ├─ 无 token → LoginView
     ├─ 有 token：若 access 已过期 → 单飞 refresh；成功则继续，失败（401/403）→ 清 token → LoginView
     ├─ 并发：GET /auth/me （带 Bearer，超时 8s）
     │    ├─ 200 → SessionStore.user = profile → 角色化 RootTabView
     │    ├─ 401 → refresh 一次 → 重试 /me；仍 401 → 清 token → LoginView
     │    └─ 网络错误 → 进入“离线外壳”：显示登录页 + 顶部横幅“连不上服务器”，**保留 token**，恢复网络后可自动重试（不要求重输密码）
     └─ 冷启动预算：≤1.5s 出首屏（不含网络），见 §9
```

**不要**在 `/auth/me` 返回前就渲染主界面，否则儿童模式/家长 Tab 会闪一下再切换。**网络错误不要清 token**，否则 NAS 短暂不可达会把用户登出；只有服务端明确拒绝 refresh 才清（见 ADR-0003 §5）。

### 2.2 角色化 Tab

| 角色 `role` | Tab 顺序 | 说明 |
| --- | --- | --- |
| `child` | 练习 · 对话 · 故事 · 我的 | 无“家长”Tab；“我的”内是成长（诊断/错音本）与设置 |
| `parent` | 家长 · 练习 · 对话 · 故事 · 我的 | 家长也能练习；首位是家长面板 |

Tab 数量 ≤5，不搞 `More` 折叠。角色能力集中在 `RoleCapabilities`：

```swift
struct RoleCapabilities: Sendable {
    let showsIPA: Bool            // child: false
    let showsNumericScore: Bool   // child: false
    let showsLowScoreWarning: Bool// child: false
    let canOpenParentPanel: Bool
    let canEditServerURL: Bool
    let minTapTarget: CGFloat     // child: 56, adult: 44
    let bodyFontScale: Double     // child: 1.15
}
```

通过 `.environment(\.capabilities, ...)` 下发，页面与组件都读它，**禁止**在 View 里写 `role == .child`。

### 2.3 路由

`AppRoute: Hashable` 枚举承载所有二级页面（`practiceDetail(sentenceID:)`、`chat(sessionID:)`、`storyDetail(materialID:)`…），配合 `NavigationStack(path:)`。深链本期不做，但路由枚举留 `init?(url:)` 扩展点。

---

## 3. 状态管理

### 3.1 三种状态，三种归属

| 归属 | 生命周期 | 载体 | 示例 |
| --- | --- | --- | --- |
| 页面状态 | 页面存在期间 | `@State private var store: PracticeStore`（`@Observable`） | 当前句子、录音状态、评测结果 |
| 全局会话 | App 生命周期 | `@State` in `AppRoot` → `.environment(SessionStore)` | 用户、角色能力、登录/登出 |
| 共享缓存/仓库 | 跨页面 | `actor CorpusRepository` 单例注入 | 语料、诊断结果、TTS 缓存 |

### 3.2 页面状态通用形状

```swift
enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading(previous: Value?)   // 保留旧数据，避免刷新时闪空
    case loaded(Value, isStale: Bool)
    case failed(APIError)
}
```

- 列表页：`LoadState<[Sentence]>`，下拉刷新时用 `.loading(previous:)` 保留内容；
- 提交类动作（评测、OCR、改写）不放进 `LoadState`，单独 `submission: SubmissionState`（`idle/uploading(progress)/scoring/result/error`），因为它们和页面数据是两条生命周期。

### 3.3 Store 约定

```swift
@MainActor @Observable
final class PracticeStore {
    private(set) var state: LoadState<[Sentence]> = .idle
    private(set) var submission: SubmissionState = .idle
    private let api: SentenceAPI
    private let audio: AudioCoordinating
    private let cache: CorpusCaching
    private var scoreTask: Task<Void, Never>?

    init(api: SentenceAPI, audio: AudioCoordinating, cache: CorpusCaching) { ... }

    func load(level: CEFRLevel) async { ... }
    func submit(recording: Recording) async { ... }   // 内部会取消旧 scoreTask
}
```

- Store **不持有 View**，不弹 Alert；错误通过状态暴露，View 决定用什么形式呈现（页面内 banner 优先于 Alert）。
- 所有 `Task` 在 `deinit`/`onDisappear` 时取消；轮询任务单独保存句柄。
- View 只做三件事：读状态、发 intent、渲染；`body` 内不发起网络请求（用 `.task`）。

### 3.4 儿童模式在状态层的体现

“不显示低分”不是隐藏 UI，而是**不把低分写入可在 UI 表达的模型**：

```swift
struct ScorePresentation {          // 由 ScorePresenter 生成
    let tier: .celebrate/.encourage/.retry   // 孩子只有这三档
    let numeric: Int?                        // 孩子恒为 nil
    let stars: Int?                          // 孩子 1–3 星
    let phonemeRows: [PhonemeRow]            // 孩子 rows 不含 IPA 字符串
}
```

`ScorePresenter` 是纯函数，单测覆盖：成人 62 分 → `numeric=62, tier=.encourage`；孩子 62 分 → `numeric=nil, stars=2, tier=.encourage`。

---

## 4. 网络层

### 4.1 端点抽象

```swift
enum AuthPolicy: Sendable {
    case none        // /health、/auth/token、/auth/refresh、/auth/revoke
    case bearer      // 业务接口：注入 access token；401 走单飞刷新后重放一次
}

protocol Endpoint: Sendable {
    var method: HTTPMethod { get }
    var path: String { get }                       // "/sentences"
    var query: [URLQueryItem] { get }
    var headers: [String: String] { get }
    var body: Body { get }                         // .none / .json(Encodable) / .multipart(MultipartPayload)
    var timeout: TimeInterval { get }
    var authPolicy: AuthPolicy { get }
    var cachePolicy: URLRequest.CachePolicy { get }
}
```

```swift
protocol APITransport: Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint, as: T.Type) async throws -> T
    func send(_ endpoint: Endpoint) async throws -> Data          // 音频字节 / 空响应
    func upload<T: Decodable & Sendable>(_ endpoint: Endpoint, progress: @Sendable (Double) -> Void, as: T.Type) async throws -> T
}
```

- `APIClient`（`final class`, `Sendable`，持有唯一的 `URLSession`）实现 `APITransport`；
- 端点按领域拆成 8 个小组件（`AuthAPI`、`SentenceAPI`、`AttemptAPI`、`ChatAPI`、`StoryAPI`、`MaterialAPI`、`ParentAPI`、`VoiceAPI`），都只是 `APIClient` 的薄包装，便于 Store 的单测注入 fake。

### 4.2 URLSession 配置（**必须只有一个实例**）

```swift
let cfg = URLSessionConfiguration.default
cfg.httpCookieStorage = nil                 // 不读写 Cookie：移动端凭据只有 Bearer
cfg.httpShouldSetCookies = false
cfg.timeoutIntervalForRequest = 15
cfg.timeoutIntervalForResource = 90
cfg.waitsForConnectivity = false            // 需要快速失败以展示离线状态
cfg.requestCachePolicy = .reloadIgnoringLocalCacheData  // 业务缓存自己做，避免与 URLCache 打架
cfg.urlCache = nil
```

> 上面是**会话级默认值**；`Endpoint.timeout` 通过 `URLRequest.timeoutInterval` 逐请求覆盖（见 §4.5），两者不冲突。
>
> `waitsForConnectivity = true` 会让请求静默挂起直到超时，对“录音后立即要评分”的场景是灾难；必须显式设 `false`。
>
> 只有一个 `URLSession` 的理由不再是 Cookie，而是连接池复用与配置一致性；**token 由请求构造阶段注入**，不依赖 session 的可变状态。

### 4.3 认证（Bearer Token）【待后端新增·P0，阻塞 M0】

| 端点 | 用途 | 客户端动作 |
| --- | --- | --- |
| `POST /auth/token` | 邮箱+密码换 token | 存 Keychain（两个 token + `expiresAt`），用响应里的 `user` 初始化页面；冷启动用 `/auth/me` 校验 |
| `POST /auth/refresh` | 用 refresh 换新一对（**一次性轮换**） | 只能由单飞刷新任务调用；成功后原子写回；**不得重试/并发调用** |
| `POST /auth/revoke` | 吊销 refresh | 退出登录时调用；204 视为成功 |
| `GET /auth/me` | 拉 profile | 带 Bearer；401 走刷新规则 |

- **存储**：`access_token` / `refresh_token` 只进 Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`），**不写日志、不进 UserDefaults**。完整方案见 [ADR-0003](adr/0003-bearer-token.md)。
- **注入**：`APIClient` 对 `.bearer` 端点注入 `Authorization: Bearer <access>`；登录/刷新/吊销/`/health` 不注入，且它们的 401 **不触发**刷新（避免递归）。
- **单飞刷新**：并发 401 只允许一个 refresh 任务在飞，其余等待同一结果，成功后各自重放原请求一次；重放仍 401 → 登出。
- **失败语义**：refresh 被服务端拒绝（401/403）→ 清 token → 登出；**网络错误 → 保留 token、按离线处理**；业务 403 → `forbidden`，不登出。
- **退出**：`POST /auth/revoke {refresh_token}` → 清 Keychain + 账户缓存 + 跳登录。离线时无法吊销，服务端 refresh 仍可能有效（记录为已知限制）。
- **切换 base URL**：token 与服务器绑定，必须清 token 并重新登录。
- Web 端继续用 Cookie；服务端双模式并存，客户端不读写 Cookie。

### 4.4 Multipart 构造（`POST /attempts`、`/asr`、`/ocr`、`/chat/.../turn`）

字段规范（顺序固定，便于服务端与抓包对齐）：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `audio` | file | 视端点 | `/attempts`、`/attempts/async`、`/asr` 必填；`/chat/.../turn` 可选（带 audio 时服务端会顺带存录音并后台评分）；`/ocr` 不用 audio，用 `image` |
| `text` | text | `/chat/.../turn` **必填** | 对话的 ASR 文本；空字符串会被 400 `bad_request` 拒绝（≤500 字符） |
| `sentence_id` | text | 跟读/连读必填 | 语料 id |
| `reference_text` | text | 跟读/连读必填 | 句子英文原文；盲测时用隐藏句原文 |
| `mode` | text | 是 | `scripted` \| `unscripted` |
| `duration_ms` | text | 是 | 录音实际时长（整数毫秒） |
| `language` | text | 仅 `/asr` | `en`（默认，对话/复述） \| `zh-CN`（中文语音输入） |

各端点的最小字段集：

| 端点 | 字段 |
| --- | --- |
| `POST /attempts`、`/attempts/async` | `audio` + `sentence_id` + `reference_text` + `mode` + `duration_ms` |
| `POST /asr` | `audio` + 可选 `language` |
| `POST /chat/sessions/:id/turn` | **`text`** + 可选 `audio`；**不再由 turn 内部做 ASR/TTS** |
| `POST /ocr` | `image`（不是 `audio`） |

约束：
- 文件名与 `Content-Type` 必须与真实编码一致（`audio/mp4` ↔ `.m4a`），否则可能命中 `unsupported_audio`；
- 单文件 ≤ 12MB，客户端提交前检查，**不依赖服务端 413**；
- ≤ 2MB 时用内存 `Data` 拼 multipart；> 2MB（照片 OCR）用临时文件 + `uploadTask(fromFile:)`，避免峰值内存；
- boundary 用 `UUID().uuidString`；每个 part 之间严格 `\r\n`；结尾 `--boundary--\r\n`。

### 4.5 超时与取消

| 端点 | 请求超时 | 说明 |
| --- | --- | --- |
| `/health`、`/family/*`、`/suggestions` | 10s | 轻量 JSON |
| `/auth/token`、`/auth/refresh` | 10s | 登录/刷新；refresh 已在单飞任务里，不要叠加应用层重试 |
| `/auth/revoke` | 5s | 退出时调用；失败不阻塞本地清理 |
| `/sentences`、`/diagnosis`、`/review`、`/materials`、`/parent/summary`、`/chat/sessions/:id/messages` | 15s | 可缓存 / 轮询 |
| `/tts` | 20s | 首次合成 1–3s，留足余量 |
| `/asr`、`/ocr`、`/story/rewrite`、`/story/retell`、`/attempts`(同步) | 60s | 服务端推理 |
| `/attempts/async`、`/story/:id/illustrate`、`/chat/.../turn` | 30s | 生图/对话可能慢，超时走重试 UI |

- 所有请求用 `try Task.checkCancellation()` 保持可取消；页面 `onDisappear` 取消当前 `Task`；
- 用户离开对话页 → 取消正在进行的 `turn` 上传（服务端可能仍算完成，但客户端不再等待）。

### 4.6 解码约定

- JSON 为 `snake_case` → `keyDecodingStrategy = .convertFromSnakeCase`（`translation_zh` → `translationZh`）；
- 时间字段：**【待确认】** 是 ISO8601 还是 Unix 秒。实现上用 `.custom` 策略同时兼容两态；
- 未知字段忽略（`Codable` 默认行为），**不要**用 `JSONDecoder` 严格模式，否则后端加字段即崩；
- 空响应体：`204`/`Content-Length: 0` 视为成功，不要尝试解码；
- 音频响应：按 `Content-Type` 决定扩展名（`audio/wav` → `.wav`，`audio/mpeg`/`audio/mp3` → `.mp3`，缺省按请求的 `format` 兜底）。

### 4.7 重试策略

| 场景 | 重试 | 说明 |
| --- | --- | --- |
| GET（幂等） | 最多 2 次，200ms→800ms（±20% 抖动） | 仅对 `cannotConnectToHost`/`networkConnectionLost`/`timedOut`/5xx |
| POST 提交类（`/attempts`、`/ocr`、`/story/*`） | **不自动重试** | 推理有成本且可能非幂等；交给用户点“重试”，并在 UI 上明确 |
| `/attempts/async` | 可重试 1 次（仅在请求未发出时） | 连接失败不会产生服务端记录 |
| `/tts` | 可重试 2 次 | 幂等且便宜 |
| 401（业务接口） | **不按网络重试** | 由 `TokenRefresher` 单飞 refresh 一次，成功后重放原请求一次；refresh 被拒 → 登出 |
| `/auth/refresh` | **不重试** | 一次成败即结论；重试会撞“一次性轮换” |
| `/auth/token`、`/auth/revoke` | 不自动重试 | 凭据/副作用操作；交给用户重新提交或下次启动补吊销 |
| 取消 | 不重试 | `CancellationError` 原样上抛 |

> 连读模式的可靠性靠 **async + 轮询**，而不是 HTTP 重试；同步 `/attempts` 只用于单句跟读。

---

## 5. 错误模型与映射

### 5.1 错误类型

```swift
enum APIError: Error, Equatable, Sendable {
    case transport(URLError.Code)                    // 连接/超时/DNS
    case unauthorized                                 // 刷新后仍 401：会话失效，需重新登录
    case forbidden                                    // 403，孩子调家长接口
    case server(code: ServerErrorCode, message: String?, status: Int)
    case decoding(path: String)                       // 契约漂移，需上报
    case payloadTooLarge(localBytes: Int)             // 客户端预检拦截
    case cancelled
}
```

> **401 不直接冒泡到页面**：`APIClient` 先走单飞刷新；只有刷新被服务端拒绝（或重放仍 401）才转换为 `.unauthorized`，由 `SessionStore.handleUnauthorized()` 清 token 并跳登录。纯网络错误不能被映射成 `.unauthorized`（见 §4.3）。

`ServerErrorCode` 覆盖 `bad_request / unsupported_audio / payload_too_large / provider_error / provider_timeout / provider_unavailable / audio_not_found / session_closed / internal_error / unknown(String)`。

### 5.2 映射表（唯一事实来源）

| 服务端 `code` / HTTP | 成人文案 | 孩子文案 | 主操作 | 可重试 |
| --- | --- | --- | --- | --- |
| `transport(.notConnectedToInternet)` / `.networkConnectionLost` | 网络不可用，请检查是否连接到家里的 Wi-Fi | 先连上家里的 Wi-Fi 再玩哦 | 重试 | 是 |
| `transport(.cannotFindHost)` / `.cannotConnectToHost` / `.timedOut` | 连不上学习服务器（NAS 可能未开机或不在同一网络） | 服务器睡着了，叫爸爸妈妈看一下 | 重试 / 设置里改服务器地址 | 是 |
| HTTP 401 / `unauthorized` | 登录已过期，请重新登录 | 需要重新登录 | 重新登录 | 否 |
| HTTP 403 / `forbidden` | 当前账号无权访问该功能 | —（孩子不应触达） | 返回 | 否 |
| `bad_request` | 提交的内容不完整，请重试 | 这一句没准备好，再试一次 | 重试 | 否 |
| `unsupported_audio` | 音频格式不受支持，请重新录制 | 没听清，再录一次 | 重录 | 否 |
| `payload_too_large` / 413 | 录音太长了，请控制在 60 秒内 | 说得太久啦，短一点再试 | 重录 | 否 |
| `provider_timeout` | 评测服务响应超时，请重试 | 服务器有点慢，再试一次 | 重试 | 是 |
| `provider_unavailable` | 语音服务暂时不可用，稍后再试 | 现在不能评分，先听一听吧 | 稍后重试 / 去听示范 | 是 |
| `provider_error` | 服务处理失败，请重试（若持续失败请联系家长） | 出了点小问题，再试一次 | 重试 | 是 |
| `audio_not_found` | 找不到这段录音，可能已被清理 | 录音找不到了 | 重新录制 | 否 |
| `session_closed` (409) | 这段对话已经结束了，换个场景继续吧 | 这个场景结束啦，换一个吧 | 返回场景列表 | 否 |
| `internal_error` / 5xx | 服务器内部错误，请稍后再试 | 服务器打了个嗝，等一下再试 | 重试 | 是 |
| `decoding` | 版本不匹配，请更新 App（并告知家长） | — | 上报 | 否 |
| `cancelled` | 不显示 | 不显示 | — | 否 |

补充规则：
- **孩子模式下永不显示数字分数、永不出现红色失败态**；“重试”按钮始终是鼓励性文案。
- `provider_unavailable` 时提供**降级路径**：仍可播放示范音（TTS 也可能不可用 → 则提示“先看文本跟读”）。
- 所有错误都带一个 `diagnosticID`（客户端生成短 id 写日志），便于家长反馈时定位。

### 5.3 展示形式

| 场景 | 形式 |
| --- | --- |
| 页面首屏加载失败 | 全页 `ErrorStateView`（图标 + 文案 + 重试 + “检查服务器”入口） |
| 已加载后刷新失败 | 顶部 `ErrorBanner`（可关闭，保留旧数据） |
| 提交动作失败 | 卡片内联错误 + 主按钮变“重试”，**不弹 Alert** |
| 会话过期 | 全局 Alert/Sheet，唯一按钮“重新登录” |
| 权限被拒 | 专用卡片（见 `docs/audio.md` §2.3），不是错误态 |

---

## 6. 并发与 Actor 隔离

| 类型 | 隔离 | 原因 |
| --- | --- | --- |
| 所有 `View`、`*Store` | `@MainActor` | 直接驱动 UI，避免手动 hop |
| `APIClient` | `final class: Sendable`（非 actor） | `URLSession` 自身线程安全；token 由不可变的请求构造注入，不在 client 内缓存可变凭据 |
| `TokenStore` / `TokenRefresher` | `actor` | Keychain 读写与单飞刷新必须串行；并发 401 等待同一个 `Task` |
| `DiskCache`、`AudioCache`、`ImageCache` | `actor` | 文件读写 + 索引更新需要串行化 |
| `CorpusRepository` | `actor` | 合并并发请求（同一 level 只请求一次） |
| `AudioSessionController` | `actor` | category/active 切换必须串行，避免两处同时 `setCategory` |
| `VoiceRecorder` / `AudioPlayer` | `@MainActor` 门面 | AVFoundation 对象非 `Sendable`，只允许主线程访问；内部回调 hop 回主线程 |
| DTO | `struct: Sendable`（全 `let`） | 跨隔离传递 |
| 轮询任务 | 由 Store（MainActor）持有 `Task` | 取消点在 Store |

规则：
- Swift 6 严格并发下，`@unchecked Sendable` **必须**注释说明为什么安全，否则 review 拒绝。
- 网络/解码天然运行在非主线程（await 返回后回到 Store 的 MainActor），不要在 `Task.detached` 里再包一层。
- 一次“跟读提交”的并发模型：`submit()` 先 `cancel` 旧的评测任务，再 `await upload`，再把结果写回 Store。

### 6.1 异步评分轮询状态机（连读模式）

```
idle ──submit batch(A,B,C)──▶ polling(ids, deadline=+90s)
polling ──每 2s GET /attempts/status?ids=…──▶ polling
polling ──全部终态──▶ finished(results)
polling ──deadline 到──▶ timedOut(部分结果)   // 保留已完成，未完成标“稍后查看”
polling ──页面消失/用户取消──▶ cancelled       // 任务取消；数据保留在本地
```

- 轮询间隔 1.5s 起，连续两次无变化退到 3s，上限 5s；总数 ≤ 20 时一次批量查询，>20 分批（每批 10）；
- App 进入后台 → 暂停轮询（`scenePhase`），回前台立刻补一次，而不是继续后台烧电；
- 服务端可能返回 `pending`/`scoring` 之外的未知状态 → 视为 `pending` 并记录日志。

### 6.2 对话发音（后台评分）轮询

`turn` 只返回助手文本；用户那一轮的发音评分由服务端在响应之后异步写入，**不会**随 turn 返回，也不在 `GET /sessions/:id` 里。客户端要：

```
turn 200（拿到 user_message_id + user_audio_url）
  → 开始轮询 GET /chat/sessions/:id/messages（1s、2s、3s…，上限 ~15s）
  → 在 messages[].pron 中找这轮 user 消息：pron != null → 展示/停止
  → 超时仍为 null → 显示“稍后可在历史中查看”，不报错、不阻塞下一轮
  → 重新进入会话：先 GET /sessions/:id 渲染历史（无 pron），再拉一次 /messages 补齐 pron
```

- 轮询是**低优先级**的：用户再次录音/播放时暂停，避免抢带宽；
- 儿童端只拿 `pron` 做鼓励文案（服务端已剥离 IPA），**不显示数字**；
- 每次轮询限制为一次会话的 messages，不做全量历史同步。

---

## 7. 缓存与离线

### 7.1 分层缓存

| 层 | 载体 | 内容 | 上限 |
| --- | --- | --- | --- |
| 内存 | `NSCache` / Store 字段 | 当前列表、当前用户、最近 3 条评测 | — |
| 磁盘-可淘汰 | `Caches/` | TTS 音频、插画、录音副本、语料快照 | TTS 200MB、图片 100MB、录音 300MB |
| 磁盘-不可淘汰 | `Application Support/` | 小体积 JSON：最近练习、诊断快照、偏好 | < 5MB |
| 偏好 | `UserDefaults` | baseURL、TTS 语速偏好、是否自动播放 | — |
| 敏感 | Keychain | access/refresh token（本机专用）、上次登录标识（邮箱/用户 id/角色） | — |

### 7.2 缓存键

```swift
// 所有键都带 userId，避免共用 iPad 时串号
func cacheKey(_ parts: [String], userId: String) -> String {
    sha256(([userId] + parts).joined(separator: "|")).hex
}
```

| 资源 | 键组成 | TTL / 失效 |
| --- | --- | --- |
| 语料列表 | `sentences\|level=A1\|userId` | 24h 或手动刷新 |
| 单句 | `sentence\|id=123` | 同语料版本 |
| TTS | `tts\|sha256(text)\|rate\|voice\|format` | 永久（LRU 淘汰） |
| 插画 | `image\|materialId\|illustrationVersion` | 永久 |
| 诊断 | `diagnosis\|userId` | 12h（每次练习后失效） |
| 错音本 | `review\|userId` | 每次打开强制刷新（可先展示缓存） |
| 录音 | `recording\|attemptId` | 7 天 |

**退出登录必须清空**：Keychain 中的两个 token、`Caches/audio`、`Caches/images`、`Application Support/recent-*`、内存缓存。语料可保留（不涉及个人数据），但实现上统一走 `CacheJanitor.clearUserScoped(userId:)`；token 与账户缓存由 `SessionStore.logout()` 先调 `/auth/revoke` 再清（离线退出时仍清本地，见 ADR-0003 §6）。

### 7.3 离线能力矩阵

| 功能 | 无网络时 | 说明 |
| --- | --- | --- |
| 浏览语料 / 看翻译 | ✅ 用缓存快照 | 首次安装无缓存则显示空态 |
| 播放示范音（TTS） | ✅ 命中缓存可播；未命中禁用按钮 | 按钮置灰 + 提示“该句示范音未缓存” |
| 跟读录音 | ⚠️ 可以录，但**不能评分** | 录制按钮可用，提交时提示“需要连接服务器才能评分”，保留录音允许联网后重交（M4 可做） |
| 连读模式 | ❌ | 需要服务端评分，入口置灰 |
| 对话 | ❌ | 全链路在服务端 |
| 故事/OCR/改写/插画 | ❌ | 全部服务端能力 |
| 盲测 | ⚠️ 仅“盲听四选一”可用（纯客户端）；盲跟读不可用 | 见 `screens.md` |
| 诊断/错音本/家长面板 | ⚠️ 只读缓存 | 标注“数据可能不是最新” |

> **产品上必须诚实**：离线不能评分，不要做“先录后评”的假承诺，除非 M4 真的实现了离线队列（服务端无法离线，队列也只能联网后补交）。

### 7.4 离线检测

- `NWPathMonitor` 维护 `isOnline` 与 `isExpensive`（蜂窝）；
- 但**在线判定不能只看路径**：NAS 不可达时路径仍是 satisfied。因此在 `AppRoot` 启动、以及任意 `transport` 错误后，触发一次 `/health`（10s 超时，带 30s 节流），得到三态：`serverReachable / serverUnreachable / deviceOffline`；
- 顶部横幅按三态给不同文案（“没有网络” vs “连不上家里的服务器”），后者附带“检查 NAS 是否开机 / 是否同一 Wi-Fi”。

---

## 8. 安全与隐私

| 项 | 做法 |
| --- | --- |
| 凭据 | 不存密码；access/refresh token 只存 Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）；**不进 UserDefaults、不进日志、不进崩溃上报** |
| Keychain 项 | `kSecClassGenericPassword`：`service = "top.dreamsearch.english.coach.auth"`，`account = accessToken / refreshToken / tokenMeta`；另一个 service（`.session`）只存 `lastUser`（email/userId/role，无凭据） |
| 刷新 | 单飞刷新（actor），并发 401 只 refresh 一次；refresh 被拒才清 token；网络错误保留 token（见 ADR-0003） |
| 传输 | 仅 https；禁止在 Release 打开 `NSAllowsArbitraryLoads`；http 只允许 Debug 排障 |
| ATS | 不自签例外；NAS 证书必须被设备信任（换受信任证书或安装内网 CA）；LAN IP 场景需用户明确开启并二次确认（默认关闭） |
| 本地文件 | 录音/缓存目录 `.completeUntilFirstUserAuthentication`（后台播放需要） |
| 日志 | 不打印 access/refresh token、Cookie、密码、邮箱、音频；URL 中若含 id 可保留；`OSLog` 敏感字段用 `privacy: .private` |
| 隐私（必须如实告知） | 当前后端 `PROVIDER_MODE=hybrid`：**音频 → Azure**（ASR/发音评测/TTS）、**文本 → DeepSeek**（对话/改写/复述）、**图片 → DeepSeek/智谱**（OCR 视觉/插画）。**音频与照片会离开家庭网络**，不得写“录音不出户”；完全本地需 `PROVIDER_MODE=local` + 本地模型（**当前未部署**） |
| 隐私清单 | App bundle 内提供 `PrivacyInfo.xcprivacy`（Required Reason API + 收集数据声明），见 README §6.6 |
| 儿童数据 | 只上传评分必需的音频与文本；不做行为分析 SDK；不上报设备广告标识 |
| 截屏/后台快照 | 在 `scenePhase == .background` 时用模糊遮罩覆盖（家长面板可见孩子姓名） |
| 删除权 | 设置页提供“清除本机数据”（不影响服务端数据，服务端删除不在本期） |

---

## 9. 性能与可观测性

| 指标 | 预算 | 手段 |
| --- | --- | --- |
| 冷启动到首屏 | ≤1.5s | 启动不阻塞网络；语料走缓存后置刷新 |
| 语料首屏（局域网） | ≤1s | 单次请求 + 本地快照 |
| 录音开始延迟 | ≤150ms | 提前配置好 AVAudioSession，按下即录（见 audio.md） |
| 上传 10s 录音 | ≤1s（局域网） | m4a 16kHz/65kbps ≈ 81KB |
| TTS 起播 | 缓存 <300ms / 首次 ≤4s | 本地 TTS 缓存 + 首句预取 |
| 结果页渲染 | ≤1 帧丢弃 | 图表用 Swift Charts，数据点降采样 ≤200 点 |

日志：`OSLog` 分类 `net / audio / session / ui`；关键链路打 `signpost`（`load → record → upload → play`），用于定位“到底是网络慢还是评分慢”。

---

## 10. 测试策略

| 层 | 方式 | 必测用例 |
| --- | --- | --- |
| 纯逻辑 | XCTest | `ErrorMapper` 全 code 覆盖、`ScorePresenter`（孩子/成人）、`RetryPolicy`、`CacheKey`、Multipart 字节结构（含中文文本、CRLF） |
| 认证 | XCTest + `URLProtocol` 桩 | Keychain 存取（fake store）、401 单飞刷新（并发 3 个 401 只发 1 次 refresh）、refresh 被拒 → 清 token、网络错误不清 token、重放只一次、base URL 切换清 token |
| 网络 | `URLProtocol` 桩 或 `APITransport` fake | 401 触发刷新/登出、413 映射、坏 JSON → `decoding`、超时、取消 |
| 状态机 | XCTest（注入 fake transport + fake audio） | 连读轮询：全成功/部分超时/页面退出取消；对话 pron 轮询：按时出现/超时/null |
| UI | XCUITest | 登录 → 选句 → 录音（用预置 fixture 音频注入）→ 结果 → 下一句；退出后回登录页 |
| 音频真机 | 手工矩阵 | 见 `audio.md` §10（权限三态、耳机插拔、蓝牙、来电中断、静音开关） |

**不可自动化但必须人工验的**：麦克风权限流程（系统弹窗）、蓝牙路由、来电中断、后台播放。UI 测试里不要尝试点系统权限弹窗。

---

## 11. 与后端契约的未知项（实现前必须先对齐）

| # | 未知 | 影响 | 归属 |
| --- | --- | --- | --- |
| B3 | `/story/rewrite` 是否返回句子数组及 story id | 复述页需要 `story_sentences`，否则要客户端拆分 | 后端 |
| B6 | `/parent/summary` 字段 | 家长面板布局（必须先拿到样例） | 后端 |
| B7 | `/suggestions` POST 的字段与状态语义 | 提建议表单 | 后端 |
| B9 | `/attempts` 响应中音素/词/语调曲线的确切结构 | 结果页与图表 | 后端 |
| B10 | `/sentences` 是否分页、是否支持 ETag | 缓存与刷新策略 | 后端 |
| B11 | `/diagnosis` 是否含历史趋势 | 成长页是否能画趋势线 | 后端 |
| B13 | 服务端是否对并发评分/生图限流 | 连读批量大小、生图重试 | 后端 |
| B17 | token 三端点的错误码、refresh 轮换/重放检测、`/revoke` 后 access 是否立即失效 | 认证实现与失败语义（ADR-0003） | 后端 |

> **已确认（不再是未知项）**：`/chat/sessions/:id/turn` 只返回助手文本（含 `reply`/`reply_zh`/`correction`/`user_audio_url` 等），**不做 ASR、不返回 TTS 音频**；对话链路是 `/asr` → `/turn`（`text` 必填）→ `/tts`；发音评分在 `GET /sessions/:id/messages` 的 `pron`（异步，需轮询），`GET /sessions/:id` 不含该字段。原 B1 已确认；原 B12（Cookie 属性）随 ADR-0001 作废，由 B17（token 端点）替代。

以上均已登记到 `open-questions.md`，并标注阻塞的里程碑。

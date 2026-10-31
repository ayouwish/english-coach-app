# 架构设计 · ArkTS / ArkUI 分层

> 适用：HarmonyOS NEXT / API 20+，ArkTS + ArkUI。
> 本文描述**客户端内部结构**；服务端 API 事实以 [`../README.md`](../README.md) 第 2 节为准。

---

## 1. 目标与非目标

### 1.1 目标

1. **一个入口**：所有请求只走 `commons/net`，页面/VM 不直接碰 `http.createHttp()`。
2. **状态可预测**：会话、儿童模式、用量是全局状态；页面状态归页面 VM；列表用可观察数组。
3. **失败可解释**：任何网络/权限/媒体错误都能映射成一句中文 + 一个可执行的下一步。
4. **录音不丢**：上传失败时本地保留，用户可重试；不在用户不知情时重复上传/重复计费。
5. **儿童安全**：IPA、低分、复杂图表在渲染前就被过滤，而不是“渲染后再藏”。
6. **可测试**：HTTP/录音/播放都可替换为 fake，VM 可脱离真机跑单测。

### 1.2 非目标

- 不做离线完整业务（提交评测、对话、故事生成必须联网）。
- 不做后台录音/锁屏录音。
- 不做多端实时同步（服务端 SQLite 是唯一事实源）。
- 不把 AI 能力放客户端。

---

## 2. 分层视图

```text
┌─────────────────────────────────────────────────────────────┐
│ UI 层（ArkUI 声明式）                                        │
│  pages/*.ets  ← 只做布局、事件绑定、导航                     │
│  components/*.ets ← 无状态/低状态展示组件                    │
└───────────────────────────┬─────────────────────────────────┘
                            │ 只调用 VM 方法 / 读 VM 可观察字段
┌───────────────────────────▼─────────────────────────────────┐
│ ViewModel 层（@Observed class）                              │
│  - 页面状态：loading / error / empty / data                  │
│  - 业务编排：先 ASR 再 turn 再 TTS；先 async 再轮询          │
│  - 把 ApiError 映射成 UiError                                │
└───────────────────────────┬─────────────────────────────────┘
                            │ 只调用 Service
┌───────────────────────────▼─────────────────────────────────┐
│ Service 层（feature service / commons service）              │
│  AuthService / SentenceService / AttemptService /            │
│  ChatService / StoryService / ParentService / ...            │
│  - 拼 URL、DTO 转换、缓存策略、重试策略                      │
└───────────────────────────┬─────────────────────────────────┘
                            │ 只调用 HttpClient
┌───────────────────────────▼─────────────────────────────────┐
│ 基础设施层（commons）                                        │
│  HttpClient / TokenSession / AssetStore / FileCache /        │
│  AvRecorderService / AvPlayerService / AudioCoordinator      │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
                 家庭 NAS（web :3000 /api）
```

**硬规则**：

- UI 不解析 JSON、不拼 URL、不处理 `error.code`。
- VM 不直接 `http.createHttp()`、不直接操作 `AVRecorder`。
- Service 不持有页面生命周期，不弹 Toast。
- 基础设施层不 import 任何 feature/entry 代码。

---

## 3. 状态管理

### 3.1 分层策略

| 状态 | 存放 | 装饰器 | 生命周期 |
|---|---|---|---|
| 当前用户、角色、儿童模式 | `AppStorage` | `@StorageLink('session')` | 登录 → 登出 |
| 今日用量 | `AppStorage` | `@StorageLink('usage')` | 登录后 / 每次提交后更新 |
| 服务器地址、健康状态 | `AppStorage` | `@StorageLink('appConfig')` | App 启动 |
| 页面数据（句子、结果、消息） | 页面 VM 实例 | `@State vm: XxxVM` + `@Observed` | 页面创建 → 销毁 |
| 子组件单向入参 | `@Prop` | `@Prop` | 父更新 → 子重渲染 |
| 父子双向绑定（输入框、开关） | `@Link` | `@Link` | 双向 |
| 嵌套对象字段变化 | `@Observed` + `@ObjectLink` | `@ObjectLink` | 列表项/嵌套卡片 |
| 跨多层向导（连读 setup） | `@Provide/@Consume` | `@Provide/@Consume` | 向导树 |
| 长列表 | `LazyForEach` + `IDataSource` | — | 列表可见区 |

### 3.2 示例（示意）

```ts
// commons/model/src/main/ets/model/SessionState.ets
@Observed
export class SessionState {
  user: UserDTO | null = null;
  isChild: boolean = false;
  role: string = 'child';
  expiresAt: string = '';
}
```

```ts
// entry/src/main/ets/pages/Index.ets（示意）
@Entry
@Component
struct Index {
  @StorageLink('session') session: SessionState = new SessionState();
  @State navStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.navStack) {
      // 首页/业务页由 NavDestination 注册
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
  }
}
```

### 3.3 VM 约定

```ts
@Observed
export class PracticeVM {
  sentences: SentenceDTO[] = [];
  selected: SentenceDTO | null = null;
  loading: boolean = false;
  submitting: boolean = false;
  error: UiError | null = null;
  result: AttemptResultDTO | null = null;

  async load(level: string): Promise<void> { /* ... */ }
  async submit(recording: RecordingDTO): Promise<void> { /* ... */ }
  dispose(): void { /* 取消轮询、释放播放器、清临时文件 */ }
}
```

- VM 只暴露**方法**和**可观察字段**；UI 不直接改 `vm.result`。
- 每个页面 `aboutToAppear` 调 `vm.load()`；`aboutToDisappear` 调 `vm.dispose()`。
- 更新 AppStorage 中的 `SessionState` 时**整体替换对象**（`AppStorage.setOrCreate('session', new SessionState(...))`），避免嵌套属性变更不触发刷新。
- VM 内不引用 `UIContext`/`promptAction`；需要 Toast 时通过回调 `onUiEvent` 交给页面。
- VM 的所有异步方法都要有 `try/catch`，最终转成 `UiError`。

### 3.4 为什么不把大列表放 AppStorage

- AppStorage 是全局单例，放 600 句语料会造成所有页面重渲染与内存常驻。
- 语料放 `commons/storage` 的文件缓存 + 页面 VM 持有；AppStorage 只存 `lastLevel` 这类小配置。
- 儿童模式只存 `isChild` 布尔与 `childScale`，不存整份用户对象副本。

---

## 4. 路由与导航

### 4.1 路由方案

使用 **`Navigation` + `NavPathStack`**，每个业务页面是一个 `NavDestination`。`entry` 维护根栈，feature 通过 `Index.ets` 暴露 `@Builder` 或路由注册函数。

```ts
// commons/model/src/main/ets/router/Routes.ets
export class Routes {
  static readonly LOGIN = 'login';
  static readonly PRACTICE = 'practice';
  static readonly FLOW = 'flow';
  static readonly CHAT_SCENARIOS = 'chat_scenarios';
  static readonly CHAT_SESSION = 'chat_session';
  static readonly STORY_LIST = 'story_list';
  static readonly STORY_CREATE = 'story_create';
  static readonly STORY_DETAIL = 'story_detail';
  static readonly BLIND_TEST = 'blind_test';
  static readonly DIAGNOSIS = 'diagnosis';
  static readonly REVIEW = 'review';
  static readonly PARENT = 'parent';
  static readonly SETTINGS = 'settings';
  static readonly CHANGE_PASSWORD = 'change_password';
  static readonly SUGGESTIONS = 'suggestions';
}
```

### 4.2 路由表

| 路由 | 模块 | 参数 | 角色 |
|---|---|---|---|
| `login` | features/auth | `redirect?` | 未登录 |
| `practice` | features/practice | `level?`, `focus?`, `sentenceId?` | 所有 |
| `flow` | features/flow | `materialId?`, `mode?` | 所有 |
| `chat_scenarios` | features/chat | — | 所有 |
| `chat_session` | features/chat | `sessionId`, `scenarioId` | 所有 |
| `story_list` | features/story | `kind=page` 或 `kind=story` | 所有 |
| `story_create` | features/story | `level?` | 所有 |
| `story_detail` | features/story | `materialId` | 所有 |
| `blind_test` | features/blindtest | `resume?` | 所有 |
| `diagnosis` | features/diagnosis | `focus?` | 所有 |
| `review` | features/diagnosis | — | 所有 |
| `parent` | features/parent | `tab?` | **仅 parent** |
| `settings` | features/settings | — | 所有 |
| `change_password` | features/auth | `memberId?` | 家长；儿童只读提示 |
| `suggestions` | features/settings | `page?` | 所有（家长可看收件箱） |

### 4.3 登录门禁

```text
App 启动
  → 读 Asset 中的 ec_access_token / ec_refresh_token
  → 无 refresh：进 login
  → 有 refresh：GET /auth/me（带 access）
       ├─ 200 user != null：写 SessionState → 进首页
       ├─ 401：单飞 refresh → 成功则重放 /auth/me；失败清 token → 进 login
       ├─ 200 user == null：清 token → 进 login（兼容旧行为）
       └─ 网络失败：显示“连不上家庭 NAS”，提供重试/离线只读入口
```

- **不靠前端隐藏菜单做权限**：进入 `parent` 前检查 `role === 'parent'`；服务端仍会 403 兜底。
- 任何业务请求返回 401：先走一次单飞 refresh + 重放；仍 401 才 `SessionService.onUnauthorized()` → 清 token/缓存 → `navStack.clear()` → `push('login')`。
- `/auth/token`、`/auth/refresh`、`/auth/revoke`、`/health` 不参与该重试，避免递归。
- 登录成功后按角色决定首页 tab：儿童 4 个（跟读/连读/故事/我的），家长 5 个（+ 家长面板）。
- 深链（如 `englishcoach://flow?materialId=...`）先在 `DeeplinkService` 做登录检查，再入栈；未登录时暂存 pending route。

### 4.4 返回与栈行为

- 练习/连读/盲测进行中：返回前弹确认（“这次进度还没提交，确定离开？”）；已提交的异步条目继续后台轮询？**不**，页面销毁即停止轮询，但服务端继续评分；下次进入按 `ids` 恢复。
- 对话进行中：返回保留会话（服务端已存），再次进入可恢复。
- 故事生成中：返回不取消网络请求（服务端仍在跑），但客户端不再展示进度；重进列表刷新。
- 登录页不允许返回上一页；`navStack.clear()`。

---

## 5. HTTP 封装

### 5.1 接口签名（示意）

```ts
// commons/net/src/main/ets/client/HttpClient.ets
export interface ApiRequest {
  method: http.RequestMethod;
  path: string;                       // '/auth/me'（不含 /api）
  query?: Record<string, string>;
  json?: Object;                      // JSON body
  form?: http.MultiFormData[];        // multipart
  headers?: Record<string, string>;
  timeoutMs?: number;
  responseType?: 'json' | 'arrayBuffer';
  auth?: boolean;                     // 默认 true；/auth/token、/auth/refresh、/health 为 false
  retryOn401?: boolean;               // 默认 true；/auth/refresh 自身为 false
}

export interface ApiResponse<T> {
  status: number;
  data: T;
  headers: Record<string, string>;
}

export class ApiError extends Error {
  code: string = 'internal_error';
  status: number = 0;
  detail: string = '';
  retryable: boolean = false;
  requestId: string = '';
}

export interface HttpClient {
  request<T>(req: ApiRequest): Promise<ApiResponse<T>>;
  upload<T>(path: string, parts: http.MultiFormData[], fields: Record<string, string>): Promise<T>;
  download(path: string, destPath: string, timeoutMs?: number): Promise<void>;
}
```

```ts
// commons/net/src/main/ets/session/TokenSession.ets
export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  accessExpiresAt: number;           // epoch ms；由 expires_in 换算
}

export interface TokenSession {
  load(): Promise<void>;
  accessToken(): string | null;
  refreshToken(): string | null;
  save(pair: TokenPair): Promise<void>;   // 原子替换两个 token
  clear(): Promise<void>;
  needsRefresh(now?: number, skewMs?: number): boolean;  // 过期或在 skew 窗口内
}
```

### 5.2 请求构造

```ts
const req = http.createHttp();
try {
  const resp = await req.request(url, {
    method: http.RequestMethod.POST,
    header: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`,
      'Accept': 'application/json'
    },
    extraData: JSON.stringify(body),
    expectDataType: http.HttpDataType.STRING,
    usingCache: false,
    connectTimeout: 10_000,
    readTimeout: 30_000,
    maxLimit: 20 * 1024 * 1024
  });
  // ...
} finally {
  req.destroy();
}
```

要点：

- **每次请求新建 `HttpRequest`，用完 `destroy()`**；不要跨请求复用（文档明确一个实例对应一个请求）。
- `usingCache: false`：API 响应不能被系统 HTTP 缓存污染；缓存由我们自己控制。
- `maxLimit`：JSON 默认 5MB 足够；音频/图片下载显式设 20MB（图片 5MB、录音 12MB）。
- `header` 用 `Record<string,string>`，不要传 Map。
- `expectDataType: STRING` 用于 JSON；音频用 `ARRAY_BUFFER`。
- 所有 URL 的 query 做 URL 编码（中文/特殊字符；TTS 文本走 POST body，避免 URL 编码问题）。

### 5.3 Bearer Token 认证（方案 B）

移动端**不使用 Cookie**；Web 端继续用 Cookie，后端双模式并存。认证相关的新端点只有三个：

```text
登录
  POST /api/auth/token {email, password}
  ← {access_token, refresh_token, token_type:"Bearer", expires_in:3600, user}
  → TokenSession.save({accessToken, refreshToken, accessExpiresAt = now + expires_in*1000})
  → GET /auth/me（带 access）补 usage

刷新（单飞）
  POST /api/auth/refresh {refresh_token}
  ← {access_token, refresh_token, expires_in}
  → 原子替换两个 token；旧 refresh 已被服务端作废

退出
  POST /api/auth/revoke {refresh_token}   → 204
  → 无论成功失败，都清 Asset 中的两个 token + 页面缓存 + `cacheDir` 音频
```

**单飞刷新**（`commons/net` 内实现，VM/页面不可见）：

- 任何带 `auth:true` 的请求返回 401 → 只允许一次 refresh；并发 401 共享**同一个 Promise**，等待后各自重放原请求。
- 每个请求的自动重放**最多一次**；重放仍 401 → 清 token、发一次全局 `unauthorized` 事件、跳登录。
- `/auth/token`、`/auth/refresh`、`/auth/revoke`、`/health` 不参与 401 刷新，避免递归。
- refresh 返回 401/400（refresh 已失效/被吊销/被别的设备轮换掉）→ 清 token 跳登录。
- refresh 遇到网络错误/5xx → **不清 token**，把原请求以可重试错误抛出，让用户重试；避免一次断网就登出。
- access 过期前 60s 可主动刷新（可选优化），仍走同一把单飞锁。

```ts
// 示意：不是最终实现
let refreshing: Promise<void> | null = null;

function refreshOnce(): Promise<void> {
  if (!refreshing) {
    refreshing = doRefresh().finally(() => { refreshing = null; });
  }
  return refreshing;
}

async function doRefresh(): Promise<void> {
  const rt = session.refreshToken();
  if (!rt) throw new UnauthorizedError();
  const resp = await raw({ method: POST, path: '/auth/refresh', json: { refresh_token: rt },
                           auth: false, retryOn401: false });
  if (resp.status === 401 || resp.status === 400) {
    await session.clear();
    throw new UnauthorizedError();
  }
  if (resp.status !== 200) throw new ApiError({ retryable: true });  // 不清 token
  await session.save(toTokenPair(resp.data));                       // 原子替换
}
```

**安全取舍**：

- access/refresh 放 **Asset Store Kit**（`@ohos.security.asset`；Kit 聚合导入为 `@kit.AssetStoreKit`），`asset.add/query/remove` + `Tag.SECRET`，不写 Preferences、不写日志、不进备份。
- token 是敏感凭证：不埋点、不出现在错误详情/诊断导出/剪贴板/通知。
- refresh 是**一次性**的：保存前若进程被杀，服务端已作废旧 refresh，下次启动会刷新失败并回登录页——这是可接受的失败方式，不做“重试旧 refresh”。
- 不用“本地过期时间”当唯一依据；以服务端 401 为准。
- 不实现“记住密码”；登录页可选记住邮箱（默认关）。

**Asset Store vs Preferences（加密）取舍**：

| 维度 | Asset Store Kit | Preferences（明文/自行加密） |
|---|---|---|
| 加密 | 系统级加密存储，按别名访问 | 默认明文；要加密需自己用 Crypto Framework + 管理密钥 |
| 访问控制 | 可配 `ACCESSIBILITY`、`AUTH_TYPE`、`REQUIRE_PASSWORD_SET` | 无系统级访问控制 |
| 同步/备份 | 显式设 `SYNC_TYPE.NEVER`，不参与云同步 | 随应用数据，可能进备份 |
| 容量 | `SECRET` 有单条长度上限（官方文档为 1024 字节，**以 SDK/实测为准【待确认】**） | 适合小配置，不适合长密钥 |
| 复杂度 | 低（API 20 基线全部可用，含 `add/query/remove` 及同步版本） | 自行加密时密钥放哪又是新问题 |
| 适用 | **access token、refresh token** | 非敏感配置（baseUrl、lastLevel、ttsRate、token 过期时间戳） |

结论：**两个 token 必须进 Asset Store**；Preferences 只放非敏感配置（含 `accessExpiresAt` 时间戳）。不要为了“少一个 API”把 token 塞进 Preferences，也不要用固定密钥自行加密（密钥同样要存，等于没解决）。

> 【待确认】若 access token 用 JWT 且长度接近/超过 Asset 单条上限：优先让后端改用不透明短 token，而不是把 token 拆成多条 secret。refresh token 通常很短，不受影响。

### 5.4 multipart 上传

录音文件走 `multiFormDataList`（API 11+），**不要把 12MB 读进内存再拼字符串**：

```ts
const parts: http.MultiFormData[] = [
  {
    name: 'audio',
    contentType: 'audio/mp4',
    filePath: recordingPath,       // 应用沙箱路径
    remoteFileName: 'recording.m4a'
  },
  { name: 'sentence_id', contentType: 'text/plain', data: sentenceId },
  { name: 'reference_text', contentType: 'text/plain', data: text },
  { name: 'mode', contentType: 'text/plain', data: 'scripted' },
  { name: 'duration_ms', contentType: 'text/plain', data: String(durationMs) }
];
```

- `Content-Type` 必须是 `multipart/form-data`（不要手动加 boundary，系统会生成）。
- 音频 MIME 用 **`audio/mp4`**、文件名 `*.m4a`；服务端按 `mime.includes('mp4')` 存为 `.m4a`，再交 PyAV 解码。
- 字段名严格按 README 第 2 节；不要多传/改名。
- 上传前本地校验：文件存在、大小 ≤ 12MB、时长 0.6–60s。
- OCR 图片用同一套 upload，字段名 `image`，MIME `image/jpeg`，≤10MB。

### 5.5 下载与图片

`/api/audio/:id`、`/api/materials/:id/image` 都需要 `Authorization: Bearer`；其中录音接口明确返回 **`accept-ranges: none`**，图片接口也不是为流式/分块读取设计的：

- **不要**把 URL 直接交给 `AVPlayer.url` 或 `Image(url)`：它们不会带 `Authorization`，且可能依赖 Range。
- 统一走 `HttpClient.download` → `cacheDir/audio|images/<hash>.<ext>` → 再交给 AVPlayer/ImageSource。
- 下载用 `requestInStream` 或 `request` + `ARRAY_BUFFER`（≤20MB），写入临时文件后原子 rename。
- 图片：`image.createImageSource(path).createPixelMap()`，再 `Image(pixelMap)`；避免 `Image('https://...')`。
- 下载失败不覆盖旧缓存；临时文件 `.part` 启动时清理。

### 5.6 超时

| 接口 | 客户端超时 | 服务端上游超时 | 说明 |
|---|---:|---:|---|
| `/health` | 5s | 3s | 快速判断 NAS 可达 |
| `/auth/token` | 15s | — | 慢网络 |
| `/auth/refresh` | 15s | — | 单飞；网络失败不清 token |
| `/auth/revoke` | 10s | — | 退出时失败也清本地 |
| `/sentences` | 15s | — | 可缓存 |
| `/attempts`（同步） | **120s** | 60s pronounce + 40s feedback | 不要 30s 就断；给足上游重试余量 |
| `/attempts/async` | 30s | — | 只写 pending |
| `/attempts/status` | 15s | — | 轮询 |
| `/chat/sessions/:id/messages` | 15s | — | 轮询 `pron` |
| `/asr` | 45s | 30s | |
| `/tts` | 30s | 20s | |
| `/chat/.../turn` | 60s | 40s | |
| `/ocr` | **75s** | 60s | 首次加载模型 |
| `/story/rewrite` | **75s** | 60s | LLM |
| `/story/retell` | 75s | 60s | |
| `/story/:id/illustrate` | **120s** | 90s | 文生图 |
| `/materials`、`/diagnosis`、`/parent` | 30s | — | |

### 5.7 重试策略

| 操作 | 自动重试 | 理由 |
|---|---|---|
| GET（语料/诊断/状态/材料） | 2 次，500ms/1.5s + 抖动 | 幂等、便宜 |
| 图片/音频下载 | 2 次 | 幂等 |
| 登录 | 0 | 避免多次会话 |
| `/attempts`（同步） | **0** | 服务端会落库；重发=重复评测/计费 |
| `/attempts/async` | **0** | 同上；网络失败时提示“可能已提交，去历史查看” |
| `/attempts/:id/retry` | 0 | 用户显式点 |
| `/asr` | 1 次 | 纯识别，幂等 |
| `/tts` | 1 次 | 幂等 |
| `/chat/.../turn` | **0** | LLM 有成本，重发会多一轮 |
| `/story/rewrite` | 0 | 同上 |
| `/ocr` | 1 次 | 识别幂等 |
| `/illustrate` | 0 | 有费用，用户点“再试一次” |

> 【待后端新增】若要做到“网络中断后安全重发”，需要服务端支持 `Idempotency-Key`（或客户端 `request_id` 去重）。当前没有，所以对写操作一律不自动重试。

---

## 6. 错误映射

### 6.1 统一 UiError

```ts
export class UiError {
  title: string = '';
  message: string = '';
  actionLabel: string = '';
  action: UiAction = UiAction.NONE;
  retryable: boolean = false;
  code: string = '';
}
```

- `code` 仅用于日志/测试，不直接展示。
- `message` 优先用服务端 `error.message`（后端已经是中文、可操作）。
- 服务端没有 `message` 或网络层错误时，用下表兜底。

### 6.2 映射表

| 来源 | code / 条件 | 用户看到的中文 | 动作 |
|---|---|---|---|
| 400 | `bad_request` | 服务端 message（如“录音文件过大”） | 返回修改 |
| 400 | `content_unsafe` | 这段内容暂时画不成插画，换个说法试试 | 返回编辑 |
| 401 | `unauthorized` | 登录已过期，请重新登录 | 先单飞 refresh 重放一次；仍 401 才清会话 → 登录 |
| 403 | `forbidden` | 这个功能只有家长可以用 / 你没有权限看这个内容 | 返回 |
| 404 | `not_found` | 内容不在了，刷新看看 | 刷新/返回 |
| 404 | `audio_not_found` | 这条录音找不到了，可能已过期 | 隐藏播放按钮 |
| 409 | `session_closed` | 这个场景已经结束了，换一个继续吧 | 回场景列表 |
| 409 | `blind_test_closed` | 这次盲测已经结束了 | 回盲测首页 |
| 409 | `no_practiced_sentences` | 还没有练过的句子，先去跟读几句吧 | 去跟读 |
| 409 | `no_attempts` | 这次盲测还没有提交任何一句 | 继续录 |
| 409 | `no_audio` | 这条记录没有保存录音，无法重试 | 重新录 |
| 410 | `audio_gone` | 录音文件不在了 | 重新录/隐藏重试 |
| 409 | `blind_attempt_no_retry` | 盲测中的录音不能重试评测 | 结束盲测再看 |
| 413 | `payload_too_large` | 录音/图片太大了（上限 12MB / 10MB） | 缩短/重拍 |
| 429 | `daily_limit_reached` | 今天已经练了 X 分钟，达到上限，明天再来 🌙 | 展示剩余，禁用录音 |
| 500 | `internal_error` | 服务器开小差了，稍后再试 | 重试一次 |
| 502 | `provider_error` | 语音服务暂时不可用；录音已保存，稍后可重试 | 显示“重试评测” |
| 503 | `provider_unavailable` | 这个能力现在没开，换一种方式试试 | 置灰入口 |
| 503 | `ocr_unavailable` | 拍照识别未启用，可以手动输入 | 切手动 |
| 503 | `story_unavailable` | 故事改写暂未就绪，可以先自己写英文 | 切手动 |
| 503 | `retell_unavailable` | 复述评估暂未就绪 | 返回故事 |
| 503 | `illustration_unavailable` | 插画服务暂未配置 | 隐藏入口 |
| 504 | `provider_timeout` | 这次等太久了，再试一次 | 重试 |
| 网络 | `2300006` / `2300007` | 连不上家里的服务器，请确认连着家庭 Wi-Fi | 重试/检查网络 |
| 网络 | `2300028` / 客户端 timeout | 请求超时了，网络有点慢 | 重试 |
| 网络 | `2300997` | 当前网络不允许明文 HTTP（开发配置问题） | 提示改 HTTPS |
| 网络 | 客户端 `offline` | 现在没有网络，先看看缓存的内容吧 | 离线只读 |
| 媒体 | `mic_denied` | 需要麦克风才能练习；去设置里允许 | 打开设置 |
| 媒体 | `mic_unavailable` | 麦克风被占用了，关掉其他录音 App 再试 | 重试 |
| 媒体 | `record_too_short` | 这次录得太短啦，读完句子再点“说完啦” | 重录 |
| 媒体 | `record_too_large` | 录音超过 12MB，请缩短录音 | 重录 |
| 媒体 | `playback_failed` | 声音播放失败，点播放器再试一次 | 重播 |

### 6.3 展示规范

- **页面级错误**：顶部 `ErrorBanner`（浅红底），带“重试/去设置”按钮；不遮挡主内容。
- **操作级错误**：按钮下方内联文本；不弹全屏 Dialog。
- **致命错误**（401/无网络且无缓存）：全屏 `EmptyState` + 一个主按钮。
- 儿童模式：错误文案更短、更口语，不出现 HTTP 状态码/英文 code。
- 任何错误都可复制诊断信息（长按标题 3 秒，debug 包才启用），内容不含 token/录音。

---

## 7. 离线缓存

### 7.1 缓存分层

| 层 | 位置 | 内容 | TTL / 淘汰 |
|---|---|---|---|
| 内存 | VM | 当前列表、当前结果 | 页面销毁 |
| 文件 | `filesDir/cache/corpus/*.json` | 语料（按 level） | 24h，启动后台刷新 |
| 文件 | `cacheDir/audio/` | TTS、录音回放 | LRU，50MB / 7 天 |
| 文件 | `cacheDir/images/` | 材料图、插画 | LRU，100MB / 30 天 |
| 文件 | `filesDir/pending/` | 未上传成功的录音 | 最多 3 条 / 24h；登出清空 |
| Preferences | `ec_prefs` | baseUrl、lastLevel、ttsRate、childScale、lastEmail | 持久 |
| Asset | Asset Store | `ec_access_token` / `ec_refresh_token` | access 1h、refresh 30 天；刷新时原子替换 |

**不缓存**：家长面板汇总、建议收件箱、家庭成员列表、密码相关响应。这些是敏感/强时效数据，每次进页面重新拉。

### 7.2 语料缓存策略

```text
进入练习页
  → 读本地 corpus_<level>.json
      ├─ 有且 <24h：立即渲染（无 loading 闪烁）
      │     └─ 后台 GET /sentences?level= 刷新，成功则替换并 diff
      └─ 无/过期：显示骨架屏 → GET → 成功写文件 → 渲染
            └─ 失败且有过期缓存：渲染旧数据 + 顶部“离线内容，可能不是最新”
            └─ 失败且无缓存：EmptyState + 重试
```

- 语料是 600 句量级，单文件 JSON 放 `filesDir`；**不要塞 Preferences**（值长度限制/性能都不合适）。
- 写入用“临时文件 + rename”，避免半截 JSON。
- 缓存 key 含 `level` 与 `userId`（自定义语料是用户可见性隔离的）；切换账号必须失效。
- 儿童缓存的 `focus_phonemes` 也必须为空：缓存写入前按角色裁剪，不能依赖渲染时隐藏。

### 7.3 失败录音的本地保留

- 录音完成 → 先写 `filesDir/pending/<uuid>.m4a` + 元数据 JSON。
- 上传成功 → 删除 pending；失败 → 保留，列表显示“有 1 条录音待重试”。
- 重试只允许用户手动点；**不自动后台上传**（避免流量/隐私/重复计费）。
- 退出登录、切换账号、超过 24h：清理 pending 并提示。
- 不把 pending 录音放入系统相册/公共目录。

### 7.4 缓存一致性

- 登录/登出：清空 `cacheDir/audio`、`filesDir/pending`、语料缓存、材料图缓存。
- 家长修改孩子等级/时长后：孩子下次 `/auth/me` 或 `/settings` 刷新；客户端不长期缓存 `cefrLevel` 作为唯一事实。
- 盲测/连读结果：以服务端 `/attempts/status` 为准；本地只缓存“已展示过的结果”，不缓存“分数预测”。

---

## 8. 并发与生命周期

### 8.1 单飞（single-flight）

- `/health`：App 启动并发多次时只发一个请求，其余 await 同一个 Promise。
- **token 刷新**：并发 401 只发一次 `/auth/refresh`，其余 await 同一个 Promise；成功后各自重放原请求，失败则统一登出。
- 语料加载：同 level 同时只发一个 GET。
- 图片下载：同 URL 同时只发一个下载。
- 登录：按钮 loading 期间禁用，避免重复会话。

### 8.2 录音/播放互斥

由 `AudioCoordinator` 统一管理（详见 [audio.md](audio.md)）：

```text
IDLE ──record──► RECORDING ──stop──► IDLE
IDLE ──play────► PLAYING   ──end───► IDLE
RECORDING ──play──► 先 stopRecording(discard=true) → PLAYING
PLAYING ──record──► 先 stopPlayback() → RECORDING
```

- 任何时刻最多一个录音器、一个播放器。
- 页面切后台/销毁：`AudioCoordinator.stopAll()`，录音丢弃（不静默保留）。

### 8.3 连读轮询

```text
提交 async → 得到 id
  → 加入 pendingIds
  → 每 2s GET /attempts/status?ids=...
  → 有 done：更新对应条目，移出 pending
  → 全部 done 或页面销毁：停止
  → 连续失败 3 次：退避到 5s/10s；仍失败则显示“评分服务暂时不可用，稍后刷新”
```

- 轮询只在连读/盲测页面存活时进行；页面销毁即停。
- 重进页面：从本地 pending 记录恢复 ids，再继续轮询。
- 批量上限 50；超过分批。
- 不做 WebSocket/SSE（服务端没有）。

### 8.4 对话串行

- 一轮未完成前禁用录音按钮；不允许并发 `turn`。
- ASR 失败：不发送 turn，保留录音，提示重试。
- turn 成功但 TTS 失败：文字回复照常展示，提供“再读一遍”按钮；不重发 turn。
- 6 轮后 `done=true`：展示结束卡片，禁用输入，提供“换个场景”。

---

## 9. 关键时序

### 9.1 登录

```text
UI → AuthVM.login(email, pwd)
  → POST /auth/token（auth:false）→ 200 {access, refresh, expires_in, user}
  → TokenSession.save(pair)（两个 token 一起写 Asset）
  → GET /auth/me（带 Authorization）
  ← {user, usage}
  → AppStorage.session / usage
  → Navigation.replace('home')
```

### 9.2 跟读（同步）

```text
UI（录音完成）→ PracticeVM.submit(recording)
  → 本地校验 size/duration
  → POST /attempts（multipart）
  ← 200 {attempt_id,result,feedback,usage,...}
  → 更新 result / usage
  → 播放回放（可选）：GET /audio/:id → cache → AVPlayer
```

### 9.3 连读（异步）

```text
UI → FlowVM.start(items)
  → 录一句 → POST /attempts/async → {id,pending}
  → 立刻进入下一句（不等待）
  → PollScheduler 每 2s GET /attempts/status?ids=...
  → done 后填充 result
```

### 9.4 语音对话

```text
UI 按住/点击录音 → AudioCoordinator.record()
  → 停止 → 文件 m4a
  → POST /asr（audio, language=en）→ text
  → POST /chat/sessions/:id/turn（multipart：text 必填 + audio）
  ← reply / correction / suggested_replies / done（只有助手文本，无 TTS 音频）
  → POST /tts（text=reply, format=mp3）→ 下载 → AVPlayer
  → 后台：每 2s GET /chat/sessions/:id/messages，等该轮助手消息出现 pron
       → 成人补显示发音小分；儿童只用于鼓励/提示，不显示数字
```

> `pron` **不在** `/turn` 响应，也**不在** `/sessions/:id` 里；只有 `/sessions/:id/messages` 的助手消息带 `pron`。评分是 `after()` 里的异步任务，可能晚几秒，轮询 3–5 次仍为空就放弃（不阻塞对话）。
>
> 若后端未来把 ASR/TTS 收进 `/turn`，只需改 `ChatService.turnByVoice()` 的内部实现，VM/UI 不变。这是分层的主要收益。

---

## 10. 日志与可观测性

- `hilog` domain 固定 `0xEC00`；tag：`Net`、`Audio`、`VM`、`Nav`。
- 每次请求生成 `requestId`（8 位随机），日志格式：`requestId method path status code elapsedMs`。
- 不打印：access/refresh token、邮箱、录音路径、ASR 文本、LLM 回复全文。
- 错误上报只走本地日志（无三方 SDK）；debug 包可在设置页导出最近 500 行日志（脱敏后）。
- 关键指标（本地计数，不上传）：录音时长分布、上传成功率、TTS 首播耗时、轮询完成率。

---

## 11. 测试策略

| 层 | 方式 | 说明 |
|---|---|---|
| DTO/映射 | 单测 | 固定 JSON → DTO → UiError |
| Service | 单测 + FakeHttpClient | 断言 URL/字段/重试次数 |
| VM | 单测 | Fake Service，覆盖 loading/error/empty |
| 页面 | 真机手工 + 可选 UI 测试 | 录音/播放无法在模拟器可靠验证 |
| 媒体 | 真机矩阵 | 至少 2 台设备、有线/蓝牙耳机各一次 |
| 弱网 | 真机限速/断网 | 上传中断、轮询恢复、重复点击 |

Fake 示例：

```ts
export class FakeHttpClient implements HttpClient {
  responses: Map<string, ApiResponse<Object>> = new Map();
  calls: ApiRequest[] = [];
  async request<T>(req: ApiRequest): Promise<ApiResponse<T>> { /* ... */ }
}
```

> 不声称“已在某机型验证”；所有真机结论记录到 `docs/roadmap.md` 的验收记录或 issue。

---

## 12. 与服务端的边界

- 客户端**只**访问 web `/api/*`；不访问 voice `:8100`，不访问 SQLite，不读写 NAS 文件。
- 所有评分、纠错、改写、TTS、OCR 都在服务端；客户端不内置模型/词典。
- 服务端是唯一事实源；客户端缓存只用于体验，冲突时以服务端为准。
- 服务端新增字段：客户端 DTO 必须容忍未知字段（只取自己需要的），不因新增字段崩溃。
- 服务端删除/改名字段：属于破坏性变更，需要契约版本升级；客户端在 `commons/model` 集中适配。

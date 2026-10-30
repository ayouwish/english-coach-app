# commons/（HAR）· 公共能力

跨 feature 复用的基础设施与设计系统；**禁止依赖 entry/features**。

| 模块 | 职责 | 关键文件（M0 创建） |
|---|---|---|
| `net` | 唯一 HTTP 出口、Cookie 会话、multipart、下载、错误归一化 | `client/HttpClient.ets`、`session/CookieSession.ets`、`error/ApiError.ets`、`dto/*` |
| `audio` | AVRecorder/AVPlayer 封装、音频协调器、权限 | `record/RecorderService.ets`、`play/PlayerService.ets`、`coordinator/AudioCoordinator.ets` |
| `storage` | Asset token、Preferences、文件缓存/LRU | `secure/SecureStore.ets`、`prefs/PrefStore.ets`、`cache/FileCache.ets` |
| `design` | Design Tokens、通用组件、图表 | `tokens/Colors.ets`、`tokens/Spacing.ets`、`components/EcButton.ets`、`charts/*` |
| `model` | 共享 DTO/领域模型/路由常量/配置 | `dto/*`、`router/Routes.ets`、`config/AppConfig.ets` |
| `util` | 时间/格式化/重试/日志脱敏 | `TimeUtil.ets`、`Retry.ets`、`Redact.ets` |

## 依赖规则

```text
commons/net     ──► commons/model, commons/util
commons/audio   ──► commons/model, commons/storage, commons/util
commons/storage ──► commons/model, commons/util
commons/design  ──► commons/model（仅类型）, commons/util
commons/model   ──► 无（最底层）
commons/util    ──► 无
```

- 不 import `@kit.*` 之外的第三方库。
- `net` 不感知页面/路由；不弹 Toast。
- `audio` 不感知业务；只接受“录音/播放/停止”指令，通过回调返回文件/状态。
- `design` 不依赖业务 DTO（图表最多接受通用数值数组）。

## 关键接口

```ts
// net
request<T>(req: ApiRequest): Promise<ApiResponse<T>>
upload<T>(path: string, parts: http.MultiFormData[], fields: Record<string,string>): Promise<T>
download(path: string, destPath: string): Promise<void>

// audio
startRecording(): Promise<void>
stopRecording(): Promise<RecordingFile>
startPlayback(filePath: string): Promise<void>
stopPlayback(): Promise<void>
stopAll(): Promise<void>

// storage
SecureStore.get/set/remove(alias)
PrefStore.get/set(key, value)
FileCache.get/put/evict()
```

详细设计见 [`../docs/architecture.md`](../docs/architecture.md) 与 [`../docs/audio.md`](../docs/audio.md)。

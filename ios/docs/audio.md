# 音频设计 · 录音 / 播放 / 路由 / 互斥

> 客户端**只负责录音、上传、播放**。ASR、发音评测（PA）、TTS 全部在服务端（`web → voice`）。
> 本文所有参数都是“建议值 + 依据”，落地后必须在真机上按 §10 的矩阵复验。

---

## 1. 职责边界

| 能力 | 归属 | 客户端要做的事 |
| --- | --- | --- |
| 采集语音 | 客户端 | 配置 `AVAudioSession`、`AVAudioRecorder`、电平表、时长统计 |
| 编码 | 客户端（系统编码器） | 输出 m4a/AAC，控制采样率/声道/码率，保证 ≤12MB |
| 语音识别 | **服务端**【已实现·后端现有】 | 跟读/连读走 `/attempts`（服务端内部识别）；**对话轮次由客户端先调 `POST /asr`**，再调 `/chat/.../turn`（turn 不内部做 ASR，也不返回 TTS 音频）|
| 发音评测 | **服务端**【已实现·后端现有】 | 上传音频，展示返回的音素/词/语调/issues/反馈 |
| 语音合成 | **服务端**【已实现·后端现有】 | `POST /tts` 拿字节流，缓存到本地再播放 |
| 播放 | 客户端 | 本地文件播放、后台播放、路由切换、打断 |

**明确不做**：本地 VAD 切句、本地降噪/变速变调、边录边传（流式）、后台录音。

---

## 2. 麦克风权限

### 2.1 Info.plist

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要使用麦克风录制你的朗读。录音会上传到家里的学习服务器，并转发给云端语音服务用于识别和发音评分。</string>
```

> 只说“需要麦克风”会被用户（尤其是家长）拒绝。文案必须回答**为什么**和**传给谁**。
>
> **必须如实**：当前后端 `PROVIDER_MODE=hybrid`，音频会经家里服务器转发给 **Azure**（ASR/发音评测/TTS），**会离开家庭网络**。不得写成“录音只留在家里/不出户”。完全本地需要 `PROVIDER_MODE=local` + 本地模型，当前**未部署**。

### 2.2 请求时机与 API

- **不在启动时请求**。在用户第一次点“开始录音”时，先展示一屏**自研的前置说明**（图标 + 两句文案 + “继续”按钮），再触发系统弹窗。此举能明显提高通过率，也符合“不在冷启动索要权限”的体验要求。
- 最低版本 iOS 26，直接使用 `AVAudioApplication.requestRecordPermission(completionHandler:)`（`AVAudioSession.recordPermission` 已被弃用），**不需要 `#available` 分支**。

```swift
@MainActor
func ensureRecordPermission() async -> PermissionStatus {
    switch AVAudioApplication.shared.recordPermission {   // iOS 26，无需 #available
    case .granted: return .granted
    case .denied:  return .denied
    case .undetermined:
        // 用 continuation 包一层，避免依赖某个系统版本是否提供 async 重载
        let ok: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return ok ? .granted : .denied
    @unknown default: return .denied
    }
}
```

### 2.3 被拒后的引导（必须实现，不能只是弹个 Alert）

三种状态三种界面：

| 状态 | 界面 | 文案（孩子可读） | 操作 |
| --- | --- | --- | --- |
| `.undetermined` | 前置说明卡 | “读之前需要用到麦克风，录下来的声音只发给家里的学习服务器打分。” | 主按钮“开始录音” → 系统弹窗；次按钮“先听听示范” |
| `.denied` | **权限引导卡（常驻，替换录音按钮区域）** | “麦克风被关掉了，去设置里打开就能录音啦。” 附路径：设置 → English Coach → 麦克风 | 主按钮“去设置”（`UIApplication.openSettingsURLString`）；次按钮“先听示范 / 做盲听题” |
| `.restricted` | 说明卡（不可跳设置） | “这台设备限制了麦克风（家长控制），需要家长处理。” | 仅“返回” |

规则：
- 从设置返回时，在 `scenePhase == .active` 重新读权限（不要缓存），若已授权则**自动把引导卡换成录音按钮**，并保留用户原选中的句子。
- **不得**因为没权限就整页不可用：文本、翻译、示范音（缓存）、诊断、错音本仍可访问。
- 录音中途权限被撤销（极少见，如 MDM 策略变更）：`record()` 抛错 → 转 `denied` 引导卡，并丢弃半截文件。

---

## 3. AVAudioSession 配置

### 3.1 分阶段配置（由 `AudioSessionController`（actor）统一管理）

| 阶段 | category | mode | options | 理由 |
| --- | --- | --- | --- | --- |
| 录音前 | `.playAndRecord` | `.default` | `[.defaultToSpeaker, .allowBluetooth]` | 需要输入；`defaultToSpeaker` 保证外放不是听筒；`.allowBluetooth` 支持蓝牙耳机/HFP 麦克风 |
| 播放中（TTS/示范音） | `.playback` | `.spokenAudio` | `[.allowBluetoothA2DP]` | 输出优先 A2DP，音质好；`.spokenAudio` 适配人声内容；不因静音键静音 |
| 空闲 | 不主动 `setActive(true)` | — | — | 让其他 App 恢复声音；切页/停止后 `setActive(false, options: .notifyOthersOnDeactivation)` |

要点：
- **录音与播放用不同 category**。若一直用 `.playAndRecord + .allowBluetooth`，蓝牙输出会退化为 HFP（8/16kHz，TTS 明显发闷）。切换前必须 `stop()` 播放器。
- 不要用 `.ambient`：会被静音键静音，孩子以为“没声音”。
- 不要用 `.voiceChat`：带 AEC 与窄带处理，TTS 音质差；本 App 不做实时双向通话。
- `mode = .measurement` 会关闭系统音效处理，理论上更适合评测输入，但也会改变输出路由（易走听筒）并可能放大底噪。**本期用 `.default`**；若实测评测分数异常再单独评估（作为 ADR 候选）。
- 采样率：录音前 `setPreferredSampleRate(16_000)`、`setPreferredIOBufferDuration(0.005)`；硬件 IO 采样率可能被系统定在 48kHz，**但 `AVAudioRecorder` 会按 `AVSampleRateKey=16000` 编码输出**。以最终文件的实际参数为准（用 `AVURLAsset` / `afinfo` 复核），不要假设 session 的 `sampleRate` 就是文件采样率。

```swift
// AudioSessionController
func activateForRecording() async throws {
    try session.setCategory(.playAndRecord, mode: .default,
                            options: [.defaultToSpeaker, .allowBluetooth])
    try session.setPreferredSampleRate(16_000)
    try session.setActive(true)
}

func activateForPlayback() async throws {
    try session.setCategory(.playback, mode: .spokenAudio,
                            options: [.allowBluetoothA2DP])
    try session.setActive(true)
}
```

### 3.2 中断与路由变化

| 通知 | 处理 |
| --- | --- |
| `interruptionNotification .began` | 录音：立即 `stop()`，把本次录音标记为 `.interrupted`，提示“刚刚被打断了，再录一次”；播放：`pause()` 记录位置 |
| `.ended` + `.shouldResume` | 播放：恢复；录音：**不自动续录**（会产生半句，违反“不切碎”原则） |
| `routeChangeNotification .oldDeviceUnavailable` | 播放：暂停（Apple 建议，避免突然外放）；录音：继续（输入切回手机麦克风），仅在 UI 提示“麦克风已切换” |
| `.newDeviceAvailable` | 不自动切换输出，等下一次播放重新路由 |
| `mediaServicesWereResetNotification` | 重建 recorder/player，若在录音中则终止本轮并提示 |
| App 进入后台 | 录音：立即停止并丢弃（不支持后台录音）；播放：继续（`UIBackgroundModes=audio`） |

所有通知在 `AudioSessionController` 内统一注册，**页面不直接监听**，只订阅它暴露的 `AsyncStream<AudioEvent>`。

---

## 4. 录音

### 4.1 参数（唯一推荐配置）

**统一：m4a / AAC-LC、16kHz、单声道、65kbps。** 不设可选码率/采样率分支。

```swift
let settings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,       // m4a 容器 / AAC 编码
    AVSampleRateKey: 16_000,                   // 16kHz：ASR/PA 的常规输入，体积小
    AVNumberOfChannelsKey: 1,                  // 单声道
    AVEncoderBitRateKey: 65_000,               // 65kbps（固定码率）
    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue  // 有码率时基本被忽略，仅作声明
]
// 文件：Caches/Recordings/<uuid>.m4a
```

- **65kbps** 是按每秒 8.125KB 计（65,000 bit/s ÷ 8），1 分钟约 **0.49MB**；12MB 上限约 **24 分钟**。实际时长仍受**服务端 `max_audio_seconds`** 限制（voice 默认 120s，可用 `VOICE_MAX_AUDIO_SECONDS` 配置，**【待确认】**生产取值），客户端另有 60s 硬上限。
- `AVEncoderAudioQualityKey` 对 AAC 在给定 `AVEncoderBitRateKey` 时基本不起作用；填 `.high` 只是表达意图。**不要**靠它调音质，要改就改码率并同步本文。
- 不要用 44.1kHz / 立体声 / PCM/WAV：`44.1k × 2ch × 16bit = 176KB/s`，70 秒就会触顶 12MB，且服务端 ASR/评测不需要。
- **统一参数，不做 A/B 分支**：若真机验证服务端解码异常（`unsupported_audio` 或评分明显异常），先回报现象（设备、系统、文件实际参数、服务端错误码），再单点调整并回写本文；**不要**在客户端预先写“失败就换一套参数”的兜底。

### 4.2 体积核算（12MB 上限）

| 配置 | 码率 | 每秒 | 1 分钟 | 12MB 可容纳 |
| --- | --- | --- | --- | --- |
| **AAC 16kHz mono 65kbps（唯一配置）** | 65 kbps | 8.1 KB | **≈0.49 MB** | **≈24 分钟** |
| AAC 16kHz mono 32kbps（对比参考，不使用） | 32 kbps | 4 KB | 0.24 MB | ≈48 分钟 |
| WAV 16kHz mono 16bit（不使用） | 256 kbps | 32 KB | 1.9 MB | ≈6 分钟 |

结论：65kbps 下 12MB 上限**几乎不可能触发**（约 24 分钟），真正先到的是**服务端时长上限**与客户端 **60s 硬上限**。客户端仍要做提交前体积预检，因为 12MB 是服务端契约，不能靠“应该不会超”。

### 4.3 录音时长与句长

- 单词/短句：建议 UI 提示 1–8 秒；
- **单段硬上限 60s**，最后 10s 显示倒计时并变声/变色提醒，到点自动停止并**自动提交**（不丢用户内容）；
- 最小有效时长 **500ms**：更短则本地拦截，提示“太短了，再说一次”，**不发请求**（省一次评分配额）；
- 全静音检测：`averagePower` 全程低于阈值（如 -45dB）→ 提示“没有听到声音”，允许重录。

### 4.4 绝不切碎（硬性）

服务端 ASR 修过“停顿只识别前半句”的 bug（已改为连续识别）。客户端对应约束：

- 一次“开始→停止”= **一个文件 = 一次上传**；
- 禁止按静音检测自动切段、禁止边录边发、禁止把多句拼成一个文件（连读模式是“一句一文件一请求”，不是“一段多句”）；
- 录音过程中不做本地降噪/压缩/重采样，原样上传；
- 连读模式的“立刻下一句”指的是下一句重新开一个录音文件，**不是**在一个文件里连续说。

### 4.5 计量与波形

```swift
recorder.isMeteringEnabled = true
// 20Hz Timer / AsyncStream
recorder.updateMeters()
let db = recorder.averagePower(forChannel: 0)      // -160...0
let level = max(0, min(1, (db + 50) / 50))         // 映射到 0...1
```

- 电平更新在主线程以 **≤30fps** 刷新（20Hz 采样 + 合帧），波形条 24–32 根；
- **不要**用 `peakPower` 做“爆音”判断以外的用途；
- 波形只做视觉反馈，不做静音切分。

### 4.6 文件生命周期

| 阶段 | 位置 | 清理 |
| --- | --- | --- |
| 录制中 | `Caches/Recordings/<uuid>.m4a.part` → 完成后重命名 | — |
| 上传成功且拿到 `attemptId` | 重命名为 `attempt-<id>.m4a` | 保留 7 天，供“回放我的录音” |
| 上传失败 | 保留 `.pending` 标记 | 用户重试或 24h 后清 |
| 取消/过短/被中断 | 立即删除 | — |

`Caches/` 天然不进 iCloud 备份，避免录音副本被同步到 iCloud；**这不代表录音不离开设备**——录音仍会上传家里服务器并转发云端语音服务（见 §1、§5.1）。

### 4.7 duration_ms

用于服务端校验与统计。取值优先级：

1. 停止后读文件真实时长：`AVURLAsset(url:).load(.duration)`；
2. 兜底：记录 `startedAt`/`stoppedAt` 的单调时钟差。

**不要**直接依赖 `recorder.currentTime`（`stop()` 之后的行为跨版本不一致，属**【待实测】**）。

---

## 5. 上传

### 5.1 请求

```
POST {base}/attempts          multipart/form-data
  audio=@attempt.m4a (Content-Type: audio/mp4)
  sentence_id=123
  reference_text=...
  mode=scripted
  duration_ms=4200
```

- 字段顺序、文件名、`Content-Type` 必须与真实编码一致（详见 `architecture.md` §4.4）；
- 提交前：`attributesOfItem[.size] <= 12MB`，否则本地拦截并提示；
- 上传进度：≤2MB 用不确定态转圈即可；照片 OCR（可达数 MB）必须显示百分比进度。

> **对话/复述的音频不走 `/attempts`**：对话是 `POST /asr`（multipart `audio`，`language=en`）拿文本 → `POST /chat/sessions/:id/turn`（multipart，**`text` 必填** + `audio`）→ `POST /tts` 播回复；复述是 `POST /asr` → `POST /story/retell`。详见 `screens.md` §5、§6.3。

### 5.2 失败与重试

| 失败 | 处理 |
| --- | --- |
| 网络断开（请求未发出） | 保留文件，按钮变“重新提交”，**不必重录** |
| 请求已发出但超时 | 可能已在服务端评分：先用 `/attempts/status` 查（若拿到 id 不可能，因为没响应）→ 实际做法：提示“可能已提交，去历史里看看”，避免重复扣配额 |
| `unsupported_audio` | 直接提示重录；若反复出现，作为 bug 上报（附文件名/大小/时长，不附音频） |
| `payload_too_large` | 本地预检本应拦截；说明预检有 bug，记录日志 |
| `provider_timeout` / `provider_unavailable` | **不重录**，提供“重新评测”走 `POST /attempts/:id/retry`（服务端已存音频），或稍后重试 |
| 用户离开页面 | 取消上传（`Task.cancel`），文件保留 |

---

## 6. 播放

### 6.1 播放源

| 源 | 获取方式 | 播放器 |
| --- | --- | --- |
| TTS 示范音 | `POST /tts` → 字节 → 写 `Caches/TTS/<cacheKey>.(mp3\|wav)` | `AVAudioPlayer` |
| 我的录音回放 | 本地文件（刚录完）或 `GET /audio/:id` 下载后缓存 | `AVAudioPlayer` |
| 对话助手回复 | **文本来自 turn 响应**；音频由 `POST /tts {text: reply, format:"mp3"}` 合成后落盘（turn 不返回音频） | 先落盘再 `AVAudioPlayer` |
| 对话开场白 | `POST /chat/sessions` 返回的 `opening_line` 文本 → `POST /tts` | 同上 |

统一约定：**先把音频落到本地文件再播**。原因：`AVAudioPlayer` 需要 URL/Data；落盘后可缓存、可重播、可后台，且避免 Data 常驻内存。

### 6.2 语速

- 慢速 = `POST /tts` 的 `rate=slow`，由服务端合成；
- **不使用** `AVAudioPlayer.rate` 变调变速（会失真、需要 `enableRate`、且与服务端慢速音色不一致）；
- 播放器固定 `rate = 1.0`，`volume = 1.0`（响度交给系统音量键）。

### 6.3 格式

- **示范音默认 `format=wav`**：与参考音分析共用服务端预热缓存，命中时几乎零等待（【已实现·后端现有】，`/api/tts` 默认 `wav`）；
- **对话回复/长文本用 `format=mp3`**：每次都是新文本、必然 cache miss，mp3 体积约 1/3，局域网传输更快；
- `AVAudioPlayer` 对 mp3/wav/m4a 均原生支持，无需转码；
- 24kHz wav 单声道 3 秒 ≈ 144KB，mp3 约 12–20KB；缓存上限 200MB 下足够存上千条。

### 6.4 后台播放与锁屏

- `UIBackgroundModes = [audio]` + 播放阶段 category `.playback`；
- 锁屏/控制中心（M4 可选）：`MPNowPlayingInfoCenter` 展示“正在播放：句子/故事标题”，`MPRemoteCommandCenter` 支持 play/pause/next；
- **只允许播放进后台，不允许录音进后台**。录音时 `scenePhase` 变化立即停止。

### 6.5 路由与耳机/蓝牙

| 场景 | 行为 |
| --- | --- |
| 无外接设备 | `.defaultToSpeaker` → 扬声器（不强制听筒） |
| 插入有线耳机 | 系统自动切；播放继续 |
| 拔耳机（`.oldDeviceUnavailable`） | **暂停**，不自动外放（避免公共场所突然出声） |
| 连接 AirPods | 播放用 A2DP；需要录音时切 `.playAndRecord + .allowBluetooth`（HFP），此时输出音质下降属系统限制，UI 无需解释 |
| 蓝牙已连接但录音无声 | 多为 HFP 输入未就绪：重设 category 后 `setActive(true)` 一次；仍失败则提示“换用手机麦克风” |
| 输出被系统切到听筒 | 播放前 `overrideOutputAudioPort(.speaker)`；录音阶段不要覆盖（会影响 HFP） |

### 6.6 打断策略

- 同一时刻只允许一个播放器实例；新播放请求 = 停止旧的（避免叠音）；
- 进入录音前 `stop()` 播放并等待 `isPlaying == false`（用 delegate 回调或轮询 50ms，最多 300ms），再切 category；
- 与系统音乐共存：**不**使用 `.mixWithOthers`（学习场景要清晰），`setActive(true)` 会打断其他 App 音乐并在结束后 `.notifyOthersOnDeactivation` 恢复；
- 连续播放（连读模式逐句示范、故事朗读）用**预取**：当前句播放时预下载下一句 TTS，衔接空隙 <200ms。

---

## 7. 录音与播放互斥（核心不变量）

**不变量：同一时刻，`AudioCoordinator.mode` 只能是 `idle / recording / playing` 之一；任何切换必须经过协调器，页面禁止直接调用 `AVAudioRecorder.record()` 或 `AVAudioPlayer.play()`。**

```
                 beginRecording()
   idle ─────────────────────────────▶ recording
     ▲                                   │
     │  stopPlayback()/finish            │ finishRecording()
     │                                   ▼
   playing ◀────── play(url) ──────── idle(有文件, 待上传)
```

| 从 → 到 | 必须做的事 |
| --- | --- |
| `playing → recording` | 停止播放 → 等待真正停止 → 切 `.playAndRecord` → `setActive(true)` → `record()` |
| `recording → playing` | 先结束录音（停止并保存）→ 切 `.playback` → 再播 |
| `recording → idle` | 停止、校验时长/静音、生成 `RecordedAudio` |
| `playing → idle` | `stop()` 并（可选）`setActive(false, .notifyOthersOnDeactivation)` |
| 任意 → 中断 | 见 §3.2 |

为什么必须互斥：
1. 边录边放会把 TTS 录进麦克风，造成“自己跟自己说话”的评分灾难；
2. `AVAudioSession` 的 category 切换在录音中途执行会直接中断输入；
3. 蓝牙下同时输入输出会强制 HFP，音质与稳定性双降。

UI 层体现：
- 录音时隐藏/禁用“播放”按钮；
- 播放时录音按钮显示为“停止播放并录音”（一次点击完成两步，而不是让用户点两次）；
- 切换页面时协调器统一 `stopAll()`。

---

## 8. 音频状态机（实现参考）

```swift
@MainActor
final class AudioCoordinator {
    enum Mode: Equatable { case idle, recording, playing }
    private(set) var mode: Mode = .idle
    private(set) var level: Double = 0          // 0...1，供波形

    func beginRecording(maxDuration: TimeInterval) async throws -> RecordingHandle
    func finishRecording() async throws -> RecordedAudio
    func cancelRecording()
    func play(_ source: AudioSource, kind: PlaybackKind) async throws
    func stopPlayback()
    func stopAll()
}
```

- `RecordingHandle` 暴露 `id`、`fileURL`、`startedAt`、`durationMs`（停止后填充）；
- `play` 的 `kind` 决定 category：`.tts`/`.story` 用 `.playback`；`.myRecording` 也用 `.playback`；
- 所有错误映射到 `AudioError`：`permissionDenied / sessionFailed(code) / recorderFailed / tooShort / noSpeech / interrupted / fileTooLarge / playerFailed`，再由 `ErrorMapper` 转文案。

---

## 9. 失败与边缘情况清单

| 情况 | 预期行为 |
| --- | --- |
| 麦克风权限被拒 | §2.3 引导卡；录音区不可用，其余功能可用 |
| 通话/闹钟中断 | 录音中止并标记，提示重录；播放暂停 |
| 拔耳机 | 播放暂停；录音不中断 |
| 切到后台 | 录音停止（丢弃本轮）；播放继续 |
| 磁盘满 | 开始录音前检查可用空间（<50MB 提示清理缓存） |
| 蓝牙麦克风不可用 | 回退手机麦克风 + 提示 |
| 录音时长 0（系统异常） | 视为失败，删除文件，提示重录 |
| 设备静音开关打开 | 播放不受影响（`.playback`）；录音不受影响 |
| 音频被杀进程 | 保留已落盘文件，下次启动清理 `.part` |
| 模拟器 | 麦克风来自 Mac，路由/中断/蓝牙行为不可信 → **验收必须真机** |

---

## 10. 真机验收矩阵（M0 必跑）

| # | 场景 | 期望 |
| --- | --- | --- |
| 1 | 首次进入 → 点录音 → 允许 | 系统弹窗一次，之后直接录音 |
| 2 | 拒绝权限 → 点“去设置”开启 → 返回 | 引导卡自动消失，可直接录音 |
| 3 | 录音 10s → 提交 | 上传 ≤1s，返回评分，回放自己的录音正常 |
| 4 | 播放 TTS 中点录音 | 播放立即停止，录音开始（无叠音） |
| 5 | 录音中插耳机 | 不中断；停止后可正常播放 |
| 6 | 播放中拔耳机 | 立即暂停，不外放 |
| 7 | 录音中来电 | 录音中止，提示重录；通话后播放正常 |
| 8 | AirPods 连接 → 播放 → 录音 | 播放音质正常；录音可用（HFP） |
| 9 | 静音开关打开 | TTS 仍可听见 |
| 10 | 录音 59s / 61s | 60s 自动停止并提交；文件约 0.5MB，远小于 12MB |
| 11 | 蓝牙音箱 + 录音 | 输入回退手机麦克风，提示可见 |
| 12 | 后台播放 TTS 30s | 锁屏继续播放；回前台状态正确 |
| 13 | 16kHz/65kbps m4a（10s、60s）上传 | 服务端解码、ASR、评分均正常，无 `unsupported_audio`；用 `afinfo` 确认文件实际为 16kHz mono AAC |
| 14 | access token 过期时录音提交 | 401 → 单飞刷新 → 自动重放，用户无感；不出现“登录过期”误报 |

# 音频设计 · 录音 / 播放 / 互斥 / 生命周期

> 目标平台：HarmonyOS NEXT / API 12+。
> 所有“可用/支持”结论都必须经过真机验证；本文只给设计约束与参数建议，不冒充验证报告。
> 相关服务端事实：录音上限 **12MB**，服务端 PyAV 解码支持 webm/opus、wav、mp3、**m4a/aac**；ASR 已修复“停顿只识别前半句”，**客户端不要把录音切碎发送**。

---

## 1. 设计原则

1. **一次只做一件事**：录音和播放互斥；任何时刻最多一个录音器、一个播放器。
2. **短、整、清晰**：一次录一整句/一整轮，不做流式切片；0.6–60s。
3. **能听见示范**：麦克风按需开启、录完立即释放，避免占住音频输出。
4. **失败不丢**：录音先落本地，上传失败可重试；不在用户不知情时重复上传。
5. **隐私默认**：不后台录音、不锁屏录音、不上传公共目录、登出清理。

---

## 2. 麦克风权限

### 2.1 声明

`entry/src/main/module.json5`：

```json5
{
  "module": {
    "requestPermissions": [
      {
        "name": "ohos.permission.MICROPHONE",
        "reason": "$string:reason_microphone",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "inuse"
        }
      },
      { "name": "ohos.permission.INTERNET" }
    ]
  }
}
```

- `MICROPHONE` 是 **user_grant**，必须运行时申请。
- `INTERNET` 是系统授予（normal），声明即可，无需弹窗。
- **拍照识别不需要 `CAMERA`**：使用系统 `cameraPicker` 由系统相机完成拍摄，官方说明应用无需申请相机权限。若未来做自绘相机预览，才需要加 `CAMERA`（见 [permissions-and-privacy.md](permissions-and-privacy.md)）。

### 2.2 申请流程

```text
用户点“开始说”
  → checkAccessToken(MICROPHONE)
      ├─ 已授权：直接开录
      └─ 未授权：
           → 先展示应用内说明（为什么需要麦克风；儿童版更短）
           → requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE'])
               ├─ 授权：开录
               └─ 拒绝：显示“需要麦克风才能练习”
                    → 提供“去设置”
                    → requestPermissionOnSetting(context, ['ohos.permission.MICROPHONE'])（API 12+）
```

```ts
// 示意
const atManager = abilityAccessCtrl.createAtManager();
const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
const granted = result.authResults[0] === 0;
```

### 2.3 拒绝处理（必须做）

- 第一次拒绝：不重复弹系统框（系统不会再弹），改为应用内卡片 + “去设置”。
- 用户点“去设置”：优先 `requestPermissionOnSetting`（API 12）；失败则提示手动路径“设置 → 隐私 → 权限管理 → 应用 → 家庭英语教练 → 麦克风”。
- **每次录音前都检查**：用户可能在系统设置里撤销权限；不能只在首次启动检查。
- 儿童模式：说明文案用“要听到你的声音，需要打开麦克风”，不出现“权限”“授权”等术语。
- 录音按钮在无权限时仍可点：点了走申请/引导，而不是直接置灰（否则用户不知道为什么）。

### 2.4 失败原因映射

| 现象 | 可能原因 | 文案 / 动作 |
|---|---|---|
| `requestPermissionsFromUser` 返回非 0 | 用户拒绝 | “需要麦克风才能练习” + 去设置 |
| 创建 AVRecorder 失败 | 系统媒体服务异常 | “录音功能暂时不可用，重启 App 再试” |
| `prepare` 失败 | 参数不支持/文件 fd 无效 | 降级 16k/64k 重试一次；仍失败提示 |
| `start` 失败 | 麦克风被占用（通话/其他录音） | “麦克风被占用了，关掉其他录音 App 再试” |
| 录音中途 error | 设备切换/系统回收 | 停止、保留已录部分？**不保留**，提示重录 |

---

## 3. 录音（AVRecorder）

### 3.1 参数建议

| 参数 | 默认 | 低带宽回退 | 说明 |
|---|---|---|---|
| 容器 | `CFT_MPEG_4A`（m4a） | 同左 | 服务端按 mime/扩展名识别为 m4a |
| 编码 | `AUDIO_AAC` | 同左 | 不用 AMR/MP3，AAC 兼容性与体积更稳 |
| 声道 | **1（单声道）** | 1 | 口语练习不需要立体声；减半体积 |
| 采样率 | **44100 Hz** | **16000 Hz** | 44.1k 保留更多辅音细节，利于 PA；16k 用于弱网 |
| 码率 | **96000 bps** | **64000 bps** | 64–96kbps 足够语音；再高对 ASR/PA 收益很小 |
| AAC profile | 不显式设置（用默认）或 `AAC_LC` | 同左 | 64–96kbps 不适合 HE-AAC；不要依赖 `AAC_HE` |
| 音频源 | `AUDIO_SOURCE_TYPE_MIC` | 同左 | 系统麦克风 |
| 输出 | `fd://<fd>` | 同左 | 本地文件只支持 fd，不支持路径 |

**为什么默认 44.1k 而不是 16k**：

- 服务端内部会统一转 16k 单声道，但 44.1k 源保留了更多高频辅音（/s/、/θ/、/f/），对发音评测更友好。
- 96kbps 下 60s 约 720KB，远低于 12MB 上限；Wi-Fi 家庭网络不是瓶颈。
- 若真机 PA 对 44.1k 支持不佳，或上传明显慢，切 16k/64k；这是**配置项**，不是硬编码。

### 3.2 配置片段（示意）

```ts
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';

const profile: media.AVRecorderProfile = {
  audioBitrate: 96000,
  audioChannels: 1,
  audioCodec: media.CodecMimeType.AUDIO_AAC,
  audioSampleRate: 44100,
  fileFormat: media.ContainerFormatType.CFT_MPEG_4A
  // 不设置 aacProfile，使用系统默认；如需显式：AAC_LC
};

const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
const config: media.AVRecorderConfig = {
  audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
  profile,
  url: 'fd://' + file.fd
};

const recorder = await media.createAVRecorder();
recorder.on('stateChange', (state: media.AVRecorderState) => { /* 更新 UI */ });
recorder.on('error', (err: BusinessError) => { /* 停止 + 清理 */ });
await recorder.prepare(config);
await recorder.start();
```

停止与释放：

```ts
if (recorder.state === 'started' || recorder.state === 'paused') {
  await recorder.stop();
}
await recorder.reset();      // 可选
await recorder.release();    // 必须
fileIo.closeSync(file.fd);   // 必须（也接受 File 对象，按当前 SDK 为准）
```

### 3.3 状态机

```text
idle
 └─ prepare() → prepared
      └─ start() → started
           ├─ pause() → paused
           │    └─ resume() → started
           └─ stop() → stopped
                └─ reset() → idle
                     └─ release() → released
```

- 只在 `prepared` 调 `start()`；只在 `started/paused` 调 `stop()`。
- 任何异常路径都要 `release()` + `close(fd)`；否则 fd 泄漏、文件不完整。
- `release()` 后实例不可复用；下次录音重新 `createAVRecorder()`。
- **不要**在 `stateChange` 回调里做耗时操作；只更新状态机。

### 3.4 录音 UI 与计时

| 项 | 规则 |
|---|---|
| 开始 | 点击“开始说”/按住说话（二选一，全局统一） |
| 准备态 | 显示“麦克风准备中…”；就绪后自动开始，不需要再点一次 |
| 录音态 | 红色脉冲动画 + 计时 `0:03`；按钮变“说完啦” |
| 最短 | 600ms；低于则丢弃并提示（不提交） |
| 最长 | 60s 自动停止并提交；或 12MB 预估到达时提前停 |
| 取消 | 停止 → 删除文件 → 释放 → 不提交 |
| 切后台 | 立即停止 → **丢弃** → 释放；返回时提示“刚才的录音已取消” |
| 来电/音频打断 | 停止 → 丢弃 → 释放；恢复后不自动续录 |

计时用 `Date.now()` 差值即可；`duration_ms` 传实际毫秒数。**不要用文件大小反推时长**。

### 3.5 文件命名与校验

```text
filesDir/recordings/<yyyyMMdd_HHmmss>_<uuid>.m4a     // 当前录音
filesDir/pending/<uuid>.m4a + <uuid>.json            // 待上传
cacheDir/tts/<sha256(text|rate|voice|format)>.<ext>  // TTS 缓存
cacheDir/audio/<attemptOrMessageId>.<ext>            // 回放缓存
```

上传前：

- `fileIo.statSync(path).size > 0` 且 `<= 12 * 1024 * 1024`。
- 时长 `600ms <= duration <= 60000ms`。
- MIME 固定 `audio/mp4`，remote filename `recording.m4a`。
- 如果文件头不是 `ftyp`（可用前 12 字节粗检），提示“录音文件异常，请重录”。

### 3.6 声学注意事项

- **不要切片**：一次录音只上传一个文件；ASR 的连续识别依赖完整语音，切片会重新引入“只识别前半句”。
- 句间静音：开始录音后 200–300ms 再提示用户开口，避免开头吞字；服务端 ASR 对首尾静音有一定容忍，但不要依赖。
- 耳机：有线/蓝牙耳机能显著减少回声；外放时示范音可能被录进去，导致评分异常。UI 提示“建议戴耳机”。
- 距离：建议 20–30cm；儿童可能靠太近，出现喷麦/削波。不要做自动增益（系统可能已有）。
- 噪声：家庭环境噪声大时，服务端可能返回 `low_snr` warning；UI 提示“找个安静一点的地方”。

---

## 4. 播放（AVPlayer）

### 4.1 为什么先下载再播

`GET /api/audio/:id`：

- 需要 Cookie 鉴权；
- 响应头 `accept-ranges: none`；
- 音频可能是 webm/opus（网页端历史录音）或 m4a（移动端新录音）。

因此：

```text
不要：AVPlayer.url = 'https://english.dreamsearch.top/api/audio/xxx'
      （无法带 Cookie；无 Range；可能被 302/401 干扰）

要：  HttpClient.download('/audio/xxx', cachePath)
      → AVPlayer.url = 'fd://' + fd
```

TTS 同理：`POST /api/tts` 返回二进制，写入 `cacheDir/tts/...` 再播。

### 4.2 AVPlayer 片段（示意）

```ts
const player = await media.createAVPlayer();
player.on('stateChange', (state: string) => {
  if (state === 'completed') { /* 播放结束 */ }
});
player.on('error', (err: BusinessError) => { /* 失败 */ });

const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
player.url = 'fd://' + file.fd;          // 先进入 initialized
player.audioRendererInfo = {            // 再设置渲染信息
  usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
  rendererFlags: 0
};
await player.prepare();
await player.play();
// 结束/失败：
await player.release();
fileIo.closeSync(file.fd);
```

要点：

- 本地文件只支持 **fd://**，不支持直接传路径。
- `audioRendererInfo` 的建议值按场景选择；语言学习用 `STREAM_USAGE_MUSIC` 或系统推荐的媒体用途，避免被当成通话音频路由到听筒。具体枚举以 SDK 为准（【待真机验证】）。
- 播放完成/失败/页面销毁都要 `release()` + `close(fd)`。
- 连续播放多段（示范→回放）时，复用同一个 AVPlayer 用 `reset()` 换源，减少创建开销；但**换源前必须 stop/reset**，不要并发。
- 不要设置 `loop=true`（会干扰“播完自动开录”的判断）。

### 4.3 格式支持与降级

官方 Media Kit 文档列出的音频容器：**m4a、aac、mp3、ogg、wav、flac、amr、ape**；本地播放用 fd。据此：

| 来源 | 格式 | 方案 |
|---|---|---|
| 移动端录音上传后回放 | m4a/AAC | AVPlayer 直接播 |
| TTS 示范音 | wav 24kHz / mp3 | AVPlayer 直接播（默认 wav；对话用 mp3） |
| 网页端历史录音 | webm/opus | **AVPlayer 官方列表不含 webm** → 可能播不了 |
| 网页端历史录音 | ogg/opus | 官方列 ogg/VORBIS，opus in ogg 是否支持【待真机验证】 |

降级策略：

1. **m4a/mp3/wav 播放失败**：先重试一次（重新 prepare）；仍失败则提示“声音播放失败”，提供“重新下载”。
2. **wav 失败**：解析 RIFF/PCM 头，用 `AudioRenderer` 直接写 PCM（24kHz、单声道、16-bit）。这是 M4 的兜底，不是 MVP 必需；【待真机验证】。
3. **webm/opus 失败**：不要静默；提示“这条录音是网页格式，当前手机暂不支持播放”。若要支持，需要服务端转码为 m4a【待后端新增】或客户端引入解码器（违反零三方）。
4. **TTS 缓存损坏**：删除缓存文件，重新请求一次；仍失败提示。

### 4.4 TTS 播放策略

| 场景 | format | rate | 缓存 |
|---|---|---|---|
| 跟读示范音 | `wav` | 儿童 `slow`，成人偏好 | 与参考音分析共用服务端缓存，通常秒回 |
| 对话回复 | `mp3` | 偏好/儿童 slow | 新文本必 miss，mp3 体积约 wav 的 1/3 |
| 故事朗读 | `mp3` | 偏好 | 可按句子预取 |
| 错误提示音 | 不新增 | — | 用系统提示，不调 TTS |

- 请求体优先用 POST（文本不进 URL；避免中文/特殊字符编码问题）。
- 响应 `Content-Type` 可能是 `audio/wav` 或 `audio/mpeg`；按 header 决定扩展名，不要按请求参数猜。
- **失败时服务端返回的是 JSON 错误体**（`{error:{code,message}}`），不是音频。客户端必须先看 HTTP 状态与 `Content-Type`，再决定“写文件”还是“解析错误”；不要无条件按 ArrayBuffer 落盘。
- 服务端 TTS 文本上限 2000 字符；客户端按句子拆分，单次不超过 500 字符（对话回复通常很短）。
- **预取**：进入句子后 300–500ms 静默 `POST /api/tts` 预热（或 `/api/warmup`），不播放、不 loading；失败忽略。
- **自动播放**：不要在页面加载时自动播放（可能被系统/用户反感）；“跟我读”是用户手势触发，允许先播示范再开录。

### 4.5 播放 UI 状态

| 状态 | UI |
|---|---|
| idle | “🔊 听示范” |
| loading | “生成中…”（按钮禁用） |
| playing | “播放中…”，可点“停止” |
| completed | 回到“🔊 再听一遍” |
| error | 内联提示 + “重试” |

- 同一时刻只允许一个 TTS/回放播放；点另一段先停当前。
- 播放时录音按钮禁用（或点击时先停播放）；不要出现“边播边录”。
- 音量不强制最大；尊重系统音量/静音。若系统静音，提示“手机静音了”。

---

## 5. 录音与播放互斥

### 5.1 统一协调器

所有录音/播放必须经过 `AudioCoordinator`，页面不得直接 `createAVRecorder`/`createAVPlayer`。

```text
状态：IDLE / RECORDING / PLAYING / RELEASING

事件：
  startRecording()  : PLAYING → stopPlayback() → RECORDING
                      RECORDING → 忽略/报错
  stopRecording()   : RECORDING → 停止/释放 → IDLE
  startPlayback(url): RECORDING → stopRecording(discard=true) → PLAYING
                      PLAYING → stopPlayback() → 新 PLAYING
  stopAll()         : 任意 → 释放全部 → IDLE
```

- 录音时来播放请求：**默认阻止播放**，提示“先说完这一句”；不要偷偷停录音（会丢用户刚说的话）。
- 播放时来录音请求：先停播放，再开录；这是用户明确点“开始说”的意图。
- 页面切后台/销毁：`stopAll()`；录音丢弃，播放停止。

### 5.2 “跟我读”时序

```text
用户点“跟我读”
  → AudioCoordinator.startPlayback(demo)
  → 播放完成（stateChange = completed）
  → release player / close fd
  → 等待 200–300ms（音频路由从播放切回麦克风）
  → AudioCoordinator.startRecording()
  → UI 显示“该你了”
```

不要“播放一开始就开麦”：外放会把示范音录进去，且部分设备切换路由会吞字。

### 5.3 设备切换

- 插入/拔出耳机、蓝牙连接：系统可能重建音频路由；监听 `audioOutputDeviceChangeWithInfo`/音频设备变化（API 11+，【待真机验证】）。
- 录音中设备切换：停止当前录音并提示“设备切换了，请重录”，不要拼接两段不同路由的音频。
- 播放中设备切换：暂停并提示；恢复后从当前位置继续或重播。

---

## 6. 后台、锁屏与打断

### 6.1 明确不支持后台录音

- 录音只在 App 前台、页面可见时进行。
- `onBackground` / `onPageHide`：立即 `stopRecording(discard=true)`，释放麦克风；返回时提示“刚才的录音已取消”。
- 不做常驻通知、不申请 `KEEP_BACKGROUND_RUNNING`、不申请后台任务。
- 理由：儿童隐私、避免“忘记停录”、减少系统限制；跟读/对话都是短交互，不需要后台。

> 如果未来必须支持后台录音（例如家长录长故事），需要：`ohos.permission.KEEP_BACKGROUND_RUNNING` + `backgroundTaskManager.startBackgroundRunning`（类型 `audioRecording`）+ 常驻通知；并重新做隐私评估。**不在 M0–M4 范围**。

### 6.2 播放的后台/锁屏

- 默认：App 切后台/锁屏，播放暂停/停止；不申请后台播放。
- 若未来要让 TTS 在锁屏继续，需要 `AVSession` + 后台任务（`audioPlayback`）+ 通知；复杂度高，M4 再评估。
- 当前行为【待真机验证】：不同机型对 `onBackground` 后 AVPlayer 的处理可能不同；以“切后台即 `stopAll()`”为准，确保一致。

### 6.3 音频打断

- 来电、闹钟、其他 App 播放：监听 `audioInterrupt`（AVPlayer 事件）或系统音频中断回调。
- 处理：
  - `INTERRUPT_HINT_PAUSE`：暂停播放，记录位置；不自动恢复。
  - `INTERRUPT_HINT_STOP`：停止并释放。
  - 录音中被打断：停止录音、丢弃、释放；提示“刚才被电话打断了，再录一次吧”。
- 不在打断后自动重开麦克风（用户可能正在通话）。

---

## 7. 文件与资源清理

| 目录 | 内容 | 清理时机 |
|---|---|---|
| `filesDir/recordings/` | 当前/最近录音 | 上传成功 24h 后；登出立即 |
| `filesDir/pending/` | 待上传 | 上传成功/登出/24h |
| `cacheDir/tts/` | TTS 缓存 | LRU 50MB / 7 天 |
| `cacheDir/audio/` | 回放缓存 | LRU 50MB / 7 天 |
| `cacheDir/tmp/` | `.part` 临时文件 | 启动时清空 |

- 删除文件前先 `close(fd)`；删除失败只记日志，不阻塞 UI。
- 登出：清 `cacheDir/tts`、`cacheDir/audio`、`filesDir/pending`、`filesDir/recordings`；保留 App 配置（baseUrl）。
- 不把录音写入公共媒体库/相册；不需要 `READ_AUDIO`/`WRITE_AUDIO` 权限。

---

## 8. 真机验证清单（待执行）

> 以下是**必须做**的验证项；未执行前不要在文档/汇报里写“已验证”。

- [ ] 44.1kHz/96kbps、16kHz/64kbps 两种参数在目标机型上 `prepare/start/stop` 成功，产出 m4a 可被服务端评测。
- [ ] m4a 文件前 12 字节含 `ftyp`，服务端识别为 `audio/mp4`，时长/大小正确。
- [ ] 录音 60s 自动停止，文件 <12MB；上传成功。
- [ ] 拒绝麦克风后再次点击：不重复弹系统框，能引导到设置；设置授权后返回可录。
- [ ] 录音时播放示范音：被阻止或有明确提示，不出现同时录放。
- [ ] “跟我读”：示范音播完 → 200–300ms → 开录；开头不吞字。
- [ ] 有线耳机、蓝牙耳机、外放三种路由下录音/播放正常；切换设备不崩。
- [ ] 来电/闹钟打断：录音停止且丢弃；播放暂停，不自动恢复。
- [ ] 切后台/锁屏：录音停止；返回提示；无后台常驻。
- [ ] `/api/audio/:id` 下载后 AVPlayer 播放 m4a 成功；webm 历史录音失败时有可读提示。
- [ ] TTS wav（24kHz）与 mp3 都能播；缓存命中时首播 <300ms（目标，实测记录）。
- [ ] 播放失败/文件损坏时不崩溃，能重试/重新下载。
- [ ] 连续录 10 句：无 fd 泄漏、无内存持续增长、无“麦克风被占用”。

---

## 9. 与服务端的接口约定（录音相关）

| 字段 | 值 | 说明 |
|---|---|---|
| `audio` | 文件 | 字段名固定 |
| MIME | `audio/mp4` | 服务端据此存 `.m4a` |
| 文件名 | `recording.m4a` | 仅用于服务端命名 |
| `duration_ms` | 实际毫秒 | 服务端用于统计/兜底 |
| `mode` | `scripted` / `unscripted` | 跟读/自由说 |
| `reference_text` | 句子原文 | scripted 必填 |
| `sentence_id` | 语料 id | 可空（自定义文本） |
| 大小 | ≤12MB | 本地先拦 |
| 切片 | **禁止** | 一次一整段 |

> 服务端 ASR 的“连续识别”修复意味着：**不要为了“实时字幕”把录音每 2s 切一段上传**。如果未来要做实时字幕，需要服务端提供流式 ASR 接口【待后端新增】；当前客户端只做“录完再识别”。

---

## 10. 已知风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 44.1k AAC 在部分设备 PA 支持不佳 | 评分异常/上传失败 | 16k/64k 回退；真机矩阵验证 |
| 蓝牙耳机麦克风采样率低 | 音质差、评分低 | 提示“建议用有线耳机/手机麦克风” |
| 外放回声 | 录到 TTS、评分异常 | 先播后录；提示戴耳机 |
| webm 历史录音无法播 | 家长听不到网页旧录音 | 明确提示；后端转码【待后端新增】 |
| 系统后台策略差异 | 切后台录音未停 | 页面生命周期 + `stopAll()` 双保险 |
| 12MB 上限 | 长录音失败 | 60s 自动停；本地预估大小 |
| 麦克风被占用 | 无法录音 | 捕获错误并提示关闭其他 App |

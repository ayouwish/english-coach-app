# 总设计 · english-coach 原生客户端（iOS / HarmonyOS）

> 目标读者：实现客户端的工程师、需要拍板的产品负责人。
> 标注约定：**【已实现·后端现有】** 可直接调用；**【待后端新增】** 需要先改后端；**【客户端自行实现】** 纯客户端职责。

---

## 1. 产品目标

一个**家庭三到五口人共用**的英语口语教练：孩子跟读/连读/对话/讲故事，家长看诊断与周报。
服务端已运行在家庭 NAS 上，**数据不出户**（除调用云端 AI 的音频/图片/文本）。

移动端要解决的核心场景：

| 场景 | 为什么必须在移动端 |
|---|---|
| 孩子跟读、连读 | 需要随时拿起就练，且**平板/手机的麦克风质量**远好于电脑 |
| 对话训练 | 语音输入 + 即时回复，手机形态最自然 |
| 讲故事（故事模式）| 孩子边说边录，手机最方便 |
| 家长看诊断/周报 | 碎片时间查看 |
| 拍照识别书页 | 手机摄像头是唯一入口 |

---

## 2. 系统架构（客户端视角）

```
┌──────────────────┐
│  iOS / HarmonyOS │
│  （本仓库）       │
└────────┬─────────┘
         │ HTTPS（一个 base URL）
         │ Cookie 会话（首版）
         ▼
┌──────────────────────────────┐
│ web（Next.js, 3000）          │
│  · 账号/会话/SQLite           │
│  · /api/* 业务接口            │
│  · /api/asr|tts|ocr 代理      │
└────────┬─────────────────────┘
         │ 内网 HTTP
         ▼
┌──────────────────────────────┐
│ voice（FastAPI, 8100）        │
│  ASR · 发音评测 · TTS         │
│  LLM（对话/改写/复述）         │
│  OCR（书页） · 文生图          │
└──────────────────────────────┘
```

**关键约束**：客户端只认 **web** 的地址；`voice` 永远不暴露给客户端。
好处：客户端不需要知道 provider 切换、缓存、降级细节；坏处：web 是所有能力的单点（内部已做降级与 `{error:{code,message}}` 统一错误）。

### 2.1 部署形态

- 家庭 NAS，HTTPS（公信证书），**局域网可解析、公网不可达**
- 客户端必须在**同一局域网**使用（或通过 VPN）
- 因此**不需要**考虑弱网重传以外的复杂网络策略，但要处理：Wi-Fi 切换、NAS 重启、证书信任

---

## 3. 认证与会话

### 3.1 现状（后端已有 / 待新增）

| 能力 | 状态 |
|---|---|
| `POST /api/auth/login` → **Cookie 会话**（Web 端在用）| ✅ 已实现 |
| `POST /api/auth/token` → `{access_token, refresh_token}` | **【待后端新增】P0，阻塞 M0** |
| `POST /api/auth/refresh`（轮换）| **【待后端新增】** |
| `POST /api/auth/revoke` | **【待后端新增】** |
| `GET /api/auth/me` | ✅ 已实现（两种凭据都能识别）|

### 3.2 客户端策略：**Bearer Token**（ADR-0002，取代 ADR-0001）

用户已决定**直接上 Bearer Token**，移动端不使用 Cookie：

```
登录 → POST /api/auth/token → {access_token(1h), refresh_token(30d), user}
每个请求 → Authorization: Bearer <access_token>
401（access 过期）→ POST /api/auth/refresh（单飞，一次）→ 重放原请求
refresh 也失败 → 清 token → 跳登录
退出 → POST /api/auth/revoke + 清本地
```
**存储**：`access_token` / `refresh_token` 存 Keychain（iOS）或 Asset Store Kit（鸿蒙），**不写日志**。
**实现要求**：网络层必须做「单飞刷新」（并发 401 只 refresh 一次，其余等待后重放），否则会出现 token 轮换竞争导致掉登录。

> 后端保留 Cookie 模式给 Web；两种凭据解析必须落到同一 `userId`，禁止出现权限分叉。

### 3.3 账号体系（后端已有）

- 家长可在 `/parent` 创建多个成员，**每个成员独立 CEFR 水平（A1–C1）**
- 角色差异：`parent` 可看诊断/周报/家庭成员/建议；`child` 只能练习
- 客户端按 `role` 决定导航与文案（儿童模式：大按钮、无 IPA、不显示低分）

---

## 4. 音频链路（最容易出错的部分）

### 4.1 录音

| 项 | 值（已定） | 说明 |
|---|---|---|
| 容器/编码 | **m4a / AAC-LC** | iOS/鸿蒙原生支持，服务端 PyAV 可解 |
| 采样率 | **16 kHz** | 够 ASR/PA 用，体积小 |
| 声道 | **单声道** | 服务端只处理单声道逻辑 |
| 码率 | **65 kbps** | ≈ 0.49 MB/分钟；12 MB 上限约 24 分钟（仍受服务端时长上限约束）|
| 最长时长 | 服务端有 `max_audio_seconds` 限制 | 超时会被截断/拒绝 |

> 统一参数（两端一致），避免"某端能上传、另一端失败"。若真机验证服务端解码异常，再单点调整并回写本文。

**硬性约束**：单次上传 ≤ **12MB**；**不要**把一句话切成多段发送（服务端 ASR 已修复"停顿丢后半句"，整段发送才能正确识别）。

### 4.2 语音识别与评测（服务端）

- 跟读/连读：`POST /api/attempts`（同步）或 `POST /api/attempts/async`（异步，连读用）
- 自由说/对话：`POST /api/chat/sessions/:id/turn`（内部 ASR → LLM → TTS）
- 中文语音（讲故事输入）：`POST /api/asr`，`language=zh-CN`

### 4.3 播放

- 示范音：`POST /api/tts`（`format=wav` 默认，`mp3` 更小）
- 对话助手回复：随 turn 接口返回音频
- 录音回放：`GET /api/audio/:id`
- **互斥规则**：开始录音前必须停止播放（否则蓝牙设备会切到通话模式导致"声音变闷"）

### 4.4 权限

- iOS：`NSMicrophoneUsageDescription`；拍照识别需 `NSCameraUsageDescription` + `NSPhotoLibraryUsageDescription`
- 鸿蒙：`ohos.permission.MICROPHONE`；相机 `ohos.permission.CAMERA`
- **被拒绝时**：给出可操作引导（设置 → 权限 → 打开），不要让按钮"点了没反应"

---

## 5. 关键业务流程（客户端要实现的）

### 5.1 跟读练习

```
选句 → 播放示范（可选「跟我读」：播完自动开录）→ 录音 → 上传评测 → 展示
  · 音素级热力图（按 capabilities.phoneme_level 自适应）
  · 词级条长编码（不靠颜色区分）
  · 语调曲线（null 轴不画成 0）
  · 鼓励语（按分数分档，中英双语 TTS）
  · 重试评测（不重录）/ 下一句
```
详见后端 `docs/api-contract.md` §3（pronounce）与 web 的 `check-practice-ui` 断言（可当作 UI 验收清单）。

### 5.2 连读模式（异步）

```
选 5 句（或自己贴文本/拍照识别）→ 屏幕逐句大字
  → 每句录完立即 POST /api/attempts/async → 立刻下一句（不等评分）
  → 右侧列表每 1.2s 轮询 /api/attempts/status?ids=… 显示 待评分→评分中→分数
  → 全部读完：汇总（平均分、最差 2–3 句）+ 鼓励语
```
注意：**不要阻塞 UI**；轮询用 1–2s；离开页面时保留已提交任务的轮询列表（或下次进入补拉）。

### 5.3 对话训练（只有语音）

```
场景列表 → 开 session → 每轮（**三步，后端没有一体化接口**）：
  1) 录音 → `POST /api/asr` 得到文本
  2) `POST /api/chat/sessions/:id/turn`（multipart：**text 必填** + audio 可选）→ 返回**助手文本**（不返回 TTS 音频）
  3) `POST /api/tts` 播放助手回复
  · 提示句（点一下 = 自动开始录音，**不发文字**）
  · 无文字输入框（产品决定，练口语）
  · 后台发音评估：turn 接口用 `audio` 在 `after()` 里跑 unscripted 评测【已实现】，
    结果由 `GET /api/chat/sessions/:id/messages` 返回 `pron`（**不是** `/sessions/:id`）；
    前端发完一轮后轮询几次补上；家长看分数、儿童只看鼓励
```

### 5.4 故事模式（核心差异化）

```
中文输入（文字 or 🎤 说中文 → /api/asr?language=zh-CN）
  → POST /api/story/rewrite（按账号 CEFR 改写，A1–C1）
  → 对照预览（可编辑）→ 保存（kind=story）
  → 连读（异步评分）→ 鼓励语
  → 复述：录音 → ASR → POST /api/story/retell（覆盖度，不评发音分）
  → 插画：POST /api/story/:id/illustrate（智谱，每天一张）
  → 故事集：按日期分组、连续天数、录音回放、只看我的
```

### 5.5 盲测 / 诊断 / 家长面板

- 盲测：`POST /api/attempts/async` 带 `blind_test_id`，结束 `POST /api/blind-tests/:id/finish`（只统计已评分）
- 诊断：`GET /api/diagnosis`（最弱音素、掌握度、建议）
- 家长：`GET /api/parent/summary`、`GET /api/family/members`

---

## 6. 错误处理（统一策略）

后端统一返回 `{error:{code,message}}`。客户端**必须**：

1. 把 `code` 映射成稳定行为（见下表），`message` 直接展示给成人；儿童模式用更柔和的替代表述
2. **禁止静默失败**（这是本项目的硬规矩）：任何网络/服务错误都要有可见提示 + 可重试
3. 网络层统一超时（建议：普通请求 30s；评测/改写/出图 60–120s）

| code | HTTP | 客户端行为 |
|---|---|---|
| `bad_request` | 400 | 展示 message（多半是参数问题，属 bug） |
| `unsupported_audio` | 400/422 | 「录音格式不支持，请重试」→ 重新录音 |
| `audio_too_long` / `payload_too_large` | 413 | 「录太长了」→ 提示缩短 |
| `provider_unavailable` | 503 | 「服务暂时不可用（可能未配置）」+ 重试；**不要**把 mock 结果当真实结果展示 |
| `provider_error` / `provider_timeout` | 502/504 | 「服务忙，稍后重试」 |
| `audio_not_found` | 404 | 回放失败 → 隐藏播放器 |
| `internal_error` | 500 | 通用错误 + 重试 |
| 401 | 401 | 会话失效 → 跳登录 |

**降级语义（重要）**：服务端在 AI provider 不可用时会返回 503，**不会**返回假的合成音/假分数。客户端不要把失败当成功展示。

---

## 7. 离线与缓存

| 数据 | 策略 |
|---|---|
| 语料（600 句）| 启动时全量拉取 + 本地缓存（JSON/SQLite），离线可浏览 |
| 示范音（TTS）| 按 `(text,rate,voice)` 缓存到沙盒/应用缓存目录，LRU（建议 200MB）|
| 录音 | 上传成功后本地保留最近 N 条（默认 20）用于回放，其余删除 |
| 评测结果 | 本地缓存最近 50 条，离线查看 |
| 提交队列 | 上传失败进队列，恢复网络后重试（**幂等**：服务端以 attempt id 去重；客户端记录本地 uuid）|
| 图片（书页/插画）| 缓存到磁盘，`ETag`/`Last-Modified` 优先 |

**不做**：离线评测（服务端能力）、离线 LLM。

---

## 8. 安全与隐私

- 全链路 HTTPS；**证书必须被设备信任**（家庭自签场景需安装根证书，公信证书则无需）
- 会话 Cookie/Token 存 **Keychain（iOS）/ Asset Store（鸿蒙）**，不写日志
- **录音/照片会离开家庭网络**：当前部署 `PROVIDER_MODE=hybrid`，音频会发给 **Azure**（ASR/发音评测/TTS），
  文本会发给 **DeepSeek**（对话/改写/复述），书页照片与插画提示会发给 **DeepSeek/智谱**。
  服务端**不在云端留存**这些内容（只在本机缓存），但**必须如实告知家人**，不能宣称"录音不出户"。
  · 若要求完全本地：需 `PROVIDER_MODE=local` 且本地模型（faster-whisper/piper/本地 LLM）就绪——目前**未部署**
- 日志里**禁止**出现：Cookie、Token、音频 base64、完整错误堆栈给用户看
- 家长面板与"提建议"仅 `parent` 可见；儿童账号隐藏
- 截图/后台切换：iOS 可选模糊处理（孩子录音界面）

---

## 9. 双端一致性

- **同一套设计令牌**（`docs/design-tokens.md`）
- **同一套接口与错误映射**（本文第 6 节）
- **同一套页面清单**（`docs/screens-matrix.md`）
- 允许平台差异：导航形态（iOS Tab Bar / 鸿蒙 Navigation）、手势、字体（系统字体）

---

## 10. 里程碑

| 里程碑 | 内容 | 验收 |
|---|---|---|
| **M0** | **Bearer Token 登录/刷新/吊销**、语料列表、跟读评测、示范音播放 | 杀掉重开仍登录；access 过期能自动刷新；退出后 token 失效 |
| **M1** | 连读（异步+轮询）、对话训练（语音）、鼓励语 | 连读 5 句不停顿；对话 3 轮不卡 |
| **M2** | 故事模式（中文语音/文字→改写→连读→复述）、插画 | 讲一个今天的事，得到英文+插画+复述反馈 |
| **M3** | 盲测、诊断、家长面板、家庭成员管理、建议 | 家长能看趋势、建账号、看建议 |
| **M4** | 离线缓存打磨、推送（可选）、iPad/平板适配、无障碍 | 断网可浏览语料；字号/对比度达标 |

---

## 11. 风险清单

| 风险 | 影响 | 缓解 |
|---|---|---|
| 家庭 NAS 只有局域网可达 | 出门用不了 | 文档明确"家用局域网 App"；可选 Tailscale/WireGuard |
| 服务端 AI provider 出错 | 功能不可用 | 客户端展示 503 可读提示；不伪造结果 |
| 录音格式不兼容 | 评测失败 | 首版固定 m4a/AAC 16kHz 单声道；真机验证 |
| 蓝牙设备切换模式导致"声音变闷" | 误判为软件 bug | 录音前停播；文档写入 FAQ |
| Token 轮换竞争（并发 401 各自 refresh）| 掉登录 | 网络层**单飞刷新**（见 §3.2）；服务端 refresh 一次性轮换 + 宽限处理 |
| Token 泄漏 = 账号被盗 | 安全 | access 短（1h）、refresh 轮换、可吊销；存 Keychain/Asset Store |
| 儿童误触/退出 | 体验断裂 | 儿童模式大按钮、关键操作二次确认 |

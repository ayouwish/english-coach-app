# english-coach-app · 家庭英语教练 · 原生客户端

iOS、Android 与 HarmonyOS（鸿蒙）客户端。**与后端仓库 [`english-coach`](../english-coach) 分离**——本仓库只放客户端工程与设计文档。

> **当前状态（2026-11-04）**
> - 后端：**功能完整、已部署**（家庭 NAS，局域网 HTTPS），接口契约 `v1.17`
> - iOS：M0 代码骨架已落地（需 macOS/Xcode 编译验证）
> - **Android：Kotlin + Jetpack Compose 首版工程已落地**（`android/`，minSdk 26 / targetSdk 35），
>   功能清单见 [`docs/android-feature-list.md`](docs/android-feature-list.md)，工程约定见
>   [`android/CONTRACT.md`](android/CONTRACT.md) + [`android/ROUND2_CONTRACT.md`](android/ROUND2_CONTRACT.md)，
>   构建说明见 [`android/README.md`](android/README.md)。
>   第二轮已补齐鸿蒙端全部功能缺口，并额外实现离线能力（失败录音补评分队列、TTS/回放 LRU、能力开关、
>   故事本机记录、能力雷达图、全屏结果页）；验收记录见 [`android/QA_ROUND2.md`](android/QA_ROUND2.md)。
>   本机无 Android SDK，**Compose UI 尚未经过编译器验证**，首次构建需在装有 SDK 的机器上收口。
> - 鸿蒙：**功能实现完成并真机跑通** —— 跟读卡片流与结果页（子项分/逐词/语调曲线/进步历史）、
>   连读、对话、故事、诊断、复习、盲测、家长面板、家庭成员、建议箱、虚拟形象、音色、设置；
>   2026-11-03 DevEco 6.1.1 干净构建通过（BUILD SUCCESSFUL）并安装到 MatePad Pro，
>   详见 [`hos/docs/build-verification.md`](hos/docs/build-verification.md) V3。
>   登录后全量接口联调待测试账号（线上种子密码被 `BOOTSTRAP_*` 覆盖）
> - 设计文档：iOS/鸿蒙各 9–11 篇，见 `docs/`、`ios/docs/`、`hos/docs/`

---

## 0.0 文档同步规则（每个新功能必须遵守）

> 目的：**后端功能永远不领先于前端文档**。每次上线新功能，同一次变更里必须更新对应文档，否则客户端会掉队。

动手加功能时按这个清单过一遍（详见 [`docs/feature-index.md`](docs/feature-index.md) §9）：

- [ ] 接口：`english-coach/docs/api-contract.md`；web 层端点 → 本 README §6 + `docs/feature-index.md`
- [ ] 页面/交互：`docs/screens-matrix.md`（含儿童差异）
- [ ] 业务流：`docs/design-overview.md` §5（若新增流程）
- [ ] 迁移：`english-coach/web/migrations/`（幂等）+ 本 README §3.2 迁移清单
- [ ] 配置：`english-coach/deploy/.env.example` + 本 README §3.3 变量表
- [ ] 验收：`english-coach/web/scripts/check-*.mjs` 加断言；必要时 `docs/acceptance-checklist.md`
- [ ] 移动端影响：`ios/docs/*`、`hos/docs/*` 对应页面/接口章节
- [ ] 登记：`docs/feature-index.md` 对应分组（状态 ✅/🔄/📋）
- [ ] **发布记录**：`docs/release-notes.md` 追加一节（功能 + commit + 验证方法），否则用户只能翻 commit list

**功能总索引** → [`docs/feature-index.md`](docs/feature-index.md)（功能 → 接口 → 页面 → 文档 → 状态）

**发布记录（按批次回溯 + 验收步骤）** → [`docs/release-notes.md`](docs/release-notes.md)

---

## 0. 怎么用这份 README

| 你要做什么 | 看哪几节 |
|---|---|
| 验收后端功能 / 了解现在能做什么 | §1 能力全景、§3 部署与自查 |
| 在 **macOS** 上跑 iOS | §4 iOS 开发 |
| 在 **Windows**（或 macOS）上跑鸿蒙 | §5 鸿蒙开发 |
| 写客户端代码 / 对接接口 | §6 API 速查、§2 跨端约定 |
| 联调排错 | §7 联调闭环、§8 已知坑 |
| 规划 M1–M4 | §9 里程碑 + 平台 `docs/roadmap.md` |

---

## 1. 后端能力全景（截至 2026-11-02）

后端两个服务：**web**（Next.js，`:3000`，所有 `/api/*`）+ **voice**（FastAPI，`:8100`，AI 能力）。
**客户端只连 web**，由 web 代理 voice；客户端不持有任何 API Key。

### 1.1 学习功能

| 模块 | 功能 | 关键实现 |
|---|---|---|
| **跟读练习** | 语料跟读、音素级评分、词级反馈、语调曲线、重试评分、示范音/跟我读 | 语料 600 句（A1 100 / A2 200 / B1 200 / B2 100）；`check:practice-ui` 有完整 UI 语义断言可当验收清单 |
| **连读模式** | 5–6 句连读、**异步评分**（提交即走）、汇总、**读完直接「再读一遍」** | `attempts/async` + `status` 轮询；汇总页 `flow-reread`（不刷新不跳转，两轮都入库） |
| **对话训练** | 情景对话（**只有语音输入**）、不限轮数（用户点「结束对话」）、每轮后台发音评估、**整段对话回放**、场景随机变体、自定义场景 | 19 个内置场景 × 3 组变体；成人/儿童场景分离；成人可开「再看小朋友的场景」；`variation` 注入 + 禁止重复提问 + 温度 0.9 |
| **故事模式** | 中文讲述/输入 → 分级英文改写 → 连读 → 复述 → （可选）插画 → 故事集 | A1–C1 改写；**句子数 3–12（儿童默认 5 / 家长默认 8）**；中文录音**先落盘再转录**，失败可重试；故事整段朗读回放 |
| **发音诊断** | 分层诊断：**单句 / 连读这一批 / 最近 7 天 / 全部累计**；对子去重 | `scope=attempt|batch|recent|days|all`；`θ→s` 与 `s→θ` 合并为一条 |
| **盲测周报** | 异步盲测、只统计已评分数 | 待评分条目单独显示，不进统计 |
| **错音本 / 复习** | SRS 卡片 | `/api/review` |
| **家长面板** | 汇总、家庭成员管理（可建多个账号、各自 CEFR 水平）、提建议、导出 | `/api/parent/summary`、`/api/family/members`、`/api/suggestions` |
| **打印** | 单篇故事打印 / **多选故事集打印**（封面+分页，可含中文与书写线）| 页面 `/story/[id]/print`、`/story/print?ids=…` |

### 1.2 账号与设备

| 功能 | 说明 |
|---|---|
| **登录** | Web 用 Cookie；**移动端用 Bearer Token**（`/api/auth/token` + refresh 轮换 + revoke，双模式并存） |
| **多账号** | 家长可创建成员（角色/CEFR 水平/每日时长/密码），每个账号独立数据与偏好 |
| **偏好** | `auto_illustrate`（默认关）、`gender`、`tts_voice`、`story_sentences`、每日时长、自由聊开关 |

### 1.3 AI 能力（全在服务端）

| 能力 | Provider | 说明 |
|---|---|---|
| 英文 ASR / 发音评测 | **Azure** | 连续识别（**已修复"说话停顿只识别前半句"**） |
| 中文 ASR（故事输入）| **智谱 GLM-ASR** | ¥0.06/分钟；**单次仅支持 30s** → 服务端自动 25s 静音切段拼接 |
| TTS | **Azure** | 9 种音色可选（英 5 / 中 4）；24kHz WAV；自动裁剪尾静音 |
| 对话/改写/复述/OCR | **DeepSeek** | 关闭思考模式、截断重试、结构化输出校验 |
| 卡通插画 / 虚拟形象 | **智谱 GLM-Image** | ¥0.1/张；**预置形象库 12 角色 × 5 风格 = 60 张静态图**（无需按次付费） |
| 音频拼接 | 本地 PyAV | `/v1/audio/concat`：多段（webm/wav/mp3/m4a 混格式）→ 一段 16k 单声道 WAV |

### 1.4 隐私与安全边界

- 虚拟形象**不接受照片上传**（`/api/avatar` 的照片路径按策略返回 **403 `policy_disabled`**），改用**预置形象选择题**
- 插画生成只把**文字提示词**发给图像服务；提示词带**用户性别**（`a girl about 8 …`），明确禁止写实人脸
- 音频会离开家庭网络：ASR/评测/TTS 走 Azure、中文 ASR 走智谱、文本走 DeepSeek —— **UI 文案不得宣称"录音不出户"**
- 家长面板/诊断分数**仅家长可见**；儿童页面零 IPA、不显示低分

---

## 2. 跨端统一约定（客户端必须遵守）

### 2.1 认证（Bearer Token，ADR-0002）

```
POST /api/auth/token  {email,password} → {access_token, refresh_token, token_type:"Bearer", expires_in:3600, refresh_expires_in:2592000, user}
POST /api/auth/refresh {refresh_token} → 新一对（**一次性轮换**，旧 refresh 立即失效）
POST /api/auth/revoke  {refresh_token} → 204
```
- 所有接口：`Authorization: Bearer <access_token>`
- **必须做「单飞刷新」**：并发 401 只发一次 refresh，其余等待后重放；否则轮换会让后到的请求拿着失效 refresh 400 → 掉登录
- access 过期 → refresh 一次 → 仍失败才清 token 跳登录；**网络错误不要清 token**
- Token 存 **Keychain（iOS）/ Asset Store Kit（鸿蒙）**，不写日志
- Web 端继续用 Cookie，**两套凭据落到同一个 userId**

### 2.2 音频

| 项 | 值 |
|---|---|
| 录音格式 | **m4a / AAC-LC** |
| 采样率 / 声道 / 码率 | **16 kHz / 单声道 / 65 kbps** |
| 单次上限 | 12 MB（故事录音上传上限 25 MB） |
| 铁律 | **整段上传，不要按停顿切碎**（服务端已做连续识别） |
| 播放 | TTS 返回 `audio/wav`（或 mp3）；录音回放 `/api/audio/<id>`；**录音前必须停止播放**（否则蓝牙切 HFP 会"声音变闷"） |
| 长时间录音 | `VOICE_MAX_AUDIO_SECONDS` 默认 120s，故事等长录音建议服务端调到 **300** |

### 2.3 错误处理

服务端统一 `{error:{code,message}}`。客户端**禁止静默失败**，必须显示可读文案 + 重试。

| code | 含义 / 客户端动作 |
|---|---|
| `provider_unavailable`(503) | AI 服务未配置/不可用 → 可读提示 + 重试；**不要把 mock 当真实结果** |
| `provider_error`(502) / `provider_timeout`(504) | 服务重试后仍失败 → 提示稍后再试 |
| `unsupported_audio`(400/422) | 录音格式不支持 → 重录 |
| `payload_too_large`(413) / `audio_too_long`(413) | 录音太长/太大 → 缩短 |
| `policy_disabled`(403) | 按隐私策略关闭（如照片生成形象）→ 引导用预置形象 |
| `content_unsafe`(400) | 内容审核不放行 → 换个说法 |
| `audio_not_found`(404) | 回放失败 → 隐藏播放器 |
| 401 | 会话失效 → 单飞刷新 → 失败跳登录 |
| 403 | 权限不足（如儿童访问家长接口）|

### 2.4 能力开关（`GET /api/health`）

**web** 返回 `features`：
```json
{"chat_unlimited_turns":true,"chat_audio_replay":true,"chat_scenarios_audience":true,
 "avatar_presets":true,"story_mode":true,"async_scoring":true}
```
**voice** 返回 `capabilities`：
```json
{"audio_concat":true,"chat_done_turn_index":0,"asr_providers":["azure","zhipu"],
 "asr_effective":{"zh":"zhipu","en":"azure"},"avatar_presets":true,
 "image":true,"ocr":true,"features":["asr","pronounce","tts","audio/concat","ocr","story/rewrite",...]}
```
- 客户端应据此**隐藏/禁用不可用入口**（如 `image=false` 时隐藏插画按钮）
- 部署排查：`curl -s http://<nas>:8100/v1/health | grep -o '"audio_concat":true'`

---

## 3. 后端部署与自查（NAS）

### 3.1 更新

```bash
cd /vol1/1000/project/english-coach && git pull
cd deploy
docker compose build voice web
docker compose up -d --force-recreate voice web      # 必须 force-recreate，否则旧进程/旧镜像残留
docker compose logs --tail=40 web                    # 看迁移 0001–0017
```

### 3.2 迁移（自动执行，幂等）

`0001` 初始化 → `0005` 建议 → `0006` 异步评分 → `0007` 读书材料 → `0008` 故事/书页 kind →
`0009` 故事 P1–P3 → `0010` 对话发音 → `0011` Bearer Token → `0012` 虚拟形象 → `0013` 预置形象 →
`0014` 偏好/性别 → `0015` 故事录音 → `0016` 场景变体/自定义场景 → `0017` 故事句子数

升级前建议备份：
```bash
docker compose exec -T web node -e 'const D=require("better-sqlite3");new D("/data/app.db").exec("VACUUM INTO \"/data/backup-"+Date.now()+".db\"")'
```

### 3.3 `.env` 关键变量（deploy/.env）

| 变量 | 默认 | 说明 |
|---|---|---|
| `PROVIDER_MODE` | `hybrid` | `hybrid`=云端为主、本地兜底；`mock` 不花钱；`local` 纯本地（需模型） |
| `AZURE_SPEECH_KEY` / `AZURE_SPEECH_REGION` | — | 英文 ASR/PA/TTS |
| `LLM_BASE_URL` / `LLM_API_KEY` / `LLM_MODEL` | — | DeepSeek（对话/改写/复述/OCR 视觉） |
| `ASR_PROVIDER` | `auto` | `auto`=中文走智谱、英文走 Azure；也可 `azure`/`zhipu` |
| `ZHIPU_ASR_API_KEY` | 回退 `IMAGE_API_KEY` | 智谱 GLM-ASR |
| `ZHIPU_ASR_MODEL` / `ZHIPU_ASR_CHUNK_SECONDS` | `glm-asr-2512` / `25` | 单次 30s 限制 → 25s 切段 |
| `IMAGE_PROVIDER` / `IMAGE_API_KEY` / `IMAGE_MODEL` | `none` / — / `glm-image` | 卡通插画 + 预置形象生成 |
| `IMAGE_AVATAR_PHOTO` | `0` | 照片生成形象（默认关，隐私策略） |
| `CHAT_DONE_TURN_INDEX` | `0` | `0`=对话不因轮数结束 |
| `DIALOGUE_TEMPERATURE` | `0.9` | 仅对话 |
| `VOICE_MAX_AUDIO_SECONDS` | `120` | 建议故事场景调到 `300` |
| `AUTH_ACCESS_TTL_S` / `AUTH_REFRESH_TTL_S` | `3600` / `2592000` | Token 有效期 |

一次性操作（可选）：生成 60 张真实预置卡通图（约 ¥6）
```bash
docker compose run --rm -v "$PWD/../web/public/avatars/presets:/out" \
  voice python scripts/gen_avatar_presets.py --provider zhipu --out-dir /out --force
docker compose build web && docker compose up -d web
# 试水 4 张（约 ¥0.4）：追加 --characters c1,c3 --styles watercolor,cartoon
```

---

## 4. iOS 开发（macOS）

**要求**：macOS + **Xcode 26**（iOS 26 SDK）+ Homebrew；真机调试需 Apple 付费开发者账号（TestFlight 分发）。

```bash
cd english-coach-app/ios
brew install xcodegen
xcodegen generate          # 生成 EnglishCoach.xcodeproj（不提交）
open EnglishCoach.xcodeproj
```
- 在 Xcode 里选 **Signing Team**（Bundle ID 默认 `top.dreamsearch.english.coach`）
- 登录页服务器地址填：`https://english.dreamsearch.top/api`（只填主机名会自动补 `/api`）
- 局域网自签证书需要在 iPhone 上安装并信任根证书（公信证书则无需）
- 演示账号：`dad@example.com / Dad12345!`（家长）、`girl@example.com / Girl12345!`（儿童）

**M0 已实现**：Token 登录/刷新/吊销、Keychain 存储、单飞刷新、语料列表、示范音播放、录音（16k/65k/单声道）、
上传评测、分数展示（儿童无数字分/IPA）、加载/空/错误状态。

**未验证（第一轮重点）**：编译错误、真机录音格式是否被服务端接受、Keychain 行为、杀进程自动登录、
蓝牙耳机切换、后台/锁屏、证书信任 —— 详见 `ios/README.md` §0「M0 代码现状」与 `ios/docs/open-questions.md`。

---

## 5. 鸿蒙开发（Windows / macOS 均可）

**要求**：DevEco Studio 6.0.0（**API 20 / HarmonyOS NEXT**）+ HarmonyOS NEXT 真机（自动签名需登录华为开发者账号）。

1. DevEco Studio 里 **New Project → Empty Ability**（API 20），生成一个空工程
2. 用本仓库的文件覆盖：`entry/`、`AppScope/`（**保留你新工程里的 `signingConfigs`/签名配置**）
3. Project Structure → Signing Configs → 勾选「自动签名」→ Sync → Build Hap(s) → Run
4. 登录页服务器填 `https://english.dreamsearch.top/api`

**M0 已实现**：Token 登录/单飞刷新（Asset Store Kit 存 token，不可用时降级内存）、语料列表、示范音（下载后 `fd://` 播放）、
录音（AVRecorder，16k/单声道/65kbps m4a）、上传评测、错误映射、页面状态。

**未验证（第一轮重点）**：编译错误、`@kit.*` 导入名与 API 20 实际导出、AVRecorder 参数是否产出 16k/mono/65k、
AVPlayer `fd://` 播放、Asset Store 读写、Navigation 路由 —— 详见 `hos/README.md` §0.1 与 §「待确认 API」表。

### 5.1 Android 开发（Windows / macOS 均可）

**要求**：Android Studio（Ladybug 或更新）+ **JDK 17** + **Android SDK 35**。工程不需要 macOS。

```bash
cd english-coach-app/android
# Android Studio：Open → 选择 android/ 目录 → Sync
# 首次会下载 AGP 8.7.3 / Gradle 8.9 / Compose BOM（约 1–2GB）
# 命令行（本机需先有 Gradle 8.9+ 或让 Studio 生成 wrapper）：
./gradlew :app:assembleDebug
```

- 登录页服务器地址填 `https://english.dreamsearch.top`（只填主机名会自动补 `https://`，误填 `/api` 会被去掉）
- 演示账号：`dad@example.com / Dad12345!`（家长）、`girl@example.com / Girl12345!`（儿童）
- **主流版本策略**：`minSdk 26`（Android 8.0，覆盖 2017 年后所有主流机）/ `targetSdk 35`（Android 15，
  满足 Google Play 现行要求）；不写 API 26 以下的兼容分支
- `android/README.md` 有分层说明、与鸿蒙的功能对齐表、以及本机无 SDK 时的静态校验方式
  （`android/tools/check_android.py`）

---

## 6. API 速查（移动端会用到的全部端点）

> 完整字段以 `english-coach/docs/api-contract.md`（v1.17）为准；这里只列路径与用途。

### 6.1 认证与账号
| 端点 | 用途 |
|---|---|
| `POST /api/auth/token` · `/refresh` · `/revoke` | Token 登录/轮换/吊销 |
| `GET /api/auth/me` | 当前用户（role/cefrLevel/ageBand/avatar） |
| `GET/PATCH /api/settings` | `auto_illustrate` / `gender` / `tts_voice` / `story_sentences` 等偏好 |
| `GET/POST /api/family/members`、`PATCH /[id]`、`POST /[id]/password` | 家庭成员（仅家长） |

### 6.2 跟读 / 连读
| 端点 | 用途 |
|---|---|
| `GET /api/sentences?level=A1` · `GET /api/sentences/[id]` | 语料（600 句） |
| `POST /api/attempts`（multipart audio） | 同步评测（跟读） |
| `POST /api/attempts/async` · `GET /api/attempts/status?ids=` | 异步评测（连读） |
| `POST /api/attempts/[id]/retry` · `GET /api/audio/[id]` | 重试评分 / 录音回放 |
| `GET/PUT /api/practice/cursor?scope=` | **练习游标**（继续上次；按 level/focus 分别记）✅ |
| `GET /api/sentences/[id]/attempts?limit=20` | **单句历史**（进步曲线/回放，仅本人）✅ |

### 6.3 对话
| 端点 | 用途 |
|---|---|
| `GET /api/chat/scenarios[?include_child=1]` | 内置 + 自定义场景（成人默认只看成人） |
| `POST /api/chat/scenarios`、`PATCH/DELETE /[id]` | 自定义场景 CRUD（仅 owner） |
| `POST /api/chat/sessions` | 开会话（**随机抽 variation**，开场白随变体） |
| `POST /api/chat/sessions/[id]/turn`（multipart audio + text） | 一轮对话（ASR→LLM；`audio` 用于后台发音评估；**不返回 TTS 音频**） |
| `GET /api/chat/sessions/[id]/messages` | 轮询消息（含 `correction`、`pron`） |
| `POST /api/chat/sessions/[id]/end` | 结束会话（写评价汇总 + 触发整段回放预生成） |
| `GET /api/chat/sessions/[id]/audio/status` · `/audio[?force=1]` | 整段回放（ready→200 wav / building→202） |
| `GET /api/chat/sessions` · `/[id]` | 历史列表 / 详情 |

### 6.4 故事
| 端点 | 用途 |
|---|---|
| `POST /api/asr?language=zh-CN`（可带 `provider=zhipu|azure`） | 中文语音转文字 |
| `POST /api/story/recordings` | **录音先落盘再转录**（失败仍 201，可重试） |
| `POST /api/story/recordings/[id]/transcribe` | 重试转录（不重录） |
| `GET /api/story/recordings` · `/[id]/audio` | 我的录音列表 / 回放 |
| `POST /api/story/rewrite` | 中文 → 分级英文（`level`、`max_sentences` 3–12） |
| `GET/POST/DELETE /api/materials?kind=story` | 故事集 CRUD |
| `POST /api/story/[id]/illustrate?force=1` | 生成插画（需 `capabilities.image`） |
| `GET /api/story/[id]/audio/status` · `/audio` | **整段朗读回放**（异步预生成） |
| `POST /api/story/retell` | 复述覆盖度（不评发音分） |
| `GET /story/[id]/print[?zh=1&lines=1]` | **单篇打印页**（大字编号句 + 可选中文/书写线，`window.print()`）|
| `GET /story/print?ids=a,b,c[&zh=1&lines=1]` | **多选故事集打印**（封面 + 每篇分页 + 页脚「第 X/N 篇」）|

### 6.5 诊断 / 盲测 / 复习
| 端点 | 用途 |
|---|---|
| `GET /api/diagnosis?scope=…` | `all`（默认）/ `recent&days=7` / `attempt&attempt_id=` / `batch&attempt_ids=` |
| `GET /api/review` | 错音本（SRS） |
| `POST /api/blind-tests`、`POST /[id]/finish`、`GET /api/blind-tests` | 盲测 |

### 6.6 虚拟形象 / 音色 / 其他
| 端点 | 用途 |
|---|---|
| `GET /api/avatar/presets` | 预置形象库（12 角色 × 5 风格，含 `audience`/`gender`/`desc_en`） |
| `GET /api/avatar` · `POST {preset_id,style}` · `PATCH` · `DELETE` | 选择/编辑/清空形象 |
| `GET /api/avatar/image` | 形象图 |
| `GET /api/tts/voices` | 9 种音色 |
| `GET/POST /api/tts` | 示范音（`voice`/`rate`/`format`；不带 voice 回落账号偏好） |
| `POST /api/ocr`（含 HEIC） | 拍照识别书页 |
| `GET /api/parent/summary`、`GET/POST /api/suggestions` | 家长面板 / 提建议 |
| `GET /api/words/[word]` · `GET /api/words?words=a,b,c` | **单词音标**（web 代理 voice `/v1/words/ipa`；LRU 500；未收录 404 `ipa:null`）|
| `GET /v1/words/ipa?word=`（voice，契约 v1.18 §24）| cmudict 126k 词 → IPA；惰性加载 |
| `GET /api/health` | `features` + voice `capabilities` |

---

## 7. 联调最小闭环（建议按此顺序）

1. **登录** → `/api/auth/token` → 有 token
2. `GET /api/auth/me` → 用户信息（`role`/`cefrLevel`/`ageBand`）
3. `GET /api/sentences?level=<cefrLevel>` → 列表
4. `POST /api/tts` → 播放示范音（验证音频播放链路）
5. 录一句 → `POST /api/attempts` → 显示分数（验证录音上传 + 评测）
6. 连读 3 句 → `POST /api/attempts/async` + 轮询 `status`
7. 对话：`GET /api/chat/scenarios` → `POST /api/chat/sessions` → 一轮 `turn`（先 `/api/asr` 再 `turn`）
8. 故事：`POST /api/story/recordings` → `POST /api/story/rewrite` → 保存 `POST /api/materials`
9. 历史：`GET /api/chat/sessions` → 详情 → 整段回放 `audio/status` → `audio`

---

## 8. 已知坑与排查

| 现象 | 原因 / 处理 |
|---|---|
| 登录后所有请求 401 | Token 未带或已过期；确认做了**单飞刷新**；refresh 一次性轮换，并发刷新会互相踢掉 |
| 播放音频没声音/声音变闷 | 录音前没停播放 → 蓝牙切 HFP；先停播再开麦 |
| 「音频拼接服务暂未就绪」 | 先看 `raw:` 日志：**TTS 503**（语音合成不可用）还是 **concat 404**（镜像旧）。`curl /v1/health \| grep audio_concat` 自查 |
| 插画/头像按钮灰或 503 | `capabilities.image=false` → 服务端未配 `IMAGE_PROVIDER`；虚拟形象**不需要** image 能力（预置库静态图） |
| 中文识别差/失败 | 确认 `ASR_PROVIDER=auto` 且 `asr_effective.zh == "zhipu"`；Azure 中文识别本身差 |
| 故事录音很长失败 | 智谱单次 30s → 服务端切段；同时把 `VOICE_MAX_AUDIO_SECONDS` 调到 300 |
| 局域网 HTTPS 连不上 | 自签证书要在设备上安装信任；iOS 需在"关于本机 → 证书信任设置"打开 |
| 儿童账号看到 IPA / 低分 | 客户端用 `user.isChild` 控制；服务端已剥离 IPA，分数仍返回（由 UI 决定是否显示） |
| Web 端"更新了但没生效" | `docker compose up -d --force-recreate`；用 `/api/health.features` 与 `/v1/health.capabilities` 确认版本 |

### 开发机注意事项（本仓库开发过程踩过的坑）

- **`pnpm build` 并发**：同一时刻只允许一个进程 build（并行 build 会写坏 `.next`，表现为 `middleware-manifest.json` 丢失 → `/api/health` 500）
- **守卫会消耗测试账号每日额度**：反复跑 `check:*` 会 429；跑前临时提额、跑后还原（girl 20 / dad 30 / mom 30 分钟）
- **守卫起实例必须 `detached + killTree`**：否则 `next start` 子进程残留占端口，后续守卫会静默跑到旧实例上（假失败）
- **不要在工作区跑 `git checkout .` / `git clean -fd`**：会静默丢掉未提交的工作且不留 reflog 痕迹；要清理用 `git stash push -u`

---

## 9. 里程碑

| 里程碑 | 内容 | 状态 |
|---|---|---|
| **M0** | Token 登录 + 语料列表 + 跟读评测 + 示范音 | 🟡 代码已写，待两端 IDE 编译/真机验证 |
| **M1** | 连读（异步+轮询）、对话训练（语音）、鼓励语 | 📋 设计就绪 |
| **M2** | 故事模式（中文语音→改写→连读→复述）、插画、故事集 | 📋 设计就绪 |
| **M3** | 盲测、诊断、家长面板、家庭成员、建议 | 📋 设计就绪 |
| **M4** | 虚拟形象选择、离线缓存、推送、iPad/平板适配 | 📋 设计就绪 |

平台各自的详细路线与验收标准见 `ios/docs/roadmap.md`、`hos/docs/roadmap.md`。

---

## 10. 文档索引

**跨端（本仓库 `docs/`）**
- `design-overview.md` — 架构 / 认证 / 音频 / 错误 / 离线 / 隐私 / 风险
- `design-tokens.md` — 颜色 / 圆角 / 字号（与 Web 实际 CSS 对齐，跨端唯一权威）
- `screens-matrix.md` — 页面 × 接口 × 儿童/成人差异
- `backend-contract.md` — 移动端所需接口与优先级
- `acceptance-checklist.md` — 真机验收清单（从 Web 守卫提炼）
- `adr/0001-auth-strategy.md`、`adr/0002-bearer-token.md` — 认证决策

**iOS**：`ios/README.md`、`ios/docs/{architecture,audio,screens,design-system,roadmap,open-questions}.md`、`ios/docs/adr/*`

**鸿蒙**：`hos/README.md`、`hos/docs/{architecture,audio,screens,design-system,permissions-and-privacy,roadmap,open-questions}.md`、`hos/docs/adr/*`

**Android**：`android/README.md`（构建/分层/对齐表）、`android/CONTRACT.md`（团队共享契约）、
`docs/android-feature-list.md`（功能总清单 + 与鸿蒙/文档的偏差）、`android/AUDIT.md`（静态审计记录）

**发布记录**：`docs/release-notes.md`（按日期批次：功能 + commit + 怎么验证）

**后端事实来源**：[`english-coach/docs/api-contract.md`](../english-coach/docs/api-contract.md)（v1.18）、
[`english-coach/voice/README.md`](../english-coach/voice/README.md)、[`english-coach/docs/deployment.md`](../english-coach/docs/deployment.md)

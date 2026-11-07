# English Coach · Android 客户端（Kotlin + Jetpack Compose）

家庭英语口语教练的 Android 原生客户端。功能/交互与鸿蒙端（`../hos/`）对齐，架构按 Android 惯用法重写。

- **主流版本策略**：`minSdk 26`（Android 8.0，覆盖 2017 年后所有主流机）/ `targetSdk 35` / `compileSdk 35`
  （Android 15，满足 Google Play 现行要求）。不写 API 26 以下的兼容分支。
- **架构**：单 Activity + Compose + ViewModel/StateFlow + 手写 DI（无 Hilt、无 Fragment、无 Retrofit/Coil）。
- **规模**：115 个 Kotlin 文件 / 约 31.8k 行 / 27 个页面（5 个一级 Tab + 22 个二级页）。
- **功能清单（验收依据）**：[`../docs/android-feature-list.md`](../docs/android-feature-list.md)
- **2026-11 新能力对齐清单（多家庭/成本/插画总开关/盲测取消等）** → [`../docs/new-features-2026-11.md`](../docs/new-features-2026-11.md)
- **团队共享契约**：[`CONTRACT.md`](CONTRACT.md) + [`ROUND2_CONTRACT.md`](ROUND2_CONTRACT.md)
- **质量记录**：[`AUDIT.md`](AUDIT.md)（静态审计）、[`SMOKE_COMPILE.md`](SMOKE_COMPILE.md)（逻辑层冒烟编译）、
  [`QA_ROUND2.md`](QA_ROUND2.md)（第二轮逐项验收）

---

## 1. 环境与构建

| 项 | 要求 |
|---|---|
| IDE | Android Studio（Ladybug / 2024.2 或更新） |
| JDK | **17**（`kotlin.jvmTarget = 17`） |
| Android SDK | **Platform 35** + Build-Tools 35（SDK Manager 安装） |
| Gradle | 8.9（`gradle/wrapper/gradle-wrapper.properties` 已固定） |
| AGP / Kotlin | 8.7.3 / 2.0.21（Compose Compiler 随 Kotlin 2.0 插件，见 `gradle/libs.versions.toml`） |

```bash
# 方式 A（推荐）：Android Studio → Open → 选择 android/ 目录
#   Settings → Build, Execution, Deployment → Build Tools → Gradle
#   → Use Gradle from: "Local installation"，指向本机 Gradle 8.9（或让 IDE 自动下载）
# 方式 B：命令行
gradle wrapper --gradle-version 8.9 --distribution-type bin   # 首次：生成 wrapper jar（本机 Gradle 8.9+）
./gradlew :app:assembleDebug          # 产物 app/build/outputs/apk/debug/app-debug.apk
./gradlew :app:installDebug           # 连真机/模拟器直接安装
```

> **关于 Gradle wrapper**：仓库只提交了 `gradle/wrapper/gradle-wrapper.properties`，
> **未包含 `gradle-wrapper.jar`**（开发机的文件沙箱不允许写二进制文件）。
> 首次构建前执行一次 `gradle wrapper --gradle-version 8.9`（或让 Android Studio 使用本地 Gradle）生成 jar，
> 之后 `./gradlew` 才可用。

### 首次启动配置

1. 服务器地址：登录页「服务器地址」填 `https://english.dreamsearch.top`
   （只填主机名会自动补 `https://`；误填的 `/api` 后缀会被去掉；局域网 HTTP 也可用，会提示明文风险）。
2. 演示账号（见 `AppConfig.demoAccounts`）：
   - 家长：`dad@example.com / Dad12345!`
   - 儿童：`girl@example.com / Girl12345!`
3. 网络：该域名只在家庭网络可达；自签证书需在系统里安装并信任（`network_security_config.xml` 已允许用户 CA）。
4. 录音权限：首次点录音时申请（`RECORD_AUDIO`），不在启动时弹窗；永久拒绝会引导到应用设置页。

---

## 2. 目录结构

```
app/src/main/java/top/dreamsearch/englishcoach/
├── EnglishCoachApp.kt         Application：AppGraph.init
├── MainActivity.kt            单 Activity，setContent { AppRoot() }
├── core/
│   ├── config/AppConfig.kt    baseUrl 规范化、演示账号、CEFR→等级映射、偏好开关
│   ├── di/AppGraph.kt         手写 DI：prefs/config/token/session/8 个 service/audio/capability/voicePrefs/pendingUploads
│   ├── di/VmFactory.kt        vmFactory { }（ViewModelProvider.Factory）
│   ├── error/UiError.kt       UiError + ErrorMapper（成人/儿童两套中文文案）
│   ├── model/UserModels.kt    UserDto/UsageDto/MeResponseDto/TokenResponseDto/LoginResult
│   ├── net/ApiClient.kt       OkHttp 封装：Bearer + 401 单飞刷新 + 重放一次 + 超时分级
│   ├── net/ApiError.kt        ApiError + ApiErrorCode（服务端码 + 客户端本地码）
│   ├── net/Json.kt            EcJson（ignoreUnknownKeys/explicitNulls=false）+ decodeBody
│   ├── net/dto/*.kt           与服务端契约一一对应的 @Serializable DTO（6 个文件）
│   ├── service/*.kt           8 个无状态服务（Auth/Practice/Flow/Chat/Story/Account/Stats/Dictionary）
│   ├── content/CapabilityCache.kt  /health 的 features+capabilities，5 分钟 TTL（image/ocr/avatar_presets…）
│   ├── offline/PendingUploadQueue.kt  失败录音队列（入队/列出/删除/重试，落 filesDir）
│   ├── session/TokenStore.kt  EncryptedSharedPreferences 存 token（失败降级内存，绝不落明文）
│   ├── session/CredentialStore.kt  记住密码（加密；不可用则禁用该功能）
│   ├── session/SessionStore.kt     会话状态 StateFlow + 登录/恢复/登出/用量/错误映射
│   ├── storage/AppPrefs.kt         非敏感偏好
│   ├── storage/CacheStore.kt       录音/TTS/回放/图片/JSON 缓存 + LRU + 最近结果 50 条
│   ├── audio/AudioController.kt    MediaRecorder(16k/mono/AAC/64kbps .m4a) + MediaPlayer
│   ├── audio/VoicePrefs.kt         账号语音偏好本机镜像（示范音/对话朗读立即生效）
│   ├── audio/Voices.kt             内置 9 个音色（线上 /tts/voices 404）
│   └── audio/MicPermission.kt      运行时麦克风权限（含"永久拒绝去设置"）
└── ui/
    ├── AppRoot.kt              启动恢复 / 自动登录 / 登录门禁 / 主题注入
    ├── HomeScreen.kt           5 个 Tab（跟读/连读/对话/故事/我的）+ 语音降级条 + 待补评分横幅
    ├── nav/Routes.kt           路由常量 + Tabs + NavParams + TabNav + Navigator
    ├── nav/AppNavHost.kt       NavHost 接线（首页 + 20 个二级页）
    ├── design/                 DesignTokens（颜色/间距/圆角/字号/分数规则）+ EcTheme + LocalIsChild
    ├── component/              17 个通用组件（按钮/卡片/页脚手架/分数组件/雷达·折线·柱状/录音钮/输入/图片）
    └── page/                   各功能页面 + ViewModel（按 feature 分包）
        ├── auth/               LoginScreen
        ├── practice/           跟读 Tab（Pager 切句 + 页内/全屏结果 + 雷达 + 历史回放）、句子列表
        ├── flow/               连读 Tab、汇总页（含复述入口/批次诊断/待补评分）
        ├── chat/               场景、会话、历史、详情、自定义场景
        ├── story/              故事集（分组/连续天数）、新建（自动插图）、详情（复制全文/整段回放）、复述
        ├── stats/              诊断、错音本、盲测
        ├── account/            我的、设置、家长、家庭成员、建议箱、形象、音色、服务状态
        └── offline/            待补评分录音页
```

---

## 3. 关键实现约定（与鸿蒙端一致的部分）

### 3.1 认证（ADR-0002）

- `POST /api/auth/token` → 存 access/refresh（`EncryptedSharedPreferences`，Keystore AES256-GCM）。
- **单飞刷新**：并发 401 只发一次 `/auth/refresh`，其余请求等锁后复用新 token（`ApiClient.refreshMutex`）；
  refresh 被拒（400/401）才清 token 跳登录；**网络错误/5xx 不清 token**。
- 记住密码默认**不记忆**（开关在登录页）；记忆时用加密存储，存储不可用则明确提示且不降级明文。
- 主动退出后本次进程不自动登录（`CredentialStore.markLoggedOut`）。

### 3.2 音频（docs/audio.md）

| 项 | 值 |
|---|---|
| 录音 | **m4a / AAC-LC / 16 kHz / 单声道 / 64 kbps**（`MediaRecorder`） |
| 时长 | 0.6–60 s（太短本地拦截；停止后立即上传） |
| 铁律 | **整段上传，不按停顿切碎**；**录音前必须停止播放**（`AudioController` 内部保证，避免蓝牙切 HFP 声音变闷） |
| 播放 | TTS 返回 wav/mp3 字节 → 写 `cacheDir` → `MediaPlayer`；录音回放 `/api/audio/:id` |
| TTS 音色 | 9 个内置音色（英 5 / 中 4）+ 账号偏好（`VoicePrefs`）；儿童默认 slow + 童声 |

### 3.3 儿童 vs 成人（docs/screens.md §0）

- 儿童：**不显示 IPA**、**<60 不显示数字**、不用红色低分、按钮 ≥60dp、正文 19sp、文案更短。
- 判定统一 `LocalIsChild.current`（由 `EcTheme` 注入）+ `session.isChild`；
  **渲染层做"低分不显示数字"，不只依赖服务端**（`EcScore.showNumber`）。

### 3.4 错误

- 全部错误 → `ApiError` → `ErrorMapper` → `UiError`（成人/儿童两套中文）；页面用 `ErrorBanner` 展示 + 重试；
  **禁止静默失败**。401 统一走 `SessionStore.toUiError*`，同时 `expire()` 切回登录页。

### 3.5 用到但**线上不存在**的接口（已按鸿蒙端规避，不要"修正"回去）

| 文档里的接口 | 实际 | Android 实现 |
|---|---|---|
| `GET/PUT /api/practice/cursor` | 404 | `AppPrefs` 本地游标（`practice_cursor_<level>`） |
| `GET /api/sentences/:id/attempts` | 404 | `GET /api/attempts?limit=` 本地按 `sentence_id` 过滤 |
| `GET /api/tts/voices` | 404 | 内置 9 音色常量 |
| `POST /api/story/recordings` | 404 | 直接 `POST /api/asr`（zh-CN）+ 本机持久化原声 |

盲测也不是异步：用**同步** `POST /api/attempts`（带 `blind_test_id`，响应不含分数），
进度轮询 `GET /api/blind-tests` 只更新计数，`finish` 后才出分。

### 3.6 离线能力与能力开关（第二轮新增，鸿蒙端没有）

| 能力 | 实现 | 行为 |
|---|---|---|
| **失败录音队列** | `core/offline/PendingUploadQueue` + `Routes.PENDING_UPLOADS` 页 | 跟读/连读提交遇到**网络错误或 5xx**（4xx 业务错误不入队）时把录音拷进 `filesDir/pending_uploads`；首页顶部「有 N 条录音还没评分」、连读汇总「待补评分 N 条」、我的「待补评分录音」三处入口；补评分页可试听/删除/全部重试（`retryAll` 串行，成功后自动出队并刷新用量） |
| **能力开关统一** | `core/content/CapabilityCache`（5 分钟 TTL，失败不抛） | `image=false` → 自动插画开关禁用；`ocr=false` → 连读拍照识别禁用并提示；`avatar_presets=false` → 我的/设置/形象三处入口置灰或显示不可用 |
| **TTS / 回放 LRU** | `CacheStore.trimTtsCache(200MB)` / `trimAudioCache(300MB)` | 启动时按 lastModified 淘汰，避免长用后吃满存储 |
| **最近结果缓存** | `CacheStore.readRecentResult/writeRecentResult` | 最多 50 条，离线可回看最近评测结果 |
| **语音偏好本机镜像** | `core/audio/VoicePrefs` | 设置页 PATCH 成功后写入本机，示范音/对话朗读立刻生效；儿童强制 slow + 童声 |
| **故事本机记录** | `ui/page/story/StoryRuntime` + `CacheStore` JSON | 原声与最近一次复述落盘，杀进程可回看；文件失效只隐藏回放、保留文字 |

---

## 4. 与鸿蒙端的差异（有意为之）

| 差异 | 原因 |
|---|---|
| 跟读详细结果在**页内 + 全屏 overlay**（不新增路由） | Compose 页内状态更自然；功能点不减少（含能力雷达图） |
| 打印 / 导出 Markdown 下载 | Web 专属能力，移动端不实现（故事「复制全文」、建议箱「展示 + 复制」） |
| 照片生成虚拟形象 | 隐私策略关闭（服务端返回 403 `policy_disabled`），不提供入口 |
| 批量 OCR（多选图片）/ 深色模式 / 深链 | 鸿蒙端同样只有单张 OCR；深色模式两端都在 M2+（`EcTheme` 已预留结构） |
| 记住密码默认关闭 | Android 侧更保守（可一键开启，加密存储） |
| 未引入 Hilt / Retrofit / Coil | 手写 DI + OkHttp + kotlinx.serialization，依赖少、离线构建友好；图片用 `RemoteImage` |
| **多做了**：失败录音队列、能力开关、LRU 缓存、故事本机记录、能力雷达图、全屏结果页 | 见 §3.6；用户在第二轮明确要求"不要 demo，要全部实现" |

---

## 5. 验证

本机无 Android SDK，采用四层验证（结果都落在仓库里）：

```bash
cd english-coach-app/android
python tools/check_android.py       # ① 结构：包路径/import/页面签名/括号/依赖白名单
python tools/check_members.py       # ② 成员级：DTO 命名参数 / Service 方法 / Routes·常量 / 枚举值
```

| 层 | 内容 | 结果 |
|---|---|---|
| ① 静态一致性 | 115 个 Kotlin 文件：package↔目录、跨文件 import、27 个页面 composable 签名、括号配平、重复声明、未声明依赖 | ✅ 全部通过 |
| ② 成员级检查 | 232 个 data class 的命名参数、8 个 Service 的方法与参数、`AppGraph.container.*` 字段、`Routes/Tabs/NavParams/Navigator/EcColor/...` 成员、枚举值 | ✅ 全部通过 |
| ③ 全量静态审计 | 页面 → Service/DTO 调用点、页面入口签名、Compose scope/嵌套滚动/@OptIn/硬编码颜色/分层违规 | ✅ ERROR 0（详见 [`AUDIT.md`](AUDIT.md)） |
| ④ 逻辑层冒烟编译 | 缓存 Kotlin 编译器 + Android/OkHttp 桩：core 33 文件 + 页面逻辑层 21 文件 | ✅ 0 real error（详见 [`SMOKE_COMPILE.md`](SMOKE_COMPILE.md) §9） |

> ④ 仅覆盖非 Compose 的逻辑层，**Compose UI 文件只能靠正式构建验证**。它曾抓到 5 个静态检查抓不到的真实错误
> （KDoc 里的 `/auth/*` 触发嵌套块注释、`private fun load()` 不可达、`savingAddress` 不存在、
> 行首 `+` 被当一元加号），全部已修并复核；第二轮新增代码 0 real error。

**编译验证需在装有 Android SDK 的机器上**：

1. Android Studio → Open `android/` → Sync（首次下载依赖；wrapper jar 见 §1 说明）
2. `./gradlew :app:assembleDebug`
3. 真机联调清单见 `../docs/acceptance-checklist.md`，最小闭环：
   登录 → `/auth/me` → 语料 → 示范音 → 录一句 → 评测分数 → 连读 3 句 → 读故事 → 对话一轮 → 诊断；
   断网录一句 → 首页「有 N 条录音还没评分」→ 补评分页 → 全部重试。

---

## 6. 后续（M2 候选）

- 深色模式（`EcTheme` 已预留 `LocalIsChild`/色板结构）、平板双栏、无障碍（TalkBack 文案）
- 打印/PDF 导出（Android `PrintManager`；鸿蒙端也没有，属 Web 专属能力）
- 后台自动补评分（WorkManager，把当前手动重试改为网络恢复即重试）
- 单元测试：`ApiClient` 单飞刷新、`ErrorMapper` 文案、`EcScore` 儿童规则、
  `PendingUploadQueue` 入队/重试/坏索引自愈（JVM 测试，无需设备）
- 服务端能力缺口（需后端配合）：`POST /auth/password` 自助改密、故事录音持久化接口、
  批量 OCR、`GET /tts/voices`

---

## 7. 文档索引

| 文档 | 用途 |
|---|---|
| [`CONTRACT.md`](CONTRACT.md) | 第一轮团队契约：分层、Service/DTO 签名、组件 API、页面签名、儿童规则 |
| [`ROUND2_CONTRACT.md`](ROUND2_CONTRACT.md) | 第二轮：离线能力、能力开关、语音偏好、签名变更、补齐清单 |
| [`AUDIT.md`](AUDIT.md) | 全量静态审计（结构/调用点/Compose 规则/修复清单） |
| [`SMOKE_COMPILE.md`](SMOKE_COMPILE.md) | 逻辑层冒烟编译（第一轮 §1–§8、第二轮 §9） |
| [`QA_ROUND2.md`](QA_ROUND2.md) | 第二轮逐项验收（代码出处 + 问题清单 + 限制） |
| [`../docs/android-feature-list.md`](../docs/android-feature-list.md) | 功能总清单（验收依据，与鸿蒙/文档偏差 D-xx / A-xx） |
| [`../docs/feature-index.md`](../docs/feature-index.md) | 全端功能索引；§10 是 Android 实现状态 |

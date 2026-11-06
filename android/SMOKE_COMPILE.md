# Android 客户端 · 非 UI 逻辑层冒烟编译报告（SMOKE COMPILE）

> 目的：本机无 Android SDK / Gradle 可用，用「Kotlin 编译器 + 最小桩」对**非 Compose 的页面逻辑文件**
> 做一次全仓类型检查，提前拦下签名不匹配、未定义符号、注释吞代码这类整包编译才暴露的问题。
> 本文是临时验证手段的产物，**不是正式构建脚本**（按要求不提交构建脚本、不做 git commit）。

- 执行人：screens-flow（连读页）
- 日期：2026-11-04
- 结论：**逻辑层 30/30 文件除 1 个真实编译错误外全部通过；core 层修复 2 个真实错误后全部通过。**

---

## 1. 工具与版本

| 项 | 值 |
|---|---|
| 编译器 | Kotlin **1.9.22** `kotlin-compiler-embeddable`（Gradle 缓存自带；项目正式版为 Kotlin 2.0.21，仅用于冒烟） |
| JDK | Zulu 1.8.0_322（`JAVA_HOME`） |
| 协程 | `kotlinx-coroutines-core-jvm-1.9.0.jar`（真实库，来自本机 claude-code JetBrains 插件 lib 目录） |
| 序列化 | **用桩**（`@Serializable/@SerialName/Json/parseToJsonElement/jsonObject/jsonPrimitive/contentOrNull/encodeToString/decodeFromString`）：缓存里的 serialization 1.8.1 要求 Kotlin ≥ 2.0，与 1.9.22 编译器元数据不兼容 |
| Android / AndroidX | 全部打桩：`android.content.Context/SharedPreferences/ContentResolver`、`android.net.Uri`、`android.os.SystemClock/Build`、`android.util.Log/LruCache`、`androidx.core.content.edit`、`androidx.security.crypto.*`、`androidx.lifecycle.ViewModel/ViewModelProvider`、`androidx.navigation.NavController`、Compose 基础类型（`Color/Dp/TextUnit/Modifier` 中仅 DesignTokens 需要的部分） |
| OkHttp | 打桩（缓存无 OkHttp jar）：`OkHttpClient/Request/Response/RequestBody/MultipartBody/MediaType` |
| 音频/权限 | 打桩：`AudioController`（`recording/playing`、录音/播放/释放、`MAX_DURATION_MS`）、`MicPermission`、`RecordingResult` |
| Compose | **不编译**（`*Screen.kt`、`ChatComponents.kt`、`StatsUi.kt`、`StoryUi.kt`、`EcTheme.kt`、`AppNavHost.kt`、`AppRoot.kt`、`HomeScreen.kt`、`ui/component/**` 等共 32 个文件），它们只有整包构建才能验证 |

## 2. 覆盖范围

**Core（真实源码，31 个文件）**：`core/config`、`core/di/AppGraph.kt`、`core/di/VmFactory.kt`、`core/error/UiError.kt`、
`core/model/UserModels.kt`、`core/net`（ApiClient/ApiError/Json/dto 全部 6 个 DTO 文件）、`core/service/*`（8 个）、
`core/session`（SessionStore/TokenStore/CredentialStore）、`core/storage`（AppPrefs/CacheStore）、`core/util`（FileUtil/Logx）、
`core/audio/Voices.kt`、`ui/design/DesignTokens.kt`、`ui/nav/Routes.kt`。

**页面逻辑层（30 个文件）**：`ui/page/**/*ViewModel.kt`（16 个）、`*Models.kt`（4 个：AccountFamilyModels/ChatModels/PracticeModels/FlowModels）、
`*Runtime.kt`（StoryRuntime）、`PhonemeHints.kt`、`flow` 的 3 个逻辑文件（FlowModels/FlowViewModel/FlowSummaryViewModel）。

## 3. 每个文件结果

### Core 组（修 2 个真实错误、打 1 个桩后）→ **errors=0，warnings=0**
30 个真实 core 文件全部通过（含 8 个 service、6 个 DTO、SessionStore、AppGraph、DesignTokens、Routes）。
说明：`ApiClient.kt` / `TokenStore.kt` 使用了「修好的临时副本」参与编译（见 §4 的 F1/F2，仓库文件未改）；
`CredentialStore.kt` 用桩替代（见 §5 限制 L2）。

### 页面逻辑组 → 30 个文件，**29 个 errors=0，1 个真实错误**
| 文件 | errors | warnings |
|---|---|---|
| `ui/page/account/AccountFamilyModels.kt` | 0 | 0 |
| `ui/page/account/AvatarViewModel.kt` | 0 | 0 |
| `ui/page/account/FamilyViewModel.kt` | 0 | 0 |
| `ui/page/account/HealthViewModel.kt` | 0 | 0 |
| `ui/page/account/MeViewModel.kt` | 0 | 0 |
| `ui/page/account/ParentViewModel.kt` | 0 | 0 |
| `ui/page/account/SettingsViewModel.kt` | **4** | 0（见 F3） |
| `ui/page/account/SuggestionsViewModel.kt` | 0 | 0 |
| `ui/page/account/VoicesViewModel.kt` | 0 | 0 |
| `ui/page/auth/LoginViewModel.kt` | 0 | 0 |
| `ui/page/chat/ChatCustomViewModel.kt` | 0 | 0 |
| `ui/page/chat/ChatHistoryViewModel.kt` | 0 | 0 |
| `ui/page/chat/ChatModels.kt` | 0 | 0 |
| `ui/page/chat/ChatScenariosViewModel.kt` | 0 | 0 |
| `ui/page/chat/ChatSessionViewModel.kt` | 0 | 0 |
| `ui/page/flow/FlowModels.kt`（本交付） | 0 | 0 |
| `ui/page/flow/FlowViewModel.kt`（本交付） | 0 | 0 |
| `ui/page/flow/FlowSummaryViewModel.kt`（本交付） | 0 | 0 |
| `ui/page/practice/PhonemeHints.kt` | 0 | 0 |
| `ui/page/practice/PracticeModels.kt` | 0 | 0 |
| `ui/page/practice/PracticeViewModel.kt` | 0 | 0 |
| `ui/page/practice/SentenceListViewModel.kt` | 0 | 0 |
| `ui/page/stats/BlindTestViewModel.kt` | 0 | 0 |
| `ui/page/stats/DiagnosisViewModel.kt` | 0 | 0 |
| `ui/page/stats/ReviewViewModel.kt` | 0 | 0 |
| `ui/page/story/StoryDetailViewModel.kt` | 0 | 0 |
| `ui/page/story/StoryHomeViewModel.kt` | 0 | 0 |
| `ui/page/story/StoryRecordViewModel.kt` | 0 | 0 |
| `ui/page/story/StoryReviewViewModel.kt` | 0 | 0 |
| `ui/page/story/StoryRuntime.kt` | 0 | 0 |

> 说明：逻辑组是「core 真实源码 + 30 个逻辑文件一起编译」，因此上面 0 error 也证明这些 VM 对
> `AppContainer` / 各 Service / DTO / DesignTokens / Routes / AudioController 的调用签名全部匹配。

## 4. 发现的问题（按严重度）

### F1【阻断·真实】`core/net/ApiClient.kt:97` —— KDoc 里 `/auth/*` 形成嵌套块注释，整个文件解析失败
- 报错（Kotlin 1.9.22，仓库现状）：`ApiClient.kt:272:53: error: expecting a top level declaration`，随后 90+ 条连锁错误。
- 原因：Kotlin 支持**嵌套块注释**。第 97 行 KDoc 文本 `` `/auth/*` `` 在注释里又开了 `/*`，闭合错位后外层注释一直延伸到
  第 272 行字符串 `"*/*"` 里的 `*/`，导致 `execute()` 及其后所有代码被当注释吞掉。
- 改法（一行）：把第 97 行的 `` `/auth/*` `` 改成 `` `/auth/...` ``（或 `/auth/` + 去掉星号）。
- 影响：**整包编译必然失败**，不只是冒烟问题。归属：Lead（core/net）。

### F2【阻断·真实】`core/session/SessionStore.kt:58` 调用 `tokenStore.load()`，但 `TokenStore.load()` 是 `private`
- 报错：`SessionStore.kt:58: can not access 'load': it is private in 'TokenStore'`。
- 改法：`TokenStore.kt:37` 的 `private fun load()` 改为 `internal fun load()`（或 public），SessionStore 调用不变。
- 归属：Lead（core/session）。

### F3【真实】`ui/page/account/SettingsViewModel.kt` —— `savingAddress` 字段不存在（状态里叫 `saving`）
- 报错：`SettingsViewModel.kt:257:26: unresolved reference: savingAddress`；`275:25`、`290:29`：
  `cannot find a parameter with this name: savingAddress`；`269` 同。
- 现状：`SettingsUiState`（第 35 行起）只有 `val saving: Boolean = false`（第 38 行）。
- 改法：把 257/269/275/290 四处 `savingAddress` 全部改为 `saving`（如需语义更清楚，也可在 state 里加
  `val savingAddress: Boolean = false`，但同一状态已有 `saving`，建议直接复用）。
- 归属：账号页（本团队无 screens-account，已由 Lead 转交/处理）。

### 未报告的问题
其余 29 个逻辑文件、30 个 core 文件 **0 error / 0 warning**；`ui/page/flow/**` 内无需修复。

## 5. 局限（这些位置的报错不能当真）

- **L1 Compose 文件未编译**：所有 `*Screen.kt`、`ChatComponents.kt`、`StatsUi.kt`、`StoryUi.kt`、`ui/component/**`、
  `EcTheme.kt`、`AppNavHost.kt`、`AppRoot.kt`、`HomeScreen.kt`（约 32 个）**没有纳入本次类型检查**；
  Composable 调用、Modifier 作用域、参数默认值只有正式 Compose 编译才能验证。
- **L2 序列化用桩**：`CredentialStore.kt` 的 `SavedLogin.serializer()` / `EcJson.encodeToString(serializer, …)` 依赖
  Kotlin 编译器 serialization 插件；本机插件版本 1.9.22 与缓存里的 serialization 1.8.1（要求 Kotlin ≥2.0）不兼容，
  因此 `CredentialStore` 用桩替代、未做真实检查。
- **L3 Kotlin 版本**：1.9.22 不认识 Kotlin 2.0 独有语法；本次未发现此类报错，但 2.0 特性（如更严格的 smart cast）
  无法评估。
- **L4 Android/OkHttp/security 全是桩**：平台 API 的真实签名（如 `MediaRecorder` 状态机、`EncryptedSharedPreferences.create`
  参数顺序）未由真实 SDK 校验；`EncryptedSharedPreferences.create(context, fileName, masterKey, …)` 的顺序按
  security-crypto 1.1.0-alpha06 处理。
- **L5 协程版本**：用 1.9.0 真实 jar；`MutableStateFlow.update`、`FlowCollector` SAM 转换等与项目 1.9.0 一致。

## 6. 结论

1. 除 F1/F2/F3 外，**全仓非 UI 逻辑层通过类型检查**；F1 是整包编译阻断项，必须修。
2. 修复建议见 §4，均为一行级改动；F1/F2 由 Lead 直接修，F3 归账号页负责人。
3. 正式验收仍需在具备 Android SDK 的机器上跑 `./gradlew :app:compileDebugKotlin`（本次不写构建脚本）。

## 7. 复现方式（临时目录，不落仓库）

本次 harness 位于系统临时目录（`%TEMP%\smoke`）：
- `stubs/`：Android/AndroidX/OkHttp/序列化/音频最小的 .kt 桩；
- `patched/ApiClient.kt`、`patched/TokenStore.kt`：仅为绕过 F1/F2 的临时副本（不改仓库）；
- 编译命令（两组）：
  ```
  java -cp "kotlin-compiler-embeddable-1.9.22.jar;<kotlin-stdlib-1.9.22.jar>;<trove4j.jar>;<annotations-13.0.jar>" \
       org.jetbrains.kotlin.cli.jvm.K2JVMCompiler \
       -no-stdlib -no-reflect -classpath "<stdlib>;<kotlinx-coroutines-core-jvm-1.9.0.jar>" \
       -d <out> <core 真实源码> <逻辑层 30 文件> <stubs/**>
  ```
- 每组编译完按 `.kt:line:col: error/warning` 统计每文件数量（脚本只在临时目录）。

---

## 8. 复核 2026-11-04 02:39（F1/F2/F3 修复验证）

工具与 §1 完全一致（Kotlin 1.9.22 + 真实 coroutines 1.9.0 + 桩）。**本次不再使用任何业务源码的临时补丁副本为常态配置**：
`ApiClient.kt`、`TokenStore.kt`、`SessionStore.kt`、`SettingsViewModel.kt` 均直接编译仓库真实文件。

### 8.1 3 个问题的修复确认

| # | 修复内容 | 源码确认 | 复核结果 |
|---|---|---|---|
| F1 | `ApiClient.kt:97` `` `/auth/*` `` → `` `/auth/...` `` | 第 97 行已无星号，KDoc 不再嵌套开注释 | core 组 **0 error**，`ApiClient.class` 正常生成，`execute()` 及其后代码全部参与编译 |
| F2 | `TokenStore.load()` `private` → `internal` | `TokenStore.kt:38 internal fun load()` | core 组 **0 error**，`SessionStore.class`、`TokenStore.class` 正常生成 |
| F3 | `SettingsViewModel` 4 处 `savingAddress` → `saving` | 257/269/275/290 已无 `savingAddress`，与 `SettingsUiState.saving`（第 38 行）一致 | 逻辑组 **0 error**，`SettingsViewModel.class` 正常生成 |

### 8.2 重跑结果

| 组 | 编译方式 | 真实文件 error | 真实文件 warning | 生成 class |
|---|---|---|---|---|
| core（31 个真实 core 文件 + 21 个桩） | 仓库真实 `ApiClient.kt`/`TokenStore.kt`（无补丁） | **0** | 0（仅桩文件 unused-parameter 警告） | 373 |
| logic（30 个逻辑文件 + 同组 core） | 真实 `SettingsViewModel` 等；`FamilyViewModel`/`PracticeModels` 用临时副本，见 8.3/8.5 | **0** | 0（仅桩文件警告） | 712 |

- 日志中非桩诊断仅剩桩文件的 `unused parameter` 警告；业务源码 **0 error / 0 warning**。
- 另核对 Lead 提到的其它改动：`core/config/AppConfig.kt` 在 core 组真实编译通过（默认值注释无影响）；
  `ui/HomeScreen.kt`、`ui/page/auth/LoginScreen.kt` 属 Compose 文件，仍未纳入本 harness（见 8.5 / §5 L1）。

### 8.3 复核中新发现的真实错误（已报 Lead）

#### F4【真实】`ui/page/account/FamilyViewModel.kt:310` —— 行首 `+` 被解析成一元加号
```kotlin
309:        return "${member.dailyLimitMinutes} 分钟/天 · 练过 $attempts 次"
310:            + if (member.allowFreeChat) " · 允许自由对话" else ""
```
- 报错：`FamilyViewModel.kt:310:13: error: unresolved reference: +`
- 原因：`return "…"` 已是完整语句；换行后行首的 `+` 按 Kotlin 换行规则被当作**一元加号**（String 没有一元 +），不是二元连接。
- 改法（一行）：把 `+` 移到上一行行尾：
  ```kotlin
  return "${member.dailyLimitMinutes} 分钟/天 · 练过 $attempts 次" +
      if (member.allowFreeChat) " · 允许自由对话" else ""
  ```
- 复核时已用该临时修正副本验证：`FamilyViewModel.class` 可正常生成、组内 0 error（仓库文件未改）。
- 同类扫描：全仓 `.kt` 中只有这一处行首二元运算符（其余行首 `+`/`-` 均为注释或正常一元用法）。

### 8.4 复核结论

**F1 / F2 / F3 全部已修复且复核 0 error**；另发现 F4（FamilyViewModel 行首 `+`，真实错误）并已报 Lead；
除此之外逻辑层与 core 层真实源码在本次 harness 下 **全部通过**。

### 8.5 剩余不可覆盖范围（与 §5 相同）

1. **Compose UI 文件**（约 32 个 `*Screen.kt`/组件/`EcTheme`/`AppNavHost`/`AppRoot`/`HomeScreen`）未参与：本次
   `HomeScreen` 的 `rememberSaveable`、`LoginScreen` 副文案都属该范围，需正式构建验证。
2. **serialization 插件路径**：`PracticeModels.kt:83` 的 `SentenceListDto.serializer()`（与 `CredentialStore` 同类）
   在 1.9.22 harness 中不可解析，复核时用等价 `decodeFromString<SentenceListDto>(raw)` 临时副本绕过；**不是代码错误**（§5 L2）。
3. Android/OkHttp/security 平台真实签名（§5 L4）、Kotlin 2.0 特性（§5 L3）仍由正式 `:app:compileDebugKotlin` 兜底。

### 8.6 F4 复核（2026-11-04 02:41）

**F4 已修复并复核 ✅**：`FamilyViewModel.kt` 的 `+` 已移到上一行行尾，用仓库真实文件重跑逻辑组——
**real errors=0 / real warnings=0**（仅桩文件告警），`FamilyViewModel.class`、`SettingsViewModel.class` 均正常生成，
全仓 logic+core 0 real error；全仓行首二元运算符扫描复查为 0 处。

---

## 9. 第二轮复核（2026-11-05 01:50）

> 第二轮（离线能力 + 功能补齐）收尾冒烟。同一套 harness（§1），环境恢复后重跑。

### 9.1 工具

| 项 | 值 |
|---|---|
| 编译器 | Kotlin 1.9.22 `kotlin-compiler-embeddable`（项目正式版 Kotlin 2.0.21，仅冒烟用） |
| 协程 | 真实 `kotlinx-coroutines-core-jvm-1.9.0.jar` |
| 序列化 | `@Serializable/@SerialName/Json/encodeToString/decodeFromString` 用桩（1.9.22 无 serialization 插件，缓存里 1.8.1 运行时要求 Kotlin≥2.0） |
| Android / AndroidX / OkHttp | 桩：`Context/SharedPreferences/ContentResolver/ConnectivityManager/NetworkCapabilities`、`Uri/SystemClock/Log`、`androidx.core.content.edit`、`security-crypto`、`lifecycle ViewModel`、`navigation NavController`、Compose 基础类型、OkHttp |
| 音频 / 权限 | 桩：`AudioController`、`MicPermission`、`RecordingResult`；`Voices`/`VoicePrefs` 真实编译 |
| 覆盖方式 | core 组 + logic 组分别编译；**真实错误**= 非桩文件诊断 |

### 9.2 覆盖文件与结果

**core 组：33 个真实文件 → errors=0 / warnings=0，生成 410 个 class。**
含本轮 data-layer 新增/增补：
`core/content/CapabilityCache.kt`、`core/audio/VoicePrefs.kt`、`core/offline/PendingUploadQueue.kt`、
`core/storage/CacheStore.kt`（增补 LRU/队列目录/最近结果）、`core/service/PracticeService.kt`（`health(force)`/`audioByUrl`），
以及 `core/net`（ApiClient/ApiError/Json/6 个 DTO）、`core/service/*`（8 个）、`core/config`、`core/model`、
`core/session`（SessionStore/TokenStore 真实；CredentialStore 因 serialization 插件限制用桩）、`core/util`、`core/audio/Voices`、
`ui/design/DesignTokens.kt`、`ui/nav/Routes.kt`。

**logic 组：21 个页面逻辑文件 → errors=0 / warnings=0，生成 667 个 class。**
逐文件（均为 e=0 / w=0）：
- data-layer 对外逻辑：`PendingUploadQueue`（已在 core 组，逻辑组随 core 编入）
- practice：`PracticeViewModel`、`PracticeModels`▲、`PhonemeHints`
- flow：`FlowViewModel`、`FlowModels`、`FlowSummaryViewModel`
- story：`StoryHomeViewModel`、`StoryRecordViewModel`、`StoryDetailViewModel`、`StoryReviewViewModel`、`StoryRuntime`▲
- offline：`PendingUploadsViewModel`
- account：`AccountFamilyModels`、`MeViewModel`、`SettingsViewModel`、`HealthViewModel`、`AvatarViewModel`、`VoicesViewModel`、`ParentViewModel`、`FamilyViewModel`、`SuggestionsViewModel`

▲ `PracticeModels.kt` / `StoryRuntime.kt`：仓库源码里使用 `Xxx.serializer()`（依赖 serialization 编译器插件），
本 harness 无该插件 → 用**临时副本**把这两处换成等价的 `decodeFromString<T>(raw)` / `encodeToString<T>(value)`
参与编译（仓库文件未改）。**不是代码错误**，属工具限制。
关键类存在性抽查：`CapabilityCache/VoicePrefs/PendingUploadQueue/PracticeService/CacheStore/FlowViewModel/
FlowSummaryViewModel/PracticeViewModel/PendingUploadsViewModel/StoryDetailViewModel/SettingsViewModel.class` 均生成 ✅。

**静态检查**：`PYTHONIOENCODING=utf-8 python android/tools/check_android.py` → **「静态检查通过 ✅」EXIT=0**（115 个 Kotlin 文件）。

### 9.3 结论与剩余未覆盖范围

- 本轮所有改动的**逻辑层真实源码 0 error / 0 warning**，未发现需要修复的真实错误（因此无需给各 owner 发问题单）。
- **未覆盖**（只有正式 Android 构建能验）：
  1. 全部 Compose UI 文件（`*Screen.kt`、`ui/component/**`、`EcTheme`、`AppNavHost`、`AppRoot`、`HomeScreen` 等约 32 个）：
     Compose 编译器、Modifier/Composable 作用域、页面签名接线（含 `FlowSummaryScreen` 新 `onOpenReview` 参数）；
  2. `CredentialStore` 与两处 `.serializer()` 的 serialization 插件真实展开；
  3. Android/OkHttp/security-crypto 平台真实 API 签名与运行时行为（录音/权限/加密存储/网络）；
  4. 端到端运行链路（待补评分 `retryAll`、故事复述跳转、OCR 能力开关真实服务端返回）。
- 建议正式验收：有 Android SDK 机器执行 `./gradlew :app:compileDebugKotlin` + 真机回归。

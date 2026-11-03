# Android 客户端 · 团队共享契约（CONTRACT）

> 本文件是 `english-coach-app/android/` 的**唯一共享约定**。所有并行开发的人都必须严格按此实现；
> 需要改约定时先改本文件，再改代码。
>
> 事实来源（按优先级）：
> 1. `english-coach-app/hos/`（鸿蒙实现，功能与交互已真机验证）
> 2. `english-coach-app/docs/**`、`hos/docs/**`（设计文档）
> 3. `english-coach-app/README.md` §2/§6（跨端约定与 API 速查）
>
> 移植原则：**行为照抄，架构换 Android 惯用法**。不要"顺手优化"交互，不要丢功能。

---

## 0. 版本策略（用户要求：只做目前市面上的主流 Android 版本）

| 项 | 值 | 说明 |
|---|---|---|
| minSdk | **26**（Android 8.0） | 覆盖 2017 年后所有主流机；`java.time`、`EncryptedSharedPreferences` 都可用 |
| targetSdk / compileSdk | **35**（Android 15） | 满足 Google Play 现行要求 |
| 架构 | 单 Activity + Jetpack Compose + ViewModel/StateFlow | 无 Fragment |
| 屏幕 | 手机竖屏为主，平板可拉伸（`widthIn` 约束） | 不做横屏专用布局 |

不写 API 26 以下的兼容分支（不用支持库 `AppCompat`，不判断 `SDK_INT < 26`）。

---

## 1. 目录结构与**文件归属**

根包：`top.dreamsearch.englishcoach`

```
android/app/src/main/java/top/dreamsearch/englishcoach/
├── EnglishCoachApp.kt              [Lead] Application：AppGraph.init
├── MainActivity.kt                 [Lead] setContent { AppRoot() }
├── core/
│   ├── config/AppConfig.kt         [Lead] baseUrl/演示账号/等级映射
│   ├── di/AppGraph.kt              [Lead] 手写依赖图（服务都用 AppGraph.container.xxx 取）
│   ├── di/VmFactory.kt             [Lead] vmFactory { }
│   ├── error/UiError.kt            [Lead] UiError + ErrorMapper（成人/儿童两套文案）
│   ├── model/UserModels.kt         [Lead] UserDto/UsageDto/MeResponseDto/TokenResponseDto/LoginResult
│   ├── net/ApiClient.kt            [Lead] OkHttp 封装 + 401 单飞刷新
│   ├── net/ApiError.kt             [Lead] ApiError + ApiErrorCode
│   ├── net/Json.kt                 [Lead] EcJson + decodeBody
│   ├── net/dto/*.kt                [数据层] DTO（@Serializable data class）
│   ├── service/*.kt                [数据层] Service（无状态、suspend、抛 ApiError）
│   ├── session/TokenStore.kt       [Lead] token 加密存储
│   ├── session/CredentialStore.kt  [Lead] 记住密码（加密）
│   ├── session/SessionStore.kt     [Lead] 会话状态 StateFlow
│   ├── storage/AppPrefs.kt         [Lead] 非敏感偏好
│   ├── storage/CacheStore.kt       [Lead] 目录/缓存
│   ├── util/FileUtil.kt|Logx.kt    [Lead]
│   └── audio/                      [UI Kit] AudioController + 内置音色常量
├── ui/
│   ├── design/DesignTokens.kt      [Lead] EcColor/EcSpace/EcRadius/EcFont/EcScore
│   ├── design/EcTheme.kt           [Lead] Material3 主题 + LocalIsChild
│   ├── nav/Routes.kt               [Lead] Routes/Tabs/NavParams/TabNav
│   ├── nav/AppNavHost.kt           [Lead] NavHost 接线（页面完成后写）
│   ├── AppRoot.kt                  [Lead] 启动恢复/登录门禁/导航容器
│   ├── component/*.kt              [UI Kit] 组件库
│   └── page/<feature>/*.kt         [各页面负责人]
└── ...
```

**写作用域是互斥的**：只写自己负责的目录；需要别人改的文件，发消息给 Lead，不要直接改。

---

## 2. 已提供的基础设施（直接调用，不要重写）

### 2.1 网络

```kotlin
class ApiClient {                                   // AppGraph.container.api
    suspend fun getJson(path: String, query: Map<String, String>? = null, timeoutMs: Long = 15_000): ApiRaw
    suspend fun postJson(path: String, body: String, auth: Boolean = true, timeoutMs: Long = 15_000): ApiRaw
    suspend fun patchJson(path: String, body: String, timeoutMs: Long = 15_000): ApiRaw
    suspend fun deleteJson(path: String, timeoutMs: Long = 15_000): ApiRaw
    suspend fun postJsonForBytes(path: String, body: String, timeoutMs: Long = 90_000): ApiRaw
    suspend fun postMultipart(path: String, query: Map<String, String>? = null,
                              parts: List<FormPart>, timeoutMs: Long = 90_000): ApiRaw
    suspend fun getBytes(path: String, query: Map<String, String>? = null, timeoutMs: Long = 120_000): ApiRaw
    suspend fun download(path: String, destFile: File, query: Map<String, String>? = null, timeoutMs: Long = 120_000)
    fun requireOk(raw: ApiRaw)                       // 非 2xx 抛 ApiError
    fun errorOf(raw: ApiRaw): ApiError
}
class ApiRaw(val status: Int, val text: String, val bytes: ByteArray?)
class FormPart {
    companion object {
        fun text(name: String, value: String): FormPart
        fun file(name: String, fileName: String, bytes: ByteArray, contentType: String? = null): FormPart
    }
}
/** 超时常量：ApiRequest.DEFAULT_TIMEOUT_MS / EVAL_TIMEOUT_MS(120s) / LONG_TIMEOUT_MS(90s) / DOWNLOAD_TIMEOUT_MS */
```
- `path` **不含** `/api` 前缀（ApiClient 自拼 baseUrl + `/api`）。
- 401 → 自动单飞刷新并重放一次，service 不用处理。
- 解析：`decodeBody<T>(raw.text, "xxx")`（失败抛 `bad_response`）。

### 2.2 错误

```kotlin
class ApiError(val code: String, val status: Int, val detail: String) : Exception  // status=0 表示本地错误
object ApiErrorCode { /* 见 core/net/ApiError.kt，全部常量都在里面 */ }
data class UiError(val title: String, val message: String, val actionLabel: String, val retryable: Boolean, val code: String)
object ErrorMapper { fun from(err: Throwable, isChild: Boolean): UiError }
```
- **service 一律抛 `ApiError`**；VM 用 `AppGraph.session.toUiErrorAsync(e)` / `toUiError(e)` 转成中文文案。
- 禁止静默失败：页面必须显示 `UiError.message` + 可重试入口。

### 2.3 会话

```kotlin
class SessionStore {
    val state: StateFlow<SessionState>               // loggedIn/isChild/cefrLevel/remainingMinutes/...
    val isChild: Boolean
    suspend fun restore(): Boolean                   // false=需要登录；抛错=网络问题
    suspend fun login(email: String, password: String, rememberPassword: Boolean): SessionState
    suspend fun loginWithSaved(): Boolean
    suspend fun logout()
    suspend fun expire()
    fun updateUsage(usage: UsageDto)                 // 每次评测/对话后同步剩余时长
    fun applyUser(user: UserDto, usage: UsageDto?)
    suspend fun toUiErrorAsync(err: Throwable): UiError
    fun toUiError(err: Throwable): UiError
}
data class SessionState(loggedIn, userId, displayName, email, role, cefrLevel, ageBand,
    isChild, avatar, dailyLimitMinutes, minutesToday, remainingMinutes, exceeded)
```
页面/VM 通过 `AppGraph.session.state` 读取；**不要**自己再存一份登录态。

### 2.4 依赖取用

```kotlin
AppGraph.container.api / .practice / .flow / .chat / .story / .account / .stats / .dictionary
AppGraph.container.audio        // AudioController（录音/播放）
AppGraph.container.cache        // CacheStore（目录、TTS 文件、JSON 缓存、newRecordingFile()）
AppGraph.container.config       // AppConfig（baseUrl、levelForCefr、demoAccounts）
AppGraph.container.session      // SessionStore
```

### 2.5 设计 token / 主题

```kotlin
EcColor.bg/surface/surfaceAlt/ink/muted/border/primary/primarySoft/primaryPressed/focus
        good/goodText/goodBg/warn/warnText/warnBg/bad/badText/badBg/info
EcSpace.x1..x12 : Dp        EcRadius.sm/md/lg/xl/pill : Dp
EcFont.display/h1/h2/h3/body/caption/micro/childBody/childH1/sentence : TextUnit
EcButtonSize.sm/md/lg/child/record/recordChild : Dp
EcScore.color(score: Double?, isChild: Boolean): Color
EcScore.showNumber(score: Double?, isChild: Boolean): Boolean   // 儿童 <60 不显示数字
EcScore.numberText(score: Double?): String
EcScore.encouragement(score: Double?, isChild: Boolean): String
EcScore.stars(score: Double?): String
EcScore.subScoreLabel(key: String): String
LocalIsChild.current : Boolean        // 由 EcTheme 注入；组件里用它决定 IPA/低分
```
规则：**颜色/字号/间距一律取 token**，页面里不写 `Color(0xFF...)`/魔法 dp。

### 2.6 ViewModel 模板

```kotlin
data class XxxUiState(
    val loading: Boolean = false,
    val error: UiError? = null,
    /* ... 业务字段 ... */
)

class XxxViewModel(private val c: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(XxxUiState())
    val state: StateFlow<XxxUiState> = _state.asStateFlow()

    init { load() }

    fun load() { viewModelScope.launch {
        _state.update { it.copy(loading = true, error = null) }
        try { /* c.practice.xxx() */ } 
        catch (e: Throwable) { _state.update { it.copy(loading = false, error = c.session.toUiError(e)) } }
    } }
}
```
页面取 VM：
```kotlin
val vm: XxxViewModel = viewModel(factory = remember { vmFactory { XxxViewModel(AppGraph.container) } })
val state by vm.state.collectAsStateWithLifecycle()
```

### 2.7 导航

```kotlin
object Routes { HOME SENTENCES SETTINGS FLOW_SUMMARY CHAT_SESSION CHAT_HISTORY CHAT_DETAIL CHAT_CUSTOM
                STORY_RECORD STORY_DETAIL STORY_REVIEW DIAGNOSIS REVIEW BLIND_TEST PARENT FAMILY
                SUGGESTIONS AVATAR VOICES HEALTH }
object Tabs { PRACTICE=0 FLOW=1 CHAT=2 STORY=3 ME=4 }
object TabNav { fun go(tab: Int) }          // 跨页切 Tab（故事详情→去连读），HomeScreen 负责消费
object NavParams {                          // 跨页参数（跳转前写入，目标页读取后清空）
    var practiceLevel / practiceFocus / practiceSentenceId
    var flowMaterialId / chatSessionId / chatDetailId / storyMaterialId / diagnosisFocus
    fun clearPractice()
}
```
- **Tab 页**是导航的一级内容；二级页面是 `navController.navigate(Routes.X)` push 出来的。
- 需要参数的二级页：由跳转方写 `NavParams`，目标页 `init` 里读取（并清空），**不通过路由参数传**。

---

## 3. 数据层规范（`core/net/dto` + `core/service`）

### 3.1 DTO

- 移植 `hos/entry/src/main/ets/core/net/*Dtos.ets`，一一对应：
  | Android 文件 | 来源 |
  |---|---|
  | `core/net/dto/Dtos.kt` | `Dtos.ets` |
  | `core/net/dto/FlowDtos.kt` | `FlowDtos.ets` |
  | `core/net/dto/ChatDtos.ets` | `ChatDtos.ets` |
  | `core/net/dto/StoryDtos.kt` | `StoryDtos.ets` |
  | `core/net/dto/StatsDtos.kt` | `StatsDtos.ets` |
  | `core/net/dto/AccountDtos.kt` | `AccountDtos.ets` |
- 规则：
  - `interface` → `@Serializable data class`；**每个字段给默认值**（`String = ""`、`Int = 0`、`Boolean = false`、可空类型 `? = null`、`List<T> = emptyList()`）。
  - 服务端字段名**原样保留**，用 `@SerialName` 映射成 camelCase 属性；
    例外：`/settings` 的 `user`/`prefs` 与 `UserDto` 本身已是 camelCase，直接用同名属性。
  - 已存在的共享模型（`core/model/UserModels.kt` 的 `UserDto`/`UsageDto`/`MeResponseDto`/`TokenResponseDto`）**复用，不要重复定义**。
  - 单态 `Array<number|null>`（语调曲线 `F0Point`）用 `List<Double?>`。
  - 请求体（如 `SettingsPatchBodyDto`）也用 `@Serializable data class`，序列化时 `explicitNulls=false` 已关闭，可空字段不传。

### 3.2 Service

- 类名/构造必须**严格**如下（`AppGraph` 已按这些签名实例化）：

```kotlin
class AuthService(private val api: ApiClient)
class PracticeService(private val api: ApiClient)
class FlowService(private val api: ApiClient)
class ChatService(private val api: ApiClient)
class StoryService(private val api: ApiClient)
class AccountService(private val api: ApiClient)
class StatsService(private val api: ApiClient)
class DictionaryService(private val api: ApiClient)
```

- 方法：`suspend fun`，参数显式命名，**返回 DTO/基础类型**，非 2xx 抛 `ApiError`（`api.requireOk` / `api.errorOf`）。
- Service **不写文件、不播音频、不碰 Android UI**：音频字节由 VM 落到 `CacheStore` 再交给 `AudioController`。
- 必须移植的方法（以 hos 同名 service 为准，行为一致）：

| Service | 方法（返回类型以 DTO 为准） |
|---|---|
| AuthService | `login(email, password): LoginResult`（含 `/auth/token` + `/auth/me` 校正 usage）、`me(): MeResponseDto`（user 为 null 时刷新一次再取，仍空则清 token 抛 unauthorized）、`revoke()` |
| PracticeService | `sentences(level: String, focus: String = ""): List<SentenceDto>`、`tts(text, rate: String, voice: String? = null, format: String = "wav"): ByteArray`、`attempts(limit: Int = 20): List<AttemptItemDto>`（历史/进步曲线数据源）、`audio(audioId: String): ByteArray`、`evaluate(...): AttemptResponseDto`（multipart：`audio` 文件 + `sentence_id` + `reference_text` + `mode`）、`retryAttempt(attemptId): AttemptResponseDto`、`health(): HealthDto`、`warmup()` |
| FlowService | `materialsPage(limit: Int = 50): List<MaterialDto>`、`materialDetail(id): MaterialDetailDto`、`createPage(title, text, source): MaterialDto`、`savePage(title, text): MaterialDto`、`updatePage(id, title?, text?)`、`deletePage(id)`、`ocr(imageBytes: ByteArray, fileName: String): OcrResultDto`、`submitAsync(audio: ByteArray, sentenceId: String?, referenceText: String, blindTestId: String? = null): AsyncSubmitDto`、`status(ids: List<String>): List<AsyncStatusItemDto>`、`diagnosisBatch(attemptIds: List<String>)` |
| ChatService | `scenarios(includeChild: Boolean = false): List<ChatScenarioDto>`、`createScenario(...)`、`updateScenario(id, ...)`、`deleteScenario(id)`、`createSession(scenarioId: String): ChatSessionDto`、`turn(sessionId: String, audio: ByteArray?, text: String): ChatTurnDto`、`messages(sessionId: String): List<ChatMessageDto>`、`end(sessionId: String)`、`audioStatus(sessionId): ChatAudioStatusDto`、`audio(sessionId: String, force: Boolean = false): ByteArray?`（202 building → null）、`sessions(limit: Int = 20): List<ChatSessionSummaryDto>`、`sessionDetail(sessionId)`、`asr(audio: ByteArray, language: String = "en", provider: String? = null): String` |
| StoryService | `materials(kind: String = "story", limit: Int = 50): List<MaterialDto>`、`materialDetail(id): MaterialDetailDto`、`createMaterial(...): MaterialDto`、`renameMaterial(id, title)`、`deleteMaterial(id)`、`asr(audio: ByteArray, language: String = "zh-CN", provider: String? = null): String`、`rewrite(textZh, level, maxSentences, tense, useWeakPhonemes): StoryRewriteDto`、`retell(materialId, storySentences, transcript, level): StoryRetellDto`、`illustrate(materialId, force: Boolean = false)`、`audioStatus(materialId): StoryAudioStatusDto`、`storyAudio(materialId): ByteArray?`、`materialImage(materialId): ByteArray` |
| AccountService | `settings(): SettingsResponseDto`、`patchSettings(body: SettingsPatchBodyDto): SettingsResponseDto`、`familyMembers(): List<FamilyMemberDto>`、`createMember(body: FamilyCreateBodyDto): FamilyMemberDto`、`updateMember(id, body: FamilyPatchBodyDto): FamilyMemberDto`、`resetMemberPassword(id, newPassword)`、`deleteMember(id)`（若 hos 无则不实现）、`parentSummary(): ParentSummaryDto`、`submitSuggestion(category, content, page?): SuggestionCreateResultDto`、`listSuggestions(): SuggestionListDto`、`patchSuggestionStatus(id, status)`、`exportSuggestionsMarkdown(): String`、`avatarPresets(): AvatarPresetsDto`、`avatar(): AvatarStateDto`、`selectAvatar(presetId, style): AvatarStateDto`、`updateAvatarDescription(desc): AvatarStateDto`、`clearAvatar()` |
| StatsService | `diagnosis(scope: String = "all", days: Int? = null, attemptId: String? = null, attemptIds: List<String>? = null): DiagnosisDto`、`review(): ReviewDto`、`gradeReview(cardId: String, grade: Int)`、`blindTests(): BlindTestListDto`、`startBlindTest(): BlindTestStartDto`、`finishBlindTest(id): BlindTestFinishDto` |
| DictionaryService | `wordIpa(word: String): String?`（`GET /words/:word`，404/`ipa:null` → null；调用方负责 LRU 缓存） |

- 注意（实现时照抄 hos 的**线上规避**，不要照抄文档里的"不存在接口"）：
  - `GET /practice/cursor`、`GET /sentences/:id/attempts`、`GET /tts/voices` **线上不存在** →
    游标用本地偏好（`AppPrefs`），单句历史用 `PracticeService.attempts(limit)` 过滤，音色用
    内置 9 个常量（`core/audio/Voices.kt`，UI Kit 提供）。
  - 盲测提交：`POST /attempts/async` 的响应**只有** `attempt_id/blind/progress`，不含分数。
  - 对话一轮：`POST /asr` → 显示识别文本 → `POST /chat/sessions/:id/turn`（multipart：`audio` + `text`）
    → `POST /tts` 播放。`pron` 分数只能从 `GET /chat/sessions/:id/messages` 轮询拿到。

---

## 4. UI 组件库规范（`ui/component`，UI Kit 负责实现）

组件**只依赖 primitives + 回调**，不 import DTO（避免与数据层交叉依赖）。
唯一例外：`WordText` 允许直接调 `AppGraph.container.dictionary.wordIpa(word)`。

必须提供（签名可微调，但语义/命名必须一致，页面按此写）：

```kotlin
enum class EcButtonKind { PRIMARY, SECONDARY, GHOST, DANGER }
enum class EcButtonSizeKind { SM, MD, LG, CHILD }

@Composable fun EcButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    kind: EcButtonKind = EcButtonKind.PRIMARY, size: EcButtonSizeKind = EcButtonSizeKind.MD,
    enabled: Boolean = true, loading: Boolean = false, fullWidth: Boolean = false)

@Composable fun EcCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit)

@Composable fun PageScaffold(title: String, onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    content: @Composable ColumnScope.(PaddingValues) -> Unit)

@Composable fun LoadingBlock(text: String = "加载中…", subText: String? = null)
@Composable fun EmptyState(icon: String = "🌱", message: String,
    actionLabel: String? = null, onAction: (() -> Unit)? = null)
@Composable fun ErrorBanner(error: UiError?, onRetry: (() -> Unit)? = null, onDismiss: (() -> Unit)? = null)

/** 分数：0–100；儿童 <60 不显示数字（见 EcScore） */
@Composable fun ScoreBadge(score: Double?, isChild: Boolean = LocalIsChild.current, label: String? = null)
@Composable fun ScoreChip(score: Double?, isChild: Boolean = LocalIsChild.current, text: String)
@Composable fun SubScoreRow(items: List<Pair<String, Double?>>, isChild: Boolean = LocalIsChild.current)

/** 逐词：点击弹 IPA（儿童不显示 IPA） */
@Composable fun WordText(text: String, isChild: Boolean = LocalIsChild.current,
    showIpa: Boolean = true, modifier: Modifier = Modifier)

/** 图表（纯 Canvas，不引第三方库） */
@Composable fun EcLineChart(series: List<List<Float?>>, colors: List<Color>,
    height: Dp = 120.dp, minY: Float = 0f, maxY: Float = 100f)
@Composable fun EcBarChart(values: List<Float>, labels: List<String>, height: Dp = 120.dp,
    maxValue: Float = 100f, color: Color = EcColor.primary)
@Composable fun EcTrendChart(points: List<Float?>, labels: List<String>, height: Dp = 120.dp)

/** 输入与常用块 */
@Composable fun EcTextField(value: String, onValueChange: (String) -> Unit, label: String,
    placeholder: String = "", password: Boolean = false, singleLine: Boolean = true,
    enabled: Boolean = true, keyboardType: KeyboardType = KeyboardType.Text, modifier: Modifier = Modifier)
@Composable fun EcChip(label: String, selected: Boolean, onClick: () -> Unit)
@Composable fun EcSwitchRow(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit,
    subtitle: String? = null, enabled: Boolean = true)
@Composable fun EcPill(text: String, tone: PillTone = PillTone.NEUTRAL)     // NEUTRAL/GOOD/WARN/BAD/INFO
@Composable fun EcInlineNotice(text: String, tone: PillTone = PillTone.WARN)
@Composable fun EcDialog(title: String, onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit)
@Composable fun EcSectionTitle(text: String, actionLabel: String? = null, onAction: (() -> Unit)? = null)

/** 录音主按钮：大圆钮 + 录音中动效（儿童 88dp / 成人 72dp） */
@Composable fun RecordButton(recording: Boolean, enabled: Boolean = true,
    isChild: Boolean = LocalIsChild.current, onClick: () -> Unit, label: String? = null)

/** 远程图片（带 Authorization 的接口图 / 无需鉴权的静态图） */
@Composable fun RemoteImage(path: String, contentDescription: String?, modifier: Modifier = Modifier,
    withAuth: Boolean = false, fallback: @Composable () -> Unit = {})
```
- 组件内不做业务请求（`RemoteImage` 例外，走 `AppGraph.container.api`）。
- 所有按钮点击区 ≥ 48dp（儿童 60dp）；文案用安卓习惯中文，不出现"错误/token"等词。

### 4.1 音频（`core/audio`，UI Kit 负责）

```kotlin
/** 内置 9 个音色（/api/tts/voices 线上 404，按 hos MediaService 的常量移植） */
object Voices {
    val ALL: List<TtsVoice>            // TtsVoice(id, labelZh, lang, sample, isEnglish)
    fun find(id: String?): TtsVoice?
}

class AudioController(context: Context) {
    val recording: StateFlow<Boolean>
    val playing: StateFlow<Boolean>
    fun startRecording(prefix: String = "rec"): File     // 失败抛 ApiError(RECORD_FAILED / MIC_UNAVAILABLE)
    fun stopRecording(): RecordingResult                 // RecordingResult(file, durationMs, sizeBytes)
    fun cancelRecording()
    fun playFile(file: File, onComplete: (() -> Unit)? = null)
    fun playBytes(bytes: ByteArray, fileNameHint: String = "tts.wav")   // 写临时文件后播
    fun stopPlayback()
    fun release()
}
```
- **铁律**：录音前必须停播放（否则蓝牙切 HFP 声音变闷）→ `AudioController` 内部保证。
- 录音格式：**m4a / AAC-LC / 16 kHz / 单声道 / 64 kbps**（`MediaRecorder`，`OutputFormat.MPEG_4` + `AudioEncoder.AAC`）。
- 时长 0.6–60s；停止后立即上传；整段上传**不切片**。
- 录音权限由页面用 `rememberMicPermission()`（UI Kit 提供，返回 `granted: Boolean` 和 `request()`），
  第一次点录音时才申请；拒绝 → `ApiErrorCode.MIC_DENIED` 文案 + 去设置引导。

---

## 5. 页面清单（Builder 负责的签名 —— 导航层按此接线）

Tab 根页（`TabNav` 切换；无返回键）：

| 文件 | 签名 | 负责人 |
|---|---|---|
| `ui/page/practice/PracticeScreen.kt` | `@Composable fun PracticeTab()` | Practice |
| `ui/page/flow/FlowScreen.kt` | `@Composable fun FlowTab()` | Flow |
| `ui/page/chat/ChatScenariosScreen.kt` | `@Composable fun ChatScenariosTab()` | Chat |
| `ui/page/story/StoryHomeScreen.kt` | `@Composable fun StoryHomeTab()` | Story |
| `ui/page/account/MeScreen.kt` | `@Composable fun MeTab(onNavigate: (String) -> Unit)` | Account |

二级页（push，均带返回；不要自己读 navController，用传入回调）：

| 路由 | 文件与签名 | 负责人 |
|---|---|---|
| `Routes.SENTENCES` | `@Composable fun SentenceListScreen(onBack: () -> Unit)` | Practice |
| `Routes.FLOW_SUMMARY` | `@Composable fun FlowSummaryScreen(onBack: () -> Unit, onOpenFlowTab: () -> Unit)` | Flow |
| `Routes.CHAT_SESSION` | `@Composable fun ChatSessionScreen(onBack: () -> Unit)` | Chat |
| `Routes.CHAT_HISTORY` | `@Composable fun ChatHistoryScreen(onBack: () -> Unit, onOpenDetail: (String) -> Unit)` | Chat |
| `Routes.CHAT_DETAIL` | `@Composable fun ChatDetailScreen(onBack: () -> Unit)` | Chat |
| `Routes.CHAT_CUSTOM` | `@Composable fun ChatCustomScreen(onBack: () -> Unit)` | Chat |
| `Routes.STORY_RECORD` | `@Composable fun StoryRecordScreen(onBack: () -> Unit, onOpenFlow: () -> Unit)` | Story |
| `Routes.STORY_DETAIL` | `@Composable fun StoryDetailScreen(onBack: () -> Unit, onOpenFlow: () -> Unit, onOpenReview: () -> Unit)` | Story |
| `Routes.STORY_REVIEW` | `@Composable fun StoryReviewScreen(onBack: () -> Unit)` | Story |
| `Routes.DIAGNOSIS` | `@Composable fun DiagnosisScreen(onBack: () -> Unit, onPracticeFocus: (String) -> Unit)` | Stats |
| `Routes.REVIEW` | `@Composable fun ReviewScreen(onBack: () -> Unit)` | Stats |
| `Routes.BLIND_TEST` | `@Composable fun BlindTestScreen(onBack: () -> Unit)` | Stats |
| `Routes.PARENT` | `@Composable fun ParentScreen(onBack: () -> Unit, onOpenFamily: () -> Unit, onOpenSuggestions: () -> Unit)` | Account |
| `Routes.FAMILY` | `@Composable fun FamilyScreen(onBack: () -> Unit)` | Account |
| `Routes.SUGGESTIONS` | `@Composable fun SuggestionsScreen(onBack: () -> Unit)` | Account |
| `Routes.AVATAR` | `@Composable fun AvatarScreen(onBack: () -> Unit)` | Account |
| `Routes.VOICES` | `@Composable fun VoicesScreen(onBack: () -> Unit)` | Account |
| `Routes.HEALTH` | `@Composable fun HealthScreen(onBack: () -> Unit)` | Account |
| `Routes.SETTINGS` | `@Composable fun SettingsScreen(onBack: () -> Unit, onOpenAvatar: () -> Unit, onOpenVoices: () -> Unit, onOpenHealth: () -> Unit, onOpenSuggestions: () -> Unit, onLogout: () -> Unit)` | Account |
| 登录（非路由，AppRoot 直接显示） | `@Composable fun LoginScreen()`（`ui/page/auth/LoginScreen.kt`） | Account |

跨页跳转约定（`NavParams` 写入 → `navigate`）：
- 故事详情「去连读」：`NavParams.flowMaterialId = id; nav(Routes.? )` → 实际上调用 `TabNav.go(Tabs.FLOW)` 并 `onBack()`/`popBackStack()`。
- 对话场景卡：`NavParams.chatSessionId = newSession.id; nav(Routes.CHAT_SESSION)`
- 对话历史项：`NavParams.chatDetailId = id; nav(Routes.CHAT_DETAIL)`
- 故事列表项：`NavParams.storyMaterialId = id; nav(Routes.STORY_DETAIL)`
- 诊断「强化练习」：`NavParams.practiceFocus = token; NavParams.practiceLevel = level; TabNav.go(Tabs.PRACTICE)`
- 跟读页「句子列表」：`nav(Routes.SENTENCES)`

---

## 6. 全局行为规则（所有页面必须遵守）

1. **儿童 vs 成人**（docs/screens.md §0）：
   - 儿童：不显示 IPA、不显示 <60 的数字、不用红色低分、按钮 ≥60dp、正文 19sp、文案更短更口语、不加"错误/失败/权限"字样。
   - 判定统一用 `LocalIsChild.current` 或 `session.isChild`；**渲染层必须做"低分不显示数字"，不能只靠服务端**。
2. **三态**：每个页面都要有 loading / error / empty；error 用 `ErrorBanner` + 重试；空态用 `EmptyState`；loading 用骨架/`LoadingBlock`，不整屏白屏。
3. **禁止静默失败**：任何 catch 都要落到 `UiError` 并展示。
4. **限制**：`session.exceeded == true` 时禁用录音/提交并提示剩余时长（`daily_limit_reached`）。
5. **完成即同步用量**：评测/对话成功后 `session.updateUsage(resp.usage)`（有 usage 时）。
6. **点单词看音标**：所有英文正文用 `WordText`（成人默认开、儿童关；设置项 `show_word_ipa`）。
7. **中文文案**：不用英文占位；emoji 与 hos 保持一致（🌱⭐💪🎤🔊 等）。

---

## 7. 代码风格与验收

- Kotlin 官方风格；**每个文件顶部写中文注释**说明"这是哪个页面/服务、数据来源、与 hos 的对应关系"。
- 不要引入新依赖（现有：Compose、Navigation、Lifecycle、OkHttp、kotlinx.serialization、coroutines、security-crypto）。
- 不要用实验性 API（`@OptIn(ExperimentalMaterial3Api::class)` 只在必要时使用并显式标注）。
- 不写 `TODO` 占位实现：宁可不做某个次要点，也不要在主流程留空壳。
- 每个页面至少覆盖：正常态 + 加载 + 错误 + 空态；关键按钮 loading 与禁用。
- 无法验证编译（本机无 Android SDK）→ **以"结构 + 签名 + import 正确"为验收标准**：
  - 不引用不存在的类/方法；所有跨文件调用以本契约为准；
  - 文件能通过"import 全部存在、类型匹配"的人工检查。
- 完成后在回复里给出：文件清单、实现了哪些功能点、跳过了哪些（及原因）、与其他人的签名依赖。

---

## 8. 与 iOS / 鸿蒙的对齐

- 交互/文案/分数规则以 `hos/docs/screens.md` + `hos/entry/src/main/ets/pages/*` 实现为准（比文档新）。
- 视觉以 `docs/design-tokens.md` + `EcColor/EcFont` 为准。
- 不实现 Web 专属能力（打印页、导出 Markdown 下载可简化为"显示文本 + 复制"）。

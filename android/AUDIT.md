# Android 客户端 · 全项目静态审计（AUDIT）

## ★ 最终状态（02:21 收工）

- **ERROR 0 ｜ WARN 2 ｜ INFO 8**（ERROR 级问题共 **已修复 3 处**：`DictionaryService.kt` 我修、
  `MainActivity.kt` Lead 修、`ui/HomeScreen.kt` Lead 修）。
- **无法编译的原因**：本机没有 Android SDK（也无法安装），仓库缺 `gradlew` / `gradlew.bat` /
  `gradle-wrapper.jar`（本会话文件沙箱禁止 shell 写文件、写工具只支持 UTF-8 文本，二进制 jar 落不了盘；
  README 已给出 `gradle wrapper --gradle-version 8.9` 指引）。因此**全程未执行 `:app:compileDebugKotlin`**。
- **静态检查边界**：本审计是「符号级/调用形态级」检查——import 可解析、符号存在、Service/组件/DTO
  调用参数匹配、Compose scope/嵌套滚动/@OptIn、分层与 token 使用、括号平衡等；
  **不等价于编译器**（无法证明类型推断、智能转换、Compose 语义、运行时行为正确）。最终以
  「补 wrapper + Android Studio/SDK 跑一次 `:app:compileDebugKotlin`」为准。
- **页面级 ERROR：0** → 按“真实 ERROR 才打扰”的约定，没有给 screens-practice / flow / chat /
  story / stats / ui-kit 发过 ERROR 通知。

> **快照时间（最终）：2026-11-04 02:21 (+08:00)**
> 范围：`android/app/src/main/java/top/dreamsearch/englishcoach/` 全部 **110 个 .kt**
> （core 18 + dto 6 + service 8 + ui 78，其中 `ui/page/**` 58 个、`ui/component/**` 12 个）。
> 审计人：数据层（DTO/Service 作者，本轮兼任全项目静态审计）。
>
> **最终复核（02:21）**：页面最后改动停在 02:09:34；Lead 在 02:12–02:13 修了
> `MainActivity`（补 AppRoot import + 删死代码）、`Routes`（删 `diagnosisFocus`），
> 02:20 又补了 `HomeScreen.kt` 的 `import androidx.compose.runtime.saveable.rememberSaveable`。
> 之后对全仓重跑：
> 110 文件 import 可解析 0 失败 / 括号平衡 0 异常 / 112 个 Service 调用点命名参数 0 不匹配 /
> 25 个页面入口签名 0 漂移 / 组件命名参数 0 错 / Compose scope·嵌套滚动·@OptIn 0 问题 /
> 硬编码颜色 0 / `TODO` 0 / **ERROR 0**。

## 0. 审计方法（重要：本机无法编译）

本机**没有 Android SDK、仓库也没有 `gradlew`/`gradlew.bat`/`gradle-wrapper.jar`**（只有
`gradle/wrapper/gradle-wrapper.properties`），因此无法执行 `:app:compileDebugKotlin`。
本次审计用「脚本化符号解析 + 人工抽样」模拟编译器的解析阶段，检查：

| # | 检查项 | 结果 |
|---|---|---|
| 1 | 项目内 `import` 全部可解析（包存在 + 符号存在） | ✅ 110/110 文件 |
| 2 | `kotlinx.serialization` reified 扩展 import 完整性（`encodeToString` / `decodeFromString`） | ✅ 修正 1 处（见 §1） |
| 3 | 页面 → Service 调用：方法名 / 命名参数名 / 位置参数个数（112 个调用点） | ✅ 0 处不匹配 |
| 4 | 页面 → DTO 属性访问（显式类型变量、类型化 lambda 参数、`List<T>.map { it.xxx }`） | ✅ 0 处不存在的属性 |
| 5 | 页面 → `ui/component` 组件调用命名参数（22 个组件） | ✅ 0 处非法命名参数 |
| 6 | 页面入口签名 vs `CONTRACT.md` §5（25 个入口 Composable 逐一比对） | ✅ 全部一致 |
| 7 | `Routes` / `Tabs` / `NavParams` / `TabNav` / `Navigator` / `AppGraph` 成员引用 | ✅ 全部存在 |
| 8 | `SessionState` / `CacheStore` / `AppPrefs` / `AppConfig` / `ApiClient` / `AudioController` 成员引用 | ✅ 全部存在 |
| 9 | `ui/component/**` 反向依赖 `core.net.dto` / `core.service`（契约 §4 禁止） | ✅ 0 处 |
| 10 | 页面/组件里硬编码颜色 `Color(0x…)`（契约 §2.5 要求走 token） | ✅ 0 处 |
| 11 | Compose 作用域：`Modifier.weight` 不在 Row/Column scope | ✅ 0 处 |
| 12 | Compose 嵌套滚动：`LazyColumn` 嵌套 `LazyColumn` / 祖先 `verticalScroll` / `PageScaffold(scrollable=true)` + LazyColumn | ✅ 0 处 |
| 13 | 实验性 API 缺 `@OptIn`（`FlowRow`/`FlowColumn` 共 8 个文件） | ✅ 全部已标 `@OptIn(ExperimentalLayoutApi::class)` |
| 14 | 重复顶层声明 | ✅ 0 处非法（3 组同名均为 `private`，文件作用域合法，见 §3） |
| 15 | `private` 顶层符号被其它文件 import | ✅ 0 处 |
| 16 | Design token 成员引用（`EcColor`/`EcSpace`/`EcRadius`/`EcFont`/`EcButtonSize`） | ✅ 全部存在 |
| 17 | VM 层 import Compose（分层违规） | ✅ 0 处 |
| 18 | 挂起 Service 调用出现在非协程/非 suspend 上下文 | ✅ 0 处 |
| 19 | 大括号/圆括号/方括号平衡（剔除字符串与注释） | ✅ 110/110 文件平衡 |
| 20 | `TODO`/`FIXME`/空实现桩 | ✅ 0 处（“占位图/占位文案”均为正常 UI 兜底） |

> 结论（最终 02:21）：**ERROR 0 ｜ WARN 2 ｜ INFO 8**（ERROR 级问题共已修复 3 处：§1.1/§1.2/§1.3）。
> **页面级 ERROR：0 条**（签名/DTO/组件调用/VM 引用全部匹配）——因此本轮没有给
> screens-practice / flow / chat / story / stats / ui-kit 发过打扰消息，符合“真实 ERROR 才通知”的约定。

---

## 1. ERROR

### 1.1 [已修复 by Lead @02:12] `MainActivity.kt:23` 缺 `AppRoot` 的 import

- 文件：`app/src/main/java/top/dreamsearch/englishcoach/MainActivity.kt`
- 原问题：`MainActivity` 的 package 是 `top.dreamsearch.englishcoach`，调用 `AppRoot()` 时
  只 import 了 `android.os.Bundle` / `androidx.activity.*` / `androidx.compose.runtime.Composable`；
  `AppRoot` 在 `top.dreamsearch.englishcoach.ui` 包 → unresolved reference，app 模块无法编译。
- 处理：**Lead 已于 02:12 修复**——补 `import top.dreamsearch.englishcoach.ui.AppRoot`
  （并顺手删除了死代码 `AppRootPlaceholder` 与随之无用的 `Composable` import，即原 WARN W2）。
- 复核：当前 `MainActivity` import 列表含该行，文件括号/符号检查通过；此 ERROR **已关闭**。

### 1.2 [已修复 by 数据层 @02:0x] `core/service/DictionaryService.kt:36` 缺 `kotlinx.serialization.decodeFromString`

- 原问题：`EcJson.decodeFromString<WordIpaDto>(raw.text)` 用的是 reified 扩展函数，
  必须 `import kotlinx.serialization.decodeFromString`；文件只 import 了 `SerialName/Serializable`。
- 处理：**已在数据层作用域内补 import**（`core/service/DictionaryService.kt:5`）。
- 全仓复核：其余 28 处 `encodeToString(...)` / `decodeFromString<...>` 的 import 均完整
  （`core/net/Json.kt`、`core/net/ApiClient.kt` 由 Lead 修复；
  `core/session/CredentialStore.kt` 用 `encodeToString(serializer, value)` 成员形式，无需 import）。

### 1.3 [已修复 by Lead @02:20] `ui/HomeScreen.kt:54` 缺 `rememberSaveable` import

- 文件：`app/src/main/java/top/dreamsearch/englishcoach/ui/HomeScreen.kt`
- 原问题（02:18 复核发现，02:13 改动新引入）：
  ```kotlin
  var currentTab by rememberSaveable { mutableIntStateOf(Tabs.PRACTICE) }
  ```
  文件 import 里只有 `androidx.compose.runtime.remember`，没有 `rememberSaveable`
  → `unresolved reference: rememberSaveable`，整个 app 模块无法编译。
- 处理：**Lead 已于 02:20 补上**
  `import androidx.compose.runtime.saveable.rememberSaveable`（`remember` 仍被 `HomeTabBar` 的
  `remember { MutableInteractionSource() }` 使用，两个 import 都保留、无 unused）。
- 复核：`HomeScreen.kt:25` 已有该 import，第 55 行 `rememberSaveable` 可解析；
  全仓最终复核 **ERROR 0**。此 ERROR **已关闭**。

---

## 2. WARN（不阻塞编译，建议排期修）

| # | 文件:行 | 问题 | 建议 |
|---|---|---|---|
| W1 | `ui/HomeScreen.kt:58-61` | Composable 内直接 `runCatching { AppGraph.container.practice.health() }` 发业务请求（契约 §4：组件内不做业务请求；页面层也不宜）。功能/编译均无问题，属分层建议 | 抽到 `HomeViewModel`（`init { loadHealth() }`），`voiceDegraded` 由 StateFlow 驱动；或明确接受为「启动探活」并在注释标注（Lead 已知悉，暂保留） |
| W2 | `ui/page/stats/BlindTestScreen.kt:133` / `BlindTestViewModel.kt:111+` | 三态齐全，但「继续/开始」按钮依赖 `inProgress` 快照；首次 `load()` 失败时只显示 ErrorBanner，`EmptyState` 分支不可达（功能可接受，仅提示） | 无需改动；如要更严，`error==null && !loadedOnce` 时给骨架 |

> 备注：W2 属于“审阅建议”，不算缺陷；当前三态覆盖见 §5。
> 原 W2（`MainActivity.AppRootPlaceholder` 死代码）与 W3（`NavParams.diagnosisFocus` 未使用）
> **均已由 Lead 于 02:12–02:13 修复**，不再计入 WARN。

---

## 3. INFO（记录，不要求改）

| # | 位置 | 说明 |
|---|---|---|
| I1 | `ui/page/account/{FamilyScreen,ParentScreen}.kt`、`{ParentScreen,SettingsScreen}.kt`、`ui/page/story/{StoryRecordScreen,StoryReviewScreen}.kt` | 同包内 3 组同名顶层 `private fun`（`MemberCard`、`EntriesCard`、`recordButtonLabel`）——`private` 顶层声明是**文件作用域**，Kotlin 不冲突，可编译；仅提示未来可合并到公共文件 |
| I2 | `ui/component/PageScaffold.kt:49-56` | 契约 §4 的签名没有 `scrollable` 参数，UI Kit 额外加了（自带 KDoc 说明）。页面全部用默认 `false`，与 LazyColumn 无冲突 |
| I3 | `ui/page/stats/BlindTestScreen.kt` / `BlindTestViewModel.kt` | 盲测实现**已按 Lead 修正**：`PracticeService.evaluate(audio, sentenceId, referenceText, durationMs, blindTestId)`（同步 `POST /attempts`）+ 每 2s 轮询 `GET /blind-tests` 只更新计数；`session.exceeded` 前置禁用录音/开始。注释与实际实现一致 |
| I4 | `ui/page/chat/ChatSessionViewModel.kt:1113` | pron 轮询 = hos 原样 `PRON_POLL_DELAYS = [700,1100,1500,1900]ms`（Lead 已说明两种都可） |
| I5 | `core/service/AuthService.kt:40` | `AuthService(api)` 构造签名拿不到 `TokenStore`，运行期取 `AppGraph.container.tokenStore`（Lead 已批准保留，ADR-0002 行为一致） |
| I6 | `android/` 根目录 | **Gradle wrapper 二进制缺失是环境限制**：`gradlew`、`gradlew.bat`、`gradle/wrapper/gradle-wrapper.jar` 因本会话沙箱（禁止 shell 写文件、写工具只支持 UTF-8 文本）无法落盘，`gradle-wrapper.properties` 已保留。README 已改为明确指引（Android Studio 用本地 Gradle 8.9，或先执行 `gradle wrapper --gradle-version 8.9` 生成）→ 记录为「已知限制 + 文档已指引」，不算项目缺陷 |
| I7 | `ui/HomeScreen.kt:54` | Lead 已把 `currentTab` 从 `remember` 改为 `rememberSaveable`（进程重建后保留 Tab，行为改进）；需补一条 import（见 §1.3） |
| I8 | `ui/nav/Routes.kt:76` + `ui/page/stats/DiagnosisViewModel.kt:194-197` | `NavParams.diagnosisAttemptIds` 是**在用**的跨页参数：连读汇总页写入 → 诊断页 `batch` scope 读取后置 null（Lead 说明保留）；旧的未使用字段 `diagnosisFocus` 已删除 |

---

## 4. 跨文件签名核对（页面 → `core/service`，112 个调用点，0 处不匹配）

> 说明：下表是**当前快照的全部调用点**（`文件:行`）。`✅` = 方法存在、参数名/个数与 Service 真实签名一致。
> 校验方式：脚本按 Kotlin 语法解析调用实参（区分命名参数/位置参数、跳过字符串与 lambda 体），逐一对签名。

| Service 方法（真实签名要点） | 页面调用点 | 结果 |
|---|---|---|
| `AuthService.login/me/revoke` | （由 `SessionStore`/`AppRoot` 调用，页面不直连） | ✅ |
| `PracticeService.sentences(level, focus="")` | PracticeViewModel:180、SentenceListViewModel:100、FlowViewModel:321,328、BlindTestViewModel:352 | ✅ |
| `PracticeService.tts(text, rate, voice=null, format="wav")` | PracticeViewModel:336、ChatSessionViewModel:691,759、FlowSummaryViewModel:199,202、FlowViewModel:1150、StoryDetailViewModel:391,420、VoicesViewModel:121 | ✅ |
| `PracticeService.attempts(limit=20)` | PracticeViewModel:680、DiagnosisViewModel:190、BlindTestViewModel:346 | ✅ |
| `PracticeService.audio(audioId)` | PracticeViewModel:383 | ✅ |
| `PracticeService.evaluate(audio, sentenceId, referenceText, durationMs=0, blindTestId=null, mode="scripted")` | PracticeViewModel:541、BlindTestViewModel:239 | ✅ |
| `PracticeService.retryAttempt(attemptId)` | PracticeViewModel:587 | ✅ |
| `PracticeService.health()` | HomeScreen:59、FlowViewModel:1286、HealthViewModel:81、LoginViewModel:158、MeViewModel:67、SettingsViewModel:223 | ✅ |
| `PracticeService.warmup(texts, rate="normal")` | PracticeViewModel:241 | ✅ |
| `FlowService.materialsPage(limit=50)` | FlowViewModel:408 | ✅ |
| `FlowService.materialDetail(id)` | FlowViewModel:423,462,788 | ✅ |
| `FlowService.createPage(title, text, source="text")` | FlowViewModel:704、FlowSummaryViewModel:176 | ✅ |
| `FlowService.updatePage(id, title=null, text=null)` | FlowViewModel:694 | ✅ |
| `FlowService.deletePage(id)` | FlowViewModel:488 | ✅ |
| `FlowService.ocr(imageBytes, fileName)` | FlowViewModel:587 | ✅ |
| `FlowService.submitAsync(audio, sentenceId, referenceText, blindTestId=null, source="custom", materialId=null, durationMs=0)` | FlowViewModel:979 | ✅ |
| `FlowService.status(ids)` | FlowViewModel:193 | ✅ |
| `FlowService.diagnosisBatch(attemptIds)` | FlowSummaryViewModel:75 | ✅ |
| `ChatService.scenarios(includeChild=false)` | ChatScenariosViewModel:97、ChatCustomViewModel:76 | ✅ |
| `ChatService.createScenario(title, titleZh, settingZh, rolePrompt, openingLine, level, audience)` | ChatCustomViewModel:173 | ✅ |
| `ChatService.updateScenario(id, title, titleZh, settingZh, rolePrompt, openingLine, level)` | ChatCustomViewModel:170 | ✅ |
| `ChatService.deleteScenario(id)` | ChatCustomViewModel:208 | ✅ |
| `ChatService.createSession(scenarioId)` | ChatScenariosViewModel:142、ChatSessionViewModel:608 | ✅ |
| `ChatService.turn(sessionId, audio: ByteArray?, text)` | ChatSessionViewModel:444 | ✅ |
| `ChatService.messages(sessionId)` | ChatSessionViewModel:279,506 | ✅ |
| `ChatService.end(sessionId)` | ChatSessionViewModel:588 | ✅ |
| `ChatService.audioStatus(sessionId)` | ChatSessionViewModel:828 | ✅ |
| `ChatService.audio(sessionId, force=false): ByteArray?` | ChatSessionViewModel:832,859,909 | ✅ |
| `ChatService.sessions(limit=20)` | ChatHistoryViewModel:44 | ✅ |
| `ChatService.sessionDetail(sessionId)` | ChatSessionViewModel:261 | ✅ |
| `ChatService.messageAudio(audioUrl)` | ChatSessionViewModel:777 | ✅ |
| `ChatService.asr(audio, language="en", provider=null)` | ChatSessionViewModel:376 | ✅ |
| `StoryService.materials(kind="story", limit=50, offset=0)` | StoryHomeViewModel:82 | ✅ |
| `StoryService.materialDetail(id)` | StoryDetailViewModel:140、StoryReviewViewModel:118 | ✅ |
| `StoryService.createMaterial(title, text, sourceZh, level, kind="story")` | StoryRecordViewModel:408 | ✅ |
| `StoryService.renameMaterial(id, title)` | StoryDetailViewModel:534 | ✅ |
| `StoryService.deleteMaterial(id)` | StoryDetailViewModel:559 | ✅ |
| `StoryService.asr(audio, language="zh-CN", provider=null)` | StoryRecordViewModel:210（`"zh-CN"`）、StoryReviewViewModel:228（`"en-US"`） | ✅ |
| `StoryService.rewrite(textZh, level, maxSentences, tense=null, useWeakPhonemes=false)` | StoryRecordViewModel:257 | ✅ |
| `StoryService.retell(materialId, storySentences, transcript, level)` | StoryReviewViewModel:267 | ✅ |
| `StoryService.illustrate(materialId, force=false)` | StoryDetailViewModel:484、StoryRecordViewModel:435 | ✅ |
| `StoryService.audioStatus(materialId)` | StoryDetailViewModel:230 | ✅ |
| `StoryService.storyAudio(materialId, force=false): ByteArray?` | StoryDetailViewModel:311,361 | ✅ |
| `AccountService.settings()` | AvatarViewModel:97、SettingsViewModel:110、VoicesViewModel:77、StoryRecordViewModel:500 | ✅ |
| `AccountService.patchSettings(body)` | SettingsViewModel:170、VoicesViewModel:162 | ✅ |
| `AccountService.familyMembers()` | FamilyViewModel:81 | ✅ |
| `AccountService.createMember(body)` | FamilyViewModel:153 | ✅ |
| `AccountService.updateMember(memberId, body)` | FamilyViewModel:232 | ✅ |
| `AccountService.resetMemberPassword(memberId, newPassword)` | FamilyViewModel:281、SettingsViewModel:375 | ✅ |
| `AccountService.parentSummary()` | ParentViewModel:91 | ✅ |
| `AccountService.submitSuggestion(category, content, page, context)` | SuggestionsViewModel:106 | ✅ |
| `AccountService.listSuggestions(status, limit, offset)` | SuggestionsViewModel:139 | ✅ |
| `AccountService.patchSuggestionStatus(suggestionId, status)` | SuggestionsViewModel:167 | ✅ |
| `AccountService.exportSuggestionsMarkdown(status="")` | SuggestionsViewModel:186 | ✅ |
| `AccountService.avatarPresets()` | AvatarViewModel:74 | ✅ |
| `AccountService.avatar()` | AvatarViewModel:84 | ✅ |
| `AccountService.selectAvatar(presetId, style)` | AvatarViewModel:127 | ✅ |
| `AccountService.updateAvatarDescription(desc)` | AvatarViewModel:154 | ✅ |
| `AccountService.clearAvatar()` | AvatarViewModel:176 | ✅ |
| `StatsService.diagnosis(scope, days, attemptId, attemptIds)` | DiagnosisViewModel:151,166,174,181 | ✅ |
| `StatsService.review(limit=20)` | ReviewViewModel:70 | ✅ |
| `StatsService.gradeReview(cardId, grade: String)` | ReviewViewModel:113 | ✅ |
| `StatsService.blindTests(userId="")` | BlindTestViewModel:111,144,159,201,285 | ✅ |
| `StatsService.startBlindTest()` | BlindTestViewModel:131 | ✅ |
| `StatsService.finishBlindTest(blindTestId)` | BlindTestViewModel:189 | ✅ |
| `StatsService.healthFull(force=false)` | StoryDetailViewModel:180、StoryRecordViewModel:511 | ✅ |
| `DictionaryService.wordIpa(word): String?` | WordText.kt:32,178 | ✅ |

**不匹配项：0。** 页面组对 DTO 属性的使用也已核对：显式 DTO 变量、类型化 lambda 参数、
`List<Dto>.map { it.prop }` 三类访问均未出现不存在的属性；也没有把 `@SerialName` 的
snake_case 名当 Kotlin 属性用（全仓 0 处 snake_case 属性访问）。

---

## 5. 页面入口签名 vs `CONTRACT.md` §5（全部一致）

| 路由 | 文件 | 实际签名 | 契约 |
|---|---|---|---|
| Tab 根页 | `ui/page/practice/PracticeScreen.kt` | `PracticeTab()` | ✅ |
| Tab 根页 | `ui/page/flow/FlowScreen.kt` | `FlowTab()` | ✅ |
| Tab 根页 | `ui/page/chat/ChatScenariosScreen.kt` | `ChatScenariosTab()` | ✅ |
| Tab 根页 | `ui/page/story/StoryHomeScreen.kt` | `StoryHomeTab()` | ✅ |
| Tab 根页 | `ui/page/account/MeScreen.kt` | `MeTab(onNavigate: (String) -> Unit)` | ✅ |
| SENTENCES | `ui/page/practice/SentenceListScreen.kt` | `SentenceListScreen(onBack)` | ✅ |
| FLOW_SUMMARY | `ui/page/flow/FlowSummaryScreen.kt` | `FlowSummaryScreen(onBack, onOpenFlowTab)` | ✅ |
| CHAT_SESSION | `ui/page/chat/ChatSessionScreen.kt` | `ChatSessionScreen(onBack)` | ✅ |
| CHAT_HISTORY | `ui/page/chat/ChatHistoryScreen.kt` | `ChatHistoryScreen(onBack, onOpenDetail: (String) -> Unit)` | ✅ |
| CHAT_DETAIL | `ui/page/chat/ChatDetailScreen.kt` | `ChatDetailScreen(onBack)` | ✅ |
| CHAT_CUSTOM | `ui/page/chat/ChatCustomScreen.kt` | `ChatCustomScreen(onBack)` | ✅ |
| STORY_RECORD | `ui/page/story/StoryRecordScreen.kt` | `StoryRecordScreen(onBack, onOpenFlow)` | ✅ |
| STORY_DETAIL | `ui/page/story/StoryDetailScreen.kt` | `StoryDetailScreen(onBack, onOpenFlow, onOpenReview)` | ✅ |
| STORY_REVIEW | `ui/page/story/StoryReviewScreen.kt` | `StoryReviewScreen(onBack)` | ✅ |
| DIAGNOSIS | `ui/page/stats/DiagnosisScreen.kt` | `DiagnosisScreen(onBack, onPracticeFocus: (String) -> Unit)` | ✅ |
| REVIEW | `ui/page/stats/ReviewScreen.kt` | `ReviewScreen(onBack)` | ✅ |
| BLIND_TEST | `ui/page/stats/BlindTestScreen.kt` | `BlindTestScreen(onBack)` | ✅ |
| PARENT | `ui/page/account/ParentScreen.kt` | `ParentScreen(onBack, onOpenFamily, onOpenSuggestions)` | ✅ |
| FAMILY | `ui/page/account/FamilyScreen.kt` | `FamilyScreen(onBack)` | ✅ |
| SUGGESTIONS | `ui/page/account/SuggestionsScreen.kt` | `SuggestionsScreen(onBack)` | ✅ |
| AVATAR | `ui/page/account/AvatarScreen.kt` | `AvatarScreen(onBack)` | ✅ |
| VOICES | `ui/page/account/VoicesScreen.kt` | `VoicesScreen(onBack)` | ✅ |
| HEALTH | `ui/page/account/HealthScreen.kt` | `HealthScreen(onBack)` | ✅ |
| SETTINGS | `ui/page/account/SettingsScreen.kt` | `SettingsScreen(onBack, onOpenAvatar, onOpenVoices, onOpenHealth, onOpenSuggestions, onLogout)` | ✅ |
| 登录 | `ui/page/auth/LoginScreen.kt` | `LoginScreen()` | ✅ |

`ui/nav/AppNavHost.kt` 20 个 `composable(...)` 对上述页面的调用实参与声明完全匹配；
`Routes` 中除 5 个 Tab 常量外的 20 个路由全部接线；`HomeScreen` 5 个 Tab 调用参数匹配。
全部 26 个页面均使用
`viewModel(factory = remember { vmFactory { XxxViewModel(AppGraph.container) } })` +
`collectAsStateWithLifecycle()`（26/26），无页面直接 new VM。

三态覆盖（脚本快照，`loading/error/empty` 仅表示对应组件是否出现在该 Screen）：

| Screen | loading | error | empty |
|---|---|---|---|
| Practice / SentenceList / Flow / FlowSummary | ✅ | ✅ | ✅ |
| ChatScenarios / ChatSession / ChatHistory / ChatDetail / ChatCustom | ✅ | ✅ | ✅ / ✅ / ✅ / ✅ / ⚠️(表单页无空态，合理) |
| StoryHome / StoryDetail / StoryRecord / StoryReview | ✅ | ✅ | ✅ / ⚠️(详情页空态=错误态) / ⚠️(表单) / ⚠️(详情页) |
| Diagnosis / Review / BlindTest | ✅ | ✅ | ✅ |
| Diagnostics 之外的 Account 页 | ✅(Me/Login 用按钮 loading) | ✅ | ⚠️(设置/头像/健康为固定内容，无空态属合理) |

⚠️ 项为“设计上可接受”，已由 UI 层用 ErrorBanner/按钮 loading 覆盖；若验收要求严格三态，请各页负责人按 §6
规则补 `EmptyState`。

---

## 6. 无法静态验证 / 风险提示（需真机或 SDK）

1. **类型推断细节**：Kotlin 泛型、智能转换、默认参数重载解析等只能靠编译器确认；本审计只保证“符号存在 + 形态匹配”。
2. **Compose 语义**：重排/重组副作用、`LaunchedEffect` key 正确性、动画、`Scaffold` inset 叠加已人工抽查主要页面，但无法保证全部无 warning。
3. **服务端真实响应**：DTO 默认值策略（缺字段不炸）已按 `explicitNulls=false` / `coerceInputValues` 设计，但真实线上形状未抓到。
4. **运行时行为**：录音/播放/轮询生命周期、跨页参数时序、音频缓存清理等需真机验证（各页 VM 已实现 `onCleared`/`DisposableEffect` 兜底）。
5. **构建链**：仓库缺 Gradle wrapper 脚本；拿到 SDK 后建议先补 wrapper，再跑
   `./gradlew :app:compileDebugKotlin` 做最终编译验证。
6. 本文档是**静态快照**：**02:21 为最终复核/收工时间**（页面最后改动 02:09:34；
   Lead 的修复到 02:20）。若之后还有改动，请以最终文件为准并重跑本审计；建议拿 SDK 后跑
   `:app:compileDebugKotlin` 做一次真编译收口（先补 wrapper，见 §3 I6）。

---

## 7. 负责人通知记录

| 对象 | 内容 | 时间 |
|---|---|---|
| Lead | `MainActivity.kt` 缺 `AppRoot` import（ERROR，1 行修复）；AUDIT.md 路径 | 02:10 |
| Lead | 复核：MainActivity 已修、`diagnosisFocus` 已删、wrapper 限制已知悉；发现 02:13 的 `rememberSaveable` 新 ERROR（§1.3，1 行 import） | 02:16 |
| Lead | 最终复核完成：112 调用点 0 不匹配、25 页面签名 0 漂移、组件/Compose 检查 0 问题；最终 ERROR 1 条（HomeScreen import，待 Lead 修） | 02:18 |
| Lead | HomeScreen 的 `rememberSaveable` import 已由 Lead 修复；02:21 全仓复跑 **ERROR 0**，AUDIT 标记「最终」 | 02:21 |
| screens-practice / screens-flow / screens-chat / screens-story / screens-stats / ui-kit | 全程**无页面级 ERROR**（签名/DTO/组件调用/VM 方法引用全部匹配），不发打扰消息 | — |

---

## 8. 本轮修复清单（跨负责人汇总，最终 02:21：ERROR 0）

| 文件 | 修复人 | 改动 | 状态 |
|---|---|---|---|
| `core/service/DictionaryService.kt` | 数据层 | 补 `import kotlinx.serialization.decodeFromString`（§1.2） | ✅ 已修 |
| `MainActivity.kt` | Lead @02:12 | 补 `import top.dreamsearch.englishcoach.ui.AppRoot`；删 `AppRootPlaceholder` 死代码 + 无用 `Composable` import（§1.1 / 原 W2） | ✅ 已修 |
| `ui/nav/Routes.kt` | Lead @02:13 | 删除未使用的 `NavParams.diagnosisFocus`；保留 `diagnosisAttemptIds`（stats 页在用，§3 I7/I8） | ✅ 已修 |
| `ui/HomeScreen.kt` | Lead @02:13 / @02:20 | `currentTab` 改用 `rememberSaveable`（行为改进）+ 补 `import androidx.compose.runtime.saveable.rememberSaveable`（§1.3） | ✅ 已修 |

> **ERROR 级修复共 3 处**（DictionaryService / MainActivity / HomeScreen），最终复核 ERROR 0。
> 数据层本轮只改了自己的文件（`core/service/DictionaryService.kt`），页面文件一行未动；
> 页面级问题只记录不修改，符合“只能改自己作用域”的约定。
> 未执行任何 git 操作（遵守“不要执行 git commit”）。

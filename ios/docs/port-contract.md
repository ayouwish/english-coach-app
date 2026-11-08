# iOS 移植契约（Port Contract）· v1 — 2026-11-04

> **本文件是并行开发的唯一接口约定。** 所有 agent 的代码必须在类型名、方法签名、文件路径上与本文一致；
> 不一致的代码在集成阶段会被静态校验打回。
>
> 基准：`hos/`（鸿蒙实现，功能事实来源）+ `docs/`（后端/产品事实）+ `ios/README.md`、`ios/docs/*`（iOS 既有设计）。
> 参考实现：`android/`（Kotlin 全量移植，页面级差异写在 `docs/android-feature-list.md` §4）。

---

## 0. 本轮已拍板的决策

| 项 | 决策 | 备注 |
| --- | --- | --- |
| 最低系统 | **iOS 26.0** | 用户本轮确认；与 `docs/adr/0002` 一致。可用 iOS 26 SDK 全部 API，不写 `#available` 旧版兼容分支 |
| 语言/SDK | Swift 6（严格并发 `complete`）、SwiftUI、Observation | 见 `project.yml` |
| 依赖 | **零第三方** | 系统框架：Foundation / SwiftUI / AVFoundation / Charts / PhotosUI / OSLog / Security |
| 范围 | **全量对齐 HOS**：9 个功能域、28 个页面 | 见 §4 |
| 工程 | XcodeGen（`project.yml`），源码根 `ios/EnglishCoach/` | 不提交 `.xcodeproj` |
| 验收 | **静态校验**（本机无 macOS/Xcode，不能编译） | 见 §6；任何文档不得声称"已编译通过" |

### 0.1 本机环境硬约束（每个 agent 必读）

- 操作系统是 **Windows**，**没有 macOS / Xcode / Swift 工具链**。写不了 `.xcodeproj`，也跑不了 `swift build`。
- **沙箱限制**：仓库目录 `english-coach-app/**` 内，shell 命令**不能写文件**（`Set-Content`、`New-Item`、`python` 写盘、`git add` 全部会被拒绝）。
  ⇒ **所有文件改动只能通过 `write` / `edit` 工具**。shell 只用于**只读**查看、`python` 读文件打印到 stdout、`git status/diff/log` 等只读命令。
- 因此：不要写"生成脚本 → 运行脚本产出源码"的流程；源码必须逐文件用 `write` 落地。

---

## 1. 最终文件布局与所有权

源码根：`ios/EnglishCoach/`。顶层 `ios/{App,Core,Features,Resources,Config}/` 是设计期空占位（只有 `.gitkeep`），**不参与构建、不要往里写**。

```
ios/EnglishCoach/
  App/
    EnglishCoachApp.swift        @main + Environment 注入
    AppEnvironment.swift         组合根（服务装配、session、缓存），@MainActor @Observable
    AppRoot.swift                启动三态 → 登录 / HomeTabs
    RootTabView.swift            5 Tab：跟读/连读/对话/故事/我的 + voice 降级横幅
    Navigation/
      AppRoute.swift             路由枚举（§4 表）
      AppRouter.swift            @Observable 路由栈封装
  Core/
    AppConfig.swift              baseURL / 演示账号 / 版本号（UserDefaults）
    Crypto/Hashing.swift         SHA-256 缓存键
    Error/
      UIMessage.swift            用户可见文案模型
      ErrorMapper.swift          错误 → 文案（成人/儿童两套）
    Networking/
      APITransport.swift         已有：HTTPClient + Bearer + 401 单飞刷新重放
      APIError.swift             已有：错误枚举 + ServerErrorCode
      Endpoint.swift             Endpoint 类型（现 Endpoints.swift，A1 改名整理）
      MultipartBody.swift        multipart 构造（从 Endpoints.swift 拆出）
      DTO/                       网络 DTO（一个域一个文件，全部 `...DTO` 后缀）
      Services/                  9 个域 Service（每域一个文件）
    Session/
      TokenStore.swift           actor，Keychain 存取（已有）
      TokenRefresher.swift       actor，单飞刷新（已有）
      SessionStore.swift         @MainActor @Observable：phase/user/capabilities/signIn/signOut/restore
      UserProfile.swift          已登录用户模型（已有，保留类型名）
      RoleCapabilities.swift     角色能力开关（已有 Theme.swift 里，A4 抽出本文件）
      CredentialStore.swift      记住邮箱/密码（默认关）
      KeychainStore.swift        Keychain 低层封装
    Audio/
      AudioSessionController.swift  AVAudioSession category/active 串行切换
      MicPermission.swift           权限三态 + 去设置
      VoiceRecorder.swift           录音（16k/mono/AAC 65kbps m4a，60s 上限，电平，静音检测）
      AudioPlayer.swift             播放（文件/字节），完成回调，停止，进度
      AudioCoordinator.swift        @MainActor 门面：录音/播放互斥、mode、level
    Storage/
      CacheLocator.swift            目录（TTS/Images/Recordings/Cache 根）
      DiskCache.swift               泛型 JSON 磁盘缓存（TTL）
      AudioCache.swift              TTS 字节 LRU（200MB）
      ImageCache.swift              插画/形象 LRU（100MB）
      RecordingCache.swift          录音副本（7 天/300MB）
      CorpusRepository.swift        /sentences 快照（24h）合并请求
      CacheJanitor.swift            启动清理 + 用户级清理
    Content/
      PhonemeHints.swift            音素提示表（中文文案，儿童/成人两套）
      AccountPrefs.swift            账号偏好（tts_voice/tts_rate/show_word_ipa）
      CapabilityCache.swift         /health capabilities 进程内缓存
    DesignSystem/
      Tokens/Tokens.swift           间距/圆角/字号/阴影/颜色（已有，扩展）
      Tokens/Typography.swift       字体（已有，扩展）
      Tokens/Theme.swift            主题 + RoleCapabilities Environment（已有）
      Components/*.swift            组件库（§3.12）
  Features/
    Auth/          LoginView, AuthViewModel
    Practice/      跟读：句子列表/句子详情/结果页/历史/图表组件
    Flow/          连读：setup/running/汇总
    Chat/          对话：场景列表/会话/历史/详情/自定义场景
    Story/         故事：列表/讲述/详情/复述/插画
    BlindTest/     盲测（一页闭环）
    Report/        诊断/错音本/成长趋势
    Parent/        家长面板/家庭成员/建议箱/形象/音色/服务状态
    Settings/      设置
    Home/          MePage（我的）
  Resources/
    Info.plist, PrivacyInfo.xcprivacy, Assets.xcassets, Localizable.xcstrings
```

### 1.1 所有权（写入范围，互不重叠）

| Agent | 可写路径 | 说明 |
| --- | --- | --- |
| **A1 core-net** | `Core/Networking/**`, `Core/Crypto/**`, `Core/AppConfig.swift` | 网络基座、DTO、Auth/Account Service |
| **A2 core-practice-stats** | `Core/Networking/DTO/PracticeDTO.swift`, `FlowDTO.swift`, `StatsDTO.swift`, `Core/Networking/Services/{Practice,Flow,Stats,Dictionary,Media}Service.swift` | 跟读/连读/统计域 |
| **A3 core-chat-story** | `Core/Networking/DTO/{ChatDTO,StoryDTO}.swift`, `Core/Networking/Services/{Chat,Story}Service.swift` | 对话/故事域 |
| **A4 core-session-storage** | `Core/Session/**`, `Core/Storage/**`, `Core/Content/**`, `Core/Error/**`, `Core/Audio/**` | 会话、缓存、音素表、错误映射、音频 |
| **A5 core-design** | `Core/DesignSystem/**`, `Features/Shared/**` | 设计令牌与组件库、共享图表/格式化 |
| **A6 ios-verify** | `ios/tools/**`, `ios/project.yml`, `Resources/Info.plist`, `Resources/PrivacyInfo.xcprivacy`, `EnglishCoach/Resources/Assets.xcassets/**`, `ios/.gitignore` | 静态校验脚本、工程描述、资源 |

> `Core/Audio` 归 A4（音频生态与存储/会话同属"设备能力"，避免 A4/A5 交叉）。

---

## 2. 通用编码规范（强制）

1. **分层**：`App → Features → Core`。`Features/**` 内**禁止**出现 `URLSession` / `URLRequest`（读能力不足时扩展 Service）。`DesignSystem` / `Features/Shared` **禁止** import Networking 类型。`Core/Audio`、`Core/Storage` 禁止引用 `Features`。
2. **并发**：`View`/`*Store`(`*ViewModel`) 用 `@MainActor @Observable final class`；DTO 全部 `struct: Decodable, Sendable`；`TokenStore`/`TokenRefresher`/`DiskCache`/`CorpusRepository` 用 `actor`；Service 用 `struct XxxService: Sendable`（无内部可变状态）。
3. **命名**：类型 `UpperCamelCase`，文件名 = 主类型名（一个文件一个主类型 + 私有辅助类型）。网络 DTO 一律 `XxxDTO` 后缀；页面态模型放 Feature 内、不带 DTO 后缀。
4. **文案**：所有用户可见字符串为**简体中文**；网络/业务错误文案**只能**来自 `ErrorMapper`（页面不许自造"网络错误"文案）。儿童模式文案来自 `RoleCapabilities.isChild`。
5. **儿童模式**：只通过 `RoleCapabilities`（`canSeeIPA`、`showsNumericScore`、`minTapTarget`、`usesEncouragementOnly`）判断；**禁止**页面里写 `user.role == .child`。
6. **日志**：`Logger(subsystem: "top.dreamsearch.english.coach", category: ...)`；禁止 `print`；禁止打印 token/密码/邮箱/音频内容。**禁止** `TODO`/`FIXME`/`fatalError` 进提交（未实现项写进 `ios/README.md` §0.5）。
7. **可用性**：目标 iOS 26，直接用最新 API（`@Observable`、`NavigationStack`、`Charts`、`PhotosPicker`、`.scrollEdgeEffect` 等）。**不要**写 `if #available` 兼容分支。
8. **防御式解码**：DTO 字段按"服务端可能缺失/类型漂移"处理：可选 + 使用处兜底；数组字段用 `decodeFlexibleStringArray` 之类的容错（见既有 `DTOs.swift` 的 `decodeStringArray`）。解码统一走 `HTTPClient.decode`（`convertFromSnakeCase`）。
   **JSON 编解码唯一入口是 `ECJSON`（`Core/Networking/JSONCoding.swift`）**：请求体一律 `try ECJSON.encode(body, path: "xxx")`（`convertToSnakeCase`），禁止裸 `JSONEncoder().encode`；时间字符串用 `ECJSON.date(from:)` / `ECJSON.relativeText(from:)`。multipart 字段名手写 snake_case。
9. **视图体积**：单文件 > 700 行时拆成 `XxxView.swift` + `Components/XxxSubviews.swift`；页面必须有 loading / empty / error / 权限 四态（用 `StateViews.swift` 的组件）。
10. **无障碍**：交互控件加 `.accessibilityLabel`；按钮最小点击区 44pt（儿童 56pt）。

---

## 3. Core 公共 API（逐字实现，签名不得改）

> `APITransport`（已有）是唯一网络出口：
> `func send<T: Decodable & Sendable>(_ endpoint: Endpoint, as: T.Type) async throws -> T`
> `func sendData(_ endpoint: Endpoint) async throws -> Data`
> Service 内部**自己构造 `Endpoint`**（`Endpoint(method:path:query:headers:body:timeout:authPolicy:)`），不要把端点工厂堆进 `Endpoint.swift`（避免并行冲突；`Endpoint.swift` 只保留类型与 multipart 构造）。

### 3.0 共享 DTO —`Core/Networking/DTO/SharedDTO.swift`（A1）

```swift
/// 服务端 user 形状（/auth/me、/auth/token、/settings 共用）
struct AccountUserDTO: Decodable, Sendable, Equatable {
    let id: String
    let email: String
    let displayName: String
    let role: String            // "parent" | "child"
    let ageBand: String         // "child" | "teen" | "adult"
    let cefrLevel: String
    let avatar: String?
    let birthYear: Int?
    let dailyLimitMinutes: Int?
    let allowFreeChat: Bool?
    let isChild: Bool?
    let nativeLanguage: String?
    // 账号偏好（/settings 才有，其它端点缺省）
    let avatarStyle: String?
    let avatarImageUrl: String?
    let autoIllustrate: Bool?
    let gender: String?
    let storySentences: Int?

    var isChildAccount: Bool   // role=="child" || ageBand=="child" || isChild==true
    var normalizedLevel: String // 大写 A1/A2/B1/B2/C1，非法回退 A1
}

struct UsageDTO: Decodable, Sendable, Equatable {
    let minutes: Double?          // 注意：可能缺省
    let limitMinutes: Int?
    let remainingMinutes: Int?
    let exceeded: Bool?
    let attemptCount: Int?
    let chatTurnCount: Int?
}

struct AuthTokenDTO: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let refreshExpiresIn: Int?
    let user: AccountUserDTO?
}

struct MeResponseDTO: Decodable, Sendable {
    let user: AccountUserDTO?
    let usage: UsageDTO?
}
```

### 3.1 `AuthService`（A1，`Core/Networking/Services/AuthService.swift`）

```swift
struct AuthService: Sendable {
    let transport: APITransport
    func token(email: String, password: String) async throws -> AuthTokenDTO          // POST auth/token, authPolicy .none
    func refresh(refreshToken: String) async throws -> AuthTokenDTO                  // POST auth/refresh, .none
    func me() async throws -> MeResponseDTO                                          // GET auth/me, bearer；user==nil ⇒ 抛 .unauthorized
    func revoke(refreshToken: String) async throws                                   // POST auth/revoke, .none
    func changePassword(oldPassword: String, newPassword: String) async throws        // POST auth/password, bearer（后端未上线时由 UI 走降级分支）
}
```

> **`SettingsPatchDTO` 的 null 语义（B5 必读）**：Swift 的 `T?` 无法区分"不修改(omit)"与"重置为 null"，而 HOS 会对 `gender`/`story_sentences`/`tts_voice`/`show_word_ipa` 显式发 `null`。A1 的实现是：字段 `nil` = 不发送；要发 `null` 用 `body.clear(.ttsVoice)`（`SettingsPatchDTO.ClearField` 枚举）。**设置页/音色页的"恢复默认"必须用 `clear(...)`**，否则会出现"看起来保存成功但服务端没清空"的静默 bug。

### 3.2 `AccountService`（A1，`Services/AccountService.swift`）

```swift
struct AccountService: Sendable {
    let transport: APITransport
    func settings() async throws -> SettingsResponseDTO                       // GET settings
    func patchSettings(_ body: SettingsPatchDTO) async throws -> SettingsResponseDTO   // PATCH settings
    func familyMembers() async throws -> [FamilyMemberDTO]                    // GET family/members
    func createMember(_ body: FamilyCreateDTO) async throws -> FamilyMemberResponseDTO  // POST family/members
    func updateMember(id: String, _ body: FamilyPatchDTO) async throws -> FamilyMemberResponseDTO // PATCH family/members/:id
    func resetMemberPassword(id: String, newPassword: String) async throws    // POST family/members/:id/password
    func parentSummary() async throws -> ParentSummaryDTO                     // GET parent/summary（403 需被 ErrorMapper 处理）
    func submitSuggestion(_ body: SuggestionCreateDTO) async throws -> SuggestionCreateResultDTO   // POST suggestions
    func listSuggestions(status: String, limit: Int, offset: Int) async throws -> SuggestionListDTO // GET suggestions
    func patchSuggestionStatus(id: String, status: String) async throws       // PATCH suggestions/:id
    func exportSuggestionsMarkdown(status: String) async throws -> String     // GET suggestions/export（返回 Markdown 文本）
    func avatarPresets() async throws -> AvatarPresetsDTO                     // GET avatar/presets
    func avatar() async throws -> AvatarStateDTO                              // GET avatar
    func selectAvatar(presetId: String, style: String) async throws -> AvatarStateDTO  // POST avatar
    func updateAvatarDescription(_ description: String) async throws -> AvatarStateDTO // PATCH avatar
    func clearAvatar() async throws                                           // DELETE avatar
    func avatarImageData() async throws -> Data                               // GET avatar/image（二进制）
}
```

`AccountDTO.swift` 需包含（字段照抄 HOS `core/net/AccountDtos.ets`）：
`SettingsResponseDTO{user: AccountUserDTO?, prefs: PrefsDTO?, usage: UsageDTO?}`、
`PrefsDTO{correctionLevel, ttsVoice, ttsRate, showWordIpa}`、`SettingsPatchDTO`、
`FamilyMemberDTO`/`FamilyMemberListDTO`/`FamilyCreateDTO`/`FamilyPatchDTO`/`FamilyMemberResponseDTO`/`ResetPasswordBodyDTO`、
`ParentSummaryDTO`（含 `family/today/week/totals/trend/blind/phonemes/words/members/children` 各子结构，照 HOS 字段）、
`SuggestionDTO`/`SuggestionListDTO`/`SuggestionCountsDTO`/`SuggestionCreateDTO`/`SuggestionCreateResultDTO`/`SuggestionPatchDTO`/`SuggestionViewportDTO`/`SuggestionContextDTO`、
`AvatarPresetsDTO`/`AvatarPresetCharacterDTO`/`AvatarStyleDTO`/`AvatarStateDTO`/`AvatarImagesDTO`/`AvatarStyleLabelsDTO`。

### 3.3 `PracticeService`（A2）+ `PracticeDTO.swift`

```swift
struct PracticeService: Sendable {
    let transport: APITransport
    func sentences(level: String, focus: String = "") async throws -> SentenceListDTO    // GET sentences?level=&focus=
    func sentence(id: String) async throws -> SentenceDTO                                // GET sentences/:id
    func attempts(limit: Int) async throws -> [AttemptItemDTO]                           // GET attempts?limit=
    func attemptsForSentence(id: String) async throws -> [AttemptItemDTO]                // GET sentences/:id/attempts
    func evaluate(audioData: Data, filename: String, mimeType: String, sentenceId: String,
                  referenceText: String, mode: AttemptMode, durationMs: Int,
                  blindTestId: String? = nil) async throws -> AttemptResponseDTO          // POST attempts (multipart)
    func retryAttempt(id: String) async throws -> AttemptResponseDTO                     // POST attempts/:id/retry
    func audioData(audioId: String) async throws -> Data                                 // GET audio/:id
    func synthesize(text: String, rate: TTSRate, voice: String?, format: TTSFormat) async throws -> Data  // POST tts
    func warmup(texts: [String], rate: TTSRate) async                                   // POST warmup，失败静默
    func health() async throws -> HealthDTO                                              // GET health (.none)
}
```
`PracticeDTO.swift`（照 HOS `Dtos.ets`）：`SentenceDTO`, `SentenceListDTO`, `ScoresDTO`, `WordScoreDTO`, `PhonemeScoreDTO`, `NBestDTO`, `IssueDTO`, `IntonationDTO`, `IntonationRegionDTO`, `F0Point`（`[Double?]` 用 `struct F0Point: Decodable { timeMs: Double; hz: Double? }` 注意服务端是二元数组 → 需自定义解码：`[number, number|null]`）、`PronounceResultDTO`, `FeedbackDTO`, `FeedbackPointDTO`, `BlindProgressDTO`, `AttemptResponseDTO`, `AttemptItemDTO`, `AttemptListDTO`, `HealthDTO`/`HealthVoiceDTO`/`HealthCapabilitiesDTO`/`HealthDbDTO`, `TtsVoiceDTO`, 枚举 `TTSRate`/`TTSFormat`/`AttemptMode`。

### 3.4 `FlowService`（A2）+ `FlowDTO.swift`

```swift
struct FlowService: Sendable {
    let transport: APITransport
    func submitAsync(audioData: Data, referenceText: String, sentenceId: String,
                     source: String, materialId: String?, durationMs: Int) async throws -> AsyncSubmitDTO   // POST attempts/async
    func status(ids: [String]) async throws -> [AsyncStatusItemDTO]                      // GET attempts/status?ids=a,b,c
    func diagnosisBatch(attemptIds: [String]) async throws -> FlowDiagnosisDTO           // POST diagnosis (batch)
}
```
`FlowDTO.swift`：`AsyncSubmitDTO{id, attemptId, blind, status, progress}`, `AsyncStatusItemDTO{id,status,error,scoredAt,result}`, `AsyncResultDTO`, `AsyncStatusDTO`, `FlowDiagnosisDTO` 及其 counts/trend/errorWord/contrast/item/range 子结构（照 HOS `FlowDtos.ets`）。

### 3.5 `ChatService`（A3）+ `ChatDTO.swift`

```swift
struct ChatService: Sendable {
    let transport: APITransport
    func scenarios(includeChild: Bool) async throws -> ChatScenarioListDTO          // GET chat/scenarios[?include_child=1]
    func createScenario(title: String, titleZh: String, settingZh: String, rolePrompt: String,
                        openingLine: String, level: String, audience: String) async throws -> String  // POST chat/scenarios → id
    func updateScenario(id: String, title: String, titleZh: String, settingZh: String,
                        rolePrompt: String, openingLine: String, level: String) async throws  // PATCH chat/scenarios/:id
    func deleteScenario(id: String) async throws                                    // DELETE chat/scenarios/:id
    func createSession(scenarioId: String) async throws -> ChatSessionDTO           // POST chat/sessions
    func turn(sessionId: String, text: String, audioData: Data?) async throws -> ChatTurnDTO  // POST chat/sessions/:id/turn（multipart: text 必填 + audio 可选）
    func messages(sessionId: String) async throws -> ChatMessageListDTO             // GET chat/sessions/:id/messages
    func end(sessionId: String) async throws                                        // POST chat/sessions/:id/end
    func audioStatus(sessionId: String) async throws -> ChatAudioStatusDTO          // GET chat/sessions/:id/audio/status
    func audio(sessionId: String, force: Bool) async throws -> ChatAudioResult      // GET chat/sessions/:id/audio[?force=1]（200/202/500 三态）
    func sessions() async throws -> ChatSessionListDTO                              // GET chat/sessions
    func sessionDetail(id: String) async throws -> ChatSessionDetailDTO             // GET chat/sessions/:id
    func asr(audioData: Data, language: String) async throws -> String              // POST asr（multipart）→ text
    func downloadAudio(url: String) async throws -> Data                            // GET 任意音频 URL
}
```
`ChatAudioResult`（`struct, Sendable`）：`enum State { case ready(Data); case building; case failed(String) }`。
`ChatDTO.swift` 照 HOS `ChatDtos.ets`：`ChatScenarioDTO`/`ChatScenarioListDTO`/`ChatScenarioMutationDTO`/`ChatMessageDTO`/`ChatMessageListDTO`/`ChatSessionDTO`/`ChatTurnDTO`/`ChatCorrectionDTO`/`ChatPronDTO`/`ChatWordScoreDTO`/`ChatWeakPhonemeDTO`/`ChatVariationDTO`/`ChatCapabilitiesDTO`/`ChatEndDTO`/`ChatAudioStatusDTO`/`ChatAudioBuildingDTO`/`ChatSessionListItemDTO`/`ChatSessionListDTO`/`ChatSessionDetailDTO`/`ChatAsrDTO`。

### 3.6 `StoryService`（A3）+ `StoryDTO.swift`

```swift
struct StoryService: Sendable {
    let transport: APITransport
    func materials(limit: Int, offset: Int) async throws -> [StoryMaterialDTO]      // GET materials?kind=story
    func materialDetail(id: String) async throws -> StoryMaterialDTO                // GET materials/:id
    func createMaterial(title: String, text: String, sourceZh: String, level: String) async throws -> StoryMaterialCreatedDTO // POST materials
    func renameMaterial(id: String, title: String) async throws                     // PATCH materials/:id
    func deleteMaterial(id: String) async throws                                    // DELETE materials/:id
    func asr(audioData: Data, language: String) async throws -> String              // POST asr?language=zh-CN
    func rewrite(textZh: String, level: String, maxSentences: Int, tense: String) async throws -> StoryRewriteDTO  // POST story/rewrite
    func retell(materialId: String, storySentences: [String], transcript: String, level: String) async throws -> StoryRetellDTO  // POST story/retell
    func illustrate(id: String, force: Bool) async throws -> StoryIllustrationDTO    // POST story/:id/illustrate
    func audioStatus(id: String) async throws -> StoryAudioStatusDTO                // GET story/:id/audio/status
    func storyAudio(id: String, force: Bool) async throws -> Data                   // GET story/:id/audio
    func materialImageData(materialId: String) async throws -> Data                 // GET materials/:id/image
    func imageData(url: String) async throws -> Data
    func retellRecords(materialId: String) async throws -> [StoryRetellRecordDTO]    // GET story/:id/retells（契约未定，失败返回 []，页面不阻塞）
}
```
`StoryDTO.swift` 照 HOS `StoryDtos.ets`：`StoryMaterialDTO`/`StoryMaterialListDTO`/`StoryMaterialCreateDTO`/`StoryMaterialCreatedDTO`/`StoryReadabilityDTO`/`StoryRewriteDTO`/`StoryRetellDTO`/`StoryIllustrationDTO`/`StoryAudioStatusDTO`/`StoryAsrDTO`/`StoryRetellRecordDTO` + 页面模型 `StorySentenceItem`/`StoryTextPair`/`StoryCardItem`（页面模型放 `Features/Story/StoryModels.swift`，由 B3 定义）。

**已确认的实现取舍（B2/B3 必须按此写页面）**：
- `ChatService.turn` 恒为 multipart（`text` 必填 + `audio` 可选），与 HOS 的"无录音走 JSON"不同（契约优先）。
- `ChatService.asr` / `StoryService.asr`：`language` 走 **query**，同时在 multipart 里冗余同名字段。
- 202 无法从 `APITransport` 拿到状态码，`ChatService.audio` / `StoryService.storyAudio` 用「响应体首字节是 `{`/`[` 即构建中」嗅探：`ChatService.audio` 返回 `.building`，`StoryService.storyAudio` 抛 `.server(.providerUnavailable, status: 202)` ⇒ **页面必须先轮询 `audioStatus` 到 ready 再下载**。
- `StoryService.audioStatus` 404 → `status == "no_audio"`（不抛错），页面按 `ready / building / failed / no_audio` 四值处理。
- `ChatService.audio` 的 `.failed(message)` 里 `message` 可能为空串，页面需回落 `ErrorMapper` 文案。

### 3.7 `StatsService`（A2）+ `StatsDTO.swift`

```swift
struct StatsService: Sendable {
    let transport: APITransport
    func diagnosis(scope: String, days: Int, attemptIds: [String]) async throws -> DiagnosisResponseDTO   // GET diagnosis?scope=&days=
    func review(limit: Int) async throws -> ReviewResponseDTO                       // GET review?limit=
    func gradeReview(cardId: String, grade: String) async throws -> ReviewGradeResultDTO  // POST review/:id/grade
    func blindTests() async throws -> BlindTestListDTO                              // GET blind-tests
    func startBlindTest() async throws -> BlindTestStartDTO                          // POST blind-tests
    func finishBlindTest(id: String) async throws -> BlindFinishDTO                  // POST blind-tests/:id/finish
    func healthFull(force: Bool) async throws -> HealthFullDTO                        // GET health[?force=1]（全字段）
}
```
`StatsDTO.swift` 照 HOS `StatsDtos.ets`：`DiagnosisResponseDTO`/counts/trend/errorWord/contrast/item/range、`ReviewResponseDTO`/`ReviewStatsDTO`/`ReviewCardDTO`/`ReviewDisplayDTO`/`ReviewWeakPhonemeDTO`/`ReviewWeakPhonemeTrendDTO`/`ReviewWordErrorDTO`/`ReviewGradeDTO`/`ReviewGradeResultDTO`、`BlindTestDTO`/`BlindTestStartDTO`/`BlindTestListDTO`/`BlindTrendDTO`/`BlindTrendScoreDTO`/`BlindFinishDTO`、`HealthFullDTO`/`HealthFeaturesDTO`/`HealthCapabilitiesFullDTO`/`HealthVoiceFullDTO`。

### 3.8 `DictionaryService` / `MediaService`（A2）

> **A2 已确认的实现口径（后续页面按此用）**：
> - `MediaService` 带 `let transport: APITransport`（`ocr` 需要网络），装配为 `MediaService(transport:)`。
> - `OCRResultDTO` 放在 `DTO/PracticeDTO.swift`（与 HOS `Dtos.ets` 同域）。
> - `WordIpaDTO` 除契约四字段外追加可选 `variants: [String]?`、`ipaDisabled: Bool?`，`syllables` 容错接受 `[String]` 或 `Int`。
> - `PracticeService.attemptsForSentence(id:)` 线上端点不存在（三处交叉确认 404），实现为 `GET attempts?limit=100` + 本地按 `sentence_id` 过滤，签名不变。
> - `StatsService.gradeReview(cardId:grade:)` 实际请求是 **`POST review` + `{card_id, grade}`**（不是 `review/:id/grade`）。
> - `StatsService.diagnosis(scope:days:attemptIds:)` 在 `scope == "attempt"` 时取 `attemptIds.first` 作为 `attempt_id`，为空抛本地 `.server(.badRequest, status: 0)`。
> - 本地校验错误统一 `.server(code: .badRequest, message: nil, status: 0)`，`ErrorMapper` 必须按 code 正常映射（不要因 status 0 变成"服务器错误"）。
> - 超时以 HOS 为准（评测 120s / TTS 30s / 列表 15s / 轮询 20s / ocr 60s），与 `architecture.md` §4.5 旧表不一致处以 HOS 为准。

```swift
struct DictionaryService: Sendable {
    let transport: APITransport
    func wordIpa(word: String) async throws -> WordIpaDTO        // GET words/:word
    func wordIpaBatch(words: [String]) async throws -> [WordIpaDTO]  // GET words?words=a,b
}
struct WordIpaDTO: Decodable, Sendable, Equatable { let word: String; let ipa: String?; let syllables: [String]?; let error: String? }

struct VoiceOption: Identifiable, Sendable, Equatable { let id: String; let labelZh: String; let lang: String; let sample: String? }
struct MediaService: Sendable {           // 纯本地/常量 + 媒体字节
    static let voicesConst: [VoiceOption]                     // 9 内置音色（照 HOS MediaService.voices）
    static func findVoice(_ id: String) -> VoiceOption?
    static func isKnownVoice(_ id: String) -> Bool
    static func imageContentType(path: String) -> String      // heic/heif→image/heic，其它→image/jpeg
    static func imageFileName(path: String) -> String
    func ocr(imageData: Data, filename: String, mimeType: String) async throws -> OCRResultDTO  // POST ocr
}
```

### 3.9 会话（A4，`Core/Session/**`）

保持既有 `TokenStore`/`TokenRefresher`/`UserProfile` 契约不变（见源码）。新增/调整：

```swift
@MainActor @Observable
final class SessionStore {
    enum Phase: Equatable { case launching, signedOut, signedIn }
    private(set) var phase: Phase
    private(set) var user: UserProfile?
    private(set) var usage: UsageDTO?
    private(set) var startupError: APIError?
    private(set) var degradedReason: String?          // voice 不可达时的横幅
    var capabilities: RoleCapabilities { get }
    var isChild: Bool
    func restore() async
    func retryRestore() async
    func signIn(baseURLText: String, email: String, password: String, remember: Bool) async throws
    func signOut() async
    func handleSessionExpired() async
    func reloadUser() async                       // 重新 GET /auth/me + settings
    func apply(usage: UsageDTO)                   // 每次业务响应回填用量
    func markDegraded(_ on: Bool, reason: String?)
}

struct RoleCapabilities: Sendable, Equatable {        // 从 Theme.swift 抽到自身文件
    let isChild: Bool
    var canSeeIPA: Bool
    var showsNumericScore: Bool
    var usesEncouragementOnly: Bool
    var minTapTarget: CGFloat        // 儿童 56，成人 44
    static func make(isChild: Bool) -> RoleCapabilities
}

actor CredentialStore {                              // 记住登录（默认关，明文风险见 docs）
    func save(email: String, password: String) async
    func load() async -> (email: String, password: String)?
    func clear() async
}
```

**`SessionStore` 是唯一会话事实来源**：`SessionStore` 不直接持有 `URLSession`，通过注入的 `AppDependencies` 调用 Service。

### 3.10 音频（A4，`Core/Audio/**`）

```swift
@MainActor @Observable
final class AudioCoordinator {
    enum Mode { case idle, recording, playing }
    private(set) var mode: Mode
    private(set) var level: Double                 // 0...1 录音电平
    private(set) var permission: MicPermission
    func prepare() async                           // 配置 AVAudioSession
    func requestPermission() async -> Bool
    func openSettings()
    func startRecording() async throws
    func stopRecording() async throws -> RecordedAudio   // data/durationMs/peakDb
    func cancelRecording() async
    func play(data: Data, formatHint: String?) async throws
    func play(fileURL: URL) async throws
    func stopPlayback() async
    func stopAll() async
    var isRecording: Bool
    var isPlaying: Bool
}
struct RecordedAudio: Sendable, Equatable { let data: Data; let durationMs: Int; let peakDb: Double; let isSilent: Bool }
enum MicPermission: Sendable, Equatable { case unknown, granted, denied }
enum AudioError: Error, Equatable, Sendable { case permissionDenied, tooShort, silent, tooLong, tooLarge, engine(String) }
```
录音参数：**m4a / AAC / 16kHz / 单声道 / 65kbps**；上限 60s、下限 500ms、静音阈值 -45dB、体积预检 12MB；录音前停播放、播放前停录音；来电/路由变化中断时停止并回调。

### 3.11 存储（A4，`Core/Storage/**`）

```swift
enum CacheLocator { static func ttsDir() -> URL; static func imagesDir() -> URL; static func recordingsDir() -> URL
                    static func jsonDir() -> URL; static func ensureAll() }
actor DiskCache {                          // 小 JSON + TTL
    func write<T: Encodable>(_ value: T, key: String, ttl: TimeInterval) 
    func read<T: Decodable>(_ type: T.Type, key: String) -> T?
    func clearAll()
}
actor AudioCache {                         // TTS 字节 LRU 200MB，键 = sha256(text|rate|voice|format)
    func data(for key: String) -> Data?
    func store(_ data: Data, for key: String) 
    func trim()
}
actor ImageCache { func data(for key: String) -> Data? ... }   // 100MB
actor RecordingCache { func save(_ data: Data, id: String) -> URL ; func trim() }  // 300MB/7d
actor CorpusRepository {                   // /sentences 快照 24h，合并并发请求
    func sentences(level: String, focus: String, userId: String, force: Bool) async throws -> [SentenceDTO]
}
enum CacheJanitor { static func cleanupOnBoot(); static func clearUserScoped() }
```
缓存键规则（`docs/architecture.md` §7.2）：所有按用户区分的键带 `userId`，`sha256` 化；退出登录清 token + audio/images/recordings + recent-*。

### 3.12 设计系统（A5，`Core/DesignSystem/**`）

令牌（沿用既有 `Tokens.swift` 命名，缺失的补齐）：`Tokens.space[1...8]`、`Tokens.radius{sm,md,lg,xl}`、`Tokens.primary/secondary/success/warn/danger/muted/background/surface/stroke`、`AppFont.{title,heading,body,caption,micro,score}`、`Tokens.elevation`。
组件清单（每文件一个 View）：

| 文件 | 类型 | 说明 |
| --- | --- | --- |
| `Components/AppButton.swift` | `AppButton` | 已有：primary/tonal/ghost/danger/text，`EcButtonKind` 对应 |
| `Components/CardStyle.swift` | `CardStyle`/`.card()` | 已有 |
| `Components/StateViews.swift` | `EmptyStateView`/`ErrorStateView`/`InlineErrorView`/`PermissionCard`/`ErrorBanner`/`LoadingBlock`/`SkeletonBlock` | 已有 + 补 loading/skeleton |
| `Components/ScoreViews.swift` | `ScoreBadge`/`ScoreBar`/`StarRow`/`ScoreRing`/`WordChipRow` | 数字分/星级/词级色块；儿童模式隐藏数字 |
| `Components/WordText.swift` | `WordTextView` | 可点词（弹音标）；儿童默认关 `showIPA` |
| `Components/Charts.swift` | `IntonationChart`/`TrendLineChart`/`PhonemeRadarChart`/`BarChartView` | Swift Charts；空/单点数据保护；降采样 ≤200 点 |
| `Components/EcBlocks.swift` | `SectionHeader`/`InfoRow`/`PillTag`/`BulletList`/`KeyValueGrid`/`Banner` | 通用排版 |
| `Components/Sheets.swift` | `BottomSheetContainer`/`ConfirmDialog` | 统一弹层 |
| `Features/Shared/ScorePresenter.swift` | `enum ScorePresenter` | 分数→文案/颜色/星级（成人/儿童两套） |
| `Features/Shared/Formatters.swift` | `enum EcFormat` | 时长 mm:ss、相对时间、进度百分比 |
| `Features/Shared/ChartsData.swift` | `struct ChartPoint` 等 | 图表数据整形（与 DTO 解耦） |

### 3.13 错误映射（A4，`Core/Error/**`）

```swift
struct UIMessage: Sendable, Equatable {
    let title: String
    let body: String?
    let actionTitle: String?     // "重试" / "重新登录" / "去设置"
    let action: Action?
    enum Action: Sendable, Equatable { case retry, relogin, openSettings, back, none }
    let isRetryable: Bool
    let diagnosticID: String?    // 客户端短 id，写日志便于家长反馈
}
enum ErrorMapper {
    static func message(for error: any Error, isChild: Bool) -> UIMessage
    static func title(for code: APIError, isChild: Bool) -> String
    static func body(for code: APIError, isChild: Bool) -> String
    static func isNetwork(_ error: any Error) -> Bool
}
```
映射表以 `ios/docs/architecture.md` §5.2 为准（成人/儿童两套文案，逐条覆盖 `ServerErrorCode` 与 `URLError`）。

### 3.14 路由（A5 定义，B1–B5 使用）

```swift
enum AppRoute: Hashable {
    case sentences                     // 句子列表
    case practice(SentenceDTO)         // 单句跟读（含结果内联）
    case practiceResult(attemptId: String?)
    case flowSummary
    case chatScenarios
    case chatSession(sessionId: String)
    case chatHistory
    case chatDetail(sessionId: String)
    case chatCustom(scenarioId: String?)
    case storyRecord
    case storyDetail(materialId: String)
    case storyReview(materialId: String, sentences: [String])
    case flowStory(materialId: String) // 连读一篇故事（复用连读运行态，读完进汇总）
    case blindTest
    case diagnosis
    case review
    case parent
    case family
    case suggestions
    case avatar
    case voices
    case health
    case settings
}

@MainActor @Observable
final class AppRouter {
    var path: [AppRoute]
    func push(_ route: AppRoute)
    func pop()
    func popToRoot()
    func reset(to routes: [AppRoute])
}
```

### 3.15 应用装配与依赖注入（B1–B5 共同遵守）

**分层**：`App → Features → Core`。`Features` **不得** import/引用 `AppEnvironment`，只通过构造参数拿依赖。

```swift
// App/AppEnvironment.swift（B5 实现）
@MainActor
@Observable
final class AppEnvironment {
    let config: AppConfig
    let session: SessionStore              // 全局会话（唯一事实来源）
    let audio: AudioCoordinator            // 全局音频门面
    let router: AppRouter                  // 路由
    private(set) var services: AppServices?   // 登录后才可用（service 与 baseURL 绑定）

    func bootstrap() async                // 启动：CacheJanitor + session.restore() + health 降级
    func configure(baseURL: URL) -> AppServices   // 登录成功后建服务，换服务器则重建
}

/// 一组与 baseURL 绑定的 Service（登录后才有；换服务器必须重建，禁止跨服务器复用 token）。
/// **定义在 `Core/AppServices.swift`**（B5 写），放在 Core 是为了让 Features 可以引用类型而不反向依赖 App。
@MainActor
struct AppServices {
    let practice: PracticeService
    let flow: FlowService
    let chat: ChatService
    let story: StoryService
    let stats: StatsService
    let account: AccountService
    let dictionary: DictionaryService
    let media: MediaService
}
```

**Feature 页面的注入约定**（B1–B5 统一）：

1. 每个 Feature 的**根页面**自己声明 `init`，需要什么就收什么，例如：
   ```swift
   struct PracticeView: View {
       init(services: AppServices, audio: AudioCoordinator) { ... }
   }
   ```
   子页面（`XxxView`）用 `@State private var store: XxxStore` 持有 `@MainActor @Observable` 的 Store，
   Store 的 `init` 同样显式收依赖（`Store(services:audio:session:)`）。
2. 全局环境值只用三个：`@Environment(SessionStore.self)`（会话/角色）、`@Environment(RoleCapabilities.self)`（或 `\.roleCapabilities`）、`@Environment(AppRouter.self)`（导航）。
   **音频、Service、缓存一律走构造参数**，不要塞 Environment（便于测试与替换）。
3. 路由跳转只允许 `@Environment(AppRouter.self)` 的 `push/pop/popToRoot`（`AppRoute` 在 `Core/DesignSystem/Navigation/`）。
4. 需要"回首页/切 Tab"的跨域动作，用闭包参数（如 `onStartPractice: (SentenceDTO) -> Void`），不要反向 import Home。
5. **M0 遗留文件必须原地覆写，不要另建同名类型的新文件**（本机无法删除文件，另建会导致类型重名）：
   - `Features/Practice/PracticeListView.swift`、`PracticeViewModel.swift`、`SentenceView.swift` → 由 B1 覆写/改写（可改成新内容但**保持文件名唯一性**；若新架构需要 `PracticeView.swift`，则先把旧文件改为仅含注释说明的占位）。
   - `Features/Auth/{LoginView,AuthViewModel}.swift`、`App/{EnglishCoachApp,AppEnvironment}.swift` → 由 B5 覆写。
   - `Core/Networking/{APIs,DTOs,Endpoints}.swift`、`Core/Audio/AudioRecorder.swift` 已是纯注释占位/扩展，**保持不动**。

### 3.15.1 Feature 根页面类型名与签名（**冻结**，B5 按此装配 `navigationDestination`）

所有 Feature 根页面统一构造：`XXX(services: AppServices, audio: AudioCoordinator[, 路由参数])`，
并各自用 `@State private var store = XxxStore(services:audio:session:)` 持有 Store；`session` 从 `@Environment(SessionStore.self)` 取。

| 文件（`Features/<域>/`） | 类型 | init 签名 | 路由/入口 |
| --- | --- | --- | --- |
| Practice/PracticeView.swift | `PracticeView` | `(services: AppServices, audio: AudioCoordinator)` | Tab 0 |
| Practice/SentenceListView.swift | `SentenceListView` | `(services: AppServices, audio: AudioCoordinator)` | `.sentences` |
| Practice/PracticeResultView.swift | `PracticeResultView` | `(attemptId: String?, services: AppServices, audio: AudioCoordinator)` | `.practiceResult` |
| Practice/SentencePracticeView.swift | `SentencePracticeView` | `(sentence: SentenceDTO, level: String, services: AppServices, audio: AudioCoordinator)` | `.practice`（由 PracticeView/SentenceListView 推入） |
| Flow/FlowView.swift | `FlowView` | `(services: AppServices, audio: AudioCoordinator)` | Tab 1 |
| Flow/FlowSummaryView.swift | `FlowSummaryView` | `(services: AppServices, audio: AudioCoordinator)` | `.flowSummary` |
| Chat/ChatScenariosView.swift | `ChatScenariosView` | `(services: AppServices, audio: AudioCoordinator)` | Tab 2 / `.chatScenarios` |
| Chat/ChatSessionView.swift | `ChatSessionView` | `(sessionId: String, scenario: ChatScenarioDTO?, services: AppServices, audio: AudioCoordinator)` | `.chatSession` |
| Chat/ChatHistoryView.swift | `ChatHistoryView` | `(services: AppServices, audio: AudioCoordinator)` | `.chatHistory` |
| Chat/ChatDetailView.swift | `ChatDetailView` | `(sessionId: String, services: AppServices, audio: AudioCoordinator)` | `.chatDetail` |
| Chat/ChatCustomView.swift | `ChatCustomView` | `(scenarioId: String?, services: AppServices, audio: AudioCoordinator)` | `.chatCustom` |
| Story/StoryHomeView.swift | `StoryHomeView` | `(services: AppServices, audio: AudioCoordinator)` | Tab 3 |
| Story/StoryRecordView.swift | `StoryRecordView` | `(services: AppServices, audio: AudioCoordinator)` | `.storyRecord` |
| Story/StoryDetailView.swift | `StoryDetailView` | `(materialId: String, services: AppServices, audio: AudioCoordinator)` | `.storyDetail` |
| Story/StoryReviewView.swift | `StoryReviewView` | `(materialId: String, sentences: [String], services: AppServices, audio: AudioCoordinator)` | `.storyReview` |
| BlindTest/BlindTestView.swift | `BlindTestView` | `(services: AppServices, audio: AudioCoordinator)` | `.blindTest` |
| Report/DiagnosisView.swift | `DiagnosisView` | `(services: AppServices, audio: AudioCoordinator)` | `.diagnosis` |
| Report/ReviewView.swift | `ReviewView` | `(services: AppServices, audio: AudioCoordinator)` | `.review` |
| Home/MeView.swift | `MeView` | `(services: AppServices, audio: AudioCoordinator)` | Tab 4 |
| Settings/SettingsView.swift | `SettingsView` | `(services: AppServices, audio: AudioCoordinator)` | `.settings` |
| Parent/ParentView.swift | `ParentView` | `(services: AppServices, audio: AudioCoordinator)` | `.parent` |
| Parent/FamilyView.swift | `FamilyView` | `(services: AppServices, audio: AudioCoordinator)` | `.family` |
| Parent/SuggestionsView.swift | `SuggestionsView` | `(services: AppServices, audio: AudioCoordinator)` | `.suggestions` |
| Parent/AvatarView.swift | `AvatarView` | `(services: AppServices, audio: AudioCoordinator)` | `.avatar` |
| Parent/VoicesView.swift | `VoicesView` | `(services: AppServices, audio: AudioCoordinator)` | `.voices` |
| Parent/HealthView.swift | `HealthView` | `(services: AppServices, audio: AudioCoordinator)` | `.health` |

> 若某个 case 的 payload 需要页面额外数据（如 `scenario`），在 `AppRoute` 里已带或由 B5 用 `.task` 拉取；**签名以上表为准，不得单方面改动**（B5 依赖它装配，改动会导致 dispatcher 编译失败）。

---

## 4. 页面 → 归属 → 主要服务

| 页面 | 路由 | Owner | 主要服务 | 参照 |
| --- | --- | --- | --- | --- |
| 登录（含服务器地址/测连通/演示账号/记住登录） | — | B5 | AuthService, PracticeService.health | `LoginPage.ets` |
| HomeTabs 5 Tab + 降级横幅 | — | B5 | — | `HomeTabs.ets` |
| 我的（MePage） | tab | B5 | AccountService.settings, Health | `MePage.ets` |
| 设置 | `.settings` | B5 | AccountService.settings/patch, auth | `SettingsPage.ets` |
| 家长面板 | `.parent` | B5 | AccountService.parentSummary | `ParentPage.ets` |
| 家庭成员 | `.family` | B5 | AccountService.family* | `FamilyPage.ets` |
| 建议箱 | `.suggestions` | B5 | AccountService.suggestion* | `SuggestionsPage.ets` |
| 虚拟形象 | `.avatar` | B5 | AccountService.avatar* | `AvatarPage.ets` |
| 音色 | `.voices` | B5 | MediaService/PracticeService.synthesize | `VoicesPage.ets` |
| 服务状态 | `.health` | B5 | StatsService.healthFull | `HealthPage.ets` |
| 跟读（卡片流 + 页内结果） | tab | B1 | PracticeService.*, AudioCoordinator | `PracticePage.ets`（53KB，最复杂） |
| 跟读详细结果（全屏） | `.practiceResult` | B1 | PracticeService.attemptsForSentence | `PracticeResultPage.ets` |
| 句子列表 | `.sentences` | B1 | PracticeService.sentences | `SentenceListPage.ets` |
| 连读 setup/running | tab | B1 | FlowService, PracticeService | `FlowPage.ets`（41KB） |
| 连读汇总 | `.flowSummary` | B1 | FlowService.diagnosisBatch | `FlowSummaryPage.ets` |
| 对话场景列表 | tab/.chatScenarios | B2 | ChatService.scenarios | `ChatScenariosPage.ets` |
| 对话会话 | `.chatSession` | B2 | ChatService.asr/turn/messages/audio | `ChatSessionPage.ets`（26KB） |
| 对话历史/详情/自定义 | `.chatHistory`/`.chatDetail`/`.chatCustom` | B2 | ChatService | 同上 |
| 故事列表 | tab | B3 | StoryService.materials | `StoryHomePage.ets` |
| 讲故事（录音→ASR→改写） | `.storyRecord` | B3 | StoryService.recordings/asr/rewrite/createMaterial | `StoryRecordPage.ets` |
| 故事详情（朗读/插画/打印/原声） | `.storyDetail` | B3 | StoryService.detail/illustrate/audio | `StoryDetailPage.ets` |
| 故事复述 | `.storyReview` | B3 | StoryService.retell | `StoryReviewPage.ets` |
| 盲测 | `.blindTest` | B4 | StatsService.blind* + PracticeService.evaluate | `BlindTestPage.ets` |
| 诊断 | `.diagnosis` | B4 | StatsService.diagnosis | `DiagnosisPage.ets` |
| 错音本 | `.review` | B4 | StatsService.review/grade | `ReviewPage.ets` |

> 页面级细节以 **`ios/docs/screens.md`**（每个页面的结构/交互/API/状态）为准；与 HOS 冲突时以 HOS 实现为事实、把差异写进 `ios/README.md` §0.5。

---

## 5. 隐私与 Info.plist（A6）

必须包含：`NSMicrophoneUsageDescription`（如实写明音频会上传服务器并转发云端语音服务）、`NSCameraUsageDescription`、`NSPhotoLibraryAddUsageDescription`、`NSLocalNetworkUsageDescription`、`UIBackgroundModes=[audio]`、`ITSAppUsesNonExemptEncryption=false`、方向声明（iPhone：`UISupportedInterfaceOrientations` 仅 portrait；iPad：`UISupportedInterfaceOrientations~ipad` 含 portrait + 左右横屏，保证 iPad 原生全屏且横屏占满；iPad 上用 `UIRequiresFullScreen=true` 暂时保证全屏——该键 iOS 26 已弃用，用 iOS 27 SDK 构建后系统改为按支持方向离散缩放，需按 TN3192 在 M4 处理窗口尺寸），以及 `PrivacyInfo.xcprivacy`（UserDefaults CA92.1 / FileTimestamp C617.1 / DiskSpace E174.1 / 音频 + 邮箱收集声明）。

## 6. 静态校验（A6 交付 `ios/tools/check_ios.py`，所有人本地可跑）

`python ios/tools/check_ios.py`（**只读 + stdout，不得写盘**），至少校验：

1. **税则**：每个 `.swift` 大括号/圆括号/方括号配平；字符串/注释/多行字符串（`"""`）内的括号不计；`#if`/`#else`/`#endif` 配平。
2. **类型唯一**：全仓 `struct|class|enum|actor|protocol|extension` 的顶层类型名不重复；文件名与主类型名一致（容差白名单）。
3. **符号引用**：`XxxService`/`XxxDTO` 等被引用的类型在仓内有声明（启发式：抓 `UpperCamelCase` 标识符，排除系统框架符号白名单）。
4. **分层**：`Features/**` 不含 `URLSession`/`URLRequest`/`import CryptoKit`；`Core/DesignSystem/**` 与 `Features/Shared/**` 不 import Networking 类型名；`Core/**` 不引用 `Features.`。
5. **规范**：无 `print(`、无 `TODO`/`FIXME`/`fatalError(`、无 `try!`、无 `as!`；用户可见中文文案（抽查硬编码英文 UI 字符串）。
6. **工程**：`project.yml` 的 sources 覆盖 `EnglishCoach/` 全部 `.swift`；Info.plist 必备键齐全；`PrivacyInfo.xcprivacy` 可被 plist 解析。
7. **路由完整**：`AppRoute` 的 case 与 §4 表一致；每个 case 在 `AppRoot`/`RootTabView` 的 `navigationDestination` 有分发。
8. **API 一致性**：各 `*Service` 被页面调用的方法名都存在于该 Service 声明（启发式）。

输出：`OK` / 分级错误清单（`ERROR` 阻断、`WARN` 提示）+ 退出码。

## 7. 完成定义（DoD，每个 agent 交付前自检）

- [ ] 文件路径、类型名、方法签名与本文 §3 完全一致（新增能力先改本文再写代码，**不允许静默偏离**）。
- [ ] 页面具备 loading / empty / error / 权限 四态，全部走 `StateViews` + `ErrorMapper` 文案。
- [ ] 儿童/成人差异通过 `RoleCapabilities`，无散落 `if user.role == .child`。
- [ ] 无 `print`/`TODO`/`fatalError`/`try!`/`as!`；日志走 OSLog 且不含凭据。
- [ ] 不新增第三方依赖；`import` 仅系统框架。
- [ ] 自己跑 `python ios/tools/check_ios.py` 无 ERROR（工具未就绪时人工过一遍 §6 清单）。
- [ ] 回报格式：**写了哪些文件（路径+行数）、未完成/假设项、需要 Lead 决策的接口分歧**。禁止声称"已编译通过"。

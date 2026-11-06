# Android 第二轮（ROUND2）· 最终 QA 报告

> **快照时间**：2026-11-05 01:50 (+08:00)
> **范围**：`english-coach-app/android/app/src/main/java/top/dreamsearch/englishcoach/**`（115 个 .kt）+ `android/tools/check_android.py` + 本轮文档
> **依据**：`android/ROUND2_CONTRACT.md` §1–§4、`android/CONTRACT.md` §5/§6、`docs/android-feature-list.md`
> **方法**：本会话宿主 shell 沙箱不可用（`windows-acl-run: --temp is not an existing directory`；`terminal_open` 报 `PTY shell exited during startup`），因此本轮 QA **全部为 read/grep/glob 的文件级核对**：逐项在代码里找调用点/实现，不采信口头报告；无法执行编译与 `python android/tools/check_android.py`（由 Lead 收尾统一跑，见 §5 占位）。
> **结论**：ROUND2 §4 的 9 组核对项 **全部 ✅ 落地**；起草 QA 时发现的 2 条缺口（设置页语音偏好同步、`avatar_presets` 三处入口统一）已在最终快照前由对应负责人补齐（§3 保留追溯）。无未解决的真实问题；剩余未做项全部属平台/后端限制（§4）。

---

## 1. 逐项核对（以代码为准；每项给 文件:行 + 关键代码）

### 1.1 `EcRadarChart` 存在且被 practice 调用 ✅

| 子项 | 证据（文件:行 + 1 行关键代码） |
|---|---|
| 组件存在（签名与 ROUND2 §3 一致） | `ui/component/Charts.kt:309` `fun EcRadarChart(labels: List<String>, values: List<Double?>, modifier: Modifier = Modifier, size: Dp = 160.dp, color: Color = EcColor.primary, maxValue: Double = 100.0)` |
| 纯 Canvas + 无障碍描述 | `Charts.kt:356-359` `Canvas(modifier = modifier.size(size).semantics { contentDescription = description })` |
| 跟读调用点 | `ui/page/practice/PracticeScreen.kt:889` `private fun RadarBlock(...)` → `:894` `EcRadarChart(labels = radar.labels, values = radar.values, color = EcColor.primary)` |
| 雷达数据来源 | `ui/page/practice/PracticeModels.kt:171` `data class RadarUi(...)`、`:256` `radar = buildRadarUi(scores, isChild)` |
| 页内结果 + 全屏 overlay 都渲染 | `PracticeScreen.kt:669`（页内结果 `result.radar?.let { RadarBlock(...) }`）、`:790`（overlay 同款） |
| 儿童隐藏（screens.md §0） | `PracticeScreen.kt:890` `if (isChild) return` |

### 1.2 跟读全屏结果 overlay / 历史逐条回放 / HorizontalPager ✅

| 子项 | 证据 |
|---|---|
| 全屏结果页（页内 overlay，不新增路由） | `ui/page/practice/PracticeScreen.kt:738` `private fun ResultOverlay(...)`；`:161` `if (state.overlayVisible && result != null) { ResultOverlay(...) }` |
| 可关闭 | `PracticeScreen.kt:767-774` `"✕ 关闭" .clickable(onClick = vm::closeOverlay)`；系统返回键 `:119` `BackHandler(enabled = state.overlayVisible) { vm.closeOverlay() }` |
| 可重试 / 下一句 | `PracticeScreen.kt:828-844` `if (state.canRetryEvaluate) EcButton("重试评测", onClick = vm::retryEvaluate)`；`"下一句 →"` 先关 overlay 再 `nextSentence()` |
| VM 状态与开关 | `ui/page/practice/PracticeViewModel.kt:290-298` `openOverlay()/closeOverlay()`；`:974-975` `val overlayVisible: Boolean = false` |
| 历史逐条回放（`audioByUrl`） | VM `PracticeViewModel.kt:441-468` `fun playHistoryAudio(item: HistoryItemUi)` → `:457` `val bytes = c.practice.audioByUrl(item.audioUrl)` → `playBytes`；UI `PracticeScreen.kt:1100` `onPlay = { vm.playHistoryAudio(item) }` |
| 历史数据带 audioUrl | `PracticeModels.kt:157-163` `data class HistoryItemUi(... val audioUrl: String = "")`；`:386` `audioUrl = item.audioUrl.orEmpty()` |
| 左右滑动切句（保留上下句按钮） | `PracticeScreen.kt:409-440`：`:437` `HorizontalPager(state = pagerState, ...)`；落定同步 `:429-433` `snapshotFlow { pagerState.settledPage }.collect { ... vm.onPageSettled(page) }`；VM `:281-285` `onPageSettled`；上下句按钮仍在 `:1165` `"‹ 上一句"`、`:1185` `"下一句 ›"` |
| 录音/提交中禁滑 | `PracticeScreen.kt:432-435`（`userScrollEnabled = !state.busy`）+ VM `goTo` `:309` `if (s.recording || s.submitting) return` |

### 1.3 practice / flow 都用 `voicePrefs.resolve(...)` ✅

| 调用点 | 证据 |
|---|---|
| 跟读示范音 / 跟我读 | `ui/page/practice/PracticeViewModel.kt:364` `val voiceChoice = c.voicePrefs.resolve(c.session.isChild)`，随后 `:365-371` 用 `rate/voice` 请求 `POST /tts` 并按 key 缓存 |
| 连读示范音 | `ui/page/flow/FlowViewModel.kt:1212` `val choice = c.voicePrefs.resolve(s.isChild)` |
| 连读汇总「听鼓励」 | `ui/page/flow/FlowSummaryViewModel.kt:216` `val choice = c.voicePrefs.resolve(s.isChild)` |
| 实现本体 | `core/audio/VoicePrefs.kt:45-49` `fun resolve(isChild: Boolean)`（儿童强 slow + 内置 Ana 童声；成人读本机镜像）；`:52-55` `syncFromAccount(...)` |
| 镜像写入 | 音色页 `VoicesViewModel.kt:76/168`；设置页 `SettingsViewModel.kt:153/209`；健康页展示生效音色 `HealthViewModel.kt:86/154/221` |

### 1.4 `pendingUploads.enqueue(...)` 在 practice 与 flow 都有调用点 ✅

| 调用点 | 证据 |
|---|---|
| 跟读提交失败入队 | `ui/page/practice/PracticeViewModel.kt:640-648`：`val offlineFailure = e is ApiError && (e.status == 0 || e.status >= 500)` → `:643` `c.pendingUploads.enqueue(audioFile = file, sentenceId = ..., referenceText = ..., durationMs = ...)`；成功置「已保存到本机」提示 `:649-659` |
| 连读异步提交失败入队 | `ui/page/flow/FlowViewModel.kt:1027` `if (isOfflineRetryable(e) && enqueuePendingUpload(recorded, item))`；`:1058-1066` `c.pendingUploads.enqueue(..., mode = "flow")` |
| 入队条件（只网络/5xx，4xx 不入队） | 跟读 `PracticeViewModel.kt:638-640`；连读 `FlowViewModel.kt:1074-1080` `status==0 → network_unreachable/timeout；否则 err.retryable || status>=500` |
| 队列实现 | `core/offline/PendingUploadQueue.kt:38` `class PendingUploadQueue`；`:84 enqueue`、`:126 list`、`:135 count`、`:138 remove`、`:150 clear`、`:171 suspend fun retryAll` |
| 连读汇总入口显示「待补评分 N 条」 | `ui/page/flow/FlowSummaryScreen.kt:120-121` `if (state.pendingUploads > 0) PendingUploadsCard(...)`；`:412` `"📤 待补评分 $count 条"`；VM `FlowSummaryViewModel.kt:73-74` `c.pendingUploads.count()` |

### 1.5 `PendingUploadsScreen` 存在且 `Routes.PENDING_UPLOADS` 已接线 ✅

| 子项 | 证据 |
|---|---|
| 页面存在（签名符合 ROUND2 §2） | `ui/page/offline/PendingUploadsScreen.kt:74` `fun PendingUploadsScreen(onBack: () -> Unit)` |
| 路由常量 | `ui/nav/Routes.kt:45` `const val PENDING_UPLOADS = "pending_uploads"` |
| 导航接线 | `ui/nav/AppNavHost.kt:22` import；`:169-170` `composable(Routes.PENDING_UPLOADS) { PendingUploadsScreen(onBack = back) }` |
| 首页顶部横幅入口 | `ui/HomeScreen.kt:114-133` `if (pendingCount > 0) { ... .clickable { Navigator.navigate(Routes.PENDING_UPLOADS) } ... }`（`:119`）；计数 `:76/82` `pendingUploads.count()`；文案 `:126` |
| 「我的」入口（有 pending 才显示） | `ui/page/account/MeViewModel.kt:55-58` `refreshPending()`；`MeScreen.kt:107-113` `PendingUploadsCard(...)`；卡片实现 `MeScreen.kt:451` |
| VM：列表/删除/全部重试/空态 | `ui/page/offline/PendingUploadsViewModel.kt:84` class；`:98 load`、`:138 loadItems`、`:282 retryAll`；页面说明「为什么会有这条」`PendingUploadsScreen.kt:299-326`、删除二次确认 `:96-119`、清除全部 `:121-144`、全部重试 `:543`、空态 `:227` |

### 1.6 连读汇总页 `onOpenReview` 入口 + 故事 id 来源正确 ✅

| 子项 | 证据 |
|---|---|
| 新签名（ROUND2 §2） | `ui/page/flow/FlowSummaryScreen.kt:68-72` `fun FlowSummaryScreen(onBack, onOpenFlowTab, onOpenReview: (materialId: String) -> Unit)` |
| 入口仅故事来源显示 | `FlowSummaryScreen.kt:129-132` `if (data.fromStoryMaterial && data.materialId.isNotEmpty()) { EcButton(label = "📝 复述这个故事", onClick = { onOpenReview(data.materialId) }) }` |
| 故事 id 来源正确 | `FlowViewModel.kt:150` 从 `NavParams.flowMaterialId` 读取（读完清空）→ `startFromMaterial(materialId)` `:791`；`:816` `val fromStory = detail.kind.isEmpty() || detail.kind.equals("story", ignoreCase = true)`；`:819-823` `beginRun(..., materialId = materialId, fromStoryMaterial = fromStory)`；`:1257` 汇总时 `fromStoryMaterial = s.runFromStoryMaterial && s.runMaterialId.isNotEmpty()` |
| 汇总数据字段 | `ui/page/flow/FlowModels.kt:139-141` `materialId` / `fromStoryMaterial` |
| 导航层消费 | `ui/nav/AppNavHost.kt:60-72` `NavParams.storyMaterialId = materialId; nav.navigate(Routes.STORY_REVIEW)` |

### 1.7 故事列表分组/连续天数、auto_illustrate、保存后跳详情、复制全文、StoryRuntime 持久化、整段朗读 building 重试 ✅

| 子项 | 证据 |
|---|---|
| 今天/昨天/更早分组 + 连续天数 | `ui/page/story/StoryHomeViewModel.kt:156` `streakDays = StoryDates.streakDays(seenDates)`、`:185` `StoryDates.labelOf(...)`；UI `StoryHomeScreen.kt:89` `StoryHomeHeader(isChild, state.streakDays)`、`:121-125` `state.groups.forEach { stickyHeader(...) { StoryGroupHeader(group) } }`；工具 `StoryRuntime.kt:221-247`（labelOf / streakDays） |
| `auto_illustrate` 保存后自动插图 | `ui/page/story/StoryRecordViewModel.kt:440` `if (!current.autoIllustrate) return`、`:445` `illustrate()`；`:535` 读取 `user?.autoIllustrate == true`；失败提示 `:440-443`；UI `StoryRecordScreen.kt:428` `else if (state.autoIllustrate && state.imageCapable) { ... }`（失败不静默） |
| 保存后跳详情 | `StoryRecordScreen.kt:417` `Navigator.navigate(Routes.STORY_DETAIL)`（先写 `NavParams.storyMaterialId`，`:54` 注释） |
| 详情「复制全文」 | `StoryDetailViewModel.kt:556` `fun copyText(): String`；UI `StoryDetailScreen.kt:236` `val clipboard = LocalClipboardManager.current`、`:253-258` `"📋 复制全文"` → `clipboard.setText(AnnotatedString(text))` + Toast；复制内容说明 `:270-272` |
| StoryRuntime 持久化 | `StoryRuntime.kt:97-108` `load()`（`CacheStore.readJson("story_record_<id>")`）、`:111-121` `original()`（文件存在才算 playable）、`:124-136` `saveOriginal`、`:139-152` `addRetell`；写入 `StoryRecordViewModel.kt:423` `StoryRuntime.saveOriginal(...)`；回读 `StoryDetailViewModel.kt:126/161-162`；复述写入 `StoryReviewViewModel.kt:276` |
| 整段朗读 building 阶段可重试 | `StoryDetailViewModel.kt:249-257` building 超约 30s → `audioState=FAILED` + 「生成超时了，可以点「重新生成」再试」；`:390-413` `retryAudio()` 用 `storyAudio(force=true)` 重新生成；UI `StoryDetailScreen.kt:575-589` building 超时显示「🔄 重新生成」按钮，`:604-611` failed 同按钮 |

### 1.8 账号页缺口（6 项）——全部 ✅

| 子项 | 状态 | 证据 |
|---|---|---|
| 家长面板「盲测周报」入口 | ✅ | `ui/page/account/ParentScreen.kt:71` `onOpenBlindTest: () -> Unit`；`:88` 顶部动作、`:451-452` 底部按钮；`ui/nav/AppNavHost.kt:146` `onOpenBlindTest = { nav.navigate(Routes.BLIND_TEST) }` |
| 音色页「去设置」 | ✅ | `ui/page/account/VoicesScreen.kt:57` `fun VoicesScreen(onBack: () -> Unit, onOpenSettings: () -> Unit)`；`:79/183` `onClick = onOpenSettings`；`AppNavHost.kt:162-166` |
| 服务状态强制刷新 + features | ✅ | `HealthViewModel.kt:97` `fun load(force: Boolean = false)`、`:102-103` `practice.health(force)` + `stats.healthFull(force)` 并行；`:165` `fun forceRefresh()`；`HealthScreen.kt:68/128` 强制刷新；features 渲染 `HealthScreen.kt:213-245` |
| `avatar_presets=false` 隐藏/禁用形象入口（Me/Settings/形象三处） | ✅ | 「我的」：`MeViewModel.kt:61-64` `capability.refresh()` → `avatarPresetsAvailable`；`MeScreen.kt:132-138/176-182` 副标题「当前服务端未开启」+ `enabled=false`。设置页：`SettingsViewModel.kt:237-267`；`SettingsScreen.kt:463-469` 同一套置灰。形象页：`AvatarViewModel.kt:81-101` `if (caps != null && !caps.avatarPresets) unavailable = true`；`AvatarScreen.kt:92/145-161` 「形象库暂不可用」+ 重试 |
| 设置 PATCH 成功后 `voicePrefs.syncFromAccount(...)` | ✅ | `SettingsViewModel.kt:151-153` `// 账号偏好 → 本机语音镜像` → `c.voicePrefs.syncFromAccount(...)`；`:209` PATCH 响应同步；`:424/430` 展示当前生效音色/语速 |
| 「我的」待补评分入口 | ✅ | `MeViewModel.kt:34` `pendingCount`、`:55-58` `refreshPending()`；`MeScreen.kt:81-85` ON_RESUME 刷新、`:107-113` `PendingUploadsCard(...)` → `Routes.PENDING_UPLOADS` |

### 1.9 data-layer 五个基础设施 ✅

| 项 | 证据 |
|---|---|
| `CapabilityCache` | `core/content/CapabilityCache.kt:31` class；`:52 fun cached()`（5 分钟 TTL `:111`）；`:64 suspend fun refresh(force = false)`（单飞 + 失败不抛）；AppGraph `:52` |
| `VoicePrefs` | `core/audio/VoicePrefs.kt:17` class；`:45 resolve`；`:52 syncFromAccount`；`:58 put`；AppGraph `:55` |
| `PendingUploadQueue` | `core/offline/PendingUploadQueue.kt:38` class；`:84 enqueue / :126 list / :135 count / :138 remove / :150 clear / :171 retryAll`；索引 `queue.json`（`:244-248`）；AppGraph `:58` |
| `CacheStore` 增补 + LRU | `core/storage/CacheStore.kt:39 pendingUploadsDir()`；`:87 trimTtsCache(200MB)`；`:92 trimAudioCache(300MB)`；`:99/107/117 readRecentResult/writeRecentResult/clearRecentResults`；`:51-60 cleanupOnBoot()` 调用两个 trim |
| `PracticeService` 增补 | `core/service/PracticeService.kt:102 suspend fun audioByUrl(audioUrl: String)`；`:174 suspend fun health(force: Boolean = false)` → `:179 query = if (force) mapOf("force" to "1")` |
| 路由/导航接线（ROUND2 §2） | `Routes.kt:45`；`AppNavHost.kt:60-72/141-148/162-171`（FlowSummary onOpenReview、Parent onOpenBlindTest、Voices onOpenSettings、PendingUploads） |

---

## 2. 本轮新增 / 修改规模（read 工具统计；无 shell 无法算 diff）

| 类别 | 数量 | 行数（当前文件总行） |
|---|---|---|
| 新增 Kotlin 文件 | **5** | **1,591** |
| ├ `core/content/CapabilityCache.kt` | | 153 |
| ├ `core/audio/VoicePrefs.kt` | | 78 |
| ├ `core/offline/PendingUploadQueue.kt` | | 313 |
| ├ `ui/page/offline/PendingUploadsViewModel.kt` | | 451 |
| └ `ui/page/offline/PendingUploadsScreen.kt` | | 596 |
| 主要修改文件（承载本轮功能） | **31** | 约 **16,700**（当前总行，非 diff） |
| Kotlin 文件总数 | **115**（round1 收尾 110） | — |
| 文档（本轮 QA 负责） | 3 | `android/QA_ROUND2.md`（本文件）、`docs/android-feature-list.md`、`docs/feature-index.md` |

> 修改文件清单（按目录）：`core/storage/CacheStore.kt`、`core/service/PracticeService.kt`、`core/di/AppGraph.kt`、`ui/component/Charts.kt`、`ui/nav/Routes.kt`、`ui/nav/AppNavHost.kt`、`ui/HomeScreen.kt`；`ui/page/practice/{PracticeScreen,PracticeViewModel,PracticeModels}.kt`；`ui/page/flow/{FlowScreen,FlowViewModel,FlowSummaryScreen,FlowSummaryViewModel,FlowModels}.kt`；`ui/page/story/{StoryRuntime,StoryHomeScreen,StoryHomeViewModel,StoryRecordScreen,StoryRecordViewModel,StoryDetailScreen,StoryDetailViewModel,StoryReviewScreen,StoryReviewViewModel}.kt`；`ui/page/account/{ParentScreen,ParentViewModel,VoicesScreen,VoicesViewModel,HealthScreen,HealthViewModel,MeScreen,MeViewModel,SettingsScreen,SettingsViewModel,AvatarScreen,AvatarViewModel}.kt`。
> 行数口径：每个文件当前总行数（`read` 工具返回的 total lines）；本项目无 gradle wrapper/无法 git diff，故不区分新增/修改行。

---

## 3. 问题清单（最终快照：0 条未解决；2 条 QA 过程中发现并已修复）

| # | 归属 | 问题（已关闭） | 证据 / 修复 |
|---|---|---|---|
| P-1 | feature-list（账号页） | 设置页 PATCH 成功后**没有** `voicePrefs.syncFromAccount(...)`，与音色页不一致 → 设置页改「语速/音色」后跟读/连读示范音仍用旧本机偏好 | **已修复**：`SettingsViewModel.kt:151-153`（GET 后同步）、`:209`（PATCH 后同步）、`:424/430`（展示生效音色/语速）；与 `VoicesViewModel.kt:76/168` 对齐 |
| P-2 | feature-list（账号页） | `avatar_presets=false` 只统一到「我的」入口；设置页形象入口与形象页本身无能力判据 | **已修复**：`SettingsViewModel.kt:237-267` + `SettingsScreen.kt:463-469`（设置页置灰）；`AvatarViewModel.kt:81-101` + `AvatarScreen.kt:92/145-161`（形象页不可用卡片 + 重试）；与 `MeScreen.kt:132-138/176-182` 三处统一 |

> 复核方式：按 ROUND2 §4 逐条 grep 调用点/参数/接线；除上述两条（已关闭）外，未发现签名漂移、Service 调用参数不匹配、导航接线缺失或 TODO 空实现。

---

## 4. 平台 / 后端限制（不是本轮缺陷）

| 限制 | 说明 | 应对 |
|---|---|---|
| 打印 / 导出文件下载 | Web 专属能力（单篇/故事集打印、PDF）；Android 无打印页 | 移动端用「复制全文 / 弹层展示 + 一键复制」替代（本轮故事详情复制全文已补；建议箱 round1 已做） |
| 深色模式 / 平板双栏 / 无障碍极限档 | CONTRACT §0 只要求手机竖屏为主；`EcTheme` 仅浅色 | 后续 M3 再做 |
| `POST /auth/password`（本人改密，需旧密码） | 后端未实现 | 复用 `POST /family/members/:id/password`（设置页本人改密弹层、家庭成员页重置） |
| 批量 OCR | 服务端/产品仅单张（`FlowViewModel` 单图选择） | 首版单张；多张后续 |
| 故事原始录音（中文原声） | `POST /story/recordings` 线上 404，服务端不保存 | 本机持久化（`StoryRuntime`: JSON 路径 + 缓存文件），清缓存/换机/删文件后只保留文字并隐藏回放 |
| 复述历史 | 无服务端接口 | 本机只保留最近一次复述（`StoryRuntime.addRetell`） |
| `GET /tts/voices` 线上 404 | 无服务端音色清单 | 内置 9 音色常量（round1 已定） |
| `GET /sentences/:id/attempts` 线上不存在 | 无单句历史接口 | `GET /attempts?limit=` 客户端过滤（单句历史/回放） |
| 本机无法编译验证 | 本机无 Android SDK；本会话 shell 沙箱不可用 | 以「import/符号/调用参数/签名」静态核对为准；最终需在有 SDK 的机器跑 `:app:compileDebugKotlin` |

---

## 5. 静态检查

> 由 Lead 收尾统一执行（teammate 会话中 shell 沙箱后端不可用，Lead 用提权命令执行）。

**① `python tools/check_android.py`（结构 / 导入 / 页面契约）**

```
Kotlin 文件：115 个
静态检查通过 ✅          # exit 0
```
覆盖：package↔目录、跨文件 import 可解析、27 个页面 composable 签名（含本轮新增
`FlowSummaryScreen(+onOpenReview)` / `ParentScreen(+onOpenBlindTest)` / `VoicesScreen(+onOpenSettings)` /
`PendingUploadsScreen(onBack)`）、括号配平、同包重复声明、未声明第三方依赖、TODO 残留。

**② `python tools/check_members.py`（成员级，本轮新增）**

```
成员级检查：115 个 Kotlin 文件；数据类 232，Service 8
成员级检查通过 ✅          # exit 0
```
覆盖：所有 `XxxDto(...)` 命名参数存在于该 data class、`AppGraph.container.<service>.<method>(...)`
方法存在且命名参数/位置参数匹配、`AppGraph.container.<field>` 字段存在、`Routes/Tabs/NavParams/TabNav/
Navigator/EcColor/EcFont/EcSpace/EcRadius/EcButtonSize/EcScore/Voices` 成员存在、枚举值有效。

**③ 冒烟编译（Kotlin 1.9.22 + 桩）**：见 `SMOKE_COMPILE.md` §9（Lead 收尾执行）。

- 仍未执行 `:app:compileDebugKotlin`（本机无 Android SDK）；Compose UI 文件不在冒烟编译覆盖范围。
- 结论：结构与跨文件调用一致，**无悬空引用**；剩余风险集中在 Compose 运行时 / Android 平台真实签名。

---

## 6. 验收总表

| # | 能力 | 状态 |
|---|---|---|
| 1 | `EcRadarChart` + practice 调用 | ✅ |
| 2 | practice 全屏结果 overlay / 历史逐条回放 / `HorizontalPager` | ✅ |
| 3 | practice + flow 使用 `voicePrefs.resolve` | ✅ |
| 4 | practice + flow `pendingUploads.enqueue` | ✅ |
| 5 | `PendingUploadsScreen` + `Routes.PENDING_UPLOADS` 接线 | ✅ |
| 6 | flow 汇总 `onOpenReview` + 故事 id 来源 | ✅ |
| 7 | 故事 5 项（分组/连续天数、auto_illustrate、保存跳详情、复制全文、StoryRuntime 持久化） | ✅ |
| 8 | 账号 6 项（家长盲测入口、音色去设置、健康 force、capability 隐藏形象、设置同步 voicePrefs、我的待补评分入口） | ✅ 6/6（P-1/P-2 已在快照前修复） |
| 9 | data-layer 5 个基础设施（CapabilityCache / VoicePrefs / PendingUploadQueue / CacheStore LRU / PracticeService 增补） | ✅ |

> **总评**：ROUND2 §4 的 9 组核对项全部 ✅；无未解决的真实问题；剩余仅平台/后端限制（§4）。代码由多人并行完成，本报告全部结论以最终快照代码为准（`read/grep` 复核，未采信口头报告）。

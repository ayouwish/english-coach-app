# 第二轮契约增补（ROUND2）· 补齐功能缺口 + 离线能力

> 用户要求「不要只写 demo，要全部实现」。第一轮已覆盖 M1 全部页面；本轮补齐第一轮文档里标 🚧/⏭️ 的
> 功能缺口，并实现原设计文档里「M2 离线能力」的落地方案。**与 CONTRACT.md 冲突时以本文件为准。**

---

## 1. 本轮新增的共享基础设施（data-layer 负责实现，其他人直接调用）

### 1.1 `core/content/CapabilityCache.kt`（能力开关统一来源）

```kotlin
package top.dreamsearch.englishcoach.core.content

class CapabilityCache(private val api: ApiClient) {
    data class Capabilities(
        val image: Boolean = true,          // 插画 / 自动插图
        val ocr: Boolean = true,            // 拍照识别书页
        val avatarPresets: Boolean = true,  // 预置形象库可用
        val audioConcat: Boolean = true,    // 整段回放
        val wordIpa: Boolean = true,        // 点词音标
        val asrProviders: List<String> = emptyList(),
    )
    fun cached(): Capabilities?             // 5 分钟内复用，过期返回 null
    suspend fun refresh(force: Boolean = false): Capabilities
}
```
- 数据源：`GET /health`（web features）+ `voice.capabilities`（image/ocr/avatar_presets/audio_concat/word_ipa/asr_providers）。
- 调用方：`AppGraph.container.capability`（已由 Lead 在 `AppContainer` 声明）。

### 1.2 `core/audio/VoicePrefs.kt`（账号语音偏好本机镜像）

```kotlin
package top.dreamsearch.englishcoach.core.audio

class VoicePrefs(private val prefs: AppPrefs) {
    data class VoiceChoice(val voice: String?, val rate: String)   // rate: "slow" | "normal"
    var ttsVoice: String?      // null = 服务端默认音色
    var ttsRate: String        // 默认 "normal"
    /** 儿童强制 slow；未设置音色时儿童用内置童声 "en-US-AnaNeural"。 */
    fun resolve(isChild: Boolean): VoiceChoice
    /** 设置页/`/settings` 的账号偏好写回本机镜像后再 resolve。 */
    fun syncFromAccount(ttsVoice: String?, ttsRate: String?)
    fun put(voice: String?, rate: String)
}
```
- 调用方：`AppGraph.container.voicePrefs`（Lead 已声明）。
- 示范音/对话朗读/鼓励语统一走 `resolve(isChild)`，不再各页写死 `normal/slow`。

### 1.3 `core/offline/PendingUploadQueue.kt`（失败录音队列，离线能力）

```kotlin
package top.dreamsearch.englishcoach.core.offline

class PendingUploadQueue(private val context: Context, private val cacheStore: CacheStore) {
    data class PendingUpload(
        val id: String,
        val sentenceId: String,
        val referenceText: String,
        val fileName: String,
        val durationMs: Int,
        val mode: String,
        val blindTestId: String?,
        val createdAt: Long,
        val retryCount: Int,
        val lastError: String?,
    ) { val file: File }

    data class RetrySummary(val attempted: Int, val succeeded: Int, val failed: Int, val lastError: String?)

    /** 录音文件拷进队列目录（原文件可随后删除）；返回 false = 落盘失败（页面提示但不阻塞）。 */
    fun enqueue(audioFile: File, sentenceId: String, referenceText: String, durationMs: Int,
                mode: String = "scripted", blindTestId: String? = null): Boolean
    fun list(): List<PendingUpload>
    fun count(): Int
    fun remove(id: String)
    fun clear()
    /** 串行重试（每次重试前重新读 token）；成功项删除并累加 usage；返回汇总。 */
    suspend fun retryAll(practice: PracticeService): RetrySummary
}
```
- 调用方：`AppGraph.container.pendingUploads`（Lead 已声明）。
- 触发入队：跟读提交网络失败/5xx（不是 4xx 业务错误）；入队后页面提示「已保存到本机，稍后可补评分」。
- 队列索引存 `cacheStore.pendingUploadsDir()/queue.json`，录音存同目录。

### 1.4 `core/storage/CacheStore.kt` 增补

```kotlin
fun pendingUploadsDir(): File
/** TTS 缓存 LRU：按 lastModified 淘汰到 maxBytes 以内（默认 200MB）。 */
fun trimTtsCache(maxBytes: Long = 200L * 1024 * 1024)
/** 回放缓存 LRU：默认 300MB。 */
fun trimAudioCache(maxBytes: Long = 300L * 1024 * 1024)
/** 最近评测结果缓存（最多 50 条，LRU），用于离线查看。 */
fun readRecentResult(key: String): String?
fun writeRecentResult(key: String, json: String)
fun clearRecentResults()
```
- `cleanupOnBoot()` 里调用 trim（异常忽略，不阻塞启动）。

### 1.5 `PracticeService` 增补

```kotlin
suspend fun health(force: Boolean = false): HealthDto        // force=true → GET /health?force=1
suspend fun audioByUrl(audioUrl: String): ByteArray          // 传 AttemptItemDto.audio_url（形如 /api/audio/xxx）
```
> 现有 `health()` 调用点保持编译（默认参数）。

---

## 2. 页面签名变更（导航层已按新签名接线，页面必须对齐）

| 页面 | 新签名 |
|---|---|
| `FlowSummaryScreen` | `(onBack: () -> Unit, onOpenFlowTab: () -> Unit, onOpenReview: (materialId: String) -> Unit)` |
| `ParentScreen` | `(onBack: () -> Unit, onOpenFamily: () -> Unit, onOpenSuggestions: () -> Unit, onOpenBlindTest: () -> Unit)` |
| `VoicesScreen` | `(onBack: () -> Unit, onOpenSettings: () -> Unit)` |
| **新增** `ui/page/offline/PendingUploadsScreen.kt` | `@Composable fun PendingUploadsScreen(onBack: () -> Unit)` |

新增路由常量：`Routes.PENDING_UPLOADS`（首页顶部「待补评分」横幅 → 该页）。

---

## 3. 组件增补（ui-kit）

```kotlin
/** 能力雷达图（纯 Canvas）：跟读结果的能力多边形（准确/流利/完整/语调/总分）。 */
@Composable fun EcRadarChart(
    labels: List<String>,
    values: List<Double?>,
    modifier: Modifier = Modifier,
    size: Dp = 160.dp,
    color: Color = EcColor.primary,
    maxValue: Double = 100.0,
)
```

---

## 4. 本轮补齐的功能清单（按负责人）

| 负责人 | 补齐内容 |
|---|---|
| data-layer | §1.1–§1.5 五个基础设施；`CacheStore` LRU；`health(force)`；`audioByUrl`；实现后自测（静态检查 + 冒烟编译） |
| ui-kit | `EcRadarChart` |
| screens-practice | ①结果区能力雷达；②**全屏结果页**（页内 overlay，可关闭/重试/下一句）；③单句历史逐条回放（`audioByUrl`）；④卡片**左右滑动切句**（HorizontalPager，保留上下句按钮）；⑤示范音/跟我读走 `VoicePrefs.resolve(isChild)`；⑥提交失败（网络/5xx）自动 `pendingUploads.enqueue(...)` + 提示 |
| screens-flow | ①汇总页「📝 复述这个故事」入口（仅本轮来自故事材料时显示，`onOpenReview(materialId)`）；②示范音/鼓励语走 `VoicePrefs`；③OCR 入口用 `CapabilityCache`（`ocr=false` 隐藏并说明）；④异步提交失败也入队（`mode="flow"`），汇总页显示"待补评分 N 条" |
| screens-story | ①列表「今天/昨天/更早」分组 + 连续天数 chip；②按 `auto_illustrate` 设置**保存后自动插图**（默认关，开启时不静默扣费：显示"正在生成插画…"和失败重试）；③保存成功后可**跳转详情**（`Navigator.navigate(Routes.STORY_DETAIL)`）；④详情「复制全文」；⑤`StoryRuntime` 原声/复述记录**持久化**（`AppPrefs` 或 `CacheStore` JSON，杀进程后可回看）；⑥整段朗读 building 阶段加「重试」按钮 |
| screens-chat | **新增待补评分页** `ui/page/offline/PendingUploadsScreen.kt` + VM：列表（句文/时间/重试次数/错误）、单条删除、全部重试（`retryAll`）、空态、"为什么会有这条"说明；重试成功显示 usage/分数提示；不引入新依赖 |
| feature-list | 账号页缺口：①家长面板「盲测周报」入口（`onOpenBlindTest`）；②音色页「去设置」入口（`onOpenSettings`）；③服务状态页**强制刷新**（`practice.health(force = true)`，并展示 `stats.healthFull` 的 features）；④`avatar_presets=false` 时「我的形象」入口隐藏/禁用（Me/Settings/形象三处统一用 `CapabilityCache`）；⑤设置 PATCH 成功后 `voicePrefs.syncFromAccount(...)`；⑥「我的」增加「待补评分录音」入口（有 pending 时显示条数） |
| screens-stats | 最终 QA：全仓静态检查 + 交叉核对本轮 8 个新增能力是否真实落地（逐条代码出处），更新 `docs/android-feature-list.md` 与 `docs/feature-index.md` §10 的状态；写 `android/QA_ROUND2.md` |

---

## 5. 纪律

- 只写自己负责的文件；跨文件需要别人改 → 发消息给对方或 Lead。
- 不新增依赖；不写 TODO/空实现；文件顶部中文注释。
- 完成后跑 `python tools/check_android.py`（必须在自己改动后通过）。
- 不执行 git commit。

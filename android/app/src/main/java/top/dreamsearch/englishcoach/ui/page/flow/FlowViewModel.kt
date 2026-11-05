package top.dreamsearch.englishcoach.ui.page.flow

import android.net.Uri
import android.os.SystemClock
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import top.dreamsearch.englishcoach.core.audio.AudioController
import top.dreamsearch.englishcoach.core.audio.RecordingResult
import top.dreamsearch.englishcoach.core.di.AppContainer
import top.dreamsearch.englishcoach.core.error.UiError
import top.dreamsearch.englishcoach.core.net.ApiError
import top.dreamsearch.englishcoach.core.net.ApiErrorCode
import top.dreamsearch.englishcoach.core.net.dto.AsyncResultDto
import top.dreamsearch.englishcoach.core.net.dto.AsyncStatusItemDto
import top.dreamsearch.englishcoach.core.net.dto.IssueDto
import top.dreamsearch.englishcoach.core.net.dto.MaterialDto
import top.dreamsearch.englishcoach.core.net.dto.OcrResultDto
import top.dreamsearch.englishcoach.core.net.dto.SentenceDto
import top.dreamsearch.englishcoach.ui.nav.NavParams
import top.dreamsearch.englishcoach.ui.nav.Navigator
import top.dreamsearch.englishcoach.ui.nav.Routes
import kotlin.math.roundToInt

/**
 * 连读模式（Tab 根页）的状态机与业务编排。
 *
 * 对应 hos：`hos/entry/src/main/ets/viewmodel/FlowVM.ets`（FlowVM）。
 * 业务来源：`.specs/practice-flow.md` §5、`hos/docs/screens.md` §4。
 *
 * 关键约束（照抄 hos）：
 * - `submitAsync` 拿到 attempt id 立刻置 pending 并进下一句，**不等待评分**；
 * - 每 2 秒轮询 `/attempts/status?ids=`，只传 pending/scoring 的 id；全部 settled 停表；
 *   页面不可见（切 Tab / 页面销毁 / 切后台）必须停止轮询，回来时补拉一次并恢复；
 * - 上传串行（[submitMutex] + submitting 状态，不并发上传）；
 * - `runSentences` 保存本批句子，「再读一遍」复用（round+1，不重新抽句）。
 *
 * 数据来源：
 * - 语料：`PracticeService.sentences(level)`；
 * - 我的书页：`FlowService.materialsPage()` / `materialDetail()` / `deletePage()`；
 * - 拍照识别：`FlowService.ocr(bytes, fileName)`（入口可用性走 `CapabilityCache`）；
 * - 保存书页：`FlowService.createPage()` / `updatePage()`；
 * - 评分：`FlowService.submitAsync()` / `status(ids)`；
 * - 示范音：`PracticeService.tts()` → `AudioController.playBytes()`（音色/语速走 `VoicePrefs.resolve`）；
 * - 录音：`AudioController.startRecording()/stopRecording()`（0.6–60s 由组件与 VM 双重校验）。
 *
 * 第二轮（ROUND2_CONTRACT §4）补齐：
 * - 🔊 听示范走 `AppGraph.container.voicePrefs.resolve(isChild)`（不再写死 slow/normal）；
 * - 拍照识别入口能力开关统一走 `AppGraph.container.capability`（`cached()` → 后台 `refresh()`）；
 * - 提交时网络/5xx 失败 → 录音入 `AppGraph.container.pendingUploads`（`mode="flow"`），
 *   该句状态置 [FlowStatus.PENDING_OFFLINE]（不算失败），汇总页可去「待补评分」页处理；
 * - 故事入口（`NavParams.flowMaterialId`）记录来源标记，供汇总页「复述这个故事」使用。
 *
 * 线上不存在的接口（CONTRACT §3.2）：`GET /practice/cursor`、`GET /sentences/:id/attempts` 不调用。
 */
class FlowViewModel(private val c: AppContainer) : ViewModel() {

    private val _state = MutableStateFlow(FlowUiState())
    val state: StateFlow<FlowUiState> = _state.asStateFlow()

    // ---- 内部定时器/标记
    private var pollJob: Job? = null
    private var recordTimerJob: Job? = null
    private var advanceJob: Job? = null
    private var visible: Boolean = false
    private var finished: Boolean = false

    /** 上传串行锁：同一时刻最多一个 /attempts/async 在途（CONTRACT：提交串行、不并发上传）。 */
    private val submitMutex = Mutex()

    init {
        FlowRunStore.attach(this)
        val session = c.session.state.value
        _state.value = FlowUiState(
            isChild = session.isChild,
            exceeded = session.exceeded,
            remainingMinutes = session.remainingMinutes,
            level = c.config.levelForCefr(session.cefrLevel),
        )
        // 登录态 / 额度变化（录音按钮是否可用、儿童文案）
        viewModelScope.launch {
            c.session.state.collect { s ->
                _state.update {
                    it.copy(
                        isChild = s.isChild,
                        exceeded = s.exceeded,
                        remainingMinutes = s.remainingMinutes,
                    )
                }
            }
        }
        // 播放状态（示范音按钮文案）
        viewModelScope.launch {
            c.audio.playing.collect { playing ->
                _state.update { it.copy(audioPlaying = playing) }
            }
        }
        loadOcrCapability()
        // 从故事详情进入（NavParams.flowMaterialId）：直接载入该材料的句子开始连读
        if (NavParams.flowMaterialId != null) {
            consumePendingMaterial()
        } else {
            loadCorpus()
        }
    }

    // ================================================================== 生命周期 / 轮询

    /** 页面可见（首次组合 / 从汇总返回 / 从后台回来）：消费故事跳转参数、恢复轮询、补拉一次。 */
    fun onVisible() {
        visible = true
        consumePendingMaterial()
        val s = _state.value
        if (s.phase != FlowPhase.RUNNING) return
        if (pendingIds().isNotEmpty()) {
            startPolling()
        } else if (s.allSubmitted && !finished) {
            checkAllSettled()
        }
    }

    /** 页面不可见（切 Tab / push 汇总页 / 切后台 / 销毁）：停轮询、丢录音、停播放。 */
    fun onHidden() {
        visible = false
        stopPolling()
        stopRecordTimer()
        advanceJob?.cancel()
        if (_state.value.recording) {
            runCatching { c.audio.cancelRecording() }
            _state.update { it.copy(recording = false, elapsedMs = 0) }
        }
        runCatching { c.audio.stopPlayback() }
    }

    /** 故事详情「去连读」写入的 materialId：读一次立即清空，载入材料句子后直接开跑。 */
    fun consumePendingMaterial() {
        val materialId = NavParams.flowMaterialId ?: return
        NavParams.flowMaterialId = null
        if (materialId.isNotEmpty()) startFromMaterial(materialId)
    }

    override fun onCleared() {
        FlowRunStore.detach(this)
        stopPolling()
        stopRecordTimer()
        advanceJob?.cancel()
        if (_state.value.recording) runCatching { c.audio.cancelRecording() }
        runCatching { c.audio.stopPlayback() }
        super.onCleared()
    }

    private fun pendingIds(): List<String> =
        _state.value.items
            .filter { it.attemptId.isNotEmpty() && (it.status == FlowStatus.PENDING || it.status == FlowStatus.SCORING) }
            .map { it.attemptId }
            .take(MAX_STATUS_IDS)

    /** 启动轮询：`viewModelScope.launch + while (isActive)`，每 2 秒一拍；无待评 id 或页面不可见时不启动。 */
    private fun startPolling() {
        if (!visible) return
        if (_state.value.phase != FlowPhase.RUNNING) return
        if (pendingIds().isEmpty()) return
        if (pollJob?.isActive == true) return
        pollJob = viewModelScope.launch {
            while (isActive) {
                pollOnce()
                if (_state.value.phase != FlowPhase.RUNNING) break
                if (pendingIds().isEmpty()) break
                delay(POLL_INTERVAL_MS)
            }
        }
    }

    private fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    private suspend fun pollOnce() {
        val ids = pendingIds()
        if (ids.isEmpty()) {
            stopPolling()
            checkAllSettled()
            return
        }
        try {
            val updates = c.flow.status(ids)
            if (updates.isNotEmpty()) {
                val byId = updates.associateBy { it.id }
                _state.update { s ->
                    var changed = false
                    val items = s.items.map { item ->
                        val update = if (item.attemptId.isEmpty()) null else byId[item.attemptId]
                        if (update == null) {
                            item
                        } else {
                            changed = true
                            applyStatus(item, update)
                        }
                    }
                    if (changed) s.copy(items = items) else s
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (ignored: Throwable) {
            // 轮询失败静默：下一拍重试（规格 §5.4；不打断正在录音的用户）
        }
        if (pendingIds().isEmpty()) stopPolling()
        checkAllSettled()
    }

    /** 服务端状态 → 本地 item（done 时解析分数/反馈/逐词）。 */
    private fun applyStatus(item: FlowItem, update: AsyncStatusItemDto): FlowItem {
        if (update.status == "failed") {
            return item.copy(
                status = FlowStatus.FAILED,
                error = update.error?.takeIf { it.isNotEmpty() } ?: FAILED_REASON,
                hasResult = false,
            )
        }
        val wire = FlowStatus.fromWire(update.status)
        if (wire != null && wire != FlowStatus.DONE) return item.copy(status = wire)
        if (update.status != "done") return item
        val result = update.result
            ?: return item.copy(status = FlowStatus.FAILED, error = "评分结果格式异常，可以重录这句", hasResult = false)
        return applyResult(item, result)
    }

    private fun applyResult(item: FlowItem, result: AsyncResultDto): FlowItem {
        val scores = result.scores
        val recognized = result.recognizedText
        val child = _state.value.isChild
        val feedback = result.feedback
        return item.copy(
            status = FlowStatus.DONE,
            error = "",
            hasResult = true,
            scorePron = scores?.pron,
            scoreAccuracy = scores?.accuracy,
            scoreFluency = scores?.fluency,
            scoreCompleteness = scores?.completeness,
            scoreProsody = scores?.prosody,
            recognizedText = recognized,
            noSpeech = FlowText.letterCount(recognized) <= 1,
            feedbackSummary = feedback?.summary.orEmpty(),
            feedbackPraise = feedback?.praise.orEmpty(),
            feedbackClosing = feedback?.closing.orEmpty(),
            // 儿童不展示 IPA / 音素信息，只保留成人版前 2 条建议
            pointTitles = if (child) emptyList() else feedback?.points.orEmpty().take(2).map { it.title },
            pointHows = if (child) emptyList() else feedback?.points.orEmpty().take(2).map { it.how },
            words = if (child) {
                emptyList()
            } else {
                result.words
                    .sortedBy { it.score ?: 101.0 }
                    .take(10)
                    .map { FlowWordScore(word = it.word, score = it.score) }
            },
            issueTexts = if (child) emptyList() else issueTexts(result.issues),
        )
    }

    /** 连读详情的问题文案（只有成人版；儿童不出现「发成了」这类对比音素描述）。 */
    private fun issueTexts(issues: List<IssueDto>): List<String> = issues.take(2).map { issue ->
        val word = issue.word
        val expected = issue.expected.orEmpty()
        val actual = issue.actual.orEmpty()
        when {
            word.isEmpty() -> issue.type.ifEmpty { "发音小问题" }
            expected.isNotEmpty() && actual.isNotEmpty() -> "$word：$expected 发成了 $actual"
            else -> word + if (issue.type.isEmpty()) " 发音注意一下" else "：${issue.type}"
        }
    }

    private fun checkAllSettled() {
        val s = _state.value
        if (s.phase != FlowPhase.RUNNING || finished) return
        if (!s.allSubmitted) return
        if (s.items.any { it.status == FlowStatus.PENDING || it.status == FlowStatus.SCORING }) return
        finishRun()
    }

    /** 全部 done/failed → 停表 → 计算汇总快照 → 打开汇总页。 */
    private fun finishRun() {
        if (finished) return
        finished = true
        stopPolling()
        stopRecordTimer()
        advanceJob?.cancel()
        val summary = buildSummary()
        _state.update {
            it.copy(
                phase = FlowPhase.SUMMARY,
                summary = summary,
                recording = false,
                preparing = false,
                submitting = false,
                elapsedMs = 0,
            )
        }
        Navigator.navigate(Routes.FLOW_SUMMARY)
    }

    // ================================================================== setup：语料

    fun loadCorpus() {
        viewModelScope.launch {
            _state.update { it.copy(corpusLoading = true, corpusError = null) }
            try {
                val level = _state.value.level
                val loaded: List<SentenceDto> = if (level == "ALL") {
                    val merged = ArrayList<SentenceDto>()
                    for (lv in LEVELS) {
                        runCatching { c.practice.sentences(lv) }.getOrNull()?.let { merged.addAll(it) }
                    }
                    if (merged.isEmpty()) {
                        throw ApiError.local(ApiErrorCode.BAD_RESPONSE, "语料为空")
                    }
                    merged
                } else {
                    c.practice.sentences(level)
                }
                _state.update { s ->
                    val startIndex = if (s.startIndex >= loaded.size) 0 else s.startIndex
                    s.copy(corpus = loaded, startIndex = startIndex, corpusLoading = false, corpusError = null)
                        .withPreview()
                }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update {
                    it.copy(
                        corpus = emptyList(),
                        preview = emptyList(),
                        corpusLoading = false,
                        corpusError = ui,
                    )
                }
            }
        }
    }

    fun setLevel(level: String) {
        if (_state.value.level == level) return
        _state.update { it.copy(level = level, startIndex = 0, randomPick = emptyList(), setupError = null) }
        loadCorpus()
    }

    fun setCount(value: Int) {
        if (_state.value.count == value) return
        _state.update { it.copy(count = value) }
        if (_state.value.randomMode) {
            drawRandom()
        } else {
            _state.update { it.withPreview() }
        }
    }

    fun setStartIndex(value: Int) {
        val s = _state.value
        val max = (s.corpus.size - 1).coerceAtLeast(0)
        _state.update { it.copy(startIndex = value.coerceIn(0, max)).withPreview() }
    }

    fun toggleRandom() {
        val random = !_state.value.randomMode
        _state.update { it.copy(randomMode = random) }
        if (random) {
            drawRandom()
        } else {
            _state.update { it.copy(randomPick = emptyList()).withPreview() }
        }
    }

    /** 🎲 随机 / 🔀 换一批：从当前级别池里不重复抽 count 句（事件回调里抽，渲染期不随机）。 */
    fun drawRandom() {
        val s = _state.value
        val pool = s.corpus
        if (pool.isEmpty()) {
            _state.update { it.copy(randomPick = emptyList()).withPreview() }
            return
        }
        val indices = pool.indices.toMutableList()
        for (i in indices.size - 1 downTo 1) {
            val j = (0..i).random()
            val tmp = indices[i]
            indices[i] = indices[j]
            indices[j] = tmp
        }
        val wanted = s.count.coerceAtMost(pool.size)
        val picked = (0 until wanted).map { pool[indices[it]] }
        _state.update { it.copy(randomPick = picked).withPreview() }
    }

    // ================================================================== setup：我的书页

    fun loadMaterials() {
        if (_state.value.materialsLoading) return
        viewModelScope.launch {
            _state.update { it.copy(materialsLoading = true, materialsError = null) }
            try {
                val list = c.flow.materialsPage(50)
                _state.update { it.copy(materials = list, materialsLoading = false) }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(materialsLoading = false, materialsError = ui) }
            }
        }
    }

    /** 点开书页：读详情 → 把文本灌进「自己输入」并切句（可再改），带上 material_id 提交。 */
    fun openMaterial(id: String) {
        if (_state.value.materialBusyId.isNotEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(materialBusyId = id, materialsError = null) }
            try {
                val detail = c.flow.materialDetail(id)
                val text = detail.text.trim()
                if (text.isEmpty()) {
                    _state.update {
                        it.copy(
                            materialBusyId = "",
                            materialsError = UiError.of("not_found", "这篇书页只有图片、没有文字，换一篇试试", false),
                        )
                    }
                    return@launch
                }
                _state.update {
                    it.copy(
                        materialBusyId = "",
                        runMaterialId = id,
                        customInput = text,
                        customSentences = FlowText.splitMaterial(text),
                        editingMaterialId = "",
                        savedPageId = "",
                        savedPageTitle = "",
                        sourceTab = 2,
                        setupError = null,
                    )
                }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(materialBusyId = "", materialsError = ui) }
            }
        }
    }

    /** 编辑书页：读详情 → 灌进「自己输入」→ 保存时走 PATCH /materials/:id。 */
    fun beginEdit(id: String) {
        if (_state.value.materialEditBusyId.isNotEmpty()) return
        viewModelScope.launch {
            _state.update {
                it.copy(materialEditBusyId = id, materialsError = null, setupError = null, saveError = null)
            }
            try {
                val detail = c.flow.materialDetail(id)
                _state.update {
                    it.copy(
                        materialEditBusyId = "",
                        customInput = detail.text,
                        customSentences = FlowText.splitMaterial(detail.text),
                        saveTitle = detail.title,
                        editingMaterialId = id,
                        savedPageId = "",
                        savedPageTitle = "",
                        sourceTab = 2,
                    )
                }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(materialEditBusyId = "", materialsError = ui) }
            }
        }
    }

    /** 删除书页（服务端校验只能删自己录入的）。 */
    fun removeMaterial(id: String) {
        if (_state.value.materialEditBusyId.isNotEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(materialEditBusyId = id, materialsError = null) }
            try {
                c.flow.deletePage(id)
                _state.update { s ->
                    if (s.editingMaterialId == id) {
                        s.copy(
                            editingMaterialId = "",
                            customInput = "",
                            customSentences = emptyList(),
                            saveTitle = "",
                            savedPageId = "",
                            savedPageTitle = "",
                            materialEditBusyId = "",
                        )
                    } else {
                        s.copy(materialEditBusyId = "")
                    }
                }
                loadMaterials()
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(materialEditBusyId = "", materialsError = ui) }
            }
        }
    }

    /** 取消编辑，回到普通输入状态。 */
    fun cancelEdit() {
        _state.update {
            it.copy(
                editingMaterialId = "",
                customInput = "",
                customSentences = emptyList(),
                saveTitle = "",
                savedPageId = "",
                savedPageTitle = "",
                saveError = null,
            )
        }
    }

    // ================================================================== setup：自己输入 / 拍照识别

    fun setCustomInput(text: String) {
        _state.update { it.copy(customInput = text, runMaterialId = "") }
    }

    /** ✂️ 切句（多行按行、行内再按 . ! ? 。！？ 切）。 */
    fun splitCustom() {
        val text = _state.value.customInput
        val sentences = FlowText.splitMaterial(text)
        _state.update {
            it.copy(
                runMaterialId = "",
                customSentences = sentences,
                setupError = if (sentences.isEmpty()) {
                    UiError.of(
                        "bad_request",
                        if (it.isChild) "先写几句英文吧" else "没有切出句子：先输入一段英文，再点「切句」",
                        false,
                    )
                } else {
                    null
                },
            )
        }
    }

    fun updateCustomSentence(index: Int, text: String) {
        _state.update { s ->
            if (index !in s.customSentences.indices) {
                s
            } else {
                val next = s.customSentences.toMutableList()
                next[index] = text
                s.copy(customSentences = next)
            }
        }
    }

    /**
     * 拍照/相册选图后的识别：读 bytes → `FlowService.ocr(bytes, fileName)` → 追加到「自己输入」文本框。
     * 图片只在内存/缓存中过一遍，不落库（服务端 OCR 不保存原图）。
     */
    fun ocr(uri: Uri) {
        if (_state.value.ocrBusy) return
        viewModelScope.launch {
            _state.update { it.copy(ocrBusy = true, ocrError = null, ocrInfoText = "") }
            try {
                val resolver = c.appContextRef.contentResolver
                val mime = resolver.getType(uri).orEmpty()
                val fileName = ocrFileName(mime)
                val bytes = withContext(Dispatchers.IO) {
                    runCatching { resolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
                } ?: throw ApiError.local(ApiErrorCode.BAD_REQUEST, "读取照片失败，请重新选择一张")
                if (bytes.isEmpty()) {
                    throw ApiError.local(ApiErrorCode.BAD_REQUEST, "读取照片失败，请重新选择一张")
                }
                if (bytes.size > MAX_OCR_BYTES) {
                    throw ApiError.local(ApiErrorCode.PAYLOAD_TOO_LARGE, "照片太大了（上限 12MB），换一张小一点的")
                }
                val result = c.flow.ocr(bytes, fileName)
                val text = result.text.trim()
                if (text.isEmpty()) {
                    _state.update {
                        it.copy(
                            ocrBusy = false,
                            ocrError = UiError.of(
                                "bad_response",
                                if (it.isChild) {
                                    "这张图里没有找到英文句子，换一张更清楚的照片试试，或者用「自己输入」"
                                } else {
                                    "这张图里没有识别到英文文字。换一张更清晰、文字更大的照片，或改用「自己输入一段」"
                                },
                                false,
                            ),
                        )
                    }
                    return@launch
                }
                appendOcrText(text, result)
                _state.update { it.copy(ocrBusy = false) }
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(ocrBusy = false, ocrError = ui) }
            }
        }
    }

    private fun appendOcrText(text: String, result: OcrResultDto) {
        val info = buildString {
            append("已识别 ")
            append(result.lines.size)
            append(" 行 · ")
            append(result.provider.ifEmpty { "-" })
            append(" · ")
            append(result.elapsedMs)
            append("ms，已追加到下面的文本框")
        }
        _state.update { s ->
            val prev = s.customInput.trim()
            val merged = if (prev.isEmpty()) text else prev + "\n" + text
            s.copy(
                sourceTab = 2,
                runMaterialId = "",
                customInput = merged,
                customSentences = FlowText.splitMaterial(merged),
                saveTitle = FlowText.firstLine(text, 40),
                savedPageId = "",
                savedPageTitle = "",
                saveError = null,
                ocrInfoText = info,
                setupError = null,
            )
        }
    }

    private fun ocrFileName(mime: String): String = when (mime.lowercase()) {
        "image/png" -> "page.png"
        "image/heic" -> "page.heic"
        "image/heif" -> "page.heif"
        "image/webp" -> "page.webp"
        else -> "page.jpg"
    }

    // ================================================================== setup：保存书页

    fun setSaveTitle(title: String) {
        _state.update { it.copy(saveTitle = title) }
    }

    /** 💾 保存为「我的书页」（新建 POST /materials；编辑态走 PATCH）。 */
    fun saveAsPage() {
        viewModelScope.launch {
            savePageInternal()
        }
    }

    /** 保存后直接连读（已保存过就直接开始）。 */
    fun saveAndRead() {
        viewModelScope.launch {
            if (_state.value.savedPageId.isEmpty() && _state.value.editingMaterialId.isEmpty()) {
                savePageInternal()
            } else if (_state.value.editingMaterialId.isNotEmpty()) {
                savePageInternal()
            }
            val id = _state.value.savedPageId
            if (id.isEmpty()) return@launch
            _state.update { it.copy(runMaterialId = id) }
            startCustom()
        }
    }

    private suspend fun savePageInternal(): Boolean {
        val s = _state.value
        if (s.saveBusy) return false
        if (s.savedPageId.isNotEmpty() && s.editingMaterialId.isEmpty()) return true
        val text = pageTextOf(s)
        if (text.isEmpty()) {
            _state.update {
                it.copy(saveError = UiError.of("bad_request", "还没有可保存的文字", false))
            }
            return false
        }
        _state.update { it.copy(saveBusy = true, saveError = null) }
        return try {
            val title = s.saveTitle.trim().ifEmpty { "未命名书页" }
            if (s.editingMaterialId.isNotEmpty()) {
                c.flow.updatePage(s.editingMaterialId, title, text)
                _state.update {
                    it.copy(
                        saveBusy = false,
                        savedPageId = s.editingMaterialId,
                        savedPageTitle = title,
                        editingMaterialId = "",
                    )
                }
            } else {
                val created = c.flow.createPage(title, text)
                _state.update { it.copy(saveBusy = false, savedPageId = created.id, savedPageTitle = title) }
            }
            loadMaterials()
            true
        } catch (e: Throwable) {
            val ui = c.session.toUiErrorAsync(e)
            _state.update { it.copy(saveBusy = false, saveError = ui) }
            false
        }
    }

    /** 优先保存「逐句修改后」的文本；没有切过句再用原输入（与 hos 一致）。 */
    private fun pageTextOf(s: FlowUiState): String {
        val joined = s.customSentences.filter { it.isNotBlank() }.joinToString(" ").trim()
        return joined.ifEmpty { s.customInput.trim() }
    }

    // ================================================================== 开始连读

    fun startCorpus() {
        val preview = _state.value.preview
        if (preview.isEmpty()) {
            _state.update {
                it.copy(
                    setupError = UiError.of(
                        "bad_request",
                        if (it.isChild) "这里还没有句子，换一个起点吧" else "这个位置没有句子，换个起点或级别试试",
                        false,
                    ),
                )
            }
            return
        }
        val sentences = preview.map {
            FlowRunSentence(
                text = it.text,
                sentenceId = it.id,
                source = "corpus",
                materialId = "",
                translationZh = it.translationZh,
            )
        }
        beginRun(sentences, runTitle = "", materialId = "")
    }

    fun startCustom() {
        val s = _state.value
        val list = s.effectiveCustomSentences
        if (s.customSentences.isEmpty() && list.isNotEmpty()) {
            _state.update { it.copy(customSentences = list) }
        }
        if (list.isEmpty()) {
            _state.update {
                it.copy(
                    setupError = UiError.of(
                        "bad_request",
                        if (it.isChild) "先写几句话吧" else "先输入一段文本，再点「切句」",
                        false,
                    ),
                )
            }
            return
        }
        val materialId = s.runMaterialId
        val sentences = list.map { text ->
            text.trim().takeIf { it.isNotEmpty() }?.let {
                FlowRunSentence(text = it, sentenceId = "", source = "custom", materialId = materialId)
            }
        }.filterNotNull()
        if (sentences.isEmpty()) {
            _state.update {
                it.copy(setupError = UiError.of("bad_request", "切出来的句子都是空的，再检查一下文本", false))
            }
            return
        }
        beginRun(sentences, runTitle = "", materialId = materialId)
    }

    /** 故事详情「去连读」：读材料正文 → 切句 → 直接开跑（带 materialId，汇总页可回故事复述）。 */
    private fun startFromMaterial(materialId: String) {
        viewModelScope.launch {
            _state.update { it.copy(startingRun = true, setupError = null) }
            try {
                val detail = c.flow.materialDetail(materialId)
                val sentences = FlowText.splitMaterial(detail.text)
                if (sentences.isEmpty()) {
                    _state.update {
                        it.copy(
                            startingRun = false,
                            setupError = UiError.of(
                                "bad_request",
                                if (it.isChild) {
                                    "这个故事还没有英文句子，先回故事页生成一下"
                                } else {
                                    "这篇材料里没有找到可读的英文句子，先回故事页生成一下"
                                },
                                false,
                            ),
                        )
                    }
                    return@launch
                }
                _state.update { it.copy(startingRun = false) }
                // 故事材料（kind=story，或旧数据没有 kind）→ 汇总页允许「复述这个故事」
                val fromStory = detail.kind.isEmpty() || detail.kind.equals("story", ignoreCase = true)
                beginRun(
                    sentences = sentences.map {
                        FlowRunSentence(text = it, sentenceId = "", source = "custom", materialId = materialId)
                    },
                    runTitle = detail.title,
                    materialId = materialId,
                    fromStoryMaterial = fromStory,
                )
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(startingRun = false, setupError = ui) }
            }
        }
    }

    private fun beginRun(
        sentences: List<FlowRunSentence>,
        runTitle: String,
        materialId: String,
        round: Int = 1,
        fromStoryMaterial: Boolean = false,
    ) {
        stopPolling()
        stopRecordTimer()
        advanceJob?.cancel()
        finished = false
        _state.update { s ->
            s.copy(
                phase = FlowPhase.RUNNING,
                runSentences = sentences,
                items = sentences.mapIndexed { index, sentence ->
                    FlowItem(
                        index = index,
                        text = sentence.text,
                        sentenceId = sentence.sentenceId,
                        source = sentence.source,
                        materialId = sentence.materialId,
                        translationZh = sentence.translationZh,
                    )
                },
                currentIndex = 0,
                round = round,
                runTitle = runTitle,
                runMaterialId = materialId,
                runFromStoryMaterial = fromStoryMaterial,
                expandedIndex = -1,
                allSubmitted = false,
                limitReached = false,
                limitMessage = "",
                recording = false,
                preparing = false,
                submitting = false,
                elapsedMs = 0,
                error = null,
                setupError = null,
                summary = null,
            )
        }
    }

    /** 汇总页「再读一遍」：同一批句子重置为 unsent，round+1，不重新抽句。 */
    fun reread() {
        val s = _state.value
        if (s.runSentences.isEmpty()) return
        beginRun(
            s.runSentences,
            runTitle = s.runTitle,
            materialId = s.runMaterialId,
            round = s.round + 1,
            fromStoryMaterial = s.runFromStoryMaterial,
        )
    }

    /** 汇总页「再读一段」：清空本次，回 setup。 */
    fun backToSetup() {
        stopPolling()
        stopRecordTimer()
        advanceJob?.cancel()
        finished = false
        _state.update {
            it.copy(
                phase = FlowPhase.SETUP,
                items = emptyList(),
                runSentences = emptyList(),
                currentIndex = 0,
                round = 1,
                expandedIndex = -1,
                allSubmitted = false,
                limitReached = false,
                limitMessage = "",
                recording = false,
                preparing = false,
                submitting = false,
                elapsedMs = 0,
                error = null,
                setupError = null,
                summary = null,
                runTitle = "",
                runMaterialId = "",
                runFromStoryMaterial = false,
            )
        }
    }

    // ================================================================== running：录音 / 提交

    fun currentItem(): FlowItem? = _state.value.items.getOrNull(_state.value.currentIndex)

    fun startRecording() {
        val s = _state.value
        if (s.phase != FlowPhase.RUNNING || s.recording || s.preparing || s.submitting) return
        if (s.exceeded) {
            _state.update { st ->
                st.copy(
                    error = UiError.of(
                        ApiErrorCode.DAILY_LIMIT_REACHED,
                        if (st.isChild) "今天已经练得很棒啦，明天再来 🌙" else "今天的练习时长已达上限，明天再来",
                        false,
                    ),
                )
            }
            return
        }
        if (s.limitReached) {
            _state.update { st ->
                st.copy(error = UiError.of(ApiErrorCode.DAILY_LIMIT_REACHED, "今天的练习时间到啦，明天再来吧 🌙", false))
            }
            return
        }
        val item = s.items.getOrNull(s.currentIndex) ?: return
        if (item.status != FlowStatus.UNSENT) {
            _state.update { st ->
                st.copy(error = UiError.of("bad_request", "这一句已经提交过了，点「下一句」继续", false))
            }
            return
        }
        _state.update { it.copy(preparing = true, error = null, limitMessage = "") }
        try {
            c.audio.startRecording("flow_rec")
            _state.update { it.copy(preparing = false, recording = true, elapsedMs = 0) }
            startRecordTimer()
        } catch (e: Throwable) {
            _state.update { it.copy(preparing = false) }
            setUiError(e)
        }
    }

    fun stopAndSubmit() {
        val s = _state.value
        if (!s.recording) return
        stopRecordTimer()
        _state.update { it.copy(recording = false) }
        val index = s.currentIndex
        val recorded = try {
            c.audio.stopRecording()
        } catch (e: Throwable) {
            _state.update { it.copy(elapsedMs = 0) }
            setUiError(e)
            return
        }
        submitAsync(index, recorded)
    }

    fun cancelRecording() {
        stopRecordTimer()
        runCatching { c.audio.cancelRecording() }
        _state.update { it.copy(recording = false, preparing = false, elapsedMs = 0) }
    }

    /** 上传（串行）：拿到 id 立即置 pending 并进下一句，不等待评分。 */
    private fun submitAsync(index: Int, recorded: RecordingResult) {
        viewModelScope.launch {
            submitMutex.withLock {
                val item = _state.value.items.getOrNull(index)
                if (item == null) {
                    recorded.file.delete()
                    return@withLock
                }
                _state.update { it.copy(submitting = true, error = null) }
                try {
                    val audio = withContext(Dispatchers.IO) { recorded.file.readBytes() }
                    val dto = c.flow.submitAsync(
                        audio = audio,
                        sentenceId = item.sentenceId.ifEmpty { null },
                        referenceText = item.text,
                        source = item.source,
                        materialId = item.materialId.ifEmpty { null },
                        durationMs = recorded.durationMs.toInt(),
                    )
                    val attemptId = dto.resolvedId
                    if (attemptId.isEmpty()) {
                        throw ApiError.local(ApiErrorCode.BAD_RESPONSE, "提交返回缺少 id")
                    }
                    updateItem(index) {
                        it.copy(
                            attemptId = attemptId,
                            status = FlowStatus.PENDING,
                            error = "",
                            hasResult = false,
                        )
                    }
                    recorded.file.delete()
                    afterSubmitted(index)
                } catch (e: CancellationException) {
                    recorded.file.delete()
                    throw e
                } catch (e: Throwable) {
                    val ui = c.session.toUiErrorAsync(e)
                    // 第二轮：网络/5xx 失败 → 录音入「待补评分」队列，该句不算失败（状态 pending-offline）；
                    // 4xx 业务错误（额度/内容审核/参数）与鉴权失败仍按失败展示。
                    if (isOfflineRetryable(e) && enqueuePendingUpload(recorded, item)) {
                        updateItem(index) {
                            it.copy(
                                status = FlowStatus.PENDING_OFFLINE,
                                error = if (_state.value.isChild) {
                                    "这句存好啦，等会儿再评分"
                                } else {
                                    "已存本机，稍后补评分"
                                },
                                hasResult = false,
                            )
                        }
                        _state.update { it.copy(error = null) }
                        afterSubmitted(index)
                    } else {
                        updateItem(index) { it.copy(status = FlowStatus.FAILED, error = ui.message) }
                        if (ui.code == ApiErrorCode.DAILY_LIMIT_REACHED) {
                            _state.update { it.copy(limitReached = true, limitMessage = ui.message) }
                        } else {
                            _state.update { it.copy(error = ui) }
                        }
                    }
                    recorded.file.delete()
                } finally {
                    _state.update { it.copy(submitting = false) }
                }
            }
        }
    }

    /** 提交失败的录音入「待补评分」队列（`mode="flow"`）；返回 false = 落盘失败（按失败处理）。 */
    private fun enqueuePendingUpload(recorded: RecordingResult, item: FlowItem): Boolean = runCatching {
        c.pendingUploads.enqueue(
            audioFile = recorded.file,
            sentenceId = item.sentenceId,
            referenceText = item.text,
            durationMs = recorded.durationMs.toInt(),
            mode = "flow",
        )
    }.getOrElse { false }

    /**
     * 只有「传输层/服务端暂时不可用」才值得入队重试：
     * - `status = 0` 的本地网络错误（`network_unreachable` / `timeout`）；
     * - HTTP 5xx、`provider_error`、`provider_timeout`（`ApiError.retryable` 已覆盖 502/503/504）。
     * 4xx 业务错误（额度/内容审核/参数）与 401 鉴权失败不入队，避免把"永远失败"的请求囤在本机。
     */
    private fun isOfflineRetryable(e: Throwable): Boolean {
        val err = e as? ApiError ?: return false
        if (err.status == 0) {
            return err.code == ApiErrorCode.NETWORK_UNREACHABLE || err.code == ApiErrorCode.TIMEOUT
        }
        return err.retryable || err.status >= 500
    }

    private fun afterSubmitted(index: Int) {
        _state.update { it.copy(allSubmitted = it.items.none { item -> item.status == FlowStatus.UNSENT }) }
        startPolling()
        if (!_state.value.autoNext) {
            // 关闭自动下一句：当前句已提交，页面显示「下一句 →」由用户点
            checkAllSettled()
            return
        }
        advanceJob?.cancel()
        advanceJob = viewModelScope.launch {
            delay(ADVANCE_DELAY_MS)
            // 用户可能在这 400ms 内自己点了「下一句」：此时不要再抢着跳，避免跳过还没读的句子
            if (_state.value.currentIndex != index) {
                checkAllSettled()
                return@launch
            }
            val next = nextUnsentIndex(index)
            if (next >= 0) {
                _state.update { it.copy(currentIndex = next, error = null) }
            } else {
                checkAllSettled()
            }
        }
    }

    private fun updateItem(index: Int, transform: (FlowItem) -> FlowItem) {
        _state.update { s ->
            val item = s.items.getOrNull(index) ?: return@update s
            val next = s.items.toMutableList()
            next[index] = transform(item)
            s.copy(items = next)
        }
    }

    private fun nextUnsentIndex(from: Int): Int {
        val items = _state.value.items
        for (i in (from + 1) until items.size) {
            if (items[i].status == FlowStatus.UNSENT) return i
        }
        for (i in items.indices) {
            if (items[i].status == FlowStatus.UNSENT) return i
        }
        return -1
    }

    fun hasNextUnsent(): Boolean = nextUnsentIndex(_state.value.currentIndex) >= 0

    fun nextSentence() {
        advanceJob?.cancel()
        val next = nextUnsentIndex(_state.value.currentIndex)
        if (next >= 0) {
            _state.update { it.copy(currentIndex = next, error = null) }
        }
        checkAllSettled()
    }

    /** 「重录这句」：重置该条并跳回去（旧的 pending 结果直接丢弃）。 */
    fun retryItem(index: Int) {
        val s = _state.value
        val item = s.items.getOrNull(index) ?: return
        stopPolling()
        advanceJob?.cancel()
        finished = false
        if (item.status == FlowStatus.UNSENT) {
            _state.update {
                it.copy(phase = FlowPhase.RUNNING, currentIndex = index, expandedIndex = -1, error = null)
            }
            return
        }
        _state.update { st ->
            val items = st.items.toMutableList()
            items[index] = item.resetForRedo()
            st.copy(
                items = items,
                currentIndex = index,
                expandedIndex = -1,
                phase = FlowPhase.RUNNING,
                allSubmitted = false,
                limitReached = false,
                limitMessage = "",
                recording = false,
                preparing = false,
                submitting = false,
                elapsedMs = 0,
                error = null,
            )
        }
    }

    fun toggleExpanded(index: Int) {
        _state.update { it.copy(expandedIndex = if (it.expandedIndex == index) -1 else index) }
    }

    fun toggleAutoNext() {
        _state.update { it.copy(autoNext = !it.autoNext) }
    }

    private fun startRecordTimer() {
        stopRecordTimer()
        val startedAt = SystemClock.elapsedRealtime()
        recordTimerJob = viewModelScope.launch {
            while (isActive && _state.value.recording) {
                delay(RECORD_TICK_MS)
                val elapsed = SystemClock.elapsedRealtime() - startedAt
                _state.update { it.copy(elapsedMs = elapsed) }
                if (elapsed >= AudioController.MAX_DURATION_MS) {
                    // 到 60s 自动结束并提交（本地时长上限，不切片）
                    stopAndSubmit()
                    break
                }
            }
        }
    }

    private fun stopRecordTimer() {
        recordTimerJob?.cancel()
        recordTimerJob = null
    }

    // ================================================================== running：示范音

    /** 🔊 听示范：`PracticeService.tts`（音色/语速走账号偏好 `VoicePrefs`）→ `AudioController.playBytes`。 */
    fun playDemoCurrent() {
        val s = _state.value
        val item = s.items.getOrNull(s.currentIndex) ?: return
        if (s.demoLoading || s.recording || s.preparing) return
        viewModelScope.launch {
            _state.update { it.copy(demoLoading = true) }
            try {
                // 第二轮：统一走 VoicePrefs.resolve(isChild)（儿童强制 slow、未设音色用童声），不再写死 slow/normal
                val choice = c.voicePrefs.resolve(s.isChild)
                val bytes = c.practice.tts(item.text, choice.rate, choice.voice)
                c.audio.playBytes(bytes, "flow_demo.wav")
            } catch (e: Throwable) {
                val ui = c.session.toUiErrorAsync(e)
                _state.update { it.copy(error = ui) }
            } finally {
                _state.update { it.copy(demoLoading = false) }
            }
        }
    }

    fun stopPlayback() {
        runCatching { c.audio.stopPlayback() }
    }

    // ================================================================== 汇总

    /** 汇总快照（汇总页打开时构建一次；与 hos buildSummary 一致）。 */
    fun buildSummary(): FlowSummaryData {
        val s = _state.value
        val items = s.items
        val scored = items.filter { it.status == FlowStatus.DONE && it.scorePron != null }
        val avgScore = if (scored.isEmpty()) {
            null
        } else {
            ((scored.sumOf { it.scorePron ?: 0.0 } / scored.size) * 10.0).roundToInt() / 10.0
        }
        val minCompleteness = scored.mapNotNull { it.scoreCompleteness }.minOrNull()
        val attemptIds = scored.map { it.attemptId }.filter { it.isNotEmpty() }.take(MAX_BATCH_IDS)
        val worst = scored
            .sortedBy { it.scorePron ?: 100.0 }
            .take(3)
            .map { FlowWorstItem(score = it.scorePron, text = it.text, index = it.index) }
        return FlowSummaryData(
            round = s.round,
            total = items.size,
            doneCount = scored.size,
            failedCount = items.count { it.status == FlowStatus.FAILED },
            avgScore = avgScore,
            worst = worst,
            encouragement = buildEncouragement(scored.size, avgScore, minCompleteness, attemptIds, items.size, items),
            attemptIds = attemptIds,
            items = items,
            materialId = s.runMaterialId,
            fromStoryMaterial = s.runFromStoryMaterial && s.runMaterialId.isNotEmpty(),
            offlineCount = items.count { it.status == FlowStatus.PENDING_OFFLINE },
        )
    }

    private fun buildEncouragement(
        doneCount: Int,
        avgScore: Double?,
        minCompleteness: Double?,
        attemptIds: List<String>,
        total: Int,
        items: List<FlowItem>,
    ): FlowEncouragement {
        val tier = when {
            doneCount == 0 -> "no_speech"
            minCompleteness != null && minCompleteness < 60 -> "incomplete"
            (avgScore ?: 0.0) >= 85 -> "S"
            (avgScore ?: 0.0) >= 70 -> "A"
            (avgScore ?: 0.0) >= 55 -> "B"
            else -> "C"
        }
        val pool = FlowEncPools.forTier(tier)
        val seed = attemptIds.joinToString("|") + ":" + tier + ":" + total
        val variant = pool[FlowEncPools.stableHash(seed) % pool.size]
        return FlowEncouragement(
            tier = tier,
            zh = variant.zh,
            en = variant.en,
            praise = bestWordPraise(items),
        )
    }

    /** 具体化一句：挑本次读得最好的词（≥85），取不到就不编。 */
    private fun bestWordPraise(items: List<FlowItem>): String {
        var bestWord = ""
        var bestScore = -1.0
        for (item in items) {
            if (item.status != FlowStatus.DONE) continue
            for (word in item.words) {
                val score = word.score ?: continue
                if (score >= 85 && score > bestScore) {
                    bestScore = score
                    bestWord = word.word
                }
            }
        }
        return if (bestWord.isEmpty()) "" else "「$bestWord」这个词读得特别清楚。"
    }

    /** 汇总页要保存的文本（本次「自己输入」/OCR/书页正文；语料跑批时为空）。 */
    fun customTextForSave(): String {
        val s = _state.value
        return s.customSentences.filter { it.isNotBlank() }.joinToString(" ").trim()
            .ifEmpty { s.customInput.trim() }
    }

    /** 汇总页保存书页的默认标题（沿用 setup 里填的标题 / 首行）。 */
    fun suggestedPageTitle(): String {
        val s = _state.value
        return s.saveTitle.trim().ifEmpty { FlowText.firstLine(s.customInput, 40) }
    }

    // ================================================================== 杂项

    fun setSourceTab(index: Int) {
        if (index == _state.value.sourceTab) return
        _state.update { it.copy(sourceTab = index, setupError = null) }
        if (index == 1) loadMaterials()
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }

    fun clearSetupError() {
        _state.update { it.copy(setupError = null) }
    }

    fun clearOcrError() {
        _state.update { it.copy(ocrError = null) }
    }

    fun clearSaveError() {
        _state.update { it.copy(saveError = null) }
    }

    private fun setUiError(e: Throwable) {
        viewModelScope.launch {
            val ui = c.session.toUiErrorAsync(e)
            _state.update { it.copy(error = ui) }
        }
    }

    /**
     * 拍照识别入口可用性：统一走 `CapabilityCache`（`GET /health` 的 features/capabilities 汇总）。
     * 先读 5 分钟缓存；没有缓存才后台 `refresh()`；失败保持当前值（不阻塞页面）。
     */
    private fun loadOcrCapability() {
        val cached = runCatching { c.capability.cached() }.getOrNull()
        if (cached != null) {
            _state.update { it.copy(ocrEnabled = cached.ocr) }
            return
        }
        viewModelScope.launch {
            runCatching { c.capability.refresh() }
                .onSuccess { caps -> _state.update { it.copy(ocrEnabled = caps.ocr) } }
        }
    }

    private companion object {
        /** `/attempts/status` 每 2 秒一拍（规格 §5.4）。 */
        const val POLL_INTERVAL_MS = 2_000L

        /** 录完后自动进下一句的缓冲（400ms，与 hos 一致）。 */
        const val ADVANCE_DELAY_MS = 400L

        /** 录音计时刷新间隔（页面显示已录秒数）。 */
        const val RECORD_TICK_MS = 200L

        /** `/attempts/status` 最多 50 个 id（服务端硬限制）。 */
        const val MAX_STATUS_IDS = 50

        /** batch 诊断最多 20 个 attempt id（服务端硬限制）。 */
        const val MAX_BATCH_IDS = 20

        /** 拍照识别图片大小上限（与录音上限一致的 12MB 兜底）。 */
        const val MAX_OCR_BYTES = 12 * 1024 * 1024

        /** 语料等级池（服务端没有 C1 语料）。 */
        val LEVELS = listOf("A1", "A2", "B1", "B2")

        const val FAILED_REASON = "评分没有成功，可以重录这句"
    }
}

/**
 * 连读页面的完整 UI 状态（setup / running / summary 三阶段共用一份 StateFlow）。
 *
 * 字段分组与 hos FlowVM 的属性一一对应；Android 侧用不可变集合 + copy 更新，
 * 页面用 `collectAsStateWithLifecycle()` 订阅。
 */
data class FlowUiState(
    // ---- 身份 / 阶段
    val isChild: Boolean = false,
    val exceeded: Boolean = false,
    val remainingMinutes: Int = 0,
    val phase: FlowPhase = FlowPhase.SETUP,
    val round: Int = 1,
    // ---- setup：来源 tab（0 语料 / 1 我的书页 / 2 自己输入）
    val sourceTab: Int = 0,
    // ---- setup：语料
    val level: String = "A1",
    val corpus: List<SentenceDto> = emptyList(),
    val corpusLoading: Boolean = false,
    val corpusError: UiError? = null,
    val startIndex: Int = 0,
    val count: Int = 5,
    val randomMode: Boolean = false,
    val randomPick: List<SentenceDto> = emptyList(),
    val preview: List<SentenceDto> = emptyList(),
    // ---- setup：我的书页
    val materials: List<MaterialDto> = emptyList(),
    val materialsLoading: Boolean = false,
    val materialsError: UiError? = null,
    val materialBusyId: String = "",
    val materialEditBusyId: String = "",
    // ---- setup：自己输入 / OCR
    val customInput: String = "",
    val customSentences: List<String> = emptyList(),
    val runMaterialId: String = "",
    val runTitle: String = "",
    /** 本轮是否由故事材料（`NavParams.flowMaterialId` + kind=story）启动；汇总页据此显示「复述这个故事」 */
    val runFromStoryMaterial: Boolean = false,
    val startingRun: Boolean = false,
    val ocrEnabled: Boolean = true,
    val ocrBusy: Boolean = false,
    val ocrInfoText: String = "",
    val ocrError: UiError? = null,
    // ---- setup：保存书页
    val saveTitle: String = "",
    val saveBusy: Boolean = false,
    val saveError: UiError? = null,
    val savedPageId: String = "",
    val savedPageTitle: String = "",
    val editingMaterialId: String = "",
    // ---- setup：整体错误
    val setupError: UiError? = null,
    // ---- running
    val items: List<FlowItem> = emptyList(),
    val runSentences: List<FlowRunSentence> = emptyList(),
    val currentIndex: Int = 0,
    val autoNext: Boolean = true,
    val expandedIndex: Int = -1,
    val recording: Boolean = false,
    val preparing: Boolean = false,
    val submitting: Boolean = false,
    val elapsedMs: Long = 0,
    val allSubmitted: Boolean = false,
    val limitMessage: String = "",
    val limitReached: Boolean = false,
    val error: UiError? = null,
    // ---- 示范音
    val demoLoading: Boolean = false,
    val audioPlaying: Boolean = false,
    // ---- summary
    val summary: FlowSummaryData? = null,
) {
    /** 开始前用于展示/计数的句子：还没点「切句」时按当前输入即时切一次（与 startCustom 兜底一致）。 */
    val effectiveCustomSentences: List<String>
        get() = if (customSentences.isNotEmpty()) customSentences else FlowText.splitMaterial(customInput)

    /** 拉语料/改数量/改起点/换一批后刷新预览（随机模式优先用已抽到的句子）。 */
    fun withPreview(): FlowUiState {
        val nextPreview = if (randomMode && randomPick.isNotEmpty()) {
            randomPick
        } else {
            corpus.drop(startIndex).take(count)
        }
        return copy(preview = nextPreview)
    }
}

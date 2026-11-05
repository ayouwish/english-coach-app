package top.dreamsearch.englishcoach.ui.page.flow

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import top.dreamsearch.englishcoach.core.audio.MicPermission
import top.dreamsearch.englishcoach.core.audio.rememberMicPermission
import top.dreamsearch.englishcoach.core.di.AppGraph
import top.dreamsearch.englishcoach.core.di.vmFactory
import top.dreamsearch.englishcoach.core.net.dto.MaterialDto
import top.dreamsearch.englishcoach.core.net.dto.SentenceDto
import top.dreamsearch.englishcoach.ui.component.EcButton
import top.dreamsearch.englishcoach.ui.component.EcButtonKind
import top.dreamsearch.englishcoach.ui.component.EcButtonSizeKind
import top.dreamsearch.englishcoach.ui.component.EcCard
import top.dreamsearch.englishcoach.ui.component.EcChip
import top.dreamsearch.englishcoach.ui.component.EcDialog
import top.dreamsearch.englishcoach.ui.component.EcInlineNotice
import top.dreamsearch.englishcoach.ui.component.EcPill
import top.dreamsearch.englishcoach.ui.component.EcSwitchRow
import top.dreamsearch.englishcoach.ui.component.EcTextField
import top.dreamsearch.englishcoach.ui.component.EmptyState
import top.dreamsearch.englishcoach.ui.component.ErrorBanner
import top.dreamsearch.englishcoach.ui.component.LoadingBlock
import top.dreamsearch.englishcoach.ui.component.PillTone
import top.dreamsearch.englishcoach.ui.component.RecordButton
import top.dreamsearch.englishcoach.ui.component.ScoreBadge
import top.dreamsearch.englishcoach.ui.component.ScoreChip
import top.dreamsearch.englishcoach.ui.component.SubScoreRow
import top.dreamsearch.englishcoach.ui.component.WordText
import top.dreamsearch.englishcoach.ui.design.EcColor
import top.dreamsearch.englishcoach.ui.design.EcFont
import top.dreamsearch.englishcoach.ui.design.EcRadius
import top.dreamsearch.englishcoach.ui.design.EcScore
import top.dreamsearch.englishcoach.ui.design.EcSpace
import top.dreamsearch.englishcoach.ui.nav.Navigator
import top.dreamsearch.englishcoach.ui.nav.Routes
import kotlin.math.roundToInt

/**
 * 连读模式 · Tab 根页（setup → running → 汇总前收尾）。
 *
 * 对应 hos：`hos/entry/src/main/ets/pages/FlowPage.ets`；业务事实来源 `hos/docs/screens.md` §4。
 *
 * 页面结构（与 hos 一致，去掉手机不适用的二级编辑页）：
 * - setup：来源三选一（语料 / 我的书页 / 自己输入）+ 拍照识别卡片 + 保存为书页；
 * - running：第 N/M 句、进度条、当前句卡（英文 + 中文 + 听示范 + 录音）、实时评分列表；
 * - 全部 settled：页面自动 `Navigator.navigate(Routes.FLOW_SUMMARY)`；返回后显示收尾卡。
 *
 * 儿童规则（docs/screens.md §0）：大按钮、少文字、不显示 IPA / 低分数字，
 * 「评分中」改成「正在听…」，失败改成「再读一次」。
 *
 * 轮询开关：页面可见性由 `LifecycleEventObserver`（ON_START/ON_STOP）+ `onDispose` 驱动，
 * 切 Tab / push 汇总页 / 切后台都会停轮询（规格 §5.4），回来补拉一次。
 */
@Composable
fun FlowTab() {
    val vm: FlowViewModel = viewModel(factory = remember { vmFactory { FlowViewModel(AppGraph.container) } })
    val state by vm.state.collectAsStateWithLifecycle()
    val mic = rememberMicPermission()
    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri != null) vm.ocr(uri)
    }
    val onPickImage: () -> Unit = { runCatching { pickImage.launch("image/*") } }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, vm) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> vm.onVisible()
                Lifecycle.Event.ON_STOP -> vm.onHidden()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        vm.onVisible()
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            vm.onHidden()
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(EcColor.bg)) {
        when (state.phase) {
            FlowPhase.SETUP -> SetupView(vm = vm, state = state, onPickImage = onPickImage)
            FlowPhase.RUNNING -> RunningView(vm = vm, state = state, mic = mic)
            FlowPhase.SUMMARY -> FinishedView(vm = vm, state = state)
        }
    }
}

// ===========================================================================
// setup
// ===========================================================================

private val LEVEL_OPTIONS: List<Pair<String, String>> = listOf(
    "A1" to "A1",
    "A2" to "A2",
    "B1" to "B1",
    "B2" to "B2",
    "ALL" to "全部",
)

private val COUNT_OPTIONS: List<Int> = listOf(5, 10, 15)

private val SOURCE_LABELS: List<String> = listOf("📚 从语料选", "📖 我的书页", "✍️ 自己输入")

@Composable
private fun SetupView(vm: FlowViewModel, state: FlowUiState, onPickImage: () -> Unit) {
    if (state.startingRun) {
        Column(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
            LoadingBlock(text = "正在打开材料…", subText = "马上就开始连读")
        }
        return
    }
    val child = state.isChild
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = EcSpace.x4, vertical = EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
    ) {
        // 标题 + 一句话说明（儿童文案更短）
        Text(
            text = "🔗 " + if (child) "一口气读好多句" else "连读模式",
            fontSize = if (child) EcFont.childH1 else EcFont.h2,
            fontWeight = FontWeight.Bold,
            color = EcColor.ink,
        )
        Text(
            text = if (child) {
                "读完一句就自动跳到下一句，不用等评分。读完后分数会自己出现在下面的列表里 🙂"
            } else {
                "逐句连读：录完一句立刻进入下一句，评分在后台排队，结果陆续显示（每句仍有完整反馈）。"
            },
            fontSize = if (child) EcFont.childBody else EcFont.caption,
            color = EcColor.muted,
        )

        OcrCard(vm = vm, state = state, onPickImage = onPickImage)

        EcCard {
            SourceTabs(selected = state.sourceTab, onSelect = vm::setSourceTab)
            when (state.sourceTab) {
                1 -> MaterialsPanel(vm = vm, state = state)
                2 -> CustomPanel(vm = vm, state = state)
                else -> CorpusPanel(vm = vm, state = state)
            }
        }

        state.setupError?.let { error ->
            ErrorBanner(error = error, onDismiss = vm::clearSetupError)
        }
        Spacer(modifier = Modifier.height(EcSpace.x4))
    }
}

/** 拍照识别卡片（对应 hos ocrCard）：识别文本追加到「自己输入」，可编辑后再保存/开始。 */
@Composable
private fun OcrCard(vm: FlowViewModel, state: FlowUiState, onPickImage: () -> Unit) {
    val child = state.isChild
    EcCard {
        Text(
            text = "📷 " + if (child) "拍张照识别书上的句子" else "拍照识别书页",
            fontSize = if (child) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = when {
                    state.ocrBusy -> "识别中…"
                    state.ocrInfoText.isNotEmpty() -> "🖼️ 再选一张"
                    else -> "🖼️ 从相册选"
                },
                onClick = onPickImage,
                kind = EcButtonKind.SECONDARY,
                size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                enabled = state.ocrEnabled && !state.ocrBusy,
                loading = state.ocrBusy,
            )
            Text(
                text = when {
                    !state.ocrEnabled -> "当前服务端未开启识别，先用「自己输入」吧"
                    else -> "照片只用于识别，不保存原图"
                },
                fontSize = EcFont.micro,
                color = if (!state.ocrEnabled) EcColor.warnText else EcColor.muted,
                modifier = Modifier.weight(1f),
            )
        }
        if (state.ocrInfoText.isNotEmpty()) {
            Text(text = state.ocrInfoText, fontSize = EcFont.micro, color = EcColor.goodText)
        }
        state.ocrError?.let { error ->
            ErrorBanner(error = error, onRetry = onPickImage, onDismiss = vm::clearOcrError)
        }
    }
}

/** 来源三选一（语料 / 我的书页 / 自己输入）；横向可滚动，避免窄屏挤爆。 */
@Composable
private fun SourceTabs(selected: Int, onSelect: (Int) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        SOURCE_LABELS.forEachIndexed { index, label ->
            EcChip(label = label, selected = selected == index, onClick = { onSelect(index) })
        }
    }
}

/** 语料面板：等级 + 数量 5/10/15 + 随机抽句 + 预览 + 开始。 */
@Composable
private fun CorpusPanel(vm: FlowViewModel, state: FlowUiState) {
    val child = state.isChild
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
        ) {
            LEVEL_OPTIONS.forEach { (value, label) ->
                EcChip(label = label, selected = state.level == value, onClick = { vm.setLevel(value) })
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(text = "读", fontSize = EcFont.caption, color = EcColor.muted)
            COUNT_OPTIONS.forEach { count ->
                EcChip(label = "$count 句", selected = state.count == count, onClick = { vm.setCount(count) })
            }
        }

        if (state.corpusLoading) {
            LoadingBlock(text = "正在取句子…")
        } else if (state.corpusError != null) {
            ErrorBanner(error = state.corpusError, onRetry = vm::loadCorpus)
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text(text = "共 ${state.corpus.size} 句", fontSize = EcFont.caption, color = EcColor.muted)
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = if (state.randomMode) "🎲 随机 ✓" else "🎲 随机",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(onClick = vm::toggleRandom)
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
                )
                if (state.randomMode) {
                    Text(
                        text = "🔀 换一批",
                        fontSize = EcFont.caption,
                        color = EcColor.primary,
                        modifier = Modifier
                            .clickable(onClick = vm::drawRandom)
                            .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
                    )
                }
            }
            if (!state.randomMode && state.corpus.isNotEmpty()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
                ) {
                    Text(
                        text = "从第 ${state.startIndex + 1} 句开始",
                        fontSize = EcFont.caption,
                        color = EcColor.muted,
                        modifier = Modifier.weight(1f),
                    )
                    EcButton(
                        label = "−",
                        onClick = { vm.setStartIndex(state.startIndex - 1) },
                        kind = EcButtonKind.GHOST,
                        size = EcButtonSizeKind.SM,
                        enabled = state.startIndex > 0,
                    )
                    EcButton(
                        label = "＋",
                        onClick = { vm.setStartIndex(state.startIndex + 1) },
                        kind = EcButtonKind.GHOST,
                        size = EcButtonSizeKind.SM,
                        enabled = state.startIndex < state.corpus.size - 1,
                    )
                }
            }

            PreviewList(preview = state.preview)

            EcButton(
                label = "🎤 " + (if (child) "开始一起读" else "开始连读") + "（${state.preview.size} 句）",
                onClick = vm::startCorpus,
                size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.LG,
                fullWidth = true,
                enabled = state.preview.isNotEmpty(),
            )
        }
    }
}

/** 抽到的句子预览（只做展示，不可编辑；编辑去「自己输入」）。 */
@Composable
private fun PreviewList(preview: List<SentenceDto>) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.surfaceAlt)
            .padding(EcSpace.x3),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
    ) {
        if (preview.isEmpty()) {
            Text(text = "这个位置没有句子", fontSize = EcFont.caption, color = EcColor.muted)
        } else {
            preview.forEachIndexed { index, sentence ->
                Text(
                    text = "${index + 1}. ${sentence.text}",
                    fontSize = EcFont.caption,
                    color = EcColor.ink,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** 我的书页：最近 50 篇，打开 / 编辑 / 删除（编辑器复用「自己输入」面板）。 */
@Composable
private fun MaterialsPanel(vm: FlowViewModel, state: FlowUiState) {
    val child = state.isChild
    var deleteTarget by remember { mutableStateOf<MaterialDto?>(null) }

    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "📖 我的书页（家里人的都在这里）",
                fontSize = EcFont.caption,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "刷新",
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(onClick = vm::loadMaterials)
                    .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
            )
        }

        when {
            state.materialsLoading -> LoadingBlock(text = "正在加载书页…")
            state.materialsError != null -> ErrorBanner(error = state.materialsError, onRetry = vm::loadMaterials)
            state.materials.isEmpty() -> EmptyState(
                icon = "📖",
                message = if (child) {
                    "还没有保存的书页。可以让爸爸妈妈先拍一页存起来。"
                } else {
                    "还没有保存的书页。可以先拍照识别一页，识别后点「保存为书页」。"
                },
            )
            else -> state.materials.forEach { material ->
                MaterialRow(
                    material = material,
                    state = state,
                    onOpen = { vm.openMaterial(material.id) },
                    onEdit = { vm.beginEdit(material.id) },
                    onDelete = { deleteTarget = material },
                )
            }
        }
    }

    deleteTarget?.let { target ->
        EcDialog(title = "删除这一页？", onDismiss = { deleteTarget = null }) {
            Text(
                text = "删除后全家都看不到这篇书页了，无法恢复。",
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                EcButton(
                    label = "取消",
                    onClick = { deleteTarget = null },
                    kind = EcButtonKind.SECONDARY,
                    modifier = Modifier.weight(1f),
                )
                EcButton(
                    label = "删除",
                    onClick = {
                        vm.removeMaterial(target.id)
                        deleteTarget = null
                    },
                    kind = EcButtonKind.DANGER,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun MaterialRow(
    material: MaterialDto,
    state: FlowUiState,
    onOpen: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    val busy = state.materialBusyId == material.id || state.materialEditBusyId == material.id
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.surfaceAlt)
            .padding(EcSpace.x3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = material.title.ifEmpty { "未命名书页" },
                fontSize = EcFont.caption,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(text = materialMeta(material), fontSize = EcFont.micro, color = EcColor.muted)
        }
        if (busy) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                color = EcColor.primary,
                strokeWidth = 2.dp,
            )
        } else {
            Text(
                text = if (state.editingMaterialId == material.id) "编辑中" else "编辑",
                fontSize = EcFont.caption,
                color = if (state.editingMaterialId == material.id) EcColor.goodText else EcColor.muted,
                modifier = Modifier
                    .clickable(onClick = onEdit)
                    .padding(horizontal = EcSpace.x1, vertical = EcSpace.x1),
            )
            Text(
                text = "删除",
                fontSize = EcFont.caption,
                color = EcColor.badText,
                modifier = Modifier
                    .clickable(onClick = onDelete)
                    .padding(horizontal = EcSpace.x1, vertical = EcSpace.x1),
            )
            Text(
                text = "打开 →",
                fontSize = EcFont.caption,
                color = EcColor.primary,
                modifier = Modifier
                    .clickable(onClick = onOpen)
                    .padding(horizontal = EcSpace.x1, vertical = EcSpace.x1),
            )
        }
    }
}

private fun materialMeta(material: MaterialDto): String {
    val image = if (material.hasImage) "有图片" else "仅文字"
    var text = "${material.sentenceCount} 句 · $image"
    if (material.createdByName.isNotEmpty()) text += " · ${material.createdByName}"
    return text
}

/** 自己输入 / 书页正文编辑 + 保存面板（也承接 OCR 识别结果的再编辑）。 */
@Composable
private fun CustomPanel(vm: FlowViewModel, state: FlowUiState) {
    val child = state.isChild
    Column(verticalArrangement = Arrangement.spacedBy(EcSpace.x2)) {
        EcTextField(
            value = state.customInput,
            onValueChange = vm::setCustomInput,
            label = if (child) "想读的英文" else "想读的英文段落",
            placeholder = "把想读的英文段落贴进来（会按 . ! ? 。！？ 自动切句）",
            singleLine = false,
            modifier = Modifier.heightIn(min = 120.dp),
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = "✂️ 切句",
                onClick = vm::splitCustom,
                kind = EcButtonKind.SECONDARY,
                size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            )
            Text(
                text = "切出 ${state.customSentences.size} 句（可逐句修改后再开始）",
                fontSize = EcFont.micro,
                color = EcColor.muted,
                modifier = Modifier.weight(1f),
            )
        }
        state.customSentences.forEachIndexed { index, text ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text(
                    text = "${index + 1}",
                    fontSize = EcFont.micro,
                    color = EcColor.muted,
                    modifier = Modifier.width(18.dp),
                )
                EcTextField(
                    value = text,
                    onValueChange = { vm.updateCustomSentence(index, it) },
                    label = "第 ${index + 1} 句",
                    modifier = Modifier.weight(1f),
                )
            }
        }
        if (state.runMaterialId.isNotEmpty()) {
            Text(
                text = "这一批来自「我的书页」，提交时会带上书页 id",
                fontSize = EcFont.micro,
                color = EcColor.muted,
            )
        }
        if (state.editingMaterialId.isNotEmpty() ||
            state.customInput.isNotBlank() ||
            state.customSentences.isNotEmpty()
        ) {
            SavePanel(vm = vm, state = state)
        }
        EcButton(
            label = "🎤 " + (if (child) "开始读" else "开始连读") + "（${state.effectiveCustomSentences.size} 句）",
            onClick = vm::startCustom,
            size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.LG,
            fullWidth = true,
            enabled = state.effectiveCustomSentences.isNotEmpty(),
        )
    }
}

/** 保存为「我的书页」面板（新建 POST / 编辑 PATCH），并可保存后直接开读。 */
@Composable
private fun SavePanel(vm: FlowViewModel, state: FlowUiState) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.surfaceAlt)
            .padding(EcSpace.x3),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = when {
                    state.editingMaterialId.isNotEmpty() -> "✏️ 编辑书页（保存会覆盖原文）"
                    else -> "💾 保存为「我的书页」"
                },
                fontSize = EcFont.caption,
                fontWeight = FontWeight.Medium,
                color = EcColor.ink,
                modifier = Modifier.weight(1f),
            )
            if (state.editingMaterialId.isNotEmpty()) {
                Text(
                    text = "取消编辑",
                    fontSize = EcFont.caption,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(onClick = vm::cancelEdit)
                        .padding(horizontal = EcSpace.x1, vertical = EcSpace.x1),
                )
            }
        }
        EcTextField(
            value = state.saveTitle,
            onValueChange = vm::setSaveTitle,
            label = "书页标题",
            placeholder = "默认取第一行",
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = when {
                    state.savedPageId.isNotEmpty() -> "已保存 ✅"
                    state.saveBusy -> "保存中…"
                    state.editingMaterialId.isNotEmpty() -> "💾 保存修改"
                    else -> "💾 保存为书页"
                },
                onClick = vm::saveAsPage,
                kind = EcButtonKind.SECONDARY,
                loading = state.saveBusy,
                enabled = state.savedPageId.isEmpty(),
                modifier = Modifier.weight(1f),
            )
            EcButton(
                label = if (state.savedPageId.isNotEmpty()) "立即开始读 →" else "保存后直接连读 →",
                onClick = vm::saveAndRead,
                loading = state.saveBusy,
                modifier = Modifier.weight(1f),
            )
        }
        if (state.savedPageId.isNotEmpty()) {
            Text(
                text = "已保存为「${state.savedPageTitle.ifEmpty { "未命名书页" }}」",
                fontSize = EcFont.micro,
                color = EcColor.goodText,
            )
        }
        state.saveError?.let { error ->
            ErrorBanner(error = error, onRetry = vm::saveAsPage, onDismiss = vm::clearSaveError)
        }
    }
}

// ===========================================================================
// running
// ===========================================================================

@Composable
private fun RunningView(vm: FlowViewModel, state: FlowUiState, mic: MicPermission) {
    val child = state.isChild
    Column(modifier = Modifier.fillMaxSize()) {
        RunningHeader(vm = vm, state = state)
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = EcSpace.x4, vertical = EcSpace.x2),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            if (state.items.isEmpty()) {
                EmptyState(
                    icon = "🔗",
                    message = if (child) "还没有选句子哦" else "还没有选连读的句子",
                    actionLabel = "去选句子",
                    onAction = vm::backToSetup,
                )
            } else {
                if (state.allSubmitted) {
                    WaitingCard(state = state)
                } else {
                    CurrentCard(vm = vm, state = state, mic = mic)
                }
                Text(
                    text = if (child) "读过的句子（点一下看看）" else "实时评分（点一行展开详情）",
                    fontSize = EcFont.caption,
                    color = EcColor.muted,
                    modifier = Modifier.padding(top = EcSpace.x1),
                )
                state.items.forEach { item ->
                    FlowItemRow(
                        item = item,
                        isChild = child,
                        expanded = state.expandedIndex == item.index,
                        onToggle = { vm.toggleExpanded(item.index) },
                        onRedo = { vm.retryItem(item.index) },
                    )
                }
            }
            Spacer(modifier = Modifier.height(EcSpace.x4))
        }
    }
}

/** 运行页头部：标题 + 第 N/M 句 + 进度条 + 自动下一句开关 + 计数/额度提示。 */
@Composable
private fun RunningHeader(vm: FlowViewModel, state: FlowUiState) {
    val child = state.isChild
    val total = state.items.size
    val current = if (total == 0) 0 else (state.currentIndex + 1).coerceAtMost(total)
    val progress = (state.items.submittedCount().toFloat() / total.coerceAtLeast(1).toFloat()).coerceIn(0f, 1f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = EcSpace.x4, end = EcSpace.x4, top = EcSpace.x4, bottom = EcSpace.x2),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = if (state.runTitle.isNotEmpty()) {
                    "📖 ${state.runTitle}"
                } else {
                    "🔗 " + if (child) "一句一句读" else "连读模式"
                },
                fontSize = when {
                    state.runTitle.isNotEmpty() && child -> EcFont.childBody
                    state.runTitle.isNotEmpty() -> EcFont.body
                    child -> EcFont.h2
                    else -> EcFont.h3
                },
                fontWeight = FontWeight.Bold,
                color = EcColor.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            EcPill(text = "第 $current / $total 句", tone = PillTone.INFO)
        }

        // 进度条（纯 Box 拼接，避免额外依赖 Material 组件的不同版本参数）
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(EcColor.surfaceAlt),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(progress)
                    .clip(RoundedCornerShape(4.dp))
                    .background(EcColor.primary),
            )
        }

        EcSwitchRow(
            title = if (child) "读完自动跳到下一句" else "录完后自动进入下一句",
            checked = state.autoNext,
            onCheckedChange = { vm.toggleAutoNext() },
        )

        val submitted = state.items.submittedCount()
        val done = state.items.doneCount()
        val pending = state.items.pendingCount()
        val failed = state.items.failedCount()
        val offline = state.items.offlineQueuedCount()
        Text(
            text = buildString {
                if (child) {
                    append("读完 $submitted 句 · 读好 $done 句 · 正在听 $pending 句")
                    if (offline > 0) append(" · 存好 $offline 句")
                } else {
                    append("已提交 $submitted · 已评分 $done · 评分中 $pending")
                    if (failed > 0) append(" · 需重读 $failed")
                    if (offline > 0) append(" · 待补评分 $offline")
                }
            },
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )

        if (state.exceeded) {
            EcInlineNotice(
                text = if (child) "今天已经练得很棒啦，明天再来 🌙" else "今天的练习时长已达上限，明天再来",
                tone = PillTone.WARN,
            )
        } else if (state.limitMessage.isNotEmpty()) {
            EcInlineNotice(text = "🌙 ${state.limitMessage}", tone = PillTone.WARN)
        } else if (state.remainingMinutes in 1..3) {
            EcInlineNotice(
                text = if (child) {
                    "今天还能再读 ${state.remainingMinutes} 分钟，读完就休息一下 🙂"
                } else {
                    "今天还剩 ${state.remainingMinutes} 分钟练习时间"
                },
                tone = PillTone.WARN,
            )
        }
    }
}

/** 当前句卡：英文（WordText，可点词看音标）+ 中文 + 听示范 + 录音 + 状态/错误。 */
@Composable
private fun CurrentCard(vm: FlowViewModel, state: FlowUiState, mic: MicPermission) {
    val child = state.isChild
    val item = state.items.getOrNull(state.currentIndex)
    val recording = state.recording
    val elapsedSec = state.elapsedMs / 1000

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(EcColor.surface)
            .padding(EcSpace.x5),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x3),
    ) {
        if (item == null) {
            Text(
                text = if (child) "读完啦" else "这一批读完了",
                fontSize = EcFont.body,
                color = EcColor.muted,
            )
            return@Column
        }

        WordText(text = item.text, isChild = child)
        if (item.translationZh.isNotEmpty()) {
            Text(
                text = item.translationZh,
                fontSize = if (child) EcFont.childBody else EcFont.caption,
                color = EcColor.muted,
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = when {
                    state.audioPlaying -> "⏹ 停止播放"
                    state.demoLoading -> "正在合成…"
                    else -> "🔊 听示范"
                },
                onClick = {
                    if (state.audioPlaying) vm.stopPlayback() else vm.playDemoCurrent()
                },
                kind = EcButtonKind.SECONDARY,
                size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                loading = state.demoLoading,
                enabled = !recording && !state.preparing && !state.submitting,
            )
            if (item.status != FlowStatus.UNSENT) {
                EcPill(text = flowStatusBadge(item, child), tone = flowStatusTone(item, child))
            }
        }

        if (recording || state.preparing || state.submitting) {
            Text(
                text = when {
                    state.submitting -> "提交中…"
                    recording -> if (child) "我在听你说，读完点一下" else "正在听你说…读完点「说完啦」"
                    else -> "正在打开麦克风…"
                },
                fontSize = EcFont.caption,
                color = if (recording) EcColor.warnText else EcColor.primary,
            )
        }

        if (item.status == FlowStatus.UNSENT) {
            RecordButton(
                recording = recording,
                enabled = !state.preparing && !state.submitting && !state.exceeded,
                isChild = child,
                onClick = {
                    when {
                        recording -> vm.stopAndSubmit()
                        !mic.granted -> mic.request()
                        else -> vm.startRecording()
                    }
                },
                label = when {
                    recording -> if (child) "读完啦 ${elapsedSec}s，点一下" else "说完啦 ${elapsedSec}s，点一下结束"
                    !mic.granted -> if (child) "点一下，打开麦克风" else "点一下开始（首次会请求麦克风权限）"
                    state.preparing -> "麦克风准备中…"
                    else -> "点一下开始说"
                },
            )
            if (recording) {
                EcButton(
                    label = if (child) "不要了" else "✖️ 不要了",
                    onClick = vm::cancelRecording,
                    kind = EcButtonKind.GHOST,
                    size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.SM,
                    enabled = !state.submitting,
                )
            }
        }

        if (item.status != FlowStatus.UNSENT && vm.hasNextUnsent()) {
            EcButton(
                label = "下一句 →",
                onClick = vm::nextSentence,
                kind = EcButtonKind.SECONDARY,
                size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            )
        }

        if (item.status == FlowStatus.FAILED) {
            Text(
                text = item.error.ifEmpty { "评分没有成功" },
                fontSize = if (child) EcFont.childBody else EcFont.caption,
                color = if (child) EcColor.warnText else EcColor.badText,
            )
            EcButton(
                label = if (child) "再读一次这句" else "重录这句",
                onClick = { vm.retryItem(item.index) },
                kind = EcButtonKind.SECONDARY,
                size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
            )
        }

        if (item.status != FlowStatus.UNSENT) {
            val line = currentStatusLine(item, child)
            if (line.isNotEmpty()) {
                Text(text = line, fontSize = EcFont.caption, color = EcColor.muted)
            }
        }

        state.error?.let { error ->
            ErrorBanner(error = error, onDismiss = vm::clearError)
        }
    }
}

/** 全部提交完、后台还在评分时的等待卡。 */
@Composable
private fun WaitingCard(state: FlowUiState) {
    val child = state.isChild
    val done = state.items.doneCount()
    val pending = state.items.pendingCount()
    val failed = state.items.failedCount()
    val offline = state.items.offlineQueuedCount()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.lg))
            .background(EcColor.surface)
            .padding(EcSpace.x5),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Text(
            text = if (child) "都读完啦，等一下下…" else "全部读完啦，正在后台评分…",
            fontSize = if (child) EcFont.childBody else EcFont.body,
            fontWeight = FontWeight.Medium,
            color = EcColor.ink,
        )
        Text(
            text = if (child) {
                "读好 $done 句 · 正在听 $pending 句"
            } else {
                buildString {
                    append("已评分 $done 句 · 待评分 $pending 句 · 失败 $failed 句")
                    if (offline > 0) append(" · 待补评分 $offline 句")
                }
            },
            fontSize = EcFont.caption,
            color = EcColor.muted,
        )
        Text(
            text = if (child) "读完分数会自己出来，不用等在这里" else "评分完成后会自动跳到汇总页，不用一直等在这里",
            fontSize = EcFont.micro,
            color = EcColor.muted,
        )
    }
}

/** 单句行（运行页与汇总页共用）：序号+文本、状态胶囊、失败原因+重录、可展开详情。 */
@Composable
internal fun FlowItemRow(
    item: FlowItem,
    isChild: Boolean,
    expanded: Boolean,
    onToggle: () -> Unit,
    onRedo: () -> Unit,
) {
    val canExpand = item.hasResult || item.status == FlowStatus.FAILED
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EcRadius.md))
            .background(EcColor.surface)
            .clickable(enabled = canExpand, onClick = onToggle)
            .padding(EcSpace.x3),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = "${item.index + 1}. ${item.text}",
                fontSize = if (isChild) EcFont.childBody else EcFont.caption,
                color = EcColor.ink,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            EcPill(text = flowStatusBadge(item, isChild), tone = flowStatusTone(item, isChild))
        }
        if (item.status == FlowStatus.FAILED) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
            ) {
                Text(
                    text = item.error.ifEmpty { "评分没有成功" },
                    fontSize = EcFont.micro,
                    color = if (isChild) EcColor.warnText else EcColor.badText,
                    maxLines = 2,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = if (isChild) "再读一次" else "重录这句",
                    fontSize = EcFont.micro,
                    color = EcColor.primary,
                    modifier = Modifier
                        .clickable(onClick = onRedo)
                        .padding(horizontal = EcSpace.x2, vertical = EcSpace.x1),
                )
            }
        }
        if (item.status == FlowStatus.PENDING_OFFLINE) {
            // 第二轮：提交失败已入待补评分队列（不算失败，不需要重录）
            Text(
                text = item.error.ifEmpty { "已存本机，稍后补评分" },
                fontSize = EcFont.micro,
                color = EcColor.warnText,
                maxLines = 2,
            )
        }
        if (expanded && item.hasResult) {
            FlowItemDetail(item = item, isChild = isChild)
        }
    }
}

/** 展开详情：成人显示分数环/子项/逐词/问题词；儿童只给鼓励语与星星（不显示 IPA 与低分）。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FlowItemDetail(item: FlowItem, isChild: Boolean) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = EcSpace.x2),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
    ) {
        if (item.noSpeech) {
            Text(
                text = if (isChild) {
                    "这次好像没有听到声音，可以再读一次"
                } else {
                    "这次好像没有听到声音，可以点「重录这句」再读一次"
                },
                fontSize = EcFont.caption,
                color = EcColor.warnText,
            )
        } else if (isChild) {
            Text(
                text = EcScore.encouragement(item.scorePron, true),
                fontSize = EcFont.childBody,
                color = EcColor.ink,
            )
            if (item.scorePron != null) {
                Text(text = EcScore.stars(item.scorePron), fontSize = EcFont.h3, color = EcColor.ink)
            }
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EcSpace.x3),
            ) {
                ScoreBadge(score = item.scorePron, isChild = false, label = "这一句")
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    SubScoreRow(
                        items = listOf(
                            "accuracy" to item.scoreAccuracy,
                            "fluency" to item.scoreFluency,
                            "completeness" to item.scoreCompleteness,
                            "prosody" to item.scoreProsody,
                        ),
                        isChild = false,
                    )
                }
            }
            if (item.words.isNotEmpty()) {
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(EcSpace.x1),
                    verticalArrangement = Arrangement.spacedBy(EcSpace.x1),
                ) {
                    item.words.forEach { word ->
                        ScoreChip(
                            score = word.score,
                            isChild = false,
                            text = word.word + " " + (word.score?.let { EcScore.numberText(it) } ?: "—"),
                        )
                    }
                }
            }
        }

        if (item.feedbackSummary.isNotEmpty()) {
            Text(
                text = item.feedbackSummary,
                fontSize = if (isChild) EcFont.childBody else EcFont.caption,
                color = EcColor.ink,
            )
        }
        if (item.feedbackPraise.isNotEmpty()) {
            Text(text = "👍 ${item.feedbackPraise}", fontSize = EcFont.micro, color = EcColor.goodText)
        }
        item.pointTitles.forEach { title ->
            Text(text = "· $title", fontSize = EcFont.micro, color = EcColor.ink)
        }
        item.issueTexts.forEach { issue ->
            Text(text = "· $issue", fontSize = EcFont.micro, color = EcColor.warnText)
        }
        if (item.feedbackClosing.isNotEmpty()) {
            Text(text = item.feedbackClosing, fontSize = EcFont.micro, color = EcColor.muted)
        }
    }
}

// ===========================================================================
// summary 收尾卡（汇总页被返回后仍显示）
// ===========================================================================

@Composable
private fun FinishedView(vm: FlowViewModel, state: FlowUiState) {
    val child = state.isChild
    val summary = state.summary
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(EcSpace.x4),
        verticalArrangement = Arrangement.spacedBy(EcSpace.x4),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(EcRadius.lg))
                .background(EcColor.surface)
                .padding(EcSpace.x5),
            verticalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            Text(
                text = "🎉 " + if (child) "读完啦！" else "连读完成",
                fontSize = if (child) EcFont.childH1 else EcFont.h2,
                fontWeight = FontWeight.Bold,
                color = EcColor.ink,
            )
            Text(
                text = summary?.let { summaryLineText(it, child) } ?: "还没有读完一轮连读",
                fontSize = EcFont.caption,
                color = EcColor.muted,
            )
            summary?.let {
                Text(
                    text = encouragementZhText(it),
                    fontSize = if (child) EcFont.childBody else EcFont.body,
                    color = EcColor.ink,
                )
            }
        }
        EcButton(
            label = "📊 查看本轮汇总",
            onClick = { Navigator.navigate(Routes.FLOW_SUMMARY) },
            size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.LG,
            fullWidth = true,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(EcSpace.x2),
        ) {
            EcButton(
                label = if (child) "🔁 再读一遍～" else "🔁 再读一遍",
                onClick = vm::reread,
                kind = EcButtonKind.SECONDARY,
                size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                modifier = Modifier.weight(1f),
            )
            EcButton(
                label = "再读一段",
                onClick = vm::backToSetup,
                kind = EcButtonKind.GHOST,
                size = if (child) EcButtonSizeKind.CHILD else EcButtonSizeKind.MD,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

// ===========================================================================
// 纯文本辅助（运行页 / 汇总页共用）
// ===========================================================================

/** 单句状态胶囊文案（儿童不出现「评分中/失败」等技术词）。 */
internal fun flowStatusBadge(item: FlowItem, isChild: Boolean): String = when (item.status) {
    FlowStatus.DONE -> when {
        item.scorePron == null -> "已评分"
        isChild -> EcScore.stars(item.scorePron)
        else -> "${EcScore.numberText(item.scorePron)} 分"
    }
    FlowStatus.SCORING -> if (isChild) "正在听…" else "评分中…"
    FlowStatus.PENDING -> if (isChild) "正在听…" else "待评分…"
    FlowStatus.FAILED -> if (isChild) "再读一次" else "评分失败"
    // 第二轮：提交时网络/5xx 失败，录音已入本机「待补评分」队列（不算失败）
    FlowStatus.PENDING_OFFLINE -> if (isChild) "存好啦" else "待补评分"
    FlowStatus.UNSENT -> "未读"
}

/** 状态胶囊色调（儿童失败用 warn 而不是 bad，避免刺眼红色）。 */
internal fun flowStatusTone(item: FlowItem, isChild: Boolean): PillTone = when (item.status) {
    FlowStatus.DONE -> PillTone.GOOD
    FlowStatus.FAILED -> if (isChild) PillTone.WARN else PillTone.BAD
    FlowStatus.SCORING, FlowStatus.PENDING -> PillTone.INFO
    FlowStatus.PENDING_OFFLINE -> PillTone.WARN
    FlowStatus.UNSENT -> PillTone.NEUTRAL
}

/** 当前句的状态说明（提交后自动进下一句，提示可以继续读）。 */
private fun currentStatusLine(item: FlowItem, isChild: Boolean): String = when (item.status) {
    FlowStatus.PENDING -> if (isChild) {
        "这一句已经交上去啦，等一下下（可以先读下一句）"
    } else {
        "这一句已提交，正在排队评分…（可以继续读下一句）"
    }
    FlowStatus.SCORING -> if (isChild) {
        "我在听这一句啦（可以继续读下一句）"
    } else {
        "这一句正在评分…（可以继续读下一句）"
    }
    FlowStatus.DONE -> if (isChild) {
        "这一句读好啦 ✅（可以继续读下一句）"
    } else {
        "这一句已评分 ✅（可以继续读下一句）"
    }
    FlowStatus.FAILED -> if (isChild) "这一句刚才没成功，再读一次就好" else "这一句提交或评分没有成功"
    FlowStatus.PENDING_OFFLINE -> if (isChild) {
        "这句存好啦，等会儿再评分（可以先读下一句）"
    } else {
        "已存本机，稍后补评分（可以继续读下一句）"
    }
    FlowStatus.UNSENT -> ""
}

/** 汇总一行文字（成人/儿童两套措辞；低分/平均分按 EcScore 规则隐藏数字）。 */
internal fun summaryLineText(data: FlowSummaryData, isChild: Boolean): String {
    val parts = ArrayList<String>()
    parts.add(
        if (isChild) "一共 ${data.total} 句 · 读好 ${data.doneCount} 句" else "共 ${data.total} 句 · 已评分 ${data.doneCount} 句",
    )
    if (data.failedCount > 0) {
        parts.add(if (isChild) "再读 ${data.failedCount} 句" else "失败 ${data.failedCount} 句")
    }
    if (data.offlineCount > 0) {
        parts.add(if (isChild) "先存好 ${data.offlineCount} 句" else "待补评分 ${data.offlineCount} 句")
    }
    val avg = data.avgScore
    if (avg != null && EcScore.showNumber(avg, isChild)) {
        parts.add("平均 ${averageText(avg)} 分")
    }
    if (data.round > 1) {
        parts.add("第 ${data.round} 遍")
    }
    return parts.joinToString(" · ")
}

/** 鼓励语 = 本地中文文案 + 具体化补充（挑本次读得最好的词）。 */
internal fun encouragementZhText(data: FlowSummaryData): String =
    data.encouragement.zh + data.encouragement.praise

/** 平均分文案：整数不带小数点，否则保留 1 位（与 hos 的 round(x*10)/10 一致）。 */
private fun averageText(avg: Double): String {
    val rounded = (avg * 10).roundToInt()
    return if (rounded % 10 == 0) (rounded / 10).toString() else "${rounded / 10}.${rounded % 10}"
}

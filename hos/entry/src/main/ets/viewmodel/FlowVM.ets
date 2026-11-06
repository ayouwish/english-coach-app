import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { ApiErrorCode } from '../core/net/ApiError';
import { UiError } from '../core/error/UiError';
import { AsyncResultDto, AsyncStatusItemDto, MaterialDetailDto, MaterialDto, OcrResultDto, ScoresDto, SentenceDto, WordScoreDto } from '../core/net/Dtos';
import { FlowService } from '../core/service/FlowService';
import { PracticeService } from '../core/service/PracticeService';
import { SessionStore } from '../core/session/SessionStore';
import { AudioController } from '../core/audio/AudioController';
import { RecordingResult } from '../core/audio/AudioRecorder';
import { AppConfig } from '../core/config/AppConfig';
import { AppRuntime } from '../core/config/AppRuntime';
import { CacheService } from '../core/service/CacheService';
import { FileUtil } from '../core/util/FileUtil';
import { EcScore } from '../design/DesignTokens';
/** 连读阶段：setup → running → summary（再读一遍回 running，再读一段回 setup）。 */
export class FlowPhase {
    static readonly SETUP: string = 'setup';
    static readonly RUNNING: string = 'running';
    static readonly SUMMARY: string = 'summary';
}
/** 单句状态：unsent | pending | scoring | done | failed */
export class FlowStatus {
    static readonly UNSENT: string = 'unsent';
    static readonly PENDING: string = 'pending';
    static readonly SCORING: string = 'scoring';
    static readonly DONE: string = 'done';
    static readonly FAILED: string = 'failed';
}
/** 连读中一句话的本地模型（服务端 attempt 的可视化镜像）。 */
export class FlowItem {
    index: number = 0;
    text: string = '';
    sentenceId: string = '';
    /** corpus | custom */
    source: string = 'custom';
    materialId: string = '';
    attemptId: string = '';
    status: string = FlowStatus.UNSENT;
    error: string = '';
    hasResult: boolean = false;
    scorePron: number = -1;
    scoreAccuracy: number = -1;
    scoreFluency: number = -1;
    scoreCompleteness: number = -1;
    scoreProsody: number = -1;
    recognizedText: string = '';
    noSpeech: boolean = false;
    feedbackSummary: string = '';
    feedbackPraise: string = '';
    feedbackClosing: string = '';
    pointTitles: string[] = [];
    pointHows: string[] = [];
    wordTexts: string[] = [];
    wordScores: number[] = [];
    issueTexts: string[] = [];
    constructor(index: number, text: string, sentenceId: string, source: string, materialId: string) {
        this.index = index;
        this.text = text;
        this.sentenceId = sentenceId;
        this.source = source;
        this.materialId = materialId;
    }
    /** 「重录这句」：清掉上一轮 attempt 的全部展示数据。 */
    resetForRedo(): void {
        this.attemptId = '';
        this.status = FlowStatus.UNSENT;
        this.error = '';
        this.hasResult = false;
        this.scorePron = -1;
        this.scoreAccuracy = -1;
        this.scoreFluency = -1;
        this.scoreCompleteness = -1;
        this.scoreProsody = -1;
        this.recognizedText = '';
        this.noSpeech = false;
        this.feedbackSummary = '';
        this.feedbackPraise = '';
        this.feedbackClosing = '';
        this.pointTitles = [];
        this.pointHows = [];
        this.wordTexts = [];
        this.wordScores = [];
        this.issueTexts = [];
    }
}
/** 一批句子（再读一遍时复用，不重新抽句/切句）。 */
export class FlowRunSentence {
    text: string = '';
    sentenceId: string = '';
    source: string = 'custom';
    materialId: string = '';
    constructor(text: string, sentenceId: string, source: string, materialId: string) {
        this.text = text;
        this.sentenceId = sentenceId;
        this.source = source;
        this.materialId = materialId;
    }
}
/** 汇总页「最差 3 句」一行。 */
export class FlowWorstItem {
    score: number = -1;
    text: string = '';
    index: number = 0;
}
/** 本地鼓励语文案（中英双语，6 档，确定性挑选）。 */
export class FlowEncouragement {
    tier: string = '';
    zh: string = '';
    en: string = '';
    /** 具体化补充（可能为空） */
    praise: string = '';
}
class FlowEnc {
    zh: string = '';
    en: string = '';
    constructor(zh: string, en: string) {
        this.zh = zh;
        this.en = en;
    }
}
/** 汇总页渲染快照（一次构建，避免页面反复计算）。 */
export class FlowSummaryData {
    round: number = 1;
    total: number = 0;
    /** 已评分句数（done 且 pron 非 null） */
    doneCount: number = 0;
    failedCount: number = 0;
    /** -1 = 没有可算的平均分 */
    avgScore: number = -1;
    worst: FlowWorstItem[] = [];
    encouragement: FlowEncouragement = new FlowEncouragement();
    /** 参与 scope=batch 诊断的 attempt id（≤20） */
    attemptIds: string[] = [];
    items: FlowItem[] = [];
}
/** 纯文本工具：切句规则按规格 §5.2（保留句末标点，丢弃无字母碎片）。 */
export class FlowText {
    static splitSentences(input: string): string[] {
        const out: string[] = [];
        let current = '';
        for (let i = 0; i < input.length; i++) {
            const ch = input.charAt(i);
            current = current + ch;
            if (ch === '.' || ch === '!' || ch === '?' || ch === '。' || ch === '！' || ch === '？') {
                const trimmed = current.trim();
                if (trimmed.length > 0) {
                    out.push(trimmed);
                }
                current = '';
            }
        }
        const tail = current.trim();
        if (tail.length > 0) {
            out.push(tail);
        }
        const result: string[] = [];
        for (let i = 0; i < out.length; i++) {
            if (FlowText.letterCount(out[i]) > 0) {
                result.push(out[i]);
            }
        }
        return result;
    }
    /** 英文字母个数（判断「有没有听到内容」用，数字/标点不算）。 */
    static letterCount(text: string): number {
        let count = 0;
        for (let i = 0; i < text.length; i++) {
            const ch = text.charAt(i);
            if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
                count = count + 1;
            }
        }
        return count;
    }
    /** 取首行并截断（保存书页的默认标题）。 */
    static firstLine(text: string, max: number): string {
        const idx = text.indexOf('\n');
        const line = idx >= 0 ? text.substring(0, idx) : text;
        const trimmed = line.trim();
        const value = trimmed.length > max ? trimmed.substring(0, max) : trimmed;
        return value.length > 0 ? value : '未命名书页';
    }
}
/**
 * 连读模式状态机（规格 .specs/practice-flow.md §5）。
 *
 * 关键约束：
 * - 提交 `/attempts/async` 拿到 id 立刻置 pending 并进下一句，不等待评分；
 * - 1200ms 轮询 `/attempts/status?ids=`，只传 pending/scoring 的 id；全部 settled 停表；
 * - `runSentences` 保存本批句子，「再读一遍」复用（round+1，不重新抽句，旧 pending 丢弃）；
 * - 轮询定时器由页面 aboutToDisappear 的 `dispose()` 停掉。
 *
 * 说明：ArkTS 的 @Observed 只观察第一层属性，因此 `items` 内部元素更新后统一调用
 * `notifyItems()` 重新赋值数组来触发页面刷新。
 */
@Observed
export class FlowVM {
    // ---- 身份 / 阶段
    isChild: boolean = false;
    userId: string = '';
    phase: string = FlowPhase.SETUP;
    round: number = 1;
    /** 汇总完成回调（由页面注入：push Routes.FLOW_SUMMARY） */
    onFinished: (() => void) | null = null;
    // ---- setup：语料
    sourceTab: number = 0;
    level: string = 'A1';
    /** true = 已按账号 cefrLevel 初始化过默认等级 */
    private levelReady: boolean = false;
    corpus: SentenceDto[] = [];
    corpusLoading: boolean = false;
    corpusError: string = '';
    startIndex: number = 0;
    count: number = 5;
    randomMode: boolean = false;
    randomPick: SentenceDto[] = [];
    preview: SentenceDto[] = [];
    // ---- setup：我的书页
    materials: MaterialDto[] = [];
    materialsLoading: boolean = false;
    materialsError: string = '';
    materialBusyId: string = '';
    // ---- setup：自己输入 / OCR
    customInput: string = '';
    customSentences: string[] = [];
    /** 从书页进入时带上 material_id（提交 async 时一起传） */
    runMaterialId: string = '';
    /** 从故事进入时的标题（running 页显示「正在读：xxx」） */
    runTitle: string = '';
    ocrEnabled: boolean = true;
    ocrBusy: boolean = false;
    ocrStatusText: string = '';
    ocrError: string = '';
    ocrInfoText: string = '';
    saveTitle: string = '';
    saveBusy: boolean = false;
    saveError: string = '';
    savedPageId: string = '';
    savedPageTitle: string = '';
    /** 正在编辑的书页 id（非空时保存走 PATCH 而不是新建） */
    editingMaterialId: string = '';
    /** 正在编辑/删除的书页 id（行内 loading） */
    materialEditBusyId: string = '';
    // ---- setup：错误
    setupError: string = '';
    // ---- running
    items: FlowItem[] = [];
    runSentences: FlowRunSentence[] = [];
    currentIndex: number = 0;
    autoNext: boolean = true;
    expandedIndex: number = -1;
    recording: boolean = false;
    preparing: boolean = false;
    submitting: boolean = false;
    elapsedMs: number = 0;
    allSubmitted: boolean = false;
    limitMessage: string = '';
    limitReached: boolean = false;
    // ---- running：错误（统一 UiError，页面只展示文案）
    hasError: boolean = false;
    error: UiError = new UiError('', '', '', false, '');
    // ---- summary
    summary: FlowSummaryData = new FlowSummaryData();
    // ---- 内部定时器/标记
    private pollTimer: number = -1;
    private recordTimer: number = -1;
    private advanceTimer: number = -1;
    private recordStartedAt: number = 0;
    private polling: boolean = false;
    private finished: boolean = false;
    // ================================================================== 生命周期
    /** 页面出现：注入身份；首次进入时拉语料。 */
    async init(): Promise<void> {
        this.checkOcrCapability();
        if (this.phase === FlowPhase.RUNNING && this.items.length > 0) {
            this.resume();
            return;
        }
        if (this.phase === FlowPhase.SUMMARY && this.items.length > 0) {
            // 刚读完一轮：保留汇总态（「查看本轮汇总」可再次打开）
            return;
        }
        this.phase = FlowPhase.SETUP;
        this.round = 1;
        this.clearSetupError();
        await this.loadCorpus();
    }
    /** 页面再次可见（从汇总返回 / 切回 Tab）：有待评项就立刻补拉一次。 */
    resume(): void {
        if (this.phase !== FlowPhase.RUNNING) {
            return;
        }
        if (this.pendingCount() > 0) {
            this.startPolling();
            void this.pollOnce();
            return;
        }
        if (this.allSubmitted && !this.finished) {
            this.checkAllSettled();
        }
    }
    /** 设置阶段身份（切换账号时重置，避免上一用户的数据串台）。 */
    attach(isChild: boolean, cefrLevel: string, userId: string): void {
        if (this.userId.length > 0 && this.userId !== userId) {
            this.resetForUserChange();
        }
        this.userId = userId;
        this.isChild = isChild;
        if (!this.levelReady) {
            const mapped = AppConfig.levelForCefr(cefrLevel);
            if (this.level.length === 0 || this.level === 'A1') {
                this.level = mapped;
            }
            this.levelReady = true;
        }
    }
    /** 页面销毁 / 切后台：停轮询、丢录音、停播放（规格 §5.4 / §8）。 */
    dispose(): void {
        this.stopPolling();
        this.stopRecordTimer();
        this.clearAdvanceTimer();
        this.recording = false;
        this.preparing = false;
        void AudioController.stopAll();
    }
    private resetForUserChange(): void {
        this.dispose();
        this.items = [];
        this.runSentences = [];
        this.corpus = [];
        this.preview = [];
        this.randomPick = [];
        this.materials = [];
        this.customInput = '';
        this.customSentences = [];
        this.runMaterialId = '';
        this.savedPageId = '';
        this.savedPageTitle = '';
        this.phase = FlowPhase.SETUP;
        this.round = 1;
        this.currentIndex = 0;
        this.expandedIndex = -1;
        this.allSubmitted = false;
        this.finished = false;
        this.limitReached = false;
        this.limitMessage = '';
        this.clearError();
        this.clearSetupError();
        this.levelReady = false;
        this.summary = new FlowSummaryData();
    }
    // ================================================================== setup：语料
    async loadCorpus(): Promise<void> {
        this.corpusLoading = true;
        this.corpusError = '';
        try {
            if (this.level === 'ALL') {
                const levels: string[] = ['A1', 'A2', 'B1', 'B2'];
                const merged: SentenceDto[] = [];
                for (let i = 0; i < levels.length; i++) {
                    try {
                        const part = await PracticeService.sentences(levels[i]);
                        for (let j = 0; j < part.length; j++) {
                            merged.push(part[j]);
                        }
                    }
                    catch (err) {
                        // 单级别失败不影响其它级别（「全部」是聚合视图）
                    }
                }
                if (merged.length === 0) {
                    throw new Error('corpus_empty');
                }
                this.corpus = merged;
            }
            else {
                this.corpus = await PracticeService.sentences(this.level);
            }
            if (this.startIndex >= this.corpus.length) {
                this.startIndex = 0;
            }
            if (this.randomMode) {
                this.drawRandom();
            }
            this.refreshPreview();
        }
        catch (err) {
            this.corpus = [];
            this.preview = [];
            this.corpusError = this.isChild ? '句子没有取到，再试一次吧' : '取句子失败，请检查网络后重试';
        }
        finally {
            this.corpusLoading = false;
        }
    }
    setLevel(level: string): void {
        if (this.level === level) {
            return;
        }
        this.level = level;
        this.startIndex = 0;
        this.randomPick = [];
        this.setupError = '';
        void this.loadCorpus();
    }
    setStartIndex(value: number): void {
        const max = this.corpus.length > 0 ? this.corpus.length - 1 : 0;
        let next = value;
        if (next < 0) {
            next = 0;
        }
        if (next > max) {
            next = max;
        }
        this.startIndex = next;
        this.refreshPreview();
    }
    setCount(value: number): void {
        if (this.count === value) {
            return;
        }
        this.count = value;
        if (this.randomMode) {
            this.drawRandom();
        }
        else {
            this.refreshPreview();
        }
    }
    /** 事件回调里抽句（绝不在渲染期随机）。 */
    toggleRandom(): void {
        this.randomMode = !this.randomMode;
        if (this.randomMode) {
            this.drawRandom();
        }
        else {
            this.randomPick = [];
            this.refreshPreview();
        }
    }
    /** 🎲 随机 / 🔀 换一批：从当前级别池里不重复抽 count 句。 */
    drawRandom(): void {
        const pool = this.corpus;
        const picked: SentenceDto[] = [];
        if (pool.length === 0) {
            this.randomPick = picked;
            this.refreshPreview();
            return;
        }
        const indices: number[] = [];
        for (let i = 0; i < pool.length; i++) {
            indices.push(i);
        }
        for (let i = indices.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const tmp = indices[i];
            indices[i] = indices[j];
            indices[j] = tmp;
        }
        const wanted = this.count < pool.length ? this.count : pool.length;
        for (let i = 0; i < wanted; i++) {
            picked.push(pool[indices[i]]);
        }
        this.randomPick = picked;
        this.refreshPreview();
    }
    private refreshPreview(): void {
        if (this.randomMode && this.randomPick.length > 0) {
            this.preview = this.randomPick;
            return;
        }
        const out: SentenceDto[] = [];
        for (let i = this.startIndex; i < this.corpus.length && out.length < this.count; i++) {
            out.push(this.corpus[i]);
        }
        this.preview = out;
    }
    levelPoolSize(): number {
        return this.corpus.length;
    }
    // ================================================================== setup：我的书页
    async loadMaterials(): Promise<void> {
        if (this.materialsLoading) {
            return;
        }
        this.materialsLoading = true;
        this.materialsError = '';
        try {
            this.materials = await FlowService.materialsPage(50);
        }
        catch (err) {
            this.materialsError = this.uiMessage(err as Error);
        }
        finally {
            this.materialsLoading = false;
        }
    }
    /** 点开书页：读详情 → 把文本灌进「自己输入」并切句（可再改）。 */
    async openMaterial(id: string): Promise<void> {
        if (this.materialBusyId.length > 0) {
            return;
        }
        this.materialBusyId = id;
        this.materialsError = '';
        this.setupError = '';
        try {
            const detail: MaterialDetailDto = await FlowService.materialDetail(id);
            const text = detail.text === undefined ? '' : detail.text;
            if (text.trim().length === 0) {
                this.materialsError = '这篇书页只有图片、没有文字，换一篇试试';
                return;
            }
            this.runMaterialId = id;
            this.customInput = text;
            this.customSentences = FlowText.splitSentences(text);
            this.sourceTab = 2;
            if (this.customSentences.length === 0) {
                this.setupError = '这篇书页里没有找到可读的英文句子';
            }
        }
        catch (err) {
            this.materialsError = this.uiMessage(err as Error);
        }
        finally {
            this.materialBusyId = '';
        }
    }
    // ================================================================== setup：自己输入 / OCR
    /** 编辑书页：读详情 → 灌进「自己输入」→ 保存时走 PATCH /materials/:id。 */
    async beginEdit(id: string): Promise<void> {
        if (this.materialEditBusyId.length > 0) {
            return;
        }
        this.materialEditBusyId = id;
        this.materialsError = '';
        this.setupError = '';
        this.saveError = '';
        try {
            const detail: MaterialDetailDto = await FlowService.materialDetail(id);
            const text = detail.text === undefined ? '' : detail.text;
            const title = detail.title === undefined ? '' : detail.title;
            this.customInput = text;
            this.customSentences = FlowText.splitSentences(text);
            this.saveTitle = title;
            this.editingMaterialId = id;
            this.savedPageId = '';
            this.savedPageTitle = '';
            this.sourceTab = 2;
        }
        catch (err) {
            this.materialsError = this.uiMessage(err as Error);
        }
        finally {
            this.materialEditBusyId = '';
        }
    }

    /** 取消编辑，回到普通输入状态。 */
    cancelEdit(): void {
        this.editingMaterialId = '';
        this.customInput = '';
        this.customSentences = [];
        this.saveTitle = '';
        this.savedPageId = '';
        this.savedPageTitle = '';
        this.saveError = '';
    }

    /** 删除书页（服务端校验只能删自己录入的）。 */
    async removeMaterial(id: string): Promise<void> {
        if (this.materialEditBusyId.length > 0) {
            return;
        }
        this.materialEditBusyId = id;
        this.materialsError = '';
        try {
            await FlowService.deletePage(id);
            if (this.editingMaterialId === id) {
                this.cancelEdit();
            }
            await this.loadMaterials();
        }
        catch (err) {
            this.materialsError = this.uiMessage(err as Error);
        }
        finally {
            this.materialEditBusyId = '';
        }
    }
    setCustomInput(text: string): void {
        this.customInput = text;
        this.runMaterialId = '';
    }
    /** ✂️ 切句 */
    splitCustom(): void {
        this.runMaterialId = '';
        this.customSentences = FlowText.splitSentences(this.customInput);
        if (this.customSentences.length === 0) {
            this.setupError = this.isChild ? '先写几句英文吧' : '没有切出句子：先输入一段英文，再点「切句」';
        }
        else {
            this.setupError = '';
        }
    }
    /** 逐句修改（TextInput onChange 直接写数组元素；不触发布局重排）。 */
    updateCustomSentence(index: number, text: string): void {
        if (index < 0 || index >= this.customSentences.length) {
            return;
        }
        this.customSentences[index] = text;
    }
    /** 拍照/相册（系统 PhotoViewPicker，不需要媒体库权限、不申请 CAMERA）。 */
    async pickPhotoAndOcr(): Promise<void> {
        if (this.ocrBusy) {
            return;
        }
        this.ocrError = '';
        const ctx = AppRuntime.context();
        if (ctx === null) {
            this.ocrError = '应用还没准备好，请稍后再试';
            return;
        }
        let uri = '';
        try {
            const options = new photoAccessHelper.PhotoSelectOptions();
            options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
            options.maxSelectNumber = 1;
            const picker = new photoAccessHelper.PhotoViewPicker();
            const result = await picker.select(options);
            if (result.photoUris.length > 0) {
                uri = result.photoUris[0];
            }
        }
        catch (err) {
            // 用户取消选择是常态：不弹错误
            return;
        }
        if (uri.length === 0) {
            return;
        }
        const localPath = this.copyPickedImage(uri);
        if (localPath.length === 0) {
            this.ocrError = '读取照片失败，请重新选择一张';
            return;
        }
        this.ocrBusy = true;
        this.ocrStatusText = '正在识别…';
        try {
            const result = await FlowService.ocr(localPath);
            const text = result.text === undefined ? '' : result.text.trim();
            if (text.length === 0) {
                this.ocrError = this.isChild
                    ? '这张图里没有找到英文句子，换一张更清楚的照片试试，或者用「自己输入」'
                    : '这张图里没有识别到英文文字。换一张更清晰、文字更大的照片，或改用「自己输入一段」';
                return;
            }
            this.appendOcrText(text, result);
        }
        catch (err) {
            this.ocrError = this.ocrMessage(err as Error);
        }
        finally {
            FileUtil.remove(localPath);
            this.ocrBusy = false;
            this.ocrStatusText = '';
        }
    }
    private appendOcrText(text: string, result: OcrResultDto): void {
        this.sourceTab = 2;
        this.runMaterialId = '';
        const prev = this.customInput.trim();
        this.customInput = prev.length > 0 ? (prev + '\n' + text) : text;
        this.customSentences = FlowText.splitSentences(this.customInput);
        const lines = result.lines === undefined ? 0 : result.lines.length;
        const provider = result.provider === undefined ? '-' : result.provider;
        const elapsed = result.elapsed_ms === undefined ? -1 : result.elapsed_ms;
        let info = '已识别 ' + lines.toString() + ' 行 · ' + provider;
        if (elapsed >= 0) {
            info = info + ' · ' + elapsed.toString() + 'ms';
        }
        this.ocrInfoText = info + '，已追加到下面的文本框';
        this.saveTitle = FlowText.firstLine(text, 40);
        this.savedPageId = '';
        this.savedPageTitle = '';
        this.saveError = '';
        this.setupError = '';
    }
    private copyPickedImage(uri: string): string {
        let src: fileIo.File | null = null;
        try {
            CacheService.ensureAll();
            const dest = AppRuntime.cacheDir() + '/ocr_' + Date.now().toString() + '.' + FlowVM.imageExt(uri);
            src = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
            fileIo.copyFileSync(src.fd, dest);
            return dest;
        }
        catch (err) {
            return '';
        }
        finally {
            if (src !== null) {
                try {
                    fileIo.closeSync(src);
                }
                catch (err) {
                    // 关闭失败不阻塞
                }
            }
        }
    }
    private static imageExt(uri: string): string {
        const lower = uri.toLowerCase();
        const dot = lower.lastIndexOf('.');
        if (dot >= 0) {
            const ext = lower.substring(dot + 1);
            if (ext === 'png' || ext === 'jpg' || ext === 'jpeg' || ext === 'heic' || ext === 'heif' || ext === 'webp') {
                return ext === 'jpeg' ? 'jpg' : ext;
            }
        }
        return 'jpg';
    }
    private ocrMessage(err: Error): string {
        const ui = SessionStore.toUiError(err, this.isChild);
        if (err.name === 'ApiError') {
            // 服务端 503 ocr_unavailable 的 message 已给出可操作建议（「可以先用自己输入一段」）
            return ui.message;
        }
        return this.isChild ? '识别没有成功，再试一次吧' : '识别没有成功，请重试或改用「自己输入一段」';
    }
    /** 💾 保存为「我的书页」（POST /materials，仅文字）。 */
    async saveAsPage(): Promise<void> {
        if (this.saveBusy || (this.savedPageId.length > 0 && this.editingMaterialId.length === 0)) {
            return;
        }
        // 优先保存「逐句修改后」的文本；没有切过句再用原输入
        let text = this.customSentences.length > 0 ? this.customSentences.join(' ') : this.customInput.trim();
        if (text.trim().length === 0) {
            text = this.customInput.trim();
        }
        if (text.trim().length === 0) {
            this.saveError = '还没有可保存的文字';
            return;
        }
        this.saveBusy = true;
        this.saveError = '';
        try {
            const title = this.saveTitle.trim().length > 0 ? this.saveTitle.trim() : '未命名书页';
            if (this.editingMaterialId.length > 0) {
                await FlowService.updatePage(this.editingMaterialId, title, text);
                this.savedPageId = this.editingMaterialId;
                this.savedPageTitle = title;
                this.editingMaterialId = '';
            } else {
                const created = await FlowService.createPage(title, text);
                this.savedPageId = created.id;
                this.savedPageTitle = title;
            }
            void this.loadMaterials();
        }
        catch (err) {
            this.saveError = this.uiMessage(err as Error);
        }
        finally {
            this.saveBusy = false;
        }
    }
    /** 保存后直接连读。 */    async saveAndRead(): Promise<void> {
        if (this.savedPageId.length === 0) {
            await this.saveAsPage();
        }
        if (this.savedPageId.length === 0) {
            return;
        }
        this.runMaterialId = this.savedPageId;
        this.startCustom();
    }
    // ================================================================== 开始连读
    startCorpus(): void {
        if (this.preview.length === 0) {
            this.setupError = this.isChild ? '这里还没有句子，换一个起点吧' : '这个位置没有句子，换个起点或级别试试';
            return;
        }
        const sentences: FlowRunSentence[] = [];
        for (let i = 0; i < this.preview.length; i++) {
            const item = this.preview[i];
            sentences.push(new FlowRunSentence(item.text, item.id, 'corpus', ''));
        }
        this.beginRun(sentences);
    }
    /** 故事页「朗读这个故事」：用故事句子直接开始连读（带 material_id，汇总可做复述）。 */
    startStoryRead(title: string, materialId: string, texts: string[]): boolean {
        const sentences: FlowRunSentence[] = [];
        for (let i = 0; i < texts.length; i++) {
            const text = texts[i].trim();
            if (text.length > 0) {
                sentences.push(new FlowRunSentence(text, '', 'custom', materialId));
            }
        }
        if (sentences.length === 0) {
            this.setupError = '这个故事还没有英文句子，先回故事页生成一下';
            return false;
        }
        this.runMaterialId = materialId;
        this.runTitle = title;
        this.beginRun(sentences);
        return true;
    }
    startCustom(): void {
        let list = this.customSentences;
        if (list.length === 0) {
            list = FlowText.splitSentences(this.customInput);
            this.customSentences = list;
        }
        if (list.length === 0) {
            this.setupError = this.isChild ? '先写几句话吧' : '先输入一段文本，再点「切句」';
            return;
        }
        const sentences: FlowRunSentence[] = [];
        for (let i = 0; i < list.length; i++) {
            const text = list[i].trim();
            if (text.length > 0) {
                sentences.push(new FlowRunSentence(text, '', 'custom', this.runMaterialId));
            }
        }
        if (sentences.length === 0) {
            this.setupError = '切出来的句子都是空的，再检查一下文本';
            return;
        }
        this.beginRun(sentences);
    }
    private beginRun(sentences: FlowRunSentence[]): void {
        this.runSentences = sentences;
        this.items = this.buildItems(sentences);
        this.currentIndex = 0;
        this.round = 1;
        this.expandedIndex = -1;
        this.phase = FlowPhase.RUNNING;
        this.allSubmitted = false;
        this.finished = false;
        this.limitReached = false;
        this.limitMessage = '';
        this.recording = false;
        this.preparing = false;
        this.submitting = false;
        this.elapsedMs = 0;
        this.clearError();
        this.clearSetupError();
        this.stopPolling();
        this.stopRecordTimer();
        this.clearAdvanceTimer();
    }
    private buildItems(sentences: FlowRunSentence[]): FlowItem[] {
        const items: FlowItem[] = [];
        for (let i = 0; i < sentences.length; i++) {
            const sentence = sentences[i];
            items.push(new FlowItem(i, sentence.text, sentence.sentenceId, sentence.source, sentence.materialId));
        }
        return items;
    }
    // ================================================================== running：录音 / 提交
    currentItem(): FlowItem | null {
        if (this.currentIndex < 0 || this.currentIndex >= this.items.length) {
            return null;
        }
        return this.items[this.currentIndex];
    }
    async startRecording(): Promise<void> {
        if (this.recording || this.preparing || this.submitting) {
            return;
        }
        if (this.phase !== FlowPhase.RUNNING) {
            return;
        }
        if (this.limitReached) {
            this.setErrorText('今天的练习时间到啦，明天再来吧 🌙');
            return;
        }
        const item = this.currentItem();
        if (item === null) {
            return;
        }
        if (item.status !== FlowStatus.UNSENT) {
            this.setErrorText('这一句已经提交过了，点「下一句」继续');
            return;
        }
        this.clearError();
        this.limitMessage = '';
        this.preparing = true;
        try {
            await AudioController.startRecording();
            this.recording = true;
            this.recordStartedAt = Date.now();
            this.elapsedMs = 0;
            this.startRecordTimer();
        }
        catch (err) {
            this.recording = false;
            this.setUiError(err as Error);
        }
        finally {
            this.preparing = false;
        }
    }
    async stopAndSubmit(): Promise<void> {
        if (!this.recording) {
            return;
        }
        this.recording = false;
        this.stopRecordTimer();
        const index = this.currentIndex;
        let recorded: RecordingResult | null = null;
        try {
            recorded = await AudioController.stopRecording();
        }
        catch (err) {
            // 太短（<600ms）/空文件已被 AudioRecorder 拦掉：只提示，不产生请求
            this.setUiError(err as Error);
            return;
        }
        if (recorded === null) {
            return;
        }
        await this.submitAsync(index, recorded);
    }
    async cancelRecording(): Promise<void> {
        this.recording = false;
        this.stopRecordTimer();
        this.elapsedMs = 0;
        await AudioController.cancelRecording();
    }
    private async submitAsync(index: number, recorded: RecordingResult): Promise<void> {
        if (index < 0 || index >= this.items.length) {
            FileUtil.remove(recorded.path);
            return;
        }
        const item = this.items[index];
        this.submitting = true;
        this.clearError();
        try {
            const dto = await FlowService.submitAsync(recorded.path, item.text, item.sentenceId, item.source, item.materialId, recorded.durationMs);
            let attemptId = '';
            if (dto.id !== undefined && dto.id.length > 0) {
                attemptId = dto.id;
            }
            else if (dto.attempt_id !== undefined && dto.attempt_id.length > 0) {
                attemptId = dto.attempt_id;
            }
            if (attemptId.length === 0) {
                throw new Error('提交返回缺少 id');
            }
            item.attemptId = attemptId;
            item.status = FlowStatus.PENDING;
            item.error = '';
            item.hasResult = false;
            this.notifyItems();
            FileUtil.remove(recorded.path);
            this.afterSubmitted(index);
        }
        catch (err) {
            FileUtil.remove(recorded.path);
            item.status = FlowStatus.FAILED;
            const ui = SessionStore.toUiError(err as Error, this.isChild);
            item.error = ui.message;
            if (ui.code === ApiErrorCode.DAILY_LIMIT_REACHED) {
                this.limitReached = true;
                this.limitMessage = '🌙 ' + ui.message;
            }
            else {
                this.setUiError(err as Error);
            }
            this.notifyItems();
        }
        finally {
            this.submitting = false;
        }
    }
    private afterSubmitted(index: number): void {
        this.checkAllSubmitted();
        this.startPolling();
        if (!this.autoNext) {
            // 不自动跳：页面显示「下一句 →」，用户也可以点「重录这句」重读当前句
            this.checkAllSettled();
            return;
        }
        this.clearAdvanceTimer();
        this.advanceTimer = setTimeout(() => {
            this.advanceTimer = -1;
            const next = this.nextUnsentIndex(index);
            if (next >= 0) {
                this.currentIndex = next;
                this.clearError();
            }
            this.checkAllSettled();
        }, 400);
    }
    /** 是否还有未读的句子（页面决定是否显示「下一句 →」）。 */
    hasNextUnsent(): boolean {
        return this.nextUnsentIndex(this.currentIndex) >= 0;
    }
    nextSentence(): void {
        const next = this.nextUnsentIndex(this.currentIndex);
        if (next >= 0) {
            this.currentIndex = next;
            this.clearError();
        }
        this.checkAllSettled();
    }
    private nextUnsentIndex(from: number): number {
        for (let i = from + 1; i < this.items.length; i++) {
            if (this.items[i].status === FlowStatus.UNSENT) {
                return i;
            }
        }
        for (let i = 0; i < this.items.length; i++) {
            if (this.items[i].status === FlowStatus.UNSENT) {
                return i;
            }
        }
        return -1;
    }
    private checkAllSubmitted(): void {
        let all = true;
        for (let i = 0; i < this.items.length; i++) {
            if (this.items[i].status === FlowStatus.UNSENT) {
                all = false;
                break;
            }
        }
        this.allSubmitted = all;
    }
    private startRecordTimer(): void {
        this.stopRecordTimer();
        this.recordTimer = setInterval(() => {
            this.elapsedMs = Date.now() - this.recordStartedAt;
            if (this.elapsedMs >= 60000) {
                void this.stopAndSubmit();
            }
        }, 200);
    }
    private stopRecordTimer(): void {
        if (this.recordTimer >= 0) {
            clearInterval(this.recordTimer);
            this.recordTimer = -1;
        }
    }
    private clearAdvanceTimer(): void {
        if (this.advanceTimer >= 0) {
            clearTimeout(this.advanceTimer);
            this.advanceTimer = -1;
        }
    }
    // ================================================================== running：轮询
    startPolling(): void {
        if (this.pollTimer >= 0) {
            return;
        }
        if (this.phase !== FlowPhase.RUNNING) {
            return;
        }
        if (this.pendingIds().length === 0) {
            return;
        }
        this.pollTimer = setInterval(() => {
            void this.pollOnce();
        }, 1200);
        void this.pollOnce();
    }
    stopPolling(): void {
        if (this.pollTimer >= 0) {
            clearInterval(this.pollTimer);
            this.pollTimer = -1;
        }
    }
    private pendingIds(): string[] {
        const ids: string[] = [];
        for (let i = 0; i < this.items.length && ids.length < 50; i++) {
            const item = this.items[i];
            if (item.attemptId.length === 0) {
                continue;
            }
            if (item.status === FlowStatus.PENDING || item.status === FlowStatus.SCORING) {
                ids.push(item.attemptId);
            }
        }
        return ids;
    }
    private async pollOnce(): Promise<void> {
        if (this.polling) {
            return;
        }
        const ids = this.pendingIds();
        if (ids.length === 0) {
            this.stopPolling();
            this.checkAllSettled();
            return;
        }
        this.polling = true;
        try {
            const updates = await FlowService.status(ids);
            if (updates.length > 0) {
                for (let i = 0; i < this.items.length; i++) {
                    const item = this.items[i];
                    if (item.attemptId.length === 0) {
                        continue;
                    }
                    for (let j = 0; j < updates.length; j++) {
                        const update = updates[j];
                        if (update.id === item.attemptId) {
                            this.applyStatus(item, update);
                            break;
                        }
                    }
                }
                this.notifyItems();
            }
        }
        catch (err) {
            // 轮询失败静默：下一拍重试（规格 §5.4）
        }
        finally {
            this.polling = false;
        }
        if (this.pendingIds().length === 0) {
            this.stopPolling();
        }
        this.checkAllSettled();
    }
    private applyStatus(item: FlowItem, update: AsyncStatusItemDto): void {
        if (update.status === FlowStatus.PENDING || update.status === FlowStatus.SCORING
            || update.status === FlowStatus.DONE || update.status === FlowStatus.FAILED) {
            item.status = update.status;
        }
        if (update.status === FlowStatus.FAILED) {
            item.error = (update.error === undefined || update.error === null || update.error.length === 0)
                ? '评分没有成功，可以重录这句' : update.error;
            item.hasResult = false;
            return;
        }
        if (update.status !== FlowStatus.DONE) {
            return;
        }
        const result = update.result;
        if (result === undefined || result === null) {
            item.status = FlowStatus.FAILED;
            item.error = '评分结果格式异常，可以重录这句';
            item.hasResult = false;
            return;
        }
        item.error = '';
        this.applyResult(item, result);
    }
    private applyResult(item: FlowItem, result: AsyncResultDto): void {
        item.hasResult = true;
        const scores = result.scores;
        if (scores === undefined) {
            item.scorePron = -1;
            item.scoreAccuracy = -1;
            item.scoreFluency = -1;
            item.scoreCompleteness = -1;
            item.scoreProsody = -1;
        }
        else {
            item.scorePron = FlowVM.scoreOf(scores, 'pron');
            item.scoreAccuracy = FlowVM.scoreOf(scores, 'accuracy');
            item.scoreFluency = FlowVM.scoreOf(scores, 'fluency');
            item.scoreCompleteness = FlowVM.scoreOf(scores, 'completeness');
            item.scoreProsody = FlowVM.scoreOf(scores, 'prosody');
        }
        const recognized = result.recognized_text;
        item.recognizedText = recognized === undefined ? '' : recognized;
        item.noSpeech = FlowText.letterCount(item.recognizedText) <= 1;
        this.applyFeedback(item, result);
        this.applyWords(item, result);
        this.applyIssues(item, result);
    }
    private applyFeedback(item: FlowItem, result: AsyncResultDto): void {
        item.feedbackSummary = '';
        item.feedbackPraise = '';
        item.feedbackClosing = '';
        item.pointTitles = [];
        item.pointHows = [];
        const feedback = result.feedback;
        if (feedback === undefined || feedback === null) {
            return;
        }
        item.feedbackSummary = feedback.summary === undefined ? '' : feedback.summary;
        item.feedbackPraise = feedback.praise === undefined ? '' : feedback.praise;
        item.feedbackClosing = feedback.closing === undefined ? '' : feedback.closing;
        const points = feedback.points;
        if (points === undefined || this.isChild) {
            return;
        }
        const titles: string[] = [];
        const hows: string[] = [];
        for (let i = 0; i < points.length && i < 2; i++) {
            const point = points[i];
            const title = point.title;
            const how = point.how;
            titles.push(title === undefined ? '' : title);
            hows.push(how === undefined ? '' : how);
        }
        item.pointTitles = titles;
        item.pointHows = hows;
    }
    /** 连读详情：word 只有分数，没有 phonemes（规格 §5.3 / §8），成人按分数升序展示。 */
    private applyWords(item: FlowItem, result: AsyncResultDto): void {
        item.wordTexts = [];
        item.wordScores = [];
        const words = result.words;
        if (words === undefined || this.isChild) {
            return;
        }
        const sorted: WordScoreDto[] = [];
        for (let i = 0; i < words.length; i++) {
            sorted.push(words[i]);
        }
        sorted.sort((a: WordScoreDto, b: WordScoreDto) => {
            const sa = (a.score === undefined || a.score === null) ? 101 : a.score;
            const sb = (b.score === undefined || b.score === null) ? 101 : b.score;
            return sa - sb;
        });
        const texts: string[] = [];
        const scores: number[] = [];
        for (let i = 0; i < sorted.length && i < 10; i++) {
            texts.push(sorted[i].word);
            scores.push((sorted[i].score === undefined || sorted[i].score === null) ? -1 : (sorted[i].score as number));
        }
        item.wordTexts = texts;
        item.wordScores = scores;
    }
    /** 儿童不展示 IPA / 音素信息，只保留成人版前 2 条。 */
    private applyIssues(item: FlowItem, result: AsyncResultDto): void {
        item.issueTexts = [];
        const issues = result.issues;
        if (issues === undefined || this.isChild) {
            return;
        }
        const texts: string[] = [];
        for (let i = 0; i < issues.length && i < 2; i++) {
            const issue = issues[i];
            const word = issue.word === undefined ? '' : issue.word;
            const expected = issue.expected === undefined || issue.expected === null ? '' : issue.expected;
            const actual = issue.actual === undefined || issue.actual === null ? '' : issue.actual;
            if (word.length === 0) {
                texts.push(issue.type === undefined ? '发音小问题' : issue.type);
            }
            else if (expected.length > 0 && actual.length > 0) {
                texts.push(word + '：' + expected + ' 发成了 ' + actual);
            }
            else {
                texts.push(word + (issue.type === undefined ? ' 发音注意一下' : '：' + issue.type));
            }
        }
        item.issueTexts = texts;
    }
    private static scoreOf(scores: ScoresDto, key: string): number {
        let value: number | null | undefined = null;
        if (key === 'pron') {
            value = scores.pron;
        }
        else if (key === 'accuracy') {
            value = scores.accuracy;
        }
        else if (key === 'fluency') {
            value = scores.fluency;
        }
        else if (key === 'completeness') {
            value = scores.completeness;
        }
        else if (key === 'prosody') {
            value = scores.prosody;
        }
        if (value === undefined || value === null) {
            return -1;
        }
        return value;
    }
    // ================================================================== running：状态 / 交互
    submittedCount(): number {
        let n = 0;
        for (let i = 0; i < this.items.length; i++) {
            if (this.items[i].status !== FlowStatus.UNSENT) {
                n = n + 1;
            }
        }
        return n;
    }
    pendingCount(): number {
        let n = 0;
        for (let i = 0; i < this.items.length; i++) {
            const status = this.items[i].status;
            if (status === FlowStatus.PENDING || status === FlowStatus.SCORING) {
                n = n + 1;
            }
        }
        return n;
    }
    doneCount(): number {
        let n = 0;
        for (let i = 0; i < this.items.length; i++) {
            if (this.items[i].status === FlowStatus.DONE) {
                n = n + 1;
            }
        }
        return n;
    }
    failedCount(): number {
        let n = 0;
        for (let i = 0; i < this.items.length; i++) {
            if (this.items[i].status === FlowStatus.FAILED) {
                n = n + 1;
            }
        }
        return n;
    }
    progressPercent(): number {
        if (this.items.length === 0) {
            return 0;
        }
        return Math.round(this.submittedCount() * 100 / this.items.length);
    }
    statusBadge(item: FlowItem): string {
        if (item.status === FlowStatus.DONE) {
            if (item.scorePron < 0) {
                return '已评分';
            }
            return EcScore.showNumber(item.scorePron, this.isChild) ? (Math.round(item.scorePron).toString() + ' 分') : '已评分';
        }
        if (item.status === FlowStatus.SCORING) {
            return '评分中…';
        }
        if (item.status === FlowStatus.PENDING) {
            return '待评分…';
        }
        if (item.status === FlowStatus.FAILED) {
            return '评分失败';
        }
        return '未读';
    }
    statusTone(item: FlowItem): string {
        if (item.status === FlowStatus.DONE) {
            return 'good';
        }
        if (item.status === FlowStatus.FAILED) {
            return 'bad';
        }
        if (item.status === FlowStatus.SCORING || item.status === FlowStatus.PENDING) {
            return 'primary';
        }
        return 'muted';
    }
    currentStatusLine(): string {
        const item = this.currentItem();
        if (item === null) {
            return '';
        }
        if (item.status === FlowStatus.PENDING) {
            return '这一句已提交，正在排队评分…（可以继续读下一句）';
        }
        if (item.status === FlowStatus.SCORING) {
            return '这一句正在评分…（可以继续读下一句）';
        }
        if (item.status === FlowStatus.DONE) {
            return '这一句已评分 ✅（可以继续读下一句）';
        }
        if (item.status === FlowStatus.FAILED) {
            return '这一句提交或评分没有成功';
        }
        return '';
    }
    toggleExpanded(index: number): void {
        this.expandedIndex = this.expandedIndex === index ? -1 : index;
        // 重新赋值数组，保证 ForEach 一定重算 key / 刷新行内容
        this.notifyItems();
    }
    /** 「重录这句」：重置该条并跳回去（旧 pending 直接丢弃）。 */
    retryItem(index: number): void {
        if (index < 0 || index >= this.items.length) {
            return;
        }
        const item = this.items[index];
        item.resetForRedo();
        this.currentIndex = index;
        this.expandedIndex = -1;
        this.phase = FlowPhase.RUNNING;
        this.finished = false;
        this.allSubmitted = false;
        this.limitReached = false;
        this.limitMessage = '';
        this.clearError();
        this.stopPolling();
        this.clearAdvanceTimer();
        this.notifyItems();
    }
    /** 汇总页「再读一遍」：同一批句子，items 重置 unsent，round+1，不重新抽句。 */
    reread(): void {
        if (this.runSentences.length === 0) {
            return;
        }
        this.items = this.buildItems(this.runSentences);
        this.currentIndex = 0;
        this.expandedIndex = -1;
        this.round = this.round + 1;
        this.phase = FlowPhase.RUNNING;
        this.allSubmitted = false;
        this.finished = false;
        this.limitReached = false;
        this.limitMessage = '';
        this.recording = false;
        this.preparing = false;
        this.submitting = false;
        this.elapsedMs = 0;
        this.clearError();
        this.stopPolling();
        this.stopRecordTimer();
        this.clearAdvanceTimer();
    }
    /** 汇总页「再读一段」：清空本次，回 setup。 */
    backToSetup(): void {
        this.phase = FlowPhase.SETUP;
        this.items = [];
        this.runSentences = [];
        this.currentIndex = 0;
        this.round = 1;
        this.expandedIndex = -1;
        this.allSubmitted = false;
        this.finished = false;
        this.limitReached = false;
        this.limitMessage = '';
        this.recording = false;
        this.preparing = false;
        this.submitting = false;
        this.clearError();
        this.clearSetupError();
        this.stopPolling();
        this.stopRecordTimer();
        this.clearAdvanceTimer();
    }
    private checkAllSettled(): void {
        if (this.phase !== FlowPhase.RUNNING || this.finished) {
            return;
        }
        if (!this.allSubmitted) {
            return;
        }
        if (this.pendingCount() > 0) {
            return;
        }
        this.finishRun();
    }
    /** 全部 done/failed → 停表 → 计算汇总快照 → 通知页面 push 汇总页。 */
    finishRun(): void {
        this.finished = true;
        this.stopPolling();
        this.clearAdvanceTimer();
        this.stopRecordTimer();
        this.recording = false;
        this.summary = this.buildSummary();
        this.phase = FlowPhase.SUMMARY;
        const callback = this.onFinished;
        if (callback !== null) {
            callback();
        }
    }
    // ================================================================== summary
    buildSummary(): FlowSummaryData {
        const data = new FlowSummaryData();
        data.round = this.round;
        data.total = this.items.length;
        const items: FlowItem[] = [];
        for (let i = 0; i < this.items.length; i++) {
            items.push(this.items[i]);
        }
        data.items = items;
        let scoredCount = 0;
        let sum = 0;
        let minCompleteness = -1;
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            if (item.status === FlowStatus.FAILED) {
                data.failedCount = data.failedCount + 1;
            }
            if (item.status !== FlowStatus.DONE || item.scorePron < 0) {
                continue;
            }
            scoredCount = scoredCount + 1;
            sum = sum + item.scorePron;
            if (item.attemptId.length > 0 && data.attemptIds.length < 20) {
                data.attemptIds.push(item.attemptId);
            }
            if (item.scoreCompleteness >= 0) {
                if (minCompleteness < 0 || item.scoreCompleteness < minCompleteness) {
                    minCompleteness = item.scoreCompleteness;
                }
            }
        }
        data.doneCount = scoredCount;
        data.avgScore = scoredCount > 0 ? Math.round((sum / scoredCount) * 10) / 10 : -1;
        const worst: FlowWorstItem[] = [];
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            if (item.status !== FlowStatus.DONE || item.scorePron < 0) {
                continue;
            }
            const row = new FlowWorstItem();
            row.score = item.scorePron;
            row.text = item.text;
            row.index = item.index;
            worst.push(row);
        }
        worst.sort((a: FlowWorstItem, b: FlowWorstItem) => a.score - b.score);
        const top: FlowWorstItem[] = [];
        for (let i = 0; i < worst.length && i < 3; i++) {
            top.push(worst[i]);
        }
        data.worst = top;
        data.encouragement = this.buildEncouragement(data, minCompleteness);
        return data;
    }
    private buildEncouragement(data: FlowSummaryData, minCompleteness: number): FlowEncouragement {
        let tier = 'C';
        if (data.doneCount === 0) {
            tier = 'no_speech';
        }
        else if (minCompleteness >= 0 && minCompleteness < 60) {
            tier = 'incomplete';
        }
        else if (data.avgScore >= 85) {
            tier = 'S';
        }
        else if (data.avgScore >= 70) {
            tier = 'A';
        }
        else if (data.avgScore >= 55) {
            tier = 'B';
        }
        else {
            tier = 'C';
        }
        const pool = FlowVM.pool(tier);
        let seed = '';
        for (let i = 0; i < data.attemptIds.length; i++) {
            seed = seed + data.attemptIds[i] + '|';
        }
        seed = seed + ':' + tier + ':' + data.total.toString();
        const index = FlowVM.hash(seed) % pool.length;
        const variant = pool[index];
        const result = new FlowEncouragement();
        result.tier = tier;
        result.zh = variant.zh;
        result.en = variant.en;
        result.praise = this.bestWordPraise(data);
        return result;
    }
    /** 具体化一句：挑本次读得最好的词（≥85），取不到就不编。 */
    private bestWordPraise(data: FlowSummaryData): string {
        let bestWord = '';
        let bestScore = -1;
        for (let i = 0; i < data.items.length; i++) {
            const item = data.items[i];
            if (item.status !== FlowStatus.DONE) {
                continue;
            }
            for (let j = 0; j < item.wordTexts.length; j++) {
                const score = item.wordScores[j];
                if (score >= 85 && score > bestScore) {
                    bestScore = score;
                    bestWord = item.wordTexts[j];
                }
            }
        }
        if (bestWord.length === 0) {
            return '';
        }
        return '「' + bestWord + '」这个词读得特别清楚。';
    }
    /** FNV 风格确定性哈希（同一批结果永远选到同一条文案）。 */
    private static hash(input: string): number {
        let h = 0;
        for (let i = 0; i < input.length; i++) {
            h = (h * 31 + input.charCodeAt(i)) % 1000000007;
        }
        return h;
    }
    private static pool(tier: string): FlowEnc[] {
        if (tier === 'S') {
            return FlowVM.POOL_S;
        }
        if (tier === 'A') {
            return FlowVM.POOL_A;
        }
        if (tier === 'B') {
            return FlowVM.POOL_B;
        }
        if (tier === 'C') {
            return FlowVM.POOL_C;
        }
        if (tier === 'incomplete') {
            return FlowVM.POOL_INCOMPLETE;
        }
        return FlowVM.POOL_NO_SPEECH;
    }
    // 6 档 × 5 条中英双语文案：成长型措辞，绝不含否定词
    private static readonly POOL_S: FlowEnc[] = [
        new FlowEnc('太棒了！这次特别清楚！', 'Great job! That was so clear!'),
        new FlowEnc('哇，这次读得特别棒！', 'Wow, you did great!'),
        new FlowEnc('进步好大，继续保持！', 'Big progress! Keep going!'),
        new FlowEnc('这次的声音又清楚又好听！', 'That sounded clear and lovely!'),
        new FlowEnc('太厉害了，一口气读下来了！', 'Amazing! You read the whole thing!')
    ];
    private static readonly POOL_A: FlowEnc[] = [
        new FlowEnc('读得很好！继续这样就好。', 'Nice reading! Keep it up.'),
        new FlowEnc('很稳！保持这个节奏。', 'Very steady! Keep this rhythm.'),
        new FlowEnc('这次比上次更顺了。', 'Smoother than last time!'),
        new FlowEnc('很好，句子都读完整了。', 'Good job finishing every sentence.'),
        new FlowEnc('听起来很棒，再来一次会更好。', 'Sounds great! One more time will be even better.')
    ];
    private static readonly POOL_B: FlowEnc[] = [
        new FlowEnc('很认真！再读一遍会更顺。', 'Good try! Reading again will be smoother.'),
        new FlowEnc('看到你在努力，继续保持。', 'I can see your effort. Keep going!'),
        new FlowEnc('大部分都读到了，真棒！', 'You got most of it. Nice work!'),
        new FlowEnc('慢一点会更清楚，我们再试试。', 'Slow down a little and try again.'),
        new FlowEnc('你的声音很响亮，很好！', 'Your voice was nice and loud!')
    ];
    private static readonly POOL_C: FlowEnc[] = [
        new FlowEnc('谢谢你勇敢地读出来。我们慢慢来。', 'Thank you for reading! Let us take our time.'),
        new FlowEnc('敢开口就很了不起，我们一起再试试。', 'Speaking up is brave. Let us try together.'),
        new FlowEnc('今天已经在进步的路上了。', 'You are on the way. Keep going!'),
        new FlowEnc('我听到你的声音了，我们再练一次。', 'I heard your voice! Let us practice again.'),
        new FlowEnc('一点点来，你已经在变好了。', 'Little by little, you are getting better.')
    ];
    private static readonly POOL_NO_SPEECH: FlowEnc[] = [
        new FlowEnc('这次好像没听到你的声音，我们再来一次好吗？', 'Let us try again! I will listen.'),
        new FlowEnc('麦克风可能没收到，靠近一点再说一次吧。', 'Come a little closer and say it again.'),
        new FlowEnc('没关系，我们深呼吸一下再来一次。', 'No worries. Take a breath and try again.'),
        new FlowEnc('准备好了吗？我在这儿听着呢。', 'Ready? I am listening.'),
        new FlowEnc('我们慢慢来，先大声说一句试试。', 'Take your time. Say one sentence loudly.')
    ];
    private static readonly POOL_INCOMPLETE: FlowEnc[] = [
        new FlowEnc('有几句话没读完，没关系，我们试试一口气读完。', 'You can do it! Let us finish the whole page.'),
        new FlowEnc('读到一半也很好，下次把它读完吧。', 'Halfway is good too. Let us finish next time.'),
        new FlowEnc('慢慢来，把每一句都读完就更棒了。', 'Take your time and finish each sentence.'),
        new FlowEnc('我们已经读了一大半了，再读一点点就好。', 'We are almost done. Just a little more.'),
        new FlowEnc('一句一句来，读完最后一句我们就成功啦。', 'One sentence at a time. Let us finish the last one!')
    ];
    // ================================================================== 错误 / 刷新
    private setUiError(err: Error): void {
        const ui = SessionStore.toUiError(err, this.isChild);
        this.error = ui;
        this.hasError = true;
    }
    private setErrorText(message: string): void {
        this.error = new UiError('', message, '', false, '');
        this.hasError = true;
    }
    clearError(): void {
        this.hasError = false;
        this.error = new UiError('', '', '', false, '');
    }
    clearSetupError(): void {
        this.setupError = '';
    }
    private uiMessage(err: Error): string {
        return SessionStore.toUiError(err, this.isChild).message;
    }
    private notifyItems(): void {
        const copy: FlowItem[] = [];
        for (let i = 0; i < this.items.length; i++) {
            copy.push(this.items[i]);
        }
        this.items = copy;
    }
    private checkOcrCapability(): void {
        PracticeService.health().then((health) => {
            const voice = health.voice;
            if (voice === undefined) {
                return;
            }
            const caps = voice.capabilities;
            if (caps !== undefined && caps.ocr !== undefined) {
                this.ocrEnabled = caps.ocr;
            }
        }).catch(() => {
            // 健康检查失败不阻塞入口；真正 OCR 时再报可读错误
        });
    }
}
/**
 * 进程内连读运行态（FlowPage / FlowSummaryPage 共享）。
 * 导航层不支持传参（NavigationService.push(name)），汇总页通过这里读同一份状态。
 */
export class FlowRunStore {
    private static run: FlowVM | null = null;
    static ensure(): FlowVM {
        const current = FlowRunStore.run;
        if (current !== null) {
            return current;
        }
        const created = new FlowVM();
        FlowRunStore.run = created;
        return created;
    }
    static current(): FlowVM | null {
        return FlowRunStore.run;
    }
    static clear(): void {
        FlowRunStore.run = null;
    }
}

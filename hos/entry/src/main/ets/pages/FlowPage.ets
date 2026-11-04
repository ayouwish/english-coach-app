import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { EmptyState } from '../components/EmptyState';
import { LoadingBlock } from '../components/LoadingBlock';
import { Chip } from '../components/EcBlocks';
import { WordText } from '../components/WordText';
import { ScoreRing, SubScoreBar } from '../components/ScoreViews';
import { EcFont, EcRadius, EcScore, EcShadow, EcSpace } from '../design/DesignTokens';
import { MaterialDto, SentenceDto } from '../core/net/Dtos';
import { NavigationService } from '../core/router/NavigationService';
import { StoryReadRequest } from '../core/session/StoryReadRequest';
import { Routes } from '../core/router/Routes';
import { SessionState } from '../core/session/SessionStore';
import { FlowItem, FlowPhase, FlowRunStore, FlowStatus, FlowVM } from '../viewmodel/FlowVM';

/**
 * 连读模式（Tab 根页）：setup → running →（全部 settled 自动 push 汇总页）。
 *
 * 与 Web 的差异（手机简化）：
 * - setup 的「我的书页」只保留最近 50 篇 + 打开（重命名/编辑/删除收到二级页，本期不做）；
 * - 拍照入口用系统 PhotoViewPicker（相册），不申请 CAMERA，也不做多选；
 * - running 的逐条详情直接内联展开（手机屏小，不用底部 Sheet）。
 */
@Component
export struct FlowPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @StorageLink('story_read_ver') @Watch('onStoryReadRequest') storyReadVer: number = 0;
  @State vm: FlowVM = FlowRunStore.ensure();
  private started: boolean = false;
  private levels: string[] = ['A1', 'A2', 'B1', 'B2', 'ALL'];
  private counts: number[] = [5, 10, 15];
  private sourceLabels: string[] = ['📚 从语料选', '📖 我的书页', '✍️ 自己输入'];

  aboutToAppear(): void {
    this.vm.attach(this.session.isChild, this.session.cefrLevel, this.session.userId);
    this.vm.onFinished = () => {
      this.openSummary();
    };
    // 故事页点「朗读这个故事」后跳过来：优先消费请求，不要被 init 重置回 setup
    if (StoryReadRequest.pending()) {
      this.started = true;
      this.consumeStoryRead();
      return;
    }
    // 页面重建（例如从故事详情 clear 掉导航栈）时，连读正在跑：保持 running 而不是重置
    if (this.vm.phase === FlowPhase.RUNNING && this.vm.items.length > 0) {
      this.started = true;
      this.vm.resume();
      return;
    }
    if (!this.started) {
      this.started = true;
      void this.vm.init();
    } else {
      this.vm.resume();
    }
  }

  private consumeStoryRead(): void {
    if (!StoryReadRequest.pending()) {
      return;
    }
    const title = StoryReadRequest.title;
    const materialId = StoryReadRequest.materialId;
    const texts = StoryReadRequest.sentences.slice(0);
    StoryReadRequest.clear();
    this.vm.startStoryRead(title, materialId, texts);
  }

  onStoryReadRequest(): void {
    this.consumeStoryRead();
  }

  aboutToDisappear(): void {
    // 规格 §5.4：页面不可见必须停轮询（同时丢弃录音、停播放）
    this.vm.dispose();
  }

  private openSummary(): void {
    NavigationService.push(Routes.FLOW_SUMMARY);
  }

  // ================================================================== 通用样式

  private cardBg(): ResourceColor {
    return $r('app.color.ec_surface');
  }

  private muted(): ResourceColor {
    return $r('app.color.ec_muted');
  }

  private ink(): ResourceColor {
    return $r('app.color.ec_ink');
  }

  // ================================================================== setup 页

  @Builder
  setupHeader() {
    Column({ space: EcSpace.x1 }) {
      Text('🔗 ' + (this.session.isChild ? '一口气读好多句' : '连读模式'))
        .fontSize(this.session.isChild ? EcFont.childH1 : EcFont.h2)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.ink())
        .width('100%')
      Text(this.session.isChild
        ? '读完一句就自动跳到下一句，不用等评分。读完后分数会自己出现在下面的列表里 🙂'
        : '逐句连读：录完一句立刻进入下一句，评分在后台排队，结果陆续显示（每句仍有完整反馈）。')
        .fontSize(EcFont.caption)
        .fontColor(this.muted())
        .width('100%')
    }
    .width('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4, bottom: EcSpace.x2 })
  }

  // ---------------------------------------------------------------- 拍照识别

  @Builder
  ocrCard() {
    Column({ space: EcSpace.x2 }) {
      Text('📷 ' + (this.session.isChild ? '拍张照识别书上的句子' : '拍照识别书页'))
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.ink())
        .width('100%')

      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: this.vm.ocrBusy ? '识别中…'
            : (this.vm.ocrInfoText.length > 0 ? '🖼️ 再选一张' : '🖼️ 从相册选'),
          kind: EcButtonKind.TONAL,
          btnWidth: '46%',
          loading: this.vm.ocrBusy,
          disabled: this.vm.ocrBusy || !this.vm.ocrEnabled,
          onTap: () => {
            void this.vm.pickPhotoAndOcr();
          }
        })
        if (this.vm.ocrBusy) {
          Text(this.vm.ocrStatusText)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .layoutWeight(1)
        } else if (!this.vm.ocrEnabled) {
          Text('当前部署没有开启拍照识别，先用「自己输入」吧')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_warn_text'))
            .layoutWeight(1)
            .maxLines(2)
        } else {
          Text('照片只用于识别，不保存原图')
            .fontSize(EcFont.micro)
            .fontColor(this.muted())
            .layoutWeight(1)
            .maxLines(2)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.ocrInfoText.length > 0) {
        Text(this.vm.ocrInfoText)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      }
      if (this.vm.ocrError.length > 0) {
        ErrorBanner({
          title: '识别没有成功',
          message: this.vm.ocrError,
          actionLabel: '再试一次',
          onAction: () => {
            void this.vm.pickPhotoAndOcr();
          }
        })
      }
      if (this.vm.ocrInfoText.length > 0 && this.vm.customInput.trim().length > 0) {
        this.savePanel()
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor(this.cardBg())
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  savePanel() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.vm.editingMaterialId.length > 0
          ? (this.session.isChild ? '✏️ 改一改这篇' : '✏️ 编辑书页（保存会覆盖原文）')
          : (this.session.isChild ? '💾 存起来以后还能读' : '💾 保存为「我的书页」'))
          .fontSize(EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.ink())
          .layoutWeight(1)
        if (this.vm.editingMaterialId.length > 0) {
          Text('取消编辑')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .onClick(() => {
              this.vm.cancelEdit();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      TextInput({ text: this.vm.saveTitle, placeholder: '书页标题（默认取第一行）' })
        .height(44)
        .fontSize(EcFont.caption)
        .fontColor(this.ink())
        .placeholderColor(this.muted())
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.saveTitle = value;
        })
      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: this.vm.savedPageId.length > 0 ? '已保存 ✅'
            : (this.vm.saveBusy ? '保存中…'
              : (this.vm.editingMaterialId.length > 0 ? '💾 保存修改' : '💾 保存为书页')),
          kind: EcButtonKind.TONAL,
          btnWidth: '48%',
          loading: this.vm.saveBusy,
          disabled: this.vm.savedPageId.length > 0,
          onTap: () => {
            void this.vm.saveAsPage();
          }
        })
        EcButton({
          label: this.vm.savedPageId.length > 0 ? '立即开始读 →' : '保存后直接连读 →',
          kind: EcButtonKind.PRIMARY,
          btnWidth: '48%',
          loading: this.vm.saveBusy,
          onTap: () => {
            void this.vm.saveAndRead();
          }
        })
      }
      .width('100%')
      if (this.vm.saveError.length > 0) {
        ErrorBanner({
          message: this.vm.saveError,
          actionLabel: '重试',
          onAction: () => {
            void this.vm.saveAsPage();
          }
        })
      }
    }
    .width('100%')
    .padding(EcSpace.x3)
    .backgroundColor($r('app.color.ec_surface_alt'))
    .borderRadius(EcRadius.md)
    .alignItems(HorizontalAlign.Start)
  }

  // ---------------------------------------------------------------- 来源 tab

  @Builder
  sourceTabs() {
    Row({ space: EcSpace.x2 }) {
      ForEach(this.sourceLabels, (label: string, index: number) => {
        Text(label)
          .fontSize(EcFont.micro)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.vm.sourceTab === index ? Color.White : this.muted())
          .backgroundColor(this.vm.sourceTab === index
            ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x2, bottom: EcSpace.x2 })
          .borderRadius(EcRadius.pill)
          .accessibilityText(label)
          .onClick(() => {
            this.onSourceTab(index);
          })
      }, (label: string, index: number) => label + index.toString())
    }
    .width('100%')
  }

  private onSourceTab(index: number): void {
    if (this.vm.sourceTab === index) {
      return;
    }
    this.vm.sourceTab = index;
    this.vm.clearSetupError();
    if (index === 1) {
      void this.vm.loadMaterials();
    }
  }

  // ---------------------------------------------------------------- 语料

  @Builder
  corpusPanel() {
    Column({ space: EcSpace.x3 }) {
      Row({ space: EcSpace.x1 }) {
        ForEach(this.levels, (item: string) => {
          Text(item === 'ALL' ? '全部' : item)
            .fontSize(EcFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.vm.level === item ? Color.White : this.muted())
            .backgroundColor(this.vm.level === item
              ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
            .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
            .borderRadius(EcRadius.pill)
            .accessibilityText('等级 ' + item)
            .onClick(() => {
              this.vm.setLevel(item);
            })
        }, (item: string) => item)
      }
      .width('100%')

      if (this.vm.corpusLoading) {
        LoadingBlock({ text: '正在取句子…' })
      } else if (this.vm.corpusError.length > 0) {
        ErrorBanner({
          message: this.vm.corpusError,
          actionLabel: '重试',
          onAction: () => {
            void this.vm.loadCorpus();
          }
        })
      } else {
        Row({ space: EcSpace.x2 }) {
          Text('共 ' + this.vm.levelPoolSize().toString() + ' 句')
            .fontSize(EcFont.caption)
            .fontColor(this.muted())
          Blank()
          Text(this.vm.randomMode ? '🎲 随机 ✓' : '🎲 随机')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .onClick(() => {
              this.vm.toggleRandom();
            })
          if (this.vm.randomMode) {
            Text('🔀 换一批')
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_primary'))
              .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
              .accessibilityText('换一批随机句子')
              .onClick(() => {
                this.vm.drawRandom();
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (!this.vm.randomMode) {
          Row({ space: EcSpace.x2 }) {
            Text('从第')
              .fontSize(EcFont.caption)
              .fontColor(this.muted())
            TextInput({ text: this.vm.startIndex.toString() })
              .width(56)
              .height(34)
              .type(InputType.Number)
              .fontSize(EcFont.caption)
              .fontColor(this.ink())
              .backgroundColor($r('app.color.ec_surface_alt'))
              .borderRadius(EcRadius.sm)
              .onChange((value: string) => {
                const parsed = parseInt(value, 10);
                if (!isNaN(parsed)) {
                  this.vm.setStartIndex(parsed);
                }
              })
            Text('句开始')
              .fontSize(EcFont.caption)
              .fontColor(this.muted())
            Blank()
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }

        Row({ space: EcSpace.x2 }) {
          Text('读')
            .fontSize(EcFont.caption)
            .fontColor(this.muted())
          ForEach(this.counts, (n: number) => {
            Text(n.toString() + ' 句')
              .fontSize(EcFont.caption)
              .fontColor(this.vm.count === n ? Color.White : this.muted())
              .backgroundColor(this.vm.count === n
                ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
              .borderRadius(EcRadius.sm)
              .onClick(() => {
                this.vm.setCount(n);
              })
          }, (n: number) => n.toString())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        this.previewList()

        EcButton({
          label: '🎤 开始连读（' + this.vm.preview.length.toString() + ' 句）',
          kind: EcButtonKind.PRIMARY,
          big: this.session.isChild,
          disabled: this.vm.preview.length === 0,
          onTap: () => {
            this.vm.startCorpus();
          }
        })
      }
    }
    .width('100%')
  }

  @Builder
  previewList() {
    Column({ space: EcSpace.x1 }) {
      ForEach(this.vm.preview, (item: SentenceDto, index: number) => {
        Text((index + 1).toString() + '. ' + item.text)
          .fontSize(EcFont.caption)
          .fontColor(this.ink())
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }, (item: SentenceDto) => item.id)
      if (this.vm.preview.length === 0) {
        Text('这个位置没有句子')
          .fontSize(EcFont.caption)
          .fontColor(this.muted())
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x3)
    .backgroundColor($r('app.color.ec_surface_alt'))
    .borderRadius(EcRadius.md)
    .alignItems(HorizontalAlign.Start)
  }

  // ---------------------------------------------------------------- 我的书页

  @Builder
  materialsPanel() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('📖 我的书页（家里人的都在这里）')
          .fontSize(EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.ink())
          .layoutWeight(1)
        Text('刷新')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .onClick(() => {
            void this.vm.loadMaterials();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.vm.materialsLoading) {
        LoadingBlock({ text: '正在加载书页…' })
      } else if (this.vm.materialsError.length > 0) {
        ErrorBanner({
          message: this.vm.materialsError,
          actionLabel: '重试',
          onAction: () => {
            void this.vm.loadMaterials();
          }
        })
      } else if (this.vm.materials.length === 0) {
        Text(this.session.isChild
          ? '还没有保存的书页。可以让爸爸妈妈先拍一页存起来。'
          : '还没有保存的书页。可以先拍照识别一页，识别后点「保存为书页」。')
          .fontSize(EcFont.caption)
          .fontColor(this.muted())
          .width('100%')
      } else {
        ForEach(this.vm.materials, (material: MaterialDto) => {
          Row({ space: EcSpace.x2 }) {
            Column({ space: 2 }) {
              Text(material.title === undefined ? '未命名书页' : material.title)
                .fontSize(EcFont.caption)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.ink())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(this.materialMeta(material))
                .fontSize(EcFont.micro)
                .fontColor(this.muted())
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            if (this.vm.materialBusyId === material.id || this.vm.materialEditBusyId === material.id) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.ec_primary'))
            } else {
              Row({ space: EcSpace.x1 }) {
                Text(this.vm.editingMaterialId === material.id ? '编辑中' : '编辑')
                  .fontSize(EcFont.caption)
                  .fontColor(this.vm.editingMaterialId === material.id
                    ? $r('app.color.ec_good_text') : $r('app.color.ec_muted'))
                  .padding({ left: EcSpace.x1, top: EcSpace.x1, bottom: EcSpace.x1 })
                  .onClick(() => {
                    void this.vm.beginEdit(material.id);
                  })
                Text('删除')
                  .fontSize(EcFont.caption)
                  .fontColor($r('app.color.ec_bad_text'))
                  .padding({ left: EcSpace.x1, right: EcSpace.x1, top: EcSpace.x1, bottom: EcSpace.x1 })
                  .onClick(() => {
                    this.getUIContext().showAlertDialog({
                      title: '删除这一页？',
                      message: '删除后全家都看不到这篇书页了，无法恢复。',
                      primaryButton: {
                        value: '取消',
                        action: () => {
                        }
                      },
                      secondaryButton: {
                        value: '删除',
                        fontColor: $r('app.color.ec_bad_text'),
                        action: () => {
                          void this.vm.removeMaterial(material.id);
                        }
                      }
                    });
                  })
                Text('打开 →')
                  .fontSize(EcFont.caption)
                  .fontColor($r('app.color.ec_primary'))
                  .padding({ left: EcSpace.x1, top: EcSpace.x1, bottom: EcSpace.x1 })
                  .onClick(() => {
                    void this.vm.openMaterial(material.id);
                  })
              }
              .alignItems(VerticalAlign.Center)
            }
          }
          .width('100%')
          .padding(EcSpace.x3)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
          .alignItems(VerticalAlign.Center)
        }, (material: MaterialDto) => material.id)
      }
    }
    .width('100%')
  }

  private materialMeta(material: MaterialDto): string {
    const count = material.sentence_count === undefined ? 0 : material.sentence_count;
    const by = material.created_by_name === undefined ? '' : material.created_by_name;
    const image = material.has_image === true ? '有图片' : '仅文字';
    let text = count.toString() + ' 句 · ' + image;
    if (by.length > 0) {
      text = text + ' · ' + by;
    }
    return text;
  }

  // ---------------------------------------------------------------- 自己输入

  @Builder
  customPanel() {
    Column({ space: EcSpace.x2 }) {
      TextArea({ text: this.vm.customInput, placeholder: '把想读的英文段落贴进来（会按 . ! ? 。！？ 自动切句）' })
        .height(120)
        .fontSize(EcFont.body)
        .fontColor(this.ink())
        .placeholderColor(this.muted())
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.setCustomInput(value);
        })
      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: '✂️ 切句',
          kind: EcButtonKind.TONAL,
          btnWidth: '30%',
          onTap: () => {
            this.vm.splitCustom();
          }
        })
        Text('切出 ' + this.vm.customSentences.length.toString() + ' 句（可逐句修改后再开始）')
          .fontSize(EcFont.micro)
          .fontColor(this.muted())
          .layoutWeight(1)
          .maxLines(2)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      ForEach(this.vm.customSentences, (text: string, index: number) => {
        Row({ space: EcSpace.x2 }) {
          Text((index + 1).toString())
            .fontSize(EcFont.micro)
            .fontColor(this.muted())
            .width(18)
          TextInput({ text: text })
            .layoutWeight(1)
            .height(40)
            .fontSize(EcFont.caption)
            .fontColor(this.ink())
            .backgroundColor($r('app.color.ec_surface_alt'))
            .borderRadius(EcRadius.sm)
            .onChange((value: string) => {
              this.vm.updateCustomSentence(index, value);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (text: string, index: number) => 'custom' + index.toString() + '_' + text)

      if (this.vm.runMaterialId.length > 0) {
        Text('这一批来自「我的书页」，提交时会带上书页 id')
          .fontSize(EcFont.micro)
          .fontColor(this.muted())
          .width('100%')
      }

      // 编辑书页时（从「我的书页」点编辑）在这里显示保存面板；普通手输不显示（与 Web 一致）
      if (this.vm.editingMaterialId.length > 0) {
        this.savePanel()
      }

      EcButton({
        label: '🎤 开始连读（' + this.vm.customSentences.length.toString() + ' 句）',
        kind: EcButtonKind.PRIMARY,
        big: this.session.isChild,
        disabled: this.vm.customSentences.length === 0,
        onTap: () => {
          this.vm.startCustom();
        }
      })
    }
    .width('100%')
  }

  // ---------------------------------------------------------------- setup 主视图

  @Builder
  setupView() {
    Scroll() {
      Column({ space: EcSpace.x3 }) {
        this.setupHeader()
        this.ocrCard()

        Column({ space: EcSpace.x3 }) {
          this.sourceTabs()
          if (this.vm.sourceTab === 0) {
            this.corpusPanel()
          } else if (this.vm.sourceTab === 1) {
            this.materialsPanel()
          } else {
            this.customPanel()
          }
          if (this.vm.setupError.length > 0) {
            ErrorBanner({
              title: '',
              message: this.vm.setupError,
              actionLabel: '',
              onAction: () => {
              }
            })
          }
        }
        .width('100%')
        .padding(EcSpace.x4)
        .backgroundColor(this.cardBg())
        .borderRadius(EcRadius.lg)
        .shadow(EcShadow.card())
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x6 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  // ================================================================== running 页

  /** 退出本轮连读、回到选句/输入界面（已读记录保留在服务端）。 */
  private exitRun(): void {
    this.vm.backToSetup();
    // 停止可能还在跑的录音/轮询（backToSetup 只改状态）
    this.vm.dispose();
  }

  private confirmExitRun(): void {
    let hasProgress = this.vm.currentIndex > 0;
    for (let i = 0; i < this.vm.items.length; i++) {
      if (this.vm.items[i].status !== FlowStatus.UNSENT) {
        hasProgress = true;
        break;
      }
    }
    if (!hasProgress) {
      this.exitRun();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '退出这次连读？',
      message: '已经读过的句子会保留在记录里，回去可以重新选句或接着读。',
      primaryButton: {
        value: '继续练',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: $r('app.color.ec_bad_text'),
        action: () => {
          this.exitRun();
        }
      }
    });
  }

  @Builder
  runningHeader() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('‹ 重新选句')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText('退出连读，重新选句')
          .onClick(() => {
            this.confirmExitRun();
          })
        Text(this.vm.runTitle.length > 0
          ? ('📖 ' + this.vm.runTitle)
          : ('🔗 ' + (this.session.isChild ? '一句一句读' : '连读模式')))
          .fontSize(this.vm.runTitle.length > 0 ? EcFont.body : EcFont.h3)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.ink())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('第 ' + Math.min(this.vm.currentIndex + 1, this.vm.items.length).toString()
          + ' / ' + this.vm.items.length.toString() + ' 句')
          .fontSize(EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_primary'))
          .backgroundColor($r('app.color.ec_primary_soft'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x1, bottom: EcSpace.x1 })
          .borderRadius(EcRadius.pill)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Progress({ value: this.vm.progressPercent(), total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(8)
        .color($r('app.color.ec_primary'))

      Row({ space: EcSpace.x2 }) {
        Text(this.vm.autoNext ? '☑' : '☐')
          .fontSize(EcFont.body)
          .fontColor($r('app.color.ec_primary'))
        Text(this.session.isChild ? '读完自动跳到下一句' : '录完后自动进入下一句（400ms 缓冲）')
          .fontSize(EcFont.micro)
          .fontColor(this.muted())
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.vm.autoNext = !this.vm.autoNext;
      })

      if (this.vm.limitMessage.length > 0) {
        Text('🌙 ' + this.vm.limitMessage)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .backgroundColor($r('app.color.ec_warn_bg'))
          .padding(EcSpace.x3)
          .borderRadius(EcRadius.md)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4, bottom: EcSpace.x2 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  currentCard() {
    Column({ space: EcSpace.x3 }) {
      WordText({
        text: this.vm.currentItem() === null ? '' : (this.vm.currentItem() as FlowItem).text,
        fontSizeVp: this.session.isChild ? 26 : EcFont.sentence,
        lineHeightVp: this.session.isChild ? 38 : 34,
        inkColor: this.ink()
      })

      if (this.vm.recording || this.vm.preparing || this.vm.submitting) {
        Row({ space: EcSpace.x2 }) {
          if (this.vm.submitting) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color($r('app.color.ec_primary'))
          }
          Text(this.vm.submitting ? '提交中…'
            : (this.vm.recording
              ? '正在听你说…读完点「说完啦」'
              : '正在打开麦克风…'))
            .fontSize(EcFont.caption)
            .fontColor(this.vm.recording ? $r('app.color.ec_warn_text') : $r('app.color.ec_primary'))
        }
        .width('100%')
      }

      if (this.vm.currentItem() !== null
        && (this.vm.currentItem() as FlowItem).status === FlowStatus.UNSENT) {
        if (this.vm.recording) {
          Row({ space: EcSpace.x2 }) {
            EcButton({
              label: '⏹ 说完啦 ' + Math.floor(this.vm.elapsedMs / 1000).toString() + 's',
              kind: EcButtonKind.DANGER,
              big: this.session.isChild,
              btnWidth: '62%',
              disabled: this.vm.submitting,
              onTap: () => {
                void this.vm.stopAndSubmit();
              }
            })
            EcButton({
              label: '✖️ 不要了',
              kind: EcButtonKind.GHOST,
              btnWidth: '34%',
              disabled: this.vm.submitting,
              onTap: () => {
                void this.vm.cancelRecording();
              }
            })
          }
          .width('100%')
        } else {
          EcButton({
            label: this.vm.preparing ? '麦克风准备中…' : '🎤 开始录音',
            kind: EcButtonKind.PRIMARY,
            big: this.session.isChild,
            loading: this.vm.preparing,
            disabled: this.vm.submitting,
            onTap: () => {
              void this.vm.startRecording();
            }
          })
        }
      }

      if (this.vm.currentStatusLine().length > 0) {
        Text(this.vm.currentStatusLine())
          .fontSize(EcFont.caption)
          .fontColor(this.muted())
          .width('100%')
      }

      if (this.vm.hasError) {
        ErrorBanner({
          title: this.vm.error.title,
          message: this.vm.error.message,
          actionLabel: '',
          onAction: () => {
            this.vm.clearError();
          }
        })
      }

      // 已提交、但还没自动跳（autoNext 关闭 / 失败后）时给一个明确的「下一句」
      if (this.vm.currentItem() !== null
        && (this.vm.currentItem() as FlowItem).status !== FlowStatus.UNSENT
        && this.vm.hasNextUnsent()) {
        EcButton({
          label: '下一句 →',
          kind: EcButtonKind.TONAL,
          onTap: () => {
            this.vm.nextSentence();
          }
        })
      }

      if (this.vm.currentItem() !== null
        && (this.vm.currentItem() as FlowItem).status === FlowStatus.FAILED) {
        EcButton({
          label: '重录这句',
          kind: EcButtonKind.TONAL,
          onTap: () => {
            this.vm.retryItem(this.vm.currentIndex);
          }
        })
      }
    }
    .width('100%')
    .padding(EcSpace.x5)
    .backgroundColor(this.cardBg())
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
    .margin({ left: EcSpace.x4, right: EcSpace.x4 })
  }

  @Builder
  waitingCard() {
    Column({ space: EcSpace.x2 }) {
      Text('全部读完啦，正在后台评分…')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.ink())
        .width('100%')
      Text('已评分 ' + this.vm.doneCount().toString() + ' 句 · 待评分 '
        + this.vm.pendingCount().toString() + ' 句 · 失败 '
        + this.vm.failedCount().toString() + ' 句')
        .fontSize(EcFont.caption)
        .fontColor(this.muted())
        .width('100%')
      Text('评分完成后会自动跳到汇总页，不用一直等在这里')
        .fontSize(EcFont.micro)
        .fontColor(this.muted())
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x5)
    .backgroundColor(this.cardBg())
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
    .margin({ left: EcSpace.x4, right: EcSpace.x4 })
  }

  @Builder
  flowRow(item: FlowItem) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text((item.index + 1).toString() + '. ' + item.text)
          .fontSize(this.session.isChild ? EcFont.body : EcFont.caption)
          .fontColor(this.ink())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Chip({ text: this.vm.statusBadge(item), tone: this.vm.statusTone(item) })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (item.status === FlowStatus.FAILED) {
        Row({ space: EcSpace.x2 }) {
          Text(item.error.length > 0 ? item.error : '评分没有成功')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_bad_text'))
            .maxLines(2)
            .layoutWeight(1)
          Text('重录这句')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_primary'))
            .onClick(() => {
              this.vm.retryItem(item.index);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      if (this.vm.expandedIndex === item.index && item.hasResult) {
        this.detailBlock(item)
      }
    }
    .width('100%')
    .padding(EcSpace.x3)
    .backgroundColor(this.cardBg())
    .borderRadius(EcRadius.md)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (item.hasResult || item.status === FlowStatus.FAILED) {
        this.vm.toggleExpanded(item.index);
      }
    })
  }

  @Builder
  detailBlock(item: FlowItem) {
    Column({ space: EcSpace.x2 }) {
      if (item.noSpeech) {
        Text('这次好像没有听到声音，可以点「重录这句」再读一次')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
      } else if (this.session.isChild) {
        Text(EcScore.encouragement(item.scorePron, true))
          .fontSize(EcFont.body)
          .fontColor(this.ink())
          .width('100%')
      } else {
        Row({ space: EcSpace.x3 }) {
          ScoreRing({
            score: item.scorePron < 0 ? 0 : item.scorePron,
            label: '这一句',
            isChild: false,
            ringSize: 72
          })
          Column({ space: 2 }) {
            SubScoreBar({ label: '准确', score: item.scoreAccuracy, isChild: false })
            SubScoreBar({ label: '流利', score: item.scoreFluency, isChild: false })
            SubScoreBar({ label: '完整', score: item.scoreCompleteness, isChild: false })
            SubScoreBar({ label: '语调', score: item.scoreProsody, isChild: false })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      if (item.feedbackSummary.length > 0) {
        Text(item.feedbackSummary)
          .fontSize(EcFont.caption)
          .fontColor(this.ink())
          .width('100%')
      }
      if (item.feedbackPraise.length > 0) {
        Text('👍 ' + item.feedbackPraise)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      }
      if (item.pointTitles.length > 0) {
        ForEach(item.pointTitles, (title: string, index: number) => {
          Text('· ' + title)
            .fontSize(EcFont.micro)
            .fontColor(this.ink())
            .width('100%')
        }, (title: string, index: number) => item.index.toString() + 'p' + index.toString())
      }
      if (item.wordTexts.length > 0 && !this.session.isChild) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(item.wordTexts, (word: string, index: number) => {
            Text(word + ' ' + (item.wordScores[index] < 0
              ? '—' : Math.round(item.wordScores[index]).toString()))
              .fontSize(EcFont.micro)
              .fontColor(EcScore.colorByMode(item.wordScores[index] < 0 ? null : item.wordScores[index], false))
              .backgroundColor($r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 2, bottom: 2 })
              .borderRadius(EcRadius.sm)
              .margin(2)
          }, (word: string, index: number) => item.index.toString() + 'w' + index.toString())
        }
        .width('100%')
      }
      if (item.issueTexts.length > 0) {
        ForEach(item.issueTexts, (text: string, index: number) => {
          Text('· ' + text)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_warn_text'))
            .width('100%')
        }, (text: string, index: number) => item.index.toString() + 'i' + index.toString())
      }
      Text('连读详情不含音素明细与语调图')
        .fontSize(EcFont.micro)
        .fontColor(this.muted())
        .width('100%')
    }
    .width('100%')
    .padding({ top: EcSpace.x2 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  runningView() {
    Column({ space: EcSpace.x2 }) {
      this.runningHeader()
      if (this.vm.allSubmitted) {
        this.waitingCard()
      } else {
        this.currentCard()
      }
      Text('实时评分（点一行展开详情）')
        .fontSize(EcFont.caption)
        .fontColor(this.muted())
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x1 })
      List({ space: EcSpace.x2 }) {
        ForEach(this.vm.items, (item: FlowItem) => {
          ListItem() {
            this.flowRow(item)
          }
        }, (item: FlowItem) => 'flow' + item.index.toString() + '_' + item.status + '_'
          + Math.round(item.scorePron).toString() + '_'
          + (this.vm.expandedIndex === item.index ? 'e' : 'n'))
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: EcSpace.x4, right: EcSpace.x4, bottom: EcSpace.x3 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  // ================================================================== summary 残留页

  @Builder
  finishedView() {
    Scroll() {
      Column({ space: EcSpace.x4 }) {
        Column({ space: EcSpace.x2 }) {
          Text('🎉 ' + (this.session.isChild ? '读完啦！' : '连读完成'))
            .fontSize(EcFont.h2)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.ink())
            .width('100%')
          Text(this.summaryLine())
            .fontSize(EcFont.caption)
            .fontColor(this.muted())
            .width('100%')
          Text(this.vm.summary.encouragement.zh)
            .fontSize(EcFont.body)
            .fontColor(this.ink())
            .width('100%')
        }
        .width('100%')
        .padding(EcSpace.x5)
        .backgroundColor(this.cardBg())
        .borderRadius(EcRadius.lg)
        .shadow(EcShadow.card())
        .alignItems(HorizontalAlign.Start)

        EcButton({
          label: '📊 查看本轮汇总',
          kind: EcButtonKind.PRIMARY,
          onTap: () => {
            this.openSummary();
          }
        })
        Row({ space: EcSpace.x2 }) {
          EcButton({
            label: this.session.isChild ? '🔁 再读一遍～' : '🔁 再读一遍',
            kind: EcButtonKind.TONAL,
            btnWidth: '48%',
            onTap: () => {
              this.vm.reread();
            }
          })
          EcButton({
            label: '再读一段',
            kind: EcButtonKind.GHOST,
            btnWidth: '48%',
            onTap: () => {
              this.vm.backToSetup();
            }
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding(EcSpace.x4)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  private summaryLine(): string {
    const data = this.vm.summary;
    let text = '共 ' + data.total.toString() + ' 句 · 已评分 ' + data.doneCount.toString() + ' 句';
    if (data.failedCount > 0) {
      text = text + ' · 失败 ' + data.failedCount.toString() + ' 句';
    }
    if (data.avgScore >= 0 && EcScore.showNumber(data.avgScore, this.session.isChild)) {
      text = text + ' · 平均 ' + data.avgScore.toString() + ' 分';
    }
    if (data.round > 1) {
      text = text + ' · 第 ' + data.round.toString() + ' 遍';
    }
    return text;
  }

  // ================================================================== 页面

  build() {
    Column() {
      if (this.vm.phase === FlowPhase.SETUP) {
        this.setupView()
      } else if (this.vm.phase === FlowPhase.RUNNING) {
        if (this.vm.items.length === 0) {
          EmptyState({
            icon: '🔗',
            message: this.session.isChild ? '还没有选句子哦' : '还没有选连读的句子',
            actionLabel: '去选句子',
            onAction: () => {
              this.vm.backToSetup();
            }
          })
        } else {
          this.runningView()
        }
      } else {
        this.finishedView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
      // Tab 切换 / 被二级页覆盖：不可见时停轮询，回来立刻补拉一次（规格 §5.4）
      if (isVisible) {
        this.vm.resume();
      } else {
        this.vm.dispose();
      }
    })
  }
}

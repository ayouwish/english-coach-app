import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { SuggestionDto } from '../core/net/AccountDtos';
import { SessionState } from '../core/session/SessionStore';
import { ClipboardUtil } from '../core/util/ClipboardUtil';
import { SuggestionCategory, SuggestionsVM } from '../viewmodel/AccountVM';

/**
 * 建议箱（`/api/suggestions`）：
 * - 所有人（含儿童）都能提交，儿童 3 分类 + 大字号 + 「发送给爸爸妈妈」；
 * - 列表 / 标记已读已解决 / 导出 Markdown 仅家长（儿童 403，入口本来也不渲染）。
 * 导出在端上用「可选中复制的文本块」呈现（不做系统分享）。
 */
@Component
export struct SuggestionsPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: SuggestionsVM = new SuggestionsVM();
  private started: boolean = false;
  private filterKeys: string[] = ['', 'open', 'read', 'resolved'];
  private filterLabels: string[] = ['全部', '未读', '已读', '已解决'];

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    this.vm.init(this.session.isChild);
  }

  private filterFg(index: number): ResourceColor {
    return this.vm.filterStatus === this.filterKeys[index] ? Color.White : $r('app.color.ec_muted');
  }

  private filterBg(index: number): ResourceColor {
    return this.vm.filterStatus === this.filterKeys[index]
      ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt');
  }

  private categorySelected(key: string): boolean {
    return this.vm.category === key;
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Text(this.vm.title())
        .fontSize(this.vm.isChild ? EcFont.childH1 : EcFont.h2)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      Text(this.vm.subtitle())
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .lineHeight(22)
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  submitCard() {
    Column({ space: EcSpace.x2 }) {
      Text(this.vm.isChild ? '想说的话' : '具体内容')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.vm.categories(), (item: SuggestionCategory) => {
          Text(this.vm.isChild ? item.childLabel : item.adultLabel)
            .fontSize(this.vm.isChild ? EcFont.body : EcFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.categorySelected(item.key) ? Color.White : $r('app.color.ec_muted'))
            .backgroundColor(this.categorySelected(item.key)
              ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
            .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
            .borderRadius(EcRadius.pill)
            .margin({ right: EcSpace.x2, bottom: EcSpace.x2 })
            .accessibilityText(item.adultLabel)
            .onClick(() => {
              this.vm.category = item.key;
            })
        }, (item: SuggestionCategory) => 'cat-' + item.key)
      }
      .width('100%')

      TextArea({
        text: this.vm.content,
        placeholder: this.vm.isChild ? '比如：我想读恐龙的故事' : '例如：跟读页的示范音有时要等很久…'
      })
        .width('100%')
        .height(this.vm.isChild ? 140 : 112)
        .fontSize(this.vm.isChild ? EcFont.childBody : EcFont.body)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .maxLength(this.vm.maxLength)
        .onChange((value: string) => {
          this.vm.content = value;
        })

      Row({ space: EcSpace.x2 }) {
        Text(this.vm.content.length.toString() + ' / ' + this.vm.maxLength.toString())
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .layoutWeight(1)
      }
      .width('100%')

      if (this.vm.createError.length > 0) {
        Text(this.vm.createError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
      if (this.vm.createNotice.length > 0) {
        Text(this.vm.createNotice)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
          .padding(EcSpace.x2)
          .backgroundColor($r('app.color.ec_good_bg'))
          .borderRadius(EcRadius.sm)
      }

      EcButton({
        label: this.vm.submitting
          ? '提交中…'
          : (this.vm.isChild ? '✉️ 发送给爸爸妈妈' : '提交建议'),
        kind: EcButtonKind.PRIMARY,
        big: this.vm.isChild,
        loading: this.vm.submitting,
        onTap: () => {
          void this.vm.submit();
        }
      })
      Text('建议会记在家庭建议箱里，家长可以统一查看和导出。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  listHeader() {
    Column({ space: EcSpace.x2 }) {
      Text('共 ' + this.vm.total.toString() + ' 条')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      Row({ space: EcSpace.x2 }) {
        Chip({ text: '未读 ' + this.vm.countOpen.toString(), tone: 'warn' })
        Chip({ text: '已读 ' + this.vm.countRead.toString(), tone: 'primary' })
        Chip({ text: '已解决 ' + this.vm.countResolved.toString(), tone: 'good' })
      }
      .alignItems(VerticalAlign.Center)

      Row({ space: EcSpace.x2 }) {
        ForEach(this.filterLabels, (label: string, index: number) => {
          Text(label)
            .fontSize(EcFont.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.filterFg(index))
            .backgroundColor(this.filterBg(index))
            .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
            .borderRadius(EcRadius.pill)
            .accessibilityText(label)
            .onClick(() => {
              void this.vm.setFilter(this.filterKeys[index]);
            })
        }, (label: string, index: number) => 'filter-' + index.toString())
      }
      .width('100%')

      Row({ space: EcSpace.x2 }) {
        EcButton({
          label: this.vm.exporting ? '导出中…' : '📋 导出 Markdown',
          kind: EcButtonKind.TONAL,
          loading: this.vm.exporting,
          btnWidth: '60%',
          onTap: () => {
            void this.vm.exportMarkdown();
          }
        })
        Text('刷新')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .onClick(() => {
            void this.vm.loadList();
          })
      }
      .width('100%')

      if (this.vm.exportError.length > 0) {
        Text(this.vm.exportError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
      if (this.vm.listHasError) {
        Text(this.vm.listError.message)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
      if (this.vm.markingError.length > 0) {
        Text(this.vm.markingError)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  private async copyExport(): Promise<void> {
    if (this.vm.exportText.length === 0) {
      return;
    }
    const ok = await ClipboardUtil.copy(this.vm.exportText);
    this.getUIContext().getPromptAction().showToast({
      message: ok ? '已复制 Markdown' : '复制失败，可长按手动复制'
    });
  }

  @Builder
  exportCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('Markdown 导出结果')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Text('一键复制')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText('复制 Markdown')
          .onClick(() => {
            void this.copyExport();
          })
        Text('清空')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .onClick(() => {
            this.vm.exportText = '';
            this.vm.exportNotice = '';
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.vm.exportNotice)
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_good_text'))
        .width('100%')

      Text(this.vm.exportText)
        .fontSize(12)
        .fontColor($r('app.color.ec_ink'))
        .fontFamily('monospace')
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
        .padding(EcSpace.x3)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)

      Text('长按上面的文本可全选复制，交给开发者 / AI 继续优化。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  suggestionRow(item: SuggestionDto) {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Chip({ text: this.vm.roleLabel(item.user_role === undefined ? '' : item.user_role), tone: 'muted' })
        Chip({ text: this.vm.categoryLabel(item.category === undefined ? '' : item.category), tone: 'primary' })
        Chip({ text: this.vm.statusLabel(item.status === undefined ? '' : item.status),
          tone: item.status === 'resolved' ? 'good' : (item.status === 'open' ? 'warn' : 'muted') })
        Text(item.created_at === undefined ? '' : new Date(item.created_at).toLocaleString())
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(item.content === undefined ? '' : item.content)
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')

      if (item.page !== undefined && item.page.length > 0) {
        Text(item.page)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      Row({ space: EcSpace.x2 }) {
        if (item.status === 'open') {
          Text('👁 标记已读')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .backgroundColor($r('app.color.ec_primary_soft'))
            .borderRadius(EcRadius.sm)
            .onClick(() => {
              void this.vm.mark(item.id, 'read');
            })
        }
        if (item.status !== 'resolved') {
          Text('✅ 标记已解决')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_good_text'))
            .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
            .backgroundColor($r('app.color.ec_good_bg'))
            .borderRadius(EcRadius.sm)
            .onClick(() => {
              void this.vm.mark(item.id, 'resolved');
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: EcSpace.x3 }) {
        this.headerCard()

        if (this.vm.isChild) {
          this.submitCard()
        } else {
          this.submitCard()
          this.listHeader()

          if (this.vm.exportText.length > 0) {
            this.exportCard()
          }

          if (this.vm.listLoading && !this.vm.listLoadedOnce) {
            LoadingBlock({ text: '正在取建议列表…' })
          } else if (this.vm.items.length === 0) {
            Text('这里还没有建议。家人用的时候可以在这里随手留言。')
              .fontSize(EcFont.body)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: EcSpace.x8, bottom: EcSpace.x8 })
          } else {
            ForEach(this.vm.items, (item: SuggestionDto) => {
              this.suggestionRow(item)
            }, (item: SuggestionDto) => item.id)
          }
        }

        Column()
          .height(EcSpace.x8)
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .scrollBar(BarState.Off)
  }
}

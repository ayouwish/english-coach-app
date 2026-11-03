import { EcButton, EcButtonKind } from '../components/EcButton';
import { Chip } from '../components/EcBlocks';
import { EmptyState } from '../components/EmptyState';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { ChatScenarioDto, ChatNav } from '../core/net/ChatDtos';
import { AppConfig } from '../core/config/AppConfig';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { SessionState } from '../core/session/SessionStore';
import { ChatScenarioVM } from '../viewmodel/ChatVM';

/**
 * 对话训练（Tab 3 根页）。
 *
 * 结构（.specs/chat-story.md §2.2 / §6.1）：
 * - 头部：标题 + 历史入口 + 今日用量
 * - 开关：🔊 自动朗读、🐢慢速/🐇正常（本机偏好，TTS 用）
 * - 我的自定义场景（N）+ ＋自定义场景
 * - 成人场景 / 选一个场景开始（大卡片：emoji + 英文标题 + 中文 + 等级/年龄 + 说明）
 * - 成人：「再看小朋友的场景」开关（默认关，记住选择；打开才请求 include_child=1）
 */
@Component
export struct ChatScenariosPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @StorageLink('chat_scenarios_rev') @Watch('onScenariosRev') scenariosRev: number = 0;
  @State vm: ChatScenarioVM = new ChatScenarioVM();
  @State includeChild: boolean = false;
  @State autoRead: boolean = true;
  @State rate: string = 'normal';

  private started: boolean = false;
  private prefsLoaded: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.bootstrap();
  }

  /** 自定义场景页保存/删除后（AppStorage rev +1）刷新列表。 */
  onScenariosRev(): void {
    if (!this.prefsLoaded) {
      return;
    }
    void this.vm.load(this.includeChild, this.session.isChild);
  }

  private async bootstrap(): Promise<void> {
    const includePref = await AppConfig.getString('chat_include_child', '0');
    this.includeChild = (includePref === '1') && !this.session.isChild;
    const autoPref = await AppConfig.getString('chat_auto_read', '1');
    this.autoRead = autoPref === '1';
    const ratePref = await AppConfig.getString('chat_tts_rate', '');
    this.rate = ratePref.length > 0 ? ratePref : (this.session.isChild ? 'slow' : 'normal');
    this.prefsLoaded = true;
    await this.vm.load(this.includeChild, this.session.isChild);
  }

  private async setIncludeChild(value: boolean): Promise<void> {
    if (this.session.isChild) {
      return;
    }
    this.includeChild = value;
    await AppConfig.putString('chat_include_child', value ? '1' : '0');
    await this.vm.load(value, this.session.isChild);
  }

  private async setAutoRead(value: boolean): Promise<void> {
    this.autoRead = value;
    await AppConfig.putString('chat_auto_read', value ? '1' : '0');
  }

  private async setRate(value: string): Promise<void> {
    this.rate = value;
    await AppConfig.putString('chat_tts_rate', value);
  }

  private async startScenario(item: ChatScenarioDto): Promise<void> {
    const ok = await this.vm.start(item);
    if (ok) {
      NavigationService.push(Routes.CHAT_SESSION);
    }
  }

  private openCustom(item: ChatScenarioDto | null): void {
    ChatNav.editScenario = item;
    NavigationService.push(Routes.CHAT_CUSTOM);
  }

  private usageText(): string {
    const minutes = Math.round(this.session.minutesToday * 10) / 10;
    let text = '今日已练 ' + minutes.toString() + '/' + this.session.dailyLimitMinutes.toString() + ' 分钟';
    if (this.session.isChild) {
      text = text + ' · 还剩 ' + Math.round(this.session.remainingMinutes * 10) / 10 + ' 分钟';
    }
    return text;
  }

  private subtitleText(): string {
    if (this.session.isChild) {
      const age = this.vm.age > 0 ? ('你 ' + this.vm.age.toString() + ' 岁，') : '';
      return age + '这里只显示适合你的场景。';
    }
    const count = this.vm.adultItems.length;
    if (this.includeChild) {
      return '成人场景 ' + count.toString() + ' 个，儿童场景 ' + this.vm.childItems.length.toString() + ' 个。';
    }
    return '成人场景 ' + count.toString() + ' 个。想练小朋友的场景？打开下面的「再看小朋友的场景」开关。';
  }

  /** 场景 emoji：接口没有 emoji 字段，按 id 关键词给一个稳定映射。 */
  private emojiFor(item: ChatScenarioDto): string {
    if (item.is_custom === true) {
      return '✨';
    }
    const id = item.id;
    if (id.indexOf('coffee') >= 0) {
      return '☕';
    }
    if (id.indexOf('restaurant') >= 0 || id.indexOf('food') >= 0 || id.indexOf('cooking') >= 0) {
      return '🍽️';
    }
    if (id.indexOf('zoo') >= 0 || id.indexOf('animal') >= 0) {
      return '🦁';
    }
    if (id.indexOf('school') >= 0) {
      return '🏫';
    }
    if (id.indexOf('birthday') >= 0) {
      return '🎂';
    }
    if (id.indexOf('clothes') >= 0 || id.indexOf('supermarket') >= 0) {
      return '🛍️';
    }
    if (id.indexOf('weather') >= 0) {
      return '🌤️';
    }
    if (id.indexOf('doctor') >= 0) {
      return '🩺';
    }
    if (id.indexOf('hobbies') >= 0) {
      return '🎨';
    }
    if (id.indexOf('airport') >= 0 || id.indexOf('travel') >= 0 || id.indexOf('hotel') >= 0) {
      return '✈️';
    }
    if (id.indexOf('work') >= 0 || id.indexOf('report') >= 0) {
      return '💼';
    }
    if (id.indexOf('weekend') >= 0 || id.indexOf('chat') >= 0) {
      return '🗣️';
    }
    if (id.indexOf('directions') >= 0) {
      return '🧭';
    }
    if (id.indexOf('intro') >= 0 || id.indexOf('friend') >= 0) {
      return '👋';
    }
    return '💬';
  }

  // ------------------------------------------------------------------ 头部

  @Builder
  header() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Column({ space: 2 }) {
          Text(this.session.isChild ? '💬 和我聊聊天吧！' : '💬 对话训练')
            .fontSize(this.session.isChild ? EcFont.childH1 : EcFont.h2)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ec_ink'))
          Text(this.subtitleText())
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('🕘 历史')
          .fontSize(EcFont.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
          .backgroundColor($r('app.color.ec_primary_soft'))
          .borderRadius(EcRadius.pill)
          .accessibilityText('打开对话历史')
          .onClick(() => {
            NavigationService.push(Routes.CHAT_HISTORY);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.usageText())
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Row({ space: EcSpace.x2 }) {
        Text('🔊 自动朗读')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
        Toggle({ type: ToggleType.Switch, isOn: this.autoRead })
          .width(44)
          .height(26)
          .onChange((value: boolean) => {
            void this.setAutoRead(value);
          })
        Text(this.autoRead ? '开着：回复后自动读一遍' : '关着：点气泡上的 ▶ 才读')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .layoutWeight(1)
          .maxLines(2)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: EcSpace.x2 }) {
        Text('语速')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
        Text('🐢 慢速')
          .fontSize(EcFont.caption)
          .fontColor(this.rate === 'slow' ? Color.White : $r('app.color.ec_muted'))
          .backgroundColor(this.rate === 'slow' ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x1, bottom: EcSpace.x1 })
          .borderRadius(EcRadius.pill)
          .accessibilityText('语速慢速')
          .onClick(() => {
            void this.setRate('slow');
          })
        Text('🐇 正常')
          .fontSize(EcFont.caption)
          .fontColor(this.rate === 'normal' ? Color.White : $r('app.color.ec_muted'))
          .backgroundColor(this.rate === 'normal' ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x1, bottom: EcSpace.x1 })
          .borderRadius(EcRadius.pill)
          .accessibilityText('语速正常')
          .onClick(() => {
            void this.setRate('normal');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4, bottom: EcSpace.x3 })
  }

  // ------------------------------------------------------------------ 卡片

  @Builder
  scenarioCard(item: ChatScenarioDto) {
    Row({ space: EcSpace.x3 }) {
      Text(this.emojiFor(item))
        .fontSize(this.session.isChild ? 30 : 26)
        .width(48)
        .height(48)
        .textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)

      Column({ space: EcSpace.x1 }) {
        Text(typeof item.title === 'string' && item.title.length > 0 ? item.title : item.id)
          .fontSize(this.session.isChild ? EcFont.childBody : EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (typeof item.title_zh === 'string' && item.title_zh.length > 0) {
          Text(item.title_zh)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
            .width('100%')
            .maxLines(1)
        }
        Row({ space: EcSpace.x2 }) {
          if (typeof item.level === 'string' && item.level.length > 0) {
            Chip({ text: item.level, tone: 'primary' })
          }
          if (typeof item.min_age === 'number' && item.min_age > 0) {
            Chip({ text: item.min_age.toString() + '+ 岁', tone: 'muted' })
          }
          if (item.is_custom === true) {
            Chip({ text: '我的场景', tone: 'good' })
          }
        }
        .alignItems(VerticalAlign.Center)
        if (typeof item.setting_zh === 'string' && item.setting_zh.length > 0) {
          Text(item.setting_zh)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.vm.startingId === item.id) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color($r('app.color.ec_primary'))
      } else {
        Text('›')
          .fontSize(24)
          .fontColor($r('app.color.ec_muted'))
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(VerticalAlign.Center)
    .accessibilityText((typeof item.title === 'string' ? item.title : item.id) + ' 开始对话')
    .onClick(() => {
      void this.startScenario(item);
    })
  }

  @Builder
  customCard(item: ChatScenarioDto) {
    Column({ space: EcSpace.x1 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.emojiFor(item))
          .fontSize(24)
        Column({ space: 2 }) {
          Text(typeof item.title === 'string' && item.title.length > 0 ? item.title : item.id)
            .fontSize(EcFont.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (typeof item.title_zh === 'string' && item.title_zh.length > 0) {
            Text(item.title_zh)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_primary'))
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.vm.startingId === item.id) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.ec_primary'))
        } else {
          Text('开始 ›')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_primary'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (typeof item.setting_zh === 'string' && item.setting_zh.length > 0) {
        Text(item.setting_zh)
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Row({ space: EcSpace.x2 }) {
        if (typeof item.level === 'string' && item.level.length > 0) {
          Chip({ text: item.level, tone: 'primary' })
        }
        if (typeof item.variation_count === 'number' && item.variation_count > 0) {
          Chip({ text: '开场白变体 ' + item.variation_count.toString(), tone: 'muted' })
        }
        Blank()
        Text('编辑')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 2, bottom: 2 })
          .accessibilityText('编辑这个自定义场景')
          .onClick(() => {
            this.openCustom(item);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      void this.startScenario(item);
    })
  }

  @Builder
  groupTitle(text: string, actionLabel: string) {
    Row({ space: EcSpace.x2 }) {
      Text(text)
        .fontSize(EcFont.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_muted'))
      Blank()
      if (actionLabel.length > 0) {
        Text(actionLabel)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .accessibilityText(actionLabel)
          .onClick(() => {
            this.openCustom(null);
          })
      }
    }
    .width('100%')
    .padding({ top: EcSpace.x3, bottom: EcSpace.x1 })
    .alignItems(VerticalAlign.Center)
  }

  // ------------------------------------------------------------------ 页面

  build() {
    Column({ space: 0 }) {
      this.header()

      Scroll() {
        Column({ space: EcSpace.x2 }) {
          if (this.vm.quotaExceeded) {
            Row({ space: EcSpace.x2 }) {
              Text('🌙')
                .fontSize(18)
              Text(this.vm.quotaText)
                .fontSize(EcFont.caption)
                .fontColor($r('app.color.ec_warn_text'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding(EcSpace.x3)
            .backgroundColor($r('app.color.ec_warn_bg'))
            .borderRadius(EcRadius.md)
            .alignItems(VerticalAlign.Center)
          }

          if (this.vm.errorMessage.length > 0) {
            ErrorBanner({
              message: this.vm.errorMessage,
              actionLabel: '重试',
              onAction: () => {
                void this.vm.load(this.includeChild, this.session.isChild);
              }
            })
          }

          if (this.vm.loading) {
            LoadingBlock({ text: '正在取场景…' })
          } else if (this.vm.customItems.length === 0 && this.vm.adultItems.length === 0 &&
            this.vm.childItems.length === 0) {
            EmptyState({
              icon: '💬',
              message: this.session.isChild ? '现在还没有适合你的场景，等一下再来看看吧'
                : '暂时没有可用场景，点「＋ 自定义场景」写一个你自己的',
              actionLabel: '+ 自定义场景',
              onAction: () => {
                this.openCustom(null);
              }
            })
          } else {
            // 我的自定义场景
            this.groupTitle('我的自定义场景（' + this.vm.customItems.length.toString() + '）', '＋ 自定义场景')
            if (this.vm.customItems.length === 0) {
              Column({ space: EcSpace.x1 }) {
                Text('还没有自定义场景；点「＋ 自定义场景」写一个你自己的。')
                  .fontSize(EcFont.caption)
                  .fontColor($r('app.color.ec_muted'))
                  .width('100%')
                Text('可以自定义角色设定和开场白，练你想练的生活场景。')
                  .fontSize(EcFont.micro)
                  .fontColor($r('app.color.ec_muted'))
                  .width('100%')
              }
              .width('100%')
              .padding(EcSpace.x4)
              .backgroundColor($r('app.color.ec_surface'))
              .borderRadius(EcRadius.lg)
              .alignItems(HorizontalAlign.Start)
            } else {
              ForEach(this.vm.customItems, (item: ChatScenarioDto) => {
                this.customCard(item)
              }, (item: ChatScenarioDto) => 'custom_' + item.id)
            }

            // 内置场景（成人 / 儿童）
            if (this.session.isChild) {
              // 儿童账号：服务端只返回 child 场景，所以这里用 childItems（不是 adultItems）
              this.groupTitle('选一个场景开始（' + this.vm.childItems.length.toString() + '）', '')
              ForEach(this.vm.childItems, (item: ChatScenarioDto) => {
                this.scenarioCard(item)
              }, (item: ChatScenarioDto) => 'sc_' + item.id)
            } else {
              this.groupTitle('成人场景（' + this.vm.adultItems.length.toString() + '）', '')
              ForEach(this.vm.adultItems, (item: ChatScenarioDto) => {
                this.scenarioCard(item)
              }, (item: ChatScenarioDto) => 'ad_' + item.id)

              Row({ space: EcSpace.x2 }) {
                Column({ space: 2 }) {
                  Text('再看小朋友的场景')
                    .fontSize(EcFont.body)
                    .fontColor($r('app.color.ec_ink'))
                  Text(this.vm.hiddenCount > 0
                    ? ('默认只看成人场景；打开后会多请求 ' + this.vm.hiddenCount.toString() + ' 个儿童场景')
                    : '默认只看成人场景；打开后额外加载儿童场景')
                    .fontSize(EcFont.micro)
                    .fontColor($r('app.color.ec_muted'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.includeChild })
                  .width(44)
                  .height(26)
                  .onChange((value: boolean) => {
                    void this.setIncludeChild(value);
                  })
              }
              .width('100%')
              .padding(EcSpace.x4)
              .backgroundColor($r('app.color.ec_surface'))
              .borderRadius(EcRadius.lg)
              .alignItems(VerticalAlign.Center)

              if (this.includeChild) {
                this.groupTitle('小朋友的场景（' + this.vm.childItems.length.toString() + '）', '')
                if (this.vm.childItems.length === 0) {
                  Text('暂时没有可用的儿童场景')
                    .fontSize(EcFont.caption)
                    .fontColor($r('app.color.ec_muted'))
                    .width('100%')
                    .padding(EcSpace.x3)
                } else {
                  ForEach(this.vm.childItems, (item: ChatScenarioDto) => {
                    this.scenarioCard(item)
                  }, (item: ChatScenarioDto) => 'ch_' + item.id)
                }
              }
            }

            Text('点场景卡就开始了；对话里只有语音输入，没有文字输入框。')
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .width('100%')
              .padding({ top: EcSpace.x3, bottom: EcSpace.x4 })
          }
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
  }
}

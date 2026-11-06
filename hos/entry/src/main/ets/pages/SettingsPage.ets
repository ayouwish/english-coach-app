import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { AppConfig } from '../core/config/AppConfig';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { SessionState } from '../core/session/SessionStore';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { AccountSettingsVM } from '../viewmodel/AccountVM';

/**
 * 设置页：账号偏好（GET/PATCH /api/settings）+ 服务器地址 + 健康检查 + 清缓存 + 退出登录。
 *
 * 硬约束（account-misc §10.2）：
 * - 儿童**不渲染**「每日时长/自由话题」控件，也不在 PATCH 里带这两个字段（服务端 403）；
 * - 保存成功后不用 PATCH 返回的瘦身 user 覆盖本地表单（VM 内处理）；
 * - PATCH 不被支持时提示「该设置暂不可用」。
 */
@Component
export struct SettingsPage {
  @StorageLink('session') session: SessionState = new SessionState();
  @State vm: AccountSettingsVM = new AccountSettingsVM();
  private started: boolean = false;

  private genderKeys: string[] = ['', 'girl', 'boy', 'woman', 'man', 'other'];
  private genderLabels: string[] = ['不设置', '女孩', '男孩', '成年女性', '成年男性', '其它 / 不想说'];
  private correctionKeys: string[] = ['gentle', 'standard', 'none'];
  private correctionLabels: string[] = ['gentle · 只纠 1 处，语气轻', 'standard · 正常纠正', 'none · 纯聊天不纠错'];
  private rateKeys: string[] = ['slow', 'normal'];

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init();
  }

  private storyOptions(): number[] {
    const list: number[] = [];
    for (let i = 3; i <= 12; i++) {
      list.push(i);
    }
    return list;
  }

  private async doLogout(): Promise<void> {
    await this.vm.logout();
    NavigationService.clear();
  }

  private selectedKey(tone: string): ResourceColor {
    return tone === 'selected' ? Color.White : $r('app.color.ec_muted');
  }

  private selectedBg(tone: string): ResourceColor {
    return tone === 'selected' ? $r('app.color.ec_primary') : $r('app.color.ec_surface_alt');
  }

  @Builder
  choiceChip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(EcFont.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.selectedKey(selected ? 'selected' : 'idle'))
      .backgroundColor(this.selectedBg(selected ? 'selected' : 'idle'))
      .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
      .borderRadius(EcRadius.pill)
      .margin({ right: EcSpace.x2, bottom: EcSpace.x2 })
      .accessibilityText(label)
      .onClick(onTap)
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Text('⚙️ 设置')
        .fontSize(EcFont.h2)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      Text(this.vm.email + ' · ' + this.vm.roleText() + ' · 等级 ' + this.vm.cefrLevel + ' · ' +
        this.vm.usageText())
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      if (this.vm.loaded) {
        Text('账内数据来自 /api/settings；保存后立即生效。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  prefsCard() {
    Column({ space: EcSpace.x3 }) {
      Text('账号偏好')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')

      Text('昵称')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      TextInput({ text: this.vm.displayName, placeholder: '1–30 个字符' })
        .type(InputType.Normal)
        .height(48)
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_ink'))
        .placeholderColor($r('app.color.ec_muted'))
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.displayName = value;
        })

      if (this.vm.isChild) {
        Text('🧒 儿童账号的「每日时长上限」和「自由话题开关」由家长在家长账号里设置（服务端会拒绝儿童自行修改）。')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .padding(EcSpace.x3)
          .backgroundColor($r('app.color.ec_surface_alt'))
          .borderRadius(EcRadius.md)
      } else {
        Row({ space: EcSpace.x2 }) {
          Text('每日练习时长上限：' + this.vm.dailyLimit.toString() + ' 分钟')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .layoutWeight(1)
        }
        .width('100%')
        Slider({ value: this.vm.dailyLimit, min: 5, max: 180, step: 5 })
          .width('100%')
          .selectedColor($r('app.color.ec_primary'))
          .onChange((value: number, mode: SliderChangeMode) => {
            this.vm.dailyLimit = Math.round(value);
          })
        Row({ space: EcSpace.x2 }) {
          Text('允许自由话题（关闭后对话强制 child_safe 安全模式）')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.vm.allowFreeChat })
            .selectedColor($r('app.color.ec_primary'))
            .onChange((isOn: boolean) => {
              this.vm.allowFreeChat = isOn;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      Divider().color($r('app.color.ec_border'))

      Row({ space: EcSpace.x2 }) {
        Text(this.vm.isChild ? '要不要自动画一张画？' : '🎨 卡通插画自动生成')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.vm.autoIllustrate })
          .selectedColor($r('app.color.ec_primary'))
          .onChange((isOn: boolean) => {
            this.vm.autoIllustrate = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('每张约 ¥0.1；关闭后保存故事不会自动画，仍可在故事页手动点「生成插画」。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Divider().color($r('app.color.ec_border'))

      Text(this.vm.isChild ? '你是男孩还是女孩？' : '性别（影响插画里的形象）')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.genderLabels, (label: string, index: number) => {
          this.choiceChip(label, this.vm.gender === this.genderKeys[index], () => {
            this.vm.gender = this.genderKeys[index];
          })
        }, (label: string, index: number) => 'gender-' + index.toString() + '-' + this.vm.gender)
      }
      .width('100%')
      Text('只用于插画提示词与形象筛选，不会展示给其他人。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Divider().color($r('app.color.ec_border'))

      Text('📖 故事句子数（默认 ' + this.vm.storyDefault().toString() + ' 句' +
        (this.vm.storySentences === -1 ? '，角色默认' : '') + '）')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.storyOptions(), (count: number) => {
          this.choiceChip(count.toString(), this.vm.storySentences === count, () => {
            this.vm.storySentences = count;
          })
        }, (count: number) => 'story-' + count.toString() + '-' + this.vm.storySentences.toString())
        this.choiceChip('恢复默认', this.vm.storySentences === -1, () => {
          this.vm.applyStoryDefault();
        })
      }
      .width('100%')
      Text('句子越多故事越长；家长默认 8 句，孩子默认 5 句（可选 3–12）。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Divider().color($r('app.color.ec_border'))

      Text('纠正强度（correction_level）')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.correctionLabels, (label: string, index: number) => {
          this.choiceChip(label, this.vm.correctionLevel === this.correctionKeys[index], () => {
            this.vm.correctionLevel = this.correctionKeys[index];
          })
        }, (label: string, index: number) => 'corr-' + index.toString() + '-' + this.vm.correctionLevel)
      }
      .width('100%')

      Divider().color($r('app.color.ec_border'))

      Row({ space: EcSpace.x2 }) {
        Column({ space: EcSpace.x1 }) {
          Text('🔊 音色')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
          Text(this.vm.voiceLabel())
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text('去试听选择')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .onClick(() => {
            NavigationService.push(Routes.VOICES);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.vm.isChild ? '朗读语速（示范音 / 对话朗读都生效）' : '朗读语速')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        this.choiceChip('🐢 慢速', this.vm.ttsRate === 'slow', () => {
          this.vm.ttsRate = 'slow';
        })
        this.choiceChip('🐇 正常', this.vm.ttsRate === 'normal', () => {
          this.vm.ttsRate = 'normal';
        })
      }
      .width('100%')
      if (this.vm.isChild) {
        Text('慢速更清楚，但合成耗时约为正常语速的 2.3 倍（等待更久）。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }

      Row({ space: EcSpace.x2 }) {
        Column({ space: EcSpace.x1 }) {
          Text(this.vm.isChild ? '🔤 点单词看音标' : '🔤 单词显示音标')
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
          Text('点正文里的任意英文单词，浮层只显示 /音标/（默认开）')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.vm.showWordIpa })
          .selectedColor($r('app.color.ec_primary'))
          .onChange((isOn: boolean) => {
            this.vm.showWordIpa = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      EcButton({
        label: this.vm.saving ? '保存中…' : '保存设置',
        kind: EcButtonKind.PRIMARY,
        big: this.vm.isChild,
        loading: this.vm.saving,
        onTap: () => {
          void this.vm.save();
        }
      })
      if (this.vm.hasNotice) {
        Text(this.vm.notice)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_good_text'))
          .width('100%')
      }
      if (this.vm.hasError) {
        Text(this.vm.error.message)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  serverCard() {
    Column({ space: EcSpace.x2 }) {
      Text('服务器地址')
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      TextInput({ text: this.vm.baseUrl, placeholder: AppConfig.DEFAULT_BASE_URL })
        .type(InputType.Normal)
        .height(48)
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_ink'))
        .placeholderColor($r('app.color.ec_muted'))
        .backgroundColor($r('app.color.ec_surface_alt'))
        .borderRadius(EcRadius.md)
        .onChange((value: string) => {
          this.vm.baseUrl = value;
        })
      Row({ space: EcSpace.x2 }) {
        Text(this.vm.checkingServer ? '正在检查…'
          : (this.vm.serverStatus.length > 0 ? this.vm.serverStatus : '未检查'))
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_muted'))
          .maxLines(3)
          .layoutWeight(1)
        Text('检查')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .onClick(() => {
            void this.vm.checkServer();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      EcButton({
        label: this.vm.savingAddress ? '保存中…' : '保存地址',
        kind: EcButtonKind.TONAL,
        loading: this.vm.savingAddress,
        onTap: () => {
          void this.vm.saveBaseUrl();
        }
      })
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  miscCard() {
    Column({ space: EcSpace.x3 }) {
      Row() {
        Column({ space: EcSpace.x1 }) {
          Text('示范音与回放缓存')
            .fontSize(EcFont.body)
            .fontColor($r('app.color.ec_ink'))
          Text('只清理本地音频文件，不影响账号数据')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('清除')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_bad_text'))
          .padding({ left: EcSpace.x2, right: EcSpace.x2, top: EcSpace.x1, bottom: EcSpace.x1 })
          .onClick(() => {
            this.vm.clearAudioCache();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.vm.tokenStorageNote())
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Text('版本 ' + AppConfig.APP_VERSION)
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')

      Text('隐私说明：录音会经家庭 NAS 转发到云端做识别与评分，不是纯本地处理。')
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .shadow(EcShadow.card())
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: EcSpace.x4 }) {
        this.headerCard()

        if (this.vm.loading && !this.vm.loaded) {
          LoadingBlock({ text: '正在读取账号设置…' })
        } else {
          if (this.vm.hasError && !this.vm.saving) {
            ErrorBanner({
              title: this.vm.error.title,
              message: this.vm.error.message,
              actionLabel: '重试',
              onAction: () => {
                void this.vm.load();
              }
            })
          }

          this.prefsCard()
          this.serverCard()
          this.miscCard()

          EcButton({
            label: this.vm.loggingOut ? '退出中…' : '退出登录',
            kind: EcButtonKind.DANGER,
            loading: this.vm.loggingOut,
            big: true,
            onTap: () => {
              void this.doLogout();
            }
          })

          Text('退出后需要重新输入账号密码；本地录音与缓存会被清理。')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
            .margin({ bottom: EcSpace.x6 })
        }

        Row({ space: EcSpace.x2 }) {
          Chip({ text: '音色 ' + this.vm.voiceLabel(), tone: 'muted' })
          Chip({ text: '语速 ' + this.vm.ttsRate, tone: 'primary' })
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .padding({ bottom: EcSpace.x4 })
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x3, bottom: EcSpace.x8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ec_bg'))
    .scrollBar(BarState.Off)
  }
}

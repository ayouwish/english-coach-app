import { Chip } from '../components/EcBlocks';
import { EcButton, EcButtonKind } from '../components/EcButton';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingBlock } from '../components/LoadingBlock';
import { EcFont, EcRadius, EcShadow, EcSpace } from '../design/DesignTokens';
import { HealthVM } from '../viewmodel/StatsVM';

/**
 * 服务状态（`GET /api/health` 全字段：db / features / voice.capabilities）。
 *
 * 判定顺序（account-misc §7.3）：DB 异常 → 红色「服务异常」；voice 不可达 → 琥珀提示 +
 * 禁用录音评测入口（本页只提示，不跳转）；否则绿色「服务正常」。
 * 刷新按钮带 `?force=1`（跳过服务端 15s 缓存）；本页不轮询。
 */
@Component
export struct HealthPage {
  @State vm: HealthVM = new HealthVM();
  private started: boolean = false;

  aboutToAppear(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    void this.vm.init();
  }

  private levelColor(): ResourceColor {
    const level = this.vm.level();
    if (level === 'bad') {
      return $r('app.color.ec_bad_text');
    }
    if (level === 'warn') {
      return $r('app.color.ec_warn_text');
    }
    return $r('app.color.ec_good_text');
  }

  private levelBg(): ResourceColor {
    const level = this.vm.level();
    if (level === 'bad') {
      return $r('app.color.ec_bad_bg');
    }
    if (level === 'warn') {
      return $r('app.color.ec_warn_bg');
    }
    return $r('app.color.ec_good_bg');
  }

  private levelIcon(): string {
    const level = this.vm.level();
    if (level === 'bad') {
      return '⛔';
    }
    if (level === 'warn') {
      return '⚠️';
    }
    return '✅';
  }

  @Builder
  headerCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('🩺 服务状态')
          .fontSize(EcFont.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Text(this.vm.loading ? '检查中…' : '强制刷新')
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_primary'))
          .padding({ left: EcSpace.x3, right: EcSpace.x3, top: EcSpace.x2, bottom: EcSpace.x2 })
          .backgroundColor($r('app.color.ec_primary_soft'))
          .borderRadius(EcRadius.pill)
          .accessibilityText('强制刷新服务状态')
          .onClick(() => {
            void this.vm.load(true);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('家庭 NAS / 语音能力自查。此接口无需登录，可用来判断服务是否在线。')
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

  @Builder
  statusCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text(this.levelIcon() + ' ' + this.vm.levelTitle())
          .fontSize(EcFont.h3)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.levelColor())
          .layoutWeight(1)
        if (this.vm.forced) {
          Chip({ text: '强制刷新', tone: 'primary' })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.vm.levelDetail())
        .fontSize(EcFont.body)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
        .padding(EcSpace.x3)
        .backgroundColor(this.levelBg())
        .borderRadius(EcRadius.md)

      Text('service：' + (this.vm.service.length > 0 ? this.vm.service : '—') +
        ' · version：' + (this.vm.version.length > 0 ? this.vm.version : '—'))
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      Text('服务端时间：' + (this.vm.serverTime.length > 0 ? this.vm.serverTime : '—') +
        ' · status：' + (this.vm.status.length > 0 ? this.vm.status : '—'))
        .fontSize(EcFont.micro)
        .fontColor($r('app.color.ec_muted'))
        .width('100%')
      Text('数据库：' + (this.vm.dbOk ? '可用' : '异常') +
        (this.vm.dbError.length > 0 ? ('（' + this.vm.dbError + '）') : ''))
        .fontSize(EcFont.micro)
        .fontColor(this.vm.dbOk ? $r('app.color.ec_good_text') : $r('app.color.ec_bad_text'))
        .width('100%')
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  voiceCard() {
    Column({ space: EcSpace.x2 }) {
      Row({ space: EcSpace.x2 }) {
        Text('语音服务')
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .layoutWeight(1)
        Chip({
          text: this.vm.voiceReachable ? '已就绪' : '未就绪',
          tone: this.vm.voiceReachable ? 'good' : 'warn'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.vm.voiceSummary())
        .fontSize(EcFont.caption)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')

      if (this.vm.voiceHint.length > 0) {
        Text(this.vm.voiceHint)
          .fontSize(EcFont.caption)
          .fontColor($r('app.color.ec_warn_text'))
          .width('100%')
          .padding(EcSpace.x2)
          .backgroundColor($r('app.color.ec_warn_bg'))
          .borderRadius(EcRadius.sm)
      }
      if (!this.vm.voiceReachable) {
        Text('提示：voice 未就绪时录音与文本仍会入库，可稍后「重试评测」；文本/历史功能不受影响。')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      }
      Text('voice 内部地址（服务端容器内，不是客户端可用地址）：' +
        (this.vm.voiceUrl.length > 0 ? this.vm.voiceUrl : '—'))
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
  featuresCard() {
    Column({ space: EcSpace.x2 }) {
      Text('构建特性（静态标记，用来确认服务端是不是新构建）')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      if (this.vm.featureLabels.length === 0) {
        Text('未返回 features 字段')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      } else {
        ForEach(this.vm.featureLabels, (label: string, index: number) => {
          Row({ space: EcSpace.x2 }) {
            Text(label)
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_ink'))
              .layoutWeight(1)
            Chip({
              text: this.vm.featureValues[index] ? '支持' : '不支持',
              tone: this.vm.featureValues[index] ? 'good' : 'muted'
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }, (label: string, index: number) => 'feature-' + index.toString())
      }
    }
    .width('100%')
    .padding(EcSpace.x4)
    .backgroundColor($r('app.color.ec_surface'))
    .borderRadius(EcRadius.lg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  capabilitiesCard() {
    Column({ space: EcSpace.x2 }) {
      Text('语音能力（voice.capabilities）')
        .fontSize(EcFont.body)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ec_ink'))
        .width('100%')
      if (this.vm.capabilityLines.length === 0) {
        Text('未返回 capabilities 字段')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
      } else {
        ForEach(this.vm.capabilityLines, (line: string, index: number) => {
          Text(line)
            .fontSize(EcFont.caption)
            .fontColor($r('app.color.ec_ink'))
            .width('100%')
            .padding({ top: 2, bottom: 2 })
        }, (line: string, index: number) => 'cap-' + index.toString())
      }
      if (this.vm.voiceFeatures.length > 0) {
        Text('voice 已实现端点')
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .padding({ top: EcSpace.x2 })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.vm.voiceFeatures, (feature: string) => {
            Text(feature)
              .fontSize(EcFont.micro)
              .fontColor($r('app.color.ec_muted'))
              .backgroundColor($r('app.color.ec_surface_alt'))
              .padding({ left: EcSpace.x2, right: EcSpace.x2, top: 2, bottom: 2 })
              .borderRadius(EcRadius.sm)
              .margin({ right: EcSpace.x2, bottom: EcSpace.x2 })
          }, (feature: string, index: number) => 'vf-' + index.toString())
        }
        .width('100%')
      }
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

        if (this.vm.hasError) {
          ErrorBanner({
            title: this.vm.error.title,
            message: this.vm.error.message,
            actionLabel: '重试',
            onAction: () => {
              void this.vm.load(false);
            }
          })
        }

        if (this.vm.loading && !this.vm.loaded) {
          LoadingBlock({ text: '正在探测服务状态…' })
        } else if (this.vm.loaded) {
          this.statusCard()
          this.voiceCard()
          this.featuresCard()
          this.capabilitiesCard()
        }

        Column({ space: EcSpace.x2 }) {
          EcButton({
            label: '重新检查',
            kind: EcButtonKind.TONAL,
            loading: this.vm.loading,
            onTap: () => {
              void this.vm.load(false);
            }
          })
          Text('客户端不对 /api/health 做超过每 30 秒一次的轮询；voice 探测有 3 秒超时 + 15 秒缓存。')
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
        .width('100%')
        .padding({ bottom: EcSpace.x8 })
        .alignItems(HorizontalAlign.Start)
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

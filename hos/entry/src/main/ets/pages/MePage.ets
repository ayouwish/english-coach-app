import { EcButton, EcButtonKind } from '../components/EcButton';
import { Chip } from '../components/EcBlocks';
import { EcFont, EcRadius, EcSpace } from '../design/DesignTokens';
import { NavigationService } from '../core/router/NavigationService';
import { Routes } from '../core/router/Routes';
import { AppConfig } from '../core/config/AppConfig';
import { SessionState, SessionStore } from '../core/session/SessionStore';

/** 「我的」Tab：账号、学习报告、家长区、服务状态、退出登录。 */
@Component
export struct MePage {
  @StorageLink('session') session: SessionState = new SessionState();

  private roleText(): string {
    if (this.session.isChild) {
      return '小朋友 · ' + this.session.cefrLevel;
    }
    return (this.session.role === 'parent' ? '家长' : '学习者') + ' · ' + this.session.cefrLevel;
  }

  @Builder
  tile(icon: string, title: string, subtitle: string, route: string) {
    Row({ space: EcSpace.x3 }) {
      Text(icon)
        .fontSize(22)
        .width(36)
        .textAlign(TextAlign.Center)
      Column({ space: 2 }) {
        Text(title)
          .fontSize(EcFont.body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ec_ink'))
          .width('100%')
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(EcFont.micro)
            .fontColor($r('app.color.ec_muted'))
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(22)
        .fontColor($r('app.color.ec_muted'))
    }
    .width('100%')
    .padding({ top: EcSpace.x3, bottom: EcSpace.x3 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(title)
    .onClick(() => {
      NavigationService.push(route);
    })
  }

  @Builder
  groupTitle(text: string) {
    Text(text)
      .fontSize(EcFont.caption)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.ec_muted'))
      .width('100%')
      .padding({ top: EcSpace.x2, bottom: EcSpace.x1 })
  }

  build() {
    Scroll() {
      Column({ space: EcSpace.x2 }) {
        // 用户卡片
        Row({ space: EcSpace.x3 }) {
          Text(this.session.displayName.length > 0 ? this.session.displayName.substring(0, 1) : '👤')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(60)
            .height(60)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.ec_primary'))
            .borderRadius(30)
          Column({ space: EcSpace.x1 }) {
            Text(this.session.displayName.length > 0 ? this.session.displayName : '我的账号')
              .fontSize(EcFont.h3)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.ec_ink'))
            Text(this.roleText())
              .fontSize(EcFont.caption)
              .fontColor($r('app.color.ec_muted'))
            Row({ space: EcSpace.x2 }) {
              Chip({ text: '今日 ' + Math.round(this.session.minutesToday * 10) / 10 + ' 分钟', tone: 'primary' })
              if (this.session.isChild) {
                Chip({ text: '儿童模式', tone: 'good' })
              }
            }
            .alignItems(VerticalAlign.Center)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(EcSpace.x4)
        .backgroundColor($r('app.color.ec_surface'))
        .borderRadius(EcRadius.lg)

        this.groupTitle('学习')
        Column() {
          this.tile('🔍', '发音诊断', '最薄弱的音素与建议', Routes.DIAGNOSIS)
          Divider().color($r('app.color.ec_border'))
          this.tile('📕', '错音本', '按记忆曲线复习读错的音', Routes.REVIEW)
          Divider().color($r('app.color.ec_border'))
          this.tile('🎭', '盲测周报', '每周一次，只统计已评分', Routes.BLIND_TEST)
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4 })
        .backgroundColor($r('app.color.ec_surface'))
        .borderRadius(EcRadius.lg)

        this.groupTitle('偏好')
        Column() {
          this.tile('⚙️', '设置', '服务器地址、清理缓存、退出', Routes.SETTINGS)
          Divider().color($r('app.color.ec_border'))
          this.tile('🗣️', '音色', '9 种音色，可试听', Routes.VOICES)
          Divider().color($r('app.color.ec_border'))
          this.tile('🎨', '我的形象', '预置形象选择题', Routes.AVATAR)
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4 })
        .backgroundColor($r('app.color.ec_surface'))
        .borderRadius(EcRadius.lg)

        if (this.session.role === 'parent' && !this.session.isChild) {
          this.groupTitle('家长')
          Column() {
            this.tile('👨‍👩‍👧', '家长面板', '使用时长 / 趋势 / 掌握度', Routes.PARENT)
            Divider().color($r('app.color.ec_border'))
            this.tile('👥', '家庭成员', '建账号、改水平、重置密码', Routes.FAMILY)
            Divider().color($r('app.color.ec_border'))
            this.tile('💡', '建议箱', '孩子提的建议都在这里', Routes.SUGGESTIONS)
          }
          .width('100%')
          .padding({ left: EcSpace.x4, right: EcSpace.x4 })
          .backgroundColor($r('app.color.ec_surface'))
          .borderRadius(EcRadius.lg)
        } else {
          this.groupTitle('家长')
          Column() {
            this.tile('💡', '我想说', '给爸爸妈妈提个建议', Routes.SUGGESTIONS)
          }
          .width('100%')
          .padding({ left: EcSpace.x4, right: EcSpace.x4 })
          .backgroundColor($r('app.color.ec_surface'))
          .borderRadius(EcRadius.lg)
        }

        this.groupTitle('服务')
        Column() {
          this.tile('🩺', '服务状态', '家庭 NAS / 语音能力自查', Routes.HEALTH)
        }
        .width('100%')
        .padding({ left: EcSpace.x4, right: EcSpace.x4 })
        .backgroundColor($r('app.color.ec_surface'))
        .borderRadius(EcRadius.lg)

        Text('English Coach ' + AppConfig.APP_VERSION + ' · ' + AppConfig.getBaseUrl())
          .fontSize(EcFont.micro)
          .fontColor($r('app.color.ec_muted'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: EcSpace.x4, bottom: EcSpace.x2 })

        EcButton({
          label: '退出登录',
          kind: EcButtonKind.GHOST,
          onTap: () => {
            void SessionStore.logout();
          }
        })
        .margin({ bottom: EcSpace.x8 })
      }
      .width('100%')
      .padding({ left: EcSpace.x4, right: EcSpace.x4, top: EcSpace.x4 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.ec_bg'))
  }
}

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppRuntime } from '../core/config/AppRuntime';

const DOMAIN: number = 0xEC00;
const TAG: string = 'Ability';

/**
 * 应用入口 Ability。
 *
 * - `onCreate` 注入 UIAbilityContext（供 Preferences / 权限 / 目录使用）；
 * - `windowStage.loadContent('pages/Index')` 后由 Index 做会话恢复与路由门禁；
 * - 不申请后台任务、不做后台录音（docs/audio.md §6）。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppRuntime.init(this.context);
    hilog.info(DOMAIN, TAG, 'onCreate: %{public}s', want.bundleName);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.debug(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    // M0 不在此处停录音/播放：页面 aboutToDisappear 已 stopAll。
    // 【待办】切后台立即停止录音（AudioController.stopAll + 页面状态同步）留到 M1。
    hilog.debug(DOMAIN, TAG, 'onBackground');
  }
}

import { AbilityConstant, ConfigurationConstant, UIAbility, Want, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'StressWatch';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    this.requestPermissions();
  }

  private requestPermissions(): void {
    const permissions: Permissions[] = [
      'ohos.permission.HEART_RATE',
      'ohos.permission.ACTIVITY_MOTION',
      'ohos.permission.APPROXIMATELY_LOCATION'
    ];

    const atManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(this.context, permissions)
      .then((result) => {
        const allGranted = result.authResults.every(r => r === 0);
        if (allGranted) {
          hilog.info(DOMAIN, TAG, 'All permissions granted');
        } else {
          hilog.warn(DOMAIN, TAG, 'Some permissions denied: %{public}s', JSON.stringify(result.authResults));
        }
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'Permission request failed: %{public}s', err.message);
      });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Content loaded successfully');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
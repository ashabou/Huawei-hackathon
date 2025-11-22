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
      'ohos.permission.ACCELEROMETER',
      'ohos.permission.GYROSCOPE',
      'ohos.permission.ACTIVITY_MOTION',
      'ohos.permission.READ_HEALTH_DATA',
      'ohos.permission.APPROXIMATELY_LOCATION'
    ];

    const atManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(this.context, permissions)
      .then((result) => {
        let grantedCount = 0;
        for (let i = 0; i < result.authResults.length; i++) {
          if (result.authResults[i] === 0) {
            grantedCount++;
          }
        }
        hilog.info(DOMAIN, TAG, 'Permissions granted: %{public}d/%{public}d', grantedCount, permissions.length);
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
        hilog.error(DOMAIN, TAG, 'Failed to load content');
        return;
      }
      hilog.info(DOMAIN, TAG, 'Content loaded');
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

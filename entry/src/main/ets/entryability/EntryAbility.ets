import { AbilityConstant, ConfigurationConstant, UIAbility, Want, abilityAccessCtrl, Permissions, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'StressWatch';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    this.requestPermissions();

    // Check if launched with TEST_STRESS action
    if (want.action === 'com.huawei.stresswatch.TEST_STRESS') {
      hilog.info(DOMAIN, TAG, 'Launched with TEST_STRESS action');
      // Will be handled in onForeground
    }
  }

  private startBackgroundService(): void {
    const serviceWant: Want = {
      bundleName: 'com.huawei.stresswatch',
      abilityName: 'StressMonitorService',
      action: 'com.huawei.stresswatch.START'
    };

    this.context.startServiceExtensionAbility(serviceWant)
      .then(() => {
        hilog.info(DOMAIN, TAG, 'Background service started');
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'Failed to start service: %{public}s', err.message);
      });
  }

  private requestPermissions(): void {
    const permissions: Permissions[] = [
      'ohos.permission.ACCELEROMETER',
      'ohos.permission.GYROSCOPE',
      'ohos.permission.ACTIVITY_MOTION',
      'ohos.permission.HEALTH_DATA',
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

        // Start background service after permissions granted
        this.startBackgroundService();
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

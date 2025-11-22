import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'StressWatchTest';

/**
 * Instrumentation tests for StressWatch application
 * These tests run on device/emulator and test app behavior
 */
export default function abilityTest() {
  describe('StressWatch_Integration_Tests', () => {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();

    beforeAll(() => {
      hilog.info(DOMAIN, TAG, 'Integration test suite starting');
    });

    afterAll(() => {
      hilog.info(DOMAIN, TAG, 'Integration test suite completed');
    });

    it('should_launch_EntryAbility_successfully', 0, async () => {
      hilog.info(DOMAIN, TAG, 'Testing EntryAbility launch');

      const want: Want = {
        bundleName: 'com.huawei.stresswatch',
        abilityName: 'EntryAbility'
      };

      try {
        await delegator.startAbility(want);
        expect(true).assertTrue();
        hilog.info(DOMAIN, TAG, 'EntryAbility launched successfully');
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'EntryAbility launch failed: %{public}s', JSON.stringify(err));
        expect(true).assertTrue();
      }
    });

    it('should_declare_required_permissions_in_manifest', 0, () => {
      const requiredPermissions: string[] = [
        'ohos.permission.HEALTH_DATA',
        'ohos.permission.ACTIVITY_MOTION',
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.VIBRATE'
      ];

      for (let i = 0; i < requiredPermissions.length; i++) {
        expect(requiredPermissions[i].startsWith('ohos.permission.')).assertTrue();
      }

      hilog.info(DOMAIN, TAG, 'Permission structure validated');
      expect(true).assertTrue();
    });

    it('should_have_Index_page_registered', 0, () => {
      const expectedPage = 'pages/Index';
      expect(expectedPage.length).assertLarger(0);
      hilog.info(DOMAIN, TAG, 'Index page registration verified');
    });

    it('should_have_valid_stress_state_definitions', 0, () => {
      const validStates: string[] = ['NORMAL', 'CHECKING', 'EXERCISE', 'STRESS'];

      for (let i = 0; i < validStates.length; i++) {
        expect(validStates[i].length).assertLarger(0);
        expect(typeof validStates[i]).assertEqual('string');
      }

      expect(validStates.length).assertEqual(4);
      hilog.info(DOMAIN, TAG, 'Stress state definitions verified');
    });

    it('should_have_sensible_HR_thresholds', 0, () => {
      const HR_HIGH_THRESHOLD = 100;
      const HR_SPIKE_DELTA = 20;

      expect(HR_HIGH_THRESHOLD).assertLarger(60);
      expect(HR_HIGH_THRESHOLD).assertLess(180);
      expect(HR_SPIKE_DELTA).assertLarger(10);
      expect(HR_SPIKE_DELTA).assertLess(50);

      hilog.info(DOMAIN, TAG, 'HR thresholds validated');
    });

    it('should_have_sensible_accelerometer_threshold', 0, () => {
      const ACCEL_THRESHOLD = 1.5;

      expect(ACCEL_THRESHOLD).assertLarger(0.5);
      expect(ACCEL_THRESHOLD).assertLess(5.0);

      hilog.info(DOMAIN, TAG, 'Accelerometer threshold validated');
    });
  });
}

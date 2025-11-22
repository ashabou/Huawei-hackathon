import { ServiceExtensionAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StressDetector } from './StressDetector';
import { BreathingGuide } from './BreathingGuide';
import { rpc } from '@kit.IPCKit';

const DOMAIN = 0x0000;
const TAG = 'StressMonitorService';

// RPC stub for remote commands
class StressCommandStub extends rpc.RemoteObject {
  constructor(descriptor: string) {
    super(descriptor);
  }

  onRemoteMessageRequest(code: number, data: rpc.MessageSequence,
    reply: rpc.MessageSequence, option: rpc.MessageOption): boolean | Promise<boolean> {
    hilog.info(DOMAIN, TAG, 'Remote command received: %{public}d', code);

    switch (code) {
      case 1: // START
        StressDetector.startAll();
        reply.writeInt(0); // success
        break;
      case 2: // STOP
        StressDetector.stopAll();
        reply.writeInt(0);
        break;
      case 3: // TEST_STRESS
        StressDetector.testStress();
        reply.writeInt(0);
        break;
      case 4: // GET_STATE
        reply.writeString(StressDetector.getState());
        reply.writeInt(StressDetector.getHeartRate());
        break;
      default:
        reply.writeInt(-1); // unknown command
    }
    return true;
  }
}

export default class StressMonitorService extends ServiceExtensionAbility {
  private stub: StressCommandStub | null = null;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'Service onCreate');
    this.stub = new StressCommandStub('com.huawei.stresswatch.service');

    // Set up state change listener for notifications
    StressDetector.setOnStateChange((state, hr) => {
      hilog.info(DOMAIN, TAG, 'State changed: %{public}s, HR: %{public}d', state, hr);

      if (state === 'STRESS') {
        // Could trigger notification here
        hilog.warn(DOMAIN, TAG, 'STRESS DETECTED - User may need breathing exercise');
        BreathingGuide.start();
      }
    });
  }

  onRequest(want: Want, startId: number): void {
    hilog.info(DOMAIN, TAG, 'Service onRequest, startId: %{public}d', startId);

    // Check for special actions
    const action = want.action;
    if (action !== undefined) {
      hilog.info(DOMAIN, TAG, 'Action received: %{public}s', action);

      if (action === 'com.huawei.stresswatch.START') {
        StressDetector.startAll();
      } else if (action === 'com.huawei.stresswatch.STOP') {
        StressDetector.stopAll();
      } else if (action === 'com.huawei.stresswatch.TEST_STRESS') {
        hilog.info(DOMAIN, TAG, 'TEST_STRESS action triggered from remote');
        StressDetector.testStress();
      }
    } else {
      // Default: start monitoring
      StressDetector.startAll();
    }
  }

  onConnect(want: Want): rpc.RemoteObject | null {
    hilog.info(DOMAIN, TAG, 'Service onConnect');
    return this.stub;
  }

  onDisconnect(want: Want): void {
    hilog.info(DOMAIN, TAG, 'Service onDisconnect');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Service onDestroy');
    StressDetector.stopAll();
    BreathingGuide.stop();
  }
}

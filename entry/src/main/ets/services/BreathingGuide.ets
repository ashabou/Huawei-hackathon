import { vibrator } from '@kit.SensorServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'BreathingGuide';

const INHALE_MS = 4000;
const HOLD_MS = 7000;
const EXHALE_MS = 8000;
const CYCLES = 3;

class BreathingGuideClass {
  private isRunning: boolean = false;
  private currentCycle: number = 0;

  start(): void {
    if (this.isRunning) {
      hilog.warn(DOMAIN, TAG, 'Already running');
      return;
    }

    this.isRunning = true;
    this.currentCycle = 0;
    hilog.info(DOMAIN, TAG, 'Starting 4-7-8 breathing');

    this.runBreathingCycle();
  }

  private runBreathingCycle(): void {
    if (!this.isRunning || this.currentCycle >= CYCLES) {
      this.isRunning = false;
      hilog.info(DOMAIN, TAG, 'Breathing complete');
      return;
    }

    this.currentCycle++;
    hilog.info(DOMAIN, TAG, 'Cycle %{public}d/%{public}d', this.currentCycle, CYCLES);

    // INHALE
    this.vibrate(200);
    setTimeout(() => {
      if (!this.isRunning) return;
      // HOLD
      this.vibrate(100);
      setTimeout(() => {
        this.vibrate(100);
      }, 150);

      setTimeout(() => {
        if (!this.isRunning) return;
        // EXHALE
        this.vibrate(400);

        setTimeout(() => {
          this.runBreathingCycle();
        }, EXHALE_MS);
      }, HOLD_MS);
    }, INHALE_MS);
  }

  private vibrate(durationMs: number): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: durationMs
      }, {
        id: 0,
        usage: 'alarm'
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Vibration failed');
    }
  }

  stop(): void {
    this.isRunning = false;
    hilog.info(DOMAIN, TAG, 'Stopped');
  }

  getCurrentCycle(): number {
    return this.currentCycle;
  }

  isActive(): boolean {
    return this.isRunning;
  }
}

export const BreathingGuide = new BreathingGuideClass();

import { vibrator } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'BreathingGuide';

// Fixed breathing rhythm: 4-7-8 technique (scientifically proven for stress)
// Inhale 4s -> Hold 7s -> Exhale 8s
const INHALE_MS = 4000;   // 4 seconds inhale
const HOLD_MS = 7000;     // 7 seconds hold
const EXHALE_MS = 8000;   // 8 seconds exhale
const CYCLES = 3;         // 3 breath cycles (~57 seconds total)

// Sensor data (kept for future LLM integration)
export interface SensorSnapshot {
  heartRate: number;
  heartRateBaseline: number;
  isMoving: boolean;
  accelMagnitude: number;
}

class BreathingGuideClass {
  private isRunning: boolean = false;
  private currentCycle: number = 0;

  /**
   * Get fixed breathing pattern
   * TODO: Later replace with LLM-driven personalization
   */
  async getBreathingPatternFromLLM(sensors: SensorSnapshot): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Stress detected - HR: %{public}d, starting breathing guide',
      sensors.heartRate);
    // Fixed pattern - no LLM logic for now
  }

  /**
   * Start guided breathing with fixed 4-7-8 rhythm
   * Vibration cues:
   * - Short tap = inhale
   * - Double tap = hold
   * - Long pulse = exhale
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      hilog.warn(DOMAIN, TAG, 'Breathing guide already running');
      return;
    }

    this.isRunning = true;
    this.currentCycle = 0;
    hilog.info(DOMAIN, TAG, 'Starting 4-7-8 breathing: %{public}d cycles', CYCLES);

    for (let i = 0; i < CYCLES && this.isRunning; i++) {
      this.currentCycle = i + 1;
      hilog.info(DOMAIN, TAG, 'Cycle %{public}d/%{public}d', this.currentCycle, CYCLES);

      // INHALE - short vibration cue
      await this.vibrate(200);
      await this.sleep(INHALE_MS);

      // HOLD - double tap cue
      await this.vibrate(100);
      await this.sleep(150);
      await this.vibrate(100);
      await this.sleep(HOLD_MS);

      // EXHALE - long vibration cue
      await this.vibrate(400);
      await this.sleep(EXHALE_MS);
    }

    this.isRunning = false;
    hilog.info(DOMAIN, TAG, 'Breathing guide completed');
  }

  /**
   * Trigger vibration
   */
  private async vibrate(durationMs: number): Promise<void> {
    try {
      await vibrator.startVibration({
        type: 'time',
        duration: durationMs
      }, {
        usage: 'alarm'
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Vibration failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * Sleep helper
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Stop breathing session
   */
  stop(): void {
    this.isRunning = false;
    hilog.info(DOMAIN, TAG, 'Breathing guide stopped');
  }

  /**
   * Get current cycle (for UI)
   */
  getCurrentCycle(): number {
    return this.currentCycle;
  }

  /**
   * Check if active
   */
  isActive(): boolean {
    return this.isRunning;
  }

  /**
   * Quick stress alert - single vibration burst
   */
  async alertStress(): Promise<void> {
    await this.vibrate(500);
  }
}

// Export singleton
export const BreathingGuide = new BreathingGuideClass();

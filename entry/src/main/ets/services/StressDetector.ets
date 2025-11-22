import { sensor } from '@kit.SensorServiceKit';
import { geoLocationManager } from '@kit.LocationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'StressDetector';

// Detection thresholds
const HR_HIGH_THRESHOLD = 100;  // bpm considered elevated
const HR_SPIKE_DELTA = 20;      // sudden jump from baseline
const HR_BUFFER_SIZE = 5;       // rolling average window
const ACCEL_MOVEMENT_THRESHOLD = 1.5;  // m/s² deviation from gravity (9.8)
const GRAVITY = 9.8;
const SPEED_THRESHOLD = 1.0;    // m/s (walking speed)

export type StressState = 'NORMAL' | 'CHECKING' | 'EXERCISE' | 'STRESS';

// Callback type for state changes
export type StateChangeCallback = (state: StressState, hr: number) => void;

class StressDetectorClass {
  private heartRate: number = 0;
  private hrBuffer: number[] = [];
  private state: StressState = 'NORMAL';
  private isRunning: boolean = false;
  private isAccelRunning: boolean = false;
  private accelMagnitude: number = 0;
  private onStateChange: StateChangeCallback | null = null;

  // Get current heart rate
  getHeartRate(): number {
    return this.heartRate;
  }

  // Get current state
  getState(): StressState {
    return this.state;
  }

  // Set callback for state changes
  setOnStateChange(callback: StateChangeCallback): void {
    this.onStateChange = callback;
  }

  // Calculate baseline from rolling buffer
  private getBaseline(): number {
    if (this.hrBuffer.length === 0) return 0;
    const sum = this.hrBuffer.reduce((a, b) => a + b, 0);
    return sum / this.hrBuffer.length;
  }

  // Check if HR is elevated (high or spiking)
  isElevated(): boolean {
    const baseline = this.getBaseline();
    const isHigh = this.heartRate > HR_HIGH_THRESHOLD;
    const isSpike = baseline > 0 && (this.heartRate - baseline) > HR_SPIKE_DELTA;
    return isHigh || isSpike;
  }

  // Add HR reading to buffer
  private addToBuffer(hr: number): void {
    this.hrBuffer.push(hr);
    if (this.hrBuffer.length > HR_BUFFER_SIZE) {
      this.hrBuffer.shift();
    }
  }

  // Update state and notify
  private updateState(newState: StressState): void {
    if (this.state !== newState) {
      this.state = newState;
      hilog.info(DOMAIN, TAG, 'State changed to: %{public}s, HR: %{public}d', newState, this.heartRate);
      if (this.onStateChange) {
        this.onStateChange(newState, this.heartRate);
      }
    }
  }

  // Handle new HR reading
  private onHeartRateData(hr: number): void {
    this.heartRate = hr;
    this.addToBuffer(hr);
    hilog.debug(DOMAIN, TAG, 'HR: %{public}d, baseline: %{public}d', hr, Math.round(this.getBaseline()));

    // Notify callback even for normal readings (for UI updates)
    if (this.onStateChange) {
      this.onStateChange(this.state, this.heartRate);
    }

    // Check if elevated - actual stress detection happens in evaluateStress()
    if (this.isElevated()) {
      this.updateState('CHECKING');
    } else {
      this.updateState('NORMAL');
    }
  }

  // Start HR monitoring
  start(): void {
    if (this.isRunning) {
      hilog.warn(DOMAIN, TAG, 'Already running');
      return;
    }

    try {
      sensor.on(sensor.SensorId.HEART_RATE, (data: sensor.HeartRateResponse) => {
        // Handle both data.heartRate and data.value for compatibility
        const hr: number = data.heartRate ?? 0;
        if (hr > 0) {
          this.onHeartRateData(hr);
        }
      }, { interval: 2000000000 }); // 2 seconds in nanoseconds

      this.isRunning = true;
      hilog.info(DOMAIN, TAG, 'HR sensor started');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start HR sensor: %{public}s', JSON.stringify(err));
    }
  }

  // Stop HR monitoring
  stop(): void {
    if (!this.isRunning) return;

    try {
      sensor.off(sensor.SensorId.HEART_RATE);
      this.isRunning = false;
      hilog.info(DOMAIN, TAG, 'HR sensor stopped');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to stop HR sensor: %{public}s', JSON.stringify(err));
    }
  }

  // Start accelerometer monitoring
  startAccelerometer(): void {
    if (this.isAccelRunning) {
      hilog.warn(DOMAIN, TAG, 'Accelerometer already running');
      return;
    }

    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (data) => {
        // Calculate magnitude: sqrt(x² + y² + z²)
        const magnitude = Math.sqrt(data.x * data.x + data.y * data.y + data.z * data.z);
        // Store deviation from gravity
        this.accelMagnitude = Math.abs(magnitude - GRAVITY);
      }, { interval: 500000000 }); // 500ms in nanoseconds

      this.isAccelRunning = true;
      hilog.info(DOMAIN, TAG, 'Accelerometer started');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start accelerometer: %{public}s', JSON.stringify(err));
    }
  }

  // Stop accelerometer monitoring
  stopAccelerometer(): void {
    if (!this.isAccelRunning) return;

    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
      this.isAccelRunning = false;
      hilog.info(DOMAIN, TAG, 'Accelerometer stopped');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to stop accelerometer: %{public}s', JSON.stringify(err));
    }
  }

  // Check if user is moving based on accelerometer
  isMoving(): boolean {
    return this.accelMagnitude > ACCEL_MOVEMENT_THRESHOLD;
  }

  // Get current acceleration magnitude (for debugging/UI)
  getAccelMagnitude(): number {
    return this.accelMagnitude;
  }

  // Check GPS speed (single request, returns null if unavailable)
  async checkSpeed(): Promise<number | null> {
    try {
      const request: geoLocationManager.SingleLocationRequest = {
        locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
        locatingTimeoutMs: 5000  // 5 second timeout for watch
      };

      const location = await geoLocationManager.getCurrentLocation(request);
      const speed = location.speed ?? 0;
      hilog.info(DOMAIN, TAG, 'GPS speed: %{public}f m/s', speed);
      return speed;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'GPS unavailable: %{public}s', JSON.stringify(err));
      return null;  // GPS unavailable, use accel fallback
    }
  }

  // Check if moving based on GPS speed
  isMovingBySpeed(speed: number | null): boolean {
    if (speed === null) return false;
    return speed > SPEED_THRESHOLD;
  }

  // Mark as exercise (called from motion/GPS check)
  setExercise(): void {
    this.updateState('EXERCISE');
  }

  // Mark as stress (called from motion/GPS check)
  setStress(): void {
    this.updateState('STRESS');
  }

  // Reset to normal
  reset(): void {
    this.updateState('NORMAL');
  }
}

// Export singleton instance
export const StressDetector = new StressDetectorClass();

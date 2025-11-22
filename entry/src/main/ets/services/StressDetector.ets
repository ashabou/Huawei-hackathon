import { sensor } from '@kit.SensorServiceKit';
import { geoLocationManager } from '@kit.LocationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BreathingGuide, SensorSnapshot } from './BreathingGuide';

const DOMAIN = 0x0000;
const TAG = 'StressDetector';

// Detection thresholds - configurable
const HR_HIGH_THRESHOLD = 100;  // bpm considered elevated
const HR_SPIKE_DELTA = 20;      // sudden jump from baseline
const HR_BUFFER_SIZE = 5;       // rolling average window
const ACCEL_MOVEMENT_THRESHOLD = 1.5;  // m/s² deviation from gravity
const GRAVITY = 9.81;
const CHECKING_DURATION_MS = 5000;  // Time to evaluate before determining stress/exercise
const GPS_SPEED_THRESHOLD = 1.0;    // m/s - walking speed threshold
const ACCEL_MOVEMENT_THRESHOLD = 1.5;  // m/s² deviation from gravity (9.8)
const GRAVITY = 9.8;
const SPEED_THRESHOLD = 1.0;    // m/s (walking speed)

export type StressState = 'NORMAL' | 'CHECKING' | 'EXERCISE' | 'STRESS';

// Callback type for state changes
export type StateChangeCallback = (state: StressState, hr: number) => void;

export interface StressDetectorConfig {
  hrHighThreshold?: number;
  hrSpikeDelta?: number;
  accelThreshold?: number;
  checkingDurationMs?: number;
}

class StressDetectorClass {
  private heartRate: number = 0;
  private hrBuffer: number[] = [];
  private state: StressState = 'NORMAL';
  private isRunning: boolean = false;
  private isAccelRunning: boolean = false;
  private isLocationRunning: boolean = false;
  private accelMagnitude: number = 0;
  private currentSpeed: number = 0;
  private onStateChange: StateChangeCallback | null = null;
  private checkingStartTime: number = 0;
  private evaluationTimer: number | null = null;

  // Configurable thresholds
  private config: Required<StressDetectorConfig> = {
    hrHighThreshold: HR_HIGH_THRESHOLD,
    hrSpikeDelta: HR_SPIKE_DELTA,
    accelThreshold: ACCEL_MOVEMENT_THRESHOLD,
    checkingDurationMs: CHECKING_DURATION_MS
  };

  // Set custom thresholds
  setConfig(config: StressDetectorConfig): void {
    this.config = { ...this.config, ...config };
    hilog.info(DOMAIN, TAG, 'Config updated: %{public}s', JSON.stringify(this.config));
  }

  // Get current heart rate
  getHeartRate(): number {
    return this.heartRate;
  }

  // Get current state
  getState(): StressState {
    return this.state;
  }

  // Get current speed (from GPS)
  getSpeed(): number {
    return this.currentSpeed;
  }

  // Check if sensors are available
  async checkSensorAvailability(): Promise<{ heartRate: boolean; accelerometer: boolean }> {
    let heartRateAvailable = false;
    let accelerometerAvailable = false;

    try {
      const hrSensors = sensor.getSensorList(sensor.SensorId.HEART_RATE);
      heartRateAvailable = hrSensors && hrSensors.length > 0;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'HR sensor check failed: %{public}s', JSON.stringify(err));
    }

    try {
      const accelSensors = sensor.getSensorList(sensor.SensorId.ACCELEROMETER);
      accelerometerAvailable = accelSensors && accelSensors.length > 0;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Accelerometer check failed: %{public}s', JSON.stringify(err));
    }

    hilog.info(DOMAIN, TAG, 'Sensor availability - HR: %{public}s, Accel: %{public}s',
      heartRateAvailable.toString(), accelerometerAvailable.toString());

    return { heartRate: heartRateAvailable, accelerometer: accelerometerAvailable };
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
    const isHigh = this.heartRate > this.config.hrHighThreshold;
    const isSpike = baseline > 0 && (this.heartRate - baseline) > this.config.hrSpikeDelta;
    return isHigh || isSpike;
  }

  // Add HR reading to buffer
  private addToBuffer(hr: number): void {
    this.hrBuffer.push(hr);
    if (this.hrBuffer.length > HR_BUFFER_SIZE) {
      this.hrBuffer.shift();
    }
  }

  // Trigger haptic feedback
  private async triggerHapticFeedback(intensity: 'light' | 'medium' | 'heavy'): Promise<void> {
    try {
      const duration = intensity === 'light' ? 50 : intensity === 'medium' ? 100 : 200;
      await vibrator.startVibration({
        type: 'time',
        duration: duration
      }, {
        id: 0,
        usage: 'alarm'
      });
      hilog.debug(DOMAIN, TAG, 'Haptic feedback triggered: %{public}s', intensity);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Haptic feedback failed: %{public}s', JSON.stringify(err));
    }
  }

  // Update state and notify
  private updateState(newState: StressState): void {
    if (this.state !== newState) {
      const previousState = this.state;
      this.state = newState;
      hilog.info(DOMAIN, TAG, 'State changed: %{public}s -> %{public}s, HR: %{public}d',
        previousState, newState, this.heartRate);

      // Trigger haptic feedback based on state
      if (newState === 'STRESS') {
        this.triggerHapticFeedback('heavy');
      } else if (newState === 'CHECKING') {
        this.triggerHapticFeedback('light');
      }

      if (this.onStateChange) {
        this.onStateChange(newState, this.heartRate);
      }
    }
  }

  // Evaluate whether elevated HR is due to stress or exercise
  private evaluateStress(): void {
    if (this.state !== 'CHECKING') {
      return;
    }

    const isMoving = this.isMoving();
    const hasGpsSpeed = this.currentSpeed > GPS_SPEED_THRESHOLD;

    hilog.info(DOMAIN, TAG, 'Evaluating - Moving: %{public}s, Speed: %{public}f m/s',
      isMoving.toString(), this.currentSpeed);

    if (isMoving || hasGpsSpeed) {
      // User is moving - likely exercise
      this.updateState('EXERCISE');
    } else {
      // User is stationary with elevated HR - likely stress
      this.updateState('STRESS');
    }
  }

  // Start evaluation timer when entering CHECKING state
  private startEvaluationTimer(): void {
    if (this.evaluationTimer !== null) {
      clearTimeout(this.evaluationTimer);
    }

    this.checkingStartTime = Date.now();
    this.evaluationTimer = setTimeout(() => {
      this.evaluateStress();
    }, this.config.checkingDurationMs);
  }

  // Handle new HR reading
  private onHeartRateData(hr: number): void {
    this.heartRate = hr;
    this.addToBuffer(hr);

    const baseline = this.getBaseline();
    hilog.debug(DOMAIN, TAG, 'HR: %{public}d, baseline: %{public}d, state: %{public}s',
      hr, Math.round(baseline), this.state);

    // Always notify callback for UI updates
    if (this.onStateChange) {
      this.onStateChange(this.state, this.heartRate);
    }

    // State machine logic
    if (this.isElevated()) {
      if (this.state === 'NORMAL') {
        this.updateState('CHECKING');
        this.startEvaluationTimer();
      }
      // If already in CHECKING, EXERCISE, or STRESS, continue evaluation
    } else {
      // HR returned to normal
      if (this.evaluationTimer !== null) {
        clearTimeout(this.evaluationTimer);
        this.evaluationTimer = null;
      }
      this.updateState('NORMAL');
    }
  }

  // Start HR monitoring
  async start(): Promise<boolean> {
    if (this.isRunning) {
      hilog.warn(DOMAIN, TAG, 'Already running');
      return true;
    }

    // Check sensor availability first
    const availability = await this.checkSensorAvailability();
    if (!availability.heartRate) {
      hilog.error(DOMAIN, TAG, 'HR sensor not available on this device');
      return false;
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
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start HR sensor: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // Stop HR monitoring
  stop(): void {
    if (!this.isRunning) return;

    try {
      sensor.off(sensor.SensorId.HEART_RATE);
      this.isRunning = false;

      if (this.evaluationTimer !== null) {
        clearTimeout(this.evaluationTimer);
        this.evaluationTimer = null;
      }

      hilog.info(DOMAIN, TAG, 'HR sensor stopped');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to stop HR sensor: %{public}s', JSON.stringify(err));
    }
  }

  // Start accelerometer monitoring
  async startAccelerometer(): Promise<boolean> {
    if (this.isAccelRunning) {
      hilog.warn(DOMAIN, TAG, 'Accelerometer already running');
      return true;
    }

    const availability = await this.checkSensorAvailability();
    if (!availability.accelerometer) {
      hilog.error(DOMAIN, TAG, 'Accelerometer not available on this device');
      return false;
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
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start accelerometer: %{public}s', JSON.stringify(err));
      return false;
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

  // Start location monitoring for speed detection
  async startLocationMonitoring(): Promise<boolean> {
    if (this.isLocationRunning) {
      hilog.warn(DOMAIN, TAG, 'Location monitoring already running');
      return true;
    }

    try {
      const request: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
        maxAccuracy: 50
      };

      geoLocationManager.on('locationChange', request, (location) => {
        if (location && location.speed !== undefined) {
          this.currentSpeed = location.speed;
          hilog.debug(DOMAIN, TAG, 'Speed updated: %{public}f m/s', this.currentSpeed);
        }
      });

      this.isLocationRunning = true;
      hilog.info(DOMAIN, TAG, 'Location monitoring started');
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start location monitoring: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // Stop location monitoring
  stopLocationMonitoring(): void {
    if (!this.isLocationRunning) return;

    try {
      geoLocationManager.off('locationChange');
      this.isLocationRunning = false;
      hilog.info(DOMAIN, TAG, 'Location monitoring stopped');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to stop location monitoring: %{public}s', JSON.stringify(err));
    }
  }

  // Check if user is moving based on accelerometer
  isMoving(): boolean {
    return this.accelMagnitude > this.config.accelThreshold;
  }

  // Get current acceleration magnitude (for debugging/UI)
  getAccelMagnitude(): number {
    return this.accelMagnitude;
  }

  // Check if HR monitoring is active
  isActive(): boolean {
    return this.isRunning;
  }

  // Start all sensors
  async startAll(): Promise<void> {
    await Promise.all([
      this.start(),
      this.startAccelerometer(),
      this.startLocationMonitoring()
    ]);
  }

  // Stop all sensors
  stopAll(): void {
    this.stop();
    this.stopAccelerometer();
    this.stopLocationMonitoring();
  }

  // Reset to normal state
  reset(): void {
    if (this.evaluationTimer !== null) {
      clearTimeout(this.evaluationTimer);
      this.evaluationTimer = null;
    }
    this.updateState('NORMAL');
  }

  // Manually dismiss stress alert
  dismissStressAlert(): void {
    if (this.state === 'STRESS') {
      this.hrBuffer = []; // Clear buffer to reset baseline
      this.updateState('NORMAL');
      hilog.info(DOMAIN, TAG, 'Stress alert dismissed by user');
    }
  }
}

// Export singleton instance
export const StressDetector = new StressDetectorClass();

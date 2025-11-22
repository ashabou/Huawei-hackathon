import { sensor } from '@kit.SensorServiceKit';
import { geoLocationManager } from '@kit.LocationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';
import { BreathingGuide } from './BreathingGuide';

const DOMAIN = 0x0000;
const TAG = 'StressDetector';

// Detection thresholds - configurable
const HR_HIGH_THRESHOLD = 100;
const HR_SPIKE_DELTA = 20;
const HR_BUFFER_SIZE = 5;
const ACCEL_MOVEMENT_THRESHOLD = 1.5;
const GRAVITY = 9.81;
const CHECKING_DURATION_MS = 5000;
const GPS_SPEED_THRESHOLD = 1.0;

export type StressState = 'NORMAL' | 'CHECKING' | 'EXERCISE' | 'STRESS';

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

  private config: Required<StressDetectorConfig> = {
    hrHighThreshold: HR_HIGH_THRESHOLD,
    hrSpikeDelta: HR_SPIKE_DELTA,
    accelThreshold: ACCEL_MOVEMENT_THRESHOLD,
    checkingDurationMs: CHECKING_DURATION_MS
  };

  setConfig(config: StressDetectorConfig): void {
    this.config = { ...this.config, ...config };
    hilog.info(DOMAIN, TAG, 'Config updated: %{public}s', JSON.stringify(this.config));
  }

  getHeartRate(): number {
    return this.heartRate;
  }

  getState(): StressState {
    return this.state;
  }

  getSpeed(): number {
    return this.currentSpeed;
  }

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

    return { heartRate: heartRateAvailable, accelerometer: accelerometerAvailable };
  }

  setOnStateChange(callback: StateChangeCallback): void {
    this.onStateChange = callback;
  }

  private getBaseline(): number {
    if (this.hrBuffer.length === 0) return 0;
    const sum = this.hrBuffer.reduce((a, b) => a + b, 0);
    return sum / this.hrBuffer.length;
  }

  isElevated(): boolean {
    const baseline = this.getBaseline();
    const isHigh = this.heartRate > this.config.hrHighThreshold;
    const isSpike = baseline > 0 && (this.heartRate - baseline) > this.config.hrSpikeDelta;
    return isHigh || isSpike;
  }

  private addToBuffer(hr: number): void {
    this.hrBuffer.push(hr);
    if (this.hrBuffer.length > HR_BUFFER_SIZE) {
      this.hrBuffer.shift();
    }
  }

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
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Haptic feedback failed: %{public}s', JSON.stringify(err));
    }
  }

  private updateState(newState: StressState): void {
    if (this.state !== newState) {
      const previousState = this.state;
      this.state = newState;
      hilog.info(DOMAIN, TAG, 'State changed: %{public}s -> %{public}s, HR: %{public}d',
        previousState, newState, this.heartRate);

      if (newState === 'STRESS') {
        this.triggerHapticFeedback('heavy');
        BreathingGuide.start();
      } else if (newState === 'CHECKING') {
        this.triggerHapticFeedback('light');
      } else if (newState === 'NORMAL' && previousState === 'STRESS') {
        BreathingGuide.stop();
      }

      if (this.onStateChange) {
        this.onStateChange(newState, this.heartRate);
      }
    }
  }

  private evaluateStress(): void {
    if (this.state !== 'CHECKING') {
      return;
    }

    const isMoving = this.isMoving();
    const hasGpsSpeed = this.currentSpeed > GPS_SPEED_THRESHOLD;

    if (isMoving || hasGpsSpeed) {
      this.updateState('EXERCISE');
    } else {
      this.updateState('STRESS');
    }
  }

  private startEvaluationTimer(): void {
    if (this.evaluationTimer !== null) {
      clearTimeout(this.evaluationTimer);
    }

    this.checkingStartTime = Date.now();
    this.evaluationTimer = setTimeout(() => {
      this.evaluateStress();
    }, this.config.checkingDurationMs);
  }

  private onHeartRateData(hr: number): void {
    this.heartRate = hr;
    this.addToBuffer(hr);

    if (this.onStateChange) {
      this.onStateChange(this.state, this.heartRate);
    }

    if (this.isElevated()) {
      if (this.state === 'NORMAL') {
        this.updateState('CHECKING');
        this.startEvaluationTimer();
      }
    } else {
      if (this.evaluationTimer !== null) {
        clearTimeout(this.evaluationTimer);
        this.evaluationTimer = null;
      }
      this.updateState('NORMAL');
    }
  }

  async start(): Promise<boolean> {
    if (this.isRunning) {
      return true;
    }

    const availability = await this.checkSensorAvailability();
    if (!availability.heartRate) {
      hilog.error(DOMAIN, TAG, 'HR sensor not available');
      return false;
    }

    try {
      sensor.on(sensor.SensorId.HEART_RATE, (data: sensor.HeartRateResponse) => {
        const hr: number = data.heartRate ?? 0;
        if (hr > 0) {
          this.onHeartRateData(hr);
        }
      }, { interval: 2000000000 });

      this.isRunning = true;
      hilog.info(DOMAIN, TAG, 'HR sensor started');
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start HR sensor: %{public}s', JSON.stringify(err));
      return false;
    }
  }

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

  async startAccelerometer(): Promise<boolean> {
    if (this.isAccelRunning) {
      return true;
    }

    const availability = await this.checkSensorAvailability();
    if (!availability.accelerometer) {
      hilog.error(DOMAIN, TAG, 'Accelerometer not available');
      return false;
    }

    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (data) => {
        const magnitude = Math.sqrt(data.x * data.x + data.y * data.y + data.z * data.z);
        this.accelMagnitude = Math.abs(magnitude - GRAVITY);
      }, { interval: 500000000 });

      this.isAccelRunning = true;
      hilog.info(DOMAIN, TAG, 'Accelerometer started');
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start accelerometer: %{public}s', JSON.stringify(err));
      return false;
    }
  }

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

  async startLocationMonitoring(): Promise<boolean> {
    if (this.isLocationRunning) {
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
        }
      });

      this.isLocationRunning = true;
      hilog.info(DOMAIN, TAG, 'Location monitoring started');
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start location: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  stopLocationMonitoring(): void {
    if (!this.isLocationRunning) return;

    try {
      geoLocationManager.off('locationChange');
      this.isLocationRunning = false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to stop location: %{public}s', JSON.stringify(err));
    }
  }

  isMoving(): boolean {
    return this.accelMagnitude > this.config.accelThreshold;
  }

  getAccelMagnitude(): number {
    return this.accelMagnitude;
  }

  isActive(): boolean {
    return this.isRunning;
  }

  async startAll(): Promise<void> {
    await Promise.all([
      this.start(),
      this.startAccelerometer(),
      this.startLocationMonitoring()
    ]);
  }

  stopAll(): void {
    this.stop();
    this.stopAccelerometer();
    this.stopLocationMonitoring();
  }

  reset(): void {
    if (this.evaluationTimer !== null) {
      clearTimeout(this.evaluationTimer);
      this.evaluationTimer = null;
    }
    this.updateState('NORMAL');
  }

  dismissStressAlert(): void {
    if (this.state === 'STRESS') {
      this.hrBuffer = [];
      this.updateState('NORMAL');
      BreathingGuide.stop();
      hilog.info(DOMAIN, TAG, 'Stress alert dismissed');
    }
  }

  // Test method for demo purposes - simulates stress detection
  async testStress(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Test stress triggered');
    this.heartRate = 115;
    this.accelMagnitude = 0.3; // Stationary
    this.updateState('CHECKING');

    // After short delay, transition to STRESS
    setTimeout(() => {
      if (this.state === 'CHECKING') {
        this.updateState('STRESS');
      }
    }, 1000);
  }
}

export const StressDetector = new StressDetectorClass();

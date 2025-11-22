import { sensor } from '@kit.SensorServiceKit';
import { geoLocationManager } from '@kit.LocationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';

const DOMAIN = 0x0000;
const TAG = 'StressDetector';

const HR_HIGH_THRESHOLD = 100;
const HR_SPIKE_DELTA = 20;
const HR_BUFFER_SIZE = 5;
const ACCEL_MOVEMENT_THRESHOLD = 1.5;
const GRAVITY = 9.81;
const CHECKING_DURATION_MS = 5000;
const GPS_SPEED_THRESHOLD = 1.0;

export type StressState = 'NORMAL' | 'CHECKING' | 'EXERCISE' | 'STRESS';

export type StateChangeCallback = (state: StressState, hr: number) => void;

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
  private evaluationTimer: number | null = null;

  private hrHighThreshold: number = HR_HIGH_THRESHOLD;
  private hrSpikeDelta: number = HR_SPIKE_DELTA;
  private accelThreshold: number = ACCEL_MOVEMENT_THRESHOLD;
  private checkingDurationMs: number = CHECKING_DURATION_MS;

  getHeartRate(): number {
    return this.heartRate;
  }

  getState(): StressState {
    return this.state;
  }

  getSpeed(): number {
    return this.currentSpeed;
  }

  setOnStateChange(callback: StateChangeCallback): void {
    this.onStateChange = callback;
  }

  private getBaseline(): number {
    if (this.hrBuffer.length === 0) return 0;
    let sum = 0;
    for (let i = 0; i < this.hrBuffer.length; i++) {
      sum += this.hrBuffer[i];
    }
    return sum / this.hrBuffer.length;
  }

  isElevated(): boolean {
    const baseline = this.getBaseline();
    const isHigh = this.heartRate > this.hrHighThreshold;
    const isSpike = baseline > 0 && (this.heartRate - baseline) > this.hrSpikeDelta;
    return isHigh || isSpike;
  }

  private addToBuffer(hr: number): void {
    this.hrBuffer.push(hr);
    if (this.hrBuffer.length > HR_BUFFER_SIZE) {
      this.hrBuffer.shift();
    }
  }

  private triggerHapticFeedback(durationMs: number): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: durationMs
      }, {
        id: 0,
        usage: 'alarm'
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Haptic failed');
    }
  }

  private updateState(newState: StressState): void {
    if (this.state !== newState) {
      this.state = newState;
      hilog.info(DOMAIN, TAG, 'State: %{public}s, HR: %{public}d', newState, this.heartRate);

      if (newState === 'STRESS') {
        this.triggerHapticFeedback(200);
      } else if (newState === 'CHECKING') {
        this.triggerHapticFeedback(50);
      }

      if (this.onStateChange !== null) {
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

    this.evaluationTimer = setTimeout(() => {
      this.evaluateStress();
    }, this.checkingDurationMs);
  }

  private onHeartRateData(hr: number): void {
    this.heartRate = hr;
    this.addToBuffer(hr);

    if (this.onStateChange !== null) {
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

  start(): void {
    if (this.isRunning) {
      return;
    }

    try {
      hilog.info(DOMAIN, TAG, 'Starting heart rate sensor...');

      sensor.on(sensor.SensorId.HEART_RATE, (data: sensor.HeartRateResponse) => {
        // Log raw data for debugging
        hilog.info(DOMAIN, TAG, 'HR callback! Raw: %{public}s', JSON.stringify(data));

        // Get heart rate value
        const hr: number = data.heartRate;
        hilog.info(DOMAIN, TAG, 'Parsed HR: %{public}d', hr);

        if (hr > 0) {
          this.onHeartRateData(hr);
        }
      }, { interval: 1000000000 }); // 1 second

      this.isRunning = true;
      hilog.info(DOMAIN, TAG, 'HR sensor subscription OK - waiting for data...');

      // Notify UI we're waiting
      if (this.onStateChange !== null) {
        this.onStateChange('NORMAL', 0);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'HR sensor FAILED: %{public}s', JSON.stringify(err));
      if (this.onStateChange !== null) {
        this.onStateChange('NORMAL', -1);
      }
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
      hilog.error(DOMAIN, TAG, 'Failed to stop HR sensor');
    }
  }

  startAccelerometer(): void {
    if (this.isAccelRunning) {
      return;
    }

    try {
      hilog.info(DOMAIN, TAG, 'Starting accelerometer...');

      sensor.on(sensor.SensorId.ACCELEROMETER, (data: sensor.AccelerometerResponse) => {
        const magnitude = Math.sqrt(data.x * data.x + data.y * data.y + data.z * data.z);
        this.accelMagnitude = Math.abs(magnitude - GRAVITY);
        // Log first few readings
        hilog.info(DOMAIN, TAG, 'Accel: x=%{public}f y=%{public}f z=%{public}f mag=%{public}f',
          data.x, data.y, data.z, this.accelMagnitude);
      }, { interval: 500000000 });

      this.isAccelRunning = true;
      hilog.info(DOMAIN, TAG, 'Accelerometer subscription OK');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Accelerometer FAILED: %{public}s', JSON.stringify(err));
    }
  }

  stopAccelerometer(): void {
    if (!this.isAccelRunning) return;

    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
      this.isAccelRunning = false;
      hilog.info(DOMAIN, TAG, 'Accelerometer stopped');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to stop accelerometer');
    }
  }

  startLocationMonitoring(): void {
    if (this.isLocationRunning) {
      return;
    }

    try {
      const request: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
        scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
        maxAccuracy: 50
      };

      geoLocationManager.on('locationChange', request, (location: geoLocationManager.Location) => {
        if (location.speed !== undefined) {
          this.currentSpeed = location.speed;
        }
      });

      this.isLocationRunning = true;
      hilog.info(DOMAIN, TAG, 'Location started');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start location');
    }
  }

  stopLocationMonitoring(): void {
    if (!this.isLocationRunning) return;

    try {
      geoLocationManager.off('locationChange');
      this.isLocationRunning = false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to stop location');
    }
  }

  isMoving(): boolean {
    return this.accelMagnitude > this.accelThreshold;
  }

  getAccelMagnitude(): number {
    return this.accelMagnitude;
  }

  isActive(): boolean {
    return this.isRunning;
  }

  startAll(): void {
    this.start();
    this.startAccelerometer();
    this.startLocationMonitoring();
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
      hilog.info(DOMAIN, TAG, 'Stress alert dismissed');
    }
  }

  testStress(): void {
    hilog.info(DOMAIN, TAG, 'Test stress triggered');
    this.heartRate = 115;
    this.accelMagnitude = 0.3;
    this.updateState('CHECKING');

    setTimeout(() => {
      if (this.state === 'CHECKING') {
        this.updateState('STRESS');
      }
    }, 1000);
  }
}

export const StressDetector = new StressDetectorClass();

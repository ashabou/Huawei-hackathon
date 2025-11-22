import { describe, it, expect } from '@ohos/hypium';

class MockStressDetectorLogic {
  private hrBuffer: number[] = [];
  private readonly HR_BUFFER_SIZE = 5;
  private readonly HR_HIGH_THRESHOLD = 100;
  private readonly HR_SPIKE_DELTA = 20;
  private readonly ACCEL_THRESHOLD = 1.5;

  getBaseline(): number {
    if (this.hrBuffer.length === 0) return 0;
    let sum = 0;
    for (let i = 0; i < this.hrBuffer.length; i++) {
      sum += this.hrBuffer[i];
    }
    return sum / this.hrBuffer.length;
  }

  addToBuffer(hr: number): void {
    this.hrBuffer.push(hr);
    if (this.hrBuffer.length > this.HR_BUFFER_SIZE) {
      this.hrBuffer.shift();
    }
  }

  isElevated(currentHr: number): boolean {
    const baseline = this.getBaseline();
    const isHigh = currentHr > this.HR_HIGH_THRESHOLD;
    const isSpike = baseline > 0 && (currentHr - baseline) > this.HR_SPIKE_DELTA;
    return isHigh || isSpike;
  }

  isMoving(accelMagnitude: number): boolean {
    return accelMagnitude > this.ACCEL_THRESHOLD;
  }

  getBufferLength(): number {
    return this.hrBuffer.length;
  }
}

function createDetector(): MockStressDetectorLogic {
  return new MockStressDetectorLogic();
}

export default function localUnitTest() {
  describe('StressDetectorTests', () => {

    it('baseline_empty_buffer_returns_zero', 0, () => {
      const detector = createDetector();
      const baseline = detector.getBaseline();
      expect(baseline).assertEqual(0);
    });

    it('baseline_single_value', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(75);
      const baseline = detector.getBaseline();
      expect(baseline).assertEqual(75);
    });

    it('baseline_multiple_values', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(70);
      detector.addToBuffer(80);
      detector.addToBuffer(75);
      const baseline = detector.getBaseline();
      expect(baseline).assertEqual(75);
    });

    it('baseline_rolling_average', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(60);
      detector.addToBuffer(62);
      detector.addToBuffer(64);
      detector.addToBuffer(66);
      detector.addToBuffer(68);
      detector.addToBuffer(70);
      detector.addToBuffer(72);
      expect(detector.getBufferLength()).assertEqual(5);
      const baseline = detector.getBaseline();
      expect(baseline).assertEqual(68);
    });

    it('elevated_above_threshold', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(70);
      detector.addToBuffer(72);
      detector.addToBuffer(68);
      const result = detector.isElevated(105);
      expect(result).assertTrue();
    });

    it('elevated_at_threshold_is_false', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(70);
      expect(detector.isElevated(100)).assertFalse();
    });

    it('elevated_above_threshold_is_true', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(70);
      expect(detector.isElevated(101)).assertTrue();
    });

    it('elevated_spike_detection', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      const result = detector.isElevated(95);
      expect(result).assertTrue();
    });

    it('not_elevated_normal_hr', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      const result = detector.isElevated(75);
      expect(result).assertFalse();
    });

    it('spike_with_empty_buffer', 0, () => {
      const detector = createDetector();
      const result = detector.isElevated(95);
      expect(result).assertFalse();
    });

    it('moving_above_threshold', 0, () => {
      const detector = createDetector();
      const result = detector.isMoving(2.0);
      expect(result).assertTrue();
    });

    it('stationary_below_threshold', 0, () => {
      const detector = createDetector();
      const result = detector.isMoving(0.5);
      expect(result).assertFalse();
    });

    it('at_threshold_is_false', 0, () => {
      const detector = createDetector();
      const result = detector.isMoving(1.5);
      expect(result).assertFalse();
    });

    it('slightly_above_threshold', 0, () => {
      const detector = createDetector();
      const result = detector.isMoving(1.51);
      expect(result).assertTrue();
    });

    it('buffer_max_size', 0, () => {
      const detector = createDetector();
      for (let i = 0; i < 10; i++) {
        detector.addToBuffer(70 + i);
      }
      expect(detector.getBufferLength()).assertEqual(5);
    });

    it('buffer_removes_oldest', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(100);
      detector.addToBuffer(50);
      detector.addToBuffer(50);
      detector.addToBuffer(50);
      detector.addToBuffer(50);
      detector.addToBuffer(50);
      const baseline = detector.getBaseline();
      expect(baseline).assertEqual(50);
    });

    it('exercise_elevated_and_moving', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      const isElevated = detector.isElevated(110);
      const isMoving = detector.isMoving(3.0);
      expect(isElevated).assertTrue();
      expect(isMoving).assertTrue();
    });

    it('stress_elevated_and_stationary', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      const isElevated = detector.isElevated(110);
      const isMoving = detector.isMoving(0.5);
      expect(isElevated).assertTrue();
      expect(isMoving).assertFalse();
    });

    it('normal_not_elevated', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      detector.addToBuffer(70);
      const isElevated = detector.isElevated(72);
      expect(isElevated).assertFalse();
    });

    it('zero_hr_reading', 0, () => {
      const detector = createDetector();
      detector.addToBuffer(0);
      const baseline = detector.getBaseline();
      expect(baseline).assertEqual(0);
    });

    it('very_high_hr', 0, () => {
      const detector = createDetector();
      const result = detector.isElevated(200);
      expect(result).assertTrue();
    });

    it('negative_acceleration', 0, () => {
      const detector = createDetector();
      const result = detector.isMoving(-1.0);
      expect(result).assertFalse();
    });
  });
}

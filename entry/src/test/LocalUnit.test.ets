import { describe, beforeEach, afterEach, it, expect } from '@ohos/hypium';

/**
 * Unit tests for StressWatch application
 * Tests core business logic without requiring device sensors
 */

// Mock the StressDetector class logic for testing (without sensor dependencies)
class MockStressDetectorLogic {
  private hrBuffer: number[] = [];
  private readonly HR_BUFFER_SIZE = 5;
  private readonly HR_HIGH_THRESHOLD = 100;
  private readonly HR_SPIKE_DELTA = 20;
  private readonly ACCEL_THRESHOLD = 1.5;

  getBaseline(): number {
    if (this.hrBuffer.length === 0) return 0;
    const sum = this.hrBuffer.reduce((a, b) => a + b, 0);
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

  clearBuffer(): void {
    this.hrBuffer = [];
  }

  getBufferLength(): number {
    return this.hrBuffer.length;
  }
}

export default function localUnitTest() {
  describe('StressDetector Logic Tests', () => {
    let detector: MockStressDetectorLogic;

    beforeEach(() => {
      detector = new MockStressDetectorLogic();
    });

    afterEach(() => {
      detector.clearBuffer();
    });

    describe('getBaseline()', () => {
      it('should return 0 when buffer is empty', 0, () => {
        const baseline = detector.getBaseline();
        expect(baseline).assertEqual(0);
      });

      it('should return correct average for single value', 0, () => {
        detector.addToBuffer(75);
        const baseline = detector.getBaseline();
        expect(baseline).assertEqual(75);
      });

      it('should calculate correct average for multiple values', 0, () => {
        detector.addToBuffer(70);
        detector.addToBuffer(80);
        detector.addToBuffer(75);
        const baseline = detector.getBaseline();
        expect(baseline).assertEqual(75);
      });

      it('should maintain rolling average with buffer size limit', 0, () => {
        // Add 7 values - buffer size is 5
        detector.addToBuffer(60);
        detector.addToBuffer(62);
        detector.addToBuffer(64);
        detector.addToBuffer(66);
        detector.addToBuffer(68);
        detector.addToBuffer(70);
        detector.addToBuffer(72);

        // Should only contain last 5: 64, 66, 68, 70, 72
        expect(detector.getBufferLength()).assertEqual(5);

        // Average should be (64+66+68+70+72)/5 = 68
        const baseline = detector.getBaseline();
        expect(baseline).assertEqual(68);
      });
    });

    describe('isElevated()', () => {
      it('should return true when HR exceeds high threshold', 0, () => {
        detector.addToBuffer(70);
        detector.addToBuffer(72);
        detector.addToBuffer(68);
        const result = detector.isElevated(105);
        expect(result).assertTrue();
      });

      it('should return false when HR at exactly threshold', 0, () => {
        detector.addToBuffer(70);
        expect(detector.isElevated(100)).assertFalse();
      });

      it('should return true when HR above threshold', 0, () => {
        detector.addToBuffer(70);
        expect(detector.isElevated(101)).assertTrue();
      });

      it('should return true when HR spikes above baseline', 0, () => {
        // Pre-fill buffer to establish baseline ~70
        detector.addToBuffer(70);
        detector.addToBuffer(70);
        detector.addToBuffer(70);
        // Baseline is 70, delta threshold is 20, so 91+ triggers spike
        const result = detector.isElevated(95);
        expect(result).assertTrue();
      });

      it('should return false for normal HR within threshold', 0, () => {
        detector.addToBuffer(70);
        detector.addToBuffer(70);
        detector.addToBuffer(70);
        const result = detector.isElevated(75);
        expect(result).assertFalse();
      });

      it('should handle spike detection with empty buffer', 0, () => {
        // With empty buffer, baseline is 0
        // isSpike requires baseline > 0, so should only check threshold
        const result = detector.isElevated(95);
        expect(result).assertFalse(); // 95 < 100, and no spike check with 0 baseline
      });
    });

    describe('isMoving()', () => {
      it('should return true when acceleration exceeds threshold', 0, () => {
        const result = detector.isMoving(2.0);
        expect(result).assertTrue();
      });

      it('should return false when stationary', 0, () => {
        const result = detector.isMoving(0.5);
        expect(result).assertFalse();
      });

      it('should return false at exactly threshold', 0, () => {
        const result = detector.isMoving(1.5);
        expect(result).assertFalse();
      });

      it('should return true slightly above threshold', 0, () => {
        const result = detector.isMoving(1.51);
        expect(result).assertTrue();
      });
    });

    describe('Buffer Management', () => {
      it('should not exceed buffer size of 5', 0, () => {
        for (let i = 0; i < 10; i++) {
          detector.addToBuffer(70 + i);
        }
        expect(detector.getBufferLength()).assertEqual(5);
      });

      it('should remove oldest values when buffer is full', 0, () => {
        detector.addToBuffer(100);
        detector.addToBuffer(50);
        detector.addToBuffer(50);
        detector.addToBuffer(50);
        detector.addToBuffer(50);
        // Buffer: [100, 50, 50, 50, 50], baseline = 60

        detector.addToBuffer(50);
        // Buffer: [50, 50, 50, 50, 50], baseline = 50

        const baseline = detector.getBaseline();
        expect(baseline).assertEqual(50);
      });
    });

    describe('State Transition Scenarios', () => {
      it('should identify exercise: elevated HR + movement', 0, () => {
        detector.addToBuffer(70);
        detector.addToBuffer(70);
        detector.addToBuffer(70);

        const isElevated = detector.isElevated(110);
        const isMoving = detector.isMoving(3.0);

        expect(isElevated).assertTrue();
        expect(isMoving).assertTrue();
      });

      it('should identify stress: elevated HR + stationary', 0, () => {
        detector.addToBuffer(70);
        detector.addToBuffer(70);
        detector.addToBuffer(70);

        const isElevated = detector.isElevated(110);
        const isMoving = detector.isMoving(0.5);

        expect(isElevated).assertTrue();
        expect(isMoving).assertFalse();
      });

      it('should identify normal: normal HR', 0, () => {
        detector.addToBuffer(70);
        detector.addToBuffer(70);
        detector.addToBuffer(70);

        const isElevated = detector.isElevated(72);
        expect(isElevated).assertFalse();
      });
    });

    describe('Edge Cases', () => {
      it('should handle zero HR reading', 0, () => {
        detector.addToBuffer(0);
        const baseline = detector.getBaseline();
        expect(baseline).assertEqual(0);
      });

      it('should handle very high HR reading', 0, () => {
        const result = detector.isElevated(200);
        expect(result).assertTrue();
      });

      it('should handle negative acceleration safely', 0, () => {
        const result = detector.isMoving(-1.0);
        expect(result).assertFalse();
      });
    });
  });
}

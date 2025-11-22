# BRUTAL CODE REVIEW: StressWatch HarmonyOS Wearable App

**Reviewer**: Senior Smartwatch Software Engineer
**Date**: 2025-11-22
**Target SDK**: HarmonyOS 5.1.0 (API 18)
**IDE**: DevEco Studio

---

## Executive Summary

This is a **hackathon-level MVP** for a stress detection smartwatch app targeting HarmonyOS wearables. While the core concept is sound, the implementation is **severely incomplete**, contains **critical architectural flaws**, and has **zero meaningful tests**. This code is **NOT production-ready**.

| Metric | Status |
|--------|--------|
| Functional Completeness | 20% |
| Test Coverage | 0% |
| Production Readiness | NO |
| Security | CRITICAL ISSUES |

---

## 1. ARCHITECTURE ANALYSIS

### Project Structure
```
Huawei-hackathon/
├── AppScope/                              # App-level resources
├── entry/src/main/ets/
│   ├── entryability/EntryAbility.ets      # App lifecycle handler
│   ├── entrybackupability/                # Backup handler (boilerplate)
│   ├── pages/Index.ets                    # UI (BROKEN - not connected)
│   └── services/StressDetector.ets        # Core logic (DISCONNECTED)
├── entry/src/ohosTest/                    # Instrumentation tests (USELESS)
├── entry/src/test/                        # Unit tests (USELESS)
└── build-profile.json5                    # Build config (CONTAINS SECRETS!)
```

### CRITICAL ISSUE #1: Service Not Connected to UI

**File**: `entry/src/main/ets/pages/Index.ets`

```typescript
@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  @State heartRate: number = 0;

  build() {
    Column() {
      Text(`Current heart rate: ${this.heartRate} bpm`)
      Button('Start')
        .onClick(() => {
          console.log('Heart rate: ', this.heartRate)  // LOGS 0 FOREVER!
        })
    }
  }
}
```

**Problem**: The `StressDetector` service is **NEVER IMPORTED or USED** in the UI. The button logs the initial value (0) forever. The `@State heartRate` is never updated.

**Expected Implementation**:
```typescript
import { StressDetector, StressState } from '../services/StressDetector';

@Entry
@Component
struct Index {
  @State heartRate: number = 0;
  @State stressState: StressState = 'NORMAL';

  aboutToAppear() {
    StressDetector.setOnStateChange((state, hr) => {
      this.heartRate = hr;
      this.stressState = state;
    });
    StressDetector.start();
    StressDetector.startAccelerometer();
  }

  aboutToDisappear() {
    StressDetector.stop();
    StressDetector.stopAccelerometer();
  }
  // ...
}
```

---

## 2. STRESS DETECTOR SERVICE ANALYSIS

**File**: `entry/src/main/ets/services/StressDetector.ets`

### What Works
- Rolling average HR baseline calculation (lines 44-48)
- Spike detection logic (lines 51-56)
- Accelerometer magnitude calculation (lines 138-142)
- State machine concept with callback system

### CRITICAL ISSUES

#### Issue #2: State Machine Logic is Incomplete (Line 88-93)

```typescript
if (this.isElevated()) {
  this.updateState('CHECKING');
} else {
  this.updateState('NORMAL');
}
```

The `CHECKING` state **NEVER transitions** to `STRESS` or `EXERCISE`. The comment at line 88 mentions `evaluateStress()` but **this function doesn't exist**.

**Missing Logic**:
```typescript
// This should exist but doesn't:
private evaluateStress(): void {
  if (this.state === 'CHECKING') {
    if (this.isMoving()) {
      this.updateState('EXERCISE');
    } else {
      // User is stationary with elevated HR = stress
      this.updateState('STRESS');
    }
  }
}
```

#### Issue #3: Potential Memory Leak (Lines 104-114)

```typescript
sensor.on(sensor.SensorId.HEART_RATE, (data) => {
  // ...
}, { interval: 2000000000 });
this.isRunning = true;
```

If `start()` is called multiple times without `stop()`, **multiple listeners stack up**. The `isRunning` flag helps but doesn't prevent edge cases during rapid lifecycle transitions.

#### Issue #4: No Sensor Availability Check

No check for `sensor.getSensorList()` to verify HR sensor exists on device. On non-wearable devices, emulators without sensor support, or devices without HR sensors, this silently fails.

**Should Add**:
```typescript
private async checkSensorAvailability(): Promise<boolean> {
  try {
    const sensors = sensor.getSensorList(sensor.SensorId.HEART_RATE);
    return sensors.length > 0;
  } catch {
    return false;
  }
}
```

#### Issue #5: Race Condition

The accelerometer `isMoving()` check (line 166-168) and HR `isElevated()` check operate independently with no synchronization. Movement state could change between the check and the decision point.

#### Issue #6: Hardcoded Magic Numbers (Lines 8-12)

```typescript
const HR_HIGH_THRESHOLD = 100;        // Why 100? Citation needed
const HR_SPIKE_DELTA = 20;            // Medical basis?
const ACCEL_MOVEMENT_THRESHOLD = 1.5; // Tested on real hardware?
const GRAVITY = 9.8;                  // Should be 9.81 m/s²
```

These thresholds need medical/research backing and should be configurable per user (age, fitness level, etc.).

---

## 3. SECURITY VULNERABILITIES

### CRITICAL: Signing Credentials in Git

**File**: `build-profile.json5` (Lines 8-14)

```json5
"material": {
  "certpath": "/Users/mt/.ohos/config/default_MyApplication_...cer",
  "keyPassword": "0000001B03485FF7FDA27B8F1A7C2B3081D3F272421AC443...",
  "storePassword": "0000001BDA1770030DEE2E3D99E9036687A90D76B37392D8..."
}
```

**SIGNING PASSWORDS ARE COMMITTED TO GIT!** Even if encrypted by DevEco Studio, this is a major security risk. These should be:
- Stored in environment variables
- Managed via CI/CD secrets
- Never committed to version control

**Fix**: Add to `.gitignore`:
```
build-profile.json5
```

Or use placeholder values and document setup in README.

### Permission Over-Request

**File**: `entry/src/main/module.json5` (Lines 10-37)

```json5
"requestPermissions": [
  { "name": "ohos.permission.HEART_RATE" },           // USED
  { "name": "ohos.permission.ACTIVITY_MOTION" },      // NOT USED IN CODE
  { "name": "ohos.permission.APPROXIMATELY_LOCATION" }, // NOT USED IN CODE
  { "name": "ohos.permission.VIBRATE" }               // NOT USED IN CODE
]
```

Location, activity motion, and vibrate permissions are requested but **never used** in the codebase. This:
1. Violates principle of least privilege
2. Will cause app store review flags
3. Degrades user trust

---

## 4. UI/UX CRITIQUE

### Wearable Design Violations

| Issue | Description |
|-------|-------------|
| Layout | No circular/watch-face-optimized layout |
| Screen Size | No consideration for 466x466 or 454x454 watch displays |
| Navigation | No swipe gestures or crown/bezel support |
| Always-On | No ambient mode / always-on display support |
| Placeholder | "Hello World" text is unprofessional |

### Missing UI Elements

- No visual stress level indicator (color coding, gauge, etc.)
- No historical HR graph
- No settings screen for thresholds
- No breathing exercise intervention
- No haptic feedback on stress detection
- No notification when stress is detected

### Recommended Wearable UI Pattern

```typescript
@Entry
@Component
struct Index {
  build() {
    Stack() {
      // Circular background
      Circle()
        .width('100%')
        .height('100%')
        .fill(this.getBackgroundColor())

      Column() {
        // Large HR display
        Text(this.heartRate.toString())
          .fontSize(48)
          .fontWeight(FontWeight.Bold)

        Text('BPM')
          .fontSize(14)

        // Status indicator
        Text(this.stressState)
          .fontSize(16)
          .fontColor(this.getStateColor())
      }
    }
  }
}
```

---

## 5. TEST COVERAGE: ZERO ACTUAL TESTS

### Existing Tests Are Boilerplate

**File**: `entry/src/ohosTest/ets/test/Ability.test.ets`

```typescript
it('assertContain', 0, () => {
  let a = 'abc';
  let b = 'b';
  expect(a).assertContain(b);
  expect(a).assertEqual(a);
})
```

This tests whether `'abc'` contains `'b'`. It tests **NOTHING** about the actual application. This is DevEco Studio auto-generated boilerplate.

### Required Test Cases

#### Unit Tests for StressDetector

```typescript
describe('StressDetector', () => {
  describe('getBaseline()', () => {
    it('should return 0 when buffer is empty', () => {});
    it('should calculate average of buffer values', () => {});
    it('should use only last 5 readings', () => {});
  });

  describe('isElevated()', () => {
    it('should return true when HR > 100', () => {});
    it('should return true when HR spikes > 20 above baseline', () => {});
    it('should return false for normal readings', () => {});
    it('should handle edge case at exactly 100 BPM', () => {});
  });

  describe('isMoving()', () => {
    it('should return true when accel > 1.5 m/s² deviation', () => {});
    it('should return false when stationary', () => {});
  });

  describe('state transitions', () => {
    it('should transition NORMAL -> CHECKING on elevated HR', () => {});
    it('should transition CHECKING -> EXERCISE when moving', () => {});
    it('should transition CHECKING -> STRESS when stationary', () => {});
    it('should call callback on state change', () => {});
  });
});
```

#### Integration Tests

```typescript
describe('EntryAbility', () => {
  it('should request all required permissions on create', () => {});
  it('should handle permission denial gracefully', () => {});
});
```

---

## 6. HOW TO TEST THIS CODE

### A. Setup Development Environment

1. **Install DevEco Studio 4.0+** (NEXT for HarmonyOS 5.x)
   - Download from: https://developer.huawei.com/consumer/en/deveco-studio/

2. **Install HarmonyOS SDK 5.1.0 (API 18)**
   - DevEco Studio → Settings → SDK Manager → HarmonyOS → 5.1.0

3. **Configure Signing**
   - Generate debug signing config
   - Remove hardcoded passwords from `build-profile.json5`

### B. Run Unit Tests (Local)

```bash
# Via DevEco Studio
# Right-click entry/src/test → Run 'localUnitTest'

# Via CLI (hvigor)
cd /path/to/Huawei-hackathon
hvigorw testArkTSDebug --no-daemon
```

### C. Run Instrumentation Tests (On Device)

```bash
# Build test HAP
hvigorw assembleHap --mode module -p module=entry -p product=default -p buildMode=debug

# Connect device/emulator
hdc list targets

# Install
hdc install entry/build/default/outputs/default/entry-default-signed.hap

# Run instrumented tests
hdc shell aa test -b com.example.myapplication -m entry_test
```

### D. Manual Testing on Wearable

#### Prerequisites
- Huawei Watch GT3/GT4, WATCH 4 series, or compatible wearable
- USB debugging enabled on watch
- Paired with HarmonyOS phone for permission dialogs

#### Deploy
```bash
# Build release HAP
hvigorw assembleHap -p product=default

# Install to watch
hdc -t <watch-serial> install entry/build/default/outputs/default/entry-default-signed.hap

# Launch app
hdc shell aa start -a EntryAbility -b com.example.myapplication
```

#### Test Scenarios

| # | Scenario | Steps | Expected | Actual |
|---|----------|-------|----------|--------|
| 1 | Normal Rest | Sit still, HR ~60-80 | State: NORMAL | N/A (not implemented) |
| 2 | Elevated HR | Exercise to raise HR >100 | State: CHECKING | N/A |
| 3 | Exercise Detection | Walk/run with elevated HR | State: EXERCISE | NOT IMPLEMENTED |
| 4 | Stress Detection | Sit still with elevated HR | State: STRESS | NOT IMPLEMENTED |
| 5 | Permission Denial | Deny HR permission | Graceful error message | Untested |

#### View Logs
```bash
# All app logs
hdc hilog | grep -E "(StressDetector|StressWatch)"

# Real-time HR data
hdc hilog | grep "HR:"
```

### E. Emulator Testing with Mock Sensors

1. Create mock configuration in `entry/src/mock/mock-config.json5`:

```json5
{
  "mockList": [
    {
      "name": "@kit.SensorServiceKit",
      "functions": {
        "sensor.on": {
          "HEART_RATE": {
            "data": [
              { "heartRate": 72 },
              { "heartRate": 75 },
              { "heartRate": 110 },
              { "heartRate": 115 },
              { "heartRate": 85 }
            ],
            "interval": 2000
          }
        }
      }
    }
  ]
}
```

2. Enable mock in DevEco Studio:
   - Build Configuration → Enable Mock

### F. Linting

```bash
# Run code linter (uses code-linter.json5 config)
hvigorw lint

# Security rules configured:
# - @security/no-unsafe-aes: error
# - @security/no-unsafe-hash: error
# - etc.
```

---

## 7. ADDITIONAL ISSUES

### Bundle Name is Generic
**File**: `AppScope/app.json5`
```json5
"bundleName": "com.example.myapplication"
```
Should be: `com.huawei.stresswatch` or organization-specific name.

### Singleton Anti-Pattern
```typescript
export const StressDetector = new StressDetectorClass();
```
Makes unit testing difficult. Should use dependency injection:
```typescript
export class StressDetectorClass { ... }
export const createStressDetector = () => new StressDetectorClass();
```

### Inconsistent Logging Tags
```typescript
// StressDetector.ets
const TAG = 'StressDetector';

// EntryAbility.ets
const TAG = 'StressWatch';

// EntryBackupAbility.ets
const TAG = 'testTag';  // LAZY!
```

### Dead Code
```typescript
@State message: string = 'Hello World';  // Never displayed or used
```

---

## 8. SEVERITY MATRIX

| Issue | Severity | Type | File:Line |
|-------|----------|------|-----------|
| Service not connected to UI | CRITICAL | Bug | Index.ets:* |
| State machine incomplete | CRITICAL | Bug | StressDetector.ets:88-93 |
| Signing passwords in git | CRITICAL | Security | build-profile.json5:8-14 |
| No actual tests | HIGH | Quality | */test/*.ets |
| No sensor availability check | HIGH | Bug | StressDetector.ets:103 |
| Unused permissions requested | MEDIUM | Security | module.json5:10-37 |
| Hardcoded thresholds | MEDIUM | Maintainability | StressDetector.ets:8-12 |
| Generic bundle name | LOW | Config | app.json5:3 |
| Inconsistent log tags | LOW | Quality | Multiple |

---

## 9. RECOMMENDATIONS

### P0 - Must Fix Before Any Testing

1. **Connect StressDetector to Index.ets**
   - Import service, call `start()` in `aboutToAppear()`
   - Bind `@State` variables via callback

2. **Implement state transition logic**
   - Add `evaluateStress()` method
   - Call it from `onHeartRateData()` when in CHECKING state

3. **Remove signing credentials from git**
   - Add `build-profile.json5` to `.gitignore`
   - Use environment variables

4. **Write actual unit tests**
   - Cover `StressDetector` class methods
   - Test state transitions
   - Test edge cases

### P1 - Should Fix

5. Add sensor availability check before subscription
6. Implement location-based speed detection
7. Add haptic feedback on stress detection
8. Create watch-optimized circular UI
9. Remove unused permission requests

### P2 - Nice to Have

10. Historical HR data persistence
11. Breathing exercise intervention
12. Cloud sync capability
13. Configurable threshold profiles

---

## Conclusion

This codebase demonstrates understanding of HarmonyOS wearable concepts but fails at basic implementation. The **StressDetector service is well-designed but completely disconnected from the UI**, making the app non-functional. Combined with security issues and zero test coverage, this requires significant work before it can be considered even MVP-ready.

**Estimated effort to make functional**: 2-3 days for an experienced HarmonyOS developer.

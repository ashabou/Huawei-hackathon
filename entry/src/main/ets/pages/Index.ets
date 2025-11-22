import { StressDetector, StressState } from '../services/StressDetector';
import { BreathingGuide } from '../services/BreathingGuide';

@Entry
@Component
struct Index {
  // === HR Monitoring State ===
  @State heartRate: number = 0;
  @State state: StressState = 'NORMAL';
  @State isMonitoring: boolean = false;
  @State statusMessage: string = 'Starting...';
  @State sensorError: boolean = false;

  // === Breathing UI State ===
  @State showBreathingUI: boolean = false;
  @State circleSize: number = 120;
  @State circleOpacity: number = 0.6;
  @State labelGlow: number = 0.85;
  @State breathLabel: string = 'Breathe In';
  @State circleColor: string = '#4ADFFF';

  // Breathing animation internals
  private breathPhase: string = 'inhale';
  private breathTimerStep: number = 0;
  private breathTimerId: number = -1;
  private r: number = 74;
  private g: number = 223;
  private b: number = 255;

  // Colors for each state
  private getStateColor(): ResourceColor {
    switch (this.state) {
      case 'NORMAL': return '#4CAF50';
      case 'CHECKING': return '#FFC107';
      case 'EXERCISE': return '#2196F3';
      case 'STRESS': return '#F44336';
      default: return '#9E9E9E';
    }
  }

  private getStatusMessage(): string {
    switch (this.state) {
      case 'NORMAL': return 'All good';
      case 'CHECKING': return 'Checking...';
      case 'EXERCISE': return 'Exercise detected';
      case 'STRESS': return 'Breathe...';
      default: return 'Ready';
    }
  }

  // Helper for smooth color transitions
  private approach(current: number, target: number, speed: number): number {
    if (current < target) return current + speed;
    if (current > target) return current - speed;
    return current;
  }

  private toHex(x: number): string {
    const val = Math.max(0, Math.min(255, Math.round(x)));
    const hex = val.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }

  // Start breathing animation
  private startBreathingAnimation(): void {
    if (this.breathTimerId !== -1) return;

    // Reset to initial state
    this.circleSize = 120;
    this.circleOpacity = 0.6;
    this.labelGlow = 0.85;
    this.breathPhase = 'inhale';
    this.breathTimerStep = 0;
    this.r = 74;
    this.g = 223;
    this.b = 255;

    this.breathTimerId = setInterval(() => {
      this.breathTimerStep++;

      // Phase logic
      if (this.breathPhase === 'inhale') {
        this.circleSize += 1.6;
        this.circleOpacity += 0.004;
        this.labelGlow += 0.002;
        this.breathLabel = 'Breathe In';

        if (this.breathTimerStep >= 50) {
          this.breathPhase = 'hold';
          this.breathTimerStep = 0;
        }
      } else if (this.breathPhase === 'hold') {
        this.breathLabel = 'Hold';
        if (this.breathTimerStep >= 70) {
          this.breathPhase = 'exhale';
          this.breathTimerStep = 0;
        }
      } else if (this.breathPhase === 'exhale') {
        this.circleSize -= 1.0;
        this.circleOpacity -= 0.004;
        this.labelGlow -= 0.002;
        this.breathLabel = 'Breathe Out';

        if (this.breathTimerStep >= 80) {
          this.breathPhase = 'inhale';
          this.breathTimerStep = 0;
        }
      }

      // Color targets
      let targetR = 74;
      let targetG = 223;
      let targetB = 255;

      if (this.breathPhase === 'inhale') {
        targetR = 74;
        targetG = 223;
        targetB = 255;
      } else if (this.breathPhase === 'hold') {
        targetR = 150;
        targetG = 240;
        targetB = 255;
      } else {
        targetR = 57;
        targetG = 198;
        targetB = 232;
      }

      // Smooth color transition
      this.r = this.approach(this.r, targetR, 1.5);
      this.g = this.approach(this.g, targetG, 1.5);
      this.b = this.approach(this.b, targetB, 1.5);

      this.circleColor = '#' + this.toHex(this.r) + this.toHex(this.g) + this.toHex(this.b);

      // Clamps
      if (this.circleOpacity > 0.9) this.circleOpacity = 0.9;
      if (this.circleOpacity < 0.4) this.circleOpacity = 0.4;
      if (this.labelGlow > 1.0) this.labelGlow = 1.0;
      if (this.labelGlow < 0.5) this.labelGlow = 0.5;
      if (this.circleSize < 120) this.circleSize = 120;
      if (this.circleSize > 240) this.circleSize = 240;
    }, 100);
  }

  // Stop breathing animation
  private stopBreathingAnimation(): void {
    if (this.breathTimerId !== -1) {
      clearInterval(this.breathTimerId);
      this.breathTimerId = -1;
    }
  }

  // Dismiss breathing UI and return to monitoring
  private dismissBreathingUI(): void {
    this.stopBreathingAnimation();
    this.showBreathingUI = false;
    StressDetector.dismissStressAlert();
  }

  aboutToAppear(): void {
    this.startMonitoring();
  }

  aboutToDisappear(): void {
    this.stopBreathingAnimation();
  }

  private startMonitoring(): void {
    StressDetector.setOnStateChange((newState: StressState, hr: number) => {
      if (hr === -1) {
        this.sensorError = true;
        this.statusMessage = 'Sensor unavailable';
        return;
      }

      this.sensorError = false;
      this.state = newState;
      this.heartRate = hr;
      this.statusMessage = this.getStatusMessage();

      // Auto-show breathing UI when stress detected
      if (newState === 'STRESS' && !this.showBreathingUI) {
        this.showBreathingUI = true;
        this.startBreathingAnimation();
      }
    });

    StressDetector.start();
    StressDetector.startAccelerometer();
    this.isMonitoring = true;
    this.statusMessage = 'Monitoring...';
  }

  private stopMonitoring(): void {
    StressDetector.stop();
    StressDetector.stopAccelerometer();
    BreathingGuide.stop();
    this.stopBreathingAnimation();
    this.showBreathingUI = false;
    this.isMonitoring = false;
    this.state = 'NORMAL';
    this.heartRate = 0;
    this.statusMessage = 'Tap Start to begin';
  }

  private triggerTestStress(): void {
    this.statusMessage = 'Testing...';
    StressDetector.testStress();
  }

  // === Breathing UI ===
  @Builder
  BreathingUI() {
    Column() {
      Stack() {
        Circle()
          .width(this.circleSize)
          .height(this.circleSize)
          .fill(this.circleColor)
          .opacity(this.circleOpacity)

        Text(this.breathLabel)
          .fontSize(22)
          .fontColor('#E8FAFF')
          .fontWeight(FontWeight.Medium)
          .opacity(this.labelGlow)
      }

      // Dismiss button
      Button('Done')
        .width(80)
        .height(36)
        .fontSize(14)
        .backgroundColor('#2196F3')
        .margin({ top: 40 })
        .onClick(() => {
          this.dismissBreathingUI();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#071A28')
  }

  // === HR Monitoring UI ===
  @Builder
  MonitoringUI() {
    Column() {
      Text(this.sensorError ? 'ERR' : (this.heartRate > 0 ? `${this.heartRate}` : '--'))
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.sensorError ? '#FF5722' : this.getStateColor())

      Text('bpm')
        .fontSize(14)
        .fontColor('#888888')
        .margin({ bottom: 12 })

      Circle()
        .width(12)
        .height(12)
        .fill(this.getStateColor())
        .margin({ bottom: 4 })

      Text(this.statusMessage)
        .fontSize(14)
        .fontColor(this.getStateColor())
        .margin({ bottom: 16 })

      Row() {
        Button(this.isMonitoring ? 'Stop' : 'Start')
          .width(70)
          .height(32)
          .fontSize(12)
          .backgroundColor(this.isMonitoring ? '#666666' : '#4CAF50')
          .onClick(() => {
            if (this.isMonitoring) {
              this.stopMonitoring();
            } else {
              this.startMonitoring();
            }
          })

        Button('Test')
          .width(50)
          .height(32)
          .fontSize(12)
          .backgroundColor('#FF9800')
          .margin({ left: 8 })
          .onClick(() => {
            this.triggerTestStress();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#1a1a1a')
  }

  build() {
    if (this.showBreathingUI) {
      this.BreathingUI();
    } else {
      this.MonitoringUI();
    }
  }
}

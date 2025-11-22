import { StressDetector, StressState } from '../services/StressDetector';
import { BreathingGuide } from '../services/BreathingGuide';

@Entry
@Component
struct Index {
  @State heartRate: number = 0;
  @State state: StressState = 'NORMAL';
  @State isMonitoring: boolean = false;
  @State statusMessage: string = 'Tap Start to begin monitoring';

  // Colors for each state
  private getStateColor(): ResourceColor {
    switch (this.state) {
      case 'NORMAL': return '#4CAF50';    // Green
      case 'CHECKING': return '#FFC107';  // Yellow
      case 'EXERCISE': return '#2196F3';  // Blue
      case 'STRESS': return '#F44336';    // Red
      default: return '#9E9E9E';          // Grey
    }
  }

  // Status message for each state
  private getStatusMessage(): string {
    switch (this.state) {
      case 'NORMAL': return 'All good';
      case 'CHECKING': return 'Checking...';
      case 'EXERCISE': return 'Exercise detected';
      case 'STRESS': return 'Breathe...';
      default: return 'Ready';
    }
  }

  // Start background monitoring
  private startMonitoring(): void {
    StressDetector.setOnStateChange((newState: StressState, hr: number) => {
      this.state = newState;
      this.heartRate = hr;
      this.statusMessage = this.getStatusMessage();
    });

    StressDetector.start();
    StressDetector.startAccelerometer();
    this.isMonitoring = true;
    this.statusMessage = 'Monitoring...';
  }

  // Stop monitoring
  private stopMonitoring(): void {
    StressDetector.stop();
    StressDetector.stopAccelerometer();
    BreathingGuide.stop();
    this.isMonitoring = false;
    this.state = 'NORMAL';
    this.heartRate = 0;
    this.statusMessage = 'Tap Start to begin';
  }

  // Test button - force trigger stress for demo
  private async triggerTestStress(): Promise<void> {
    this.statusMessage = 'Testing...';
    await StressDetector.testStress();
  }

  build() {
    Column() {
      // Heart rate display - large and centered
      Text(this.heartRate > 0 ? `${this.heartRate}` : '--')
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getStateColor())

      Text('bpm')
        .fontSize(14)
        .fontColor('#888888')
        .margin({ bottom: 12 })

      // State indicator circle
      Circle()
        .width(12)
        .height(12)
        .fill(this.getStateColor())
        .margin({ bottom: 4 })

      // Status message
      Text(this.statusMessage)
        .fontSize(14)
        .fontColor(this.getStateColor())
        .margin({ bottom: 16 })

      // Buttons row
      Row() {
        // Start/Stop button
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

        // Test button - for demo
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
}

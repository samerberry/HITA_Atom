import { ImmersiveHeader } from '../../../common/components/ImmersiveHeader';
import { CompatibleSheetMaterial } from '../../../common/theme/CompatibleSheetMaterial';

export const COURSE_CONTROL_OVERFLOW: number = 16;

@Component
export struct CourseControlHost {
  @Prop barHeight: number = 44;
  @Prop materialEnabled: boolean = true;
  @Prop itemWeight: number = 0;
  @BuilderParam content: () => void;
  @State pressing: boolean = false;
  onPressingChanged: (pressing: boolean) => void = (_pressing: boolean) => {};

  aboutToDisappear(): void {
    this.setPressing(false);
  }

  private setPressing(pressing: boolean): void {
    if (this.pressing === pressing) return;
    this.pressing = pressing;
    this.onPressingChanged(pressing);
  }

  private observeTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.setPressing(true);
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.setPressing(false);
    }
  }

  build() {
    if (this.materialEnabled && CompatibleSheetMaterial.isEnabled()) {
      Stack({ alignContent: Alignment.TopStart }) {
        // Enlarge the native title region while keeping the control's layout bounds unchanged.
        Column() {
          ImmersiveHeader({ barHeight: this.barHeight + COURSE_CONTROL_OVERFLOW * 2 }) {
            Column() {
              this.content();
            }
            .width('100%')
            .height(this.barHeight + COURSE_CONTROL_OVERFLOW * 2)
            .padding(COURSE_CONTROL_OVERFLOW)
            .clip(false)
            .hitTestBehavior(HitTestMode.Transparent)
          }
        }
        .width('calc(100% + ' + (COURSE_CONTROL_OVERFLOW * 2).toString() + 'vp)')
        .height(this.barHeight + COURSE_CONTROL_OVERFLOW * 2)
        .position({ x: -COURSE_CONTROL_OVERFLOW, y: -COURSE_CONTROL_OVERFLOW })
        .clip(false)
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height(this.barHeight)
      .clip(false)
        .layoutWeight(this.itemWeight)
      .zIndex(this.pressing ? 3 : 1)
      .hitTestBehavior(HitTestMode.Transparent)
      .onTouch((event: TouchEvent) => this.observeTouch(event))
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        this.content();
      }
      .layoutWeight(this.itemWeight)
    }
  }
}

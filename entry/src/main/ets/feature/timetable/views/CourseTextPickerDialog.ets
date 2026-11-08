import { ImmersiveHeader } from '../../../common/components/ImmersiveHeader';
import { CompatibleMaterialModifier } from '../../../common/theme/CompatibleMaterialModifier';
import { CompatibleLightModifier } from '../../../common/theme/CompatibleLightModifier';

/** Retains the native wheel while making its material light follow the shared curve. */
@CustomDialog
export struct CourseTextPickerDialog {
  controller: CustomDialogController;
  options: TextPickerDialogOptionsExt = { range: [] };
  @State private selected: number = 0;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.selected = typeof this.options.selected === 'number' ? this.options.selected : 0;
  }

  private accept(): void {
    if (!this.active) return;
    const range: string[] = this.options.range as string[];
    if (this.selected < 0 || this.selected >= range.length) return;
    this.options.onAccept?.({ index: this.selected, value: range[this.selected] });
    this.controller.close();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  build() {
    Column({ space: 12 }) {
      TextPicker({ range: this.options.range, selected: this.selected })
        .width('100%')
        .height(216)
        .canLoop(this.options.canLoop === undefined ? true : this.options.canLoop)
        .onChange((_value: string | string[], index: number | number[]) => {
          if (typeof index === 'number') this.selected = index;
        })
      ImmersiveHeader({ barHeight: 44 }) {
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Capsule })
            .layoutWeight(1).height(44)
            .backgroundColor($r('app.color.hita_surface_soft'))
            .fontColor($r('app.color.hita_text_202b45'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_surface_soft')))
            .onClick(() => {
              this.options.onCancel?.();
              this.controller.close();
            })
          Button('确定', { type: ButtonType.Capsule })
            .layoutWeight(1).height(44)
            .backgroundColor($r('app.color.hita_primary_fill'))
            .fontColor(CompatibleMaterialModifier.foreground('#FFFFFF'))
            .attributeModifier(new CompatibleMaterialModifier($r('app.color.hita_primary_fill')))
            .onClick(() => this.accept())
        }.width('100%')
      }
    }
    .width('100%')
    .padding(20)
    .attributeModifier(new CompatibleLightModifier(24, true, true))
  }
}

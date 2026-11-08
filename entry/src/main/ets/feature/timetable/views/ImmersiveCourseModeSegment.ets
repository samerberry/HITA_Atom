import { ColorMetrics, LengthMetrics, SegmentButtonV2ItemOptions, SegmentButtonV2Items,
  TabSegmentButtonV2, uiMaterial } from '@kit.ArkUI';
import { Available } from '@kit.BasicServicesKit';
import { HeaderMaterial } from '../../../common/theme/ImmersiveHeaderMaterial';
import { CompatibleLightModifier } from '../../../common/theme/CompatibleLightModifier';

@Available({ minApiVersion: 'HarmonyOS 26.0.0' })
@Component
export struct ImmersiveCourseModeSegment {
  @Prop labels: string[] = [];
  @Prop selectedIndex: number = 0;
  onSelect: (index: number) => void = () => {};
  private items: SegmentButtonV2Items = new SegmentButtonV2Items([]);
  private material: uiMaterial.ImmersiveMaterial | undefined = HeaderMaterial.create();

  aboutToAppear(): void {
    this.items = new SegmentButtonV2Items(this.labels.map((label: string): SegmentButtonV2ItemOptions => {
      return { text: label, accessibilityText: label };
    }));
  }
  build() {
    TabSegmentButtonV2({
      items: this.items,
      selectedIndex: this.selectedIndex,
      $selectedIndex: (index: number) => this.onSelect(index),
      enableStateAnimation: true,
      backgroundSystemMaterial: this.material,
      buttonBackgroundColor: ColorMetrics.resourceColor(this.material === undefined ?
        $r('app.color.hita_control_eaf0f7') : Color.Transparent),
      buttonPadding: LengthMetrics.vp(4),
      buttonMinHeight: LengthMetrics.vp(44),
      buttonBorderRadius: LengthMetrics.vp(22),
      itemMinHeight: LengthMetrics.vp(36),
      itemBorderRadius: LengthMetrics.vp(18),
      itemSpace: LengthMetrics.vp(0),
      itemPadding: { top: LengthMetrics.vp(0), bottom: LengthMetrics.vp(0),
        start: LengthMetrics.vp(12), end: LengthMetrics.vp(12) },
      itemFontSize: LengthMetrics.fp(14),
      itemSelectedFontSize: LengthMetrics.fp(14),
      itemFontWeight: FontWeight.Regular,
      itemSelectedFontWeight: FontWeight.Medium,
      itemFontColor: ColorMetrics.resourceColor($r('sys.color.ohos_id_color_text_secondary')),
      itemSelectedFontColor: ColorMetrics.resourceColor($r('sys.color.ohos_id_color_text_primary')),
      itemSelectedBackgroundColor: ColorMetrics.resourceColor($r('app.color.hita_immersive_segment_selected')),
      itemShadow: { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
    })
      .width('100%')
      .clip(false)
      .attributeModifier(new CompatibleLightModifier());
  }
}

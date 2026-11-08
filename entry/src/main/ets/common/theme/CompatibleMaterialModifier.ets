import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { HeaderMaterial } from './ImmersiveHeaderMaterial';

export class CompatibleMaterialModifier implements AttributeModifier<CommonAttribute> {
  private fallbackColor: ResourceColor;
  private blueSurface: boolean;
  private enabled: boolean;
  private tint: ResourceColor | undefined;
  private shadow: boolean | undefined;

  constructor(fallbackColor: ResourceColor, blueSurface: boolean = false, enabled: boolean = true,
    tint: ResourceColor | undefined = undefined, shadow: boolean | undefined = undefined) {
    this.fallbackColor = fallbackColor;
    this.blueSurface = blueSurface;
    this.enabled = enabled;
    this.tint = tint;
    this.shadow = shadow;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (this.enabled) {
        HeaderMaterial.apply(instance, this.fallbackColor, this.blueSurface, this.tint, this.shadow);
      }
    }
  }

  static foreground(fallbackColor: ResourceColor): ResourceColor {
    return deviceInfo.apiAvailable('26.0.0') ? $r('sys.color.ohos_id_color_text_primary') : fallbackColor;
  }
}

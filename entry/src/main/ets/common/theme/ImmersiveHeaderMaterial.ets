import { uiMaterial } from '@kit.ArkUI';
import { Available, deviceInfo } from '@kit.BasicServicesKit';
import { CompatibleLightModifier } from './CompatibleLightModifier';

@Available({ minApiVersion: 'HarmonyOS 26.0.0' })
export class HeaderMaterial {
  static apply(instance: CommonAttribute, fallbackColor: ResourceColor, blueSurface: boolean,
    tint: ResourceColor | undefined = undefined, shadow: boolean | undefined = undefined): void {
    try {
      const material: uiMaterial.ImmersiveMaterial | undefined = HeaderMaterial.create(blueSurface, tint, shadow);
      if (material === undefined) {
        return;
      }
      // An opaque legacy fill would hide the material's blur and refraction.
      instance.backgroundColor(Color.Transparent);
      instance.systemMaterial(material);
      new CompatibleLightModifier().applyNormalAttribute(instance);
    } catch (e) {
      instance.backgroundColor(fallbackColor);
    }
  }

  static create(blueSurface: boolean = false,
    tint: ResourceColor | undefined = undefined, shadow: boolean | undefined = undefined): uiMaterial.ImmersiveMaterial | undefined {
    try {
      if (!uiMaterial.isImmersiveMaterialSupported()) {
        return undefined;
      }
      return new uiMaterial.ImmersiveMaterial({
        style: blueSurface ? uiMaterial.ImmersiveStyle.REGULAR : HeaderMaterial.controlStyle(),
        materialColor: blueSurface ?
          (tint === undefined ? $r('app.color.hita_immersive_hero_tint') : tint) : Color.Transparent,
        colorInvert: !blueSurface,
        applyShadow: shadow === undefined ? blueSurface : shadow,
        interactive: true,
        lightEffect: deviceInfo.apiAvailable('27.0.0') ? { color: Color.White } : null
      });
    } catch (e) {
      return undefined;
    }
  }

  private static controlStyle(): uiMaterial.ImmersiveStyle {
    try {
      if (uiMaterial.getGlobalMaterialLevel() === uiMaterial.MaterialLevel.EXQUISITE) {
        return uiMaterial.ImmersiveStyle.ULTRA_THIN;
      }
    } catch (e) {
      // Let the system retain its balanced or low-power rendering policy.
    }
    return uiMaterial.ImmersiveStyle.THIN;
  }
}

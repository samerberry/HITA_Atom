import { uiMaterial } from '@kit.ArkUI';
import { Available } from '@kit.BasicServicesKit';

@Available({ minApiVersion: 'HarmonyOS 26.0.0' })
export class SheetMaterial {
  static supported(): boolean {
    try {
      return uiMaterial.isImmersiveMaterialSupported();
    } catch (e) {
      return false;
    }
  }

  static options(options: SheetOptions, interactive: boolean = true): SheetOptions {
    try {
      const material: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THICK,
        colorInvert: false,
        interactive: interactive,
        lightEffect: null
      });
      // Callers pass fresh sheet options; retain their sizing and lifecycle callbacks.
      options.systemMaterial = material;
      options.backgroundColor = Color.Transparent;
      return options;
    } catch (e) {
      return options;
    }
  }
}

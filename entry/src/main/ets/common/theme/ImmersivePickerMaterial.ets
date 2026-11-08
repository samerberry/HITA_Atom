import { uiMaterial } from '@kit.ArkUI';
import { Available } from '@kit.BasicServicesKit';

@Available({ minApiVersion: 'HarmonyOS 26.0.0' })
export class PickerMaterial {
  static supported(): boolean {
    try {
      return uiMaterial.isImmersiveMaterialSupported();
    } catch (_) {
      return false;
    }
  }

  static create(): uiMaterial.ImmersiveMaterial | undefined {
    try {
      return new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THICK,
        colorInvert: false,
        interactive: true,
        lightEffect: null
      });
    } catch (_) {
      return undefined;
    }
  }

  static textOptions(options: TextPickerDialogOptionsExt): TextPickerDialogOptionsExt {
    const material: uiMaterial.ImmersiveMaterial | undefined = PickerMaterial.create();
    if (material !== undefined) {
      options.systemMaterial = material;
      options.backgroundColor = Color.Transparent;
    }
    return options;
  }
}

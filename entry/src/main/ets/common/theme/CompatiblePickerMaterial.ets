import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { PickerMaterial } from './ImmersivePickerMaterial';

export class CompatiblePickerMaterial {
  static isEnabled(): boolean {
    if (deviceInfo.apiAvailable('26.0.0') && !deviceInfo.apiAvailable('27.0.0')) {
      return PickerMaterial.supported();
    }
    return false;
  }

  static textOptions(options: TextPickerDialogOptionsExt, requested: boolean): TextPickerDialogOptionsExt {
    return requested && CompatiblePickerMaterial.isEnabled() ? PickerMaterial.textOptions(options) : options;
  }

  static dialogMaterial(requested: boolean): SystemUiMaterial | undefined {
    return requested && CompatiblePickerMaterial.isEnabled() ? PickerMaterial.create() : undefined;
  }
}

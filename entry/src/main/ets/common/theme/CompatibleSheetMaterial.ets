import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { SheetMaterial } from './ImmersiveSheetMaterial';

export class CompatibleSheetMaterial {
  static isEnabled(): boolean {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return !deviceInfo.apiAvailable('27.0.0') && SheetMaterial.supported();
    }
    return false;
  }

  static options(options: SheetOptions, requested: boolean = true, interactive: boolean = true): SheetOptions {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (requested && CompatibleSheetMaterial.isEnabled()) {
        return SheetMaterial.options(options, interactive);
      }
    }
    return options;
  }

  static bodyColor(fallback: ResourceColor): ResourceColor {
    return CompatibleSheetMaterial.isEnabled() ? Color.Transparent : fallback;
  }

  static cardColor(fallback: ResourceColor): ResourceColor {
    return CompatibleSheetMaterial.isEnabled() ? $r('app.color.hita_immersive_sheet_card') : fallback;
  }
}

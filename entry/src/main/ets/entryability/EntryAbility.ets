import { UIAbility, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NAV_BAR_INSET_KEY, NAV_BAR_INSET_FALLBACK,
  STATUS_BAR_INSET_KEY, STATUS_BAR_INSET_FALLBACK } from '../common/theme/StatusBarInset';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;
  private barUpdate: Promise<void> = Promise.resolve();
  private avoidAreaChanged = (area: window.AvoidAreaOptions): void => {
    if (area.type === window.AvoidAreaType.TYPE_SYSTEM ||
      area.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) this.captureNavigationInset();
  };

  onWindowStageCreate(stage: window.WindowStage): void {
    AppStorage.setOrCreate('atomicDarkMode', this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    AppStorage.setOrCreate('atomicActive', true);
    AppStorage.setOrCreate(NAV_BAR_INSET_KEY, NAV_BAR_INSET_FALLBACK);
    AppStorage.setOrCreate(STATUS_BAR_INSET_KEY, STATUS_BAR_INSET_FALLBACK);
    // The custom week header keeps the native capsule; bottom content avoids the live system inset.
    stage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(0, 'HitaAtomic', 'Load failed: %{public}d', error.code);
        return;
      }
      try {
        this.mainWindow = stage.getMainWindowSync();
        this.configureSystemBars();
        this.captureNavigationInset();
        this.mainWindow.on('avoidAreaChange', this.avoidAreaChanged);
      } catch (_) {
        hilog.warn(0, 'HitaAtomic', 'System inset unavailable; using safe fallback');
      }
    });
  }

  private configureSystemBars(): void {
    const target = this.mainWindow;
    if (target === undefined) return;
    const dark = AppStorage.get<boolean>('atomicDarkMode') ?? false;
    // Match the full app: extend the window itself under transparent system bars.
    this.barUpdate = this.barUpdate.then(async (): Promise<void> => {
      if (this.mainWindow !== target) return;
      await target.setWindowLayoutFullScreen(true);
      await target.setWindowBackgroundColor(dark ? '#101214' : '#F5F6F8');
      await target.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: dark ? '#E5E7EB' : '#182431',
        navigationBarColor: '#00000000',
        navigationBarContentColor: dark ? '#BCC3CF' : '#4E5C72'
      });
      if (this.mainWindow === target) this.captureNavigationInset();
    }).catch(() => {
      hilog.warn(0, 'HitaAtomic', 'Unable to configure immersive system bars');
    });
  }

  private captureNavigationInset(): void {
    const mainWindow = this.mainWindow;
    if (mainWindow === undefined) return;
    try {
      const system = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicator = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topInset = mainWindow.getUIContext().px2vp(system.topRect.height);
      AppStorage.setOrCreate(STATUS_BAR_INSET_KEY, Math.max(0, topInset));
      const inset = mainWindow.getUIContext().px2vp(Math.max(system.bottomRect.height, indicator.bottomRect.height));
      AppStorage.setOrCreate(NAV_BAR_INSET_KEY, Math.max(0, inset));
    } catch (_) {
      // Retain the last measured value while the window is being resized or recreated.
    }
  }

  onWindowStageDestroy(): void {
    try { this.mainWindow?.off('avoidAreaChange', this.avoidAreaChanged); } catch (_) {}
    this.mainWindow = undefined;
  }

  onConfigurationUpdate(configuration: Configuration): void {
    AppStorage.setOrCreate('atomicDarkMode', configuration.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.configureSystemBars();
  }

  onForeground(): void {
    this.configureSystemBars();
    this.captureNavigationInset();
    AppStorage.setOrCreate('atomicActive', true);
  }

  onBackground(): void { AppStorage.setOrCreate('atomicActive', false); }
}

/**
 * TimetableTheme.ets — 时间表标题/日期栏的预置字体色。
 */
export class TimetableTheme {
  static readonly AUTO_TEXT: string = 'auto';
  static readonly DEFAULT_TEXT: string = '#14213D';
  static readonly WHITE_TEXT: string = '#FFFFFF';
  /** 默认、白、红、橙、黄、绿、青、蓝、紫。 */
  static readonly PALETTE: string[] = [
    '#14213D', '#FFFFFF',
    '#E53935', '#FB8C00', '#F9A825', '#43A047', '#00ACC1', '#1E88E5', '#8E24AA'
  ];

  static resolveText(selected: string, dark: boolean, hasWallpaper: boolean,
    adaptiveColor: string = ''): string {
    if (selected === TimetableTheme.AUTO_TEXT) {
      return adaptiveColor || (dark ? '#ECEFF4' : TimetableTheme.DEFAULT_TEXT);
    }
    return selected;
  }
}

export class TimetableDisplayOptions {
  drawTimeLines: boolean = true;
  timeLineColor: string = '';
  eveningHint: boolean = true;
  wallpaperMask: number = 0;

  copy(): TimetableDisplayOptions {
    const result = new TimetableDisplayOptions();
    result.drawTimeLines = this.drawTimeLines;
    result.timeLineColor = this.timeLineColor;
    result.eveningHint = this.eveningHint;
    result.wallpaperMask = this.wallpaperMask;
    return result;
  }

  lineColor(dark: boolean): string {
    return this.timeLineColor || (dark ? '#3A414B' : '#D7DEE8');
  }

  static parse(raw: string): TimetableDisplayOptions {
    const result = new TimetableDisplayOptions();
    try {
      const value = JSON.parse(raw) as Record<string, Object>;
      if (value === null || typeof value !== 'object' || Array.isArray(value)) return result;
      if (typeof value['drawTimeLines'] === 'boolean') result.drawTimeLines = value['drawTimeLines'] as boolean;
      if (typeof value['eveningHint'] === 'boolean') result.eveningHint = value['eveningHint'] as boolean;
      const color = value['timeLineColor'];
      if (typeof color === 'string' && /^#[0-9a-fA-F]{6}$/.test(color)) result.timeLineColor = color.toUpperCase();
      const mask = value['wallpaperMask'];
      if (typeof mask === 'number' && Number.isFinite(mask)) result.wallpaperMask = Math.round(Math.max(0, Math.min(80, mask)));
    } catch (_) {
    }
    return result;
  }
}

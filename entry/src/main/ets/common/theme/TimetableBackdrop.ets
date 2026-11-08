export class TimetableBackdropColors {
  statusText: string;
  navigationText: string;
  titleText: string;
  dateText: string;
  timeText: string;
  line: string;
  minorLine: string;
  linePicker: string;
  todayMask: string;
  todayHeader: number;

  constructor(dark: boolean) {
    this.titleText = dark ? '#ECEFF4' : '#14213D';
    this.statusText = this.titleText;
    this.navigationText = dark ? '#BCC3CF' : '#4E5C72';
    this.dateText = this.titleText;
    this.timeText = this.titleText;
    this.line = dark ? '#3A414B' : '#D7DEE8';
    this.minorLine = dark ? '#262B32' : '#EEF2F6';
    this.linePicker = this.line;
    this.todayMask = '';
    this.todayHeader = 0;
    this.setToday(dark);
  }

  setToday(dark: boolean): void {
    const rgb = dark ? 0x85B8FF : 0x2E86E8;
    const alpha = dark ? 46 : 23;
    this.todayHeader = ((alpha << 24) | rgb) >>> 0;
    this.todayMask = timetableLineInk('#' + rgb.toString(16).padStart(6, '0'), alpha / 255);
  }
}

export function timetableLineInk(hex: string, alpha: number): string {
  const rgb = parseInt(hex.substring(1), 16);
  return 'rgba(' + ((rgb >> 16) & 255) + ',' + ((rgb >> 8) & 255) + ',' +
    (rgb & 255) + ',' + alpha + ')';
}

/** A small decoded image, reused when the mask, viewport or appearance changes. */
export class TimetableBackdropPixels {
  width: number;
  height: number;
  stride: number;
  rgba: Uint8Array;
  premultiplied: boolean;

  constructor(width: number, height: number, stride: number, rgba: Uint8Array, premultiplied: boolean) {
    this.width = width;
    this.height = height;
    this.stride = stride;
    this.rgba = rgba;
    this.premultiplied = premultiplied;
  }

  private brightness(viewW: number, viewH: number, left: number, top: number, right: number,
    bottom: number, dark: boolean, mask: number): number {
    const scale = Math.max(viewW / this.width, viewH / this.height);
    const cropX = (this.width - viewW / scale) / 2;
    const cropY = (this.height - viewH / scale) / 2;
    // Sample the visible ImageFit.Cover region, not the hidden edges of a wide photo.
    const x0 = Math.max(0, Math.floor(cropX + left / scale));
    const y0 = Math.max(0, Math.floor(cropY + top / scale));
    const x1 = Math.min(this.width, Math.max(x0 + 1, Math.ceil(cropX + right / scale)));
    const y1 = Math.min(this.height, Math.max(y0 + 1, Math.ceil(cropY + bottom / scale)));
    const base = dark ? [16, 18, 20] : [244, 247, 252];
    let total = 0;
    let count = 0;
    for (let y = y0; y < y1; y++) {
      for (let x = x0; x < x1; x++) {
        const i = y * this.stride + x * 4;
        if (i + 3 >= this.rgba.length) continue;
        const alpha = this.rgba[i + 3] / 255;
        const factor = this.premultiplied ? 1 : alpha;
        const r = this.rgba[i] * factor + base[0] * (1 - alpha);
        const g = this.rgba[i + 1] * factor + base[1] * (1 - alpha);
        const b = this.rgba[i + 2] * factor + base[2] * (1 - alpha);
        total += (0.299 * r + 0.587 * g + 0.114 * b) * (1 - mask / 100);
        count++;
      }
    }
    return count > 0 ? total / count : (dark ? 18 : 247);
  }

  colors(dark: boolean, maskDepth: number, width: number, height: number,
    chromeHeight: number, dateHeight: number, today: number,
    statusHeight: number = 24, navigationHeight: number = 24): TimetableBackdropColors {
    const colors = new TimetableBackdropColors(dark);
    if (this.width <= 0 || this.height <= 0 || this.stride < this.width * 4 ||
      this.rgba.length < this.stride * this.height) return colors;
    const w = Math.max(1, width);
    const h = Math.max(1, height);
    const mask = Math.max(0, Math.min(80, maskDepth));
    const header = Math.max(1, Math.min(h, chromeHeight));
    const dateTop = Math.max(0, header - dateHeight);
    const gutter = Math.min(48, w / 4);
    colors.statusText = this.brightness(w, h, 0, 0, w, Math.min(h, statusHeight), dark, mask) < 128 ?
      '#FFFFFF' : '#333333';
    colors.navigationText = this.brightness(w, h, 0, Math.max(0, h - navigationHeight), w, h, dark, mask) < 128 ?
      '#FFFFFF' : '#333333';
    colors.titleText = this.brightness(w, h, 0, 0, w, dateTop, dark, mask) < 128 ? '#FFFFFF' : '#333333';
    colors.dateText = this.brightness(w, h, 0, dateTop, w, header, dark, mask) < 128 ? '#FFFFFF' : '#333333';
    colors.timeText = this.brightness(w, h, 0, header, gutter, h, dark, mask) < 128 ? '#FFFFFF' : '#333333';
    const gridDark = this.brightness(w, h, gutter, header, w, h, dark, mask) < 128;
    colors.linePicker = gridDark ? '#FFFFFF' : '#333333';
    colors.line = timetableLineInk(colors.linePicker, gridDark ? 0.16 : 0.14);
    colors.minorLine = timetableLineInk(colors.linePicker, gridDark ? 0.07 : 0.06);
    const day = Math.max(0, Math.min(6, today - 1));
    const columnWidth = (w - gutter) / 7;
    const left = gutter + day * columnWidth;
    colors.setToday(this.brightness(w, h, left, dateTop, left + columnWidth, h, dark, mask) < 128);
    return colors;
  }
}

export class CourseColorModel {
  hue: number = 0;
  saturation: number = 0;
  brightness: number = 0;

  static fromColor(color: number): CourseColorModel {
    const r: number = ((color >>> 16) & 255) / 255;
    const g: number = ((color >>> 8) & 255) / 255;
    const b: number = (color & 255) / 255;
    const max: number = Math.max(r, g, b);
    const min: number = Math.min(r, g, b);
    const delta: number = max - min;
    const result: CourseColorModel = new CourseColorModel();
    result.brightness = max;
    result.saturation = max === 0 ? 0 : delta / max;
    if (delta > 0) {
      if (max === r) { result.hue = 60 * (((g - b) / delta) % 6); }
      else if (max === g) { result.hue = 60 * ((b - r) / delta + 2); }
      else { result.hue = 60 * ((r - g) / delta + 4); }
      result.hue = (result.hue + 360) % 360;
    }
    return result;
  }

  static toColor(hue: number, saturation: number, brightness: number): number {
    const h: number = ((hue % 360) + 360) % 360 / 60;
    const s: number = Math.max(0, Math.min(1, saturation));
    const v: number = Math.max(0, Math.min(1, brightness));
    const c: number = v * s;
    const x: number = c * (1 - Math.abs(h % 2 - 1));
    const m: number = v - c;
    let r: number = 0;
    let g: number = 0;
    let b: number = 0;
    if (h < 1) { r = c; g = x; }
    else if (h < 2) { r = x; g = c; }
    else if (h < 3) { g = c; b = x; }
    else if (h < 4) { g = x; b = c; }
    else if (h < 5) { r = x; b = c; }
    else { r = c; b = x; }
    return (0xFF000000 | (Math.round((r + m) * 255) << 16) |
      (Math.round((g + m) * 255) << 8) | Math.round((b + m) * 255)) >>> 0;
  }
}

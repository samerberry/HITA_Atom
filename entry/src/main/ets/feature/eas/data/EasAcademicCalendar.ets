import { DAY_MILLIS, EasTimetable } from '../../../common/model/timetable/TimetableModels';
import { EasTermItem } from '../model/EasModels';
import { EasLegacyCourseCatalogParser } from './EasLegacyCourseCatalogParser';

/** Only explicit first-teaching-week dates are accepted; never infer from a month. */
export class EasAcademicCalendar {
  static parseLegacyHtml(html: string, term: EasTermItem): number | undefined {
    const fields: Map<string, string> | undefined =
      EasLegacyCourseCatalogParser.parseFormFields(html, 'xnxq');
    const selected: string | undefined = fields?.get('xnxq');
    if (selected !== undefined && selected.length > 0 && selected !== term.getCode()) {
      return undefined;
    }
    const source: string = html.replace(/<!--[\s\S]*?-->/g, '')
      .replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, '');
    // Match leaf rows, including calendars nested inside a layout table.
    const rows: RegExp = /<tr\b[^>]*>((?:(?!<tr\b)[\s\S])*?)<\/tr>/gi;
    let row: RegExpExecArray | null = rows.exec(source);
    let weekColumn: number = -1;
    let mondayColumn: number = -1;
    let monthContext: number[] = [];
    let spans: number[] = [];
    let previousCells: string[] = [];
    let previousEnd: number = 0;
    const dates: Set<number> = new Set<number>();
    while (row !== null) {
      if (/<\/?table\b/i.test(source.substring(previousEnd, row.index))) {
        spans = [];
        previousCells = [];
        weekColumn = -1;
        mondayColumn = -1;
      }
      const cells: string[] = [];
      const pattern: RegExp = /<(?:td|th)\b([^>]*)>([\s\S]*?)<\/(?:td|th)>/gi;
      let cell: RegExpExecArray | null = pattern.exec(row[1]);
      let column: number = 0;
      while (cell !== null) {
        while ((spans[column] || 0) > 0) {
          cells[column] = previousCells[column];
          spans[column]--;
          column++;
        }
        const colspan: number = EasAcademicCalendar.span(cell[1], 'colspan');
        const rowspan: number = EasAcademicCalendar.span(cell[1], 'rowspan');
        for (let i: number = 0; i < colspan; i++) {
          cells[column] = EasAcademicCalendar.text(cell[2]);
          spans[column] = rowspan - 1;
          column++;
        }
        cell = pattern.exec(row[1]);
      }
      const headerWeek: number = cells.findIndex((value: string): boolean => value === '周次');
      const headerMonday: number = cells.findIndex((value: string): boolean =>
        /^(星期一|周一|一|Monday)$/i.test(value));
      if (headerWeek >= 0 && headerMonday >= 0) {
        weekColumn = headerWeek;
        mondayColumn = headerMonday;
        monthContext = EasAcademicCalendar.lastYearMonth(
          EasAcademicCalendar.text(source.substring(0, row.index)));
        spans = [];
      } else if (weekColumn >= 0 && mondayColumn < cells.length &&
        /^(第)?(0?1|一)(周)?$/.test(cells[weekColumn] || '')) {
        const date: number | undefined = EasAcademicCalendar.calendarMonday(
          cells.slice(mondayColumn, mondayColumn + 7), monthContext);
        if (date !== undefined && EasAcademicCalendar.matchesTerm(date, term)) {
          dates.add(date);
        }
      }
      previousCells = cells;
      previousEnd = rows.lastIndex;
      row = rows.exec(source);
    }
    return dates.size === 1 ? Array.from(dates)[0] : undefined;
  }

  static parseShenzhenJson(body: string, term: EasTermItem): number | undefined {
    let root: Object;
    try {
      root = JSON.parse(body) as Object;
    } catch (e) {
      return undefined;
    }
    const dates: Set<number> = new Set<number>();
    EasAcademicCalendar.collectWeekDates(root, term, dates);
    return dates.size === 1 ? Array.from(dates)[0] : undefined;
  }

  private static collectWeekDates(value: Object, term: EasTermItem, dates: Set<number>): void {
    if (value === null || typeof value !== 'object') {
      return;
    }
    if (Array.isArray(value)) {
      const items: Object[] = value as Object[];
      for (let i: number = 0; i < items.length; i++) {
        EasAcademicCalendar.collectWeekDates(items[i], term, dates);
      }
      return;
    }
    const row: Record<string, Object> = value as Record<string, Object>;
    const code: string = EasAcademicCalendar.field(row, ['code']);
    if (code.length > 0 && code !== '0' && code !== '200') {
      return;
    }
    const year: string = EasAcademicCalendar.field(row, ['XN', 'xn']);
    const semester: string = EasAcademicCalendar.field(row, ['XQ', 'xq']);
    const combined: string = EasAcademicCalendar.field(row, ['XNXQ', 'xnxq']);
    const week: string = EasAcademicCalendar.field(row, ['ZC', 'zc', 'DJZ', 'djz']);
    if ((year.length > 0 && year !== term.yearCode) ||
      (semester.length > 0 && Number(semester) !== Number(term.termCode)) ||
      (combined.length > 0 && combined !== term.getCode() &&
        combined !== term.yearCode + '-' + term.termCode) ||
      (week.length > 0 && Number(week) !== 1)) {
      return;
    }
    const date: number | undefined = EasAcademicCalendar.date(
      EasAcademicCalendar.field(row, ['RQ', 'rq', 'DQRQ', 'dqrq', 'RQ1', 'rq1', 'KSRQ', 'ksrq']));
    if (date !== undefined) {
      const monday: number = EasTimetable.mondayMsOf(date);
      if (EasAcademicCalendar.matchesTerm(monday, term)) {
        dates.add(monday);
      }
      return;
    }
    const keys: string[] = ['content', 'data', 'list', 'rows', 'result', 'rqList'];
    for (let i: number = 0; i < keys.length; i++) {
      if (row[keys[i]] !== undefined) {
        EasAcademicCalendar.collectWeekDates(row[keys[i]], term, dates);
      }
    }
  }

  private static calendarMonday(cells: string[], context: number[]): number | undefined {
    if (cells.length === 0) {
      return undefined;
    }
    const full: number | undefined = EasAcademicCalendar.date(cells[0]);
    if (full !== undefined) {
      return new Date(full).getDay() === 1 ? full : undefined;
    }
    if (context.length !== 2) {
      return undefined;
    }
    const monthDay: RegExpExecArray | null = /^(\d{1,2})月(\d{1,2})日?$/.exec(cells[0]);
    if (monthDay !== null) {
      const month: number = Number(monthDay[1]);
      const year: number = context[0] + (context[1] === 1 && month === 12 ? -1 :
        context[1] === 12 && month === 1 ? 1 : 0);
      const date: number | undefined = EasAcademicCalendar.makeDate(year, month, Number(monthDay[2]));
      return date !== undefined && new Date(date).getDay() === 1 ? date : undefined;
    }
    const days: number[] = cells.map((text: string): number =>
      text.length === 0 ? 0 : /^(?:0?[1-9]|[12]\d|3[01])日?$/.test(text) ?
        Number(text.replace('日', '')) : -1);
    if (days.length !== 7 || days.some((day: number): boolean => day < 0 || day > 31)) {
      return undefined;
    }
    // Monthly EAS tables leave adjacent-month days blank. Anchor on a visible
    // weekday, and accept blanks only where that week really leaves the month.
    if (days.some((day: number): boolean => day === 0)) {
      const anchorIndex: number = days.findIndex((day: number): boolean => day > 0);
      if (anchorIndex < 0) {
        return undefined;
      }
      const anchor: number | undefined = EasAcademicCalendar.makeDate(
        context[0], context[1], days[anchorIndex]);
      if (anchor === undefined || EasTimetable.dowOfMs(anchor) !== anchorIndex + 1) {
        return undefined;
      }
      const monday: number = EasTimetable.mondayMsOf(anchor);
      const valid: boolean = days.every((day: number, index: number): boolean => {
        const expected: Date = new Date(monday + index * DAY_MILLIS);
        const inMonth: boolean = expected.getFullYear() === context[0] &&
          expected.getMonth() + 1 === context[1];
        return day === 0 ? !inMonth : inMonth && expected.getDate() === day;
      });
      return valid ? monday : undefined;
    }
    const crossesMonth: boolean = days.some((day: number, index: number): boolean =>
      index > 0 && day < days[index - 1]);
    const offsets: number[] = crossesMonth ? [0, -1, 1] : [0];
    for (let i: number = 0; i < offsets.length; i++) {
      const month: Date = new Date(context[0], context[1] - 1 + offsets[i], 1);
      const date: number | undefined = EasAcademicCalendar.makeDate(
        month.getFullYear(), month.getMonth() + 1, days[0]);
      if (date !== undefined && new Date(date).getDay() === 1 &&
        days.every((day: number, index: number): boolean => new Date(date + index * DAY_MILLIS).getDate() === day)) {
        return date;
      }
    }
    return undefined;
  }

  private static date(raw: string): number | undefined {
    // Timestamp responses use instants; campus calendar days are in UTC+8.
    if (/^\d{10}(?:\d{3})?$/.test(raw) ||
      /^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:?\d{2})$/i.test(raw)) {
      const parts: RegExpExecArray | null = /^(\d{4})-(\d{2})-(\d{2})T/.exec(raw);
      if (parts !== null && EasAcademicCalendar.makeDate(
        Number(parts[1]), Number(parts[2]), Number(parts[3])) === undefined) {
        return undefined;
      }
      const instant: number = /^\d+$/.test(raw) ?
        Number(raw) * (raw.length === 10 ? 1000 : 1) : new Date(raw).getTime();
      if (!Number.isFinite(instant)) {
        return undefined;
      }
      const campusDate: Date = new Date(instant + 8 * 60 * 60 * 1000);
      return EasAcademicCalendar.makeDate(campusDate.getUTCFullYear(),
        campusDate.getUTCMonth() + 1, campusDate.getUTCDate());
    }
    const match: RegExpExecArray | null =
      /^(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})(?:日)?(?:$|[T\s])/.exec(raw.trim());
    return match === null ? undefined :
      EasAcademicCalendar.makeDate(Number(match[1]), Number(match[2]), Number(match[3]));
  }

  private static makeDate(year: number, month: number, day: number): number | undefined {
    const date: Date = new Date(year, month - 1, day, 0, 0, 0, 0);
    return year >= 2000 && year <= 2100 && date.getFullYear() === year &&
      date.getMonth() === month - 1 && date.getDate() === day ? date.getTime() : undefined;
  }

  private static matchesTerm(date: number, term: EasTermItem): boolean {
    const years: RegExpExecArray | null = /^(\d{4})(?:-(\d{4}))?$/.exec(term.yearCode);
    if (years === null) {
      return false;
    }
    const startYear: number = Number(years[1]);
    const endYear: number = years[2] === undefined ? startYear : Number(years[2]);
    const d: Date = new Date(date);
    const semester: number = Number(term.termCode);
    const autumn: boolean = /秋/.test(term.termName) ||
      (!/春|夏|冬|寒/.test(term.termName) && semester === 1);
    if (autumn) {
      return d.getFullYear() === startYear && d.getMonth() >= 6 && d.getMonth() <= 10;
    }
    const spring: boolean = /春/.test(term.termName) ||
      (!/秋|夏|冬|寒/.test(term.termName) && semester === 2);
    const summer: boolean = /夏/.test(term.termName) ||
      (!/秋|春|冬|寒/.test(term.termName) && semester === 3);
    if (spring) {
      return d.getFullYear() === endYear && d.getMonth() <= 4;
    }
    if (summer) {
      return d.getFullYear() === endYear && d.getMonth() >= 4 && d.getMonth() <= 8;
    }
    return d.getFullYear() === endYear ||
      (d.getFullYear() === endYear - 1 && d.getMonth() === 11);
  }

  private static lastYearMonth(text: string): number[] {
    const pattern: RegExp = /(\d{4})[年/.-](\d{1,2})(?:月|(?!\d))/g;
    let match: RegExpExecArray | null = pattern.exec(text);
    let result: number[] = [];
    while (match !== null) {
      if (Number(match[2]) >= 1 && Number(match[2]) <= 12) {
        result = [Number(match[1]), Number(match[2])];
      }
      match = pattern.exec(text);
    }
    return result;
  }

  private static field(row: Record<string, Object>, keys: string[]): string {
    for (let i: number = 0; i < keys.length; i++) {
      const value: Object | undefined = row[keys[i]];
      if (typeof value === 'string' || typeof value === 'number') {
        const text: string = String(value).trim();
        if (text.length > 0 && text.toLowerCase() !== 'null') {
          return text;
        }
      }
    }
    return '';
  }

  private static text(html: string): string {
    return html.replace(/<[^>]+>/g, ' ').replace(/&nbsp;|&#160;/gi, ' ')
      .replace(/&#(\d+);/g, (all: string, code: string): string => String.fromCharCode(Number(code)))
      .replace(/\s+/g, '').trim();
  }

  private static span(attrs: string, name: string): number {
    const match: RegExpExecArray | null = new RegExp('\\b' + name + '\\s*=\\s*["\']?(\\d+)', 'i').exec(attrs);
    return match === null ? 1 : Math.min(40, Math.max(1, Number(match[1])));
  }
}

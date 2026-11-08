import { EasEventItem, EasTimetable } from '../../common/model/timetable/TimetableModels';

/** Dates are anchored to the timetable's first Monday, not the current calendar week. */
export class CourseDateSelection {
  static weekCount(timetable: EasTimetable): number {
    if (!Number.isFinite(timetable.startTime) || !Number.isFinite(timetable.endTime) ||
      timetable.startTime <= 0 || timetable.endTime <= timetable.startTime) {
      return 0;
    }
    return Math.ceil((timetable.endTime - timetable.startTime) / (7 * 86400000));
  }

  /** Only the old importer used exactly 25 weeks ending at next Monday midnight. */
  static repairedImportedEnd(timetable: EasTimetable, events: EasEventItem[]): number {
    if (timetable.code.length === 0 || timetable.endTime !== timetable.startTime + 25 * 7 * 86400000) {
      return timetable.endTime;
    }
    let lastEnd: number = 0;
    for (const event of events) {
      if (event.timetableId === timetable.id && Number.isFinite(event.to) &&
        event.from >= timetable.startTime && event.to > event.from) lastEnd = Math.max(lastEnd, event.to);
    }
    return lastEnd > 0 ? CourseDateSelection.weekEnd(lastEnd) : timetable.endTime;
  }

  static numbers(count: number): number[] {
    const values: number[] = [];
    for (let i: number = 1; i <= count; i++) values.push(i);
    return values;
  }

  static toggle(values: number[], value: number, selected: boolean): number[] {
    const next: number[] = values.filter((item: number): boolean => item !== value);
    if (selected) next.push(value);
    return next.sort((a: number, b: number): number => a - b);
  }

  static weekEnd(timestamp: number): number {
    const end: Date = new Date(EasTimetable.mondayMsOf(timestamp));
    end.setDate(end.getDate() + 7);
    return end.getTime() - 1;
  }

  static weeklyDates(timetable: EasTimetable, weeks: number[], weekdays: number[],
    availableWeeks: number = CourseDateSelection.weekCount(timetable)): number[] {
    const count: number = CourseDateSelection.weekCount(timetable);
    if (!Number.isInteger(availableWeeks) || availableWeeks < count) throw new Error('教学周范围无效');
    if (count === 0) throw new Error('课表起止日期无效，请先在课表管理中设置');
    if (weeks.length === 0) throw new Error('请至少选择一个教学周');
    if (weekdays.length === 0) throw new Error('请至少选择一个星期几');
    const dates: number[] = [];
    const seen: Set<number> = new Set<number>();
    for (const week of weeks) {
      if (!Number.isInteger(week) || week < 1 || week > availableWeeks) throw new Error('所选教学周超出课表范围');
      for (const weekday of weekdays) {
        if (!Number.isInteger(weekday) || weekday < 1 || weekday > 7) throw new Error('星期选择无效');
        const date: Date = new Date(EasTimetable.mondayMsOf(timetable.startTime));
        date.setDate(date.getDate() + (week - 1) * 7 + weekday - 1);
        const value: number = date.getTime();

        if (!seen.has(value)) {
          dates.push(value);
          seen.add(value);
        }
      }
    }
    return dates.sort((a: number, b: number): number => a - b);
  }
}
